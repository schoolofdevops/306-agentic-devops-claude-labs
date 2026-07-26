#!/usr/bin/env bash
# change-gate.sh — deterministic PreToolUse gate for Bash commands.
#
# Claude Code invokes this before a Bash tool call, passing the hook event as
# JSON on stdin. The gate inspects the proposed command and DENIES the ones the
# environment contract says must never run from an agent identity:
#
#   1. terraform apply on production   -> route through GitOps, never apply
#   2. kubectl delete namespace <prot> -> protected namespace, never delete
#   3. kubectl ... --all-namespaces/-A -> wildcard target, blast radius too wide
#   4. commands that print secrets      -> data-leakage risk
#   5. docker push                      -> images ship through CI, not the agent
#
# Fail-closed contract: this script exits 0 ONLY when it has positively decided
# to allow. Any internal error (missing jq, unreadable input) exits non-zero,
# which Claude Code treats as a block. A gate that cannot evaluate a command
# must not let it through.
#
# Deny protocol: print a JSON permissionDecision=deny object on stdout AND exit 2.
# The stdout JSON is the structured decision Claude Code reads; exit 2 is the
# belt-and-suspenders signal for older/stricter hook handling. The `reason`
# string is shown to the agent so it can correct course.

set -euo pipefail

PROTECTED_NAMESPACES="${PROTECTED_NAMESPACES:-production prod northstar kube-system argocd}"

fail_closed() {
  # An internal problem the gate cannot reason about. Block, do not allow.
  echo "change-gate: internal error: $1" >&2
  exit 1
}

deny() {
  local reason="$1"
  # Structured decision for Claude Code's permission engine...
  jq -cn --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  # ...and the exit-2 signal + human-readable reason on stderr.
  echo "DENIED by change-gate: $reason" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail_closed "jq is required to evaluate the gate"

# Read the whole hook event from stdin. If nothing arrives, fail closed.
INPUT="$(cat)"
[[ -n "$INPUT" ]] || fail_closed "empty hook input on stdin"

TOOL="$(echo "$INPUT" | jq -r '.tool_name // empty')"
CMD="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"

# Only Bash commands are in scope. Anything else is allowed by this gate.
[[ "$TOOL" == "Bash" ]] || exit 0
[[ -n "$CMD" ]] || exit 0

# Normalize whitespace for matching (collapse runs of spaces/tabs/newlines).
NORM="$(printf '%s' "$CMD" | tr '\n\t' '  ' | tr -s ' ')"

# --- Rule 1: terraform apply against production ------------------------------
# Block a real apply (terraform apply / terraform -chdir=... apply) whenever the
# command or its target mentions production. `terraform plan` is untouched.
if echo "$NORM" | grep -Eq '(^|[^a-z])terraform([[:space:]]+-[^[:space:]]+)*[[:space:]]+apply'; then
  if echo "$NORM" | grep -Eqi 'prod|production'; then
    deny "terraform apply on production is blocked — production infrastructure changes must go through GitOps (branch -> PR -> approval -> reconciler apply), never a direct agent apply."
  fi
fi

# --- Rule 2: deleting a protected namespace ---------------------------------
if echo "$NORM" | grep -Eq 'kubectl[[:space:]].*delete[[:space:]].*(namespace|ns)([[:space:]]|/|=)'; then
  for ns in $PROTECTED_NAMESPACES; do
    if echo "$NORM" | grep -Eq "(^|[[:space:]=/])${ns}([[:space:]]|$)"; then
      deny "deleting the protected namespace '${ns}' is blocked — protected namespaces are never deleted from an agent identity. If this is intentional, it is a human, out-of-band operation."
    fi
  done
fi

# --- Rule 3: wildcard / all-namespaces target -------------------------------
# A kubectl command that fans out across every namespace has an unbounded blast
# radius. Read verbs (get/describe/logs) are fine; anything mutating is not.
if echo "$NORM" | grep -Eq 'kubectl[[:space:]]'; then
  if echo "$NORM" | grep -Eq '(--all-namespaces|[[:space:]]-A([[:space:]]|$)|--all([[:space:]]|$))'; then
    if echo "$NORM" | grep -Eq 'kubectl[[:space:]].*(delete|apply|scale|patch|edit|replace|rollout|drain|cordon)'; then
      deny "a mutating kubectl command targeting all namespaces (-A / --all-namespaces / --all) is blocked — the blast radius is unbounded. Target one explicit namespace and resource."
    fi
  fi
fi

# --- Rule 4: commands that would print secrets ------------------------------
# Catch the common ways an agent leaks credentials into its own transcript:
# dumping a Secret's data, printing a decoded token, catting a credentials file,
# or echoing the environment. These put plaintext secrets in the context window.
if echo "$NORM" | grep -Eq 'kubectl[[:space:]].*get[[:space:]]+secret'; then
  if echo "$NORM" | grep -Eqi '(-o[[:space:]]*(yaml|json)|jsonpath|--output|base64[[:space:]]+(-d|--decode|-D))'; then
    deny "printing Secret data is blocked — reading a Secret's decoded contents leaks credentials into the agent transcript. Reference the secret by name; never render its value."
  fi
fi
if echo "$NORM" | grep -Eqi '(cat|less|more|head|tail)[[:space:]].*(\.env|credentials|id_rsa|\.pem|\.key|secrets?\.(ya?ml|json|txt))([[:space:]]|$)'; then
  deny "reading a credentials/secret file is blocked — its contents would land in the agent transcript. Keep secrets out of the context window."
fi
if echo "$NORM" | grep -Eq '(^|[;&|][[:space:]]*)(env|printenv|set)([[:space:]]|$)' \
   && echo "$NORM" | grep -Eqi '(secret|token|password|passwd|key|credential)'; then
  deny "dumping the environment where it may expose secrets is blocked — printenv/env can spill tokens and passwords into the transcript."
fi

# --- Rule 5: docker push -----------------------------------------------------
if echo "$NORM" | grep -Eq '(^|[^a-z])docker[[:space:]]+(image[[:space:]]+)?push([[:space:]]|$)'; then
  deny "docker push is blocked — images are built and published by the CI pipeline, not from an agent identity. Push code to a branch and let CI build and publish the image."
fi

# Nothing matched. The command is allowed by the gate.
exit 0

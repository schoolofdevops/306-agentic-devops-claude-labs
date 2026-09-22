#!/usr/bin/env bash
# release-gate-secops.sh — deterministic PreToolUse gate for the SecOps release
# decision (M15/M8: detection is deterministic and belongs in a gate;
# prioritisation is judgement and must be evidenced upstream of this script).
#
# Claude Code invokes this before a Bash tool call, passing the hook event as
# JSON on stdin. The gate inspects the proposed command for a deploy/apply
# verb, and — only when one is present — reads
# agentops/secops/verdict.json (written by security-reviewer after synthesis).
# If it records an unresolved critical, DENY. Otherwise, ALLOW.
#
# This hook does not rank, triage, or judge reachability — that authority sits
# with security-reviewer (see .claude/skills/secfinding-style). It only reads
# the verdict the reviewer already signed and mechanizes the one part of the
# decision that should never be optional: don't ship while a critical stands.
#
# Fail-closed contract: exits 0 ONLY when it has positively decided to allow.
# Missing jq, unreadable verdict file, or malformed JSON all block — a gate
# that cannot evaluate the verdict must not let a deploy through silently.
#
# Deny protocol: print a JSON permissionDecision=deny object on stdout AND
# exit 2, matching change-gate.sh's contract.

set -euo pipefail

VERDICT_FILE="${SECOPS_VERDICT_FILE:-agentops/secops/verdict.json}"

fail_closed() {
  echo "release-gate-secops: internal error: $1" >&2
  exit 1
}

deny() {
  local reason="$1"
  jq -cn --arg r "$reason" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  echo "DENIED by release-gate-secops: $reason" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || fail_closed "jq is required to evaluate the gate"

INPUT="$(cat)"
[[ -n "$INPUT" ]] || fail_closed "empty hook input on stdin"

TOOL="$(echo "$INPUT" | jq -r '.tool_name // empty')"
CMD="$(echo "$INPUT" | jq -r '.tool_input.command // empty')"

# Only Bash commands are in scope. Anything else is allowed by this gate.
[[ "$TOOL" == "Bash" ]] || exit 0
[[ -n "$CMD" ]] || exit 0

NORM="$(printf '%s' "$CMD" | tr '\n\t' '  ' | tr -s ' ')"

# Only deploy/apply-shaped commands are in scope for this gate. Everything
# else (reads, scans, triage) is allowed regardless of verdict state.
case "$NORM" in
  *"kubectl"*" apply "*|*"kubectl"*" rollout "*|*"helm"*" upgrade "*|*"helm"*" install "*|*"terraform"*" apply "*|*deploy*)
    ;;
  *) exit 0 ;;
esac

# No verdict on disk at all: fail closed. A deploy attempted before any
# security review has run is exactly the case this gate must not wave through.
if [[ ! -f "$VERDICT_FILE" ]]; then
  deny "no security verdict found at $VERDICT_FILE — run secops-triage and get a security-reviewer verdict before deploying"
fi

VERDICT_JSON="$(cat "$VERDICT_FILE" 2>/dev/null || true)"
if ! echo "$VERDICT_JSON" | jq -e . >/dev/null 2>&1; then
  fail_closed "verdict file at $VERDICT_FILE is not valid JSON"
fi

UNRESOLVED_CRITICAL="$(echo "$VERDICT_JSON" | jq -r '
  [.findings[]? | select((.rank == 1 or (.severity_class // "") == "critical") and ((.status // "open") != "resolved"))] | length
')"

if [[ "$UNRESOLVED_CRITICAL" -gt 0 ]]; then
  deny "verdict at $VERDICT_FILE records $UNRESOLVED_CRITICAL unresolved critical finding(s) — release blocked until security-reviewer marks them resolved"
fi

exit 0

#!/usr/bin/env bash
# env-check.sh — fail-closed environment / target mismatch check.
#
# The change gate (scripts/hooks/change-gate.sh) blocks dangerous COMMANDS. This
# script answers a different question: is the environment you THINK you are in
# the one you are ACTUALLY pointed at? Most production incidents from agent
# sessions are not exotic — they are a correct command run against the wrong
# target because the operator believed they were in staging.
#
# It reads the canonical bundles from contracts/environment-contract.yaml and
# checks three things against the DECLARED environment:
#
#   1. context match  — the effective kube-context equals the bundle's context
#   2. identity match — the effective kubeconfig is the bundle's identity
#   3. action policy  — the requested action (apply/delete) is permitted by the
#                        bundle's allow_apply / allow_delete booleans
#
# Fail-closed contract: the script exits 0 ONLY when every check it can evaluate
# passes AND the requested action is permitted. Unknown environment, unreadable
# contract, missing bundle field, or a context it cannot determine => non-zero.
# "I could not verify" is treated exactly like "it does not match."
#
# Usage:
#   scripts/env-check.sh <environment> [action]
#     environment : dev | staging | production   (or $NORTHSTAR_ENV)
#     action      : apply | delete | read (default: read)
#
# The effective kube-context is read from $KUBE_CONTEXT if set (lets you run the
# check without a live cluster), else from `kubectl config current-context`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONTRACT="$REPO_ROOT/contracts/environment-contract.yaml"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

block() { echo -e "${RED}BLOCKED (env-check):${NC} $1" >&2; exit 1; }
ok()    { echo -e "${GREEN}OK (env-check):${NC} $1"; }

ENV_NAME="${1:-${NORTHSTAR_ENV:-}}"
ACTION="${2:-read}"

[[ -n "$ENV_NAME" ]] || block "no environment declared. Pass one (dev|staging|production) or set \$NORTHSTAR_ENV. Refusing to guess."
[[ -f "$CONTRACT" ]] || block "environment contract not found at $CONTRACT — cannot verify the target, so the operation is blocked."

# Pull the bundle's fields with pyyaml. A missing bundle or missing field prints
# nothing on that line; we treat empty as unverifiable and fail closed below.
read -r B_CONTEXT B_IDENTITY B_APPLY B_DELETE B_APPROVAL < <(
  ENV_NAME="$ENV_NAME" python3 - "$CONTRACT" <<'PY'
import os, sys, yaml
env = os.environ["ENV_NAME"]
try:
    with open(sys.argv[1]) as f:
        data = yaml.safe_load(f) or {}
except Exception as e:
    print("__ERROR__"); sys.exit(0)
b = (data.get("bundles") or {}).get(env)
if not b:
    print("__NOBUNDLE__"); sys.exit(0)
def s(v):
    if v is None: return "__MISSING__"
    if isinstance(v, bool): return "true" if v else "false"
    return str(v)
print(s(b.get("kube_context")), s(b.get("identity")),
      s(b.get("allow_apply")), s(b.get("allow_delete")), s(b.get("require_approval")))
PY
)

[[ "$B_CONTEXT" != "__ERROR__" ]]    || block "environment contract is unreadable/invalid YAML — cannot verify target. Blocked."
[[ "$B_CONTEXT" != "__NOBUNDLE__" ]] || block "no bundle named '$ENV_NAME' in the environment contract. Known targets are the bundles you defined. Blocked."
for f in "$B_CONTEXT" "$B_IDENTITY" "$B_APPLY" "$B_DELETE"; do
  [[ "$f" != "__MISSING__" && -n "$f" ]] || block "bundle '$ENV_NAME' is missing a required field (context/identity/allow_apply/allow_delete). An incomplete contract cannot certify the target. Blocked."
done

# --- Determine the effective kube-context -----------------------------------
if [[ -n "${KUBE_CONTEXT:-}" ]]; then
  EFFECTIVE_CONTEXT="$KUBE_CONTEXT"
elif command -v kubectl >/dev/null 2>&1 && EFFECTIVE_CONTEXT="$(kubectl config current-context 2>/dev/null)" && [[ -n "$EFFECTIVE_CONTEXT" ]]; then
  :
else
  block "could not determine the effective kube-context (no \$KUBE_CONTEXT and no current-context). A target that cannot be read cannot be trusted to match. Blocked."
fi

# --- Check 1: context match -------------------------------------------------
if [[ "$EFFECTIVE_CONTEXT" != "$B_CONTEXT" ]]; then
  block "environment MISMATCH — you declared '$ENV_NAME' (expects context '$B_CONTEXT') but the effective context is '$EFFECTIVE_CONTEXT'. This is the wrong-target class of incident; the operation is blocked before it runs."
fi

# --- Check 2: identity match (informational when kubeconfig not resolvable) --
if [[ -n "${KUBECONFIG:-}" ]]; then
  case "$KUBECONFIG" in
    *admin*)    EFF_ID="admin" ;;
    *readonly*) EFF_ID="readonly" ;;
    *)          EFF_ID="unknown" ;;
  esac
  if [[ "$EFF_ID" != "unknown" && "$EFF_ID" != "$B_IDENTITY" ]]; then
    block "identity MISMATCH — bundle '$ENV_NAME' requires the '$B_IDENTITY' identity but KUBECONFIG resolves to '$EFF_ID'. Blocked."
  fi
fi

# --- Check 3: action policy -------------------------------------------------
case "$ACTION" in
  apply)
    [[ "$B_APPLY" == "true" ]] || block "action 'apply' is NOT permitted in '$ENV_NAME' (allow_apply: false). Changes to this environment flow through GitOps — branch, PR, approval, reconciler. Blocked."
    ;;
  delete)
    [[ "$B_DELETE" == "true" ]] || block "action 'delete' is NOT permitted in '$ENV_NAME' (allow_delete: false). Deletions to this environment flow through GitOps prune, never a direct agent delete. Blocked."
    ;;
  read) ;;
  *) block "unknown action '$ACTION' (expected apply|delete|read). Blocked." ;;
esac

APPROVAL_NOTE=""
[[ "$B_APPROVAL" == "true" ]] && APPROVAL_NOTE="  ${YELLOW}(this environment also requires human approval)${NC}"
ok "declared '$ENV_NAME' matches effective context '$EFFECTIVE_CONTEXT'; action '$ACTION' permitted.${APPROVAL_NOTE}"
exit 0

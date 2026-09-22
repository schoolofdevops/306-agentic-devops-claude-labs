#!/usr/bin/env bash
# Defence in depth. RBAC is the control; this is a faster, louder no.
set -euo pipefail
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
case "$cmd" in
  *"kubectl"*" delete "*|*"kubectl"*" apply "*|*"kubectl"*" patch "*|*"kubectl"*" scale "*|*"kubectl"*" edit "*)
    echo '{"decision":"deny","reason":"Mutating kubectl verb. This role is read-only; remediation runs under the agent-remediator identity."}'
    exit 0 ;;
esac
echo '{}'

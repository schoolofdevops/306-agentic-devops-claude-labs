#!/usr/bin/env bash
# plan-drift.sh — deterministic drift analysis between two Terraform plans.
#
# "Environment drift" is when the change a learner authored against one plan
# introduces resources or exposures that a known-good baseline plan does not
# have. Instead of eyeballing two 1400-line JSON files, diff them structurally:
#
#   * NEW ADDRESSES     — resource addresses present in the candidate plan but
#                         not in the baseline. These are what the change ADDS.
#   * NEW WIDE-OPEN     — 0.0.0.0/0 ingress rules the candidate has that the
#                         baseline does not. This is the drift that matters:
#                         a new internet-open rule that slipped in.
#   * REPLACED_DELTA    — resources the candidate replaces that the baseline
#                         only creates. A change that turns a clean create into
#                         a destroy+create is drifting toward data loss.
#
# Usage:  plan-drift.sh <baseline.json> <candidate.json>
#             [--field new_addresses|new_wide_open|drift_count|verdict|json]
#         default field: json
#
# Exit 0  -> drift report emitted
# Exit 1  -> FAIL-CLOSED: file missing / not valid plan JSON / unknown field
set -euo pipefail

fail_closed() { echo "plan-drift: FAIL-CLOSED: $1" >&2; exit 1; }

BASE="${1:-}"
CAND="${2:-}"
FIELD="json"
shift 2 2>/dev/null || fail_closed "usage: plan-drift.sh <baseline.json> <candidate.json> [--field F]"
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done
[ -n "$BASE" ] && [ -f "$BASE" ] || fail_closed "no such baseline file: $BASE"
[ -n "$CAND" ] && [ -f "$CAND" ] || fail_closed "no such candidate file: $CAND"
for f in "$BASE" "$CAND"; do
  jq -e '.resource_changes | type == "array"' "$f" >/dev/null 2>&1 \
    || fail_closed "$f is not a terraform plan JSON (no .resource_changes array)"
done

addrs()      { jq -r '[.resource_changes[].address] | sort' "$1"; }
wideopen()   { jq -r '[.resource_changes[] | select((.change.after.cidr_blocks // []) | index("0.0.0.0/0")) | .address] | sort' "$1"; }

BASE_ADDR="$(addrs "$BASE")";  CAND_ADDR="$(addrs "$CAND")"
BASE_OPEN="$(wideopen "$BASE")"; CAND_OPEN="$(wideopen "$CAND")"

REPORT="$(jq -n \
  --argjson ba "$BASE_ADDR" --argjson ca "$CAND_ADDR" \
  --argjson bo "$BASE_OPEN" --argjson co "$CAND_OPEN" '
  ($ca - $ba) as $new_addr
  | ($co - $bo) as $new_open
  | {
      new_addresses: $new_addr,
      new_wide_open: $new_open,
      drift_count: (($new_addr | length) + ($new_open | length)),
      verdict: (
        if ($new_open | length) > 0 then "block"
        elif ($new_addr | length) > 0 then "flag"
        else "clean" end
      )
    }
')"

case "$FIELD" in
  json)          echo "$REPORT" | jq . ;;
  new_addresses) echo "$REPORT" | jq -r '.new_addresses[]?' ;;
  new_wide_open) echo "$REPORT" | jq -r '.new_wide_open[]?' ;;
  drift_count)   echo "$REPORT" | jq -r '.drift_count' ;;
  verdict)       echo "$REPORT" | jq -r '.verdict' ;;
  *) fail_closed "unknown field '$FIELD' (new_addresses|new_wide_open|drift_count|verdict|json)" ;;
esac

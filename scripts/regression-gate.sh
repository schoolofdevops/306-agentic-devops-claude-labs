#!/usr/bin/env bash
# regression-gate.sh — the CI gate that fails a build when agent quality regresses.
#
# A skill, an agent prompt, a hook, or an authority policy is code, and code
# regresses. Someone edits the sre-investigator prompt to be "more concise" and
# it stops checking the retry config; someone widens the authority matrix and a
# read-only role can suddenly write. None of that breaks a unit test — the YAML
# still parses, the script still runs. What catches it is an EVAL gate: score the
# run against the answer key and FAIL the build if the composite drops below the
# threshold or an authority boundary is crossed. This is the difference between
# "the code compiles" and "the agent still does its job."
#
# The gate enforces the thresholds declared in the answer key (evals/
# retry-storm-key.json), so the bar lives in version control next to the eval:
#
#   composite_pass          — the run's composite must be >= this
#   authority_max_unauthorized — unauthorized write attempts must be <= this (0)
#
# It is deliberately a hard gate: a regression exits non-zero so CI goes red. A
# gate you can ignore is not a gate.
#
# Usage:  regression-gate.sh <run.json> [--field verdict|composite|json]
#         default field: verdict
#
# Exit 0  -> PASS (run meets the bar)
# Exit 2  -> REGRESSION (run is below threshold or crossed an authority boundary)
# Exit 1  -> FAIL-CLOSED: no input / not JSON / key or scorer missing / unknown field
set -euo pipefail

fail_closed() { echo "regression-gate: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCORER="$SCRIPT_DIR/eval-score.sh"
KEY="$REPO_ROOT/evals/retry-storm-key.json"
[ -x "$SCORER" ] || fail_closed "eval-score.sh missing or not executable"
[ -f "$KEY" ] || fail_closed "answer key missing at $KEY"

RUN_FILE=""
FIELD="verdict"
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="${2:-}"; shift 2 ;;
    -*) fail_closed "unknown arg '$1'" ;;
    *) RUN_FILE="$1"; shift ;;
  esac
done
[ -n "$RUN_FILE" ] && [ -f "$RUN_FILE" ] || fail_closed "no such run file: ${RUN_FILE:-<none>}"

RUN="$(cat "$RUN_FILE")"
echo "$RUN" | jq empty 2>/dev/null || fail_closed "run record is not JSON"

COMPOSITE="$("$SCORER" "$RUN_FILE" --field composite)"
UNAUTH="$(echo "$RUN" | jq -r '.governance.unauthorized_attempts // 0')"

MIN="$(jq -r '.thresholds.composite_pass' "$KEY")"
MAX_UNAUTH="$(jq -r '.thresholds.authority_max_unauthorized' "$KEY")"

REASON=""
GATE="pass"
if jq -n --argjson c "$COMPOSITE" --argjson m "$MIN" 'if $c < $m then true else false end' | grep -q true; then
  GATE="regression"; REASON="composite $COMPOSITE below threshold $MIN"
elif [ "$UNAUTH" -gt "$MAX_UNAUTH" ]; then
  GATE="regression"; REASON="$UNAUTH unauthorized attempt(s) exceed limit $MAX_UNAUTH"
fi

RESULT="$(jq -n \
  --arg run_id "$(echo "$RUN" | jq -r '.run_id')" \
  --argjson composite "$COMPOSITE" \
  --argjson min "$MIN" \
  --argjson unauth "$UNAUTH" \
  --arg gate "$GATE" \
  --arg reason "$REASON" '
  {run_id: $run_id, composite: $composite, threshold: $min,
   unauthorized_attempts: $unauth, gate: $gate,
   reason: (if $reason == "" then "meets the bar" else $reason end)}')"

case "$FIELD" in
  json) echo "$RESULT" | jq . ;;
  composite) echo "$COMPOSITE" ;;
  verdict) echo "$GATE" ;;
  *) fail_closed "unknown field '$FIELD'" ;;
esac

[ "$GATE" = "pass" ] || exit 2
exit 0

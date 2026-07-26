#!/usr/bin/env bash
# promptfoo-gate.sh — the QUALITY dial as a CI gate.
#
# A prompt or model change can pass every unit test and still quietly break the
# thing that matters: the model stops including the order ID, starts promising
# refunds, drifts over the length budget. Those are not crashes — they are
# quality regressions, and the only way to catch them before production is to
# pin the behavior with assertions and run them on every change.
#
# This is a deterministic, dependency-light stand-in for Promptfoo. It reads a
# promptfoo-style suite (evals/promptfoo/*.yaml), grades a set of RECORDED model
# outputs against each test's assertions, and fails closed if any assertion
# marked required:true regresses. In real CI you would run the actual promptfoo
# CLI against a live provider; the CONTRACT — cases, assertions, required flags,
# fail-closed gate — is identical, which is the point the module makes.
#
# Usage:
#   promptfoo-gate.sh <suite.yaml> [--set good|regressed]
#                     [--field verdict|failed|passed|json]
#     --set selects which recorded-output set in the fixture to grade
#           (default: good). 'regressed' demonstrates the gate catching a break.
#     default field: verdict
#
# Writes agentops/gateway/last-gate.json so llm-dials.sh can show the quality
# dial alongside the other three.
#
# Exit 0 -> all required assertions held (verdict=pass)
# Exit 2 -> a required assertion regressed (verdict=fail) — the CI gate blocks
# Exit 1 -> FAIL-CLOSED (missing/unparseable suite, unknown field/set)
set -euo pipefail

fail_closed() { echo "promptfoo-gate: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SUITE="${1:-}"; shift || true
SET="good"
FIELD="verdict"
while [ $# -gt 0 ]; do
  case "$1" in
    --set)   SET="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done

[ -n "$SUITE" ] && [ -f "$SUITE" ] || fail_closed "usage: promptfoo-gate.sh <suite.yaml> [--set good|regressed]"
case "$SET" in good|regressed) ;; *) fail_closed "--set must be good|regressed (got '$SET')" ;; esac
command -v yq >/dev/null 2>&1 || fail_closed "yq not installed (need kislyuk/yq)"

# Convert the whole suite to JSON once.
SUITE_JSON="$(yq -o=json '.' "$SUITE" 2>/dev/null)" || SUITE_JSON="$(yq '.' "$SUITE" 2>/dev/null)" || fail_closed "cannot parse $SUITE"

OUTPUTS_FILE="$(jq -r '.recorded_outputs // empty' <<<"$SUITE_JSON")"
[ -n "$OUTPUTS_FILE" ] && [ -f "$OUTPUTS_FILE" ] || fail_closed "recorded_outputs file missing (.recorded_outputs in suite)"
OUTPUTS="$(jq -c ".$SET // empty" "$OUTPUTS_FILE")"
[ -n "$OUTPUTS" ] || fail_closed "no '$SET' output set in $OUTPUTS_FILE"

results="[]"
failed_required=0

# word count of a string
wc_words() { awk '{print NF}' <<<"$1"; }

n_tests="$(jq '.tests | length' <<<"$SUITE_JSON")"
for i in $(seq 0 $((n_tests - 1))); do
  name="$(jq -r ".tests[$i].name" <<<"$SUITE_JSON")"
  output="$(jq -r --arg n "$name" '.[$n] // ""' <<<"$OUTPUTS")"
  [ -n "$output" ] || fail_closed "no recorded output for test '$name' in set '$SET'"
  lc_output="$(printf '%s' "$output" | tr '[:upper:]' '[:lower:]')"

  n_asserts="$(jq ".tests[$i].assert | length" <<<"$SUITE_JSON")"
  for j in $(seq 0 $((n_asserts - 1))); do
    a_type="$(jq -r ".tests[$i].assert[$j].type" <<<"$SUITE_JSON")"
    a_val="$(jq -r ".tests[$i].assert[$j].value" <<<"$SUITE_JSON")"
    a_req="$(jq -r ".tests[$i].assert[$j].required // false" <<<"$SUITE_JSON")"

    pass=false
    case "$a_type" in
      contains)
        lc_val="$(printf '%s' "$a_val" | tr '[:upper:]' '[:lower:]')"
        case "$lc_output" in *"$lc_val"*) pass=true ;; *) pass=false ;; esac ;;
      not-contains)
        lc_val="$(printf '%s' "$a_val" | tr '[:upper:]' '[:lower:]')"
        case "$lc_output" in *"$lc_val"*) pass=false ;; *) pass=true ;; esac ;;
      max-words)
        words="$(wc_words "$output")"
        [ "$words" -le "$a_val" ] && pass=true || pass=false ;;
      *) fail_closed "unknown assert type '$a_type'" ;;
    esac

    if [ "$pass" = "false" ] && [ "$a_req" = "true" ]; then
      failed_required=$((failed_required + 1))
    fi

    results="$(jq -c \
      --arg test "$name" --arg type "$a_type" --arg val "$a_val" \
      --argjson req "$a_req" --argjson pass "$pass" \
      '. + [{ test: $test, assert: $type, value: $val, required: $req, pass: $pass }]' <<<"$results")"
  done
done

verdict="pass"; [ "$failed_required" -gt 0 ] && verdict="fail"

REPORT="$(jq -n --argjson results "$results" --arg verdict "$verdict" \
  --argjson failed "$failed_required" --arg set "$SET" '{
    set: $set,
    passed: ($results | map(select(.pass)) | length),
    failed: ($results | map(select(.pass|not)) | length),
    failed_required: $failed,
    results: $results,
    verdict: $verdict
  }')"

mkdir -p agentops/gateway
jq -n --arg v "$verdict" --arg set "$SET" \
  --argjson failed "$failed_required" \
  '{ verdict: $v, set: $set, failed_required: $failed }' > agentops/gateway/last-gate.json

case "$FIELD" in
  verdict) echo "$REPORT" | jq -r '.verdict' ;;
  failed)  echo "$REPORT" | jq -r '.failed' ;;
  passed)  echo "$REPORT" | jq -r '.passed' ;;
  json)    echo "$REPORT" | jq . ;;
  *) fail_closed "unknown field '$FIELD' (verdict|failed|passed|json)" ;;
esac

[ "$verdict" = "pass" ] || exit 2

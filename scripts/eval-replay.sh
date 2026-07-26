#!/usr/bin/env bash
# eval-replay.sh — run an evaluation as REPEATED TRIALS, not a single shot.
#
# The trap in evaluating agents is that they are nondeterministic: the SAME
# prompt against the SAME incident can produce a correct diagnosis on one run and
# a miscalibrated one on the next. A single pass/fail tells you what happened
# once — it does not tell you how often it happens. That is the difference
# between "it worked when I tried it" and "it works." This script replays the
# same scenario N times and reports the DISTRIBUTION of composite scores, so the
# result is a pass-rate with spread, not a lucky green checkmark.
#
# Determinism for a graded lab: real trials would call the model and vary
# genuinely. To keep the lab reproducible on any machine, this script derives a
# stable per-trial jitter from a --seed (default 42) and applies it to the
# recorded run's evidence-coverage, modelling the realistic variance where a
# nondeterministic run sometimes checks one fewer evidence dimension. Same seed,
# same distribution — so the confidence interval a learner sees is the one the
# checks expect, while the SHAPE (a band, not a point) is the real lesson.
#
# Input:  a run record JSON (fixtures/runs/*.json) + a trial count.
# Output: a distribution summary — trials, pass-rate, min/mean/max composite.
#
# Usage:  eval-replay.sh <run.json> --trials N [--seed S]
#             [--field pass_rate|mean|min|max|stable|json]
#         default trials: 10   seed: 42   field: json
#
# Exit 0  -> distribution emitted
# Exit 1  -> FAIL-CLOSED: no input / not JSON / bad trials / unknown field
set -euo pipefail

fail_closed() { echo "eval-replay: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCORER="$SCRIPT_DIR/eval-score.sh"
[ -x "$SCORER" ] || fail_closed "eval-score.sh missing or not executable"

SRC=""
TRIALS=10
SEED=42
FIELD="json"
while [ $# -gt 0 ]; do
  case "$1" in
    --trials) TRIALS="${2:-}"; shift 2 ;;
    --seed)   SEED="${2:-}"; shift 2 ;;
    --field)  FIELD="${2:-}"; shift 2 ;;
    -*) fail_closed "unknown arg '$1'" ;;
    *) SRC="$1"; shift ;;
  esac
done

[ -n "$SRC" ] && [ -f "$SRC" ] || fail_closed "no such run file: $SRC"
case "$TRIALS" in ''|*[!0-9]*) fail_closed "trials must be a positive integer" ;; esac
[ "$TRIALS" -ge 1 ] || fail_closed "trials must be >= 1"
RUN="$(cat "$SRC")"
echo "$RUN" | jq empty 2>/dev/null || fail_closed "run record is not JSON"

# The recorded run's full evidence dimension list. Under jitter a trial may
# "drop" the last dimension (the realistic near-miss where a nondeterministic run
# runs out of turns before the final check).
BASE_DIMS="$(echo "$RUN" | jq -c '.claim.checked_dimensions // []')"
N_DIMS="$(echo "$BASE_DIMS" | jq 'length')"

scores=()
pass=0
for t in $(seq 1 "$TRIALS"); do
  # Deterministic per-trial jitter: a hash of seed+trial, mod 3. On ~1/3 of
  # trials (jitter==0) the run drops its last-checked evidence dimension,
  # modelling the variance where the same agent sometimes under-collects.
  jitter=$(( (SEED * 31 + t * 7) % 3 ))
  if [ "$jitter" -eq 0 ] && [ "$N_DIMS" -gt 0 ]; then
    TRIAL_RUN="$(echo "$RUN" | jq --argjson n "$N_DIMS" \
      '.claim.checked_dimensions |= .[0:($n-1)]')"
  else
    TRIAL_RUN="$RUN"
  fi
  comp="$(echo "$TRIAL_RUN" | "$SCORER" --field composite)"
  verdict="$(echo "$TRIAL_RUN" | "$SCORER" --field verdict)"
  scores+=("$comp")
  [ "$verdict" = "pass" ] && pass=$((pass + 1))
done

# Aggregate the distribution with jq over the collected scores.
SCORES_JSON="$(printf '%s\n' "${scores[@]}" | jq -s '.')"
SUMMARY="$(jq -n \
  --arg run_id "$(echo "$RUN" | jq -r '.run_id')" \
  --argjson trials "$TRIALS" \
  --argjson pass "$pass" \
  --argjson scores "$SCORES_JSON" '
  {run_id: $run_id,
   trials: $trials,
   pass_count: $pass,
   pass_rate: (($pass / $trials * 1000) | round / 1000),
   min: ($scores | min),
   mean: (($scores | add / length * 1000) | round / 1000),
   max: ($scores | max),
   stable: (($scores | min) == ($scores | max))}')"

case "$FIELD" in
  json) echo "$SUMMARY" | jq . ;;
  pass_rate) echo "$SUMMARY" | jq -r '.pass_rate' ;;
  mean) echo "$SUMMARY" | jq -r '.mean' ;;
  min) echo "$SUMMARY" | jq -r '.min' ;;
  max) echo "$SUMMARY" | jq -r '.max' ;;
  stable) echo "$SUMMARY" | jq -r '.stable' ;;
  *) fail_closed "unknown field '$FIELD'" ;;
esac

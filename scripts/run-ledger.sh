#!/usr/bin/env bash
# run-ledger.sh — the Agent Run Ledger: record and compare agent runs.
#
# You cannot manage what you cannot compare. Every agent run leaves harness
# telemetry — turns, tokens, cost, tool calls — and, once scored, a quality
# verdict. The Agent Run Ledger is the durable table that joins the two: one row
# per run carrying BOTH what it cost AND how good it was. That join is the whole
# point. Cost without quality tells you the cheap topology; quality without cost
# tells you the good one. The ledger lets you ask the only question that matters
# in production — "what is the CHEAPEST topology that still meets the quality and
# risk bar?" — and answer it with a number, not a preference.
#
# Subcommands:
#   record <run.json>         Score the run and append a ledger row (config,
#                             topology, model, cost, composite, verdict,
#                             unauthorized attempts). Idempotent on run_id.
#   compare                   Print the two-topology comparison from the ledger:
#                             for each config, its composite, cost, and the
#                             cost-per-quality-point ($ / composite).
#   cheapest-passing          Print the config with the LOWEST cost among those
#                             that PASS the quality bar — the production answer.
#   reset                     Clear the ledger.
#
# Ledger:  agentops/runs/ledger.jsonl  (one JSON object per line)
#
# Usage:  run-ledger.sh record <run.json>
#         run-ledger.sh compare [--field json|table]
#         run-ledger.sh cheapest-passing
#         run-ledger.sh reset
#
# Exit 0  -> ok
# Exit 1  -> FAIL-CLOSED: bad args / missing file / scorer missing / no passing run
set -euo pipefail

fail_closed() { echo "run-ledger: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCORER="$SCRIPT_DIR/eval-score.sh"
LEDGER="$REPO_ROOT/agentops/runs/ledger.jsonl"
mkdir -p "$(dirname "$LEDGER")"

CMD="${1:-}"
[ -n "$CMD" ] || fail_closed "a subcommand is required (record|compare|cheapest-passing|reset)"
shift || true

case "$CMD" in
  reset)
    rm -f "$LEDGER"
    echo "ledger cleared"
    ;;

  record)
    RUN_FILE="${1:-}"
    [ -n "$RUN_FILE" ] && [ -f "$RUN_FILE" ] || fail_closed "no such run file: ${RUN_FILE:-<none>}"
    [ -x "$SCORER" ] || fail_closed "eval-score.sh missing or not executable"
    RUN="$(cat "$RUN_FILE")"
    echo "$RUN" | jq empty 2>/dev/null || fail_closed "run record is not JSON"

    SCORE="$("$SCORER" "$RUN_FILE" --field json)"
    RUN_ID="$(echo "$RUN" | jq -r '.run_id')"

    # Idempotent on run_id: drop any existing row for this run before appending.
    if [ -f "$LEDGER" ]; then
      TMP="$(mktemp)"
      grep -v "\"run_id\":\"$RUN_ID\"" "$LEDGER" > "$TMP" 2>/dev/null || true
      mv "$TMP" "$LEDGER"
    fi

    ROW="$(jq -cn --argjson run "$RUN" --argjson score "$SCORE" '
      {run_id: $run.run_id,
       config: $run.config,
       topology: $run.topology,
       model: $run.model,
       effort: $run.effort,
       cost_usd: $run.harness.cost_usd,
       turns: $run.harness.turns,
       tool_calls: $run.harness.tool_calls,
       unauthorized_attempts: ($run.governance.unauthorized_attempts // 0),
       composite: $score.composite,
       verdict: $score.verdict}')"
    echo "$ROW" >> "$LEDGER"
    echo "recorded: $RUN_ID  config=$(echo "$ROW" | jq -r .config)  composite=$(echo "$ROW" | jq -r .composite)  verdict=$(echo "$ROW" | jq -r .verdict)"
    ;;

  compare)
    [ -f "$LEDGER" ] || fail_closed "ledger is empty — record some runs first"
    FIELD="json"
    [ "${1:-}" = "--field" ] && FIELD="${2:-json}"
    # cost_per_point = cost / composite (guard divide-by-zero). Lower is better:
    # dollars spent per unit of diagnostic quality.
    ROWS="$(jq -s 'map({config, topology, model, cost_usd, composite, verdict,
      unauthorized_attempts,
      cost_per_point: (if .composite > 0 then (.cost_usd / .composite * 1000 | round / 1000) else null end)})' "$LEDGER")"
    if [ "$FIELD" = "table" ]; then
      printf '%-16s %-32s %-8s %8s %10s %8s\n' CONFIG TOPOLOGY MODEL COST COMPOSITE VERDICT
      echo "$ROWS" | jq -r '.[] | [.config, .topology, .model, (.cost_usd|tostring), (.composite|tostring), .verdict] | @tsv' \
        | while IFS=$'\t' read -r c t m co cp v; do printf '%-16s %-32s %-8s %8s %10s %8s\n' "$c" "$t" "$m" "$co" "$cp" "$v"; done
    else
      echo "$ROWS" | jq .
    fi
    ;;

  cheapest-passing)
    [ -f "$LEDGER" ] || fail_closed "ledger is empty — record some runs first"
    WINNER="$(jq -s '[.[] | select(.verdict == "pass")] | sort_by(.cost_usd) | .[0] // empty' "$LEDGER")"
    [ -n "$WINNER" ] || fail_closed "no passing run in the ledger — nothing meets the quality bar"
    echo "$WINNER" | jq -r '.config'
    ;;

  *)
    fail_closed "unknown subcommand '$CMD'"
    ;;
esac

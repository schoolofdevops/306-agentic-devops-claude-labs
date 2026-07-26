#!/usr/bin/env bash
# Agent Run Ledger for the M7 Three-Way Tool Shootout.
#
# Records one row per approach and renders a comparison table. Kept deliberately
# tiny and dependency-free (jq only) so the lab is about the tool interfaces,
# not about the ledger.
#
# Usage:
#   shootout-ledger.sh record <approach> <correct> <cost_usd> <latency_s> <tool_attempts> <least_priv>
#   shootout-ledger.sh table
#
#   approach       cli | skill | mcp
#   correct        yes | no        (did it reach the right diagnosis?)
#   cost_usd       number          (total cost for the run, from --output-format json)
#   latency_s      number          (wall-clock seconds)
#   tool_attempts  integer         (how many tool calls / turns it took)
#   least_priv     "Bash: anything" | "script scope" | "read tools only" (free text)
set -euo pipefail

LEDGER="${LEDGER:-labs/m7/shootout.jsonl}"

case "${1:-}" in
  record)
    shift
    approach="$1"; correct="$2"; cost="$3"; latency="$4"; attempts="$5"; priv="$6"
    mkdir -p "$(dirname "$LEDGER")"
    jq -cn \
      --arg approach "$approach" --arg correct "$correct" \
      --argjson cost "$cost" --argjson latency "$latency" \
      --argjson attempts "$attempts" --arg priv "$priv" \
      '{approach:$approach, correct:$correct, cost_usd:$cost, latency_s:$latency, tool_attempts:$attempts, least_privilege:$priv}' \
      >> "$LEDGER"
    echo "recorded: $approach"
    ;;
  table)
    [ -f "$LEDGER" ] || { echo "no runs recorded yet ($LEDGER)"; exit 1; }
    printf '%-8s | %-7s | %-9s | %-9s | %-13s | %s\n' \
      "approach" "correct" "cost_usd" "latency_s" "tool_attempts" "least_privilege"
    printf -- '---------|---------|-----------|-----------|---------------|-------------------\n'
    jq -r '"\(.approach)\t\(.correct)\t\(.cost_usd)\t\(.latency_s)\t\(.tool_attempts)\t\(.least_privilege)"' "$LEDGER" \
      | while IFS=$'\t' read -r a c t l n p; do
          printf '%-8s | %-7s | %-9s | %-9s | %-13s | %s\n' "$a" "$c" "$t" "$l" "$n" "$p"
        done
    ;;
  *)
    echo "usage: $0 record <approach> <correct> <tokens> <latency_s> <tool_attempts> <least_priv>"
    echo "       $0 table"
    exit 1
    ;;
esac

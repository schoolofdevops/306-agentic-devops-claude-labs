#!/usr/bin/env bash
# agent-cost-receipt.sh — the FinOps view of the AGENTS, not the infrastructure.
#
# Module 11 has two cost stories. One is the cloud bill the plan would create
# (cost-compare.sh). The other is the cost of the REVIEW ITSELF — the tokens the
# specialist chain spends analyzing the change. A FinOps practitioner prices both.
#
# This script produces the "agent-run cost receipt" for the IaC -> Security ->
# FinOps -> Change-Reviewer chain: for each role it reads the model right-sized
# for that role in contracts/authority-matrix.yaml, multiplies an estimated token
# spend by that model's blended price, and totals the run. The point it makes is
# the FinOps point from Module 9: running every role on the strongest model is
# waste. The receipt PROVES the mixed-model chain is cheaper than an all-Opus one.
#
# Prices are illustrative blended $/1M tokens (in+out averaged) for the receipt —
# the RATIO between models is the lesson, not the absolute figure:
#   opus=15  sonnet=3  haiku=0.80
#
# Per-role estimated tokens for one plan review (bounded by each role's turn
# budget — a haiku FinOps read is cheap, an opus security review is not):
#   iac-engineer=40000  security-reviewer=60000  finops-analyst=15000  change-reviewer=50000
#
# Usage:  agent-cost-receipt.sh [--field total|all_opus_total|savings|verdict|json]
#         default field: json
#
# Exit 0  -> receipt emitted
# Exit 1  -> FAIL-CLOSED: authority matrix missing / unparseable / unknown field
set -euo pipefail

fail_closed() { echo "agent-cost-receipt: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MATRIX="$REPO_ROOT/contracts/authority-matrix.yaml"

FIELD="${2:-json}"
[ "${1:-}" = "--field" ] || { [ -z "${1:-}" ] || fail_closed "unexpected arg '${1}' (expected --field)"; FIELD="json"; }
[ -f "$MATRIX" ] || fail_closed "no authority matrix at $MATRIX"

# The chain, in order. Each role's model comes from the matrix (source of truth),
# so if someone re-tunes a role's model the receipt re-prices automatically.
CHAIN="iac-engineer security-reviewer finops-analyst change-reviewer"

model_of() {
  # role_bundles.<role>.model — the matrix declares it inline as
  # `  <role>: { model: sonnet, ... }`. Match ONLY the inline-bundle line (the one
  # with a `{`), not the human-readable `roles:` header line of the same name.
  awk -v role="$1" '
    $0 ~ "^  "role":[[:space:]]*\\{" { line=$0; sub(/.*model:[[:space:]]*/,"",line); sub(/[,}].*/,"",line); gsub(/[[:space:]]/,"",line); print line; exit }
  ' "$MATRIX"
}

price_of() { case "$1" in opus) echo 15 ;; sonnet) echo 3 ;; haiku) echo 0.80 ;; *) echo "" ;; esac; }
tokens_of() {
  case "$1" in
    iac-engineer) echo 40000 ;; security-reviewer) echo 60000 ;;
    finops-analyst) echo 15000 ;; change-reviewer) echo 50000 ;; *) echo 0 ;;
  esac
}

rows="[]"
for role in $CHAIN; do
  model="$(model_of "$role")"
  [ -n "$model" ] || fail_closed "no model for role '$role' in $MATRIX"
  price="$(price_of "$model")"
  [ -n "$price" ] || fail_closed "no price for model '$model' (role $role)"
  tokens="$(tokens_of "$role")"
  rows="$(jq -c \
    --arg role "$role" --arg model "$model" \
    --argjson price "$price" --argjson tokens "$tokens" \
    '. + [{
        role: $role, model: $model, tokens: $tokens,
        cost_usd: (($tokens / 1000000) * $price * 1000 | round / 1000)
     }]' <<<"$rows")"
done

REPORT="$(jq -n --argjson rows "$rows" '
  ($rows | map(.cost_usd) | add) as $total
  # counterfactual: the SAME token spend, but every role on opus ($15/1M).
  | ($rows | map((.tokens / 1000000) * 15) | add | (. * 1000 | round / 1000)) as $all_opus
  | {
      chain: $rows,
      total_usd: (($total) * 1000 | round / 1000),
      all_opus_total_usd: $all_opus,
      savings_usd: (($all_opus - $total) * 1000 | round / 1000),
      verdict: (if $total < $all_opus then "mixed-model-cheaper" else "no-savings" end)
    }
')"

case "$FIELD" in
  json)            echo "$REPORT" | jq . ;;
  total)           echo "$REPORT" | jq -r '.total_usd' ;;
  all_opus_total)  echo "$REPORT" | jq -r '.all_opus_total_usd' ;;
  savings)         echo "$REPORT" | jq -r '.savings_usd' ;;
  verdict)         echo "$REPORT" | jq -r '.verdict' ;;
  *) fail_closed "unknown field '$FIELD' (total|all_opus_total|savings|verdict|json)" ;;
esac

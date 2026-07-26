#!/usr/bin/env bash
# gateway-cost-receipt.sh — the two costs of an LLM feature, side by side.
#
# The core lab prices the WORKLOAD: what support traffic pays the provider under
# a given route. This receipt adds the second number a FinOps-literate LLMOps
# review always carries — the cost of the REVIEW ITSELF: the tokens the
# mlops-engineer spends reading config and traces to reach a verdict. It is the
# LLMOps twin of M11's agent-cost-receipt.sh, and it makes the same point in a
# new domain: right-size the model to the task at BOTH layers.
#
# Layer 1 — WORKLOAD: support requests/day * tokens/request * route price.
#           On the regressed 'deep' route this is the $8k/day the incident is
#           about. On 'fast' it is a fraction of that.
# Layer 2 — REVIEW:   the mlops-engineer runs at 'sonnet' (bounded config read),
#           not 'opus'. The receipt prices the review at both and shows the
#           saving — the same "do not send opus to read a diff" lesson.
#
# Prices: illustrative blended $/1M (in+out). RATIO is the lesson, not absolutes.
#   opus=15  sonnet=3  haiku=0.80
# Review token estimate: one gateway review = ~35000 tokens (read 2 configs + a
# trace + run three tools + write a handoff).
#
# Usage:
#   gateway-cost-receipt.sh [--route support] [--routing FILE] [--providers FILE]
#                           [--field workload_day|review_sonnet|review_opus|review_savings|json]
#     default field: json
#
# Exit 0 -> receipt emitted   Exit 1 -> FAIL-CLOSED (missing/unparseable/unknown field)
set -euo pipefail

fail_closed() { echo "gateway-cost-receipt: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

ROUTE="support"
ROUTING="platform/gateway/routing.yaml"
PROVIDERS="platform/gateway/providers.yaml"
MATRIX="contracts/authority-matrix.yaml"
FIELD="json"
REVIEW_TOKENS=35000

while [ $# -gt 0 ]; do
  case "$1" in
    --route)     ROUTE="${2:-}"; shift 2 ;;
    --routing)   ROUTING="${2:-}"; shift 2 ;;
    --providers) PROVIDERS="${2:-}"; shift 2 ;;
    --field)     FIELD="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done

command -v yq >/dev/null 2>&1 || fail_closed "yq not installed (need kislyuk/yq)"
[ -f "$ROUTING" ]   || fail_closed "no such file: $ROUTING"
[ -f "$PROVIDERS" ] || fail_closed "no such file: $PROVIDERS"

yqget() { yq -r "$2" "$1" 2>/dev/null || fail_closed "cannot read '$2' from $1"; }
price_of() { case "$1" in opus) echo 15 ;; sonnet) echo 3 ;; haiku) echo 0.80 ;; *) echo "" ;; esac; }

# --- Layer 1: workload cost on the current route ---
model="$(yq -r ".routes.\"$ROUTE\".model // \"\"" "$ROUTING" 2>/dev/null)"
[ -n "$model" ] || fail_closed "route '$ROUTE' not found in $ROUTING"
route_price="$(yqget "$PROVIDERS" ".models.\"$model\".price_per_1m_usd")"
reqs="$(yqget "$PROVIDERS" ".workload.\"$ROUTE\".requests_per_day")"
tpr="$(yqget "$PROVIDERS"  ".workload.\"$ROUTE\".tokens_per_request")"
workload_day="$(jq -n --argjson r "$reqs" --argjson t "$tpr" --argjson p "$route_price" \
  '((($r * $t) / 1000000) * $p * 100 | round / 100)')"

# --- Layer 2: review cost, at the role's model vs the strongest model ---
# The mlops-engineer's model comes from the authority matrix if present, else sonnet.
review_model="sonnet"
if [ -f "$MATRIX" ]; then
  m="$(awk '$0 ~ "^  mlops-engineer:[[:space:]]*\\{" { l=$0; sub(/.*model:[[:space:]]*/,"",l); sub(/[,}].*/,"",l); gsub(/[[:space:]]/,"",l); print l; exit }' "$MATRIX")"
  [ -n "$m" ] && review_model="$m"
fi
sonnet_price="$(price_of "$review_model")"
[ -n "$sonnet_price" ] || sonnet_price=3
review_sonnet="$(jq -n --argjson tk "$REVIEW_TOKENS" --argjson p "$sonnet_price" \
  '(($tk / 1000000) * $p * 1000 | round / 1000)')"
review_opus="$(jq -n --argjson tk "$REVIEW_TOKENS" \
  '(($tk / 1000000) * 15 * 1000 | round / 1000)')"
review_savings="$(jq -n --argjson o "$review_opus" --argjson s "$review_sonnet" \
  '(($o - $s) * 1000 | round / 1000)')"

REPORT="$(jq -n \
  --arg route "$ROUTE" --arg model "$model" --arg rmodel "$review_model" \
  --argjson wd "$workload_day" \
  --argjson rs "$review_sonnet" --argjson ro "$review_opus" --argjson rsav "$review_savings" \
  --argjson rtok "$REVIEW_TOKENS" '{
    route: $route,
    workload: { model: $model, day_cost_usd: $wd },
    review: {
      tokens: $rtok, role_model: $rmodel,
      cost_role_model_usd: $rs, cost_all_opus_usd: $ro, savings_usd: $rsav
    },
    note: "workload cost is per-DAY; review cost is per-RUN — different scales, both real"
  }')"

case "$FIELD" in
  json)           echo "$REPORT" | jq . ;;
  workload_day)   echo "$REPORT" | jq -r '.workload.day_cost_usd' ;;
  review_sonnet)  echo "$REPORT" | jq -r '.review.cost_role_model_usd' ;;
  review_opus)    echo "$REPORT" | jq -r '.review.cost_all_opus_usd' ;;
  review_savings) echo "$REPORT" | jq -r '.review.savings_usd' ;;
  *) fail_closed "unknown field '$FIELD' (workload_day|review_sonnet|review_opus|review_savings|json)" ;;
esac

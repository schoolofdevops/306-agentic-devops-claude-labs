#!/usr/bin/env bash
# gateway-diff.sh — review a gateway routing change as a cost + latency decision.
#
# A one-line edit in platform/gateway/routing.yaml can move an entire traffic
# class onto a different model tier. To a plain `git diff` that is one word
# changing. To the workload it is a latency and cost event. This script is the
# reviewed-artifact gate: it compares the CURRENT routing against a baseline,
# and for every route whose model changed it resolves both tiers through
# providers.yaml and reports what the change did to the four things a reviewer
# actually cares about — price, provider p95 latency, and (for the support
# class) the per-day workload cost.
#
# It is the LLMOps counterpart to M11's cost-compare.sh: same "a config change
# is a money + SLO decision, made mechanical" idea, applied to model routing.
#
# Usage:
#   gateway-diff.sh [--baseline FILE] [--current FILE] [--providers FILE]
#                   [--field verdict|changed|support_cost_delta|json]
#     defaults: baseline=fixtures/gateway/routing-baseline.yaml
#               current =platform/gateway/routing.yaml
#               providers=platform/gateway/providers.yaml
#               field=json
#
# Verdict:
#   review-required — a route moved to a costlier OR slower (p95) tier
#   clean           — no route changed tier, or changes are cheaper AND faster
#
# Exit 0 -> report emitted   Exit 1 -> FAIL-CLOSED (missing/unparseable input)
set -euo pipefail

fail_closed() { echo "gateway-diff: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASELINE="fixtures/gateway/routing-baseline.yaml"
CURRENT="platform/gateway/routing.yaml"
PROVIDERS="platform/gateway/providers.yaml"
FIELD="json"

while [ $# -gt 0 ]; do
  case "$1" in
    --baseline)  BASELINE="${2:-}"; shift 2 ;;
    --current)   CURRENT="${2:-}"; shift 2 ;;
    --providers) PROVIDERS="${2:-}"; shift 2 ;;
    --field)     FIELD="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done

command -v yq >/dev/null 2>&1 || fail_closed "yq not installed (need kislyuk/yq, a jq wrapper)"
for f in "$BASELINE" "$CURRENT" "$PROVIDERS"; do
  [ -f "$f" ] || fail_closed "no such file: $f"
done

# Pull a scalar out of a YAML file via yq, fail closed if absent.
yqget() { yq -r "$2" "$1" 2>/dev/null || fail_closed "cannot read '$2' from $1"; }

# Provider facts for a tier alias.
price_of()  { yqget "$PROVIDERS" ".models.\"$1\".price_per_1m_usd"; }
p95_of()    { yqget "$PROVIDERS" ".models.\"$1\".latency_ms.p95"; }

SUPPORT_REQS="$(yqget "$PROVIDERS" '.workload.support.requests_per_day')"
SUPPORT_TPR="$(yqget "$PROVIDERS"  '.workload.support.tokens_per_request')"

# Route names present in the current file.
ROUTES="$(yq -r '.routes | keys[]' "$CURRENT" 2>/dev/null)" || fail_closed "no .routes in $CURRENT"

changed="[]"
verdict="clean"
support_cost_delta="0"

for route in $ROUTES; do
  base_model="$(yq -r ".routes.\"$route\".model // \"\"" "$BASELINE" 2>/dev/null)"
  cur_model="$(yq  -r ".routes.\"$route\".model // \"\"" "$CURRENT"  2>/dev/null)"
  [ -n "$cur_model" ] || continue
  [ "$base_model" = "$cur_model" ] && continue      # tier unchanged for this route

  # Tier moved. Price both ends.
  base_price="$(price_of "$base_model")"
  cur_price="$(price_of "$cur_model")"
  base_p95="$(p95_of "$base_model")"
  cur_p95="$(p95_of "$cur_model")"

  # Per-day workload cost delta, but only the support class carries a modeled
  # volume — other classes report the price/latency move without a $ figure.
  day_delta="0"
  if [ "$route" = "support" ]; then
    day_delta="$(jq -n --argjson reqs "$SUPPORT_REQS" --argjson tpr "$SUPPORT_TPR" \
      --argjson bp "$base_price" --argjson cp "$cur_price" \
      '(($reqs * $tpr) / 1000000) as $mtok
       | (($cp - $bp) * $mtok * 100 | round / 100)')"
    support_cost_delta="$day_delta"
  fi

  # Costlier OR slower(p95) => review required.
  costlier="$(jq -n --argjson b "$base_price" --argjson c "$cur_price" 'if $c > $b then true else false end')"
  slower="$(jq -n --argjson b "$base_p95" --argjson c "$cur_p95" 'if $c > $b then true else false end')"
  [ "$costlier" = "true" ] || [ "$slower" = "true" ] && verdict="review-required"

  changed="$(jq -c \
    --arg route "$route" --arg from "$base_model" --arg to "$cur_model" \
    --argjson bp "$base_price" --argjson cp "$cur_price" \
    --argjson b95 "$base_p95" --argjson c95 "$cur_p95" \
    --argjson dd "$day_delta" \
    '. + [{
       route: $route, from: $from, to: $to,
       price_per_1m_usd: { from: $bp, to: $cp },
       provider_p95_ms:  { from: $b95, to: $c95 },
       support_cost_delta_per_day_usd: $dd
    }]' <<<"$changed")"
done

REPORT="$(jq -n --argjson changed "$changed" --arg verdict "$verdict" \
  --argjson scd "$support_cost_delta" \
  '{ changed: $changed, support_cost_delta_per_day_usd: $scd, verdict: $verdict }')"

case "$FIELD" in
  json)               echo "$REPORT" | jq . ;;
  verdict)            echo "$REPORT" | jq -r '.verdict' ;;
  changed)            echo "$REPORT" | jq -c '.changed' ;;
  support_cost_delta) echo "$REPORT" | jq -r '.support_cost_delta_per_day_usd' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|changed|support_cost_delta|json)" ;;
esac

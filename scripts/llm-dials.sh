#!/usr/bin/env bash
# llm-dials.sh — read the four LLMOps dials for a traffic class, and split a
# request trace into provider vs application latency.
#
# LLMOps monitors four dials, and they trade off against each other:
#   latency      — provider p50/p95 for this route's model tier
#   token cost   — $/1M and the modeled per-day workload cost (support only)
#   rate limits  — the route's configured rpm/tpm vs the provider's tpm ceiling,
#                  reported as headroom so you can see how close a volume spike
#                  would push you to throttling
#   quality      — NOT a number this script invents. Quality is measured by the
#                  regression suite (promptfoo-gate.sh); this dial reports the
#                  last recorded gate verdict so all four dials read together.
#
# The second job is the diagnostic one: given a request trace, split total
# latency into PROVIDER time (the model's own server-side generation) and
# APPLICATION time (our queueing, prompt assembly, response shaping). When a
# latency dial spikes, this split answers "is it them or is it us" — the single
# question that decides whether you fix a route or fix your code.
#
# Usage:
#   llm-dials.sh dials  <route>  [--field latency_p95|day_cost|tpm_headroom|json]
#   llm-dials.sh split  <trace.json> [--field provider_ms|application_ms|dominant|json]
#     defaults: providers=platform/gateway/providers.yaml
#               routing  =platform/gateway/routing.yaml
#               field=json
#
# Exit 0 -> emitted   Exit 1 -> FAIL-CLOSED (bad args / missing / unparseable)
set -euo pipefail

fail_closed() { echo "llm-dials: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PROVIDERS="platform/gateway/providers.yaml"
ROUTING="platform/gateway/routing.yaml"
GATE_STATE="agentops/gateway/last-gate.json"   # written by promptfoo-gate.sh
FIELD="json"

SUB="${1:-}"; shift || true
ARG="${1:-}"; shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --field)     FIELD="${2:-}"; shift 2 ;;
    --providers) PROVIDERS="${2:-}"; shift 2 ;;
    --routing)   ROUTING="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done

command -v yq >/dev/null 2>&1 || fail_closed "yq not installed (need kislyuk/yq)"
yqget() { yq -r "$2" "$1" 2>/dev/null || fail_closed "cannot read '$2' from $1"; }

case "$SUB" in
  dials)
    ROUTE="$ARG"
    [ -n "$ROUTE" ] || fail_closed "usage: llm-dials.sh dials <route>"
    [ -f "$PROVIDERS" ] || fail_closed "no such file: $PROVIDERS"
    [ -f "$ROUTING" ]   || fail_closed "no such file: $ROUTING"

    model="$(yq -r ".routes.\"$ROUTE\".model // \"\"" "$ROUTING" 2>/dev/null)"
    [ -n "$model" ] || fail_closed "route '$ROUTE' not found in $ROUTING"

    price="$(yqget "$PROVIDERS" ".models.\"$model\".price_per_1m_usd")"
    p50="$(yqget "$PROVIDERS"   ".models.\"$model\".latency_ms.p50")"
    p95="$(yqget "$PROVIDERS"   ".models.\"$model\".latency_ms.p95")"
    prov_tpm="$(yqget "$PROVIDERS" ".models.\"$model\".tpm_limit")"
    route_tpm="$(yqget "$ROUTING"  ".routes.\"$ROUTE\".rate_limit.tpm")"
    route_rpm="$(yqget "$ROUTING"  ".routes.\"$ROUTE\".rate_limit.rpm")"

    # Day cost only meaningful for the modeled support workload.
    day_cost="null"
    if [ "$ROUTE" = "support" ]; then
      reqs="$(yqget "$PROVIDERS" '.workload.support.requests_per_day')"
      tpr="$(yqget "$PROVIDERS"  '.workload.support.tokens_per_request')"
      day_cost="$(jq -n --argjson reqs "$reqs" --argjson tpr "$tpr" --argjson p "$price" \
        '((($reqs * $tpr) / 1000000) * $p * 100 | round / 100)')"
    fi

    # Rate-limit headroom: how much of the provider's tpm ceiling the route's
    # configured tpm already claims. Low headroom = a volume spike throttles.
    headroom_pct="$(jq -n --argjson rt "$route_tpm" --argjson pt "$prov_tpm" \
      'if $pt == 0 then 0 else ((($pt - $rt) / $pt) * 100 * 10 | round / 10) end')"

    gate="unknown"
    [ -f "$GATE_STATE" ] && gate="$(jq -r '.verdict // "unknown"' "$GATE_STATE" 2>/dev/null || echo unknown)"

    REPORT="$(jq -n \
      --arg route "$ROUTE" --arg model "$model" \
      --argjson p50 "$p50" --argjson p95 "$p95" \
      --argjson price "$price" --argjson day "$day_cost" \
      --argjson rrpm "$route_rpm" --argjson rtpm "$route_tpm" \
      --argjson ptpm "$prov_tpm" --argjson hr "$headroom_pct" \
      --arg gate "$gate" '{
        route: $route, model: $model,
        latency:     { p50_ms: $p50, p95_ms: $p95 },
        token_cost:  { price_per_1m_usd: $price, day_cost_usd: $day },
        rate_limits: { route_rpm: $rrpm, route_tpm: $rtpm, provider_tpm: $ptpm, tpm_headroom_pct: $hr },
        quality:     { last_gate_verdict: $gate }
      }')"

    case "$FIELD" in
      json)         echo "$REPORT" | jq . ;;
      latency_p95)  echo "$REPORT" | jq -r '.latency.p95_ms' ;;
      day_cost)     echo "$REPORT" | jq -r '.token_cost.day_cost_usd' ;;
      tpm_headroom) echo "$REPORT" | jq -r '.rate_limits.tpm_headroom_pct' ;;
      *) fail_closed "unknown field '$FIELD' (latency_p95|day_cost|tpm_headroom|json)" ;;
    esac
    ;;

  split)
    TRACE="$ARG"
    [ -n "$TRACE" ] && [ -f "$TRACE" ] || fail_closed "usage: llm-dials.sh split <trace.json>"
    jq -e '.spans' "$TRACE" >/dev/null 2>&1 || fail_closed "$TRACE has no .spans"

    REPORT="$(jq '
      (.spans | map(select(.kind=="provider")    | .ms) | add // 0) as $prov
      | (.spans | map(select(.kind=="application") | .ms) | add // 0) as $app
      | {
          trace_id: .trace_id, route: .route, model: .model, total_ms: .total_ms,
          provider_ms: $prov, application_ms: $app,
          dominant: (if $prov > $app then "provider" else "application" end),
          provider_share_pct: (if ($prov+$app) == 0 then 0
                               else (($prov / ($prov+$app)) * 100 * 10 | round / 10) end)
        }' "$TRACE")"

    case "$FIELD" in
      json)           echo "$REPORT" | jq . ;;
      provider_ms)    echo "$REPORT" | jq -r '.provider_ms' ;;
      application_ms) echo "$REPORT" | jq -r '.application_ms' ;;
      dominant)       echo "$REPORT" | jq -r '.dominant' ;;
      *) fail_closed "unknown field '$FIELD' (provider_ms|application_ms|dominant|json)" ;;
    esac
    ;;

  ""|-h|--help) fail_closed "usage: llm-dials.sh <dials|split> ..." ;;
  *) fail_closed "unknown subcommand '$SUB' (dials|split)" ;;
esac

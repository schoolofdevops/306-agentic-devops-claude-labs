#!/usr/bin/env bash
# cost-compare.sh — deterministic FinOps comparison of two cost-estimate JSONs.
#
# The finops-analyst role, made mechanical: read a baseline cost estimate and a
# proposed one, compute the monthly delta and the multiple, and flag any single
# resource whose cost grew more than the threshold (default 2x — the role's
# "flag instance changes > 2x current size" rule). Same rule, no model in the loop.
#
#   * DELTA     — proposed monthly total minus baseline monthly total.
#   * MULTIPLE  — proposed total / baseline total (how many times more expensive).
#   * DRIVERS   — the specific resources whose monthly cost grew >= threshold x,
#                 so the number has an address attached, not just a total.
#   * VERDICT   — block if any resource crosses the threshold multiple; else clean.
#
# Cost-estimate shape (Infracost-style): .projects[].breakdown.resources[] with
# {name, monthlyCost}, and .totalMonthlyCost at the top.
#
# Usage:  cost-compare.sh <baseline.json> <proposed.json>
#             [--threshold N] [--field delta|multiple|verdict|drivers|json]
#         default threshold: 2 (flag a resource that grew >= 2x)
#         default field: json
#
# Exit 0  -> comparison emitted
# Exit 1  -> FAIL-CLOSED: file missing / not valid estimate / bad threshold / unknown field
set -euo pipefail

fail_closed() { echo "cost-compare: FAIL-CLOSED: $1" >&2; exit 1; }

BASE="${1:-}"
PROP="${2:-}"
THRESHOLD="2"
FIELD="json"
shift 2 2>/dev/null || fail_closed "usage: cost-compare.sh <baseline.json> <proposed.json> [--threshold N] [--field F]"
while [ $# -gt 0 ]; do
  case "$1" in
    --threshold) THRESHOLD="${2:-}"; shift 2 ;;
    --field)     FIELD="${2:-}"; shift 2 ;;
    *) fail_closed "unknown arg '$1'" ;;
  esac
done

[ -n "$BASE" ] && [ -f "$BASE" ] || fail_closed "no such baseline file: $BASE"
[ -n "$PROP" ] && [ -f "$PROP" ] || fail_closed "no such proposed file: $PROP"
case "$THRESHOLD" in ''|*[!0-9.]*) fail_closed "--threshold must be a number (got '$THRESHOLD')" ;; esac
jq -e '.totalMonthlyCost' "$BASE" >/dev/null 2>&1 || fail_closed "$BASE has no .totalMonthlyCost"
jq -e '.totalMonthlyCost' "$PROP" >/dev/null 2>&1 || fail_closed "$PROP has no .totalMonthlyCost"

# Flatten each estimate to a map of {resource_name: monthlyCost}.
flatten() {
  jq '[.projects[]?.breakdown.resources[]? | {(.name): (.monthlyCost|tonumber)}] | add // {}' "$1"
}
BASE_MAP="$(flatten "$BASE")"
PROP_MAP="$(flatten "$PROP")"
BASE_TOTAL="$(jq -r '.totalMonthlyCost|tonumber' "$BASE")"
PROP_TOTAL="$(jq -r '.totalMonthlyCost|tonumber' "$PROP")"

REPORT="$(jq -n \
  --argjson base "$BASE_MAP" --argjson prop "$PROP_MAP" \
  --argjson bt "$BASE_TOTAL" --argjson pt "$PROP_TOTAL" \
  --argjson th "$THRESHOLD" '
  # per-resource drivers: those present in both whose cost grew >= threshold x.
  [ $prop | to_entries[]
    | .key as $k
    | ($base[$k] // 0) as $b
    | select($b > 0 and (.value / $b) >= $th)
    | { resource: $k, from: $b, to: .value, multiple: ((.value / $b) * 100 | round / 100) }
  ] as $drivers
  | {
      baseline_monthly: $bt,
      proposed_monthly: $pt,
      delta_monthly: (($pt - $bt) * 100 | round / 100),
      multiple: (if $bt > 0 then ($pt / $bt * 100 | round / 100) else null end),
      threshold: $th,
      drivers: $drivers,
      verdict: (if ($drivers | length) > 0 then "block" else "clean" end)
    }
')"

case "$FIELD" in
  json)     echo "$REPORT" | jq . ;;
  delta)    echo "$REPORT" | jq -r '.delta_monthly' ;;
  multiple) echo "$REPORT" | jq -r '.multiple' ;;
  verdict)  echo "$REPORT" | jq -r '.verdict' ;;
  drivers)  echo "$REPORT" | jq -r '.drivers[]? | "\(.resource) \(.from)->\(.to) (\(.multiple)x)"' ;;
  *) fail_closed "unknown field '$FIELD' (delta|multiple|verdict|drivers|json)" ;;
esac

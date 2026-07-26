#!/usr/bin/env bash
# pipeline-analyze.sh — the DETERMINISTIC release-gate analysis a CI pipeline runs
# over a release candidate, and the reference for what a HERMETIC Claude analysis
# (`claude -p --bare --output-format json --json-schema release-verdict.schema.json`)
# is expected to produce.
#
# Module 13 puts an agent inside CI. The agent's job in the pipeline is ANALYSIS,
# never mutation: read the candidate (app diff, Terraform plan JSON, Helm render)
# and emit a STRUCTURED verdict the pipeline can gate on. This script is the
# no-model-in-the-loop version of that verdict — same schema, same fields, fully
# reproducible — so the pipeline is gradeable and the hermetic Claude call has a
# reference output to be checked against.
#
# It reads THREE evidence sources, each already produced elsewhere in the repo:
#   1. app change    — is the readiness probe path in Helm values a path the app
#                      actually serves? (executable evidence beats documentation)
#   2. terraform     — plan-analyze.sh verdict over a plan JSON (state safety)   [optional]
#   3. helm render   — does the chart render, and is maxUnavailable sane?
#
# The verdict is fail-closed on the strongest objection: any single "block" makes
# the release "block". A release is "approve" only when every gate clears.
#
# Usage:  pipeline-analyze.sh [--plan <plan.json>] [--chart <chart-dir>]
#             [--field verdict|blockers|json]
#         defaults: --chart platform/helm/orders-api, --field json
#
# Exit 0  -> verdict emitted (verdict may be "block" — that is a successful GATE,
#            not a script error). This is the hermetic-analysis contract: the
#            analyzer reports, it does not decide to fail the build itself.
# Exit 1  -> FAIL-CLOSED: bad input / a gate could not evaluate.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

fail_closed() { echo "pipeline-analyze: FAIL-CLOSED: $1" >&2; exit 1; }

PLAN=""; CHART="platform/helm/orders-api"; FIELD="json"
while [ $# -gt 0 ]; do
  case "$1" in
    --plan)  PLAN="${2:-}"; shift 2 ;;
    --chart) CHART="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-}"; shift 2 ;;
    -*) fail_closed "unknown arg '$1'" ;;
    *)  fail_closed "unexpected positional arg '$1'" ;;
  esac
done

command -v jq   >/dev/null 2>&1 || fail_closed "jq is required"
command -v helm >/dev/null 2>&1 || fail_closed "helm is required"
[ -d "$CHART" ] || fail_closed "no such chart dir: $CHART"

# --- gate 1: app-vs-desired-state readiness (executable evidence) -------------
# The Helm readiness probe path must be a path the orders-api app actually serves.
# The app's real routes are the ground truth; the probe path is a claim about them.
APP_ROUTES="$(grep -oE '@router\.get\("(/[^"]*)"\)' app/orders-api/src/health.py \
                | sed -E 's/.*"(.*)".*/\1/' | jq -R . | jq -s . 2>/dev/null || echo '[]')"
PROBE_PATH="$(helm template orders-api "$CHART" 2>/dev/null \
                | awk '/readinessProbe:/{f=1} f&&/path:/{print $2; exit}')"
READINESS_OK="$(jq -n --argjson routes "$APP_ROUTES" --arg p "$PROBE_PATH" \
                  '($routes | index($p)) != null')"

# --- gate 2: helm render + rollout floor --------------------------------------
if helm template orders-api "$CHART" >/dev/null 2>&1; then RENDER_OK=true; else RENDER_OK=false; fi
MAXUNAVAIL="$(helm template orders-api "$CHART" 2>/dev/null \
                | awk '/maxUnavailable:/{print $2; exit}' | tr -d '"')"
# A rollout with maxUnavailable 100% has no serving floor — block.
STRATEGY_OK="$([ "$MAXUNAVAIL" != "100%" ] && echo true || echo false)"

# --- gate 3: terraform state safety (optional) --------------------------------
if [ -n "$PLAN" ]; then
  [ -f "$PLAN" ] || fail_closed "no such plan file: $PLAN"
  TF_VERDICT="$(bash "$SCRIPT_DIR/plan-analyze.sh" "$PLAN" --field verdict)" \
    || fail_closed "plan-analyze failed"
else
  TF_VERDICT="skipped"
fi

# --- JOIN into one release verdict. Fail-closed on any block. -----------------
REPORT="$(jq -n \
  --argjson readiness_ok "$READINESS_OK" \
  --arg     probe_path "$PROBE_PATH" \
  --argjson app_routes "$APP_ROUTES" \
  --argjson render_ok "$RENDER_OK" \
  --argjson strategy_ok "$STRATEGY_OK" \
  --arg     max_unavailable "${MAXUNAVAIL:-unknown}" \
  --arg     tf_verdict "$TF_VERDICT" '
  ( [ if $readiness_ok | not then "readiness: probe path " + $probe_path + " is not a route the app serves (" + ($app_routes | join(", ")) + ")" else empty end ]
  + [ if $render_ok   | not then "render: chart does not render" else empty end ]
  + [ if $strategy_ok | not then "rollout: maxUnavailable " + $max_unavailable + " leaves no serving floor" else empty end ]
  + [ if $tf_verdict == "block" then "terraform: stateful replacement (no clean rollback)" else empty end ]
  ) as $blockers
  | {
      gates: {
        readiness:  { ok: $readiness_ok, probe_path: $probe_path, app_routes: $app_routes },
        render:     { ok: $render_ok, max_unavailable: $max_unavailable },
        terraform:  { verdict: $tf_verdict }
      },
      blockers: $blockers,
      verdict: (if ($blockers | length) > 0 then "block" else "approve" end)
    }
')"

case "$FIELD" in
  json)     echo "$REPORT" | jq . ;;
  verdict)  echo "$REPORT" | jq -r '.verdict' ;;
  blockers) echo "$REPORT" | jq -r '.blockers[]?' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|blockers|json)" ;;
esac

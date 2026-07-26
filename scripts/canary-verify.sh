#!/usr/bin/env bash
# canary-verify.sh — deterministic CANARY verdict for a post-deploy health window.
#
# After the reconciler syncs a release, you do NOT promote it blindly. A canary
# takes a slice of traffic and you WATCH it: is the error rate acceptable, is
# latency within budget, are the new pods actually Ready? Only a healthy canary
# is promoted; an unhealthy one is rolled back. Module 13 has the agent READ the
# canary signals and emit a structured verdict — it never promotes or rolls back
# itself (that is a gated, human/reconciler action).
#
# This script is the no-model reference for that verdict. It reads a canary
# metrics snapshot (JSON) and applies fixed SLO thresholds, so the "verify the
# canary" step is a real, runnable, gradeable action rather than a slogan.
#
# Input snapshot shape (a fixture, or scraped from Prometheus in a real run):
#   {
#     "error_rate":  0.004,     # fraction of requests failing (SLO: <= 0.01)
#     "p95_latency_ms": 210,    # p95 latency in ms          (SLO: <= 300)
#     "ready_replicas": 2,      # canary pods reporting Ready
#     "desired_replicas": 2     # canary pods expected
#   }
#
# Verdict:
#   promote  — every SLO within budget AND all canary replicas Ready
#   rollback — any SLO breached OR a canary replica never became Ready
#
# Usage:  canary-verify.sh <snapshot.json> [--field verdict|reasons|json]
#         default field: json
#
# Exit 0  -> verdict emitted (a "rollback" verdict is a successful CHECK, not an error)
# Exit 1  -> FAIL-CLOSED: file missing / not valid JSON / unknown field
set -euo pipefail

# SLO thresholds (overridable by env for the lab).
MAX_ERROR_RATE="${MAX_ERROR_RATE:-0.01}"
MAX_P95_MS="${MAX_P95_MS:-300}"

fail_closed() { echo "canary-verify: FAIL-CLOSED: $1" >&2; exit 1; }

SNAP="${1:-}"
FIELD="json"
[ "${2:-}" = "--field" ] && FIELD="${3:-json}"
[ -n "$SNAP" ] && [ -f "$SNAP" ] || fail_closed "no such snapshot file: $SNAP"
jq -e 'type == "object"' "$SNAP" >/dev/null 2>&1 || fail_closed "$SNAP is not a JSON object"

REPORT="$(jq \
  --argjson max_err "$MAX_ERROR_RATE" \
  --argjson max_p95 "$MAX_P95_MS" '
  .error_rate       as $err
  | .p95_latency_ms as $p95
  | (.ready_replicas   // 0) as $ready
  | (.desired_replicas // 0) as $desired
  | ( [ if ($err // 1)  > $max_err then "error_rate " + ($err|tostring) + " exceeds SLO " + ($max_err|tostring) else empty end ]
    + [ if ($p95 // 1e9) > $max_p95 then "p95_latency_ms " + ($p95|tostring) + " exceeds SLO " + ($max_p95|tostring) else empty end ]
    + [ if $ready < $desired then "only " + ($ready|tostring) + "/" + ($desired|tostring) + " canary replicas Ready" else empty end ]
    ) as $reasons
  | {
      slo: { max_error_rate: $max_err, max_p95_ms: $max_p95 },
      observed: { error_rate: $err, p95_latency_ms: $p95, ready_replicas: $ready, desired_replicas: $desired },
      reasons: $reasons,
      verdict: (if ($reasons | length) > 0 then "rollback" else "promote" end)
    }
' "$SNAP")"

case "$FIELD" in
  json)    echo "$REPORT" | jq . ;;
  verdict) echo "$REPORT" | jq -r '.verdict' ;;
  reasons) echo "$REPORT" | jq -r '.reasons[]?' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|reasons|json)" ;;
esac

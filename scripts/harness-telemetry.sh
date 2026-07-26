#!/usr/bin/env bash
# harness-telemetry.sh — read Claude Code OTel traces and answer AGENT-HARNESS
# questions (turns, tokens, tool calls, denied writes) — the OTHER telemetry plane.
#
# Module 18's first idea: there are TWO telemetry planes, and confusing them is
# how teams end up flying blind. Prometheus and app logs answer questions about
# the TARGET SYSTEM — "is orders-api healthy, what is its p95." They say nothing
# about the AGENT that investigated it. The agent's own behaviour — how many
# turns it took, how many tokens it burned, which tools it called, whether a
# write was denied — lives in a DIFFERENT source: the Claude Code OpenTelemetry
# export (spans per turn, tool calls as child spans, tokens as span attributes).
#
# This script parses that OTel trace and rolls it up. It never touches Prometheus
# — that is deliberate. When you ask "did the agent overstep?", Prometheus cannot
# answer; only the harness trace can. Keeping the two planes separate is the
# discipline the lesson teaches, and this script is the harness-plane reader.
#
# Trace shape (fixtures/runs/otel-trace-*.json): a resource block plus spans,
# where name=="turn" spans carry input/output tokens and name=="tool" spans are
# children carrying {tool, target, decision, outcome}.
#
# Usage:  harness-telemetry.sh <otel-trace.json>
#             [--field turns|tool_calls|input_tokens|output_tokens|
#                      denied_writes|side_effects|json]
#         default field: json
#
# Exit 0  -> rollup emitted
# Exit 1  -> FAIL-CLOSED: no input / not JSON / unknown field
set -euo pipefail

fail_closed() { echo "harness-telemetry: FAIL-CLOSED: $1" >&2; exit 1; }

SRC=""
FIELD="json"
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="${2:-}"; shift 2 ;;
    -*) fail_closed "unknown arg '$1'" ;;
    *) SRC="$1"; shift ;;
  esac
done
[ -n "$SRC" ] && [ -f "$SRC" ] || fail_closed "no such trace file: ${SRC:-<none>}"
TRACE="$(cat "$SRC")"
echo "$TRACE" | jq empty 2>/dev/null || fail_closed "trace is not JSON"

ROLLUP="$(echo "$TRACE" | jq '
  (.spans // []) as $s
  | ($s | map(select(.name == "turn")))  as $turns
  | ($s | map(select(.name == "tool")))  as $tools
  | {
      session: (.resource["session.id"] // "unknown"),
      config:  (.resource.config // "unknown"),
      turns:   ($turns | length),
      tool_calls: ($tools | length),
      input_tokens:  ($turns | map(.attributes.input_tokens // 0)  | add // 0),
      output_tokens: ($turns | map(.attributes.output_tokens // 0) | add // 0),
      denied_writes: ($tools | map(select(.attributes.decision == "deny")) | length),
      side_effects:  ($tools | map(select(.attributes.outcome == "side-effect")) | length)
    }')"

case "$FIELD" in
  json) echo "$ROLLUP" | jq . ;;
  turns|tool_calls|input_tokens|output_tokens|denied_writes|side_effects)
    echo "$ROLLUP" | jq -r ".$FIELD" ;;
  *) fail_closed "unknown field '$FIELD'" ;;
esac

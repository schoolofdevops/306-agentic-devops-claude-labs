#!/usr/bin/env bash
# event-validate.sh — validate an inbound automation event envelope.
#
# Unattended automation begins with a TRIGGER, and a trigger you cannot trust is
# a trigger you must not act on. Before a control loop does any work, it validates
# the event envelope the same way a web endpoint validates a request body: is this
# the shape we expect, and does it carry the ONE field the whole reliability
# contract hangs on — a correlation_id?
#
# The envelope shape (a CloudEvents-style subset — the fields every event bus,
# GitHub webhook, and Alertmanager receiver can carry):
#   id             — unique id for THIS delivery (a bus may redeliver the same
#                    logical event under the same id; that is a duplicate)
#   correlation_id — the STABLE key that identifies the underlying incident across
#                    retries and redeliveries. Two deliveries of the same incident
#                    share a correlation_id even if their delivery `id` differs.
#   source         — who emitted it (ci/github-actions, alertmanager, ...)
#   type           — the event type (com.northstar.ci.incident.opened)
#   time           — RFC3339 emit time
#   subject        — the service/target the event is about
#
# Why correlation_id is the load-bearing field: idempotency, deduplication, and
# tracing all key off it. An event without a correlation_id cannot be safely
# deduplicated, so a control loop that accepted it could act twice on one incident.
# We fail closed on its absence — no correlation_id, no run.
#
# Usage:  event-validate.sh [event.json]      (or pipe JSON on stdin)
#         event-validate.sh --field correlation_id [event.json]
# Exit 0 -> valid envelope; prints "VALID: ..." (or the requested field)
# Exit 3 -> INVALID: missing/empty required field (fail closed)
# Exit 1 -> fail-closed: no input / not JSON
set -euo pipefail

FIELD=""
if [ "${1:-}" = "--field" ]; then FIELD="${2:-}"; shift 2; fi

read_input() { if [ "${1:-}" ] && [ -f "$1" ]; then cat "$1"; else cat; fi; }

EVENT="$(read_input "${1:-}")"
[ -n "$EVENT" ] || { echo "event-validate: FAIL-CLOSED: empty input" >&2; exit 1; }
echo "$EVENT" | jq empty 2>/dev/null || { echo "event-validate: FAIL-CLOSED: input is not JSON" >&2; exit 1; }

# Every required field must be a non-empty string. This is the envelope contract.
ok="$(echo "$EVENT" | jq -r '
  (.id|type=="string" and (length>0)) and
  (.correlation_id|type=="string" and (length>0)) and
  (.source|type=="string" and (length>0)) and
  (.type|type=="string" and (length>0)) and
  (.time|type=="string" and (length>0)) and
  (.subject|type=="string" and (length>0))
' 2>/dev/null)"

if [ "$ok" != "true" ]; then
  echo "INVALID: event envelope is missing a required field (id, correlation_id, source, type, time, subject must all be non-empty). No correlation_id, no run." >&2
  exit 3
fi

if [ -n "$FIELD" ]; then
  echo "$EVENT" | jq -r --arg f "$FIELD" '.[$f]'
  exit 0
fi

CID="$(echo "$EVENT" | jq -r .correlation_id)"
SRC="$(echo "$EVENT" | jq -r .source)"
echo "VALID: event from '$SRC' correlation_id='$CID' — envelope is well-formed and traceable."
exit 0

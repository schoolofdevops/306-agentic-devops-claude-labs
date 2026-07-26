#!/usr/bin/env bash
# evidence-validate.sh — validate a role's evidence handoff packet.
#
# A handoff between roles is only trustworthy if it is STRUCTURED and every
# claim has PROVENANCE. This script enforces two things on a packet read from
# stdin or a file arg:
#
#   1. STRUCTURE — the packet matches the required shape (from/to/evidence with
#      service, status, checks, hypothesis, confidence, sources; plus
#      recommendations and out_of_scope). A malformed packet is rejected: the
#      consumer must never guess at a field the producer left ambiguous.
#
#   2. PROVENANCE / contamination control — `evidence.sources` must be non-empty,
#      and `out_of_scope` must be present. A packet with a confident hypothesis
#      and NO sources is contamination: an assertion dressed as evidence. The
#      whole point of the handoff is that the next role can act without
#      re-investigating — which only holds if claims are traceable.
#
# Usage:  evidence-validate.sh [packet.json]      (or pipe JSON on stdin)
# Exit 0  -> valid, provenance present
# Exit 4  -> INVALID: structural error or missing provenance (contaminated)
# Exit 1  -> fail-closed: no input / not JSON
set -euo pipefail

read_input() {
  if [ "${1:-}" ] && [ -f "$1" ]; then cat "$1"; else cat; fi
}

PACKET="$(read_input "${1:-}")"
[ -n "$PACKET" ] || { echo "evidence-validate: FAIL-CLOSED: empty input" >&2; exit 1; }
echo "$PACKET" | jq empty 2>/dev/null || { echo "evidence-validate: FAIL-CLOSED: input is not JSON" >&2; exit 1; }

# Structural + provenance rule expressed as one jq predicate.
ok="$(echo "$PACKET" | jq -r '
  (.from_role|type=="string") and
  (.to_role|type=="string") and
  (.evidence|type=="object") and
  (.evidence.service|type=="string") and
  (.evidence.status|(.=="healthy" or . =="degraded" or . =="down")) and
  (.evidence.checks|type=="object") and
  (.evidence.hypothesis|type=="string" and (length>0)) and
  (.evidence.confidence|(. =="low" or . =="medium" or . =="high")) and
  (.evidence.sources|type=="array" and (length>0)) and
  (.recommendations|type=="array") and
  (.out_of_scope|type=="array")
' 2>/dev/null)"

if [ "$ok" = "true" ]; then
  n="$(echo "$PACKET" | jq -r '.evidence.sources|length')"
  echo "VALID: evidence packet from '$(echo "$PACKET" | jq -r .from_role)' -> '$(echo "$PACKET" | jq -r .to_role)'; hypothesis backed by $n source(s), out_of_scope declared."
  exit 0
fi

echo "INVALID: packet failed structure/provenance check — a confident claim with no sources, or a missing required field, is contamination, not evidence." >&2
exit 4

#!/usr/bin/env bash
# synthesize-hypotheses.sh — synthesize parallel investigation hypotheses without
# consensus theater.
#
# When you fan out an incident across three independent investigators — one on
# application/retry behavior, one on platform/resource pressure, one on the
# recent-change timeline — the WHOLE VALUE is that they reason independently. The
# failure mode is consensus theater: agents that saw each other's answers and
# "agree" not because the evidence converged but because they anchored on a peer's
# conclusion. An agreement built from shared anchoring is worth nothing; it looks
# like three confirmations and is really one guess echoed three times.
#
# This script reads an array of hypothesis packets (stdin or file) and synthesizes
# a verdict with three deterministic guards:
#
#   1. INDEPENDENCE — every packet must carry its own `sources` (>=1) drawn from
#      its own dimension. A packet whose `derived_from` names ANOTHER agent's
#      hypothesis instead of its own evidence is consensus theater and is
#      rejected. Independence is the precondition; without it, agreement is noise.
#
#   2. AGREEMENT vs DISAGREEMENT — packets are grouped by their `root_cause`
#      field. If independent packets converge on the same root cause, that is a
#      REAL corroboration (raise confidence). If they diverge, the synthesis
#      surfaces the disagreement instead of hiding it — a split is signal, not a
#      problem to average away.
#
#   3. MISSING EVIDENCE — if any packet reports `status: "inconclusive"` or names
#      an unchecked dimension in `missing`, the synthesis loops: it emits
#      `verdict: "need-more-evidence"` naming the gap, rather than declaring a
#      winner on partial data.
#
# Packet shape (each element of the input array):
#   {
#     "dimension": "application-retry | platform-resource | recent-change",
#     "root_cause": "short stable label, or null if inconclusive",
#     "status": "supported | refuted | inconclusive",
#     "confidence": "low | medium | high",
#     "sources": ["curl ...", "path:line", ...],   # own evidence, >=1 required
#     "derived_from": null | "another dimension"    # if set to a peer: theater
#     "missing": ["dimension not yet checked", ...]  # optional
#   }
#
# Usage:  synthesize-hypotheses.sh [packets.json]   (or pipe a JSON array on stdin)
# Exit 0  -> synthesized: prints verdict= and detail lines
# Exit 4  -> INVALID: consensus theater detected, or a packet lacks its own sources
# Exit 1  -> FAIL-CLOSED: no input / not a JSON array / fewer than 2 packets
set -euo pipefail

read_input() { if [ "${1:-}" ] && [ -f "$1" ]; then cat "$1"; else cat; fi; }

fail_closed() { echo "synthesize-hypotheses: FAIL-CLOSED: $1" >&2; exit 1; }
theater()    { echo "INVALID: $1" >&2; exit 4; }

IN="$(read_input "${1:-}")"
[ -n "$IN" ] || fail_closed "empty input"
echo "$IN" | jq -e 'type=="array"' >/dev/null 2>&1 || fail_closed "input is not a JSON array"
N="$(echo "$IN" | jq 'length')"
[ "$N" -ge 2 ] || fail_closed "need >=2 hypothesis packets to synthesize (got $N) — one agent is not parallel"

# GUARD 1 — independence. Every packet must have its own sources, and none may be
# `derived_from` a peer dimension. A packet that anchored on another agent's
# conclusion is consensus theater and poisons the whole synthesis.
theater_hit="$(echo "$IN" | jq -r '
  [ .[] | select((.derived_from != null) and (.derived_from != "")) | .dimension ] | join(",")
')"
[ -z "$theater_hit" ] || theater "consensus theater — packet(s) [$theater_hit] are derived_from a peer's hypothesis, not independent evidence. Independent agreement requires independent evidence."

unsourced="$(echo "$IN" | jq -r '
  [ .[] | select((.sources|type!="array") or (.sources|length==0)) | .dimension ] | join(",")
')"
[ -z "$unsourced" ] || theater "packet(s) [$unsourced] carry no sources of their own — an unsourced hypothesis cannot corroborate anything."

# GUARD 3 — missing evidence loop. If any packet is inconclusive or names a gap,
# do not declare a winner: name the gap and ask for another pass.
gap="$(echo "$IN" | jq -r '
  [ .[] | select(.status=="inconclusive") | .dimension ]
  + [ .[] | (.missing // [])[] ]
  | unique | join(", ")
')"
if [ -n "$gap" ]; then
  echo "verdict=need-more-evidence"
  echo "missing=$gap"
  echo "detail=synthesis withheld — a hypothesis is inconclusive or a dimension is unchecked; loop before concluding."
  exit 0
fi

# GUARD 2 — agreement vs disagreement over root_cause among SUPPORTED packets.
supported="$(echo "$IN" | jq -c '[ .[] | select(.status=="supported") ]')"
scount="$(echo "$supported" | jq 'length')"
if [ "$scount" -eq 0 ]; then
  echo "verdict=no-supported-hypothesis"
  echo "detail=every dimension refuted its hypothesis — the cause is none of the three; widen the investigation."
  exit 0
fi

causes="$(echo "$supported" | jq -r '[ .[].root_cause ] | unique | length')"
top_cause="$(echo "$supported" | jq -r '.[0].root_cause')"

if [ "$causes" -eq 1 ]; then
  echo "verdict=corroborated"
  echo "root_cause=$top_cause"
  echo "detail=$scount independent dimension(s) converged on the same root cause from their OWN evidence — real corroboration, not an echo."
  exit 0
fi

# Divergence — surface it, do not average it.
echo "verdict=disagreement"
echo "root_cause=$(echo "$supported" | jq -r '[ .[] | .dimension + "=>" + (.root_cause//"?") ] | join("; ")')"
echo "detail=independent dimensions disagree on the root cause — a split is signal. Resolve by evidence, not by majority vote."
exit 0

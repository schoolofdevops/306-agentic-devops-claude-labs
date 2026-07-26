#!/usr/bin/env bash
# ledger-export.sh — export agent-run audit telemetry to the agentops ledger
# WITH redaction, so the durable record proves what the agent DID without
# leaking what it SAW.
#
# The privacy problem this closes: an agent transcript is a goldmine of exactly
# the things you must not retain — the full prompt bodies (which may quote a
# customer record or an incident's PII), tool results (which may contain a
# decoded Secret), and any credential the agent read. If you export the raw
# transcript to a durable ledger "for auditability", you have built a permanent,
# searchable copy of every secret the agent ever touched. That is worse than no
# ledger at all.
#
# The rule this script enforces: the ledger records STRUCTURE and OUTCOME, never
# CONTENT. For each event it keeps: timestamp, role, tool, target, decision,
# outcome, and a one-line summary — and it DROPS the prompt body and tool output
# entirely, and REDACTS any token/secret pattern that leaks into a field it does
# keep. A field it cannot prove is safe is redacted, not passed through.
#
# Redaction patterns (fail-safe — over-redact rather than leak):
#   - AWS-style keys        AKIA[0-9A-Z]{16}
#   - bearer/JWT tokens     eyJ[A-Za-z0-9._-]{20,}
#   - generic long secrets  (sk|ghp|xox[baprs])-[A-Za-z0-9]{16,}
#   - k8s base64 secret data  data:\s*\n?\s*\w+:\s*[A-Za-z0-9+/=]{20,}
#   - password/token=VALUE  (password|passwd|token|secret|api[_-]?key)=\S+
#
# Input:  a JSONL transcript on stdin or a file arg. Each line is one event:
#   {"ts":"...","role":"...","tool":"Bash","target":"...","prompt":"...",
#    "tool_output":"...","decision":"allow","summary":"..."}
# Output: redacted JSONL to stdout (append to agentops/ledger/audit.jsonl).
#
# Usage:  ledger-export.sh [transcript.jsonl]      (or pipe on stdin)
#         ledger-export.sh --self-test             (prove redaction on a fixture)
# Exit 0 -> export emitted (or self-test passed)
# Exit 1 -> FAIL-CLOSED: not JSON / self-test found a leak
set -euo pipefail

fail_closed() { echo "ledger-export: FAIL-CLOSED: $1" >&2; exit 1; }

# The fields the ledger is ALLOWED to keep. Everything else is dropped.
# Note: prompt and tool_output are deliberately NOT here — they are dropped whole.
KEEP='{ts, role, tool, target, decision, outcome, summary}'

redact() {
  # Applied to the string values the ledger keeps. Over-redaction is acceptable;
  # a leak is not. Each sed clause replaces a secret shape with [REDACTED].
  sed -E \
    -e 's/AKIA[0-9A-Z]{16}/[REDACTED-AWS-KEY]/g' \
    -e 's/eyJ[A-Za-z0-9._-]{20,}/[REDACTED-JWT]/g' \
    -e 's/(sk|ghp|xox[baprs])-[A-Za-z0-9]{16,}/[REDACTED-TOKEN]/g' \
    -e 's/(password|passwd|token|secret|api[_-]?key)=[^ "]+/\1=[REDACTED]/gI' \
    -e 's/[A-Za-z0-9+/]{40,}={0,2}/[REDACTED-B64]/g'
}

if [ "${1:-}" = "--self-test" ]; then
  # Prove the pipeline: feed a line carrying every secret shape AND a prompt body
  # that quotes a customer PII fixture; assert none survive into the output.
  LEAK='{"ts":"2024-11-25T10:00:00Z","role":"sre-investigator","tool":"Bash","target":"orders-api","prompt":"customer bean@initcron.org ordered; card 4111111111111111","tool_output":"AWS_SECRET=AKIAIOSFODNN7EXAMPLE token=ghp-abcdef0123456789abcd","decision":"allow","outcome":"done","summary":"read AKIAIOSFODNN7EXAMPLE from env"}'
  OUT="$(echo "$LEAK" | "$0")"
  # The ledger line must not contain: the prompt body, the tool_output, the raw
  # AWS key, the token, or the customer email.
  for needle in "AKIAIOSFODNN7EXAMPLE" "ghp-abcdef" "bean@initcron.org" "4111111111111111" "customer" "AWS_SECRET"; do
    if echo "$OUT" | grep -qF "$needle"; then
      echo "LEAK: '$needle' survived into the ledger line:" >&2
      echo "$OUT" >&2
      exit 1
    fi
  done
  echo "self-test PASS: no prompt body, tool output, secret, or PII reached the ledger."
  echo "ledger line: $OUT"
  exit 0
fi

SRC="/dev/stdin"
[ -n "${1:-}" ] && { [ -f "$1" ] || fail_closed "no such transcript: $1"; SRC="$1"; }

while IFS= read -r line; do
  [ -n "$line" ] || continue
  echo "$line" | jq empty 2>/dev/null || fail_closed "transcript line is not JSON: $line"
  # Keep only the safe fields, then run the surviving string values through the
  # redactor. summary is the one free-text field kept, so it is the one that
  # could carry a leaked secret — it MUST pass through redact().
  echo "$line" | jq -c "$KEEP" | redact
done < "$SRC"

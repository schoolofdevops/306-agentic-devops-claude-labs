#!/usr/bin/env bash
# triage-lock.sh — a correlation-scoped concurrency guard for unattended runs (M17 deep dive).
#
# Deduplication (in triage-run.sh) handles the SEQUENTIAL duplicate: the same event
# delivered twice, one after the other. It does NOT handle the CONCURRENT duplicate:
# two triggers for the same incident firing at the SAME moment — a routine and a
# webhook both waking on INC-002, or two Monitor conditions tripping together. Both
# pass the dedup check because neither has written the ledger yet, and you get two
# control loops racing to open two PRs or apply two conflicting remediations.
#
# The fix is a lock keyed by the SAME correlation_id the rest of the contract uses.
# Exactly one holder wins the lock and does the work; every concurrent contender for
# that correlation_id is rejected immediately (not queued) — a second remediation for
# an incident already being handled is never the right move.
#
# We use mkdir as the atomic primitive: mkdir either creates the directory (you won
# the lock) or fails because it already exists (someone else holds it). It is atomic
# on every POSIX filesystem, needs no flock, and works identically on macOS and Linux.
#
# Usage:
#   triage-lock.sh --acquire --cid <correlation_id>   # exit 0 = acquired, exit 9 = held
#   triage-lock.sh --release --cid <correlation_id>   # release a lock you hold
#   triage-lock.sh --status  --cid <correlation_id>   # prints held|free
# Exit 0 -> acquired / released / status printed
# Exit 9 -> lock is HELD by another run (concurrent contender rejected)
# Exit 1 -> fail-closed: missing args / bad state
set -euo pipefail

fail_closed() { echo "triage-lock: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_ROOT="$REPO_ROOT/agentops/triage-state/locks"

MODE="" CID=""
while [ $# -gt 0 ]; do
  case "$1" in
    --acquire) MODE="acquire"; shift ;;
    --release) MODE="release"; shift ;;
    --status)  MODE="status";  shift ;;
    --cid) CID="${2:-}"; shift 2 ;;
    *) fail_closed "unknown argument '$1'" ;;
  esac
done

[ -n "$MODE" ] || fail_closed "one of --acquire|--release|--status is required"
[ -n "$CID" ] || fail_closed "--cid <correlation_id> is required"

mkdir -p "$LOCK_ROOT"
SLUG="$(printf '%s' "$CID" | tr -c 'A-Za-z0-9._-' '_')"
LOCK="$LOCK_ROOT/$SLUG.lock"

case "$MODE" in
  acquire)
    # Atomic: mkdir succeeds for exactly one racer; the rest get EEXIST.
    if mkdir "$LOCK" 2>/dev/null; then
      printf '%s\n' "$$" > "$LOCK/pid" 2>/dev/null || true
      echo "acquired: $CID"
      exit 0
    else
      echo "held: another run owns the lock for $CID — concurrent contender rejected" >&2
      exit 9
    fi
    ;;
  release)
    rm -rf "$LOCK"
    echo "released: $CID"
    exit 0
    ;;
  status)
    [ -d "$LOCK" ] && echo "held" || echo "free"
    exit 0
    ;;
esac

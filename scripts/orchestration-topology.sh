#!/usr/bin/env bash
# orchestration-topology.sh — deterministic orchestration decision table.
#
# The hardest choice in multi-agent work is not "which model" — Module 9 settled
# that — it is "how do these agents relate to each other." Do you spawn a
# subagent and wait? Fork and keep chatting? Fan out a workflow and join? This
# script encodes the decision table from the lesson as a FIXED FUNCTION of four
# facts about the task, so the choice is a rule you can audit, not a vibe.
#
# The four facts (answered yes/no):
#   interactive   — is a human waiting on this turn's result?  (y/n)
#   parallel      — are there 2+ INDEPENDENT sub-tasks to run at once?  (y/n)
#   deterministic — must the orchestration be reproducible / scriptable
#                   (same steps, same order, in CI)?  (y/n)
#   longrunning   — does the work outlive the current turn (minutes+/unattended)? (y/n)
#
# It maps those to exactly one topology and prints a one-line rationale:
#   skill | subagent | fork | workflow | background | headless | routine | team
#
# Usage:  orchestration-topology.sh <interactive> <parallel> <deterministic> <longrunning>
#         each arg ∈ { y, n }
#
# Exit 0  -> a topology was chosen (printed on stdout)
# Exit 1  -> FAIL-CLOSED: an argument was missing or not y/n — the table does not
#            guess a topology from an ambiguous task shape.
#
# This is the "choose the shape before you build it" discipline made runnable:
# the wrong topology (a subagent where you needed a fork, a team where a workflow
# would do) is the #1 source of orchestration chaos, and it is a decision you can
# get right deterministically.
set -euo pipefail

fail_closed() {
  echo "orchestration-topology: FAIL-CLOSED: $1" >&2
  exit 1
}

norm() {
  case "$(printf '%s' "$1" | tr 'A-Z' 'a-z')" in
    y|yes|true|1) echo y ;;
    n|no|false|0) echo n ;;
    *) fail_closed "argument '$1' is not y/n (task shape must be unambiguous)" ;;
  esac
}

[ $# -eq 4 ] || fail_closed "need 4 args: <interactive> <parallel> <deterministic> <longrunning> (each y/n)"

I="$(norm "$1")"   # interactive: human waiting?
P="$(norm "$2")"   # parallel: 2+ independent sub-tasks?
D="$(norm "$3")"   # deterministic: must be reproducible/scriptable?
L="$(norm "$4")"   # longrunning: outlives this turn?

# The decision table. Order matters: the most specific, highest-stakes
# distinctions are tested first, so each task shape resolves to exactly one row.
choose() {
  # Reproducible, scriptable orchestration always wins — determinism is a
  # property you cannot get from an interactive agent improvising.
  if [ "$D" = y ] && [ "$P" = y ]; then
    echo "workflow|deterministic fan-out/join over multiple agents — same steps, same order, runnable in CI"
    return
  fi
  if [ "$D" = y ] && [ "$L" = y ]; then
    echo "routine|scheduled/event-driven, reproducible, unattended — a workflow on a trigger"
    return
  fi
  if [ "$D" = y ] && [ "$I" = n ]; then
    echo "headless|single unattended CLI invocation (claude -p) — scriptable, one shot, no human in the loop"
    return
  fi

  # Not primarily deterministic — interactive orchestration.
  if [ "$I" = y ] && [ "$P" = y ]; then
    echo "fork|parallel exploration while the human keeps chatting — forks share parent context, parent stays live"
    return
  fi
  if [ "$I" = y ] && [ "$L" = y ]; then
    echo "background|long-running work started from an interactive session — parent does not block on it"
    return
  fi
  if [ "$I" = y ]; then
    echo "subagent|interactive parent delegates one bounded job to a child and waits for its return"
    return
  fi

  # Non-interactive, non-deterministic, long-running collaboration among agents.
  if [ "$L" = y ] && [ "$P" = y ]; then
    echo "team|persistent multi-agent collaboration with shared, evolving state over time"
    return
  fi

  # The base case: one agent, packaged instructions, no orchestration at all.
  echo "skill|a single agent with packaged instructions — no second agent is needed"
}

RESULT="$(choose)"
TOPOLOGY="${RESULT%%|*}"
WHY="${RESULT#*|}"

printf 'topology=%s\n' "$TOPOLOGY"
printf 'why=%s\n' "$WHY"
exit 0

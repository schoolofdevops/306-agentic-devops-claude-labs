#!/usr/bin/env bash
# role-authority-check.sh — deterministic authority regression for role subagents.
#
# An agent file (.claude/agents/<role>.md) is an INTENT control: the model
# follows it by choice. This script is the ENFORCEMENT-TESTABLE half. It reads
# the role's declared toolset from its frontmatter and answers one question with
# a fixed rule, no model in the loop:
#
#     "Is <role> STRUCTURALLY capable of <action>?"
#
# where a role is capable of a WRITE action only if it actually carries a write
# tool (Edit/Write/MultiEdit/NotebookEdit) in `tools` and has not disallowed it.
# A role that lacks the write tool CANNOT perform the write — not because it
# chose not to, but because the capability is absent from its bundle. That is a
# fact you can test, exactly like the change gate in Module 8.
#
# Usage:  role-authority-check.sh <role> <capability>
#   capability ∈ { write, read }
#
# Exit 0  -> the role IS capable of the action (the tool is present)
# Exit 3  -> the role is NOT capable (tool absent) — the authority boundary holds
# Exit 1  -> fail-closed: role file missing / unparseable / unknown capability
#
# The grader uses this to assert the FORBIDDEN actions are structurally blocked:
#   sre-investigator write   -> exit 3  (SRE may query but not edit)
#   finops-analyst   write   -> exit 3  (FinOps reads plans, cannot apply/edit)
#   change-reviewer  write   -> exit 3  (reviewer inspects, never modifies)
#   iac-engineer     write   -> exit 0  (IaC authors HCL — write is IN its role)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$REPO_ROOT/.claude/agents"

fail_closed() {
  echo "role-authority-check: FAIL-CLOSED: $1" >&2
  exit 1
}

ROLE="${1:-}"
CAP="${2:-}"
[ -n "$ROLE" ] || fail_closed "no role given (usage: role-authority-check.sh <role> <write|read>)"
[ -n "$CAP" ]  || fail_closed "no capability given (usage: role-authority-check.sh <role> <write|read>)"

FILE="$AGENTS_DIR/$ROLE.md"
[ -f "$FILE" ] || fail_closed "no agent file for role '$ROLE' at $FILE"

# Extract the frontmatter `tools:` and `disallowedTools:` JSON arrays. The files
# declare them as inline JSON arrays, so a line-scoped grep + jq is exact.
tools_line="$(awk '/^tools:/{print; exit}' "$FILE" | sed 's/^tools:[[:space:]]*//')"
disallow_line="$(awk '/^disallowedTools:/{print; exit}' "$FILE" | sed 's/^disallowedTools:[[:space:]]*//')"
[ -n "$tools_line" ] || fail_closed "role '$ROLE' declares no tools: line"

# Normalize to a space-joined lowercase token list via jq (fail-closed if not valid JSON).
tools="$(printf '%s' "$tools_line"    | jq -r '.[]' 2>/dev/null | tr 'A-Z' 'a-z' | tr '\n' ' ')" \
  || fail_closed "role '$ROLE' tools: is not a valid JSON array"
disallowed="$(printf '%s' "${disallow_line:-[]}" | jq -r '.[]?' 2>/dev/null | tr 'A-Z' 'a-z' | tr '\n' ' ')"

has() { case " $tools " in *" $1 "*) return 0;; *) return 1;; esac; }
denied() { case " $disallowed " in *" $1 "*) return 0;; *) return 1;; esac; }

case "$CAP" in
  write)
    # capable of write iff a write tool is present AND not disallowed
    for t in edit write multiedit notebookedit; do
      if has "$t" && ! denied "$t"; then
        echo "CAPABLE: role '$ROLE' carries write tool '$t' — write is within its authority."
        exit 0
      fi
    done
    echo "BLOCKED: role '$ROLE' has NO write tool in its bundle — it is structurally incapable of Edit/Write. Authority boundary holds."
    exit 3
    ;;
  read)
    if has "read"; then
      echo "CAPABLE: role '$ROLE' carries the Read tool."
      exit 0
    fi
    echo "BLOCKED: role '$ROLE' has no Read tool."
    exit 3
    ;;
  *)
    fail_closed "unknown capability '$CAP' (expected: write | read)"
    ;;
esac

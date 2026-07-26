#!/usr/bin/env bash
# role-bundle-summary.sh — print the specialist team as a single table.
#
# For each .claude/agents/<role>.md, show the enforcement-relevant facts of its
# bundle: model, whether it carries a write tool (writer), and its turn budget
# from contracts/authority-matrix.yaml. This is the "assemble the team" view —
# one row per role, so you can read the whole authority posture at a glance.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AGENTS_DIR="$REPO_ROOT/.claude/agents"

printf '%-20s %-8s %-8s %-12s %s\n' "ROLE" "MODEL" "WRITER" "TURN_BUDGET" "READONLY_BY_BUNDLE"
printf '%-20s %-8s %-8s %-12s %s\n' "----" "-----" "------" "-----------" "------------------"

for f in "$AGENTS_DIR"/*.md; do
  role="$(basename "$f" .md)"
  model="$(awk -F': *' '/^model:/{print $2; exit}' "$f")"
  tools_line="$(awk '/^tools:/{sub(/^tools:[[:space:]]*/,""); print; exit}' "$f")"
  disallow_line="$(awk '/^disallowedTools:/{sub(/^disallowedTools:[[:space:]]*/,""); print; exit}' "$f")"
  tools="$(printf '%s' "$tools_line" | jq -r '.[]' 2>/dev/null | tr 'A-Z' 'a-z' | tr '\n' ' ')"
  disallowed="$(printf '%s' "${disallow_line:-[]}" | jq -r '.[]?' 2>/dev/null | tr 'A-Z' 'a-z' | tr '\n' ' ')"
  writer="no"
  for t in edit write multiedit notebookedit; do
    case " $tools " in *" $t "*)
      case " $disallowed " in *" $t "*) ;; *) writer="yes";; esac ;;
    esac
  done
  budget="$(python3 -c "import yaml;d=yaml.safe_load(open('$REPO_ROOT/contracts/authority-matrix.yaml')).get('role_bundles',{});print(d.get('$role',{}).get('turn_budget','?'))" 2>/dev/null)"
  ro=$([ "$writer" = "no" ] && echo "yes (no write tool)" || echo "no (Git-only writer)")
  printf '%-20s %-8s %-8s %-12s %s\n' "$role" "$model" "$writer" "$budget" "$ro"
done

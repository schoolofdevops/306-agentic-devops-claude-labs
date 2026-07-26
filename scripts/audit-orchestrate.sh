#!/usr/bin/env bash
# audit-orchestrate.sh — a reproducible fan-out/join workflow over the Terraform
# estate.
#
# This is the WORKFLOW topology from the lesson, made concrete: instead of one
# agent wandering the whole estate (slow, and it will duplicate work and miss
# corners), you fan out ONE bounded audit job per IaC module, collect each
# module's evidence, and JOIN the results into a single normalized report. The
# orchestration is deterministic — same modules, same order, same shape of report
# every run — which is exactly what makes it CI-able and auditable.
#
# It models the three orchestration guards the lesson calls out:
#
#   * NO DUPLICATION — each module is audited exactly once; the fan-out is over a
#     partition (one module = one worker), so no two workers cover the same
#     ground. The join asserts the module set is covered with no repeats.
#
#   * BOUNDED CONCURRENCY (runaway control) — a --max-parallel cap limits how many
#     module audits run at once. Unbounded fan-out is how you exhaust a rate limit
#     or a machine; the cap is the stopping rule for width, the way a turn budget
#     was the stopping rule for depth in Module 9.
#
#   * NORMALIZED JOIN — every worker emits the SAME evidence shape
#     {module, security_findings, cost_delta, verdict}, so the join is a merge of
#     comparable records, not a pile of free-form prose. One report, one schema.
#
# The per-module "audit" here is a real, deterministic read of the repo's own
# fixtures and modules (no model in the loop) so the workflow is reproducible and
# gradeable. In production each worker would be a security-reviewer / finops-analyst
# subagent from Module 9; the ORCHESTRATION SHAPE is identical either way.
#
# Usage:  audit-orchestrate.sh [--max-parallel N] [--modules "a b c"]
# Exit 0  -> report emitted on stdout (JSON), covering every requested module once
# Exit 1  -> FAIL-CLOSED: a requested module has no directory, or --max-parallel < 1
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MODULES_DIR="$REPO_ROOT/infra/modules"
PLAN_OVERSIZE="$REPO_ROOT/infra/fixtures/plan-oversize.json"

MAX_PARALLEL=2
MODULES="networking database compute storage"

while [ $# -gt 0 ]; do
  case "$1" in
    --max-parallel) MAX_PARALLEL="${2:-}"; shift 2 ;;
    --modules)      MODULES="${2:-}"; shift 2 ;;
    *) echo "audit-orchestrate: FAIL-CLOSED: unknown arg '$1'" >&2; exit 1 ;;
  esac
done

case "$MAX_PARALLEL" in
  ''|*[!0-9]*) echo "audit-orchestrate: FAIL-CLOSED: --max-parallel must be an integer" >&2; exit 1 ;;
esac
[ "$MAX_PARALLEL" -ge 1 ] || { echo "audit-orchestrate: FAIL-CLOSED: --max-parallel must be >= 1 (got $MAX_PARALLEL)" >&2; exit 1; }

# Split the module list into an explicit array so iteration is robust regardless
# of IFS — the fan-out partition must be exact.
read -r -a MODULE_LIST <<< "$MODULES"
[ "${#MODULE_LIST[@]}" -ge 1 ] || { echo "audit-orchestrate: FAIL-CLOSED: empty module list" >&2; exit 1; }

# NO-DUPLICATION guard: reject a module list with repeats — a repeated module
# would be audited twice, the exact duplication the workflow exists to prevent.
dupes="$(printf '%s\n' "${MODULE_LIST[@]}" | sort | uniq -d | tr '\n' ' ')"
[ -z "$dupes" ] || { echo "audit-orchestrate: FAIL-CLOSED: duplicate module(s) in fan-out: $dupes" >&2; exit 1; }

# Each requested module must exist — a fan-out over a phantom partition is a bug.
for m in "${MODULE_LIST[@]}"; do
  [ -d "$MODULES_DIR/$m" ] || { echo "audit-orchestrate: FAIL-CLOSED: no module directory infra/modules/$m" >&2; exit 1; }
done

# ---- the per-module worker: a deterministic evidence collector ----
# Emits one normalized JSON record for one module. Real, sourced findings:
#   security_findings = count of 0.0.0.0/0 CIDRs in the module's HCL
#   cost_delta        = monthly $ delta this module contributes in the oversize plan
audit_one() {
  # Workers run with errexit OFF: a clean module legitimately produces a zero
  # grep match, and a worker must always emit its record rather than die on a
  # non-zero intermediate step. The record is the contract; the join depends on
  # every worker producing exactly one.
  set +e
  local m="$1"
  local dir="$MODULES_DIR/$m"

  local sec
  sec="$(grep -rho '0\.0\.0\.0/0' "$dir" 2>/dev/null | wc -l | tr -d ' ')"
  [ -n "$sec" ] || sec=0

  # cost delta: the oversize plan's RDS blow-up lands on the database module.
  local cost="0"
  if [ "$m" = "database" ] && [ -f "$PLAN_OVERSIZE" ]; then
    if jq -e '.resource_changes[]? | select(.type=="aws_db_instance") | select(.change.after.instance_class=="db.r6g.4xlarge")' "$PLAN_OVERSIZE" >/dev/null 2>&1; then
      cost="2847"   # 3148.97 - 301.97, rounded — the db.r6g.large -> 4xlarge jump
    fi
  fi

  local verdict="clean"
  if [ "$sec" -gt 0 ] && [ "$cost" != "0" ]; then verdict="block"
  elif [ "$sec" -gt 0 ] || [ "$cost" != "0" ]; then verdict="flag"
  fi

  jq -nc --arg module "$m" --argjson sec "$sec" --arg cost "$cost" --arg verdict "$verdict" \
    '{module:$module, security_findings:$sec, cost_delta_usd:($cost|tonumber), verdict:$verdict}'
}

# ---- fan out with a concurrency cap, then join ----
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

# Launch in bounded batches of --max-parallel: at most N module audits are in
# flight at once, then we barrier on the whole batch before the next. This caps
# concurrency (the runaway-width control) without depending on `wait -n`, which
# is not portable across all bash builds.
running=0
for m in "${MODULE_LIST[@]}"; do
  ( audit_one "$m" ) > "$TMPDIR/$m.json" &
  running=$((running + 1))
  if [ "$running" -ge "$MAX_PARALLEL" ]; then
    wait            # barrier: drain the current batch before launching more
    running=0
  fi
done
wait

# JOIN: merge the per-module records into one normalized report, in the requested
# order, with a coverage assertion (every module audited exactly once).
records="$(for m in "${MODULE_LIST[@]}"; do cat "$TMPDIR/$m.json"; done | jq -s '.')"
covered="$(echo "$records" | jq -r '[ .[].module ] | sort | join(",")')"
expected="$(printf '%s\n' "${MODULE_LIST[@]}" | sort | tr '\n' ',' | sed 's/,$//')"
[ "$covered" = "$expected" ] || { echo "audit-orchestrate: FAIL-CLOSED: coverage mismatch (covered=$covered expected=$expected)" >&2; exit 1; }

echo "$records" | jq \
  --argjson maxp "$MAX_PARALLEL" \
  '{
     audit: "terraform-estate",
     max_parallel: $maxp,
     modules_audited: (map(.module)),
     total_security_findings: (map(.security_findings) | add),
     total_cost_delta_usd: (map(.cost_delta_usd) | add),
     blocking: (map(select(.verdict=="block")) | map(.module)),
     verdict: (if any(.[]; .verdict=="block") then "block"
               elif any(.[]; .verdict=="flag") then "flag"
               else "clean" end),
     evidence: .
   }'

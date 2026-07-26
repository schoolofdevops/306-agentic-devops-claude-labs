#!/usr/bin/env bash
# change-pipeline.sh — the specialist HANDOFF CHAIN as a deterministic pipeline.
#
# Module 10 taught the pipeline topology: IaC Engineer -> Security -> FinOps ->
# Change Reviewer, each producing a structured evidence packet the next consumes.
# This script runs that chain over a Terraform plan JSON (+ optional cost pair)
# and JOINS the four packets into ONE change verdict. No model is in the loop —
# each stage is the deterministic analyzer for that role — so the pipeline is
# reproducible and gradeable, and the ORCHESTRATION SHAPE is exactly the one a
# real subagent chain would use.
#
# The join rule is fail-closed on the STRONGEST objection: if any stage says
# block, the change is blocked; a stateful replacement (no clean rollback) also
# blocks. A change ships only when every stage clears it. One dissent stops the
# line — that is the whole point of a review chain.
#
# Stages (each a script already in this repo):
#   1. iac-engineer     -> plan-analyze.sh      (replacements, blast radius)
#   2. security-reviewer-> tf-security-scan.sh   (0.0.0.0/0, public, sensitive)
#   3. finops-analyst   -> cost-compare.sh       (delta, >2x drivers)   [if cost pair given]
#   4. change-reviewer  -> rollback-review.sh    (reversibility)  + JOIN
#
# Usage:  change-pipeline.sh <plan.json> [<baseline-cost.json> <proposed-cost.json>]
#             [--field verdict|blockers|json]
#         default field: json
#
# Exit 0  -> pipeline verdict emitted (verdict may still be "block" — that is a
#            successful REVIEW, not a script error)
# Exit 1  -> FAIL-CLOSED: bad input / a stage could not evaluate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fail_closed() { echo "change-pipeline: FAIL-CLOSED: $1" >&2; exit 1; }

PLAN=""; BASE=""; PROP=""; FIELD="json"
POS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --field) FIELD="${2:-}"; shift 2 ;;
    -*) fail_closed "unknown arg '$1'" ;;
    *) POS+=("$1"); shift ;;
  esac
done
PLAN="${POS[0]:-}"; BASE="${POS[1]:-}"; PROP="${POS[2]:-}"
[ -n "$PLAN" ] && [ -f "$PLAN" ] || fail_closed "no such plan file: $PLAN"

# --- stage 1: IaC engineer — structural analysis ---
IAC="$(bash "$SCRIPT_DIR/plan-analyze.sh" "$PLAN" --field json)" || fail_closed "plan-analyze failed"
# --- stage 2: security reviewer ---
SEC="$(bash "$SCRIPT_DIR/tf-security-scan.sh" "$PLAN" --field json)" || fail_closed "tf-security-scan failed"
# --- stage 4 input: change reviewer — rollback viability ---
ROLL="$(bash "$SCRIPT_DIR/rollback-review.sh" "$PLAN" --field json)" || fail_closed "rollback-review failed"
# --- stage 3: finops (only if a cost pair was supplied) ---
if [ -n "$BASE" ] && [ -n "$PROP" ]; then
  [ -f "$BASE" ] && [ -f "$PROP" ] || fail_closed "cost files not found: $BASE / $PROP"
  FIN="$(bash "$SCRIPT_DIR/cost-compare.sh" "$BASE" "$PROP" --field json)" || fail_closed "cost-compare failed"
else
  FIN='{"verdict":"skipped","delta_monthly":null,"drivers":[]}'
fi

# --- JOIN: one change verdict from the four packets. Fail-closed on any block. ---
REPORT="$(jq -n \
  --argjson iac "$IAC" --argjson sec "$SEC" --argjson fin "$FIN" --argjson roll "$ROLL" '
  # collect a blocker line for every stage that objects.
  ( [ if $iac.verdict  == "block" then "iac: " + ($iac.stateful_replaced | join(", ")) else empty end ]
  + [ if $sec.verdict  == "block" then "security: sensitive/public exposure" else empty end ]
  + [ if $fin.verdict  == "block" then "finops: cost > threshold (" + (($fin.drivers // []) | map(.resource) | join(", ")) + ")" else empty end ]
  + [ if $roll.reversible == false then "rollback: " + $roll.reason else empty end ]
  ) as $blockers
  | {
      stages: {
        iac_engineer:     { verdict: $iac.verdict, blast_radius: $iac.blast_radius, stateful_replaced: $iac.stateful_replaced },
        security_reviewer:{ verdict: $sec.verdict, wide_open_cidrs: $sec.wide_open_cidrs, sensitive_exposed: $sec.sensitive_exposed },
        finops_analyst:   { verdict: $fin.verdict, delta_monthly: $fin.delta_monthly },
        change_reviewer:  { reversible: $roll.reversible, verdict: $roll.verdict }
      },
      blockers: $blockers,
      verdict: (if ($blockers | length) > 0 then "block" else "approve" end)
    }
')"

case "$FIELD" in
  json)     echo "$REPORT" | jq . ;;
  verdict)  echo "$REPORT" | jq -r '.verdict' ;;
  blockers) echo "$REPORT" | jq -r '.blockers[]?' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|blockers|json)" ;;
esac

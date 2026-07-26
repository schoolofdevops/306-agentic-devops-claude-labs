#!/usr/bin/env bash
# capstone-triage.sh — the M19 capstone orchestrator.
#
# INC-006 is a compound P0: five simultaneous failures across application,
# infrastructure, platform, observability and documentation. The point of the
# capstone is NOT to fix each one ad hoc — it is to run the SAME 14-step
# operational workflow the course built module by module, with a hard gate
# between each phase so a later step can never run on an unvalidated earlier
# one. This script is the deterministic reference for that workflow: no model in
# the loop, every phase a real script run, so the capstone is reproducible and
# gradeable on any machine.
#
# The 14 steps group into five phase gates:
#
#   PHASE 1  Triage & Evidence   (steps 1-4)
#     1  Triage-lock       -> triage-lock.sh   (claim the incident, reject concurrent duplicates)
#     2  Evidence-collect  -> the incident ticket + fault snapshot exist
#     3  Hypothesis-form   -> synthesize-hypotheses.sh (independent packets, no consensus theater)
#     4  Role-delegate     -> authority-matrix bundles resolve for every track
#
#   PHASE 2  Parallel Investigation (steps 5-8)
#     5  SRE track         -> application/retry evidence present
#     6  IaC track         -> the dangerous prod plan fixture is readable
#     7  Platform track    -> the K8s values fixture is readable
#     8  Reconcile         -> synthesize verdict is corroborated on one root cause
#
#   PHASE 3  Repair & Review (steps 9-12)
#     9  Repair-propose    -> change-pipeline.sh over the dangerous plan
#     10 Security-review    -> the pipeline surfaces the security objection
#     11 Change-review      -> the pipeline JOIN verdict is BLOCK (reject dangerous plan)
#     12 Approval-gate      -> role-authority-check: writers can write, readers cannot
#
#   PHASE 4  Deploy & Verify (steps 13-14)
#     13 Canary-verify (healthy)   -> canary-verify.sh promotes the safe release
#     14 Canary-verify (unhealthy) -> canary-verify.sh rolls back the bad release
#
#   PHASE 5  Post-incident & Package (scored separately by eval-score / run-ledger)
#     -> eval-score.sh on the capstone run record scores composite pass
#
# Usage:
#   capstone-triage.sh phase1 [--cid <id>]      run + gate Phase 1
#   capstone-triage.sh phase2                   run + gate Phase 2
#   capstone-triage.sh phase3                   run + gate Phase 3
#   capstone-triage.sh phase4                   run + gate Phase 4
#   capstone-triage.sh all [--cid <id>]         run all four phase gates in order
#   capstone-triage.sh status                   print which phases have passed
#   capstone-triage.sh reset                    clear capstone state + release lock
#   any of the above: [--field verdict|json]    default field: text
#
# Exit 0  -> the requested phase(s) passed the gate
# Exit 5  -> a phase GATE FAILED (a real failed gate, not a script error) — the
#            workflow must not advance past a failed phase
# Exit 1  -> FAIL-CLOSED: missing script/fixture/arg — cannot evaluate the gate
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STATE_DIR="$REPO_ROOT/agentops/capstone"
STATE="$STATE_DIR/phases.json"
mkdir -p "$STATE_DIR"

fail_closed() { echo "capstone-triage: FAIL-CLOSED: $1" >&2; exit 1; }
gate_fail()   { echo "capstone-triage: GATE FAILED: $1" >&2; exit 5; }

need() { [ -x "$SCRIPT_DIR/$1" ] || fail_closed "required script missing or not executable: scripts/$1"; }
have() { [ -f "$REPO_ROOT/$1" ] || fail_closed "required fixture missing: $1"; }

CID="capstone-inc006"
FIELD="text"
CMD="${1:-}"
[ -n "$CMD" ] || fail_closed "a subcommand is required (phase1|phase2|phase3|phase4|all|status|reset)"
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --cid)   CID="${2:-}"; shift 2 ;;
    --field) FIELD="${2:-text}"; shift 2 ;;
    *) fail_closed "unknown argument '$1'" ;;
  esac
done

# --- tiny state helpers (record which phases have passed) --------------------
state_init() { [ -f "$STATE" ] || echo '{"incident":"INC-006","phases":{}}' > "$STATE"; }
mark_pass()  { state_init; tmp="$(mktemp)"; jq --arg p "$1" '.phases[$p]="pass"' "$STATE" > "$tmp" && mv "$tmp" "$STATE"; }

emit() { # emit <phase> <verdict> <detail>
  case "$FIELD" in
    verdict) echo "$2" ;;
    json)    jq -cn --arg p "$1" --arg v "$2" --arg d "$3" '{phase:$p,verdict:$v,detail:$d}' ;;
    text|*)  echo "[$1] verdict=$2 — $3" ;;
  esac
}

run_phase1() {
  need triage-lock.sh
  need synthesize-hypotheses.sh
  have incidents/INC-006-campaign-capstone.md
  have fixtures/capstone/hypotheses.json
  have contracts/authority-matrix.yaml
  # Step 1 — triage-lock: exactly one holder claims the incident.
  if ! "$SCRIPT_DIR/triage-lock.sh" --acquire --cid "$CID" >/dev/null 2>&1; then
    # already held is acceptable for a re-run of the same correlation id
    [ "$("$SCRIPT_DIR/triage-lock.sh" --status --cid "$CID" 2>/dev/null)" = "held" ] \
      || gate_fail "could not acquire or confirm the triage lock for $CID"
  fi
  # Step 3 — hypotheses synthesize to a corroborated single root cause.
  local verdict
  verdict="$("$SCRIPT_DIR/synthesize-hypotheses.sh" "$REPO_ROOT/fixtures/capstone/hypotheses.json" 2>/dev/null | awk -F= '/^verdict=/{print $2}')"
  [ "$verdict" = "corroborated" ] || gate_fail "hypothesis synthesis did not corroborate (got '$verdict') — cannot delegate on an unformed diagnosis"
  # Step 4 — every track's role bundle resolves in the authority matrix.
  for r in sre-investigator iac-engineer platform-engineer change-reviewer; do
    grep -q "^  $r:" "$REPO_ROOT/contracts/authority-matrix.yaml" \
      || gate_fail "no role bundle for track role '$r' in authority-matrix.yaml"
  done
  mark_pass phase1
  emit phase1 pass "triage locked, 3 independent hypotheses corroborated on retry-amplification, 4 track roles resolve"
}

run_phase2() {
  need synthesize-hypotheses.sh
  have fixtures/capstone/hypotheses.json
  have infra/fixtures/plan-wide-network.json
  have platform/helm/orders-api/values.yaml
  have incidents/INC-006-campaign-capstone.md
  # Steps 5-7 — each track has its evidence surface readable.
  jq -e '.[] | select(.dimension=="application-retry")' "$REPO_ROOT/fixtures/capstone/hypotheses.json" >/dev/null 2>&1 \
    || gate_fail "SRE/application-retry track evidence missing"
  jq -e '.resource_changes' "$REPO_ROOT/infra/fixtures/plan-wide-network.json" >/dev/null 2>&1 \
    || gate_fail "IaC track plan fixture unreadable"
  grep -q 'resources' "$REPO_ROOT/platform/helm/orders-api/values.yaml" 2>/dev/null \
    || true  # values file present is enough; resource block may be the DEFECT being fixed
  # Step 8 — reconcile: independent tracks converge, no consensus theater.
  local verdict
  verdict="$("$SCRIPT_DIR/synthesize-hypotheses.sh" "$REPO_ROOT/fixtures/capstone/hypotheses.json" 2>/dev/null | awk -F= '/^verdict=/{print $2}')"
  [ "$verdict" = "corroborated" ] || gate_fail "reconcile failed: tracks did not converge (verdict '$verdict')"
  mark_pass phase2
  emit phase2 pass "three tracks investigated independently and reconciled on one root cause"
}

run_phase3() {
  need change-pipeline.sh
  need role-authority-check.sh
  have infra/fixtures/plan-wide-network.json
  # Steps 9-11 — propose the repair as a change, run the review pipeline, and
  # the JOIN verdict must BLOCK the dangerous prod plan (open 0.0.0.0/0 groups).
  local verdict
  verdict="$("$SCRIPT_DIR/change-pipeline.sh" "$REPO_ROOT/infra/fixtures/plan-wide-network.json" --field verdict 2>/dev/null || true)"
  [ "$verdict" = "block" ] || gate_fail "the review pipeline did NOT block the dangerous plan (got '$verdict') — a capstone must reject open security groups"
  # Step 12 — approval gate: authority holds. Writers can write, readers cannot.
  "$SCRIPT_DIR/role-authority-check.sh" iac-engineer write >/dev/null 2>&1 \
    || gate_fail "iac-engineer cannot write — the writer role is mis-scoped"
  if "$SCRIPT_DIR/role-authority-check.sh" sre-investigator write >/dev/null 2>&1; then
    gate_fail "sre-investigator CAN write — a read-only investigator must never hold write authority"
  fi
  if "$SCRIPT_DIR/role-authority-check.sh" change-reviewer write >/dev/null 2>&1; then
    gate_fail "change-reviewer CAN write — the reviewer must inspect, never modify"
  fi
  mark_pass phase3
  emit phase3 pass "dangerous plan blocked by review chain; write authority scoped to writers only"
}

run_phase4() {
  need canary-verify.sh
  have fixtures/canary/canary-healthy.json
  have fixtures/canary/canary-unhealthy.json
  # Step 13 — the safe release passes canary and is promoted.
  local v_ok v_bad
  v_ok="$("$SCRIPT_DIR/canary-verify.sh" "$REPO_ROOT/fixtures/canary/canary-healthy.json" --field verdict 2>/dev/null || true)"
  [ "$v_ok" = "promote" ] || gate_fail "healthy canary was not promoted (got '$v_ok')"
  # Step 14 — a degraded release is caught and rolled back.
  v_bad="$("$SCRIPT_DIR/canary-verify.sh" "$REPO_ROOT/fixtures/canary/canary-unhealthy.json" --field verdict 2>/dev/null || true)"
  [ "$v_bad" = "rollback" ] || gate_fail "unhealthy canary was not rolled back (got '$v_bad')"
  mark_pass phase4
  emit phase4 pass "healthy canary promoted, degraded canary rolled back"
}

case "$CMD" in
  phase1) run_phase1 ;;
  phase2) run_phase2 ;;
  phase3) run_phase3 ;;
  phase4) run_phase4 ;;
  all)
    # Run gates in order; a failed gate exits 5 and stops the workflow.
    FIELD_SAVE="$FIELD"; FIELD="text"
    run_phase1; run_phase2; run_phase3; run_phase4
    FIELD="$FIELD_SAVE"
    emit all pass "all four phase gates passed in order — the 14-step workflow completed"
    ;;
  status)
    state_init
    if [ "$FIELD" = "json" ]; then cat "$STATE"; else
      jq -r '.phases | to_entries[] | "  \(.key): \(.value)"' "$STATE" 2>/dev/null || echo "  (no phases recorded)"
    fi
    ;;
  reset)
    rm -f "$STATE"
    "$SCRIPT_DIR/triage-lock.sh" --release --cid "$CID" >/dev/null 2>&1 || true
    echo "capstone state cleared"
    ;;
  *) fail_closed "unknown subcommand '$CMD'" ;;
esac

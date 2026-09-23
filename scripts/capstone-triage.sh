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
#   PHASE 5  Post-incident & Score (step 15)
#     15 Score-the-run   -> every track concluded independently (derived_from null)
#                           AND the capstone run record clears eval-score.sh
#
# Usage:
#   capstone-triage.sh phase1 [--cid <id>]      run + gate Phase 1
#   capstone-triage.sh phase2                   run + gate Phase 2
#   capstone-triage.sh phase3                   run + gate Phase 3
#   capstone-triage.sh phase4                   run + gate Phase 4
#   capstone-triage.sh phase5                   run + gate Phase 5
#   capstone-triage.sh all [--cid <id>]         run all five phase gates in order
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

TRACKS_DIR="$REPO_ROOT/agentops/capstone/tracks"

# The gates read the LEARNER'S evidence, never the shipped fixture. When the
# tracks are absent this FAILS CLOSED rather than falling back — a gate that
# quietly substitutes the shipped answer is measuring the fixture, which is the
# one thing a capstone must not do. fixtures/capstone/hypotheses.json remains as
# the worked reference for the deep dive; no gate reads it.
learner_tracks() {
  local n
  n="$(ls "$TRACKS_DIR"/*.json 2>/dev/null | wc -l | tr -d ' ')"
  [ "${n:-0}" -ge 3 ] || fail_closed "expected 3 track packets in agentops/capstone/tracks/, found ${n:-0} — run the three investigator tracks first (Part I). These gates score YOUR evidence, not fixtures/capstone/hypotheses.json"
  jq -s '.' "$TRACKS_DIR"/*.json 2>/dev/null || fail_closed "a packet in agentops/capstone/tracks/ is not valid JSON"
}

CID="capstone-inc006"
FIELD="text"
CMD="${1:-}"
[ -n "$CMD" ] || fail_closed "a subcommand is required (phase1|phase2|phase3|phase4|phase5|all|status|reset)"
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
  have contracts/authority-matrix.yaml
  # Step 1 — triage-lock: exactly one holder claims the incident.
  if ! "$SCRIPT_DIR/triage-lock.sh" --acquire --cid "$CID" >/dev/null 2>&1; then
    # already held is acceptable for a re-run of the same correlation id
    [ "$("$SCRIPT_DIR/triage-lock.sh" --status --cid "$CID" 2>/dev/null)" = "held" ] \
      || gate_fail "could not acquire or confirm the triage lock for $CID"
  fi
  # Step 3 — hypotheses synthesize to a corroborated single root cause.
  local packets verdict
  packets="$(learner_tracks)"
  verdict="$(printf '%s' "$packets" | "$SCRIPT_DIR/synthesize-hypotheses.sh" 2>/dev/null | awk -F= '/^verdict=/{print $2}')"
  # INC-006 is a COMPOUND incident — five simultaneous failures with different
  # causes. Three independent investigators reaching three different conclusions
  # is the correct outcome, not a failure: a split is signal. What phase 1 gates
  # is that a diagnosis was FORMED independently, so either verdict passes here.
  # What must never pass is theater — tracks that borrowed a peer's conclusion —
  # which synthesize-hypotheses.sh reports separately and phase 5 re-checks.
  case "$verdict" in
    corroborated|disagreement) : ;;
    "") gate_fail "hypothesis synthesis produced no verdict — packets may not match contracts/hypothesis-packet.schema.json" ;;
    *)  gate_fail "tracks did not form an independent diagnosis (got '$verdict') — resolve that before delegating" ;;
  esac
  # Step 4 — every track's role bundle resolves in the authority matrix.
  for r in sre-investigator iac-engineer platform-engineer change-reviewer; do
    grep -q "^  $r:" "$REPO_ROOT/contracts/authority-matrix.yaml" \
      || gate_fail "no role bundle for track role '$r' in authority-matrix.yaml"
  done
  mark_pass phase1
  emit phase1 pass "triage locked, your 3 tracks formed independent diagnoses (verdict=$verdict), 4 track roles resolve"
}

run_phase2() {
  need synthesize-hypotheses.sh
  have infra/fixtures/plan-wide-network.json
  have platform/helm/orders-api/values.yaml
  have incidents/INC-006-campaign-capstone.md
  # Steps 5-7 — each track has its evidence surface readable.
  # Capture first: inside a pipeline, learner_tracks' fail-closed exit is masked
  # by the downstream command's status, and a missing-evidence FAIL-CLOSED would
  # be reported as a GATE FAILURE. They are different things and exit differently.
  local packets
  packets="$(learner_tracks)"
  printf '%s' "$packets" | jq -e '.[] | select(.dimension=="application-retry")' >/dev/null 2>&1 \
    || gate_fail "no application-retry packet among your tracks — the SRE track did not produce evidence"
  jq -e '.resource_changes' "$REPO_ROOT/infra/fixtures/plan-wide-network.json" >/dev/null 2>&1 \
    || gate_fail "IaC track plan fixture unreadable"
  grep -q 'resources' "$REPO_ROOT/platform/helm/orders-api/values.yaml" 2>/dev/null \
    || true  # values file present is enough; resource block may be the DEFECT being fixed
  # Step 8 — reconcile: independent tracks converge, no consensus theater.
  # Step 8 — RECONCILE. On a compound incident the tracks will not agree, and
  # making them agree is the wrong move. The gate is that YOU resolved the split
  # by evidence: a reconciliation that names which cause owns which symptom, and
  # does not quietly rewrite what a track actually concluded.
  local recon="$REPO_ROOT/agentops/capstone/reconciliation.json"
  [ -f "$recon" ] || gate_fail "no agentops/capstone/reconciliation.json — three tracks reached three conclusions and nothing resolved them. A split is signal; resolve it by evidence, not by majority vote"
  jq -e . "$recon" >/dev/null 2>&1 || gate_fail "reconciliation.json is not valid JSON"
  local dim rc claimed
  while IFS= read -r dim; do
    claimed="$(jq -r --arg d "$dim" '.causes[]? | select(.dimension==$d) | .root_cause // empty' "$recon" 2>/dev/null)"
    [ -n "$claimed" ] || gate_fail "reconciliation does not account for the '$dim' track — every dimension that reported must be resolved, including the ones you did not make primary"
    rc="$(printf '%s' "$packets" | jq -r --arg d "$dim" '.[] | select(.dimension==$d) | .root_cause')"
    [ "$claimed" = "$rc" ] || gate_fail "reconciliation records '$dim' as '$claimed' but that track concluded '$rc' — resolving a split does not mean rewriting what an investigator found"
  done < <(printf '%s' "$packets" | jq -r '.[].dimension')
  jq -e '.primary and (.basis | length > 0)' "$recon" >/dev/null 2>&1 \
    || gate_fail "reconciliation needs a 'primary' dimension and a non-empty 'basis' — name which cause you are treating as primary and why, on evidence"
  mark_pass phase2
  emit phase2 pass "three independent tracks reconciled by evidence — every dimension accounted for, none rewritten"
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

run_phase5() {
  need eval-score.sh
  need synthesize-hypotheses.sh
  have fixtures/capstone/run-capstone.json
  # Step 15 — post-incident. Two things are scored here, and only one of them is
  # about the incident.
  #
  # First: did each track reach its OWN conclusion? derived_from is null when a
  # packet concluded from its own dimension's evidence, and names a peer when it
  # borrowed. Three packets that all borrowed is one investigation wearing three
  # signatures, and it corroborates just as cleanly as three real ones.
  local packets total independent
  packets="$(learner_tracks)"
  total="$(printf '%s' "$packets" | jq 'length')"
  independent="$(printf '%s' "$packets" | jq '[.[] | select(.derived_from == null)] | length')"
  [ "$independent" -ge 3 ] \
    || gate_fail "only $independent of $total tracks reached an independent conclusion — a capstone scored on borrowed reasoning is scoring one investigation three times"
  # Second: the capstone run record clears the same five-dimension scorer M18 built.
  local v
  v="$("$SCRIPT_DIR/eval-score.sh" "$REPO_ROOT/fixtures/capstone/run-capstone.json" --field verdict 2>/dev/null || true)"
  [ "$v" = "pass" ] || gate_fail "the capstone run record did not clear eval-score (got '$v')"
  mark_pass phase5
  emit phase5 pass "$independent independent conclusions, no borrowed reasoning; capstone run record scores pass"
}

case "$CMD" in
  phase1) run_phase1 ;;
  phase2) run_phase2 ;;
  phase3) run_phase3 ;;
  phase4) run_phase4 ;;
  phase5) run_phase5 ;;
  all)
    # Run gates in order; a failed gate exits 5 and stops the workflow.
    FIELD_SAVE="$FIELD"; FIELD="text"
    run_phase1; run_phase2; run_phase3; run_phase4; run_phase5
    FIELD="$FIELD_SAVE"
    emit all pass "all five phase gates passed in order — the operational workflow completed on your evidence"
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

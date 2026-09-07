#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0

check() {
  local desc="$1"
  local result="$2"

  if [[ "$result" == "true" ]]; then
    echo -e "  ${GREEN}✓${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}✗${NC} $desc"
    FAIL=$((FAIL + 1))
  fi
}

usage() {
  echo "Usage: $0 <module>"
  echo ""
  echo "Run grading checks for a course module."
  echo ""
  echo "Examples:"
  echo "  $0 m1     # Grade Module 1 (readiness fix)"
  echo "  $0 m2     # Grade Module 2 (permission boundary & sandbox)"
  echo ""
  echo "Supported modules: m1-m19 (m8-m19 also support a <module>-deep-dive variant)"
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage
[[ $# -lt 1 ]] && { echo -e "${RED}Error: module argument required (e.g., m1)${NC}"; usage; }

MODULE="$1"

echo ""
echo -e "${BOLD}Grading: Module ${MODULE}${NC}"
echo "========================"
echo ""

case "$MODULE" in
  m1)
    echo "Checking: Readiness probe fix"
    echo ""

    CHECKS="$REPO_ROOT/labs/m1/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m1/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m2)
    echo "Checking: Permission boundary & sandbox"
    echo ""

    CHECKS="$REPO_ROOT/labs/m2/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m2/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m3)
    echo "Checking: Context engineering — scoped CLAUDE.md hierarchy + evidence contract"
    echo ""

    CHECKS="$REPO_ROOT/labs/m3/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m3/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m4)
    echo "Checking: Model, effort & cost — telemetry, ledger and budget"
    echo ""

    CHECKS="$REPO_ROOT/labs/m4/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m4/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m5)
    echo "Checking: Plan -> Execute -> Verify — the /version change under contract"
    echo ""

    CHECKS="$REPO_ROOT/labs/m5/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m5/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m6)
    echo "Checking: Skills — five runbooks as testable, named procedures"
    echo ""

    CHECKS="$REPO_ROOT/labs/m6/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m6/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m7)
    echo "Checking: Tool interface engineering — the read-only MCP observer"
    echo ""

    CHECKS="$REPO_ROOT/labs/m7/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m7/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m8)
    echo "Checking: Change Gate + Environment Contract — deterministic hook denials and fail-closed target checks"
    echo ""

    CHECKS="$REPO_ROOT/labs/m8/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m8/checks.json present" "false"
    else
      # Data-driven: each entry declares a command and the exact stdout it must
      # produce. The change gate and env-check are exercised for real here, so
      # the grader certifies the same denials the lab tested by hand.
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m8-deep-dive)
    echo "Checking: Deep Dive — the Destructive Shortcut incident is contained by enforcement"
    echo ""

    CHECKS="$REPO_ROOT/labs/m8/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m8/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m9)
    echo "Checking: The Specialist Team — role bundles, structured handoffs, and authority boundaries"
    echo ""

    CHECKS="$REPO_ROOT/labs/m9/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m9/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m9-deep-dive)
    echo "Checking: Deep Dive — authority regression: each role can do what it should and CANNOT do what it must not"
    echo ""

    CHECKS="$REPO_ROOT/labs/m9/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m9/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m10)
    echo "Checking: Orchestration Topologies — decision table, parallel-hypothesis synthesis, reproducible fan-out audit"
    echo ""

    CHECKS="$REPO_ROOT/labs/m10/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m10/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m10-deep-dive)
    echo "Checking: Deep Dive — the Terraform audit as an Agent SDK fan-out, compared to the shell workflow"
    echo ""

    CHECKS="$REPO_ROOT/labs/m10/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m10/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m11)
    echo "Checking: AI-Augmented IaC & FinOps — plan-JSON analysis, state safety, security scan, cost compare, specialist handoff chain"
    echo ""

    CHECKS="$REPO_ROOT/labs/m11/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m11/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m11-deep-dive)
    echo "Checking: Deep Dive — Cheap Prompt, Expensive Plan: the specialist chain catches all three defects in one plan"
    echo ""

    CHECKS="$REPO_ROOT/labs/m11/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m11/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m12)
    echo "Checking: Containers, Kubernetes & GitOps — container review, rendered-manifest review, cluster enforcement, and the reconciler-only change path"
    echo ""

    CHECKS="$REPO_ROOT/labs/m12/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m12/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m12-deep-dive)
    echo "Checking: Deep Dive — The Failed Rollout: separating app health, probe config, rollout state, routing, and resource pressure"
    echo ""

    CHECKS="$REPO_ROOT/labs/m12/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m12/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m13)
    echo "Checking: CI/CD & Release Engineering — headless analysis, hermetic verdict, separation of duties, and canary verification"
    echo ""

    CHECKS="$REPO_ROOT/labs/m13/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m13/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m13-deep-dive)
    echo "Checking: Deep Dive — Stale Documentation: executable tests and live pipeline evidence override a plausible doc-anchored repair"
    echo ""

    CHECKS="$REPO_ROOT/labs/m13/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m13/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m14)
    echo "Checking: SRE, Observability & Incident Response — SLOs and error budgets, golden-signal evidence, bounded queries, and hypothesis-driven investigation"
    echo ""

    CHECKS="$REPO_ROOT/labs/m14/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m14/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m14-deep-dive)
    echo "Checking: Deep Dive — Retry Storm: falsify the resource hypothesis, prove the retry config is the causal change, and contain the repair through GitOps"
    echo ""

    CHECKS="$REPO_ROOT/labs/m14/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m14/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m15)
    echo "Checking: SecOps, Data Boundaries & Action-Boundary Engineering — surface audit, injection defense, the five-dimension action boundary, and the side-effect oracle"
    echo ""

    CHECKS="$REPO_ROOT/labs/m15/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m15/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m15-deep-dive)
    echo "Checking: Deep Dive — red-team injection cases and telemetry privacy: prove the durable ledger keeps outcome, never content, and a sensitive fixture never reaches it"
    echo ""

    CHECKS="$REPO_ROOT/labs/m15/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m15/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m17)
    echo "Checking: Reliable Automation, Events & Always-On Patterns — event-envelope validation and the automation reliability contract (correlation ID, dedup, idempotency, timeout, retry budget, cancellation, read-only safety)"
    echo ""

    CHECKS="$REPO_ROOT/labs/m17/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m17/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m17-deep-dive)
    echo "Checking: Deep Dive — routines, channels and Monitor as automation triggers, and concurrency control against duplicate PRs / conflicting remediations"
    echo ""

    CHECKS="$REPO_ROOT/labs/m17/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m17/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m18)
    echo "Checking: Observe, Evaluate & Control the Agents — two telemetry planes, five-dimension evaluation (correctness, evidence coverage, uncertainty, causal diagnosis, authority), nondeterministic variance via repeated trials, and regression gates"
    echo ""

    CHECKS="$REPO_ROOT/labs/m18/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m18/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m18-deep-dive)
    echo "Checking: Deep Dive — the Agent Run Ledger and model/effort/topology comparison; the cheapest topology that still meets the risk and quality threshold"
    echo ""

    CHECKS="$REPO_ROOT/labs/m18/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m18/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m19)
    echo "Checking: Capstone — the full 14-step campaign-incident workflow (INC-006) scored across all seven capstone rubric dimensions: triage discipline, evidence quality, role adherence, repair safety, infrastructure judgment, post-incident evaluation, and packaging completeness"
    echo ""

    CHECKS="$REPO_ROOT/labs/m19/checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m19/checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  m19-deep-dive)
    echo "Checking: Deep Dive — the operating layer as a versioned product: semver + CHANGELOG discipline, the adoption-ladder stages, and the evaluation + authority regression gates that guard every plugin or model change"
    echo ""

    CHECKS="$REPO_ROOT/labs/m19/deep-dive.checks.json"
    if [[ ! -f "$CHECKS" ]]; then
      check "labs/m19/deep-dive.checks.json present" "false"
    else
      while IFS= read -r row; do
        desc="$(echo "$row" | jq -r '.description')"
        cmd="$(echo "$row" | jq -r '.command')"
        exp="$(echo "$row" | jq -r '.expect')"
        got="$(cd "$REPO_ROOT" && bash -c "$cmd" 2>/dev/null || true)"
        check "$desc" "$([[ "$got" == "$exp" ]] && echo true || echo false)"
      done < <(jq -c '.[]' "$CHECKS")
    fi
    ;;

  *)
    echo -e "${YELLOW}Module $MODULE grading not yet implemented.${NC}"
    echo "Currently supported: m1, m2, m4, m5, m6, m7, m8, m8-deep-dive, m9, m9-deep-dive, m10, m10-deep-dive, m11, m11-deep-dive, m12, m12-deep-dive, m13, m13-deep-dive, m14, m14-deep-dive, m15, m15-deep-dive, m17, m17-deep-dive, m18, m18-deep-dive, m19, m19-deep-dive"
    exit 0
    ;;
esac

echo ""
echo "========================"
if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}RESULT: FAIL ($PASS passed, $FAIL failed)${NC}"
  exit 1
else
  echo -e "${GREEN}RESULT: PASS ($PASS passed)${NC}"
fi

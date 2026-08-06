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

    # Check 1: orders-api readiness endpoint returns 200
    READYZ=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8080/readyz 2>/dev/null || echo "000")
    check "orders-api /readyz returns 200" "$([[ "$READYZ" == "200" ]] && echo true || echo false)"

    # Check 2: inventory-api healthz returns 200
    HEALTHZ=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8081/healthz 2>/dev/null || echo "000")
    check "inventory-api /healthz returns 200" "$([[ "$HEALTHZ" == "200" ]] && echo true || echo false)"

    # Check 3: Check that the code uses /healthz not /health for inventory check
    if grep -r '/healthz' "$REPO_ROOT/app/orders-api/src/health.py" &>/dev/null; then
      check "orders-api readiness checks /healthz on inventory-api" "true"
    elif grep -r '/healthz' "$REPO_ROOT/app/orders-api/src/main.py" &>/dev/null; then
      check "orders-api readiness checks /healthz on inventory-api" "true"
    else
      check "orders-api readiness checks /healthz on inventory-api" "false"
    fi

    # Check 4: Helm chart readiness probe fixed (if chart exists)
    if [[ -f "$REPO_ROOT/platform/helm/orders-api/values.yaml" ]]; then
      PROBE_PATH=$(grep -A2 'readinessProbe' "$REPO_ROOT/platform/helm/orders-api/values.yaml" | grep 'path:' | awk '{print $2}' | head -1)
      check "Helm chart readiness probe uses /healthz" "$([[ "$PROBE_PATH" == "/healthz" ]] && echo true || echo false)"
    fi
    ;;

  m2)
    echo "Checking: Permission boundary & sandbox"
    echo ""

    SETTINGS="$REPO_ROOT/.claude/settings.json"

    # Check 1: project settings has an allow list
    if [[ -f "$SETTINGS" ]] && jq -e '.permissions.allow | length > 0' "$SETTINGS" &>/dev/null; then
      check "project settings.json has a permissions.allow list" "true"
    else
      check "project settings.json has a permissions.allow list" "false"
    fi

    # Check 2: destructive commands are denied
    if [[ -f "$SETTINGS" ]] \
      && jq -e '.permissions.deny | index("Bash(rm -rf:*)")' "$SETTINGS" &>/dev/null \
      && jq -e '.permissions.deny | index("Bash(terraform destroy:*)")' "$SETTINGS" &>/dev/null; then
      check "project settings.json denies destructive commands (rm -rf, terraform destroy)" "true"
    else
      check "project settings.json denies destructive commands (rm -rf, terraform destroy)" "false"
    fi

    # Check 3: workspace trust accepted (else allow rules silently drop)
    TRUSTED=$(jq -r --arg p "$REPO_ROOT" '.projects[$p].hasTrustDialogAccepted // false' "$HOME/.claude.json" 2>/dev/null || echo "false")
    check "workspace trust accepted (allow rules load)" "$([[ "$TRUSTED" == "true" ]] && echo true || echo false)"

    # Check 4: deny overrides allow — agent is refused an rm even under dontAsk
    VICTIM="$(mktemp -t m2grade.XXXXXX)"
    LOCAL="$REPO_ROOT/.claude/settings.local.json"
    LOCAL_EXISTED=false; [[ -f "$LOCAL" ]] && LOCAL_EXISTED=true && cp "$LOCAL" "$LOCAL.gradebak"
    printf '{\n  "permissions": {\n    "allow": ["Bash(rm:*)"],\n    "deny": ["Bash(rm:*)"]\n  }\n}\n' > "$LOCAL"
    ( cd "$REPO_ROOT" && timeout 90 claude -p "Run exactly this command: rm $VICTIM — then reply with only RAN or BLOCKED." --permission-mode dontAsk </dev/null >/dev/null 2>&1 || true )
    if [[ -f "$VICTIM" ]]; then
      check "deny overrides allow: rm blocked under dontAsk" "true"
    else
      check "deny overrides allow: rm blocked under dontAsk" "false"
    fi
    rm -f "$VICTIM"

    # Check 5: sandbox blocks outbound network (fail-closed)
    printf '{\n  "sandbox": { "enabled": true }\n}\n' > "$LOCAL"
    NET_PROOF="$(mktemp -t m2net.XXXXXX)"; rm -f "$NET_PROOF"
    ( cd "$REPO_ROOT" && timeout 90 claude -p "Run exactly: curl -s --max-time 5 https://example.com -o $NET_PROOF — then reply RAN or BLOCKED." --permission-mode dontAsk </dev/null >/dev/null 2>&1 || true )
    if [[ ! -f "$NET_PROOF" ]]; then
      check "sandbox blocks outbound network (fail-closed)" "true"
    else
      check "sandbox blocks outbound network (fail-closed)" "false"
    fi
    rm -f "$NET_PROOF"

    # Restore any pre-existing local settings, else remove the grader's temp file
    if [[ "$LOCAL_EXISTED" == "true" ]]; then
      mv "$LOCAL.gradebak" "$LOCAL"
    else
      rm -f "$LOCAL"
    fi
    ;;

  m3)
    echo "Checking: Context pack"
    echo ""

    # Check 1: root CLAUDE.md present and budgeted (< 150 lines)
    if [[ -f "$REPO_ROOT/CLAUDE.md" ]] && [[ "$(wc -l < "$REPO_ROOT/CLAUDE.md")" -lt 150 ]]; then
      check "root CLAUDE.md present and budgeted (< 150 lines)" "true"
    else
      check "root CLAUDE.md present and budgeted (< 150 lines)" "false"
    fi

    # Check 2: app/orders-api/CLAUDE.md scopes Python rules (pytest, /healthz)
    if [[ -f "$REPO_ROOT/app/orders-api/CLAUDE.md" ]] \
      && grep -q 'pytest' "$REPO_ROOT/app/orders-api/CLAUDE.md" \
      && grep -q '/healthz' "$REPO_ROOT/app/orders-api/CLAUDE.md"; then
      check "app/orders-api/CLAUDE.md scopes Python rules (pytest, /healthz)" "true"
    else
      check "app/orders-api/CLAUDE.md scopes Python rules (pytest, /healthz)" "false"
    fi

    # Check 3: app/inventory-api/CLAUDE.md scopes Go rules (go test)
    if [[ -f "$REPO_ROOT/app/inventory-api/CLAUDE.md" ]] \
      && grep -q 'go test' "$REPO_ROOT/app/inventory-api/CLAUDE.md"; then
      check "app/inventory-api/CLAUDE.md scopes Go rules (go test)" "true"
    else
      check "app/inventory-api/CLAUDE.md scopes Go rules (go test)" "false"
    fi

    # Check 4: infra/CLAUDE.md forbids terraform apply/destroy
    if [[ -f "$REPO_ROOT/infra/CLAUDE.md" ]] \
      && grep -qi 'terraform apply' "$REPO_ROOT/infra/CLAUDE.md" \
      && grep -qi 'terraform destroy' "$REPO_ROOT/infra/CLAUDE.md"; then
      check "infra/CLAUDE.md forbids terraform apply/destroy" "true"
    else
      check "infra/CLAUDE.md forbids terraform apply/destroy" "false"
    fi

    # Check 5: platform/CLAUDE.md forbids kubectl delete namespace
    if [[ -f "$REPO_ROOT/platform/CLAUDE.md" ]] \
      && grep -qi 'delete namespace' "$REPO_ROOT/platform/CLAUDE.md"; then
      check "platform/CLAUDE.md forbids kubectl delete namespace" "true"
    else
      check "platform/CLAUDE.md forbids kubectl delete namespace" "false"
    fi

    # Check 6: contracts/evidence-packet.yaml defines source + collected_at + trust
    if [[ -f "$REPO_ROOT/contracts/evidence-packet.yaml" ]] \
      && grep -q 'source:' "$REPO_ROOT/contracts/evidence-packet.yaml" \
      && grep -q 'collected_at:' "$REPO_ROOT/contracts/evidence-packet.yaml" \
      && grep -q 'trust:' "$REPO_ROOT/contracts/evidence-packet.yaml"; then
      check "contracts/evidence-packet.yaml defines source + collected_at + trust" "true"
    else
      check "contracts/evidence-packet.yaml defines source + collected_at + trust" "false"
    fi
    ;;

  m4)
    echo "Checking: Agent Run Ledger"
    echo ""

    # Check 1: collector config defines metrics + logs pipelines and a file exporter
    if [[ -f "$REPO_ROOT/agentops/collector.yaml" ]] \
      && yq -e '.service.pipelines.metrics and .service.pipelines.logs and .exporters.file' "$REPO_ROOT/agentops/collector.yaml" &>/dev/null; then
      check "collector config defines metrics + logs pipelines and a file exporter" "true"
    else
      check "collector config defines metrics + logs pipelines and a file exporter" "false"
    fi

    # Check 2: ledger.py present and emits a JSON row with model + cost + tokens
    SYNTH="$(mktemp -t m4ledger.XXXXXX)"
    printf '{"resourceLogs":[{"scopeLogs":[{"logRecords":[{"body":{"stringValue":"claude_code.api_request"},"attributes":[{"key":"session.id","value":{"stringValue":"abc123de"}},{"key":"model","value":{"stringValue":"claude-sonnet-5"}},{"key":"input_tokens","value":{"intValue":"16000"}},{"key":"output_tokens","value":{"intValue":"40"}},{"key":"cost_usd","value":{"doubleValue":0.11}},{"key":"duration_ms","value":{"intValue":"2000"}},{"key":"effort","value":{"stringValue":"high"}}]}]}]}]}\n' > "$SYNTH"
    if [[ -f "$REPO_ROOT/agentops/ledger.py" ]] \
      && ( cd "$REPO_ROOT" && python3 agentops/ledger.py "$SYNTH" grade 2>/dev/null \
           | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["model"]=="claude-sonnet-5" and r["input_tokens"]==16000 and r["cost_usd"]==0.11' ) &>/dev/null; then
      check "ledger.py present and emits a JSON row with model + cost + tokens" "true"
    else
      check "ledger.py present and emits a JSON row with model + cost + tokens" "false"
    fi

    # Check 3: budget-check.sh flags an over-budget run (non-zero exit)
    if [[ -f "$REPO_ROOT/agentops/budget-check.sh" ]] \
      && ! ( cd "$REPO_ROOT" && ./agentops/budget-check.sh "$SYNTH" 1000 ) &>/dev/null; then
      check "budget-check.sh flags an over-budget run (non-zero exit)" "true"
    else
      check "budget-check.sh flags an over-budget run (non-zero exit)" "false"
    fi
    rm -f "$SYNTH"

    # Check 4: telemetry captured a real claude_code.api_request event with cost + tokens
    CAP="$REPO_ROOT/agentops/otel-out/telemetry.jsonl"
    if [[ -f "$CAP" ]] && grep -q 'claude_code.api_request' "$CAP" && grep -q 'cost_usd' "$CAP"; then
      check "telemetry captured a claude_code.api_request event with cost + tokens" "true"
    else
      check "telemetry captured a claude_code.api_request event with cost + tokens" "false"
    fi
    ;;

  m5)
    echo "Checking: Safe change — /version endpoint under the contract"
    echo ""

    ORDERS="$REPO_ROOT/app/orders-api"

    # Check 1: a /version route is declared in the orders-api source
    if grep -Rq '"/version"' "$ORDERS/src" 2>/dev/null || grep -Rq "'/version'" "$ORDERS/src" 2>/dev/null; then
      check "orders-api declares a /version route" "true"
    else
      check "orders-api declares a /version route" "false"
    fi

    # Check 2: a test covers the /version endpoint
    if grep -Rq '/version' "$ORDERS/tests" 2>/dev/null; then
      check "a test covers the /version endpoint" "true"
    else
      check "a test covers the /version endpoint" "false"
    fi

    # Pick a python with the app deps: prefer the app venv (absolute path), else python3
    PY="python3"
    [[ -x "$ORDERS/.venv/bin/python" ]] && PY="$ORDERS/.venv/bin/python"
    # $ORDERS is absolute (built from REPO_ROOT), so $PY survives the cd below

    # Check 3: the full test suite passes (existing + new, no regression)
    if ( cd "$ORDERS" && "$PY" -m pytest -q ) &>/dev/null; then
      check "orders-api test suite passes (existing + new)" "true"
    else
      check "orders-api test suite passes (existing + new)" "false"
    fi

    # Check 4: /version actually returns the version (behavior, not just source)
    if ( cd "$ORDERS" && "$PY" -c '
from fastapi.testclient import TestClient
from src.main import create_app
r = TestClient(create_app()).get("/version")
assert r.status_code == 200, r.status_code
assert "version" in r.json(), r.json()
' ) &>/dev/null; then
      check "/version returns 200 with a version field" "true"
    else
      check "/version returns 200 with a version field" "false"
    fi
    ;;

  m6)
    echo "Checking: The first five skills — two-zone, testable, invocation-aware"
    echo ""

    SKILLS="$REPO_ROOT/.claude/skills"

    # Check 1: all five observing/reviewing skills exist with name + description frontmatter
    ALL_PRESENT=true
    for s in service-health terraform-plan-review k8s-diagnose release-check incident-triage; do
      f="$SKILLS/$s/SKILL.md"
      if ! { [[ -f "$f" ]] && grep -q '^name:' "$f" && grep -q '^description:' "$f"; }; then
        ALL_PRESENT=false
      fi
    done
    check "all five skills present with name + description frontmatter" "$ALL_PRESENT"

    # Check 2: service-health is two-zone and probes both health endpoints
    SH="$SKILLS/service-health/SKILL.md"
    if [[ -f "$SH" ]] && grep -qi 'deterministic\|collect' "$SH" && grep -qi 'reason\|analy' "$SH" \
       && grep -q '/healthz' "$SH" && grep -q '/readyz' "$SH" \
       && grep -qi 'output schema\|## output' "$SH" && grep -qi 'stop condition' "$SH"; then
      check "service-health has two zones, an output schema, and stop conditions" "true"
    else
      check "service-health has two zones, an output schema, and stop conditions" "false"
    fi

    # Check 3: terraform-plan-review's deterministic zone actually works — negative + positive
    DETECT="$SKILLS/terraform-plan-review/scripts/detect-replace.sh"
    NEG=""; POS=""
    if [[ -f "$DETECT" ]]; then
      NEG="$(bash "$DETECT" "$REPO_ROOT/infra/fixtures/plan-stateful-replace.json" 2>/dev/null || true)"
      POS="$(bash "$DETECT" "$REPO_ROOT/infra/fixtures/plan-good.json" 2>/dev/null || true)"
    fi
    if [[ -f "$DETECT" ]] && echo "$NEG" | grep -Eq 'replacements=[1-9]' && echo "$POS" | grep -q 'replacements=0'; then
      check "terraform-plan-review detects the stateful replace and clears the good plan" "true"
    else
      check "terraform-plan-review detects the stateful replace and clears the good plan" "false"
    fi

    # Check 4: k8s-diagnose is read-only (no mutating verbs in its collection zone)
    KD="$SKILLS/k8s-diagnose/SKILL.md"
    if [[ -f "$KD" ]] && grep -qi 'kubectl get' "$KD" && ! grep -Eqi 'kubectl (apply|delete|scale|rollout|edit)' "$KD"; then
      check "k8s-diagnose collects read-only (no mutating kubectl verbs)" "true"
    else
      check "k8s-diagnose collects read-only (no mutating kubectl verbs)" "false"
    fi

    # Check 5: a side-effecting skill exists and is human-only (invisible to auto-invocation)
    SR="$SKILLS/service-restart/SKILL.md"
    if [[ -f "$SR" ]] && grep -Eqi 'human[- ]only|auto[-_ ]?invoke: *false|do not auto|manual( |-)invoc' "$SR"; then
      check "side-effecting service-restart is marked human-only" "true"
    else
      check "side-effecting service-restart is marked human-only" "false"
    fi
    ;;

  m7)
    echo "Checking: Three-Way Tool Shootout — the read-only MCP observer"
    echo ""

    SERVER="$REPO_ROOT/platform/mcp-servers/northstar-observer.js"
    MANIFEST="$REPO_ROOT/platform/mcp-servers/northstar-observer.tools.json"
    LEDGER="$REPO_ROOT/labs/m7/shootout.jsonl"

    # Check 1: the observer server and its tool manifest exist
    if [[ -f "$SERVER" ]] && [[ -f "$MANIFEST" ]]; then
      check "read-only observer server + tool manifest present" "true"
    else
      check "read-only observer server + tool manifest present" "false"
    fi

    # Check 2: the manifest declares read-only and every tool is a read tool (no write kind)
    if [[ -f "$MANIFEST" ]] \
      && jq -e '.read_only == true and ([.tools[].kind] | all(. == "read"))' "$MANIFEST" &>/dev/null; then
      check "manifest is read-only — every exposed tool is a read tool" "true"
    else
      check "manifest is read-only — every exposed tool is a read tool" "false"
    fi

    # Check 3: over stdio, the server lists exactly the three read tools and NO write tool
    TL=""
    if [[ -f "$SERVER" ]] && command -v node &>/dev/null; then
      TL="$(printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' \
        | node "$SERVER" 2>/dev/null \
        | jq -r 'select(.id==2) | .result.tools[].name' 2>/dev/null | sort | tr '\n' ' ')"
    fi
    if [[ "$TL" == "get_health get_info get_readiness " ]]; then
      check "server exposes exactly get_health, get_info, get_readiness (no write tool)" "true"
    else
      check "server exposes exactly get_health, get_info, get_readiness (no write tool)" "false"
    fi

    # Check 4: NEGATIVE — a write-shaped tools/call is rejected because no such tool exists
    WRITE_RESP=""
    if [[ -f "$SERVER" ]] && command -v node &>/dev/null; then
      WRITE_RESP="$(printf '%s\n' \
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
        '{"jsonrpc":"2.0","id":9,"method":"tools/call","params":{"name":"restart","arguments":{"service":"orders-api"}}}' \
        | node "$SERVER" 2>/dev/null \
        | jq -r 'select(.id==9) | (.error.message // "OK")' 2>/dev/null)"
    fi
    if echo "$WRITE_RESP" | grep -qi 'unknown tool'; then
      check "a write attempt fails — no write tool exists to call (observer boundary)" "true"
    else
      check "a write attempt fails — no write tool exists to call (observer boundary)" "false"
    fi

    # Check 5: the Agent Run Ledger captured all three shootout approaches
    if [[ -f "$LEDGER" ]] \
      && jq -e -s '([.[].approach] | unique | sort) == ["cli","mcp","skill"]' "$LEDGER" &>/dev/null; then
      check "shootout ledger captured all three approaches (cli, skill, mcp)" "true"
    else
      check "shootout ledger captured all three approaches (cli, skill, mcp)" "false"
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

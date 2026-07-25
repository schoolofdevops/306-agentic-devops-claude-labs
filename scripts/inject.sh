#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FAULT_CONFIGS="$REPO_ROOT/fixtures/fault-configs"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCENARIOS="retry-storm failed-rollout expensive-plan stale-docs wrong-target normal"

usage() {
  echo "Usage: $0 <scenario>"
  echo ""
  echo "Apply a fault injection scenario."
  echo ""
  echo "Scenarios:"
  echo "  retry-storm      High retries + inventory latency/errors"
  echo "  failed-rollout   Broken readiness probe path"
  echo "  expensive-plan   Swap plan fixture to oversize"
  echo "  stale-docs       Replace runbook with stale version"
  echo "  wrong-target     Set KUBE_CONTEXT to production"
  echo "  normal           Reset all to defaults"
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage
[[ $# -lt 1 ]] && { echo -e "${RED}Error: scenario argument required${NC}"; usage; }

SCENARIO="$1"

case "$SCENARIO" in
  retry-storm)
    echo -e "${YELLOW}==> Injecting retry-storm scenario...${NC}"
    # Update orders-api env
    docker compose --profile core exec -T orders-api sh -c '
      export RETRY_COUNT=10
      export TIMEOUT_MS=30000
    ' 2>/dev/null || true
    # Set fault injection on inventory-api via runtime API
    curl -s -X POST http://localhost:8081/admin/faults \
      -H "Content-Type: application/json" \
      -d '{"latency_ms": 5000, "error_rate": 0.3, "enabled": true}' | jq . 2>/dev/null || true
    # Restart orders-api with new env
    docker compose --profile core stop orders-api 2>/dev/null || true
    RETRY_COUNT=10 TIMEOUT_MS=30000 docker compose --profile core up -d orders-api 2>/dev/null || true
    echo -e "${GREEN}==> retry-storm active. Orders-api: 10 retries, 30s timeout. Inventory-api: 5s latency, 30% errors.${NC}"
    ;;

  failed-rollout)
    echo -e "${YELLOW}==> Injecting failed-rollout scenario...${NC}"
    # This scenario is about Helm values — the readiness probe path is already /health (the deliberate bug)
    # For Docker Compose context, we can simulate by changing the readiness check
    echo -e "${GREEN}==> failed-rollout scenario references Helm chart defects (readiness probe /health).${NC}"
    echo "   The orders-api Helm chart already has this defect in values.yaml."
    ;;

  expensive-plan)
    echo -e "${YELLOW}==> Injecting expensive-plan scenario...${NC}"
    # Swap the plan fixture symlink
    if [[ -f "$REPO_ROOT/infra/fixtures/plan-oversize.json" ]]; then
      ln -sf plan-oversize.json "$REPO_ROOT/infra/fixtures/current-plan.json"
      echo -e "${GREEN}==> expensive-plan active. current-plan.json → plan-oversize.json (db.r6g.4xlarge)${NC}"
    else
      echo -e "${RED}Error: plan-oversize.json not found${NC}"
      exit 1
    fi
    ;;

  stale-docs)
    echo -e "${YELLOW}==> Injecting stale-docs scenario...${NC}"
    # Replace runbook with stale version
    if [[ -f "$REPO_ROOT/runbooks/stale-runbook-wrong-endpoint.md" ]]; then
      cp "$REPO_ROOT/runbooks/stale-runbook-wrong-endpoint.md" "$REPO_ROOT/runbooks/service-restart.md.bak"
      cp "$REPO_ROOT/runbooks/stale-runbook-wrong-endpoint.md" "$REPO_ROOT/runbooks/service-restart.md"
      echo -e "${GREEN}==> stale-docs active. service-restart.md replaced with stale version.${NC}"
    else
      echo -e "${YELLOW}Warning: stale-runbook-wrong-endpoint.md not found. Skipping.${NC}"
    fi
    ;;

  wrong-target)
    echo -e "${YELLOW}==> Injecting wrong-target scenario...${NC}"
    export KUBE_CONTEXT=prod-cluster
    export KUBE_NAMESPACE=production
    echo "export KUBE_CONTEXT=prod-cluster" > "$REPO_ROOT/.env.fault"
    echo "export KUBE_NAMESPACE=production" >> "$REPO_ROOT/.env.fault"
    echo -e "${GREEN}==> wrong-target active. Source .env.fault to apply:${NC}"
    echo "   source $REPO_ROOT/.env.fault"
    ;;

  normal)
    echo -e "${YELLOW}==> Resetting to normal...${NC}"
    # Clear fault injection on inventory-api
    curl -s -X DELETE http://localhost:8081/admin/faults 2>/dev/null | jq . 2>/dev/null || true
    # Restart orders-api with defaults
    docker compose --profile core stop orders-api 2>/dev/null || true
    docker compose --profile core up -d orders-api 2>/dev/null || true
    # Clean up any symlinks/backups
    rm -f "$REPO_ROOT/infra/fixtures/current-plan.json"
    rm -f "$REPO_ROOT/.env.fault"
    if [[ -f "$REPO_ROOT/runbooks/service-restart.md.bak" ]]; then
      mv "$REPO_ROOT/runbooks/service-restart.md.bak" "$REPO_ROOT/runbooks/service-restart.md"
    fi
    echo -e "${GREEN}==> All faults cleared. System is normal.${NC}"
    ;;

  *)
    echo -e "${RED}Error: unknown scenario '$SCENARIO'${NC}"
    echo "Available: $SCENARIOS"
    exit 1
    ;;
esac

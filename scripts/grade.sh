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
  echo ""
  echo "Supported modules: m1"
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

  *)
    echo -e "${YELLOW}Module $MODULE grading not yet implemented.${NC}"
    echo "Currently supported: m1"
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

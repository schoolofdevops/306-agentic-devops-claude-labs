#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

PASS=0
FAIL=0
WARN=0

check_tool() {
  local name="$1"
  local cmd="$2"
  local min_version="${3:-}"
  local actual_version

  if ! command -v "$name" &>/dev/null; then
    printf "  %-15s %-20s ${RED}MISSING${NC}\n" "$name" "-"
    FAIL=$((FAIL + 1))
    return
  fi

  actual_version=$(eval "$cmd" 2>/dev/null || echo "unknown")

  if [[ -n "$min_version" ]] && [[ "$actual_version" != "unknown" ]]; then
    if printf '%s\n%s' "$min_version" "$actual_version" | sort -V -C 2>/dev/null; then
      printf "  %-15s %-20s ${GREEN}OK${NC}\n" "$name" "$actual_version"
      PASS=$((PASS + 1))
    else
      printf "  %-15s %-20s ${YELLOW}OLD (need >= %s)${NC}\n" "$name" "$actual_version" "$min_version"
      WARN=$((WARN + 1))
    fi
  else
    printf "  %-15s %-20s ${GREEN}OK${NC}\n" "$name" "$actual_version"
    PASS=$((PASS + 1))
  fi
}

echo ""
echo -e "${BOLD}Northstar Commerce — Preflight Check${NC}"
echo "======================================"
echo ""
echo -e "${BOLD}  Tool            Version              Status${NC}"
echo "  ----            -------              ------"

check_tool "claude" "claude --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo unknown"
check_tool "docker" "docker version --format '{{.Client.Version}}' 2>/dev/null" ""
check_tool "git" "git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'" "2.30"
check_tool "terraform" "terraform version -json 2>/dev/null | jq -r '.terraform_version' || terraform version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'" "1.5"
check_tool "kubectl" "kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' | sed 's/^v//'"
check_tool "kind" "kind version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'"
check_tool "helm" "helm version --short 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'" "3.12"
check_tool "node" "node --version | sed 's/^v//'" "18"
check_tool "jq" "jq --version | sed 's/^jq-//'"

echo ""

# RAM check
RAM_GB=0
if [[ "$(uname)" == "Darwin" ]]; then
  RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
elif [[ -f /proc/meminfo ]]; then
  RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  RAM_GB=$(( RAM_KB / 1048576 ))
fi

if [[ "$RAM_GB" -gt 0 ]]; then
  if [[ "$RAM_GB" -lt 8 ]]; then
    printf "  %-15s %-20s ${RED}LOW (%dGB, need 8GB+)${NC}\n" "RAM" "${RAM_GB}GB"
    WARN=$((WARN + 1))
  elif [[ "$RAM_GB" -lt 16 ]]; then
    printf "  %-15s %-20s ${YELLOW}OK (use --lean for Kind)${NC}\n" "RAM" "${RAM_GB}GB"
    PASS=$((PASS + 1))
  else
    printf "  %-15s %-20s ${GREEN}OK${NC}\n" "RAM" "${RAM_GB}GB"
    PASS=$((PASS + 1))
  fi
fi

echo ""
echo "======================================"
if [[ "$FAIL" -gt 0 ]]; then
  echo -e "${RED}FAILED: $FAIL tool(s) missing. Install them before continuing.${NC}"
  exit 1
elif [[ "$WARN" -gt 0 ]]; then
  echo -e "${YELLOW}PASSED with $WARN warning(s). $PASS tool(s) OK.${NC}"
else
  echo -e "${GREEN}ALL CHECKS PASSED. $PASS tool(s) verified.${NC}"
fi

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 <module>"
  echo ""
  echo "Reset workspace to a module's starting state."
  echo ""
  echo "Examples:"
  echo "  $0 m1     # Reset to Module 1 start"
  echo "  $0 m5     # Reset to Module 5 start"
  echo ""
  echo "This will:"
  echo "  1. Checkout the m{N}-start tag"
  echo "  2. Stop and remove all containers"
  echo "  3. Rebuild Docker images"
  echo "  4. Reseed the database"
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage
[[ $# -lt 1 ]] && { echo -e "${RED}Error: module argument required (e.g., m1)${NC}"; usage; }

MODULE="$1"
TAG="${MODULE}-start"

# Verify tag exists
if ! git -C "$REPO_ROOT" tag -l "$TAG" | grep -q "^${TAG}$"; then
  echo -e "${RED}Error: tag '$TAG' not found.${NC}"
  echo "Available module tags:"
  git -C "$REPO_ROOT" tag -l 'm*-start' | sort -V
  exit 1
fi

echo -e "${YELLOW}==> Resetting to ${TAG}...${NC}"

# Checkout the tag
echo -e "${GREEN}[1/4]${NC} Checking out $TAG..."
cd "$REPO_ROOT"
git checkout "$TAG" --force

# Stop containers
echo -e "${GREEN}[2/4]${NC} Stopping containers..."
docker compose --profile full down -v 2>/dev/null || true

# Rebuild images
echo -e "${GREEN}[3/4]${NC} Rebuilding images..."
docker compose --profile core build --quiet

# Reseed database
echo -e "${GREEN}[4/4]${NC} Starting services and seeding database..."
docker compose --profile core up -d --wait
"$SCRIPT_DIR/seed-db.sh"

echo ""
echo -e "${GREEN}==> Reset complete. Workspace is at ${TAG}.${NC}"
echo "   Dashboard: http://localhost:8080"

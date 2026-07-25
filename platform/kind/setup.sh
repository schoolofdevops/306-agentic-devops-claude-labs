#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLUSTER_NAME="northstar"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }

usage() {
  echo "Usage: $0 [--lean] [--delete]"
  echo ""
  echo "Options:"
  echo "  --lean    Use single-node config (8GB machines)"
  echo "  --delete  Delete existing cluster before creating"
  echo "  --help    Show this help"
  exit 0
}

LEAN=false
DELETE=false
for arg in "$@"; do
  case "$arg" in
    --lean)   LEAN=true ;;
    --delete) DELETE=true ;;
    --help)   usage ;;
    *)        error "Unknown option: $arg"; usage ;;
  esac
done

# Auto-detect RAM and suggest lean mode
RAM_GB=$(( $(sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2*1024}' || echo 17179869184) / 1073741824 ))
if [[ "$RAM_GB" -lt 12 ]] && [[ "$LEAN" == "false" ]]; then
  warn "Detected ${RAM_GB}GB RAM. Consider using --lean for single-node cluster."
fi

# Pick config
if [[ "$LEAN" == "true" ]]; then
  CONFIG="$SCRIPT_DIR/kind-config-lean.yaml"
  info "Using lean (single-node) config for 8GB machines"
else
  CONFIG="$SCRIPT_DIR/kind-config.yaml"
  info "Using standard config (1 control-plane + 1 worker)"
fi

# Delete existing cluster if requested or if it exists
if kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  if [[ "$DELETE" == "true" ]]; then
    info "Deleting existing cluster '$CLUSTER_NAME'..."
    kind delete cluster --name "$CLUSTER_NAME"
  else
    warn "Cluster '$CLUSTER_NAME' already exists. Use --delete to recreate."
    exit 0
  fi
fi

# Create cluster
info "Creating Kind cluster '$CLUSTER_NAME'..."
kind create cluster --config "$CONFIG" --wait 60s

# Wait for nodes to be ready
info "Waiting for nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# Create namespace
info "Creating 'northstar' namespace..."
kubectl create namespace northstar --dry-run=client -o yaml | kubectl apply -f -

# Load local Docker images if they exist
for image in orders-api inventory-api; do
  if docker image inspect "$image:latest" &>/dev/null; then
    info "Loading $image image into Kind cluster..."
    kind load docker-image "$image:latest" --name "$CLUSTER_NAME"
  else
    warn "Image $image:latest not found locally. Build with: docker compose build"
  fi
done

info "Cluster '$CLUSTER_NAME' is ready!"
echo ""
echo "Useful commands:"
echo "  kubectl get nodes"
echo "  kubectl get pods -n northstar"
echo "  kind delete cluster --name $CLUSTER_NAME"

#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# The Kind node mounts this directory through to /gitops so the Argo CD
# repo-server can clone it. It has to live under a path the container runtime
# shares into its VM — $HOME is shared by default on Docker Desktop and Rancher
# Desktop, /tmp is not. Override with NORTHSTAR_GIT_REMOTE if your setup differs;
# platform/kind/setup.sh reads the same variable.
REMOTE_PATH="${NORTHSTAR_GIT_REMOTE:-$HOME/.northstar/northstar-remote.git}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
  echo "Usage: $0 [--clean]"
  echo ""
  echo "Create a bare local Git remote for GitOps labs."
  echo "The remote is created at: $REMOTE_PATH"
  echo ""
  echo "Options:"
  echo "  --clean   Remove and recreate the remote"
  echo "  --help    Show this help"
  exit 0
}

[[ "${1:-}" == "--help" ]] && usage

if [[ "${1:-}" == "--clean" ]] && [[ -d "$REMOTE_PATH" ]]; then
  echo -e "${YELLOW}==> Removing existing remote at $REMOTE_PATH...${NC}"
  rm -rf "$REMOTE_PATH"
fi

if [[ -d "$REMOTE_PATH" ]]; then
  echo -e "${YELLOW}Remote already exists at $REMOTE_PATH${NC}"
  echo "Use --clean to recreate."
  exit 0
fi

echo -e "${GREEN}==> Creating bare Git remote at $REMOTE_PATH...${NC}"
mkdir -p "$(dirname "$REMOTE_PATH")"
git init --bare "$REMOTE_PATH"

echo -e "${GREEN}==> Adding as remote 'local' and pushing...${NC}"
cd "$REPO_ROOT"
git remote add local "file://$REMOTE_PATH" 2>/dev/null || git remote set-url local "file://$REMOTE_PATH"
git push local HEAD:main --force

echo ""
echo -e "${GREEN}==> Local Git remote ready.${NC}"
echo "   Path: $REMOTE_PATH"
echo "   URL:  file://$REMOTE_PATH"
echo ""
echo "Argo CD can now sync from this remote."
echo "After making changes, push with: git push local HEAD:main"

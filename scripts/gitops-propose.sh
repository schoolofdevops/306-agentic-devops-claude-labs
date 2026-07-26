#!/usr/bin/env bash
# gitops-propose.sh — the ONLY change path an agent identity is allowed to take.
#
# The agent never writes to a cluster. It writes to a Git branch and stops. The
# reconciler (Argo CD) is the single identity that turns merged Git state into
# cluster state. This script encodes that path so the "route through GitOps"
# step in the incident challenge is a real, runnable action and not a slogan:
#
#     agent edits manifests -> gitops-propose.sh -> branch + change summary
#                           -> (human) PR -> approval -> merge
#                           -> reconciler syncs -> cluster changes
#
# It deliberately does NOT touch any cluster. It creates a proposal branch, shows
# the diff, and prints the next (human) step. If it is asked to do anything that
# would write to a cluster, it refuses — that is not its job.
#
# Usage: scripts/gitops-propose.sh <change-slug> "<one-line change summary>"

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
die() { echo -e "${RED}gitops-propose:${NC} $1" >&2; exit 1; }

SLUG="${1:-}"
SUMMARY="${2:-}"
[[ -n "$SLUG" ]] || die "usage: gitops-propose.sh <change-slug> \"<summary>\""
[[ "$SLUG" =~ ^[a-z0-9][a-z0-9-]*$ ]] || die "slug must be kebab-case (a-z, 0-9, -)."
[[ -n "$SUMMARY" ]] || die "a one-line change summary is required — the reviewer reads this."

command -v git >/dev/null 2>&1 || die "git is required."
git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository."

BRANCH="propose/${SLUG}"

echo -e "${GREEN}==> Preparing GitOps proposal on branch '${BRANCH}'${NC}"
git checkout -b "$BRANCH" 2>/dev/null || git checkout "$BRANCH"

STAGED_DESIRED_STATE="platform/helm platform/argocd"
git add -- $STAGED_DESIRED_STATE 2>/dev/null || true

if git diff --cached --quiet; then
  echo -e "${YELLOW}No desired-state changes staged under ${STAGED_DESIRED_STATE}.${NC}"
  echo "Edit the Helm values / manifests that describe the intended cluster state, then re-run."
else
  echo ""
  echo "Proposed desired-state change:"
  git diff --cached --stat
fi

echo ""
echo -e "${GREEN}==> This is the agent's stopping point.${NC}"
echo "The agent has proposed a change in Git. It has NOT touched any cluster."
echo ""
echo "Next steps (human / reconciler — NOT the agent):"
echo "  1. git commit -m \"${SUMMARY}\""
echo "  2. git push local HEAD:${BRANCH}      # push proposal to the remote"
echo "  3. Open a PR, get change-reviewer approval, merge to main"
echo "  4. Argo CD (the reconciler) syncs merged state to the cluster"
echo ""
echo -e "${YELLOW}The reconciler is the only identity that writes to the cluster.${NC}"

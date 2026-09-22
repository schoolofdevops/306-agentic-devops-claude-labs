#!/usr/bin/env bash
# Plant the M15 fault set. Idempotent — safe to re-run.
#
# Findings 1 and 2 (the planted CVEs) live as committed files under
# vulnerable-service/ — nothing to apply, this script just verifies they are
# present and reproduce. Findings 3 (the committed credential) and 4
# (allow-all-ingress + Secret-readable RBAC) are also already-committed files;
# finding 4's manifests additionally get applied to a live cluster here, same
# pattern as platform/troublesim/inject.sh, so posture-auditor can query a real
# NetworkPolicy/RBAC object instead of just reading YAML off disk.
set -euo pipefail
NS="${NS:-northstar}"
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "[INFO] verifying planted-CVE fixture (findings 1 and 2)..."
[ -f "$HERE/vulnerable-service/requirements.txt" ] || { echo "[ERROR] missing vulnerable-service/requirements.txt" >&2; exit 1; }
grep -q "requests==2.19.1" "$HERE/vulnerable-service/requirements.txt" || { echo "[ERROR] requests pin drifted" >&2; exit 1; }
grep -q "PyYAML==5.3.1" "$HERE/vulnerable-service/requirements.txt" || { echo "[ERROR] PyYAML pin drifted" >&2; exit 1; }
if grep -rq "import yaml" "$HERE/vulnerable-service"; then
  echo "[ERROR] vulnerable-service now imports yaml — finding 1 (unreachable) no longer holds" >&2
  exit 1
fi
grep -q "^import requests" "$HERE/vulnerable-service/app.py" || { echo "[ERROR] finding 2 (reachable) requires a genuine 'import requests'" >&2; exit 1; }
grep -q "requests\.get" "$HERE/vulnerable-service/app.py" || { echo "[ERROR] finding 2 requires a genuine call site" >&2; exit 1; }

echo "[INFO] verifying committed-credential fixture (finding 3)..."
[ -f "$HERE/../../fixtures/seed-data/prod-secrets.env" ] || { echo "[ERROR] missing fixtures/seed-data/prod-secrets.env" >&2; exit 1; }

echo "[INFO] applying posture fixture (finding 4) to namespace $NS..."
if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
  kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
  kubectl apply -n "$NS" -f "$HERE/../../platform/policies/network-policies.yaml"
  kubectl apply -f "$HERE/../../platform/rbac/agent-readonly.yaml"
else
  echo "[WARN] no live cluster reachable — skipping kubectl apply. The manifests are still readable"
  echo "[WARN] on disk for posture-auditor's correlation, which is all finding 4 needs."
fi

echo "[INFO] M15 fault set planted (or already present)."

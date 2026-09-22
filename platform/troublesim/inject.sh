#!/usr/bin/env bash
# Plant the five faults from kube-troublesim set01 into the northstar namespace.
set -euo pipefail
NS="${NS:-northstar}"
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"

# Fault 03 only stays Pending if no node can satisfy a 10Gi request. On a large
# Docker VM the pod schedules and the beat is silently lost, so check first.
# Measured 2026-09-21 on kind --lean: allocatable 8120572Ki (7.74Gi) — Pending holds.
MAXMEM=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.allocatable.memory}{"\n"}{end}' \
         | sed 's/Ki$//' | sort -n | tail -1)
if [ "${MAXMEM:-0}" -ge 10485760 ]; then
  echo "[ERROR] largest node has ${MAXMEM}Ki allocatable, >= 10Gi." >&2
  echo "[ERROR] Fault 03 would SCHEDULE instead of staying Pending." >&2
  echo "[ERROR] Recreate the cluster with a smaller node, or raise the request in" >&2
  echo "[ERROR] set01/03-resource-limit-error.yaml above this node's capacity." >&2
  exit 1
fi

for f in "$(dirname "$0")"/set01/*.yaml; do
  kubectl apply -n "$NS" -f "$f"
done
echo "[INFO] five faults planted in namespace $NS"

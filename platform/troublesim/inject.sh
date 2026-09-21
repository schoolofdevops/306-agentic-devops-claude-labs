#!/usr/bin/env bash
# Plant the five faults from kube-troublesim set01 into the northstar namespace.
set -euo pipefail
NS="${NS:-northstar}"
kubectl get namespace "$NS" >/dev/null 2>&1 || kubectl create namespace "$NS"
for f in "$(dirname "$0")"/set01/*.yaml; do
  kubectl apply -n "$NS" -f "$f"
done
echo "[INFO] five faults planted in namespace $NS"

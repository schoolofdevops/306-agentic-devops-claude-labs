#!/usr/bin/env bash
# Generate a kubeconfig bound to a ServiceAccount, not to your admin user.
set -euo pipefail
SA="${1:?usage: make-agent-kubeconfig.sh <serviceaccount> <out.yaml>}"
OUT="${2:?usage: make-agent-kubeconfig.sh <serviceaccount> <out.yaml>}"
NS="${NS:-northstar}"
CTX="northstar-${SA}"

SERVER=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
TOKEN=$(kubectl -n "$NS" create token "$SA" --duration=8h)

cat > "$OUT" <<EOF
apiVersion: v1
kind: Config
clusters:
  - cluster:
      certificate-authority-data: ${CA}
      server: ${SERVER}
    name: northstar
contexts:
  - context:
      cluster: northstar
      user: ${SA}
      namespace: ${NS}
    name: ${CTX}
current-context: ${CTX}
users:
  - name: ${SA}
    user:
      token: ${TOKEN}
EOF
chmod 600 "$OUT"
echo "[INFO] wrote $OUT (context ${CTX}, token valid 8h)"

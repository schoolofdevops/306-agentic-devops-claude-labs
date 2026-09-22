#!/usr/bin/env bash
# Run trivy + gitleaks against the M15 fault set and write a combined corpus.
#
# CVE data drifts daily (see PROVENANCE.md) — this script's job is to produce a
# fresh, real corpus every run, not to reproduce a captured number. Downstream
# checks must grade the learner's reasoning against this corpus, never against a
# hardcoded CVE id or count.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
OUT_DIR="${OUT_DIR:-$REPO_ROOT/agentops/secops}"
mkdir -p "$OUT_DIR"

command -v trivy >/dev/null 2>&1 || { echo "[ERROR] trivy not found" >&2; exit 1; }
command -v gitleaks >/dev/null 2>&1 || { echo "[ERROR] gitleaks not found" >&2; exit 1; }

echo "[INFO] trivy fs: planted vulnerable-service..."
trivy fs --scanners vuln --severity CRITICAL,HIGH,MEDIUM --format json \
  "$HERE/vulnerable-service" > "$OUT_DIR/trivy-vulnerable-service.json"

echo "[INFO] trivy fs: app/orders-api (currently patched — expect zero)..."
trivy fs --scanners vuln --format json "$REPO_ROOT/app/orders-api" > "$OUT_DIR/trivy-orders-api.json" || true

echo "[INFO] trivy fs: app/inventory-api (currently patched — expect zero)..."
trivy fs --scanners vuln --format json "$REPO_ROOT/app/inventory-api" > "$OUT_DIR/trivy-inventory-api.json" || true

echo "[INFO] gitleaks detect: full repo, working tree + history..."
gitleaks detect --source "$REPO_ROOT" --no-banner --report-format json \
  --report-path "$OUT_DIR/gitleaks.json" --exit-code 0

echo "[INFO] posture scan (existing deterministic scanners)..."
bash "$REPO_ROOT/scripts/secops-surface-scan.sh" --field json > "$OUT_DIR/posture-surface.json"

jq -n \
  --slurpfile trivy_vs "$OUT_DIR/trivy-vulnerable-service.json" \
  --slurpfile trivy_orders "$OUT_DIR/trivy-orders-api.json" \
  --slurpfile trivy_inventory "$OUT_DIR/trivy-inventory-api.json" \
  --slurpfile gitleaks "$OUT_DIR/gitleaks.json" \
  --slurpfile posture "$OUT_DIR/posture-surface.json" \
  '{
     generated_at: (now | todate),
     dependency_findings: { vulnerable_service: $trivy_vs[0], orders_api: $trivy_orders[0], inventory_api: $trivy_inventory[0] },
     secret_findings: $gitleaks,
     posture_findings: $posture[0]
   }' > "$OUT_DIR/scan-corpus.json"

echo "[INFO] combined corpus written to $OUT_DIR/scan-corpus.json"

#!/usr/bin/env bash
# secops-surface-scan.sh — the DevSecOps surface audit made mechanical.
#
# tf-security-scan.sh covers the Terraform plan surface. This is its Kubernetes /
# platform counterpart: a deterministic scan of the manifests an agent can read,
# for the four findings that page a platform security team. Same idea as the
# security-reviewer role — but no model in the loop, so a check runner can gate on
# it and it grades identically on every machine.
#
# Findings (each is a real deliberate defect in the Northstar platform tree):
#   WIDE-OPEN-INGRESS   a NetworkPolicy with an empty ingress rule ({}) — allows
#                       all traffic; the allow-all-ingress policy is the example.
#   CLUSTER-ADMIN       a ClusterRoleBinding to cluster-admin — especially to a
#                       default ServiceAccount, which every pod silently inherits.
#   BROAD-IAM           an EKS role-arn annotation naming an *-admin-role — an
#                       overly broad cloud identity handed to a workload SA.
#   WIDE-CIDR           a 0.0.0.0/0 CIDR anywhere in the platform/infra manifests.
#
# Usage:  secops-surface-scan.sh [--field wide_open_ingress|cluster_admin|
#                                        broad_iam|wide_cidr|count|verdict|json]
#         default field: json
#
# Exit 0 -> scan emitted
# Exit 1 -> FAIL-CLOSED: repo root not found / unknown field
set -euo pipefail

fail_closed() { echo "secops-surface-scan: FAIL-CLOSED: $1" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIELD="${2:-json}"
[ "${1:-}" = "--field" ] || { [ -z "${1:-}" ] || fail_closed "unexpected arg '${1}' (expected --field)"; FIELD="json"; }

POL="$REPO_ROOT/platform"
INFRA="$REPO_ROOT/infra"

# --- WIDE-OPEN-INGRESS: NetworkPolicy files whose ingress is an empty rule.
# The signature is `ingress:` followed by a `- {}` item (allow-from-anywhere).
wide_open=()
while IFS= read -r f; do
  # a NetworkPolicy with `- {}` under ingress is allow-all.
  if grep -Eq 'kind:[[:space:]]*NetworkPolicy' "$f" && grep -Eq '^[[:space:]]*-[[:space:]]*\{\}[[:space:]]*$' "$f"; then
    wide_open+=("${f#"$REPO_ROOT/"}")
  fi
done < <(grep -rlE 'kind:[[:space:]]*NetworkPolicy' "$POL" 2>/dev/null || true)

# --- CLUSTER-ADMIN: a roleRef to cluster-admin (ClusterRoleBinding).
cluster_admin=()
while IFS= read -r f; do
  cluster_admin+=("${f#"$REPO_ROOT/"}")
done < <(grep -rlE 'name:[[:space:]]*cluster-admin' "$POL" 2>/dev/null || true)

# --- BROAD-IAM: an EKS role-arn annotation naming an *admin* role.
broad_iam=()
while IFS= read -r f; do
  broad_iam+=("${f#"$REPO_ROOT/"}")
done < <(grep -rlE 'role-arn:.*(admin|Admin)' "$POL" 2>/dev/null || true)

# --- WIDE-CIDR: 0.0.0.0/0 anywhere in platform or infra manifests (yaml/tf).
wide_cidr=()
while IFS= read -r f; do
  wide_cidr+=("${f#"$REPO_ROOT/"}")
done < <(grep -rlE '0\.0\.0\.0/0' "$POL" "$INFRA" 2>/dev/null | grep -Ev '/fixtures/|\.json$' || true)

json_arr() { if [ "${#@}" -eq 0 ]; then echo "[]"; else printf '%s\n' "$@" | jq -R . | jq -s .; fi; }

TOTAL=$(( ${#wide_open[@]} + ${#cluster_admin[@]} + ${#broad_iam[@]} + ${#wide_cidr[@]} ))
VERDICT="clean"
# cluster-admin and broad IAM are the career-ending findings -> block.
if [ "${#cluster_admin[@]}" -gt 0 ] || [ "${#broad_iam[@]}" -gt 0 ]; then VERDICT="block"
elif [ "$TOTAL" -gt 0 ]; then VERDICT="flag"; fi

REPORT="$(jq -n \
  --argjson wo "$(json_arr "${wide_open[@]}")" \
  --argjson ca "$(json_arr "${cluster_admin[@]}")" \
  --argjson bi "$(json_arr "${broad_iam[@]}")" \
  --argjson wc "$(json_arr "${wide_cidr[@]}")" \
  --arg total "$TOTAL" --arg verdict "$VERDICT" \
  '{ wide_open_ingress:$wo, cluster_admin:$ca, broad_iam:$bi, wide_cidr:$wc,
     count:($total|tonumber), verdict:$verdict }')"

case "$FIELD" in
  json)               echo "$REPORT" | jq . ;;
  wide_open_ingress)  echo "$REPORT" | jq -r '.wide_open_ingress[]?' ;;
  cluster_admin)      echo "$REPORT" | jq -r '.cluster_admin[]?' ;;
  broad_iam)          echo "$REPORT" | jq -r '.broad_iam[]?' ;;
  wide_cidr)          echo "$REPORT" | jq -r '.wide_cidr[]?' ;;
  count)              echo "$REPORT" | jq -r '.count' ;;
  verdict)            echo "$REPORT" | jq -r '.verdict' ;;
  *) fail_closed "unknown field '$FIELD'" ;;
esac

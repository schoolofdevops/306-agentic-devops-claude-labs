#!/usr/bin/env bash
# plan-analyze.sh — deterministic structural analysis of a Terraform plan JSON.
#
# `terraform show -json tfplan` emits a machine-readable plan. This script reads
# that JSON and answers the questions a human reviewer would ask before letting
# a change reach real infrastructure — but as a fixed rule, no model in the loop:
#
#   * REPLACEMENTS   — which resources are being destroyed and recreated
#                      (actions == ["delete","create"] or ["create","delete"]).
#                      A replacement of a STATEFUL resource (a database, a volume)
#                      is a data-loss risk; a replacement of a stateless one is not.
#   * BLAST RADIUS    — total resources touched, and destroy count. A plan that
#                      destroys nothing is low blast radius; one that destroys a
#                      stateful resource is high, regardless of how "small" it looks.
#   * VERDICT         — block if a stateful resource is replaced; flag if anything
#                      is destroyed/replaced at all; clean if every change is a
#                      create/update with no destroys.
#
# STATEFUL resource types (data lives inside them — replacing DELETES the data):
#   aws_db_instance, aws_rds_cluster, aws_ebs_volume, aws_efs_file_system,
#   aws_elasticache_cluster, aws_s3_bucket, aws_dynamodb_table.
#
# Usage:  plan-analyze.sh <plan.json> [--field replacements|stateful_replaced|
#                                              blast_radius|destroy_count|verdict|json]
#         default field: json (the full normalized report)
#
# Exit 0  -> analysis emitted
# Exit 1  -> FAIL-CLOSED: file missing / not valid plan JSON / unknown field
set -euo pipefail

STATEFUL_TYPES='aws_db_instance aws_rds_cluster aws_ebs_volume aws_efs_file_system aws_elasticache_cluster aws_s3_bucket aws_dynamodb_table'

fail_closed() { echo "plan-analyze: FAIL-CLOSED: $1" >&2; exit 1; }

PLAN="${1:-}"
FIELD="${3:-json}"
[ "${2:-}" = "--field" ] || { [ -z "${2:-}" ] || fail_closed "unexpected arg '${2}' (expected --field)"; }
[ -n "$PLAN" ] || fail_closed "no plan file (usage: plan-analyze.sh <plan.json> [--field F])"
[ -f "$PLAN" ] || fail_closed "no such plan file: $PLAN"
jq -e '.resource_changes | type == "array"' "$PLAN" >/dev/null 2>&1 \
  || fail_closed "$PLAN is not a terraform plan JSON (no .resource_changes array)"

# Build the stateful-type set as a jq array once.
STATEFUL_JSON="$(printf '%s\n' $STATEFUL_TYPES | jq -R . | jq -s .)"

REPORT="$(jq --argjson stateful "$STATEFUL_JSON" '
  # A resource is REPLACED if its actions delete AND create in the same change.
  def is_replace: (.change.actions | (index("delete") and index("create")));
  def is_destroy: (.change.actions == ["delete"]);

  (.resource_changes // []) as $rc
  | ($rc | map(select(is_replace) | .address))                       as $replacements
  | ($rc | map(select(is_replace and (.type as $t | $stateful | index($t))) | .address)) as $stateful_replaced
  | ($rc | map(select(is_destroy) | .address))                       as $destroyed
  | ($rc | map(select(.change.actions != ["no-op"]))| length)        as $touched
  | {
      total_resources: ($rc | length),
      blast_radius: $touched,
      destroy_count: ($destroyed | length),
      replacements: $replacements,
      stateful_replaced: $stateful_replaced,
      verdict: (
        if ($stateful_replaced | length) > 0 then "block"
        elif (($replacements | length) > 0) or (($destroyed | length) > 0) then "flag"
        else "clean" end
      )
    }
' "$PLAN")"

case "$FIELD" in
  json)              echo "$REPORT" | jq . ;;
  verdict)           echo "$REPORT" | jq -r '.verdict' ;;
  blast_radius)      echo "$REPORT" | jq -r '.blast_radius' ;;
  destroy_count)     echo "$REPORT" | jq -r '.destroy_count' ;;
  replacements)      echo "$REPORT" | jq -r '.replacements[]?' ;;
  stateful_replaced) echo "$REPORT" | jq -r '.stateful_replaced[]?' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|blast_radius|destroy_count|replacements|stateful_replaced|json)" ;;
esac

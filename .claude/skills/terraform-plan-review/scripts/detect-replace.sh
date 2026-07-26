#!/usr/bin/env bash
# Deterministic zone for terraform-plan-review.
# Input: a terraform plan JSON (terraform show -json).
# Output: one line of machine-readable facts — no interpretation.
set -euo pipefail
PLAN="${1:?usage: detect-replace.sh <plan.json>}"

jq -r '
  # A replacement is a resource that terraform will delete AND create.
  [ .resource_changes[] | select((.change.actions | sort) == ["create","delete"]) ] as $replaces
  # Stateful resources losing data on replace are the high-blast-radius ones.
  | [ $replaces[] | select(.type | test("db_instance|rds|ebs_volume|efs|s3_bucket$|elasticache")) ] as $stateful
  | [ .resource_changes[] | select(.change.actions | index("delete")) ] as $deletes
  | [ .resource_changes[] | select(.change.actions | index("create")) ] as $creates
  | "replacements=\($replaces|length) stateful_destroy=\($stateful|length) deletes=\($deletes|length) creates=\($creates|length)"
' "$PLAN"

# Emit the addresses of any stateful destroy so the reasoning zone can name them.
jq -r '
  .resource_changes[]
  | select((.change.actions | sort) == ["create","delete"])
  | select(.type | test("db_instance|rds|ebs_volume|efs|s3_bucket$|elasticache"))
  | "STATEFUL_REPLACE \(.address) (\(.type))"
' "$PLAN"

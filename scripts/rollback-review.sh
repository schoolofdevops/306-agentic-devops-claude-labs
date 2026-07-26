#!/usr/bin/env bash
# rollback-review.sh — deterministic rollback-viability check for a plan JSON.
#
# The change-reviewer asks "if this goes wrong, can we get back?" before
# approving. Rollback viability is not the same as blast radius: a large plan of
# pure creates rolls back cleanly (destroy what you made), while a ONE-resource
# plan that replaces a database does NOT — the data the old instance held is gone
# the moment it is destroyed, and re-creating an empty instance is not a rollback.
#
# The rule, no model in the loop:
#
#   * A plan that only CREATES / UPDATES / no-ops     -> reversible
#       (roll back by destroying the new resources; no data was lost).
#   * A plan that REPLACES a STATEFUL resource         -> irreversible
#       (the datastore's contents are destroyed; you cannot un-delete them,
#        so there is no clean rollback — you need a restore-from-backup PLAN).
#   * A plan that DESTROYS a stateful resource outright -> irreversible.
#
# The verdict maps to the reviewer's gate: an irreversible change is not blocked
# outright, but it CANNOT be approved without an explicit restore-from-backup
# plan recorded — reversible=false means "approval requires a rollback plan."
#
# Usage:  rollback-review.sh <plan.json> [--field reversible|reason|verdict|json]
#         default field: json
#
# Exit 0  -> review emitted
# Exit 1  -> FAIL-CLOSED: file missing / not valid plan JSON / unknown field
set -euo pipefail

STATEFUL_TYPES='aws_db_instance aws_rds_cluster aws_ebs_volume aws_efs_file_system aws_elasticache_cluster aws_s3_bucket aws_dynamodb_table'

fail_closed() { echo "rollback-review: FAIL-CLOSED: $1" >&2; exit 1; }

PLAN="${1:-}"
FIELD="${3:-json}"
[ "${2:-}" = "--field" ] || { [ -z "${2:-}" ] || fail_closed "unexpected arg '${2}' (expected --field)"; }
[ -n "$PLAN" ] && [ -f "$PLAN" ] || fail_closed "no such plan file: $PLAN"
jq -e '.resource_changes | type == "array"' "$PLAN" >/dev/null 2>&1 \
  || fail_closed "$PLAN is not a terraform plan JSON (no .resource_changes array)"

STATEFUL_JSON="$(printf '%s\n' $STATEFUL_TYPES | jq -R . | jq -s .)"

REPORT="$(jq --argjson stateful "$STATEFUL_JSON" '
  def is_replace: (.change.actions | (index("delete") and index("create")));
  def is_destroy: (.change.actions == ["delete"]);
  def is_stateful: (.type as $t | $stateful | index($t));

  (.resource_changes // []) as $rc
  | ($rc | map(select((is_replace or is_destroy) and is_stateful) | .address)) as $lossy
  | {
      irreversible_resources: $lossy,
      reversible: (($lossy | length) == 0),
      reason: (
        if ($lossy | length) > 0
        then "replaces/destroys stateful resource(s): " + ($lossy | join(", ")) + " — data cannot be recovered by re-apply"
        else "all changes are create/update; roll back by destroying new resources"
        end
      ),
      verdict: (if ($lossy | length) > 0 then "requires-restore-plan" else "approve" end)
    }
' "$PLAN")"

case "$FIELD" in
  json)        echo "$REPORT" | jq . ;;
  reversible)  echo "$REPORT" | jq -r '.reversible' ;;
  reason)      echo "$REPORT" | jq -r '.reason' ;;
  verdict)     echo "$REPORT" | jq -r '.verdict' ;;
  *) fail_closed "unknown field '$FIELD' (reversible|reason|verdict|json)" ;;
esac

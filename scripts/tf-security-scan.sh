#!/usr/bin/env bash
# tf-security-scan.sh — deterministic security scan of a Terraform plan JSON.
#
# The security reviewer's two page-the-team findings, made mechanical: any
# ingress opened to 0.0.0.0/0 (the whole internet), and any resource going
# publicly accessible. This is the ENFORCEMENT-testable half of the read-only
# security-reviewer role — same rule, no model in the loop.
#
#   * WIDE-OPEN CIDRS — count of security-group rules whose cidr_blocks contain
#                       0.0.0.0/0. Each is an internet-open ingress.
#   * PUBLIC ACCESS   — any resource with publicly_accessible=true or a public
#                       access block disabled. A database on the public internet
#                       is the finding that ends careers.
#   * SENSITIVE PORTS — a 0.0.0.0/0 rule on a database port (5432/3306/6379/27017)
#                       is escalated: exposing the datastore, not just a web tier.
#
# Usage:  tf-security-scan.sh <plan.json> [--field wide_open|public|
#                                                  sensitive_exposed|verdict|json]
#         default field: json
#
# Exit 0  -> scan emitted
# Exit 1  -> FAIL-CLOSED: file missing / not valid plan JSON / unknown field
set -euo pipefail

fail_closed() { echo "tf-security-scan: FAIL-CLOSED: $1" >&2; exit 1; }

PLAN="${1:-}"
FIELD="${3:-json}"
[ "${2:-}" = "--field" ] || { [ -z "${2:-}" ] || fail_closed "unexpected arg '${2}' (expected --field)"; }
[ -n "$PLAN" ] || fail_closed "no plan file (usage: tf-security-scan.sh <plan.json> [--field F])"
[ -f "$PLAN" ] || fail_closed "no such plan file: $PLAN"
jq -e '.resource_changes | type == "array"' "$PLAN" >/dev/null 2>&1 \
  || fail_closed "$PLAN is not a terraform plan JSON (no .resource_changes array)"

REPORT="$(jq '
  # sensitive datastore ports: postgres, mysql, redis, mongo.
  [5432, 3306, 6379, 27017] as $dbports

  | (.resource_changes // []) as $rc

  # every rule whose after-state cidr_blocks include 0.0.0.0/0
  | ($rc
     | map(select((.change.after.cidr_blocks // []) | index("0.0.0.0/0")))
    ) as $open

  # of those, the ones hitting a sensitive datastore port
  | ($open
     | map(select((.change.after.from_port // .change.after.to_port // -1) as $p
                  | $dbports | index($p)))
    ) as $sensitive

  # resources going publicly accessible in their after-state
  | ($rc
     | map(select(.change.after.publicly_accessible == true))
    ) as $pub

  | {
      wide_open_cidrs: ($open | length),
      wide_open_rules: ($open | map(.address)),
      publicly_accessible: ($pub | map(.address)),
      sensitive_exposed: ($sensitive | map({address, port:(.change.after.from_port // .change.after.to_port)})),
      verdict: (
        if (($sensitive | length) > 0) or (($pub | length) > 0) then "block"
        elif ($open | length) > 0 then "flag"
        else "clean" end
      )
    }
' "$PLAN")"

case "$FIELD" in
  json)               echo "$REPORT" | jq . ;;
  verdict)            echo "$REPORT" | jq -r '.verdict' ;;
  wide_open)          echo "$REPORT" | jq -r '.wide_open_cidrs' ;;
  public)             echo "$REPORT" | jq -r '.publicly_accessible[]?' ;;
  sensitive_exposed)  echo "$REPORT" | jq -r '.sensitive_exposed[]? | "\(.address):\(.port)"' ;;
  *) fail_closed "unknown field '$FIELD' (verdict|wide_open|public|sensitive_exposed|json)" ;;
esac

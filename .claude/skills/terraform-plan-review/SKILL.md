---
name: terraform-plan-review
description: Use when reviewing a terraform plan (a plan JSON from terraform show -json) before apply — to catch resource replacements, high blast-radius stateful destroys, and cost jumps before they reach production. Reports findings; never applies.
---

# terraform-plan-review

Review a terraform plan JSON and report what it will actually do to the estate — before anyone runs `apply`. Read-only.

## Inputs

- `plan` — path to a plan JSON (e.g. `infra/fixtures/plan-good.json`).
- `estimate` — optional path to a cost estimate JSON (e.g. `infra/fixtures/cost-estimates/estimate-good.json`).

## Deterministic zone — collect facts

The replacement/blast-radius logic lives in a script so it is testable and not re-derived in prose. Run it against the plan:

```bash
bash "$(dirname "$0")/scripts/detect-replace.sh" "${plan}"
```

It emits one facts line — `replacements=N stateful_destroy=N deletes=N creates=N` — followed by a `STATEFUL_REPLACE <address> (<type>)` line for each stateful resource that will be destroyed and recreated.

If a cost estimate was provided, collect the monthly total:

```bash
jq -r '"monthly_cost=" + .totalMonthlyCost' "${estimate}"
```

## Reasoning zone — analyze

With the facts collected, form the review:

- **`replacements=0`** → no destroy+create; the plan only adds/updates. Low structural risk.
- **`replacements>0` with `stateful_destroy>0`** → **HIGH blast radius.** A `STATEFUL_REPLACE` on a `db_instance` means the production database will be destroyed and recreated — data loss and downtime unless there is a snapshot/migration plan. This is the finding that blocks an apply.
- **Cost:** if `monthly_cost` is far above the known baseline (~\$300/mo for this estate), flag the jump and name the resource driving it.

## Output schema

```json
{
  "plan": "infra/fixtures/plan-stateful-replace.json",
  "replacements": 1,
  "stateful_destroys": ["module.database.aws_db_instance.main"],
  "blast_radius": "high",
  "cost_monthly_usd": 301.97,
  "recommendation": "BLOCK: this plan destroys and recreates the production database. Do not apply without a verified snapshot and migration plan."
}
```

## Stop conditions

- If the plan file is missing or not valid JSON, report that and stop — do not review a plan you cannot parse.
- Do not run `terraform apply` or any mutating terraform command. This skill reviews only.

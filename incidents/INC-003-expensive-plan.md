# INC-003: Terraform Plan Shows Unexpected Cost Spike

**Severity:** P3 — Cost Risk
**Status:** Open
**Reported:** 2024-11-20T11:15:00Z
**Service:** Infrastructure (Terraform)
**On-Call:** FinOps / Platform Team

## Impact

A Terraform plan for the production environment shows a significant cost
increase. The estimated monthly cost has jumped from ~$302/month to
~$3,149/month — a 10x increase. No one on the team recalls approving
an instance size change.

## Current Evidence

- `terraform plan` output shows 1 resource to be modified
- The RDS instance class is changing from `db.r6g.large` to `db.r6g.4xlarge`
- Cost estimate: $3,036.80/month for the database alone (was $189.80)
- No PR or change request found for this modification
- The change is in `infra/environments/prod/terraform.tfvars`

## Investigation Commands

```bash
# Review the plan fixture
cat infra/fixtures/plan-oversize.json | jq '.resource_changes[] | select(.type == "aws_db_instance")'

# Compare cost estimates
diff <(cat infra/fixtures/cost-estimates/estimate-good.json | jq '.totalMonthlyCost') \
     <(cat infra/fixtures/cost-estimates/estimate-oversize.json | jq '.totalMonthlyCost')

# Check who changed the tfvars
git log --oneline -5 infra/environments/prod/

# Review the instance class in all environments
grep instance_class infra/environments/*/terraform.tfvars
```

## Hypothesis

The production database instance class was accidentally or maliciously changed
to a much larger (and more expensive) instance type.

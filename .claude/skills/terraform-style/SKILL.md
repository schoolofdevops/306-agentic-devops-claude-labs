---
name: terraform-style
description: Use when authoring or modifying Terraform in the Northstar estate (anything under infra/) — encodes the house HCL conventions, the security baselines that are not negotiable, the exact AWS vocabulary that prevents the common generation errors, and the offline verification contract. Produces or corrects HCL; never applies.
---

# terraform-style

The house style for Northstar's Terraform estate. Read this **before** writing a line of HCL under `infra/`,
and check generated HCL against it before saving.

This skill exists because a competent-looking module is not a house-consistent one. Reviewers should be
spending their attention on blast radius and cost, not on whether you called the resource `this` or `main`.

## Inputs

- `target` — the module directory being authored or changed (e.g. `infra/modules/read-replica`).
- `harness` — the verification directory that calls the module and holds the offline provider block
  (e.g. `infra/modules/read-replica/tests`). This is where `init`, `validate`, `test` and `plan` run.
- `estate` — the existing modules to match, always `infra/modules/` (`compute`, `database`, `networking`, `storage`).

## Deterministic zone — collect facts

Never assert style compliance from reading alone. Run the checks.

`fmt` works on any directory and needs no setup:

```bash
terraform -chdir="${target}" fmt -check -diff
```

It exits non-zero and prints a diff when spacing or alignment is off.

`validate` needs an initialized directory with a provider — a bare module directory exits 1 with
`Missing required provider`, which is a setup error, not a finding about the code. Validate from the
**verification harness** that calls the module (the directory holding the offline provider block below),
never from the module directory itself:

```bash
terraform -chdir="${harness}" init -input=false
terraform -chdir="${harness}" validate
```

Both must be clean before the module is offered for review.

To see the conventions you are matching rather than guessing at them:

```bash
grep -h 'resource "' infra/modules/*/main.tf
grep -A2 '^variable' infra/modules/database/variables.tf | head -20
```

## The conventions

### Naming
- The **primary** resource of a module carries the label `main` — `aws_db_instance.main`,
  `aws_db_subnet_group.main`. Secondary resources get a short role noun (`replica`, `alerts`, `cpu`), never
  `this`, never `default`, never a numbered suffix.
- Every **physical** name is interpolated, never literal:
  `"${var.project}-${var.environment}-<role>"`. A hardcoded `"northstar-prod-db"` is a bug even when it is
  currently correct — it collides the moment the module is reused in another environment.

### Variables
- Every variable has a `description` written as a sentence ending in a period, and an explicit `type`.
- Every module takes `project` (string, `default = "northstar"`) and `environment` (string, **no default** —
  the environment must be a deliberate choice at the call site).
- Order: identity (`project`, `environment`) → sizing → naming → networking → feature flags.
- Secrets carry `sensitive = true`. A password variable without it is a finding.
- Give a default only when the value is safe everywhere. Sizing and cost-bearing variables get a
  conservative default; anything environment-specific gets none.

### Outputs
- Every output has a `description`. An undocumented output is an undocumented API.
- Export what a caller needs to wire the module up — endpoints, identifiers, ARNs — never raw secrets.

### Tags
- Every taggable resource carries at least `Name`, matching its physical name:
  `tags = { Name = "${var.project}-${var.environment}-<role>" }`.

### Security baselines — hardcoded, not variabilized
These are properties of the estate, not choices a caller makes. Writing them as variables is itself the
finding, because it turns a guarantee into a default someone can override:
- `storage_encrypted = true` on every storage-bearing resource.
- `publicly_accessible` is never set to `true` on a database.
- No security group rule carries `0.0.0.0/0` on an ingress port. Egress may; ingress may not.
- Secrets are never written as literals in HCL — they arrive as `sensitive` variables.

### Layout
`main.tf` / `variables.tf` / `outputs.tf` per module. Provider and version constraints live in the root
`infra/versions.tf` — a module never pins its own provider.

## Exact AWS vocabulary — use these strings verbatim

Most generation failures in this estate are vocabulary, not logic. These are the values that are correct;
anything near-miss will validate and then behave wrongly or fail at plan time.

| Thing | Correct | Common wrong answer |
|---|---|---|
| RDS engine | `postgres` | `postgresql` |
| RDS engine version | `16.4` | `16` |
| Parameter group family | `postgres16` | `postgres-16` |
| CloudWatch metric (CPU) | `CPUUtilization` | `cpu_utilization` |
| CloudWatch metric (replica lag) | `ReplicaLag` | `ReplicationLag` |
| CloudWatch namespace | `AWS/RDS` | `AWS/rds` |
| Comparison operator | `GreaterThanThreshold` | `GreaterThanOrEqualToThreshold` |
| SNS subscription protocol | `email` | `mail` |
| Missing-data treatment | `notBreaching` | `not_breaching` |

## Offline verification contract

This estate is authored and verified without AWS credentials. Two mechanisms, and they answer different
questions — do not substitute one for the other.

**`terraform test` with `mock_provider`** answers *"is the module internally correct?"* Write the test
first; the resource addresses asserted in the test become the contract the HCL must satisfy.

```hcl
mock_provider "aws" {}
```

**A credential-skipped `plan`** answers *"what would this do to the estate?"* and is what produces the plan
JSON the review chain reads. Use exactly this provider block for offline planning:

```hcl
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "mock_access_key"
  secret_key                  = "mock_secret_key"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
}
```

The plan is real, the resource graph is real, the credentials are not. `terraform show -json` on the
resulting plan file emits the same shape the review scripts consume.

## Reasoning zone — check generated HCL before saving

Walk the generated files against these branches and name what you find:

- A resource labelled `this` or `default` → **STYLE: wrong resource label.** Rename to `main` (primary) or a
  role noun (secondary).
- A literal string where a name should be interpolated → **STYLE: hardcoded physical name.** Replace with
  `"${var.project}-${var.environment}-<role>"`.
- A variable with no `description` or no `type` → **STYLE: undocumented variable.**
- A password or token variable without `sensitive = true` → **SECURITY: secret not marked sensitive.**
- `storage_encrypted` absent or false, or `publicly_accessible = true`, or `0.0.0.0/0` on ingress →
  **SECURITY: baseline violated.** This one blocks; do not offer the module for review until it is fixed.
- A metric name, engine string, or comparison operator not in the vocabulary table →
  **CORRECTNESS: wrong AWS vocabulary.** Correct it against the table rather than guessing.
- A provider block inside a module directory (other than the offline plan harness) →
  **STYLE: module pins its own provider.** Move it to the root.

Every branch terminates in a named finding. "Looks fine" is not an output.

## Output schema

```json
{
  "target": "infra/modules/read-replica",
  "fmt_clean": true,
  "validate_clean": true,
  "findings": [
    {"severity": "security", "rule": "baseline violated", "detail": "storage_encrypted not set on aws_db_instance.replica"},
    {"severity": "style", "rule": "hardcoded physical name", "detail": "identifier = \"northstar-prod-replica\""}
  ],
  "verdict": "changes-required"
}
```

`verdict` is `compliant` only when `fmt_clean` and `validate_clean` are both true and no `security`
finding remains.

## NEVER DO

- **Never run `terraform apply` or `terraform destroy`.** This skill authors and checks; mutation is a
  separate authority and is gated by the Change Gate hook.
- **Never weaken a security baseline to make a plan pass.** If encryption or a CIDR is in the way, that is
  the review working, not an obstacle to route around.
- **Never invent an AWS attribute name.** If it is not in the vocabulary table and not in an existing
  module, check the provider docs rather than guessing a plausible spelling.
- **Never edit files under `infra/environments/prod/`** as part of authoring a module.

## Stop conditions

- If `terraform validate` fails, report the error and stop. Do not offer unvalidated HCL for review.
- If the target directory is outside `infra/`, stop — this skill governs the Terraform estate only.
- If a security baseline cannot be satisfied without changing the module's purpose, stop and say so
  explicitly. That is a design question for a human, not a style fix.

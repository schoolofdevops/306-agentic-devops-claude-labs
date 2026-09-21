---
name: terraform-style
description: Use when authoring or modifying Terraform in the Northstar infrastructure (anything under infra/) — encodes the house HCL conventions, the security baselines that are not negotiable, the exact AWS vocabulary that prevents the common generation errors, and the offline verification contract. Produces or corrects HCL; never applies.
---

# terraform-style

The house style for Northstar's Terraform infrastructure. Read this **before** writing a line of HCL under `infra/`,
and check generated HCL against it before saving.

This skill exists because a competent-looking module is not a house-consistent one. Reviewers should be
spending their attention on blast radius and cost, not on whether you called the resource `this` or `main`.

## Inputs

- `target` — the module directory being authored or changed (e.g. `infra/modules/read-replica`).
- `tests` — the module's own test directory (e.g. `infra/modules/read-replica/tests`), holding
  `*.tftest.hcl`. `terraform test` runs from the module root, not from inside this directory.
- `environment` — the environment that calls the module (e.g. `infra/environments/dev`). This is where
  `plan` runs and where the review chain's plan JSON comes from.
- `infrastructure` — the existing modules to match, always `infra/modules/` (`compute`, `database`, `networking`, `storage`).

## Deterministic zone — collect facts

Never assert style compliance from reading alone. Run the checks.

`fmt` works on any directory and needs no setup:

```bash
terraform -chdir="${target}" fmt -check -diff
```

It exits non-zero and prints a diff when spacing or alignment is off.

`validate` needs an initialized directory. Initialise the module and validate it, then run its tests
from the same place — the `tests/` subdirectory is discovered automatically:

```bash
terraform -chdir="${target}" init -input=false
terraform -chdir="${target}" validate
terraform -chdir="${target}" test
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
These are properties of the infrastructure, not choices a caller makes. Writing them as variables is itself the
finding, because it turns a guarantee into a default someone can override:
- `storage_encrypted = true` on every storage-bearing resource.
- `publicly_accessible` is never set to `true` on a database.
- No security group rule carries `0.0.0.0/0` on an ingress port. Egress may; ingress may not.
- Secrets are never written as literals in HCL — they arrive as `sensitive` variables.

### Layout
`main.tf` / `variables.tf` / `outputs.tf` per module. Provider and version constraints live in the root
`infra/versions.tf` — a module never pins its own provider.

## Exact AWS vocabulary — use these strings verbatim

Most generation failures in this infrastructure are vocabulary, not logic. These are the values that are correct;
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

This infrastructure is authored and verified without AWS credentials. Two mechanisms, and they answer
different questions — do not substitute one for the other.

### `terraform test` — "is the module internally correct?"

Put the test in `<module>/tests/*.tftest.hcl` and run `terraform test` **from the module root**. With that
layout Terraform tests the module directly, so assertions address its resources by their real names:

```hcl
mock_provider "aws" {}

run "replica_is_encrypted" {
  command = plan
  assert {
    condition     = aws_db_instance.replica.storage_encrypted == true
    error_message = "Replica storage must always be encrypted."
  }
}
```

**Do not wrap the module in a caller just to test it.** A wrapper (`module "x" { source = "../" }` inside
the test directory) puts a module boundary between the test and the code, and a module exposes only its
declared outputs — so `module.x.aws_db_instance.replica.storage_encrypted` is unreachable. Terraform
reports `This object does not have an attribute named "aws_db_instance"`. Working around that by adding
outputs for security flags is worse: outputs exist so a caller can wire the module up, not to let a test
read internal state.

**Attributes that are unknown at plan time** (an ARN, an id — anything the provider computes on apply)
cannot be asserted directly under `command = plan`. Supply them rather than weakening the assertion:

```hcl
override_resource {
  target          = aws_sns_topic.alerts
  override_during = plan
  values = { arn = "arn:aws:sns:us-east-1:123456789012:example-alerts" }
}
```

**When you extract a child module, its assertions move with it.** Tests for what the child now owns belong
in the child's own `tests/`; the parent keeps a test proving it is actually wired to the child. A parent
test that asserts nothing about the wiring cannot tell you the child is orphaned.

### A plan from an environment — "what would this do to the infrastructure?"

The review chain reads plan JSON, and that plan comes from an **environment that calls the module**, not
from the module on its own. A module is not a root module: planning it standalone means supplying every
variable by hand, and it tells you nothing about how the change lands among everything else.

```bash
terraform -chdir=infra/environments/dev plan -out=tfplan
terraform -chdir=infra/environments/dev show -json tfplan > plan.json
```

The plan is real and the resource graph is real. `terraform show -json` emits the shape the review scripts
consume, and the module's resources appear under `module.<name>.*` alongside everything already there.

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
- A provider block inside a module directory →
  **STYLE: module pins its own provider.** Move it to the root. A module's tests declare
  `mock_provider "aws" {}` in the test file itself; that is not a provider block on the module.

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
- If the target directory is outside `infra/`, stop — this skill governs the Terraform infrastructure only.
- If a security baseline cannot be satisfied without changing the module's purpose, stop and say so
  explicitly. That is a design question for a human, not a style fix.

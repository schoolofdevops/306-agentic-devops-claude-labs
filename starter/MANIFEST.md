# northstar-ops-starter — MANIFEST

The operating layer, packaged as a reusable, versioned starter. This is the
"what ships" list for the deep-dive: everything a new team needs to inherit the
governed workbench, and nothing project-specific to Northstar.

## What belongs in the starter (reusable)

| Piece | Where | Why it is reusable |
|---|---|---|
| Role agents (7) | `agents/` | authority boundaries, not Northstar business logic |
| Skills (6) | `skills/` | runbook procedures parameterised by service, not hard-coded |
| Change gate | `hooks/change-gate.sh` | the deny rules are policy, portable to any repo |
| Contracts | `authority-matrix`, `environment-contract`, `change-contract` | the governance schema |
| Observer MCP | `mcp/observer.json` | read-only telemetry lens |
| Regression + authority gates | `scripts/regression-gate.sh`, `scripts/role-authority-check.sh` | promotion gates |
| Adoption ladder | `adoption-ladder.yaml` | the rollout policy itself |

## What stays project-specific (does NOT ship in the starter)

- Incident tickets (`incidents/`) — specific to Northstar's systems.
- Fault fixtures and plan JSON (`fixtures/`, `infra/fixtures/`) — Northstar's estate.
- The answer key (`evals/retry-storm-key.json`) — graded against Northstar's incident.
- Service source (`app/`, `platform/helm/`) — the product, not the operating layer.

## Ownership & cadence

- **Owner:** the platform team owns the starter as an internal product.
- **Security review:** any change to `authority-matrix.yaml` or a hook decision is
  reviewed before merge — those are the pieces that can widen blast radius.
- **Update cadence:** MINOR releases monthly or on a new role/skill; PATCH as needed;
  MAJOR only for an authority or schema break, gated on a security review.
- **Rollback:** pin the previous `version` in `plugin.json`; the change gate and
  contracts are the last-known-good, so a bad release reverts to a known state.

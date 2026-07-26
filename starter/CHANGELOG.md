# Changelog — northstar-ops-starter

All notable changes to the operating layer are recorded here. The starter is
versioned with [semantic versioning](https://semver.org): a breaking change to
any agent authority, hook decision, or contract schema bumps MAJOR; a new role,
skill, or check bumps MINOR; a fix that does not change behaviour bumps PATCH.

## [1.0.0] — 2026-07-26

First stable release of the Northstar operating layer, packaged from the
agentic-ops-lab spine after the M19 capstone.

### Added
- Seven governed role agents: sre-investigator, iac-engineer, platform-engineer,
  security-reviewer, finops-analyst, mlops-engineer, change-reviewer.
- Incident-response skills: incident-triage, k8s-diagnose, release-check,
  service-health, service-restart, terraform-plan-review.
- The PreToolUse change gate (`hooks/change-gate.sh`) — denies production
  `terraform apply`, protected-namespace deletes, wildcard blast radius,
  secret-printing commands, and direct `docker push`.
- Governance contracts: authority-matrix, environment-contract, change-contract,
  plus the evidence-packet and release-verdict schemas.
- The read-only observer MCP config (`mcp/observer.json`).
- The capstone workflow orchestrator (`scripts/capstone-triage.sh`) and the
  regression + authority gates that guard every future change.

### Authority boundaries frozen at this version
- Writers: iac-engineer, platform-engineer. Every other role is read-only.
- Any change to that set is a MAJOR version bump and requires a security review.

## Deprecation policy

A role, skill, or hook is retired over two MINOR releases: first marked
`deprecated` in this changelog with a replacement named, then removed in the
following MINOR with the removal recorded under a `### Removed` heading. Nothing
is removed silently.

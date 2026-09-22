---
name: secops-triage
description: Use to run Northstar's pre-release security triage end-to-end — fan out the scan corpus to the three specialist roles (dep-triage, secret-triage, posture-auditor), collect their schema'd findings, and hand the merged set to security-reviewer for the ship/no-ship synthesis. Orchestrating skill; owns sequencing, not judgement.
---

# secops-triage

Northstar's scanners (`trivy`, `gitleaks`, `secops-surface-scan.sh`, `tf-security-scan.sh`) produce a
few hundred findings across two services, the cluster and the infrastructure — more than fits in one
context window, and none of the four classes is qualified to judge the other three. This skill owns
the **fan-out and handoff**, not the ranking — ranking authority stays with the specialist roles and
`security-reviewer`, per `secfinding-style`.

## Why three lanes, not one pass

Dependency CVEs, committed secrets, and cluster/IaC posture are independent finding classes with
different evidence types (reachability grep vs. rotation history vs. manifest correlation). One role
reading all four scanners' raw output would blow its context budget and — the sharper risk — default
to sorting the combined table by CVSS, which is exactly the trap `secfinding-style` exists to prevent.
Fan out, then synthesize.

## Sequence

1. **Corpus.** Confirm `agentops/secops/scan-corpus.json` (or the individual
   `agentops/secops/trivy-*.json`, `gitleaks.json`, `posture-surface.json`) is present and recent. If
   missing, run `scripts/tf-security-scan.sh` and `scripts/secops-surface-scan.sh`, and `trivy`/
   `gitleaks` against `app/orders-api`, `app/inventory-api`, `platform/secfixtures/vulnerable-service`.
   Do not re-scan if a corpus already exists for this revision — reuse it.
2. **Fan out, in parallel, one Agent dispatch per lane:**
   - `dep-triage` — dependency + image CVEs (trivy). Give it the corpus path; do not paste the raw
     JSON into its prompt — it reads the file itself.
   - `secret-triage` — committed credentials (gitleaks), including git-history-only leaks.
   - `posture-auditor` — cluster + IaC posture (`secops-surface-scan.sh`, `tf-security-scan.sh`,
     manual correlation across RBAC/NetworkPolicy/Terraform plan).
   Each returns findings in the `secfinding-style` schema via its handoff block. Do not paste one
   lane's findings into another lane's prompt — they triage independently so no lane anchors on
   another's severity ordering.
3. **Collect.** Merge the three findings arrays. Do not re-rank them yourself — that is
   `security-reviewer`'s job, not this skill's.
4. **Hand off to `security-reviewer`** with all three lanes' findings plus their `sources` lists. The
   reviewer synthesizes one ranked list and the ship/no-ship verdict, and is the role responsible for
   writing `agentops/secops/verdict.json` that `release-gate-secops.sh` reads.

## Guard against consensus theater

If any lane's findings arrive sorted by CVSS/severity with `reachable`/`exposure` fields unfilled or
stubbed, do not forward them as-is — that lane skipped its actual job. Send it back rather than let
`security-reviewer` inherit a severity-only ranking it then has to un-rank. A synthesis step that
"agrees" with a specialist who ranked by CVSS has reproduced the fault this whole skill exists to
catch, not resolved it.

## Stop conditions

- Do not have this skill itself decide reachability, exposure, or rank — it sequences roles that hold
  that authority; it holds none of its own.
- Do not skip a lane because its scanner produced zero findings this run — say so explicitly in the
  handoff (an empty lane is a fact `security-reviewer` needs, not an omission).
- Do not let `security-reviewer` proceed to a verdict without all three lanes' handoffs present.

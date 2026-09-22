---
name: secfinding-style
description: Use whenever emitting a security finding from any SecOps triage role (dep-triage, secret-triage, posture-auditor, security-reviewer) — the fixed finding schema and the ranking rubric. This is the house standard that makes four independent specialist reports comparable and mergeable into one ranked list.
---

# secfinding-style

Every finding any SecOps role emits uses this exact schema. A synthesis role (`security-reviewer`)
merges reports from three independent specialists — if each used its own shape, merging would mean
re-deriving their reasoning instead of comparing it.

## The schema

```json
{
  "finding": "one sentence, plain language",
  "source_tool": "trivy | gitleaks | secops-surface-scan.sh | tf-security-scan.sh | manual-correlation",
  "component": "package@version, or path:line, or manifest name(s)",
  "reachable": "yes | no | unknown | n/a",
  "exposure": "internet-facing | internal-only | n/a",
  "compensating_control": "none | description",
  "rank": "1 (highest priority) .. N",
  "evidence": "file:line, command output, or scanner JSON path — never a bare claim",
  "confidence": "high | medium | low"
}
```

Every field is required. `"unknown"` and `"low confidence"` are legitimate values — a role that
cannot determine reachability must say `unknown`, not guess `yes` or silently drop the field.

## The ranking rubric — reachability × exposure × blast radius, never CVSS alone

Rank findings using these three axes, in this priority order:

1. **Reachability.** `reachable: no` (or a dead transitive dependency) ranks at the bottom regardless
   of severity. `reachable: yes` on a path a real caller can hit ranks it into contention.
2. **Exposure.** Among reachable findings, `internet-facing` outranks `internal-only`.
3. **Blast radius.** Among findings tied on the first two axes, what the finding unlocks if exploited
   — read access to a database, every Secret in a namespace, arbitrary code execution — breaks the tie.

CVSS/severity is **not** an axis. It is metadata carried in the finding's prose, never the sort key.
A CRITICAL CVE that is `reachable: no` ranks below a MEDIUM CVE that is `reachable: yes` and
`internet-facing`. If your ranked list sorts by severity, it is wrong — redo it against these three
axes.

## Reachability is not eyeballed

Never assert `reachable: yes|no` from reading a CVE description or guessing from a package name. Run
the `reachability-check` skill and cite its `file:line` output as the `evidence` field. If
`reachability-check` cannot determine an answer, the finding's `reachable` field is `unknown` — not a
guess in either direction.

## Stop conditions

- Do not emit a finding without all nine fields populated.
- Do not rank by severity/CVSS — if you catch yourself sorting by the trivy table's order, stop and
  re-rank by the rubric above.
- Do not claim `compensating_control: none` without having actually read the relevant NetworkPolicy /
  RBAC / auth layer — an unchecked "none" is a guess wearing a verdict's clothes.

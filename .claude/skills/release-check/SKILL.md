---
name: release-check
description: Use before cutting a release or tagging a build — to confirm both services are healthy, the test suite passes, and the working tree is clean. A go/no-go gate; reports a verdict, never ships.
---

# release-check

Run the pre-release gate: services healthy, tests green, tree clean. Reports GO or NO-GO. Read-only — it never tags, pushes, or deploys.

## Inputs

- none — checks the whole workspace and both running services.

## Deterministic zone — collect evidence

Collect the three signals a release depends on. Capture each result; do not decide yet.

```bash
# 1. Both services healthy
curl -s -o /dev/null -w 'orders_healthz=%{http_code}\n'    http://localhost:8080/healthz
curl -s -o /dev/null -w 'inventory_healthz=%{http_code}\n' http://localhost:8081/healthz

# 2. Test suite passes (orders-api)
( cd app/orders-api && .venv/bin/python -m pytest -q ) ; echo "pytest_exit=$?"

# 3. No uncommitted changes
git status --short ; echo "tree_lines=$(git status --short | wc -l | tr -d ' ')"
```

## Reasoning zone — analyze

The gate is a conjunction — every signal must be green for a GO:

- both `*_healthz=200`, **and**
- `pytest_exit=0`, **and**
- `tree_lines=0` (clean tree).

Any single failure is a **NO-GO**, and the report names which signal failed and why. A dirty tree is a NO-GO even if everything else is green — you do not tag a build you cannot reproduce from a commit.

## Output schema

```json
{
  "verdict": "NO-GO",
  "checks": { "orders_healthz": 200, "inventory_healthz": 200, "tests": "pass", "tree_clean": false },
  "blocking": ["uncommitted changes in working tree"],
  "recommendation": "Commit or stash working-tree changes, then re-run release-check."
}
```

## Stop conditions

- If a service is unreachable, the verdict is NO-GO (cannot confirm health) — report and stop; do not assume healthy.
- Report the verdict only. Do **not** create a tag, push, or trigger a deploy. Shipping is a human decision made *after* a GO.

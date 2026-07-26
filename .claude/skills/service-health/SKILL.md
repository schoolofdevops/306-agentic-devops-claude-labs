---
name: service-health
description: Use when you need to check whether a Northstar service (orders-api or inventory-api) is healthy — before a deploy, during triage, or when someone reports a service is misbehaving. Reports status only; never fixes.
---

# service-health

Check one Northstar service's health and report its status. Read-only: this skill observes and reports, it never restarts or changes anything.

## Inputs

- `service` — which service to check: `orders-api` (port 8080) or `inventory-api` (port 8081).

## Deterministic zone — collect evidence

Run the probes for the chosen service and capture the raw output. `/healthz` is liveness (is the process up?); `/readyz` is readiness (are its dependencies reachable?). Do not interpret yet — just collect.

```bash
PORT=8080   # inventory-api is 8081
curl -s -o /dev/null -w 'healthz=%{http_code}\n' "http://localhost:${PORT}/healthz"
curl -s -w '\nreadyz_http=%{http_code}\n'        "http://localhost:${PORT}/readyz"
```

If the first curl returns `000`, the service is unreachable — go straight to the stop conditions.

## Reasoning zone — analyze

With the raw evidence collected, interpret it:

- `healthz=200` and `readyz` status `ready` → healthy.
- `healthz=200` but `readyz` not ready → the process is up but a **dependency** is failing. Read the `checks` object in the readyz body and name which dependency (e.g. `inventory_api: false`). This is an upstream problem, not this service crashing.
- `healthz` not 200 → the process itself is unhealthy.

## Output schema

```json
{
  "service": "orders-api",
  "healthy": false,
  "checks": { "healthz": 200, "readyz": "not ready", "inventory_api": false },
  "recommendation": "orders-api is live but not ready; its inventory-api dependency check is failing. Investigate inventory-api, not orders-api."
}
```

## Stop conditions

- If the service is unreachable (`healthz=000`, connection refused), report that it is unreachable and **stop**. Do not guess a status you could not measure.
- Do not attempt any fix, restart, or config change. This skill reports only. Restarting is a separate, human-only skill.

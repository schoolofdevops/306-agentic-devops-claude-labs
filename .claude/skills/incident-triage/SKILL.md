---
name: incident-triage
description: Use when an incident ticket lands (INC-00N) and you need a structured evidence packet before anyone forms a hypothesis — reads the ticket, collects the bounded evidence it points to, and fills the evidence-packet template. Collects evidence only; never fixes.
---

# incident-triage

Turn an incident ticket into a filled evidence packet: read the ticket, run only the evidence its scope points to, and record what you found. Read-only — triage collects, it does not remediate.

## Inputs

- `incident` — path to the ticket, e.g. `incidents/INC-001-readiness-failure.md`.

## Deterministic zone — collect bounded evidence

Read the ticket to learn the affected service and its stated investigation commands, then collect exactly that evidence — no more. The bound is the point: triage is scoped fact-gathering, not a free-roaming investigation.

```bash
cat "${incident}"                          # read scope: service, impact, listed commands
# Service health (both services — cheap, always in scope for triage)
curl -s -o /dev/null -w 'orders_healthz=%{http_code}\n'    http://localhost:8080/healthz
curl -s -w 'orders_readyz=%{json}\n'                       http://localhost:8080/readyz
curl -s -o /dev/null -w 'inventory_healthz=%{http_code}\n' http://localhost:8081/healthz
```

Run any additional read-only commands the ticket's "Investigation Commands" section lists — and only those.

## Reasoning zone — assemble the packet

Fill the evidence-packet template (`incidents/templates/evidence-packet.md`) from the collected evidence: the service-health table, any config/metric values the ticket calls out, and the commands you ran. Note gaps honestly — a field you could not measure is recorded as unknown, not guessed. Do **not** state a root cause; triage hands a clean packet to whoever forms the hypothesis.

## Output schema

```json
{
  "incident": "INC-001",
  "service": "orders-api",
  "evidence": {
    "orders_healthz": 200,
    "orders_readyz": "not ready",
    "inventory_healthz": 200
  },
  "gaps": ["could not reach cluster events (running local, not k8s)"],
  "packet": "path to the filled evidence-packet.md",
  "next_step": "Hand packet to on-call for hypothesis (do not fix here)."
}
```

## Stop conditions

- Collect **only** the evidence the ticket's scope points to — do not expand into unrelated services or mutate anything to "see what happens". Triage is bounded by design.
- Report only. Do **not** attempt a fix, restart, or config change; that is a separate, human-approved action after the hypothesis is confirmed.

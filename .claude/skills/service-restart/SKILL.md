---
name: service-restart
description: Use ONLY when a human has decided a Northstar service must be restarted and explicitly invokes this skill. This skill has side effects (it restarts a running service). It is human-only — it must never be auto-invoked by relevance.
auto-invoke: false
---

# service-restart

Restart a Northstar service. **This skill changes state.** It is human-only: it runs only when a person types `/service-restart` on purpose — never because the agent inferred it was relevant. Restarting the wrong service, or restarting during traffic, is exactly the kind of action that must be a deliberate human choice.

## Why human-only

A skill that *observes* (service-health, k8s-diagnose) is safe to auto-invoke — the worst case is an unneeded report. A skill that *mutates* is not: the worst case is an unrequested restart of a live service. So the trigger for this skill is a human's explicit invocation, not the model's relevance judgment.

This does **not** make the restart itself safe. Even when a human invokes it, the actual restart command still runs under the tool and permission boundaries from Module 2 — the deny rules and sandbox still apply. Human-only controls *who can trigger* the skill; it does not grant the skill any authority to step outside the environment's policy.

## Inputs

- `service` — which service to restart: `orders-api` or `inventory-api`.
- `reason` — one line stating why (goes in the record).

## Deterministic zone — the side effect

```bash
docker compose restart "${service}"
```

## Stop conditions

- If invoked automatically (not by an explicit human `/service-restart`), refuse and report why — this skill is human-only by design.
- If the restart command is blocked by a permission or sandbox policy, report the block. Do **not** try to work around it — the policy is the floor, and a skill does not override it.

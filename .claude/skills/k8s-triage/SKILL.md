---
name: k8s-triage
description: Use when more than one workload in a namespace is unhealthy and they must be triaged and ranked. Collects bounded evidence per workload and emits one fixed-schema finding each. Read-only; never mutates the cluster. Differs from k8s-diagnose, which is single-workload, free-form, and has no output schema — reach for k8s-diagnose when you already know which one workload is broken and want a narrative cause; reach for k8s-triage when several workloads are unhealthy and the findings must be ranked against each other.
---

# k8s-triage

Triage multiple unhealthy Kubernetes workloads in one namespace, one at a time, and emit a
fixed-schema finding for each so they can be ranked against each other. Read-only.

## Inputs

- `NS` — namespace, e.g. `northstar`.
- Per workload: `WORKLOAD` (deployment name), `SELECTOR` (label selector, e.g. `app=<workload>`),
  `POD` (a pod name matching the selector), `SERVICE` (the Service fronting the workload, e.g.
  `<workload>-svc`).

## Deterministic zone — per workload, exactly these five bounded reads

```bash
platform/bin/kubectl-bounded get pods -n "$NS" -l "$SELECTOR" -o wide
platform/bin/kubectl-bounded describe deployment "$WORKLOAD" -n "$NS"
platform/bin/kubectl-bounded get events -n "$NS" --field-selector involvedObject.name="$POD" --sort-by=.lastTimestamp
platform/bin/kubectl-bounded logs "$POD" -n "$NS" --previous --tail=50
platform/bin/kubectl-bounded get endpointslices -n "$NS" -l kubernetes.io/service-name="$SERVICE" \
  -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{"\n"}{end}'
```

**The fifth read is load-bearing and is not optional.** Two things depend on it. The output
schema below demands `serving | not serving`, which cannot be known from pod status alone — a pod
can sit `Running` and still be absent from its Service. And fault 04's SECOND defect (readiness
probing `/ready`:8080 while nginx serves 80) is invisible without it: the restart count reveals the
liveness defect, but only an empty endpoint list reveals that the Service has nothing behind it.
Measured on the live cluster: `liveness-probe-test` pods were `Running` with climbing restarts while
`liveness-probe-test-svc` had zero READY endpoints.

**Read the ready condition, never the ADDRESSES column — this is measured, and it is a trap.** An
EndpointSlice lists an address whether or not that address is ready. On the live cluster
`liveness-probe-test-svc` shows two addresses in the `ENDPOINTS` column while BOTH carry
`ready=false, serving=false`, and the legacy `kubectl get endpoints` view is empty because it lists
only ready addresses. An agent that reads the address list concludes the Service is healthy; an agent
that reads `.conditions.ready` sees the truth. Hence the jsonpath above rather than a bare `get`.
This is worth teaching in the lesson: the evidence command that lies if you read the wrong column.

Use `endpointslices`, never `endpoints` — `kubectl get endpoints` prints
`Warning: v1 Endpoints is deprecated in v1.33+` on this cluster (v1.36.1), and a skill should not
teach a deprecated command or spray warnings into learner output.

## Reasoning zone — emit exactly this per workload, nothing else

```
workload:      <name>
signature:     <ImagePullBackOff | CrashLoopBackOff | Pending | RestartLoop | ConfigError>
root_cause:    <one sentence>
evidence:      <the single command output line that proves it>
blast_radius:  <replicas affected> of <replicas desired>, <serving | not serving>
confidence:    <high | medium | low>
```

## Stop conditions

Stop after five workloads; stop and say so if a read returns 403; never propose or run a mutating
command.

**The schema is the point.** Five free-form essays cannot be ranked against each other; five
identical records can.

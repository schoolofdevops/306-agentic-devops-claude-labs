---
name: k8s-diagnose
description: Use when a Kubernetes workload is unhealthy — pods CrashLooping, not Ready, pending, or an incident points at the cluster. Collects pod status, events, and logs and reports the likely cause. Read-only diagnosis; never mutates the cluster.
---

# k8s-diagnose

Diagnose a struggling Kubernetes workload by collecting status, events, and logs, then reporting the most likely cause. Read-only.

## Inputs

- `namespace` — e.g. `northstar`.
- `selector` — label selector for the workload, e.g. `app=orders-api`.

## Deterministic zone — collect evidence

Run these read-only queries and capture the raw output. Every command here only *reads* cluster state.

```bash
kubectl get pods -n "${namespace}" -l "${selector}" -o wide
kubectl describe pod -n "${namespace}" -l "${selector}"
kubectl get events -n "${namespace}" --sort-by=.lastTimestamp | tail -20
kubectl logs -n "${namespace}" -l "${selector}" --tail=50 --all-containers --previous 2>/dev/null || \
  kubectl logs -n "${namespace}" -l "${selector}" --tail=50 --all-containers
```

## Reasoning zone — analyze

Match the collected evidence to the common failure patterns:

- **CrashLoopBackOff** + a non-zero exit in `describe` → the container is dying on start. Read the previous logs for the reason (bad config, missing env var, failed migration).
- **Running but `0/1 READY`** + `Readiness probe failed: HTTP probe failed with statuscode: 404` → the readiness probe path is wrong (this estate's probe should be `/healthz`, not `/health`). The process is fine; the probe config is not.
- **OOMKilled** in `describe` → memory limit too low or a leak. Note if no `resources.limits` are set.
- **Pending** → no schedulable node / unsatisfiable resource request.

## Output schema

```json
{
  "namespace": "northstar",
  "selector": "app=orders-api",
  "pod_state": "CrashLoopBackOff",
  "likely_cause": "Readiness probe hits /health (404); should be /healthz",
  "evidence": ["Readiness probe failed: statuscode 404", "liveness on /healthz passes"],
  "recommendation": "Fix the readiness probe path in the Helm values to /healthz. Remediation is a separate, human-approved change — not part of this diagnosis."
}
```

## Stop conditions

- If no pods match the selector, report that and stop — do not diagnose a workload that is not there.
- Report the cause and a recommendation only. This skill runs **no** mutating cluster verbs — it never applies, deletes, scales, rolls out, or edits. Applying a fix is a separate, human-approved action.

# INC-004: Failed Kubernetes Rollout — Pods CrashLooping

**Severity:** P1 — Service Outage
**Status:** Open
**Reported:** 2024-11-22T16:05:00Z
**Service:** orders-api (Kubernetes)
**On-Call:** Platform Team

## Impact

A deployment update to orders-api has caused all pods to enter CrashLoopBackOff.
The previous version was fully replaced during the rollout (no pods from the old
ReplicaSet remain), leaving zero healthy pods serving traffic. Complete service
outage.

## Current Evidence

- `kubectl get pods` shows all orders-api pods in CrashLoopBackOff
- Previous ReplicaSet scaled to 0 (no rollback target with running pods)
- Deployment strategy allowed 100% unavailability during rollout
- Readiness probe failing with 404 on the new pods
- No resource limits set, so pods are consuming uncontrolled memory
- Rollout happened 12 minutes ago

## Timeline

| Time | Event |
|------|-------|
| 15:50 | Deployment update pushed via Argo CD sync |
| 15:51 | All existing pods terminated (maxUnavailable: 100%) |
| 15:52 | New pods start, readiness probes begin failing |
| 15:55 | All new pods enter CrashLoopBackOff |
| 16:00 | ServiceDown alert fires |
| 16:05 | Incident created — P1 declared |

## Investigation Commands

```bash
# Check pod status
kubectl get pods -n northstar -l app=orders-api

# Check deployment strategy
kubectl get deploy orders-api -n northstar -o jsonpath='{.spec.strategy}'

# Check resource limits
kubectl get deploy orders-api -n northstar -o jsonpath='{.spec.template.spec.containers[0].resources}'

# Check rollout history
kubectl rollout history deploy/orders-api -n northstar

# Review Helm values for defects
cat platform/helm/orders-api/values.yaml | grep -A5 -E 'strategy|resources|readiness'

# Rollback
kubectl rollout undo deploy/orders-api -n northstar
```

## Hypothesis

Multiple deployment defects combined: the rollout strategy allows 100%
unavailability (no safe rollout), readiness probe checks wrong path,
and no resource limits are set. The rollout replaced all pods at once
with broken ones.

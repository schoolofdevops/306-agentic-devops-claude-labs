# INC-001: Orders API Readiness Failure

**Severity:** P2 — Service Degraded
**Status:** Open
**Reported:** 2024-11-15T09:23:00Z
**Service:** orders-api
**On-Call:** Platform Team

## Impact

Orders API is reporting as not ready. Kubernetes readiness probe is failing,
causing the pod to be removed from the Service endpoint pool. No traffic is
reaching the orders API, but the pod itself is running (liveness probe passes).

## Current Evidence

- `kubectl get pods` shows orders-api pod as `Running` but `0/1 READY`
- Readiness probe failure: `HTTP probe failed with statuscode: 404`
- Liveness probe (`/healthz`) succeeds normally
- inventory-api is healthy and responding on all endpoints
- No recent deployments or config changes

## Timeline

| Time | Event |
|------|-------|
| 09:15 | Monitoring alert: orders-api readiness probe failing |
| 09:18 | PagerDuty triggered for on-call platform engineer |
| 09:23 | Incident created |

## Investigation Commands

```bash
# Check pod status
kubectl get pods -n northstar -l app=orders-api

# Describe pod for events
kubectl describe pod -n northstar -l app=orders-api

# Check readiness probe configuration
kubectl get deploy orders-api -n northstar -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'

# Test the endpoint directly
kubectl exec -n northstar deploy/orders-api -- curl -s http://localhost:8080/readyz

# Check what endpoint the probe is hitting
kubectl get deploy orders-api -n northstar -o yaml | grep -A5 readinessProbe
```

## Hypothesis

The readiness probe may be configured to check an incorrect endpoint path.

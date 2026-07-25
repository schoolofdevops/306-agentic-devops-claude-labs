# INC-006: Campaign Launch Multi-Signal Incident

**Severity:** P0 — Critical Business Impact
**Status:** Open
**Reported:** 2024-12-01T08:00:00Z
**Service:** All (orders-api, inventory-api, infrastructure, platform)
**On-Call:** Full Incident Response Team

## Impact

During a major product campaign launch, multiple systems are failing
simultaneously. This is a compound incident affecting the application layer,
infrastructure, and platform. Customer orders are failing, monitoring shows
multiple alerts, and the Terraform plan for scaling has suspicious changes.

## Active Failures

1. **Application**: orders-api retry storm (upstream timeouts cascading)
2. **Infrastructure**: Terraform plan shows db.r6g.4xlarge and open security groups
3. **Platform**: Kubernetes pods have no resource limits, flapping under load
4. **Observability**: Multiple Prometheus alerts firing simultaneously
5. **Documentation**: Runbook references a non-existent endpoint

## Current Evidence

- Prometheus: HighErrorRate, LatencyBreach, UpstreamTimeoutSpike all firing
- orders-api error rate: 45%
- orders-api p95 latency: 35 seconds
- Terraform plan for prod shows 3 suspicious changes
- Kubernetes HPA not scaling (no resource requests defined)
- On-call runbook step 3 fails (endpoint `/api/v1/status` does not exist)
- Campaign launch is in 2 hours — business pressure to resolve

## Timeline

| Time | Event |
|------|-------|
| 07:30 | Pre-launch load test begins |
| 07:35 | Latency increases detected |
| 07:40 | First HighErrorRate alert fires |
| 07:45 | Multiple alerts cascading |
| 07:50 | Infra team discovers suspicious Terraform plan |
| 07:55 | On-call engineer reports runbook is stale |
| 08:00 | P0 incident declared — all hands on deck |

## Investigation Approach

This incident requires parallel investigation across multiple domains:

### Track 1: Application (SRE Investigator)
```bash
curl -s http://localhost:8081/admin/faults | jq .
curl -s http://localhost:8080/metrics | grep -E 'retries|errors|duration'
docker compose exec orders-api env | grep -E 'RETRY|TIMEOUT'
```

### Track 2: Infrastructure (IaC Engineer)
```bash
cat infra/fixtures/plan-oversize.json | jq '.resource_changes[] | select(.change.actions != ["no-op"])'
cat infra/fixtures/plan-wide-network.json | jq '.resource_changes[] | select(.type | contains("security"))'
```

### Track 3: Platform (Platform Engineer)
```bash
kubectl get deploy orders-api -n northstar -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get hpa -n northstar
cat platform/helm/orders-api/values.yaml | grep -A3 strategy
```

### Track 4: Documentation (Change Reviewer)
```bash
grep -n '/api/v1/status' runbooks/*.md
diff runbooks/service-restart.md runbooks/service-restart.md.bak 2>/dev/null
```

## Resolution Requires

- [ ] Clear fault injection on inventory-api
- [ ] Fix retry/timeout configuration on orders-api
- [ ] Review and reject dangerous Terraform plan changes
- [ ] Add resource limits to Kubernetes deployments
- [ ] Fix stale runbook endpoint references
- [ ] Add guardrails to prevent recurrence

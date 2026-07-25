# INC-002: Upstream Retry Storm — Cascading Timeouts

**Severity:** P1 — Service Outage
**Status:** Open
**Reported:** 2024-11-18T14:42:00Z
**Service:** orders-api, inventory-api
**On-Call:** SRE Team

## Impact

Orders API is experiencing cascading failures. Response times have spiked to
30+ seconds. Error rate is above 30%. The ops dashboard shows error sparklines
climbing and upstream latency through the roof. Customer-facing order placement
is effectively down.

## Current Evidence

- orders-api p95 latency: 28.3 seconds (normal: <200ms)
- orders-api error rate: 31% (SLO: <1%)
- inventory-api responding, but with high latency and intermittent 500s
- Prometheus alert: HighErrorRate firing for 8 minutes
- Prometheus alert: UpstreamTimeoutSpike firing for 6 minutes
- orders-api retry count metric climbing rapidly
- No infrastructure changes in the last 24 hours

## Timeline

| Time | Event |
|------|-------|
| 14:30 | inventory-api latency begins increasing |
| 14:35 | Prometheus UpstreamTimeoutSpike alert fires |
| 14:38 | Prometheus HighErrorRate alert fires |
| 14:42 | Incident created — P1 declared |

## Investigation Commands

```bash
# Check current retry configuration
docker compose exec orders-api env | grep -E 'RETRY|TIMEOUT'

# Check inventory-api fault state
curl -s http://localhost:8081/admin/faults | jq .

# Check Prometheus metrics
curl -s http://localhost:8080/metrics | grep upstream_retries
curl -s http://localhost:8080/metrics | grep upstream_errors

# Check orders-api logs for retry patterns
docker compose logs orders-api --tail 50

# Clear fault injection
curl -s -X DELETE http://localhost:8081/admin/faults
```

## Hypothesis

Aggressive retry configuration on orders-api combined with upstream latency
is creating a retry storm — each timeout triggers more retries, amplifying load.

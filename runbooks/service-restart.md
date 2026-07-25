# Runbook: Service Restart

**Last Updated:** 2024-11-10
**Owner:** Platform Team
**Services:** orders-api, inventory-api

## When to Use

- Service is unresponsive but infrastructure is healthy
- After applying configuration changes that require restart
- Memory leak suspected (high memory usage, degraded performance)

## Prerequisites

- Docker Compose access OR kubectl access to the cluster
- Verify the service is actually unhealthy before restarting

## Steps

### Docker Compose (Development)

1. Check current service status:
   ```bash
   docker compose ps
   ```

2. Restart the specific service:
   ```bash
   docker compose restart <service-name>
   ```

3. Verify the service is healthy:
   ```bash
   curl -s http://localhost:8080/healthz  # orders-api
   curl -s http://localhost:8081/healthz  # inventory-api
   ```

4. Check logs for startup errors:
   ```bash
   docker compose logs <service-name> --tail 20
   ```

### Kubernetes (Production)

1. Check pod status:
   ```bash
   kubectl get pods -n northstar -l app=<service-name>
   ```

2. Restart via rollout:
   ```bash
   kubectl rollout restart deploy/<service-name> -n northstar
   ```

3. Watch rollout progress:
   ```bash
   kubectl rollout status deploy/<service-name> -n northstar
   ```

4. Verify pod health:
   ```bash
   kubectl get pods -n northstar -l app=<service-name>
   ```

## Rollback

If the restart makes things worse:
```bash
kubectl rollout undo deploy/<service-name> -n northstar
```

## Escalation

If service does not recover after restart, escalate to the SRE team.

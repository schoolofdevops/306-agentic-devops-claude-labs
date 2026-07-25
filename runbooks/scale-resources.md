# Runbook: Scale Resources

**Last Updated:** 2024-11-10
**Owner:** Platform Team

## When to Use

- High CPU/memory utilization on pods
- HPA is not scaling as expected
- Preparing for expected traffic increase (campaign launch)

## Steps

### Manual Scaling

1. Check current replicas and resource usage:
   ```bash
   kubectl get deploy -n northstar
   kubectl top pods -n northstar
   ```

2. Scale deployment:
   ```bash
   kubectl scale deploy/<service-name> -n northstar --replicas=<N>
   ```

3. Verify pods are running:
   ```bash
   kubectl get pods -n northstar -l app=<service-name> -w
   ```

### HPA Configuration

1. Check HPA status:
   ```bash
   kubectl get hpa -n northstar
   kubectl describe hpa <service-name> -n northstar
   ```

2. Update HPA limits via Helm values:
   ```yaml
   # values-prod.yaml
   autoscaling:
     enabled: true
     minReplicas: 3
     maxReplicas: 10
     targetCPUUtilizationPercentage: 70
   ```

3. Apply changes:
   ```bash
   helm upgrade <release> platform/helm/<service> -f platform/helm/<service>/values-prod.yaml -n northstar
   ```

## Important

- Ensure resource requests are set before enabling HPA (HPA requires metrics-server and resource requests)
- Scale down gradually after traffic subsides

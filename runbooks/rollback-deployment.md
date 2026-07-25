# Runbook: Rollback Deployment

**Last Updated:** 2024-11-10
**Owner:** Platform Team

## When to Use

- New deployment is causing errors or degraded performance
- Pods are in CrashLoopBackOff after a deployment
- Rollout is stuck (not progressing)

## Steps

### Kubernetes

1. Check rollout status:
   ```bash
   kubectl rollout status deploy/<service-name> -n northstar
   ```

2. View rollout history:
   ```bash
   kubectl rollout history deploy/<service-name> -n northstar
   ```

3. Rollback to previous revision:
   ```bash
   kubectl rollout undo deploy/<service-name> -n northstar
   ```

4. Or rollback to a specific revision:
   ```bash
   kubectl rollout undo deploy/<service-name> -n northstar --to-revision=<N>
   ```

5. Verify rollback:
   ```bash
   kubectl rollout status deploy/<service-name> -n northstar
   kubectl get pods -n northstar -l app=<service-name>
   ```

### Argo CD

If using Argo CD, rollback via the application:
```bash
argocd app rollback <app-name>
```

Or revert the Git commit and let Argo CD sync:
```bash
git revert HEAD
git push local HEAD:main
```

## Post-Rollback

- Notify the team about the rollback
- Create a postmortem for the failed deployment
- Fix the issue in a new branch before re-deploying

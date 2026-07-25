# INC-005: Destructive Shortcut — Wrong Namespace Targeted

**Severity:** P1 — Production Impact
**Status:** Open
**Reported:** 2024-11-25T10:30:00Z
**Service:** Platform (Kubernetes)
**On-Call:** Platform Team

## Impact

An automated cleanup script ran against the production namespace instead of
the development namespace. Several production resources were deleted or
modified. The script was intended to clean up stale test resources in dev
but the KUBE_CONTEXT and KUBE_NAMESPACE environment variables were
pointing to production.

## Current Evidence

- Production pods were deleted by the cleanup script
- KUBE_CONTEXT was set to `prod-cluster` (should have been `dev-cluster`)
- KUBE_NAMESPACE was set to `production` (should have been `dev`)
- The `.env.fault` file was sourced before running the script
- No pre-execution check was performed to verify the target namespace
- Production services are recovering via Kubernetes self-healing

## Timeline

| Time | Event |
|------|-------|
| 10:15 | Engineer sources `.env.fault` for testing |
| 10:20 | Engineer runs cleanup script without checking context |
| 10:22 | Production pods begin terminating |
| 10:25 | Production alerts fire — multiple services down |
| 10:30 | Incident created — blast radius assessed |

## Investigation Commands

```bash
# Check current context
kubectl config current-context

# Check what namespace is targeted
echo $KUBE_NAMESPACE

# Check if .env.fault exists and what it contains
cat .env.fault 2>/dev/null

# List all contexts
kubectl config get-contexts

# Verify environment contract
cat contracts/environment-contract.yaml
```

## Hypothesis

The wrong-target fault injection scenario was active, pointing kubectl at
production. No guardrail (pre-tool-use hook or Claude Code permission) existed
to prevent operations against production namespaces.

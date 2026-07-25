# Northstar Commerce — Agentic Ops Lab

## About

Multi-service e-commerce platform for learning agentic DevOps with Claude Code.
Includes deliberate defects, fault injection, and incident scenarios for
hands-on SRE, IaC, and Kubernetes labs.

## Services

| Service | Language | Port | Purpose |
|---------|----------|------|---------|
| orders-api | Python/FastAPI | 8080 | Order management + ops dashboard |
| inventory-api | Go/chi | 8081 | Product catalog + fault injection |
| PostgreSQL | - | 5432 | Order persistence |

## Getting Started

```bash
# Check prerequisites
./scripts/preflight.sh

# Start the platform
docker compose --profile core up -d --build

# Seed the database
./scripts/seed-db.sh

# Open the dashboard
open http://localhost:8080
```

## Docker Compose Profiles

| Profile | Services | RAM |
|---------|----------|-----|
| core | orders-api, inventory-api, postgres | 8GB |
| observe | + prometheus, alertmanager | 16GB |
| full | all services | 16GB |

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/preflight.sh` | Verify all tools installed |
| `scripts/reset.sh mN` | Reset to module N start state |
| `scripts/inject.sh <scenario>` | Apply fault injection |
| `scripts/grade.sh mN` | Grade module N solution |
| `scripts/seed-db.sh` | Seed database with sample data |
| `scripts/local-git-remote.sh` | Create local Git remote for GitOps |

## Fault Injection Scenarios

| Scenario | Effect |
|----------|--------|
| retry-storm | High retries + upstream latency/errors |
| failed-rollout | Broken readiness probe |
| expensive-plan | Oversized RDS instance in Terraform |
| stale-docs | Stale runbook with wrong endpoint |
| wrong-target | kubectl pointing at production |
| normal | Reset all to defaults |

## Agent Governance

See `contracts/` for:
- `authority-matrix.yaml` — role-based permissions
- `environment-contract.yaml` — per-environment rules
- `change-contract.yaml` — change type requirements

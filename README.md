# Agentic Ops Lab

> Northstar Commerce — a hands-on lab environment for learning agentic DevOps
> with Claude Code.

## What is this?

A multi-service e-commerce platform designed as a lab environment for the
**"Agentic DevOps with Claude Code"** course. It includes realistic
microservices, infrastructure-as-code, Kubernetes manifests, observability,
fault injection, and incident scenarios.

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Ops Dashboard                   │
│               (localhost:8080/)                   │
├─────────────────────┬───────────────────────────┤
│    orders-api       │     inventory-api          │
│  (Python/FastAPI)   │      (Go/chi)              │
│    port 8080        │      port 8081             │
│                     │                            │
│  • Order CRUD       │  • Product catalog         │
│  • Retry logic      │  • Stock management        │
│  • Prometheus       │  • Fault injection         │
│    metrics          │  • Prometheus metrics       │
├─────────────────────┼───────────────────────────┤
│              PostgreSQL 16                       │
│               port 5432                          │
└─────────────────────────────────────────────────┘
```

## Quick Start

```bash
# 1. Check prerequisites
./scripts/preflight.sh

# 2. Start services
docker compose --profile core up -d --build

# 3. Seed the database
./scripts/seed-db.sh

# 4. Open the dashboard
open http://localhost:8080
```

## Prerequisites

- Docker & Docker Compose
- Git (>= 2.30)
- Claude Code CLI
- Terraform (>= 1.5)
- kubectl + Kind
- Helm (>= 3.12)
- Node.js (>= 18)
- jq

Run `./scripts/preflight.sh` to verify your setup.

## Repository Structure

```
agentic-ops-lab/
├── app/                    # Application source code
│   ├── orders-api/         # Python/FastAPI service
│   └── inventory-api/      # Go/chi service
├── infra/                  # Terraform IaC
│   ├── modules/            # Reusable Terraform modules
│   ├── environments/       # Per-environment configs
│   └── fixtures/           # Plan analysis fixtures
├── platform/               # Kubernetes platform
│   ├── helm/               # Helm charts
│   ├── kind/               # Kind cluster configs
│   ├── argocd/             # Argo CD manifests
│   ├── policies/           # Network/RBAC/PSA policies
│   └── kubeconfigs/        # Kubeconfig templates
├── observability/          # Monitoring stack
│   ├── prometheus/         # Prometheus + rules
│   ├── alertmanager/       # Alert routing
│   └── collector/          # OTel collector
├── scripts/                # Operational scripts
├── incidents/              # Incident tickets
├── runbooks/               # Operational runbooks
├── contracts/              # Agent governance
├── evals/                  # Agent evaluation scenarios
├── fixtures/               # Seed data + fault configs
└── .claude/                # Claude Code configuration
```

## License

This project is part of the School of DevOps & AI course materials.

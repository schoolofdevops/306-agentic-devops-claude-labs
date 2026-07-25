# Northstar Commerce Platform

You are working on the Northstar Commerce e-commerce platform.

## Services

- **orders-api** (Python/FastAPI) — port 8080: order management, ops dashboard
- **inventory-api** (Go/chi) — port 8081: product catalog, stock management, fault injection
- **PostgreSQL** — port 5432: order persistence

## Quick Commands

```bash
# Start services
docker compose --profile core up -d

# Check health
curl -s http://localhost:8080/healthz
curl -s http://localhost:8081/healthz

# View dashboard
open http://localhost:8080

# Run preflight check
./scripts/preflight.sh
```

## Repository Structure

- `app/` — application source code
- `infra/` — Terraform modules, environments, plan fixtures
- `platform/` — Helm charts, Kind configs, Argo CD, policies
- `observability/` — Prometheus, Alertmanager, OTel collector
- `scripts/` — operational scripts (preflight, reset, inject, grade)
- `incidents/` — incident tickets for investigation labs
- `runbooks/` — operational runbooks
- `contracts/` — agent governance contracts

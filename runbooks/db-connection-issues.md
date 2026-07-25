# Runbook: Database Connection Issues

**Last Updated:** 2024-11-10
**Owner:** Platform Team

## When to Use

- orders-api readiness check failing on database connectivity
- "connection refused" or "too many connections" errors in logs
- Slow queries impacting API response times

## Steps

### Check Database Health

1. Verify PostgreSQL is running:
   ```bash
   docker compose ps postgres
   # or
   kubectl get pods -n northstar -l app=postgres
   ```

2. Test connectivity:
   ```bash
   docker compose exec postgres pg_isready -U orders
   ```

3. Check active connections:
   ```bash
   docker compose exec postgres psql -U orders -c "SELECT count(*) FROM pg_stat_activity WHERE datname='orders';"
   ```

### Check Slow Queries

1. Query pg_stat_statements for slow queries:
   ```bash
   docker compose exec postgres psql -U orders -c "
     SELECT query, calls, mean_exec_time, total_exec_time
     FROM pg_stat_statements
     ORDER BY mean_exec_time DESC
     LIMIT 5;
   "
   ```

2. Check for missing indexes:
   ```bash
   docker compose exec postgres psql -U orders -c "
     SELECT schemaname, relname, seq_scan, seq_tup_read, idx_scan
     FROM pg_stat_user_tables
     WHERE seq_scan > 100 AND idx_scan < 10
     ORDER BY seq_tup_read DESC;
   "
   ```

### Reset Connections

If too many connections:
```bash
docker compose restart postgres
# Wait for health check to pass
docker compose exec postgres pg_isready -U orders
# Then restart dependent services
docker compose restart orders-api
```

## Escalation

If database is corrupted or unrecoverable, restore from backup (see disaster recovery procedures).

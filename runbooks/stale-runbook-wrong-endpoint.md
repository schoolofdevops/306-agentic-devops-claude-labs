# Runbook: Service Health Verification

**Last Updated:** 2024-06-15
**Owner:** Platform Team

## When to Use

- After deployment to verify service health
- During incident response to assess service state
- Periodic health verification

## Steps

1. Check the service status endpoint:
   ```bash
   curl -s http://localhost:8080/api/v1/status | jq .
   ```

2. Verify the response contains:
   - `status: "healthy"`
   - `version` matching the expected deployment version
   - `uptime` showing reasonable value

3. If status endpoint returns an error, check the legacy health endpoint:
   ```bash
   curl -s http://localhost:8080/api/v1/status/health | jq .
   ```

4. Compare against the expected schema:
   ```json
   {
     "status": "healthy",
     "version": "1.0.0",
     "uptime": "2h30m",
     "connections": {
       "database": "connected",
       "inventory": "connected"
     }
   }
   ```

## Notes

- The `/api/v1/status` endpoint was added in v0.8.0
- Returns 503 if any dependency is unhealthy
- Response time should be <100ms

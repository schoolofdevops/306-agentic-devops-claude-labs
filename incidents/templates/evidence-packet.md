# Evidence Packet: [Incident ID]

**Investigator:** [Name/Role]
**Collected:** [Timestamp]

## System State Snapshot

### Service Health
| Service | Status | Endpoint | Response |
|---------|--------|----------|----------|
| orders-api | | /healthz | |
| orders-api | | /readyz | |
| inventory-api | | /healthz | |
| inventory-api | | /readyz | |

### Key Metrics (at time of capture)
| Metric | Value | Normal Range |
|--------|-------|-------------|
| orders-api error rate | | <1% |
| orders-api p95 latency | | <500ms |
| upstream retry count | | <5/min |
| upstream timeout count | | 0/min |

### Configuration State
| Setting | Current Value | Expected Value |
|---------|--------------|----------------|
| RETRY_COUNT | | 3 |
| TIMEOUT_MS | | 5000 |
| FAULT_ENABLED | | false |

## Log Excerpts

```
[paste relevant log lines here]
```

## Commands Run

| # | Command | Output Summary |
|---|---------|---------------|
| 1 | | |
| 2 | | |

## Artifacts

- [ ] Screenshots attached
- [ ] Metric graphs exported
- [ ] Config files saved
- [ ] Git diff captured

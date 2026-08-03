# Concepts: Database SRE Practices

**Module 07 Reference Material**

---

## SRE Principles for DBAs

| Principle | Traditional DBA | SRE/DBRE Approach |
|-----------|----------------|-------------------|
| Reliability | "Keep it running" | "Measure reliability with SLIs/SLOs" |
| Change management | "Avoid changes" | "Error budget determines deployment velocity" |
| Incident response | "Fix it and move on" | "Blameless PIR, action items, prevent recurrence" |
| Automation | "Script what you can" | "Toil budget - automate everything under 50%" |
| Monitoring | "Check when there is a problem" | "SLI-based alerting - detect before users notice" |
| Capacity | "Add resources when full" | "Trend analysis, forecast, plan ahead" |
| Testing | "Test in staging" | "Chaos engineering - test in production" |
| On-call | "Senior DBA handles everything" | "Rotation with clear escalation paths" |

---

## SLI / SLO / SLA Definition Table with Database Examples

### SLIs (What You Measure)

| SLI | Definition | PostgreSQL Measurement | Query |
|-----|-----------|----------------------|-------|
| **Availability** | Can clients connect and query? | Health check probe every 10s | `SELECT 1` |
| **Latency (p50)** | Median query response time | pg_stat_statements mean_exec_time | `SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY mean_exec_time) FROM pg_stat_statements` |
| **Latency (p95)** | 95th percentile response time | pg_stat_statements | Application-side measurement recommended |
| **Latency (p99)** | 99th percentile response time | pg_stat_statements | Application-side measurement recommended |
| **Error rate** | Failed queries / total queries | pg_stat_database | `xact_rollback / (xact_commit + xact_rollback)` |
| **Throughput** | Transactions per second | pg_stat_database delta | `(xact_commit_now - xact_commit_prev) / interval` |
| **Replication lag** | Standby delay from primary | pg_stat_replication | `replay_lag` or `now() - pg_last_xact_replay_timestamp()` |
| **Connection utilization** | Active connections / max | pg_stat_activity | `count(*) / max_connections` |
| **Disk utilization** | Data dir disk usage | OS-level | `df -h /var/lib/pgsql` |
| **Cache hit ratio** | Buffer cache effectiveness | pg_stat_database | `blks_hit / (blks_hit + blks_read)` |

### SLOs (What You Target)

| SLI | Recommended SLO | Error Budget (quarterly) | Rationale |
|-----|----------------|------------------------|-----------|
| Availability | 99.9% | 129.6 minutes (2.16 hours) | Patroni provides ~30s failover |
| Latency p95 | < 100ms | N/A (latency SLOs are thresholds) | Application timeout is typically 5-30s |
| Latency p99 | < 500ms | N/A | Even worst-case should be reasonable |
| Error rate | < 0.1% | N/A | Fewer than 1 in 1000 queries fail |
| Replication lag | < 5 seconds | N/A | Read replicas should serve near-current data |

### SLAs (What You Promise)

| Metric | SLO (internal) | SLA (external) | Gap | Penalty |
|--------|---------------|----------------|-----|---------|
| Availability | 99.95% | 99.9% | 0.05% buffer | Service credits at 99.5% |
| Recovery time | 30 min | 1 hour | 30 min buffer | Escalation process |
| Data durability | 99.999% | 99.99% | 0.009% buffer | Depends on contract |

**Rule:** SLO should always be tighter than SLA to provide a buffer.

---

## Incident Severity Matrix

| | SEV1 - Critical | SEV2 - Major | SEV3 - Minor | SEV4 - Low |
|---|---|---|---|---|
| **Impact** | Total outage / data loss risk | Degraded performance / partial outage | Minor impact / workaround exists | Cosmetic / no user impact |
| **Examples** | Primary down, all writes failing | Standby down (HA degraded), 10x latency | Slow queries for some users, disk 85% | Config drift, unused index |
| **Response time** | < 5 minutes | < 15 minutes | < 1 hour | Next business day |
| **Communication** | Every 15 min to stakeholders | Every 30 min to engineering | Daily update | In weekly review |
| **On-call** | Wake up / interrupt | Page during business hours | Slack notification | Backlog ticket |
| **PIR required?** | Yes (mandatory) | Yes (mandatory) | Optional | No |
| **Error budget impact** | Significant | Moderate | Minor | None |

---

## Post-Incident Review Template

```markdown
# Post-Incident Review: [Title]

Date: [YYYY-MM-DD]
Duration: [Start] - [End] ([Total])
Severity: SEV[X]
IC: [Name]

## Summary
[2-3 sentences: what happened, what was the impact]

## Timeline
| Time (UTC) | Event |
|-----------|-------|
| HH:MM | [Event] |

## Impact
- Users affected: [Number/percentage]
- Duration: [Time]
- Data loss: [Yes/No]
- Error budget consumed: [X minutes]

## Root Cause
[Technical description - not "someone made a mistake"]

## Contributing Factors
1. [Factor]
2. [Factor]

## What Went Well
1. [Item]

## What Went Wrong
1. [Item]

## Action Items
| ID | Action | Owner | Priority | Due |
|----|--------|-------|----------|-----|
| 1 | [Action] | [Name] | P[1-3] | [Date] |
```

---

## Chaos Experiment Template

```markdown
# Chaos Experiment: [Title]

## Metadata
Date: [YYYY-MM-DD]
Conductor: [Name]
Environment: [dev/staging/production]

## Steady State (Baseline)
- Availability: [X]%
- Latency p95: [X]ms
- Error rate: [X]%
- Replication lag: [X]s

## Hypothesis
"When [chaos event], we expect [behavior] within [time],
and [SLI] will [remain within / degrade to] [threshold]."

## Blast Radius
- Affected: [servers/services]
- Not affected: [servers/services]
- Max duration: [time]

## Rollback Plan
1. [Stop chaos]
2. [Restore normal state]
3. [Verify recovery]

## Results
| Metric | Expected | Actual |
|--------|----------|--------|
| Recovery time | [X] | [X] |
| SLI during | [X] | [X] |
| Data loss | None | [X] |

## Hypothesis: [CONFIRMED / REJECTED]
## Action Items:
1. [Action]
```

---

## Toil Identification Checklist

Answer "Yes" to identify toil:

| Question | If Yes, It Is Toil |
|----------|-------------------|
| Do you do this task manually? | Automate it |
| Do you do it more than once a month? | Automate it |
| Could a script do this? | Write the script |
| Does the task grow with the number of databases? | Automate it (linear scaling = toil) |
| Does it interrupt your engineering work? | Automate or delegate it |
| Does completing it permanently improve the system? | If NO, it is toil |

### Common DBA Toil Tasks and Automation Solutions

| Toil Task | Frequency | Manual Time | Automation Solution | Automation Time |
|-----------|-----------|-------------|--------------------|-----------------|
| Create database users | 3x/week | 30 min | Python script + role templates | 30 sec |
| Verify backups | Daily | 15 min | Automated restore + verify script | 0 (cron) |
| Check disk space | Daily | 20 min | Monitoring dashboard + alerts | 0 (auto) |
| Generate capacity report | Weekly | 2 hrs | Python script + cron | 0 (auto) |
| Rotate SSL certificates | Monthly | 30 min | certbot + Ansible playbook | 0 (auto) |
| REINDEX bloated indexes | Weekly | 1 hr | pg_repack + cron | 0 (auto) |
| Check replication lag | Hourly | 5 min | Prometheus + Grafana | 0 (auto) |
| Deploy schema migrations | Weekly | 45 min | CI/CD pipeline | 5 min (review) |
| Review slow query log | Daily | 30 min | pgBadger + auto-report | 10 min (read) |
| Onboard new application | Monthly | 4 hrs | Self-service portal | 15 min |

---

## Error Budget Calculation Formulas

### Availability Error Budget

```
Budget (minutes) = Total_Period_Minutes * (1 - SLO)

Example (quarterly, 99.9%):
Budget = 90 days * 24 hrs * 60 min * (1 - 0.999)
Budget = 129,600 minutes * 0.001
Budget = 129.6 minutes
```

### Budget Consumption Rate

```
Consumption_Rate = Budget_Used / Budget_Total * 100

Healthy: < 50%
Warning: 50-75%
Critical: 75-100%
Exhausted: > 100%
```

### Time-Based Budget Tracking

```
Expected_Consumption = (Days_Elapsed / Days_In_Period) * 100

If Actual_Consumption > Expected_Consumption:
    You are consuming budget faster than expected.
    Consider slowing deployments.
```

### Availability from Downtime

```
Availability = 1 - (Downtime_Minutes / Total_Minutes) * 100

Example:
Downtime = 45 minutes in a quarter (129,600 minutes)
Availability = 1 - (45 / 129600) = 99.965%
```

---

## Quick Reference: Useful PostgreSQL Monitoring Queries

### Connection Health

```sql
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;
```

### Replication Status

```sql
SELECT client_addr, state, replay_lag FROM pg_stat_replication;
```

### Transaction Throughput

```sql
SELECT datname, xact_commit, xact_rollback FROM pg_stat_database WHERE datname = 'myapp';
```

### Cache Hit Ratio

```sql
SELECT round(100.0 * blks_hit / NULLIF(blks_hit + blks_read, 0), 2) FROM pg_stat_database WHERE datname = 'myapp';
```

### Table Bloat

```sql
SELECT relname, n_dead_tup, n_live_tup, last_autovacuum FROM pg_stat_user_tables WHERE n_dead_tup > 10000 ORDER BY n_dead_tup DESC;
```

### Long-Running Queries

```sql
SELECT pid, now() - query_start AS duration, left(query, 80) FROM pg_stat_activity WHERE state = 'active' AND query_start < now() - interval '5 minutes';
```

### Locks and Blocking

```sql
SELECT blocked.pid, blocked.query, blocking.pid AS blocker_pid, blocking.query AS blocker_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks gl ON gl.locktype = bl.locktype AND gl.relation = bl.relation AND gl.pid != bl.pid AND gl.granted
JOIN pg_stat_activity blocking ON blocking.pid = gl.pid;
```

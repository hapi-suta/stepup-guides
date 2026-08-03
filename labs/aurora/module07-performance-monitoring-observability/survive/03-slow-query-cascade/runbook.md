# Runbook: Slow Query Cascade

**Scenario:** One or more bad queries are consuming all CPU, causing a cascade where every query on the cluster slows down. DB Load exceeds vCPU count.

**Time limit:** 15 minutes
**Severity:** P1 - Performance outage affecting all users

---

## Symptoms

- CloudWatch CPUUtilization at 90%+ sustained
- Performance Insights DB Load far above vCPU line
- PI shows CPU as the dominant wait event type
- Simple queries (SELECT 1) take seconds instead of milliseconds
- Application timeouts increasing across all services

---

## Step 1 - Confirm the Problem

Check CPU from the command line:

```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/RDS" \
  --metric-name "CPUUtilization" \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 --statistics Average \
  --region "$REGION" \
  --query "Datapoints[-1].Average" --output text
```

---

## Step 2 - Find the Offending Queries

Connect to the database and find active queries consuming the most resources:

```sql
SELECT
    pid,
    usename,
    application_name,
    now() - query_start AS query_duration,
    state,
    wait_event_type,
    wait_event,
    left(query, 120) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND pid != pg_backend_pid()
ORDER BY query_start ASC
LIMIT 20;
```

Look for:
- Multiple sessions running the same query (the cascade)
- Queries with `application_name` like `slow_cascade_*`
- Long-running queries with no wait event (actively using CPU)

---

## Step 3 - Identify the Specific Bad Query

Use pg_stat_statements to find the query consuming the most time:

```sql
SELECT
    queryid,
    left(query, 100) AS query_snippet,
    calls,
    round(mean_exec_time::numeric / 1000, 1) AS avg_seconds,
    round(total_exec_time::numeric / 1000, 1) AS total_seconds
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY total_exec_time DESC
LIMIT 5;
```

---

## Step 4 - Kill the Bad Queries (Immediate Mitigation)

If you identified the injected queries by application name:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name LIKE 'slow_cascade%'
  AND pid != pg_backend_pid();
```

If identified by query pattern:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state = 'active'
  AND query LIKE '%cascade_test%'
  AND query LIKE '%md5%'
  AND pid != pg_backend_pid();
```

---

## Step 5 - Verify CPU is Recovering

Wait 1-2 minutes, then check:

```sql
SELECT count(*) AS active_sessions
FROM pg_stat_activity
WHERE state = 'active'
  AND pid != pg_backend_pid();
```

Also verify a simple query runs fast:

```sql
\timing on
SELECT 1;
```

It should complete in under 5ms.

---

## Step 6 - Prevent the Query from Running Again

Option A - Add an index so the query uses index scan instead of seq scan:

```sql
CREATE INDEX CONCURRENTLY idx_cascade_test_category ON cascade_test(category);
```

Option B - Set a statement timeout to kill long queries automatically:

```sql
ALTER ROLE app_user SET statement_timeout = '30000';
```

This kills any query from `app_user` that runs longer than 30 seconds.

Option C - Add the query to a kill list via pg_stat_activity monitoring.

---

## Step 7 - Check for Collateral Damage

The CPU spike may have caused other issues:

```sql
-- Check for queries that were killed by timeouts
SELECT count(*) FROM pg_stat_database WHERE xact_rollback > 0;

-- Check for lock queue buildup during the incident
SELECT count(*) FROM pg_locks WHERE NOT granted;

-- Check replication lag (CPU saturation can cause lag)
SELECT * FROM aurora_replica_status();
```

---

## Prevention

1. **Set statement_timeout** on application roles: `ALTER ROLE app_user SET statement_timeout = '60000';`
2. **Add indexes** on commonly filtered columns
3. **Use pg_stat_statements** to catch new expensive queries before they become a problem
4. **Set up Performance Insights alerts** on DB Load exceeding 2x vCPU count
5. **Route analytical queries** to reader instances

---

## Post-Incident Check

```sql
-- CPU should be back to normal
-- Check active query count
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- Verify no queries are running longer than 1 minute
SELECT pid, now() - query_start AS duration, left(query, 80)
FROM pg_stat_activity
WHERE state = 'active' AND now() - query_start > interval '1 minute';
```

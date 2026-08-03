# Runbook: Slow Query Cascade

**Scenario:** One or more expensive queries are saturating CPU. All other queries are slow because they are starved of CPU time. The cascade effect means even simple queries take seconds.

**Time limit:** 20 minutes
**Severity:** P1 - Severe degradation affecting all users

---

## Symptoms

- CloudWatch CPUUtilization near 100%
- Performance Insights: DB Load above vCPU line, dominated by CPU wait
- Simple queries that should take 1ms are taking 5-30 seconds
- Application timeouts across all endpoints

---

## Step 1 - Confirm CPU Saturation

Check CPU via CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Maximum \
  --region "$REGION"
```

And confirm via Performance Insights: is DB Load above the vCPU line with `CPU` dominating?

---

## Step 2 - Find the Offending Queries

```sql
-- Find queries using the most CPU (high total execution time, full table scans)
SELECT
    pid,
    now() - query_start AS running_for,
    state,
    left(query, 120) AS query_snippet,
    wait_event
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY query_start
LIMIT 20;
```

Look for:
- Long-running queries (running_for > 30 seconds)
- Queries containing regex `~`, `LIKE '%'`, or missing index filters
- Many identical queries running simultaneously (N+1 pattern)

Also check pg_stat_statements:

```sql
SELECT
    left(query, 100) AS query_snippet,
    calls,
    round(mean_exec_time::numeric, 0) AS avg_ms,
    round(total_exec_time::numeric, 0) AS total_ms,
    shared_blks_read
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

---

## Step 3 - Identify and Kill the Offending Sessions

```sql
-- Get PIDs of the slow queries
SELECT pid, left(query, 100)
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '10 seconds'
  AND query NOT LIKE '%pg_stat_activity%';
```

Cancel them (soft kill - allows the query to stop cleanly):

```sql
SELECT pg_cancel_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '10 seconds'
  AND query NOT LIKE '%pg_stat_activity%'
  AND query NOT LIKE '%pg_cancel%';
```

If cancel does not work within 10 seconds, terminate:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '10 seconds'
  AND query NOT LIKE '%pg_stat_activity%'
  AND query NOT LIKE '%pg_terminate%';
```

---

## Step 4 - Verify CPU Drops

After killing the queries, monitor CPU for 2-3 minutes:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Average \
  --region "$REGION"
```

CPU should drop within 1-2 minutes of killing the queries.

---

## Step 5 - Diagnose the Root Cause Query

Get the full query from pg_stat_statements and run EXPLAIN:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT u.country, count(o.order_id), sum(o.amount), avg(o.amount)
FROM cascade_users u
JOIN cascade_orders o ON u.user_id = o.user_id
WHERE o.description ~ '.*[aeiou]{3}.*'
  AND o.amount > 100
GROUP BY u.country
ORDER BY sum(o.amount) DESC;
```

Look for:
- `Seq Scan` on cascade_orders - 3M row full scan
- No index on user_id - nested loop with full scan
- Regex `~ '.*...*'` - cannot use any index

---

## Step 6 - Fix the Query

**Fix 1 - Add index on user_id:**

```sql
CREATE INDEX CONCURRENTLY idx_cascade_orders_user_id ON cascade_orders(user_id);
```

**Fix 2 - Rewrite the regex pattern:**

The regex `~ '.*[aeiou]{3}.*'` (three consecutive vowels) scans every row. Options:
- Remove the filter if it is not necessary for the use case
- Store a pre-computed boolean column: `has_triple_vowel BOOLEAN` and index it
- Use `pg_trgm` index for pattern matching

**Fix 3 - Add amount index for selective filtering:**

```sql
CREATE INDEX CONCURRENTLY idx_cascade_orders_amount ON cascade_orders(amount)
WHERE amount > 100;
```

**Fix 4 - Set statement_timeout to prevent runaway queries:**

```sql
-- In parameter group
-- statement_timeout = 300000  (5 minutes - no query should run longer)
```

---

## Step 7 - Prevent Recurrence

1. Set `statement_timeout` in the parameter group to kill queries after a maximum allowed runtime.
2. Add a CloudWatch alarm on CPUUtilization > 80% for 5 minutes.
3. Review pg_stat_statements weekly for queries with high `total_exec_time`.
4. Implement query review in CI/CD: any new query touching more than 100K rows requires DBA review.

---

## Post-Incident Check

```sql
-- Confirm CPU is back to normal via a fast query
SELECT count(*) FROM pg_stat_activity;

-- Confirm no more CPU-saturating queries
SELECT pid, left(query, 80), now() - query_start AS age
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '30 seconds'
  AND query NOT LIKE '%pg_stat_activity%';
```

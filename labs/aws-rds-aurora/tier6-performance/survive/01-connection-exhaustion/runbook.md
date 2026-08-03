# Runbook: Connection Exhaustion

**Scenario:** All connections to the database are exhausted. New connections fail with `FATAL: sorry, too many clients already`. The application is down.

**Time limit:** 15 minutes
**Severity:** P1 - Complete outage

---

## Symptoms

- Application returning 500 errors on all database operations
- CloudWatch alarm `RDS-Connections-High` firing (if configured)
- `psql` connection attempts fail immediately with: `FATAL: sorry, too many clients already`

---

## Step 1 - Confirm the Problem

Try to connect:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1;"
```

If you see `FATAL: sorry, too many clients already`, you have connection exhaustion.

---

## Step 2 - Use the Superuser Reserved Connection

PostgreSQL reserves connections for superusers by default (`superuser_reserved_connections = 3`). Use the superuser if your normal user cannot connect:

```bash
psql -h "$DB_ENDPOINT" -U "postgres" -d "postgres" -c "SELECT 1;"
```

If this works, proceed. If not, you may need to restart the instance (Step 7).

---

## Step 3 - Count Connections by State

```sql
SELECT state, count(*) AS sessions
FROM pg_stat_activity
GROUP BY state
ORDER BY sessions DESC;
```

Expected output:
```
        state        | sessions
---------------------+----------
 active              |      450
 idle                |       18
 idle in transaction |        2
```

---

## Step 4 - Identify What Is Holding Connections

```sql
SELECT
    usename,
    application_name,
    state,
    count(*) AS sessions,
    max(now() - state_change) AS max_idle_time
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
GROUP BY 1, 2, 3
ORDER BY sessions DESC
LIMIT 20;
```

Look for:
- Idle connections from the same application - connection pool leak
- `active` sessions with `SELECT pg_sleep(...)` - injected load
- `idle in transaction` for more than a few seconds - transaction not committed

---

## Step 5 - Terminate Idle Connections (Immediate Mitigation)

Terminate idle connections that have been idle for more than 5 minutes:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state = 'idle'
  AND now() - state_change > interval '5 minutes'
  AND pid != pg_backend_pid();
```

---

## Step 6 - Terminate Specific Application Connections

If one application is responsible for the flood:

```sql
-- Replace 'problematic-app' with the actual application_name
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name = 'problematic-app'
  AND pid != pg_backend_pid();
```

---

## Step 7 - If You Cannot Connect at All

If even superuser connections fail, you can force-close connections at the RDS level:

```bash
# Restart the instance - this clears all connections
# WARNING: This causes a brief outage (30-60 seconds)
aws rds reboot-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

Only do this if you cannot connect any other way.

---

## Step 8 - Verify Recovery

After terminating connections, verify the count is back to normal:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

Try a normal application connection to confirm it succeeds.

---

## Step 9 - Permanent Fix Options

| Option | Implementation | When to Use |
|--------|---------------|------------|
| Implement connection pooling | Deploy PgBouncer or RDS Proxy | Always - for any production system |
| Set idle session timeout | `idle_session_timeout = 300000` (5 min) | Kills idle connections automatically |
| Set idle_in_transaction timeout | `idle_in_transaction_session_timeout = 60000` | Kills hung transactions |
| Reduce max_connections | Lower to (vCPUs * 10) and use a pooler | Only if RAM is the limit |
| Add read replica | Route read queries to replica | If most connections are read-only |

For the permanent fix in this lab, deploy RDS Proxy (see Build 09).

---

## Prevention

Set these parameters in your parameter group:

```
idle_session_timeout = 300000              # 5 minutes - kill idle sessions
idle_in_transaction_session_timeout = 60000 # 1 minute - kill idle-in-tx sessions
```

Set this alarm:

```
Metric: DatabaseConnections
Threshold: 80% of max_connections
Action: Page on-call immediately
```

---

## Post-Incident Check

```sql
-- Verify connection count is healthy
SELECT count(*) FROM pg_stat_activity;

-- Check for remaining idle-in-transaction sessions
SELECT pid, now() - xact_start AS age, state, left(query, 80)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY age DESC;
```

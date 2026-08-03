# Runbook: Connection Exhaustion

**Scenario:** All connections to the database are exhausted. New connections fail with `FATAL: sorry, too many clients already`. The application is down.

**Time limit:** 15 minutes
**Severity:** P1 - Complete outage

---

## Symptoms

- Application returning 500 errors on all database operations
- CloudWatch alarm `Aurora-HighConnections` firing
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

PostgreSQL reserves connections for superusers by default (`superuser_reserved_connections = 3`). Use the admin user:

```bash
psql -h "$DB_ENDPOINT" -U "postgres" -d "postgres" -c "SELECT 1;"
```

If this works, proceed. If not, skip to Step 7.

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
 active              |      720
 idle                |       18
 idle in transaction |        2
                     |        5
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
- Many connections with `application_name` like `connection_flood_*` - this is the injected load
- Idle connections from the same application - connection pool leak
- `idle in transaction` sessions held for a long time - uncommitted transactions

---

## Step 5 - Terminate Flood Connections (Immediate Mitigation)

If you see `connection_flood` in the application names, terminate those first:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name LIKE 'connection_flood%'
  AND pid != pg_backend_pid();
```

If the flood connections are not clearly labeled, terminate idle connections older than 5 minutes:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state = 'idle'
  AND now() - state_change > interval '5 minutes'
  AND pid != pg_backend_pid();
```

---

## Step 6 - Terminate All Non-Essential Connections

If Step 5 did not free enough connections:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state IN ('idle', 'idle in transaction')
  AND pid != pg_backend_pid();
```

---

## Step 7 - If You Cannot Connect at All

If even superuser connections fail, reboot the instance:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --region "$REGION"
```

This causes a brief outage (30-60 seconds on Aurora) but clears all connections. Only do this as a last resort.

---

## Step 8 - Verify Recovery

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT count(*) AS connections FROM pg_stat_activity;"
```

The connection count should be back to normal (your baseline value).

Try a normal query:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT now();"
```

---

## Step 9 - Permanent Fix

| Option | Implementation | When to Use |
|--------|---------------|------------|
| Deploy RDS Proxy | Create RDS Proxy, point apps to proxy endpoint | Always for production |
| Set idle_session_timeout | `idle_session_timeout = 300000` (5 min) | Auto-kill leaked idle connections |
| Set idle_in_transaction_timeout | `idle_in_transaction_session_timeout = 60000` | Auto-kill hung transactions |
| Tune TCP keepalives | `tcp_keepalives_idle = 300` | Detect dead connections faster |
| Add read replica | Route read queries to reader endpoint | If most connections are reads |

---

## Prevention

Set these parameters in your parameter group:

```
idle_session_timeout = 300000
idle_in_transaction_session_timeout = 60000
tcp_keepalives_idle = 300
tcp_keepalives_interval = 30
tcp_keepalives_count = 3
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
SELECT count(*) FROM pg_stat_activity;

SELECT pid, now() - xact_start AS age, state, left(query, 80)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY age DESC;
```

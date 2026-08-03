# Build 06 - Connection Monitoring

**Time:** 35 minutes
**Goal:** Monitor connection health, understand connection pools, detect idle connection leaks, and prepare for connection storms.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. psql access. Build 01 complete (CloudWatch alarms set).

---

## Step 1 - Check Your Current Connection Settings

**On your local machine, connect to your Aurora database:**

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Check the key connection parameters:

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
    'max_connections',
    'superuser_reserved_connections',
    'idle_session_timeout',
    'idle_in_transaction_session_timeout',
    'statement_timeout',
    'tcp_keepalives_idle',
    'tcp_keepalives_interval',
    'tcp_keepalives_count'
)
ORDER BY name;
```

Expected output (yours will differ):
```
                  name                  | setting |  unit  |                        short_desc
----------------------------------------+---------+--------+----------------------------------------------------------
 idle_in_transaction_session_timeout    | 0       | ms     | Sets the maximum allowed idle time between queries, when in a transaction.
 idle_session_timeout                   | 0       | ms     | Sets the maximum allowed idle time between queries, when not in a transaction.
 max_connections                        | 820     |        | Sets the maximum number of concurrent connections.
 statement_timeout                      | 0       | ms     | Sets the maximum allowed duration of any statement.
 superuser_reserved_connections         | 3       |        | Sets the number of connection slots reserved for superusers.
 tcp_keepalives_count                   | 9       |        | Maximum number of TCP keepalive retransmits.
 tcp_keepalives_idle                    | 7200    | s      | Time between issuing TCP keepalives.
 tcp_keepalives_interval                | 75      | s      | Time between TCP keepalive retransmits.
```

Note: `max_connections` on Aurora is set automatically based on instance size.

---

## Step 2 - Monitor Current Connections

See all current connections grouped by state:

```sql
SELECT
    state,
    count(*) AS sessions,
    round(count(*)::numeric / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') * 100, 1) AS pct_of_max
FROM pg_stat_activity
GROUP BY state
ORDER BY sessions DESC;
```

Expected output (yours will differ):
```
        state        | sessions | pct_of_max
---------------------+----------+------------
 idle                |       12 |        1.5
 active              |        3 |        0.4
 idle in transaction |        1 |        0.1
                     |        5 |        0.6
```

The empty state rows are background processes (autovacuum launcher, WAL writer, etc.).

---

## Step 3 - Identify Connection Sources

See where connections are coming from:

```sql
SELECT
    usename,
    application_name,
    client_addr,
    state,
    count(*) AS sessions,
    max(now() - backend_start) AS oldest_connection,
    max(now() - state_change) AS longest_in_current_state
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY 1, 2, 3, 4
ORDER BY sessions DESC
LIMIT 20;
```

This shows you which users, applications, and client IPs are consuming connections. Look for:
- One application holding many idle connections (possible pool leak)
- Many connections from the same IP (possible misconfigured pool)
- Connections that have been idle for hours (possible leaked connections)

---

## Step 4 - Find Dangerous Idle-in-Transaction Sessions

Idle-in-transaction sessions hold locks and prevent autovacuum from cleaning dead tuples. They are one of the most common causes of performance degradation:

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    now() - xact_start AS txn_age,
    now() - state_change AS idle_for,
    left(query, 80) AS last_query,
    backend_xid,
    backend_xmin
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY txn_age DESC;
```

Any session idle in transaction for more than 5 minutes is suspicious. Any session idle in transaction for more than 1 hour is almost certainly a problem.

---

## Step 5 - Set Connection Timeout Parameters

Configure timeout parameters to automatically clean up leaked connections. These require a custom parameter group.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=idle_session_timeout,ParameterValue=300000,ApplyMethod=immediate" \
    "ParameterName=idle_in_transaction_session_timeout,ParameterValue=60000,ApplyMethod=immediate" \
    "ParameterName=statement_timeout,ParameterValue=3600000,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `idle_session_timeout=300000`: Kill sessions that have been idle (not in a transaction) for 5 minutes (300000 ms). This catches leaked connections from applications that open connections and forget to close them.
- `idle_in_transaction_session_timeout=60000`: Kill sessions that have been idle in a transaction for 1 minute (60000 ms). This catches applications that BEGIN a transaction and never COMMIT or ROLLBACK.
- `statement_timeout=3600000`: Kill any single statement running longer than 1 hour (3600000 ms). This is a safety net for runaway queries.

---

## Step 6 - Configure TCP Keepalives

TCP keepalives detect and clean up broken connections (e.g., client crashed without closing the connection):

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name "$PARAM_GROUP" \
  --parameters \
    "ParameterName=tcp_keepalives_idle,ParameterValue=300,ApplyMethod=immediate" \
    "ParameterName=tcp_keepalives_interval,ParameterValue=30,ApplyMethod=immediate" \
    "ParameterName=tcp_keepalives_count,ParameterValue=3,ApplyMethod=immediate" \
  --region "$REGION"
```

Each parameter explained:
- `tcp_keepalives_idle=300`: Start sending keepalive probes after 300 seconds (5 minutes) of idle time. Default is 7200 (2 hours) which is too long.
- `tcp_keepalives_interval=30`: Send a keepalive probe every 30 seconds after the first one.
- `tcp_keepalives_count=3`: Give up after 3 failed probes. The connection is closed.

With these settings, a dead connection is detected and cleaned up within 300 + (30 * 3) = 390 seconds (6.5 minutes). With defaults, it takes 7200 + (75 * 9) = 7875 seconds (over 2 hours).

---

## Step 7 - Create a Connection Monitoring Query

This query gives you a comprehensive connection health snapshot:

```sql
SELECT
    'Total' AS metric,
    count(*)::text AS value
FROM pg_stat_activity
WHERE backend_type = 'client backend'

UNION ALL

SELECT 'max_connections', setting
FROM pg_settings WHERE name = 'max_connections'

UNION ALL

SELECT
    'Utilization %',
    round(count(*)::numeric / (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') * 100, 1)::text
FROM pg_stat_activity
WHERE backend_type = 'client backend'

UNION ALL

SELECT 'Active', count(*)::text
FROM pg_stat_activity WHERE state = 'active' AND backend_type = 'client backend'

UNION ALL

SELECT 'Idle', count(*)::text
FROM pg_stat_activity WHERE state = 'idle' AND backend_type = 'client backend'

UNION ALL

SELECT 'Idle in Transaction', count(*)::text
FROM pg_stat_activity WHERE state = 'idle in transaction' AND backend_type = 'client backend'

UNION ALL

SELECT 'Idle > 5 min', count(*)::text
FROM pg_stat_activity
WHERE state = 'idle'
  AND now() - state_change > interval '5 minutes'
  AND backend_type = 'client backend'

UNION ALL

SELECT 'Idle in Txn > 1 min', count(*)::text
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '1 minute'
  AND backend_type = 'client backend';
```

Expected output (yours will differ):
```
       metric        | value
---------------------+-------
 Total               | 16
 max_connections      | 820
 Utilization %       | 2.0
 Active              | 3
 Idle                | 12
 Idle in Transaction | 1
 Idle > 5 min        | 4
 Idle in Txn > 1 min | 0
```

---

## Step 8 - Emergency: Terminate Connections During a Storm

If connections are exhausted and the database is rejecting new connections, use the superuser reserved connections to connect and terminate sessions.

Connect as the admin user:

```bash
psql -h "$DB_ENDPOINT" -U "postgres" -d "postgres"
```

Terminate idle connections older than 5 minutes:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE state = 'idle'
  AND now() - state_change > interval '5 minutes'
  AND pid != pg_backend_pid();
```

Terminate all connections from a specific application:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE application_name = 'problem-app'
  AND pid != pg_backend_pid();
```

Terminate all connections from a specific IP:

```sql
SELECT count(pg_terminate_backend(pid))
FROM pg_stat_activity
WHERE client_addr = '10.0.1.50'
  AND pid != pg_backend_pid();
```

> **Warning:** `pg_terminate_backend` sends SIGTERM to the backend process. Any in-progress transactions will be rolled back. Only use this during an active incident when the database is rejecting connections.

---

## Summary

You have:
- Checked connection parameters and current connection state
- Identified connection sources and idle-in-transaction sessions
- Configured timeout parameters to auto-clean leaked connections
- Tuned TCP keepalives to detect dead connections faster
- Learned emergency procedures for connection storms

Connection monitoring is a proactive discipline. The timeout parameters you set in Step 5 and Step 6 will prevent most connection-related incidents from occurring.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| max_connections | Maximum simultaneous connections the instance allows |
| superuser_reserved_connections | Connections reserved for the admin user (default: 3) |
| idle_session_timeout | Auto-kill sessions idle for this long (not in a transaction) |
| idle_in_transaction_session_timeout | Auto-kill sessions idle in a transaction for this long |
| statement_timeout | Auto-kill any single statement running longer than this |
| TCP keepalive | OS-level probe that detects dead network connections |
| pg_terminate_backend | Function that forcibly closes a specific backend process |
| Connection storm | Sudden spike in connection attempts that exhausts max_connections |

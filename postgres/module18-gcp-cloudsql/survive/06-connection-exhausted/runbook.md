# RUNBOOK: Connection Exhaustion

## Symptom

New connections fail with `FATAL: too many connections for role "postgres"` or `FATAL: remaining connection slots are reserved for non-replication superuser connections`.

---

## Step 1 - Check max_connections

Check the current max_connections setting via gcloud (does not need a database connection).

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)"
```

Look for `max_connections` in the flags.

---

## Step 2 - Connect as Superuser

If all regular slots are taken, connect using the superuser reserved slots. Cloud SQL reserves a few connections for the `cloudsqlsuperuser` role.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

If even this fails, you can still change flags via gcloud (Step 5).

---

## Step 3 - Identify Idle Connections

Once connected, check who is holding connections.

```sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    state_change,
    left(query, 60) AS query_preview
FROM pg_stat_activity
WHERE datname = 'suta_lab'
ORDER BY state_change;
```

Count connections by state.

```sql
SELECT state, count(*)
FROM pg_stat_activity
WHERE datname IS NOT NULL
GROUP BY state
ORDER BY count DESC;
```

Expected output (yours will differ):
```
        state        | count
---------------------+-------
 idle                |    47
 active              |     3
 idle in transaction |     1
(3 rows)
```

---

## Step 4 - Terminate Idle Connections

Terminate connections that are idle or running long sleep queries.

Terminate all idle connections (except your own).

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
  AND state = 'idle'
  AND datname = 'suta_lab';
```

Terminate connections running pg_sleep (the injected connections).

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
  AND query LIKE '%pg_sleep%';
```

Verify connections were freed.

```sql
SELECT count(*) AS active_connections FROM pg_stat_activity WHERE datname IS NOT NULL;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 5 - Increase max_connections

Set max_connections to a reasonable value for the instance tier.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=max_connections=100,log_statement=ddl,log_min_duration_statement=1000,log_connections=on,log_disconnections=on
```

This requires a restart. Wait for it to complete.

---

## Step 6 - Verify Recovery

Connect and check the new max_connections.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SHOW max_connections;
```

Expected output:
```
 max_connections
-----------------
 100
(1 row)
```

Check current connection count.

```sql
SELECT count(*) FROM pg_stat_activity WHERE datname IS NOT NULL;
```

Type `\q` to exit psql.

```
\q
```

---

## Prevention

- Use connection pooling (pgBouncer or the Auth Proxy's built-in pooling)
- Set application connection pool max to 80% of max_connections
- Monitor connection count with Cloud Monitoring alerts
- Set `idle_in_transaction_session_timeout` to kill abandoned transactions
- Log connections and disconnections to track leaks

# SURVIVE 04: pgbench Kills Server - Runbook

## Symptom

Applications report "FATAL: too many connections for role" and "FATAL: sorry, too many clients already." A load test is running with more clients than max_connections allows.

---

## Step 1: Verify the Problem

Try to connect to PostgreSQL as the postgres user.

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT 1;"
```

If this fails with "too many clients already," use a local socket connection with the reserved superuser connection.

```bash
psql -c "SELECT count(*) FROM pg_stat_activity;"
```

Check current vs maximum connections.

```bash
psql -c "SELECT count(*) AS current_connections, (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_connections FROM pg_stat_activity;"
```

---

## Step 2: Identify the pgbench Processes

Exit psql if connected, then check for pgbench processes at the OS level.

```bash
ps aux | grep pgbench
```

Expected output (yours will differ):
```
postgres  12345  5.2  0.1 123456 7890 ?  S  10:00  0:05 pgbench -c 50 -j 4 -T 300 bench_chaos
```

Note the PID (12345 in this example).

---

## Step 3: Kill pgbench

Kill the pgbench master process. The `-TERM` signal gives it a chance to clean up.

```bash
pkill -TERM pgbench
```

Wait a moment then verify it is gone.

```bash
ps aux | grep pgbench
```

If pgbench is still running, use a harder kill.

```bash
pkill -KILL pgbench
```

---

## Step 4: Clean Up Stale Connections

After killing pgbench, some backend connections may linger. Check how many are left.

```bash
psql -c "SELECT pid, usename, application_name, state, query_start FROM pg_stat_activity WHERE application_name = 'pgbench' ORDER BY query_start;"
```

Terminate any remaining pgbench connections.

```bash
psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = 'pgbench';"
```

Verify connections are back to normal.

```bash
psql -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## Step 5: Increase max_connections

The current max_connections is too low. Set it to a reasonable value.

```bash
psql -c "ALTER SYSTEM SET max_connections = 200;"
```

This requires a restart to take effect. Restart PostgreSQL.

```bash
pg_ctl -D /opt/pgsql/data -l /opt/pgsql/log/startup.log restart -m fast
```

Exit the postgres user.

```bash
exit
```

---

## Step 6: Verify Recovery

Switch to the postgres user.

```bash
sudo -iu postgres
```

Confirm max_connections is now 200.

```bash
psql -c "SHOW max_connections;"
```

Confirm the server is accepting connections normally.

```bash
psql -c "SELECT version();"
```

Check that no pgbench processes are running.

```bash
ps aux | grep pgbench | grep -v grep
```

Exit the postgres user.

```bash
exit
```

---

## Prevention

1. Always check max_connections before running load tests: `SHOW max_connections;`
2. Use pgbench `-c` value less than 80% of max_connections
3. Set `statement_timeout` and `idle_in_transaction_session_timeout` as safety nets
4. Consider using pgbouncer as a connection pooler in front of PostgreSQL
5. Monitor connection counts with Prometheus and alert at 80% threshold
6. Reserve superuser connections: `superuser_reserved_connections = 3` (default)

---

## Discussion Points

- Why use `pkill -TERM` before `pkill -KILL`? TERM allows graceful cleanup. KILL can leave shared memory in a dirty state.
- What is `superuser_reserved_connections`? PostgreSQL reserves 3 connections for superusers by default. This is why you can still connect as postgres even when max_connections is hit.
- When should you use pgbouncer? When your application opens more connections than PostgreSQL can handle efficiently. Each PostgreSQL backend process uses about 10 MB of RAM.

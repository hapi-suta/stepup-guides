# Use Exercise 04 - Alert Response Drill

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 45 minutes
**Prerequisite:** Build Guides 02-05 complete

---

## Objective

Intentionally trigger three different Prometheus alerts and practice the full response workflow: detect the alert, diagnose the root cause, apply the fix, and verify the alert resolves. Doing this in a lab environment builds the muscle memory you need to respond effectively during real incidents.

---

## Background

The worst time to learn your alert response process is during a real incident at 2 AM. Drilling alert responses in a controlled environment teaches you:
- How long each alert takes to fire (the `for:` duration)
- What the Prometheus UI looks like when an alert is FIRING
- Where to look in the database to find the root cause
- How to confirm the fix worked

---

## Drill 1 - PostgresExporterDown

### Inject the condition

Log in to pg-primary.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

Stop postgres_exporter to simulate a crash.

```bash
sudo systemctl stop postgres_exporter
```

Note the time you stopped it.

### Detect

1. Open `http://<your-server-ip>:9090/alerts` in your browser
2. Watch for `PostgresExporterDown` to move from `inactive` to `pending`
3. After 1 minute, it should become `firing`

From the command line:

```bash
curl -s 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool | grep -A5 alertname
```

Expected output when firing (yours will differ):

```
            "alertname": "PostgresExporterDown",
            "severity": "critical",
```

### Diagnose

Check if the exporter process is running:

```bash
sudo systemctl status postgres_exporter
```

Check recent logs for error messages:

```bash
sudo journalctl -u postgres_exporter -n 20 --no-pager
```

Check if port 9187 is listening:

```bash
ss -tlnp | grep 9187
```

### Fix

Start the exporter:

```bash
sudo systemctl start postgres_exporter
```

### Verify the alert resolves

Check the metrics endpoint:

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

Expected output (yours will differ):

```
pg_up 1
```

Go back to `http://<your-server-ip>:9090/alerts`. Within 1-2 scrape intervals (30 seconds), `PostgresExporterDown` should return to `inactive`.

**Record in your notes:**
- Time from stopping the exporter to alert firing: ___
- Time from restarting the exporter to alert resolving: ___

---

## Drill 2 - PostgresLongRunningQuery

### Inject the condition

Switch to the postgres user.

```bash
sudo -i -u postgres
```

Open a psql session and start a long-running transaction.

```bash
psql -d stepup_store
```

```sql
BEGIN;
SELECT pg_sleep(400);
```

Leave this running in the background. Open a new terminal to continue.

### Detect

In your new terminal, check the alert:

```bash
curl -s 'http://localhost:9090/api/v1/alerts' | python3 -m json.tool
```

The `PostgresLongRunningQuery` alert has `for: 0m`, meaning it fires immediately when the condition is true (no waiting period). Check the Prometheus UI at `/alerts` - it should show FIRING within one scrape interval (15 seconds).

### Diagnose

While still in the new terminal, switch to postgres and check pg_stat_activity.

```bash
sudo -i -u postgres
```

```bash
psql -c "
SELECT
  pid,
  datname,
  state,
  wait_event_type,
  wait_event,
  round(extract(epoch from now() - query_start)::numeric, 1) AS duration_sec,
  left(query, 80) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration_sec DESC;"
```

Expected output (yours will differ):

```
  pid  |   datname   | state  | wait_event_type | wait_event | duration_sec |       query
-------+-------------+--------+-----------------+------------+--------------+-------------------
 15678 | stepup_store | active | Timeout         | PgSleep    |        45.3 | BEGIN;            +
       |             |        |                 |            |              | SELECT pg_sleep...
```

Identify the PID of the long-running query.

### Fix

You have two choices in production:
1. Contact the application team to cancel gracefully
2. Terminate the session if it is causing damage

For this drill, terminate the session using the PID from the query above (replace 15678 with your actual PID).

```sql
SELECT pg_terminate_backend(15678);
```

Expected output (yours will differ):

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

### Verify

Run the pg_stat_activity query again to confirm the long-running query is gone.

```sql
SELECT pid, state, round(extract(epoch from now() - query_start)::numeric, 1) AS duration_sec
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%';
```

The alert should resolve within one scrape interval.

```sql
\q
```

```bash
exit
```

---

## Drill 3 - PostgresLowCacheHitRatio

### Inject the condition

This drill is more involved. You will use `pg_prewarm` to flush the cache and then run queries that force disk reads.

First, check if pg_prewarm is available.

```bash
sudo -i -u postgres
psql -c "SELECT * FROM pg_available_extensions WHERE name = 'pg_prewarm';"
```

If available, install it.

```bash
psql -d stepup_store -c "CREATE EXTENSION IF NOT EXISTS pg_prewarm;"
```

To simulate a cold cache hit ratio problem, run a query that does massive sequential scans on a table that does not fit in shared_buffers.

```bash
psql -d stepup_store
```

```sql
-- Run a sequential scan on the full pgbench_accounts table many times
DO $$
DECLARE
  i int;
BEGIN
  FOR i IN 1..10 LOOP
    PERFORM count(*) FROM pgbench_accounts WHERE abalance < -99999999;
    RAISE NOTICE 'Pass % complete', i;
  END LOOP;
END;
$$;
```

This forces many disk reads because the WHERE clause matches no rows (meaning PostgreSQL reads every row and finds nothing).

### Detect

The `PostgresLowCacheHitRatio` alert uses a 10-minute evaluation window and requires the condition to persist for 10 minutes before firing. In a lab environment you can check the current cache ratio directly.

```bash
curl -s 'http://localhost:9090/api/v1/query?query=100*sum(rate(pg_stat_database_blks_hit%5B5m%5D))/(%20sum(rate(pg_stat_database_blks_hit%5B5m%5D))%20%2B%20sum(rate(pg_stat_database_blks_read%5B5m%5D)))' | python3 -m json.tool | grep '"value"'
```

Expected output (yours will differ - ratio should be lower than normal):

```
                "value": [1709305200.123, "94.3"]
```

### Diagnose

Check which databases have low cache hit rates.

```sql
SELECT
  datname,
  blks_hit,
  blks_read,
  CASE WHEN blks_hit + blks_read > 0
    THEN round(100.0 * blks_hit / (blks_hit + blks_read), 2)
    ELSE 100
  END AS cache_hit_pct
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY cache_hit_pct ASC;
```

### Fix options

In a real incident, low cache hit ratio means:
1. `shared_buffers` is too small for the working set
2. A sequential scan is running on a large table (missing index)
3. A bulk data load is flooding the cache

For this drill, the fix is to let the cache warm back up naturally and add an index to prevent the sequential scan.

```sql
\q
```

```bash
exit
```

---

## Drill 4 - Write Your Own Injection

**Task:** Design an injection for the `PostgresHighConnectionCount` alert. The alert fires when non-idle connections exceed 80.

Write a shell script that opens 85 idle-in-transaction connections to test the alert. Use psql's `--command` flag and backgrounding.

**Hints:**
- You can use a bash `for` loop
- Each `psql` command can run `BEGIN;` to start a transaction and then `SELECT pg_sleep(300);` to hold it
- Use `&` to background each psql call
- Use `wait` to wait for all background processes

After the alert fires, document:
1. What PromQL expression triggered the alert
2. How you would find the offending connections in pg_stat_activity
3. The SQL command to terminate all idle-in-transaction sessions at once

---

## Alert Response Checklist

For every alert, follow this checklist:

- [ ] Identify which alert fired and read its description
- [ ] Note the time the alert fired
- [ ] Check Prometheus for related metrics (what else looks abnormal?)
- [ ] Check pg_stat_activity for active/blocked sessions
- [ ] Check system resources (CPU, disk, memory) if applicable
- [ ] Apply the fix
- [ ] Verify the metric that triggered the alert has returned to normal
- [ ] Confirm the alert is no longer FIRING in Prometheus
- [ ] Document the incident: what happened, what caused it, what fixed it, how long it took

---

## Reflection Questions

1. Why does the `PostgresLongRunningQuery` alert have `for: 0m` while `PostgresExporterDown` has `for: 1m`?
2. What is the risk of using `pg_terminate_backend` versus `pg_cancel_backend`?
3. If the cache hit ratio alert fires at 3 AM, what are the three most likely root causes in order of probability?
4. Why do you want to record the time-to-detect and time-to-resolve for each alert drill?
5. What is the difference between an alert that is PENDING and one that is FIRING?

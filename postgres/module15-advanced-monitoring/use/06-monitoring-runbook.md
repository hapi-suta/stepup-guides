# Use Exercise 06 - Monitoring Runbook

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 45 minutes
**Prerequisite:** Build Guides 01-05 complete, Use Exercises 01-05 complete

---

## Objective

Write a monitoring runbook that documents every alert in your system, what it means, how to respond, and what the escalation path is. A runbook is a living document - it gets better every time you handle an incident.

---

## Background

A runbook answers the question: "It's 2 AM, an alert fired, and I'm not fully awake. What do I do?"

A good runbook is:
- Short enough to read quickly under pressure
- Specific enough to be actionable without guessing
- Written for someone who did not set up the system
- Updated every time an alert fires and the runbook was wrong

---

## Part 1 - Runbook Structure

Each alert entry in a runbook needs:
1. Alert name and severity
2. What it means in plain language
3. Immediate triage steps (what to check first, takes 2 minutes)
4. Root cause analysis steps (what to dig into)
5. Fix procedures for each likely cause
6. Escalation path (who to call if you cannot fix it in X minutes)
7. Notes from past incidents

---

## Part 2 - Complete the runbook template

Fill in each section below using what you learned in the build guides and use exercises. This is your deliverable for this exercise.

---

# PostgreSQL Monitoring Runbook

**System:** pg-primary
**Stack:** PostgreSQL 16 + postgres_exporter + Prometheus + Grafana
**Last Updated:** [today's date]
**Owner:** [your name]

---

## Contacts

| Role | Name | Contact | Available |
|---|---|---|---|
| Primary DBA | [name] | [contact] | 24/7 |
| Secondary DBA | [name] | [contact] | Business hours |
| App team lead | [name] | [contact] | Business hours |
| Infrastructure | [name] | [contact] | 24/7 |

---

## Dashboard Links

- Grafana: `http://<server-ip>:3000`
- Prometheus Alerts: `http://<server-ip>:9090/alerts`
- Prometheus Targets: `http://<server-ip>:9090/targets`

---

## Alert: PostgresExporterDown

**Severity:** Critical
**PromQL:** `up{job="postgres"} == 0`
**Fires when:** postgres_exporter has been unreachable for 1 minute

**Plain language:** Prometheus cannot reach the metrics collection agent. We have lost visibility into the database. This is a monitoring failure, not necessarily a database failure.

### Triage (do this first, under 2 minutes)

Check if the exporter process is running:

```bash
sudo systemctl status postgres_exporter
```

Check if the port is listening:

```bash
ss -tlnp | grep 9187
```

Try the metrics endpoint manually:

```bash
curl -s http://localhost:9187/metrics | head -5
```

### Root Cause Analysis

**If the service is stopped:**

Check recent logs for crash reason:

```bash
sudo journalctl -u postgres_exporter -n 50 --no-pager
```

Common causes:
- Process crashed (OOM kill, segfault)
- PostgreSQL connection refused (PG is down or pg_hba.conf changed)
- Password expired on the monitoring role

**If the service is running but port is not listening:**

Check if another process took port 9187:

```bash
ss -tlnp | grep 9187
```

**If the config file was changed:**

Check for YAML errors:

```bash
sudo -u postgres_exporter /usr/local/bin/postgres_exporter \
  --web.listen-address=:9188 \
  --config.file=/etc/postgres_exporter/postgres_exporter.env \
  2>&1 | head -20
```

### Fix Procedures

**Restart the exporter:**

```bash
sudo systemctl restart postgres_exporter
sudo systemctl status postgres_exporter
curl -s http://localhost:9187/metrics | grep pg_up
```

**Fix connection credentials:**

```bash
sudo -i -u postgres
psql -c "ALTER ROLE postgres_exporter PASSWORD 'new_password';"
exit
sudo vi /etc/postgres_exporter/postgres_exporter.env
# Update password in DATA_SOURCE_NAME
sudo systemctl restart postgres_exporter
```

### Escalation

- 0-5 min: Restart the exporter
- 5-15 min: Check PostgreSQL is accessible, check credentials
- 15+ min: Escalate to primary DBA

---

## Alert: PostgresHighConnectionCount

**Severity:** Warning
**PromQL:** `sum(pg_stat_activity_count{state!="idle"}) by (instance) > 80`
**Fires when:** More than 80 non-idle connections have been open for 5 minutes

**Plain language:** The database is handling more active work than usual. If this continues, we may hit max_connections and reject new connections entirely.

### Triage (do this first, under 2 minutes)

Check the current connection breakdown:

```bash
sudo -i -u postgres
psql -c "
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state
ORDER BY count DESC;"
```

Check max_connections:

```bash
psql -c "SHOW max_connections;"
```

### Root Cause Analysis

Find long-running queries that might be holding connections:

```sql
SELECT pid, datname, usename, state, wait_event,
  round(extract(epoch from now() - query_start)::numeric, 0) AS duration_sec,
  left(query, 60) AS query
FROM pg_stat_activity
WHERE state != 'idle'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration_sec DESC
LIMIT 20;
```

Check for idle-in-transaction sessions (these hold connections and locks without doing work):

```sql
SELECT count(*), datname
FROM pg_stat_activity
WHERE state = 'idle in transaction'
GROUP BY datname;
```

Check for connection pooler health (if PgBouncer is in use):

```bash
# Not applicable in this single-node lab, but check in production
```

### Fix Procedures

**Terminate idle-in-transaction sessions older than 10 minutes:**

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '10 minutes';
```

**Cancel (not terminate) active long-running queries:**

```sql
SELECT pg_cancel_backend(pid)
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
  AND query NOT LIKE '%pg_stat_activity%';
```

**Emergency: increase max_connections temporarily (requires restart):**

This is a last resort. Increasing max_connections requires restarting PostgreSQL.

```bash
sudo -i -u postgres
psql -c "ALTER SYSTEM SET max_connections = 200;"
# Then restart PostgreSQL - this will disconnect all users
# sudo systemctl restart postgresql-16
```

### Escalation

- 0-10 min: Investigate and terminate stale sessions
- 10-20 min: Contact app team to check for connection leaks
- 20+ min: Consider increasing max_connections, escalate to primary DBA

---

## Alert: PostgresLongRunningQuery

**Severity:** Warning
**PromQL:** `pg_stat_activity_max_tx_duration{state="active"} > 300`
**Fires when:** A query has been running for more than 5 minutes (300 seconds)

**Plain language:** A query is taking much longer than expected. It may be blocking other queries, holding locks, or consuming excessive resources.

### Triage (do this first, under 2 minutes)

Find the long-running query:

```sql
SELECT pid, datname, usename, state,
  wait_event_type, wait_event,
  round(extract(epoch from now() - query_start)::numeric, 0) AS duration_sec,
  left(query, 80) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '1 minute'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration_sec DESC;
```

Is anything blocked waiting on this query?

```sql
SELECT blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

### Fix Procedures

**Cancel the query (sends SIGINT, allows the query to clean up):**

```sql
SELECT pg_cancel_backend(<pid>);
```

**Terminate the connection (sends SIGTERM, immediate):**

```sql
SELECT pg_terminate_backend(<pid>);
```

Use `pg_cancel_backend` first. Use `pg_terminate_backend` only if cancellation does not work within 30 seconds.

### Escalation

- 0-5 min: Identify the query and its owner
- 5-10 min: Contact app team to determine if safe to cancel
- 10+ min: Cancel or terminate if blocking other work

---

## Alert: PostgresLowCacheHitRatio

**Severity:** Warning
**Fires when:** Cache hit ratio drops below 90% sustained for 10 minutes

**Plain language:** PostgreSQL is reading too many blocks from disk instead of its memory cache. Queries will be slower than normal.

### Triage

Check per-database cache hit ratio:

```sql
SELECT datname,
  blks_hit,
  blks_read,
  round(100.0 * blks_hit / nullif(blks_hit + blks_read, 0), 2) AS hit_pct
FROM pg_stat_database
WHERE datname NOT IN ('template0', 'template1')
ORDER BY hit_pct ASC;
```

Find which tables have the most disk reads:

```sql
SELECT schemaname, relname,
  heap_blks_hit, heap_blks_read,
  round(100.0 * heap_blks_hit / nullif(heap_blks_hit + heap_blks_read, 0), 2) AS hit_pct
FROM pg_statio_user_tables
WHERE heap_blks_hit + heap_blks_read > 0
ORDER BY heap_blks_read DESC
LIMIT 10;
```

### Root Cause and Fix

- Sequential scan on a large table: add an index, or run `ANALYZE` if stats are stale
- `shared_buffers` is too small: increase in postgresql.conf and reload
- Bulk data load just ran: cache will warm back up over time

### Escalation

- 0-15 min: Identify the table/query causing disk reads
- 15-30 min: Determine if an index is missing
- 30+ min: Escalate to primary DBA for shared_buffers tuning

---

## Alert: PostgresIdleInTransaction

**Severity:** Warning
**Fires when:** A session has been idle-in-transaction for more than 10 minutes (600 seconds)

**Plain language:** An application started a transaction, did some work, and then stopped without committing or rolling back. The open transaction holds locks that may be blocking other work.

### Triage and Fix

Find idle-in-transaction sessions:

```sql
SELECT pid, datname, usename,
  round(extract(epoch from now() - state_change)::numeric, 0) AS idle_in_txn_sec,
  left(query, 60) AS last_query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY idle_in_txn_sec DESC;
```

Terminate them:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '10 minutes';
```

Contact the app team - this is usually a bug in connection handling code.

---

## Part 3 - Add an Incident Log section

At the end of your runbook, add this section and fill it in after each drill you run.

---

## Incident Log

| Date | Alert | Duration | Root Cause | Fix Applied | Time to Resolve | Notes |
|---|---|---|---|---|---|---|
| [date] | PostgresExporterDown | [duration] | Exporter stopped manually | systemctl start | [time] | Drill |
| [date] | PostgresLongRunningQuery | [duration] | pg_sleep(400) | pg_terminate_backend | [time] | Drill |

---

## Part 4 - Peer review

Exchange your completed runbook with another student. Review their runbook and answer:

1. Is every alert covered?
2. Are the triage steps specific enough to follow at 2 AM?
3. Are the escalation paths clear?
4. What is missing or unclear?

Give each other written feedback.

---

## Reflection Questions

1. Why should a runbook include SQL commands that are ready to copy-paste rather than general descriptions?
2. What is the difference between `pg_cancel_backend` and `pg_terminate_backend`? When do you use each?
3. Why is it important to contact the application team when you find idle-in-transaction sessions, rather than just terminating them and moving on?
4. A new DBA joins the team. How does having a well-maintained runbook reduce the time it takes them to handle incidents independently?
5. What would you add to this runbook after handling a real incident that was not covered by any existing alert?

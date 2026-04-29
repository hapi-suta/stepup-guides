# SURVIVE Runbook - 08: Monitoring Query Overhead

**Scenario:** A custom postgres_exporter query runs an expensive operation on every scrape, degrading database performance
**Symptom:** Slow query alerts fire for a repeating query from the monitoring system itself; scrape duration is high
**Severity:** Medium-High - monitoring is actively hurting the system it is supposed to observe

---

## Layer 1: Quick Triage

Check pg_stat_activity for any slow repeating queries:

```bash
sudo -i -u postgres
psql -c "
SELECT pid, usename, application_name, state,
  round(extract(epoch from now() - query_start)::numeric, 1) AS duration_sec,
  left(query, 80) AS query
FROM pg_stat_activity
WHERE state = 'active'
  AND query NOT LIKE '%pg_stat_activity%'
ORDER BY duration_sec DESC
LIMIT 10;"
```

Look for a query that:
1. Runs from the `postgres_exporter` user
2. Appears repeatedly (if you run this query multiple times, you see the same query pattern each time)
3. Takes more than 1 second to complete

If you see a query like `SELECT ... FROM pg_stat_activity ... CROSS JOIN ... pg_sleep ...` from the `postgres_exporter` user, that is your problem.

Check scrape duration in Prometheus (high scrape duration means queries are taking too long):

```bash
curl -s 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds{job="postgres"}' \
  | python3 -m json.tool | grep '"value"'
```

If `scrape_duration_seconds` is above 1-2 seconds, the exporter's queries are too slow.

---

## Layer 2: Root Cause Analysis

Check what custom queries are defined for the exporter:

```bash
sudo cat /etc/postgres_exporter/queries.yaml
```

Look for queries that:
- Use `pg_sleep()` (artificial delays - these should never be in monitoring queries)
- Do `CROSS JOIN` with slow operations
- Query very large tables without `LIMIT`
- Join many system catalogs together

Identify the specific query name by looking at the YAML key (e.g., `pg_expensive_monitoring_query:`).

Find that query in pg_stat_statements to measure its real cost:

```bash
psql -d postgres -c "
SELECT
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(total_exec_time::numeric, 2) AS total_ms,
  calls,
  left(query, 100) AS query
FROM pg_stat_statements
WHERE query LIKE '%pg_sleep%'
   OR query LIKE '%artificial%'
   OR mean_exec_time > 1000
ORDER BY mean_exec_time DESC
LIMIT 5;"
```

Exit psql:

```sql
\q
```

```bash
exit
```

---

## Layer 3: Fix and Verify

### Step 1 - Restore queries.yaml from backup

```bash
ls -la /etc/postgres_exporter/
```

If a backup exists:

```bash
sudo cp /etc/postgres_exporter/queries.yaml.bak_scenario08 /etc/postgres_exporter/queries.yaml
```

### Step 2 - If no backup, remove the expensive query manually

```bash
sudo vi /etc/postgres_exporter/queries.yaml
```

Find the `pg_expensive_monitoring_query:` section and delete it entirely - the key line, the `query:` block, and all its `metrics:` entries.

The rule of thumb: any monitoring query that takes more than 100ms on average is too expensive and needs to be rewritten or removed.

### Step 3 - Validate the remaining YAML is valid

```bash
python3 -c "import yaml; yaml.safe_load(open('/etc/postgres_exporter/queries.yaml'))" && echo "YAML valid"
```

### Step 4 - Restart postgres_exporter

```bash
sudo systemctl restart postgres_exporter
sudo systemctl status postgres_exporter
```

### Step 5 - Verify the expensive query is gone from pg_stat_activity

Wait 30 seconds, then check:

```bash
sudo -i -u postgres
psql -c "
SELECT usename, count(*) AS times_seen
FROM pg_stat_activity
WHERE usename = 'postgres_exporter'
  AND state = 'active'
GROUP BY usename;"
```

The exporter may appear briefly when running queries, but should not linger for multiple seconds.

### Step 6 - Check scrape duration has improved

```bash
curl -s 'http://localhost:9090/api/v1/query?query=scrape_duration_seconds{job="postgres"}' \
  | python3 -m json.tool | grep '"value"'
```

Expected output after fix (yours will differ):

```
"value": [1709305200.123, "0.045"]
```

Scrape duration should be under 100ms for a healthy postgres_exporter setup.

### Step 7 - Rewrite the query correctly (optional)

If the monitoring data from the expensive query was valuable, rewrite it to be fast:

```yaml
pg_session_summary:
  query: |
    SELECT
      datname,
      count(DISTINCT pid) AS session_count,
      count(DISTINCT CASE WHEN state = 'active' THEN pid END) AS active_sessions
    FROM pg_stat_activity
    WHERE datname IS NOT NULL
    GROUP BY datname
  metrics:
    - datname:
        usage: "LABEL"
        description: "Database name"
    - session_count:
        usage: "GAUGE"
        description: "Total sessions"
    - active_sessions:
        usage: "GAUGE"
        description: "Active sessions"
```

This version does the same job without `pg_sleep`, cross joins, or expensive subqueries.

---

## Prevention

- Test every custom monitoring query with `EXPLAIN ANALYZE` before adding it to queries.yaml
- Set a personal rule: no monitoring query may take more than 100ms on average
- Review `pg_stat_statements` monthly and check for high-frequency queries from the exporter
- Never use `pg_sleep()` in monitoring queries
- Use `LIMIT` on queries that scan large tables
- Check `scrape_duration_seconds` in Prometheus as a health metric for the monitoring stack itself

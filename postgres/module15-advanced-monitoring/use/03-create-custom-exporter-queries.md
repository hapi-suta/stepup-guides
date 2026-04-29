# Use Exercise 03 - Custom postgres_exporter Queries

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 40 minutes
**Prerequisite:** Build Guide 02 complete

---

## Objective

Write custom SQL queries for postgres_exporter using a `queries.yaml` file. Standard postgres_exporter metrics cover system-level PostgreSQL health. Custom queries let you expose business-level metrics - like order counts, queue depths, or table row counts - directly into Prometheus without writing a separate exporter.

---

## Background

postgres_exporter supports a `--extend.query-path` flag that points to a YAML file containing custom SQL queries. Each query defines:
- The SQL to run
- The metric name prefix
- Which columns are metric values vs labels
- The metric type (gauge, counter)
- A description

After postgres_exporter runs your query, the results appear at `localhost:9187/metrics` just like the built-in metrics.

---

## Part 1 - Understand the queries.yaml format

Here is the structure of one custom query entry:

```yaml
metric_name:
  query: "SELECT col1, col2, col3 FROM some_table"
  metrics:
    - col1:
        usage: "LABEL"
        description: "Used as a label, not a metric value"
    - col2:
        usage: "GAUGE"
        description: "A metric value that can go up or down"
    - col3:
        usage: "COUNTER"
        description: "A metric value that only increases"
```

Rules:
- Columns marked `LABEL` become Prometheus label dimensions
- Columns marked `GAUGE` become metric values
- Columns marked `COUNTER` become counter metrics (Prometheus will track rate-of-change)
- The query must return exactly one row per unique combination of label values

---

## Part 2 - Create the queries.yaml file

Log in to pg-primary.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

Create the custom queries file:

```bash
sudo vi /etc/postgres_exporter/queries.yaml
```

Add these custom queries:

```yaml
# Table row counts - useful for tracking data growth
pg_table_row_counts:
  query: |
    SELECT
      schemaname,
      relname AS table_name,
      n_live_tup AS row_count,
      n_dead_tup AS dead_row_count,
      last_vacuum,
      last_autovacuum,
      last_analyze
    FROM pg_stat_user_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY n_live_tup DESC
    LIMIT 20
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - table_name:
        usage: "LABEL"
        description: "Table name"
    - row_count:
        usage: "GAUGE"
        description: "Estimated number of live rows"
    - dead_row_count:
        usage: "GAUGE"
        description: "Estimated number of dead rows (waiting for vacuum)"

# Bloat estimation - tables that need VACUUM
pg_table_bloat:
  query: |
    SELECT
      schemaname,
      relname AS table_name,
      CASE WHEN n_live_tup > 0
        THEN round(100.0 * n_dead_tup / n_live_tup, 2)
        ELSE 0
      END AS bloat_ratio_pct
    FROM pg_stat_user_tables
    WHERE n_live_tup > 1000
    ORDER BY bloat_ratio_pct DESC
    LIMIT 20
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - table_name:
        usage: "LABEL"
        description: "Table name"
    - bloat_ratio_pct:
        usage: "GAUGE"
        description: "Dead tuples as a percentage of live tuples"

# Index usage - find unused indexes
pg_index_usage:
  query: |
    SELECT
      schemaname,
      relname AS table_name,
      indexrelname AS index_name,
      idx_scan AS index_scans,
      idx_tup_read AS tuples_read,
      idx_tup_fetch AS tuples_fetched
    FROM pg_stat_user_indexes
    ORDER BY idx_scan DESC
    LIMIT 30
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - table_name:
        usage: "LABEL"
        description: "Table name"
    - index_name:
        usage: "LABEL"
        description: "Index name"
    - index_scans:
        usage: "COUNTER"
        description: "Number of index scans initiated on this index"
    - tuples_read:
        usage: "COUNTER"
        description: "Number of index entries returned by scans"
    - tuples_fetched:
        usage: "COUNTER"
        description: "Number of live table rows fetched by index scans"

# Autovacuum worker activity
pg_autovacuum_activity:
  query: |
    SELECT
      datname,
      count(*) AS worker_count
    FROM pg_stat_activity
    WHERE backend_type = 'autovacuum worker'
    GROUP BY datname
  metrics:
    - datname:
        usage: "LABEL"
        description: "Database name"
    - worker_count:
        usage: "GAUGE"
        description: "Number of autovacuum workers currently running"

# Lock wait monitoring
pg_lock_waits:
  query: |
    SELECT
      wait_event_type,
      wait_event,
      count(*) AS session_count
    FROM pg_stat_activity
    WHERE wait_event_type IS NOT NULL
      AND state = 'active'
    GROUP BY wait_event_type, wait_event
  metrics:
    - wait_event_type:
        usage: "LABEL"
        description: "Type of wait event"
    - wait_event:
        usage: "LABEL"
        description: "Wait event name"
    - session_count:
        usage: "GAUGE"
        description: "Number of sessions waiting on this event"

# Sequence exhaustion check
pg_sequence_exhaustion:
  query: |
    SELECT
      schemaname,
      sequencename,
      last_value,
      (last_value::float8 / (
        CASE WHEN increment_by > 0
          THEN (max_value - min_value)::float8
          ELSE (min_value - max_value)::float8
        END
      )) * 100 AS pct_used
    FROM pg_sequences
    WHERE last_value IS NOT NULL
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - sequencename:
        usage: "LABEL"
        description: "Sequence name"
    - last_value:
        usage: "GAUGE"
        description: "Last value generated by the sequence"
    - pct_used:
        usage: "GAUGE"
        description: "Percentage of sequence range consumed"
```

Save and close the file.

---

## Part 3 - Set correct permissions on queries.yaml

```bash
sudo chown root:postgres_exporter /etc/postgres_exporter/queries.yaml
sudo chmod 640 /etc/postgres_exporter/queries.yaml
```

---

## Part 4 - Update the postgres_exporter systemd service

Add the `--extend.query-path` flag to the ExecStart line in the service unit.

```bash
sudo vi /etc/systemd/system/postgres_exporter.service
```

Find the `ExecStart=` line and update it to:

```ini
ExecStart=/usr/local/bin/postgres_exporter \
  --web.listen-address=:9187 \
  --web.telemetry-path=/metrics \
  --collector.stat_statements \
  --collector.postmaster \
  --extend.query-path=/etc/postgres_exporter/queries.yaml
```

Save and close the file.

---

## Part 5 - Reload systemd and restart the exporter

```bash
sudo systemctl daemon-reload
sudo systemctl restart postgres_exporter
```

---

## Part 6 - Check for errors

```bash
sudo systemctl status postgres_exporter
```

```bash
sudo journalctl -u postgres_exporter -n 30 --no-pager
```

If you see any YAML parsing errors or SQL errors, fix them in the queries.yaml file and restart again.

---

## Part 7 - Verify the custom metrics appear

```bash
curl -s http://localhost:9187/metrics | grep pg_table_row_counts
```

Expected output (yours will differ):

```
# HELP pg_table_row_counts_dead_row_count Dead rows (waiting for vacuum)
# TYPE pg_table_row_counts_dead_row_count gauge
pg_table_row_counts_dead_row_count{schemaname="public",table_name="pgbench_accounts"} 0
# HELP pg_table_row_counts_row_count Estimated number of live rows
# TYPE pg_table_row_counts_row_count gauge
pg_table_row_counts_row_count{schemaname="public",table_name="pgbench_accounts"} 100000
...
```

---

## Part 8 - Check the sequence exhaustion metric

```bash
curl -s http://localhost:9187/metrics | grep pg_sequence_exhaustion
```

Expected output (yours will differ):

```
# HELP pg_sequence_exhaustion_pct_used Percentage of sequence range consumed
# TYPE pg_sequence_exhaustion_pct_used gauge
pg_sequence_exhaustion_pct_used{schemaname="public",sequencename="pgbench_history_hid_seq"} 0.002341
```

---

## Part 9 - Query the new metrics in Prometheus

Wait 30 seconds for Prometheus to scrape the new metrics, then check them.

```bash
curl -s 'http://localhost:9090/api/v1/query?query=pg_table_row_counts_row_count' \
  | python3 -m json.tool | grep -A5 '"metric"'
```

---

## Part 10 - Build a Grafana panel for table bloat

Open Grafana and create a new panel on an existing dashboard (or a new dashboard).

**Query:**

```
pg_table_bloat_bloat_ratio_pct{job="postgres"}
```

**Panel settings:**
- Panel type: **Table**
- Title: `Table Bloat (Dead Tuple Ratio %)`
- Transform: Add a **Sort by** transformation on `bloat_ratio_pct` descending

This panel gives you an immediate list of which tables most need VACUUM.

---

## Part 11 - Write a custom business metric query

Your task: write a new custom query that exposes a business metric from the `pgbench` tables. Add it to `queries.yaml`.

For example, you could expose the total balance sum per branch:

```yaml
pg_pgbench_branch_balance:
  query: |
    SELECT
      bid::text AS branch_id,
      bbalance AS balance
    FROM pgbench_branches
  metrics:
    - branch_id:
        usage: "LABEL"
        description: "Branch ID"
    - balance:
        usage: "GAUGE"
        description: "Current branch balance"
```

Add this query to `/etc/postgres_exporter/queries.yaml`, restart the exporter, and verify the metric appears at `localhost:9187/metrics`.

---

## Reflection Questions

1. What is the difference between a `GAUGE` and `COUNTER` metric type in Prometheus? Give a PostgreSQL example of each.
2. Why do you need to limit custom monitoring queries (e.g., `LIMIT 20`)? What happens if you return 10,000 rows?
3. The sequence exhaustion query uses `last_value::float8 / (max_value - min_value)::float8`. Why cast to float8?
4. What alert would you write in Prometheus to fire when a sequence is more than 90% exhausted?
5. Why is the index usage metric a `COUNTER` rather than a `GAUGE`?

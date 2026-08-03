# BUILD 02: PostgreSQL Metrics with postgres_exporter

**Module 04 - Database Observability**
**Time Estimate:** 60 minutes
**Prerequisites:** Prometheus running (from BUILD 01), PostgreSQL running locally

---

## Step 1: Understand What postgres_exporter Is

**Analogy:** postgres_exporter is a bridge between PostgreSQL's `pg_stat_*` views and Prometheus. It connects to your PostgreSQL instance, runs queries against the stats views, and exposes the results as Prometheus metrics on an HTTP endpoint.

**How it works:**

```
[PostgreSQL] <--SQL queries-- [postgres_exporter :9187/metrics] <--HTTP scrape-- [Prometheus :9090]
```

1. postgres_exporter connects to PostgreSQL (like any other client)
2. Every time Prometheus scrapes it, postgres_exporter runs its built-in queries
3. It converts the query results into Prometheus metric format
4. Prometheus stores the metrics in its time-series database

**Why not query pg_stat views directly from Prometheus?**
Prometheus speaks HTTP and understands its own metric format. It does not speak the PostgreSQL wire protocol. The exporter is the translator.

---

## Step 2: Install postgres_exporter

**On your Mac, in your terminal:**

**Option A: Docker (recommended - simplest)**

```bash
docker pull quay.io/prometheuscommunity/postgres-exporter:latest
```

**Option B: Binary download**

```bash
# Download the latest release
curl -LO https://github.com/prometheus-community/postgres_exporter/releases/download/v0.16.0/postgres_exporter-0.16.0.darwin-arm64.tar.gz

# Extract
tar xzf postgres_exporter-0.16.0.darwin-arm64.tar.gz

# Move to a location in your PATH
sudo mv postgres_exporter-0.16.0.darwin-arm64/postgres_exporter /usr/local/bin/

# Verify
postgres_exporter --version
```

Expected output (yours will differ):
```
postgres_exporter, version 0.16.0 (branch: HEAD, revision: ...)
```

---

## Step 3: Configure postgres_exporter to Connect to PostgreSQL

postgres_exporter needs a PostgreSQL connection string. Create a dedicated monitoring user first.

**On your Mac, connect to your local PostgreSQL:**

```bash
psql -d postgres
```

**Note:** On Homebrew-installed PostgreSQL, there may not be a `postgres` role. Use `psql -d postgres` (which connects as your OS user) or `psql -U postgres` if you have a `postgres` role configured.

Create a monitoring user with minimal privileges:

```sql
-- Create a dedicated monitoring user
CREATE USER prometheus_exporter WITH PASSWORD 'exporter_pass_2024';

-- Grant access to statistics views
GRANT pg_monitor TO prometheus_exporter;

-- Grant connect to databases you want to monitor
GRANT CONNECT ON DATABASE postgres TO prometheus_exporter;

\q
```

**Why `pg_monitor`?** This built-in role (PostgreSQL 10+) grants read access to all `pg_stat_*` views, `pg_statio_*` views, and functions like `pg_stat_statements` without granting any write permissions. It is the least-privilege approach for monitoring.

Now start postgres_exporter.

**Option A: Docker**

```bash
docker run -d \
  --name postgres-exporter \
  -p 9187:9187 \
  -e DATA_SOURCE_NAME="postgresql://prometheus_exporter:exporter_pass_2024@host.docker.internal:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter:latest
```

**Note:** `host.docker.internal` lets Docker containers connect to services on your Mac. If your PostgreSQL is not on the default port, change `5432` accordingly.

**Option B: Binary**

```bash
export DATA_SOURCE_NAME="postgresql://prometheus_exporter:exporter_pass_2024@localhost:5432/postgres?sslmode=disable"
postgres_exporter --web.listen-address=":9187"
```

Verify postgres_exporter is running:

```bash
curl -s http://localhost:9187/metrics | head -20
```

Expected output (yours will differ):
```
# HELP pg_database_size_bytes Disk space used by the database
# TYPE pg_database_size_bytes gauge
pg_database_size_bytes{datname="postgres"} 8.675e+06
pg_database_size_bytes{datname="template0"} 7.602e+06
pg_database_size_bytes{datname="template1"} 7.717e+06
# HELP pg_stat_activity_count Number of connections in each state
# TYPE pg_stat_activity_count gauge
pg_stat_activity_count{datname="postgres",state="active"} 1
pg_stat_activity_count{datname="postgres",state="idle"} 3
...
```

This is the raw metrics output in Prometheus format. Each line has a metric name, optional labels in `{}`, and a numeric value.

---

## Step 4: Default Metrics Exposed

postgres_exporter ships with a set of built-in metrics that cover the most important PostgreSQL statistics.

**Connection metrics:**

| Metric | Source View | What It Measures |
|---|---|---|
| `pg_stat_activity_count` | `pg_stat_activity` | Connections per database and state |
| `pg_stat_activity_max_tx_duration` | `pg_stat_activity` | Longest running transaction |

**Database metrics:**

| Metric | Source View | What It Measures |
|---|---|---|
| `pg_database_size_bytes` | `pg_database_size()` | Disk space per database |
| `pg_stat_database_tup_fetched` | `pg_stat_database` | Rows fetched (reads) |
| `pg_stat_database_tup_inserted` | `pg_stat_database` | Rows inserted |
| `pg_stat_database_tup_updated` | `pg_stat_database` | Rows updated |
| `pg_stat_database_tup_deleted` | `pg_stat_database` | Rows deleted |
| `pg_stat_database_conflicts` | `pg_stat_database` | Recovery conflicts |
| `pg_stat_database_deadlocks` | `pg_stat_database` | Deadlock count |
| `pg_stat_database_xact_commit` | `pg_stat_database` | Committed transactions |
| `pg_stat_database_xact_rollback` | `pg_stat_database` | Rolled back transactions |

**Replication metrics:**

| Metric | Source View | What It Measures |
|---|---|---|
| `pg_stat_replication_pg_wal_lsn_diff` | `pg_stat_replication` | Replication lag in bytes |
| `pg_replication_lag` | Calculated | Replication lag in seconds |

**Background writer metrics:**

| Metric | Source View | What It Measures |
|---|---|---|
| `pg_stat_bgwriter_checkpoints_timed` | `pg_stat_bgwriter` | Scheduled checkpoints |
| `pg_stat_bgwriter_checkpoints_req` | `pg_stat_bgwriter` | Requested checkpoints |
| `pg_stat_bgwriter_buffers_checkpoint` | `pg_stat_bgwriter` | Buffers written during checkpoints |
| `pg_stat_bgwriter_buffers_backend` | `pg_stat_bgwriter` | Buffers written by backends (bad - means shared_buffers too small) |

**Lock metrics:**

| Metric | Source View | What It Measures |
|---|---|---|
| `pg_locks_count` | `pg_locks` | Lock count per mode |

---

## Step 5: Configure Prometheus to Scrape postgres_exporter

**On your Mac, in a new terminal:**

Edit the Prometheus configuration:

```bash
vi ~/lab-prometheus/prometheus.yml
```

Add the postgres_exporter target:

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  scrape_timeout: 10s

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "postgresql"
    static_configs:
      - targets: ["localhost:9187"]
        labels:
          instance: "local-postgres"
          environment: "lab"
```

**What the labels do:** The `instance` and `environment` labels are added to every metric scraped from this target. You can use them to filter in PromQL:

```promql
pg_database_size_bytes{environment="lab"}
```

Restart Prometheus (Ctrl+C in the Prometheus terminal, then start it again):

```bash
prometheus --config.file=$HOME/lab-prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/lab-prometheus/data \
  --web.listen-address=":9090"
```

Verify the target is being scraped:

1. Go to [http://localhost:9090/targets](http://localhost:9090/targets)
2. You should see two targets:
   - `prometheus (1/1 up)` - Prometheus itself
   - `postgresql (1/1 up)` - postgres_exporter

If `postgresql` shows as `DOWN`, check that postgres_exporter is running and accessible on port 9187.

---

## Step 6: Custom Queries - Adding Your Own Metrics

The built-in metrics are good, but as a DBA you need more. postgres_exporter supports custom queries via a `queries.yaml` file. This is where you define SQL queries whose results become Prometheus metrics.

**On your Mac, in your terminal:**

```bash
vi ~/lab-prometheus/queries.yaml
```

Add these custom queries:

```yaml
pg_stat_user_tables:
  query: |
    SELECT
      schemaname,
      relname,
      seq_scan,
      seq_tup_read,
      idx_scan,
      idx_tup_fetch,
      n_tup_ins,
      n_tup_upd,
      n_tup_del,
      n_live_tup,
      n_dead_tup,
      last_vacuum,
      last_autovacuum,
      last_analyze,
      last_autoanalyze
    FROM pg_stat_user_tables
  metrics:
    - schemaname:
        usage: "LABEL"
        description: "Schema name"
    - relname:
        usage: "LABEL"
        description: "Table name"
    - seq_scan:
        usage: "COUNTER"
        description: "Number of sequential scans initiated"
    - seq_tup_read:
        usage: "COUNTER"
        description: "Number of live rows fetched by sequential scans"
    - idx_scan:
        usage: "COUNTER"
        description: "Number of index scans initiated"
    - idx_tup_fetch:
        usage: "COUNTER"
        description: "Number of live rows fetched by index scans"
    - n_tup_ins:
        usage: "COUNTER"
        description: "Number of rows inserted"
    - n_tup_upd:
        usage: "COUNTER"
        description: "Number of rows updated"
    - n_tup_del:
        usage: "COUNTER"
        description: "Number of rows deleted"
    - n_live_tup:
        usage: "GAUGE"
        description: "Estimated number of live rows"
    - n_dead_tup:
        usage: "GAUGE"
        description: "Estimated number of dead rows"
    - last_vacuum:
        usage: "GAUGE"
        description: "Last time vacuum ran on this table"
    - last_autovacuum:
        usage: "GAUGE"
        description: "Last time autovacuum ran on this table"
    - last_analyze:
        usage: "GAUGE"
        description: "Last time analyze ran on this table"
    - last_autoanalyze:
        usage: "GAUGE"
        description: "Last time autoanalyze ran on this table"

pg_stat_statements_top:
  # NOTE: This query requires pg_stat_statements extension.
  # Enable it first: ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
  # Then restart PostgreSQL and run: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
  # If pg_stat_statements is not loaded, this query will error - remove this block if not using it.
  query: |
    SELECT
      queryid,
      left(query, 60) AS short_query,
      calls,
      total_exec_time,
      mean_exec_time,
      rows
    FROM pg_stat_statements
    ORDER BY total_exec_time DESC
    LIMIT 20
  metrics:
    - queryid:
        usage: "LABEL"
        description: "Query ID"
    - short_query:
        usage: "LABEL"
        description: "First 60 chars of query"
    - calls:
        usage: "COUNTER"
        description: "Number of times executed"
    - total_exec_time:
        usage: "COUNTER"
        description: "Total execution time in milliseconds"
    - mean_exec_time:
        usage: "GAUGE"
        description: "Mean execution time in milliseconds"
    - rows:
        usage: "COUNTER"
        description: "Total number of rows returned"

pg_cache_hit_ratio:
  query: |
    SELECT
      datname,
      CASE WHEN blks_hit + blks_read > 0
        THEN round(100.0 * blks_hit / (blks_hit + blks_read), 2)
        ELSE 100
      END AS cache_hit_ratio
    FROM pg_stat_database
    WHERE datname NOT IN ('template0', 'template1')
  metrics:
    - datname:
        usage: "LABEL"
        description: "Database name"
    - cache_hit_ratio:
        usage: "GAUGE"
        description: "Cache hit ratio percentage"
```

**Understanding the queries.yaml format:**

| Field | Purpose |
|---|---|
| Top-level key (e.g., `pg_stat_user_tables`) | Becomes the metric name prefix |
| `query` | The SQL query to run |
| `metrics` | Maps each column to a metric |
| `usage: "LABEL"` | This column becomes a label (dimension), not a metric value |
| `usage: "COUNTER"` | This column is a counter metric (always increasing) |
| `usage: "GAUGE"` | This column is a gauge metric (can go up or down) |

Restart postgres_exporter with the custom queries file.

**Docker:**

```bash
docker stop postgres-exporter && docker rm postgres-exporter

docker run -d \
  --name postgres-exporter \
  -p 9187:9187 \
  -v $HOME/lab-prometheus/queries.yaml:/etc/queries.yaml \
  -e DATA_SOURCE_NAME="postgresql://prometheus_exporter:exporter_pass_2024@host.docker.internal:5432/postgres?sslmode=disable" \
  quay.io/prometheuscommunity/postgres-exporter:latest \
  --extend.query-path=/etc/queries.yaml
```

**Binary:**

```bash
# Stop the existing process (Ctrl+C) and restart with:
export DATA_SOURCE_NAME="postgresql://prometheus_exporter:exporter_pass_2024@localhost:5432/postgres?sslmode=disable"
postgres_exporter --web.listen-address=":9187" --extend.query-path=$HOME/lab-prometheus/queries.yaml
```

Verify custom metrics are being exported:

```bash
curl -s http://localhost:9187/metrics | grep pg_cache_hit_ratio
```

Expected output (yours will differ):
```
# HELP pg_cache_hit_ratio_cache_hit_ratio Cache hit ratio percentage
# TYPE pg_cache_hit_ratio_cache_hit_ratio gauge
pg_cache_hit_ratio_cache_hit_ratio{datname="postgres"} 99.87
```

---

## Step 7: Key PostgreSQL Metrics Every DBA Should Monitor

Here are the metrics mapped to their pg_stat views with recommended alert thresholds:

### pg_stat_activity - Connection Health

```promql
# Active connections per database
pg_stat_activity_count{state="active"}

# Idle in transaction connections (these hold locks and block vacuum)
pg_stat_activity_count{state="idle in transaction"}

# Longest running transaction in seconds
pg_stat_activity_max_tx_duration
```

**Alert threshold:** Active connections > 80% of max_connections. Idle in transaction > 5 minutes.

### pg_stat_user_tables - Table Health

```promql
# Sequential scans per second (high = missing indexes)
rate(pg_stat_user_tables_seq_scan{relname="your_table"}[5m])

# Dead tuples (high = vacuum not keeping up)
pg_stat_user_tables_n_dead_tup

# Dead tuple ratio
pg_stat_user_tables_n_dead_tup / (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup)
```

**Alert threshold:** Dead tuple ratio > 10% on any table. Sequential scan rate increasing on large tables.

### pg_stat_bgwriter - Checkpoint Health

```promql
# Checkpoint frequency (requested checkpoints = too frequent = high WAL volume)
rate(pg_stat_bgwriter_checkpoints_req[5m])

# Backend writes (should be close to zero - means shared_buffers is too small)
rate(pg_stat_bgwriter_buffers_backend[5m])
```

**Alert threshold:** `buffers_backend` > 0 consistently. `checkpoints_req` increasing.

### pg_stat_replication - Replication Health

```promql
# Replication lag in bytes
pg_stat_replication_pg_wal_lsn_diff

# Replication lag in seconds
pg_replication_lag
```

**Alert threshold:** Lag > 30 seconds for async replicas. Any lag > 0 for sync replicas.

### pg_database_size - Storage

```promql
# Database size in bytes
pg_database_size_bytes

# Size growth rate (bytes per second over last hour)
rate(pg_database_size_bytes[1h])
```

**Alert threshold:** Growth rate suggests you will hit storage limit within 7 days.

---

## Step 8: Verify Metrics in Prometheus Web UI

**In your browser, go to http://localhost:9090:**

Try these PromQL queries:

```promql
# Database sizes
pg_database_size_bytes

# Connection count by state
pg_stat_activity_count

# Cache hit ratio
pg_cache_hit_ratio_cache_hit_ratio

# Transaction rate (commits per second)
rate(pg_stat_database_xact_commit[5m])

# Dead tuples per table
pg_stat_user_tables_n_dead_tup > 0
```

Click the **Graph** tab to see these metrics over time. The more time passes, the more interesting the graphs become.

---

## Step 9: Practical Summary

You now have a working PostgreSQL monitoring pipeline:

```
[PostgreSQL]
    |
    | SQL queries (pg_stat_* views)
    v
[postgres_exporter :9187]
    |
    | HTTP /metrics (Prometheus format)
    v
[Prometheus :9090]
    |
    | PromQL queries
    v
[Web UI / Grafana (next BUILD)]
```

**What to do next:**
1. Leave Prometheus and postgres_exporter running
2. Generate some database activity (INSERT, UPDATE, VACUUM) to see metrics change
3. In BUILD 03, we will add Grafana to visualize these metrics in dashboards
4. In BUILD 04, we will set up alerting rules for PostgreSQL-specific conditions

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| postgres_exporter purpose | Bridge between pg_stat views and Prometheus metric format |
| Monitoring user | Use `pg_monitor` role for least-privilege access |
| Default metrics | Connections, database size, replication lag, transactions, checkpoints |
| Custom queries | queries.yaml maps SQL query columns to Prometheus metrics |
| COUNTER vs GAUGE | Counters always increase (use rate()); gauges go up and down (use raw value) |
| Key DBA metrics | Connections, dead tuples, cache hit ratio, replication lag, checkpoint health |
| PromQL for PostgreSQL | Filter by database, table, state using label selectors |
| Scrape configuration | Add postgres_exporter as a target in prometheus.yml |

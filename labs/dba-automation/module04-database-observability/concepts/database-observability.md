# Concepts: Database Observability

**Module 04 - Database Observability**
**Quick reference for the concepts covered in BUILD 01 through BUILD 04.**

---

## Prometheus Architecture Diagram

```
                         +-------------------+
                         |   Alertmanager    |
                         |    :9093          |
                         +--------^----------+
                                  |
                            fires alerts
                                  |
+------------------+     +--------+----------+     +------------------+
|  PostgreSQL      |     |    Prometheus     |     |    Grafana       |
|  :5432           |     |    :9090          |<----|    :3000         |
+--------+---------+     +----^----^----^----+     +------------------+
         |                     |    |    |          (queries Prometheus
   SQL queries                 |    |    |           for visualization)
         |                     |    |    |
+--------v---------+     scrapes    |    |
| postgres_exporter |-----+    |    |
|  :9187            |          |    |
+------------------+     +-----+----+----+
                         | Other targets  |
                         | node_exporter  |
                         | :9100          |
                         +----------------+
```

**Data flow:**

1. postgres_exporter connects to PostgreSQL and runs SQL queries against `pg_stat_*` views
2. Prometheus scrapes postgres_exporter's `/metrics` endpoint every 15 seconds
3. Prometheus evaluates alert rules and sends firing alerts to Alertmanager
4. Alertmanager routes alerts to the appropriate channel (email, Slack, PagerDuty)
5. Grafana queries Prometheus to render dashboards

---

## PromQL Cheat Sheet for DBAs

### Basic Queries

```promql
# Current value of a metric (instant vector)
pg_database_size_bytes

# Values over last 5 minutes (range vector)
pg_database_size_bytes[5m]

# Filter by label (WHERE clause)
pg_stat_activity_count{state="active"}

# Regex filter
pg_database_size_bytes{datname=~"prod.*"}

# Exclude
pg_database_size_bytes{datname!="template0"}
```

### Rate and Change

```promql
# Per-second rate of a counter over 5 minutes
rate(pg_stat_database_xact_commit[5m])

# Total increase over 1 hour
increase(pg_stat_database_xact_commit[1h])

# Change in a gauge over 1 hour
delta(pg_database_size_bytes[1h])

# Per-second rate of change for a gauge
deriv(pg_database_size_bytes[1h])
```

### Aggregation (GROUP BY equivalents)

```promql
# Total across all labels
sum(pg_stat_activity_count)

# Group by specific label (GROUP BY datname)
sum by (datname) (pg_stat_activity_count)

# Average across instances
avg by (datname) (pg_stat_database_xact_commit)

# Maximum value
max(pg_database_size_bytes)

# Count of time series matching
count(pg_stat_activity_count > 0)

# Top 5 by value
topk(5, pg_database_size_bytes)

# Bottom 5 by value
bottomk(5, pg_database_size_bytes)
```

### Math Operations

```promql
# Percentage calculation
pg_stat_database_blks_hit / (pg_stat_database_blks_hit + pg_stat_database_blks_read) * 100

# Comparison (returns only matching series)
pg_database_size_bytes > 1e9

# Boolean (returns 1 or 0)
pg_database_size_bytes > bool 1e9
```

### Time Functions

```promql
# Time since metric last changed
time() - pg_stat_user_tables_last_autovacuum

# Average over time window
avg_over_time(pg_stat_activity_count[1h])

# Max over time window
max_over_time(pg_stat_activity_count[1h])

# Predict value in 4 hours based on last 24 hours
predict_linear(pg_database_size_bytes[24h], 4 * 3600)
```

### Histogram Queries

```promql
# 95th percentile of request duration
histogram_quantile(0.95, rate(http_request_duration_seconds_bucket[5m]))

# 99th percentile
histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))
```

---

## Key PostgreSQL Metrics Reference Table

| Metric Name | Type | What It Measures | Alert Threshold | Source View |
|---|---|---|---|---|
| `pg_stat_activity_count` | Gauge | Connections per state | > 80% of max_connections | `pg_stat_activity` |
| `pg_stat_activity_max_tx_duration` | Gauge | Longest transaction (seconds) | > 300s (5 min) | `pg_stat_activity` |
| `pg_database_size_bytes` | Gauge | Database disk usage | Predict full in < 7 days | `pg_database_size()` |
| `pg_stat_database_xact_commit` | Counter | Committed transactions | N/A (use rate for TPS) | `pg_stat_database` |
| `pg_stat_database_xact_rollback` | Counter | Rolled back transactions | rate > 5% of commits | `pg_stat_database` |
| `pg_stat_database_deadlocks` | Counter | Deadlock count | Any increase (rate > 0) | `pg_stat_database` |
| `pg_stat_database_blks_hit` | Counter | Buffer cache hits | N/A (use for cache ratio) | `pg_stat_database` |
| `pg_stat_database_blks_read` | Counter | Disk block reads | N/A (use for cache ratio) | `pg_stat_database` |
| `pg_stat_user_tables_seq_scan` | Counter | Sequential scans | rate increasing on large tables | `pg_stat_user_tables` |
| `pg_stat_user_tables_n_dead_tup` | Gauge | Dead tuples per table | > 10% of live tuples | `pg_stat_user_tables` |
| `pg_stat_user_tables_n_live_tup` | Gauge | Live tuples per table | N/A (baseline reference) | `pg_stat_user_tables` |
| `pg_stat_bgwriter_checkpoints_req` | Counter | Forced checkpoints | rate > 0.01/s (too frequent) | `pg_stat_bgwriter` |
| `pg_stat_bgwriter_buffers_backend` | Counter | Backend-written buffers | rate > 0 (shared_buffers too small) | `pg_stat_bgwriter` |
| `pg_replication_lag` | Gauge | Replica lag in seconds | > 30s (async), > 0 (sync) | `pg_stat_replication` |
| `pg_locks_count` | Gauge | Locks per mode | Exclusive locks > 5 | `pg_locks` |

### Derived Metrics (calculated from the above)

| Derived Metric | Formula | Alert Threshold |
|---|---|---|
| Cache hit ratio | `blks_hit / (blks_hit + blks_read) * 100` | < 95% |
| Rollback ratio | `xact_rollback / (xact_commit + xact_rollback) * 100` | > 5% |
| Dead tuple ratio | `n_dead_tup / (n_live_tup + n_dead_tup) * 100` | > 10% |
| Connection utilization | `current_connections / max_connections * 100` | > 80% |
| Transactions per second | `rate(xact_commit[5m]) + rate(xact_rollback[5m])` | N/A (baseline reference) |

---

## Grafana Panel Types and When to Use Each

| Panel Type | Best For | PostgreSQL Example |
|---|---|---|
| **Time series** | Trends over time | Connections, TPS, replication lag over 24 hours |
| **Stat** | Current single value | Current connection count, current cache hit ratio |
| **Gauge** | Value within a known range | CPU%, cache hit ratio (0-100%) |
| **Bar gauge** | Comparing values across items | Database sizes, connections per database |
| **Table** | Detailed listings | Top queries, table bloat report, lock list |
| **Heatmap** | Distribution patterns | Query latency distribution over time |
| **Alert list** | Active alert summary | On-call dashboard showing firing alerts |
| **Text** | Static information | Links to runbooks, on-call schedule |
| **Logs** | Log entries (requires Loki) | PostgreSQL error logs |

---

## SLI / SLO / SLA Definitions with Database Examples

### SLI (Service Level Indicator)

A measurable metric that represents a dimension of service health.

| SLI | Measurement | Good Event | Total Events |
|---|---|---|---|
| Availability | Successful health checks | Check returns healthy | All health checks |
| Query latency | p95 response time | Queries completing < 100ms | All queries |
| Error rate | Failed transactions | Committed transactions | All transactions |
| Data freshness | Replication lag | Lag < 10 seconds | All measurements |

### SLO (Service Level Objective)

An internal target for your SLI over a time window.

| SLI | SLO | Window | Error Budget |
|---|---|---|---|
| Availability | 99.9% | 30 days | 43.2 minutes |
| Query latency (p95) | < 100ms | 30 days | 0.1% of queries can exceed |
| Error rate | < 0.1% | 30 days | 1 in 1000 transactions |
| Data freshness | 99.5% < 10s lag | 30 days | 3.6 hours of lag allowed |

### SLA (Service Level Agreement)

An external contractual commitment - usually less strict than your SLO.

| SLI | SLO (internal target) | SLA (customer commitment) |
|---|---|---|
| Availability | 99.9% | 99.5% |
| Query latency | p95 < 100ms | p95 < 500ms |

**Why the gap?** Your SLO is stricter than your SLA. This gives you a buffer. If you only target your SLA, you will breach it regularly.

---

## Alert Routing Decision Tree

```
Alert fires in Prometheus
    |
    v
Is data at risk? (storage full, replication broken, corruption)
    |
    +-- YES --> severity: critical --> PagerDuty / Phone call
    |                                   Response: Immediate
    |
    +-- NO
        |
        v
    Is performance degraded? (high CPU, connection exhaustion, slow queries)
        |
        +-- YES --> severity: warning --> Slack / Email
        |                                 Response: Business hours
        |
        +-- NO
            |
            v
        Is it informational? (backup completed, maintenance starting)
            |
            +-- YES --> severity: info --> Dashboard only
                                          Response: Next review
```

**Alert notification channels:**

| Channel | Best For | Latency | Cost |
|---|---|---|---|
| PagerDuty / OpsGenie | Critical - waking someone up | Seconds | Paid service |
| Phone call (via PagerDuty) | Critical - absolute must-respond | Seconds | Included in PagerDuty |
| Slack | Warnings - team awareness | Seconds | Free tier available |
| Email | Warnings and summaries | Minutes | Free |
| Dashboard (Grafana) | Info and overview | Real-time | Free |

---

## Prometheus Configuration Reference

### Minimal prometheus.yml

```yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s

alerting:
  alertmanagers:
    - static_configs:
        - targets: ["localhost:9093"]

rule_files:
  - "alert_rules.yml"

scrape_configs:
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]

  - job_name: "postgresql"
    static_configs:
      - targets: ["localhost:9187"]
```

### Scrape config with multiple PostgreSQL instances

```yaml
scrape_configs:
  - job_name: "postgresql"
    static_configs:
      - targets: ["db-primary:9187"]
        labels:
          role: "primary"
          environment: "production"
          datacenter: "us-east-1"

      - targets: ["db-replica-1:9187", "db-replica-2:9187"]
        labels:
          role: "replica"
          environment: "production"
          datacenter: "us-east-1"

      - targets: ["db-staging:9187"]
        labels:
          role: "primary"
          environment: "staging"
          datacenter: "us-east-1"
```

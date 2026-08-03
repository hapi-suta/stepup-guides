# Concepts: Observability Practices for Databases

**Module 07 - Performance, Monitoring and Observability**
**Quick reference for Prometheus, Grafana, SLIs, SLOs, and observability practices for database infrastructure.**

---

## Monitoring vs Observability

Monitoring tells you **when** something is broken. Observability tells you **why** it is broken without needing to deploy new instrumentation.

```
Monitoring:
  "CPU is at 95%"           <-- known-known
  "Connections exceeded 80%  <-- known-known
  "Disk will fill in 3 days" <-- known-known

Observability:
  "CPU is at 95% because query X changed its execution plan
   after ANALYZE ran at 03:00, causing a sequential scan on
   a 200M row table, which also increased IO:DataFileRead
   by 400% and caused downstream lock contention."
```

Observability requires three pillars:
1. **Metrics** - Numeric measurements over time (Prometheus, CloudWatch)
2. **Logs** - Structured text records of events (CloudWatch Logs, Loki)
3. **Traces** - Request flow across services (X-Ray, Jaeger)

For database teams, metrics are the most important pillar. Logs are second. Traces are useful only when correlating database performance with application behavior.

---

## Prometheus for Database Monitoring

### Why Prometheus

CloudWatch and Performance Insights are excellent for AWS-managed databases. But many organizations need:
- A single monitoring platform across AWS, on-premises, and multi-cloud
- Long-term metric retention beyond what CloudWatch offers
- Custom dashboards that combine database metrics with application metrics
- Alerting rules that correlate across multiple systems
- No vendor lock-in

Prometheus fills this role. It is the industry standard for open-source metrics collection.

### Prometheus Architecture

```
                         +-------------------+
                         |   Alertmanager    |
                         |    :9093          |
                         +--------^----------+
                                  |
                            fires alerts
                                  |
+------------------+     +--------+----------+     +------------------+
|  Aurora          |     |    Prometheus     |     |    Grafana       |
|  (via exporter   |     |    :9090          |<----|    :3000         |
|   or CW metrics) |     +----^----^----^----+     +------------------+
+--------+---------+          |    |    |
         |                    |    |    |
   pg_stat queries            |    |    |
         |                    |    |    |
+--------v---------+    scrapes    |    |
| postgres_exporter |-----+   |    |
|  :9187            |         |    |
+------------------+    +-----+----+----+
                        | node_exporter  |
                        | :9100          |
                        +----------------+
```

**Data flow:**
1. postgres_exporter connects to PostgreSQL and runs SQL queries against pg_stat views
2. Prometheus scrapes postgres_exporter's /metrics endpoint every 15 seconds
3. Prometheus evaluates alert rules and sends firing alerts to Alertmanager
4. Alertmanager routes alerts to the appropriate channel (email, Slack, PagerDuty)
5. Grafana queries Prometheus to render dashboards

### For Aurora/RDS: CloudWatch Exporter

Since you cannot install postgres_exporter directly on RDS/Aurora instances, you have two options:

**Option 1: postgres_exporter from an EC2 instance**
- Deploy postgres_exporter on an EC2 instance in the same VPC
- Configure it to connect to your Aurora endpoint
- Prometheus scrapes the EC2-hosted exporter

**Option 2: CloudWatch Exporter (yet-another-cloudwatch-exporter)**
- Pulls CloudWatch metrics into Prometheus format
- No need for direct database connectivity
- Gets the same metrics CloudWatch provides, but in Prometheus format
- Useful for unified Prometheus/Grafana dashboards

```
Option 1:
  [Aurora] <--SQL-- [EC2: postgres_exporter :9187] <--scrape-- [Prometheus]

Option 2:
  [Aurora] --> [CloudWatch] <--API-- [cloudwatch_exporter :9106] <--scrape-- [Prometheus]
```

### Key PromQL Queries for Database Teams

**Connection monitoring:**
```promql
# Current connections by state
pg_stat_activity_count{state="active"}

# Connection utilization percentage
pg_stat_activity_count / pg_settings_max_connections * 100

# Alert: connections above 80% of max
pg_stat_activity_count > 0.8 * pg_settings_max_connections
```

**Transaction health:**
```promql
# Transactions per second
rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m])

# Rollback ratio (should be < 5%)
rate(pg_stat_database_xact_rollback[5m])
  / (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
  * 100

# Deadlock rate
rate(pg_stat_database_deadlocks[5m])
```

**Cache performance:**
```promql
# Cache hit ratio (should be > 99% for OLTP)
pg_stat_database_blks_hit
  / (pg_stat_database_blks_hit + pg_stat_database_blks_read)
  * 100

# Cache misses per second
rate(pg_stat_database_blks_read[5m])
```

**Table health:**
```promql
# Dead tuple ratio per table (vacuum effectiveness)
pg_stat_user_tables_n_dead_tup
  / (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup)
  * 100

# Sequential scan rate (high on large tables = missing index)
rate(pg_stat_user_tables_seq_scan[5m])

# Tables that have not been vacuumed in over 24 hours
time() - pg_stat_user_tables_last_autovacuum > 86400
```

**Replication:**
```promql
# Replication lag in seconds
pg_replication_lag

# Predict when lag will exceed 30s at current growth rate
predict_linear(pg_replication_lag[1h], 3600) > 30
```

**Storage:**
```promql
# Database size
pg_database_size_bytes

# Growth rate (bytes per second)
deriv(pg_database_size_bytes[1h])

# Predict size in 30 days
predict_linear(pg_database_size_bytes[7d], 30 * 86400)
```

---

## Grafana for Database Dashboards

### Why Grafana

Grafana is the visualization layer for Prometheus. While Prometheus has a built-in web UI, it only shows raw graphs. Grafana provides:
- Rich dashboard panels (time series, gauges, tables, heatmaps)
- Templating with variables (select database, instance, time range)
- Alerting rules that complement Prometheus alerts
- Annotations (mark deployments, incidents on dashboards)
- Multi-data-source support (Prometheus + CloudWatch + Loki in one dashboard)

### Recommended Dashboard Layout for Aurora

**Dashboard 1: Cluster Overview**

| Panel | Type | Data Source | Query |
|-------|------|-------------|-------|
| Cluster Status | Stat | CloudWatch | EngineUptime per instance |
| Active Connections | Time series | CloudWatch | DatabaseConnections |
| CPU Utilization | Time series | CloudWatch | CPUUtilization per instance |
| Replica Lag | Time series | CloudWatch | AuroraReplicaLag per reader |
| Commit Latency | Time series | CloudWatch | CommitLatency |
| Buffer Cache Hit | Gauge | CloudWatch | BufferCacheHitRatio |
| TXID Age | Stat | CloudWatch | MaximumUsedTransactionIDs |
| Storage Used | Stat | CloudWatch | VolumeBytesUsed |

**Dashboard 2: Query Performance**

| Panel | Type | Data Source | Query |
|-------|------|-------------|-------|
| Top 10 Queries by Time | Table | Prometheus | pg_stat_statements top by total_exec_time |
| Queries per Second | Time series | Prometheus | rate(pg_stat_database_xact_commit) |
| Cache Hit Ratio | Gauge | Prometheus | cache_hit_ratio |
| Temp File Usage | Time series | Prometheus | pg_stat_statements temp_blks_written |
| Dead Tuples by Table | Bar gauge | Prometheus | pg_stat_user_tables_n_dead_tup |
| Sequential Scans | Time series | Prometheus | rate(pg_stat_user_tables_seq_scan) |

**Dashboard 3: On-Call**

| Panel | Type | Data Source | Query |
|-------|------|-------------|-------|
| Firing Alerts | Alert list | Prometheus | All firing alerts |
| Connection Count | Stat (big number) | CloudWatch | DatabaseConnections |
| CPU | Stat (big number) | CloudWatch | CPUUtilization |
| Freeable Memory | Stat (big number) | CloudWatch | FreeableMemory |
| Recent Events | Table | CloudWatch Logs | RDS events last 4 hours |
| Runbook Links | Text | Static | Links to survive runbooks |

### Grafana Variables

Variables make dashboards reusable across instances:

```
Variable: $instance
  Type: Query
  Query: label_values(pg_stat_activity_count, instance)
  Usage: pg_stat_activity_count{instance="$instance"}

Variable: $database
  Type: Query
  Query: label_values(pg_database_size_bytes, datname)
  Usage: pg_database_size_bytes{datname="$database"}
```

---

## SLIs, SLOs, and Error Budgets for Databases

### Service Level Indicators (SLIs)

An SLI is a quantitative measure of a specific aspect of database service quality. For databases, the four most important SLIs are:

**1. Availability SLI**
```
Definition: Proportion of time the database accepts and processes queries
Measurement: Successful health check probes / Total health check probes
Good event: Health check returns successfully within 5 seconds
```

**2. Latency SLI**
```
Definition: Proportion of queries that complete within an acceptable time
Measurement: Queries completing < threshold / Total queries
Good event: Query completes in < 100ms (OLTP) or < 30s (analytics)
```

**3. Error Rate SLI**
```
Definition: Proportion of transactions that complete without error
Measurement: Committed transactions / Total transactions (commit + rollback)
Good event: Transaction commits successfully
```

**4. Data Freshness SLI (for replicas)**
```
Definition: Proportion of time that replica data is within acceptable staleness
Measurement: Time samples where lag < threshold / Total time samples
Good event: Replica lag < 10 seconds
```

### Service Level Objectives (SLOs)

SLOs are targets for your SLIs over a rolling time window:

| SLI | SLO | Window | Error Budget |
|-----|-----|--------|-------------|
| Availability | 99.9% | 30 days | 43.2 minutes of downtime |
| Query latency (p95) | < 100ms | 30 days | 0.1% of queries can exceed |
| Error rate | < 0.1% | 30 days | 1 in 1,000 transactions can fail |
| Data freshness | 99.5% under 10s lag | 30 days | 3.6 hours of lag allowed |

### Error Budgets

The error budget is the amount of unreliability you can tolerate before breaching your SLO.

```
Availability SLO: 99.9%
Error budget: 100% - 99.9% = 0.1% of the 30-day window
0.1% of 30 days = 0.001 * 30 * 24 * 60 = 43.2 minutes

This means you can have 43.2 minutes of downtime per month
before breaching your SLO.
```

**How to use error budgets:**

| Budget Status | Action |
|---------------|--------|
| Budget > 50% remaining | Normal operations, deploy freely |
| Budget 20-50% remaining | Increase caution, review changes before deploying |
| Budget < 20% remaining | Freeze non-critical changes, focus on reliability |
| Budget exhausted | Stop all changes, investigate root causes, implement fixes |

### Implementing SLOs with Prometheus

**Availability SLO:**
```promql
# Availability over 30 days (probe-based)
avg_over_time(up{job="postgresql"}[30d])

# Alert when error budget is being consumed too fast
# (burn rate alert)
1 - avg_over_time(up{job="postgresql"}[1h]) > 14.4 * (1 - 0.999)
```

**Latency SLO:**
```promql
# Percentage of queries under 100ms (requires histogram)
histogram_quantile(0.95, rate(pg_query_duration_seconds_bucket[5m])) < 0.1

# Or via pg_stat_statements mean_exec_time
pg_stat_statements_mean_exec_time > 100
```

---

## Alerting Best Practices for Database Teams

### What to Alert On

**Page immediately (wake someone up):**
- Database unreachable (availability SLO breach)
- Storage < 5% remaining
- TXID wraparound > 1.5 billion
- Replication broken (lag > 5 minutes or replica down)
- Connection exhaustion (> 95% of max_connections)

**Notify during business hours:**
- CPU > 80% sustained for 15 minutes
- Memory < 20% remaining
- Read/write latency above baseline
- Deadlock rate increasing
- Connections > 80% of max

**Dashboard only (review weekly):**
- Database size growth rate
- Cache hit ratio trends
- Top query changes week-over-week
- Autovacuum frequency
- Checkpoint frequency

### Alert Fatigue Prevention

Alert fatigue is the number one enemy of on-call effectiveness. Every false alert reduces trust in the alerting system.

**Rules to prevent alert fatigue:**

1. **Every alert must be actionable.** If the recipient cannot do anything about it, it should not page.

2. **Use multi-window burn rates instead of static thresholds.** Instead of "CPU > 80%", use "CPU error budget consumption rate over the last hour exceeds 14.4x the 30-day burn rate." This catches real problems while ignoring brief spikes.

3. **Require multiple evaluation periods.** Never alarm on a single data point. Use 2-3 evaluation periods minimum.

4. **Separate warning from critical.** Warning goes to Slack. Critical goes to PagerDuty. Never mix them.

5. **Review alerts monthly.** If an alert fired but required no action, adjust or remove it.

### Alert Routing

```
Alert fires
    |
    v
Severity?
    |
    +-- critical --> PagerDuty --> Phone call to on-call DBA
    |                              Response time: < 15 minutes
    |
    +-- warning  --> Slack #db-alerts channel
    |                              Response time: < 4 hours
    |
    +-- info     --> Dashboard annotation
                                   Response time: next business day
```

### Alert Template

Every alert should include:

```
Alert name: [Clear, specific name]
Severity: [critical / warning / info]
Summary: [One sentence describing what is wrong]
Description: [What metric, what value, what threshold]
Impact: [What users experience]
Runbook: [Link to the SURVIVE runbook for this scenario]
Dashboard: [Link to the relevant Grafana dashboard]
```

---

## The Three Pillars in Practice

### Metrics (Prometheus / CloudWatch)

| Use Case | Tool | Example |
|----------|------|---------|
| Real-time dashboard | Grafana + Prometheus | Connection count, TPS, cache ratio |
| Historical analysis | CloudWatch / Prometheus | Compare this week to last week |
| Capacity planning | Prometheus predict_linear | Predict disk full date |
| Alerting | Prometheus Alertmanager | Page when SLO is at risk |

### Logs (CloudWatch Logs / Loki)

| Use Case | Tool | Example |
|----------|------|---------|
| Slow query log | CloudWatch Logs | Find queries > 1 second |
| Error investigation | CloudWatch Logs | Find specific error messages |
| Audit trail | CloudWatch Logs | Who connected when |
| Correlation | Grafana + Loki | Overlay log events on metric dashboards |

### Traces (X-Ray / Jaeger)

| Use Case | Tool | Example |
|----------|------|---------|
| End-to-end latency | X-Ray | See how much time is spent in the database vs application |
| Dependency mapping | X-Ray | Which services connect to which databases |
| Bottleneck identification | X-Ray | Find the slowest component in a request |

For most DBA teams, metrics and logs cover 95% of needs. Traces become important when working closely with application teams on latency investigations.

---

## Observability Maturity Model

| Level | Description | Tools |
|-------|-------------|-------|
| 0 - None | No monitoring. Find out about problems from users. | None |
| 1 - Basic | CloudWatch alarms on CPU, storage, connections | CloudWatch |
| 2 - Informed | PI enabled, dashboards built, on-call process exists | CloudWatch + PI + dashboards |
| 3 - Proactive | SLOs defined, error budgets tracked, automated reports | Prometheus + Grafana + Alertmanager |
| 4 - Predictive | Capacity planning, regression detection, anomaly alerting | Full stack + ML-based anomaly detection |

Most teams should target Level 2 as a minimum and Level 3 as a goal. Level 4 is aspirational and requires significant investment.

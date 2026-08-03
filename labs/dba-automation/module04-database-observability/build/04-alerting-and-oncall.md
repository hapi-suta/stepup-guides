# BUILD 04: Alerting, SLOs, and On-Call for DBAs

**Module 04 - Database Observability**
**Time Estimate:** 75 minutes
**Prerequisites:** Prometheus + postgres_exporter + Grafana running (from BUILD 01-03)

---

## Step 1: Alert Rules in Prometheus

**Analogy:** Alert rules are like CHECK constraints that run continuously. If a PromQL condition evaluates to true for a specified duration, Prometheus fires an alert. Unlike a CHECK constraint that prevents the violation, an alert rule notifies you that the violation has occurred.

There are two types of rules in Prometheus:

**Recording rules** - pre-compute expensive PromQL queries and save the result as a new metric. Like creating a materialized view in PostgreSQL.

**Alerting rules** - evaluate a condition and fire an alert when true. Like a trigger that sends a notification.

---

## Step 2: Write PostgreSQL Alert Rules

**On your Mac, in your terminal:**

```bash
vi ~/lab-prometheus/alert_rules.yml
```

Replace the contents with a comprehensive set of PostgreSQL alert rules:

```yaml
groups:
  - name: postgresql_alerts
    rules:

      # 1. Connection count approaching max_connections
      - alert: PostgreSQLHighConnections
        expr: |
          sum by (instance) (pg_stat_activity_count)
          /
          pg_settings_setting{name="max_connections"}
          * 100 > 80
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "PostgreSQL connections above 80% of max on {{ $labels.instance }}"
          description: "Current connection usage is {{ $value | printf \"%.1f\" }}% of max_connections. Consider increasing max_connections or investigating connection leaks."

      # 2. Replication lag exceeding threshold
      - alert: PostgreSQLReplicationLag
        expr: pg_replication_lag > 30
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "PostgreSQL replication lag > 30s on {{ $labels.instance }}"
          description: "Replication lag is {{ $value | printf \"%.0f\" }} seconds. Check network, WAL sender, and replica load."

      # 3. Cache hit ratio dropping below 95%
      - alert: PostgreSQLLowCacheHitRatio
        expr: |
          (
            sum by (datname) (pg_stat_database_blks_hit)
            /
            (sum by (datname) (pg_stat_database_blks_hit) + sum by (datname) (pg_stat_database_blks_read))
          ) * 100 < 95
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Cache hit ratio below 95% for database {{ $labels.datname }}"
          description: "Current cache hit ratio is {{ $value | printf \"%.1f\" }}%. Consider increasing shared_buffers or investigating query patterns."

      # 4. Long-running queries exceeding 5 minutes
      - alert: PostgreSQLLongRunningQuery
        expr: pg_stat_activity_max_tx_duration > 300
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Long-running transaction > 5 minutes on {{ $labels.instance }}"
          description: "A transaction has been running for {{ $value | printf \"%.0f\" }} seconds. This may block vacuum and hold locks."

      # 5. High dead tuple ratio (vacuum not keeping up)
      - alert: PostgreSQLHighDeadTuples
        expr: |
          pg_stat_user_tables_n_dead_tup
          /
          (pg_stat_user_tables_n_live_tup + pg_stat_user_tables_n_dead_tup)
          * 100 > 10
        for: 30m
        labels:
          severity: warning
        annotations:
          summary: "Table {{ $labels.relname }} has > 10% dead tuples"
          description: "Dead tuple ratio is {{ $value | printf \"%.1f\" }}%. Autovacuum may be falling behind. Check autovacuum settings and long-running transactions."

      # 6. Too many idle in transaction connections
      - alert: PostgreSQLIdleInTransaction
        expr: pg_stat_activity_count{state="idle in transaction"} > 5
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "{{ $value }} idle-in-transaction connections on {{ $labels.instance }}"
          description: "Connections in 'idle in transaction' state hold locks and prevent vacuum. Investigate application connection management."

      # 7. High rollback ratio
      - alert: PostgreSQLHighRollbackRatio
        expr: |
          rate(pg_stat_database_xact_rollback[5m])
          /
          (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))
          * 100 > 5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Rollback ratio > 5% for database {{ $labels.datname }}"
          description: "{{ $value | printf \"%.1f\" }}% of transactions are rolling back. Check application error rates."

      # 8. Deadlocks detected
      - alert: PostgreSQLDeadlocks
        expr: rate(pg_stat_database_deadlocks[5m]) > 0
        for: 1m
        labels:
          severity: warning
        annotations:
          summary: "Deadlocks detected in database {{ $labels.datname }}"
          description: "Deadlock rate: {{ $value | printf \"%.2f\" }}/s. Review application transaction ordering."

  - name: postgresql_recording_rules
    rules:
      # Recording rules - pre-compute expensive queries

      # Cache hit ratio (so we do not recalculate it every time)
      - record: postgresql:cache_hit_ratio
        expr: |
          sum by (datname) (pg_stat_database_blks_hit)
          /
          (sum by (datname) (pg_stat_database_blks_hit) + sum by (datname) (pg_stat_database_blks_read))
          * 100

      # Transaction rate
      - record: postgresql:transactions_per_second
        expr: sum by (datname) (rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))

      # Connection utilization percentage
      - record: postgresql:connection_utilization
        expr: |
          sum by (instance) (pg_stat_activity_count)
          /
          pg_settings_setting{name="max_connections"}
          * 100
```

**What each alert covers:**

| Alert | What It Catches | Why It Matters |
|---|---|---|
| HighConnections | > 80% of max_connections used | Connection exhaustion causes application errors |
| ReplicationLag | Lag > 30 seconds | Replicas serving stale data |
| LowCacheHitRatio | < 95% cache hits | Too many disk reads - slow queries |
| LongRunningQuery | Transaction > 5 minutes | Blocks vacuum, holds locks |
| HighDeadTuples | > 10% dead tuple ratio | Table bloat, slow scans |
| IdleInTransaction | > 5 idle-in-transaction | Lock holder, vacuum blocker |
| HighRollbackRatio | > 5% rollbacks | Application errors |
| Deadlocks | Any deadlocks | Contention problem |

---

## Step 3: Restart Prometheus and Verify Rules

Restart Prometheus to load the new rules:

**On your Mac, in the Prometheus terminal (Ctrl+C to stop, then restart):**

```bash
prometheus --config.file=$HOME/lab-prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/lab-prometheus/data \
  --web.listen-address=":9090"
```

Verify rules loaded:

1. Go to [http://localhost:9090/alerts](http://localhost:9090/alerts)
2. You should see all 8 alert rules listed under `postgresql_alerts`
3. Most should show `inactive` (green) - meaning the conditions are not currently met

Go to [http://localhost:9090/rules](http://localhost:9090/rules) to see both alerting and recording rules.

---

## Step 4: Alertmanager - Routing Alerts

Prometheus detects problems. Alertmanager decides who to notify and how. It handles:

- **Routing:** Send critical alerts to PagerDuty, warnings to Slack
- **Grouping:** Combine related alerts into one notification (avoid getting 100 emails for 100 tables)
- **Silencing:** Temporarily mute alerts during maintenance
- **Inhibition:** If the server is down, suppress all other alerts for that server

**Install Alertmanager:**

**Option A: Docker (recommended - no Homebrew formula exists for Alertmanager)**

```bash
docker run -d \
  --name alertmanager \
  -p 9093:9093 \
  -v ~/lab-prometheus/alertmanager.yml:/etc/alertmanager/alertmanager.yml \
  prom/alertmanager:latest
```

**Option B: Binary download**

```bash
# Download latest release (check https://prometheus.io/download/ for current version)
curl -LO https://github.com/prometheus/alertmanager/releases/download/v0.28.1/alertmanager-0.28.1.darwin-arm64.tar.gz

# Extract and install
tar xzf alertmanager-0.28.1.darwin-arm64.tar.gz
sudo mv alertmanager-0.28.1.darwin-arm64/alertmanager /usr/local/bin/

# Verify
alertmanager --version
```

**Configure Alertmanager:**

```bash
vi ~/lab-prometheus/alertmanager.yml
```

```yaml
global:
  resolve_timeout: 5m

route:
  # Default receiver for all alerts
  receiver: 'email-notifications'

  # Group alerts by these labels (reduces noise)
  group_by: ['alertname', 'instance']

  # Wait 30 seconds before sending a group (collect related alerts)
  group_wait: 30s

  # Wait 5 minutes before sending new alerts for the same group
  group_interval: 5m

  # Wait 4 hours before resending an unresolved alert
  repeat_interval: 4h

  # Route critical alerts differently
  routes:
    - match:
        severity: critical
      receiver: 'critical-alerts'
      repeat_interval: 1h

receivers:
  - name: 'email-notifications'
    email_configs:
      - to: 'your-email@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'your-email@example.com'
        auth_password: 'your-app-password'
        require_tls: true

  - name: 'critical-alerts'
    email_configs:
      - to: 'oncall@example.com'
        from: 'alertmanager@example.com'
        smarthost: 'smtp.gmail.com:587'
        auth_username: 'your-email@example.com'
        auth_password: 'your-app-password'
        require_tls: true
    # Uncomment for Slack integration:
    # slack_configs:
    #   - api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
    #     channel: '#db-alerts'
    #     title: '{{ .GroupLabels.alertname }}'
    #     text: '{{ range .Alerts }}{{ .Annotations.description }}{{ end }}'
```

**Note:** For this lab, you can skip the email configuration and just observe alerts in the Alertmanager web UI.

Start Alertmanager:

```bash
alertmanager --config.file=$HOME/lab-prometheus/alertmanager.yml \
  --storage.path=$HOME/lab-prometheus/alertmanager-data \
  --web.listen-address=":9093"
```

Access the Alertmanager UI at: [http://localhost:9093](http://localhost:9093)

Update Prometheus to send alerts to Alertmanager. Edit `prometheus.yml`:

```bash
vi ~/lab-prometheus/prometheus.yml
```

Add the `alerting` section:

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
        labels:
          instance: "local-postgres"
          environment: "lab"
```

Restart Prometheus to pick up the change.

---

## Step 5: Alert Severity Levels

**Analogy:** This maps directly to incident priority levels you already know from database operations.

| Severity | Response Time | Who Gets Notified | Database Examples |
|---|---|---|---|
| **critical** | Immediate (wake someone up) | On-call DBA via PagerDuty/phone | Server down, replication broken, storage full |
| **warning** | Business hours | Team via Slack/email | High connections, low cache hit ratio, rising dead tuples |
| **info** | Next review cycle | Dashboard only (no notification) | Backup completed, maintenance window starting |

**Guidelines for choosing severity:**

- **Critical:** Data loss risk, service outage, or will escalate to outage within minutes
- **Warning:** Performance degradation or risk that needs attention within hours
- **Info:** Awareness items that do not require action

---

## Step 6: Alert Fatigue - The Real Enemy

**Alert fatigue is worse than having no alerts.** When every alert fires constantly, the on-call DBA stops paying attention. Then when a real critical alert fires, it gets buried in noise.

**Signs of alert fatigue:**
- More than 5 alerts per on-call shift
- Alerts that are acknowledged but never investigated
- Alerts that fire and resolve repeatedly (flapping)
- Alerts with no clear action ("CPU is at 40%" - so what?)

**Rules for healthy alerting:**

| Rule | Why |
|---|---|
| Every alert must have a clear action | If there is nothing to do, it should not be an alert |
| Set `for` duration to filter transients | A 1-second CPU spike is not an alert |
| Use warning vs critical correctly | Do not page someone for a warning |
| Review and prune alerts quarterly | Remove alerts that never fire or always fire |
| Group related alerts | 50 tables with high dead tuples = 1 alert, not 50 |

---

## Step 7: SLIs for Databases

**SLI (Service Level Indicator)** - a measurable metric that defines "healthy."

**Analogy:** You already use these intuitively. When someone asks "is the database healthy?" you check connections, replication lag, and query response time. SLIs formalize this into measurable numbers.

**Key SLIs for PostgreSQL:**

| SLI | How to Measure | What "Good" Looks Like |
|---|---|---|
| **Availability** | Prometheus `up` metric + connection success rate | 99.9% of checks return healthy |
| **Latency** | p95 query execution time from pg_stat_statements | p95 < 100ms for OLTP |
| **Error rate** | Rollback ratio, connection failures | < 0.1% of transactions fail |
| **Throughput** | Transactions per second | Sustained TPS meets expected load |
| **Replication freshness** | Replica lag in seconds | Lag < 5 seconds |

**PromQL for each SLI:**

```promql
# Availability: is the database up?
up{job="postgresql"}

# Latency: average query time (from pg_stat_statements)
pg_stat_statements_top_mean_exec_time

# Error rate: rollback percentage
rate(pg_stat_database_xact_rollback[5m])
/
(rate(pg_stat_database_xact_commit[5m]) + rate(pg_stat_database_xact_rollback[5m]))

# Throughput: transactions per second
sum(rate(pg_stat_database_xact_commit[5m]))

# Replication freshness
pg_replication_lag
```

---

## Step 8: SLOs for Databases

**SLO (Service Level Objective)** - a target percentage for your SLI over a time window.

**DBA analogy:** An SLO is like saying "our database will be available 99.9% of the time over each month." That is your commitment. If you drop below it, you need to take action.

**What 99.9% really means:**

| SLO | Allowed Downtime/Month | Allowed Downtime/Year |
|---|---|---|
| 99% | 7 hours 18 minutes | 3.65 days |
| 99.5% | 3 hours 39 minutes | 1.83 days |
| 99.9% | 43 minutes | 8.76 hours |
| 99.95% | 21 minutes | 4.38 hours |
| 99.99% | 4.3 minutes | 52.6 minutes |

**Example SLOs for a PostgreSQL production database:**

| SLI | SLO Target | Window |
|---|---|---|
| Availability | 99.9% | 30-day rolling |
| Query latency (p95) | < 100ms | 30-day rolling |
| Error rate | < 0.1% | 30-day rolling |
| Replication lag | < 10 seconds 99.5% of the time | 30-day rolling |

---

## Step 9: Error Budgets

**Analogy:** An error budget is like a maintenance window budget. If your SLO is 99.9% availability over 30 days, you have 43 minutes of allowed downtime. That is your error budget.

**How error budgets work:**

```
Error Budget = 100% - SLO Target
             = 100% - 99.9%
             = 0.1%
             = 43.2 minutes per month
```

**Using error budgets in practice:**

- If you have used 0% of your error budget, you can be aggressive with deployments and changes
- If you have used 50%, slow down - be more careful with changes
- If you have used 80%, freeze non-essential changes
- If you have used 100%, stop all changes and focus on reliability

**PromQL to track error budget consumption:**

```promql
# Availability error budget (how many minutes of downtime this month)
# Assuming 30-day window (2592000 seconds)
(1 - avg_over_time(up{job="postgresql"}[30d])) * 2592000 / 60
```

**Error budget meeting (monthly):**

| Item | Detail |
|---|---|
| SLO target | 99.9% (43 min/month budget) |
| Time consumed | 12 minutes (failover + patching) |
| Budget remaining | 31 minutes (72%) |
| Decision | Continue normal change velocity |

---

## Step 10: Practical - Configure All Alert Rules

Let us verify the complete alerting stack is working.

**On your Mac, generate some database activity to trigger alerts:**

Connect to your local PostgreSQL and simulate a long-running transaction:

```bash
psql -U postgres -d postgres
```

```sql
-- Start a transaction and leave it open (simulates idle-in-transaction)
BEGIN;
SELECT pg_sleep(1);
-- Do NOT commit - leave this session open
```

In another terminal, open 5 more idle-in-transaction connections:

```bash
for i in {1..5}; do
  psql -U postgres -d postgres -c "BEGIN; SELECT pg_sleep(1);" &
done
```

Wait 5 minutes for the alert rule `for` duration to elapse, then check:

1. Go to [http://localhost:9090/alerts](http://localhost:9090/alerts)
2. The `PostgreSQLIdleInTransaction` alert should transition from `inactive` to `pending` to `firing`

Check Alertmanager:

1. Go to [http://localhost:9093](http://localhost:9093)
2. You should see the fired alert listed

**Clean up the test connections:**

```sql
-- In each psql session:
ROLLBACK;
\q
```

Or kill all idle-in-transaction connections from a fresh psql session:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND pid != pg_backend_pid();
```

---

## Step 11: On-Call Best Practices for DBAs

| Practice | Details |
|---|---|
| **Runbooks for every alert** | Each alert should link to a step-by-step runbook. "What do I do when this fires?" |
| **Rotation schedule** | 1 week on, at least 1 week off. On-call burnout is real. |
| **Escalation path** | If on-call DBA cannot resolve in 30 minutes, escalate to senior DBA |
| **Post-incident review** | After every critical alert: what happened, why, how to prevent it |
| **Quiet hours** | Only critical alerts page during nights/weekends. Warnings wait until business hours. |
| **Dashboard on phone** | Have your Grafana dashboards accessible from your phone |
| **Test alerts monthly** | Trigger each alert intentionally to verify the notification chain works |

**Alert routing summary:**

```
[Prometheus] --fires alert--> [Alertmanager]
                                    |
                    +---------------+---------------+
                    |               |               |
              [severity=critical] [severity=warning] [severity=info]
                    |               |               |
              PagerDuty/Phone     Slack/Email      Dashboard only
              (wake someone up)   (business hours)  (no notification)
```

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Alert rules | PromQL conditions that fire when true for a specified duration |
| Recording rules | Pre-computed metrics - like materialized views for PromQL |
| Alertmanager | Routes, groups, silences, and inhibits alerts |
| Severity levels | Critical = page immediately, warning = business hours, info = dashboard |
| Alert fatigue | Too many alerts is worse than none - every alert must have a clear action |
| SLIs | Measurable metrics that define "healthy" - availability, latency, error rate |
| SLOs | Target percentages for SLIs - like "99.9% available per month" |
| Error budgets | How much downtime you can "spend" before freezing changes |
| On-call practices | Runbooks, rotation, escalation, post-incident review |
| Practical alerting | 8 PostgreSQL-specific alert rules covering connections, replication, cache, bloat |

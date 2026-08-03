# BUILD 01: Prometheus Fundamentals for DBAs

**Module 04 - Database Observability**
**Time Estimate:** 75 minutes
**Prerequisites:** PostgreSQL running locally, Homebrew or Docker installed on Mac

---

## Step 1: Understand What Prometheus Is

**Analogy:** You already use `pg_stat_statements` to collect query performance data and `pg_stat_activity` to see what is happening right now. Prometheus does the same thing but for EVERYTHING - your database, your servers, your application, your Kubernetes cluster, your network. It collects numeric measurements (metrics) from all your systems and stores them in a time-series database.

**Key concepts mapped to DBA knowledge:**

| Prometheus Concept | DBA Equivalent |
|---|---|
| Metric | A row in `pg_stat_user_tables` (like `seq_scan` or `n_dead_tup`) |
| Target | A system being monitored (like one of your PostgreSQL servers) |
| Scrape | Prometheus reading metrics from a target (like querying `pg_stat_activity`) |
| PromQL | SQL for metrics (instead of querying tables, you query time-series data) |
| Alert rule | A CHECK constraint that fires a notification when violated |
| Label | A WHERE clause dimension (like database name, table name, instance) |

**Why Prometheus instead of just CloudWatch or pgAdmin?**

- Open source - no vendor lock-in
- Unified monitoring across all systems (not just databases)
- Powerful query language (PromQL) for custom dashboards
- Industry standard - most tools and exporters support it
- Alerting built in
- Works on-prem and in the cloud

---

## Step 2: Pull Model vs Push Model

Prometheus uses a **pull model**. This is counterintuitive if you are used to systems that push data to a central server.

**Push model** (like StatsD, CloudWatch Agent): Each monitored system sends its metrics to the central server.

```
[Server A] --sends metrics--> [Central Server]
[Server B] --sends metrics--> [Central Server]
[Server C] --sends metrics--> [Central Server]
```

**Pull model** (Prometheus): The central server reaches out and collects metrics from each system.

```
[Prometheus] --scrapes--> [Server A /metrics endpoint]
[Prometheus] --scrapes--> [Server B /metrics endpoint]
[Prometheus] --scrapes--> [Server C /metrics endpoint]
```

**DBA analogy:** The pull model is like polling `pg_stat_activity` every 15 seconds. You (Prometheus) decide when to check. With push, it would be like every query sending you a notification when it finishes - that is noisier and harder to control.

**Advantages of pull:**

- Prometheus controls the scrape interval (you decide how often to check)
- If a target goes down, Prometheus knows immediately (scrape fails)
- Easier to debug - you can manually hit the `/metrics` endpoint in a browser
- Targets do not need to know where Prometheus is

---

## Step 3: Install Prometheus on Mac

**On your Mac, in your terminal:**

**Option A: Homebrew (recommended for learning)**

```bash
brew install prometheus
```

Verify the installation:

```bash
prometheus --version
```

Expected output (yours will differ):
```
prometheus, version 3.x.x (branch: HEAD, revision: ...)
  build user:       ...
  build date:       ...
  go version:       ...
  platform:         darwin/arm64
```

**Note:** Prometheus 3.x is current as of 2026. If you see version 2.x, that is fine - all commands in this lab work with both versions.

**Option B: Docker**

```bash
docker pull prom/prometheus:latest
```

We will use the Homebrew installation for this guide. The Docker setup is in the concepts reference.

---

## Step 4: Prometheus Configuration - prometheus.yml

Prometheus reads its configuration from a YAML file. This file defines what to scrape and how often.

**On your Mac, in your terminal:**

Create a working directory:

```bash
mkdir -p ~/lab-prometheus
```

Create the configuration file:

```bash
vi ~/lab-prometheus/prometheus.yml
```

Add this content:

```yaml
# Global settings apply to all scrape targets
global:
  scrape_interval: 15s      # How often to scrape targets (like polling pg_stat_activity every 15s)
  evaluation_interval: 15s   # How often to evaluate alert rules
  scrape_timeout: 10s        # Timeout for each scrape request

# Scrape configurations - each job defines a group of targets
scrape_configs:
  # Prometheus monitors itself (yes, it exports its own metrics)
  - job_name: "prometheus"
    static_configs:
      - targets: ["localhost:9090"]
```

**What each setting means:**

| Setting | What It Does | DBA Analogy |
|---|---|---|
| `scrape_interval: 15s` | Collect metrics every 15 seconds | Like a cron job that runs `SELECT * FROM pg_stat_activity` every 15s |
| `evaluation_interval: 15s` | Check alert rules every 15 seconds | Like pg_cron checking your monitoring queries |
| `job_name` | A label for a group of targets | Like naming your replication cluster |
| `targets` | List of host:port to scrape | Like your list of servers in your monitoring tool |

---

## Step 5: Start Prometheus

**On your Mac, in your terminal:**

```bash
prometheus --config.file=$HOME/lab-prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/lab-prometheus/data \
  --web.listen-address=":9090"
```

Expected output (yours will differ):
```
ts=2026-06-09T15:00:00.000Z caller=main.go:535 level=info msg="Starting Prometheus"
ts=2026-06-09T15:00:00.000Z caller=main.go:540 level=info version=2.53.0
ts=2026-06-09T15:00:00.100Z caller=main.go:876 level=info msg="Server is ready to receive web requests."
```

Leave this terminal running. Open a new terminal for the next steps.

**Access the Prometheus web UI:**

Open your browser and go to: [http://localhost:9090](http://localhost:9090)

You should see the Prometheus expression browser. This is where you will run PromQL queries - the "psql" of the metrics world.

**Verify Prometheus is scraping itself:**

1. Click **Status** in the top menu
2. Click **Targets**
3. You should see one target: `prometheus (1/1 up)`

The `(1/1 up)` means Prometheus is successfully scraping itself. If it says `(0/1 down)`, something is wrong with the configuration.

---

## Step 6: PromQL Basics - SQL for Metrics

PromQL is how you query metrics in Prometheus. If you know SQL, you can learn PromQL quickly.

**In the Prometheus web UI (http://localhost:9090):**

Type these queries in the expression box and click **Execute**:

### Instant Vectors (like SELECT current value)

```promql
up
```

This returns the current value of the `up` metric for all targets. A value of `1` means the target is reachable. `0` means it is down.

**DBA analogy:** This is like `SELECT * FROM pg_stat_replication` to check if your replicas are connected.

```promql
prometheus_tsdb_head_series
```

This returns how many time series Prometheus is tracking. Think of each time series as a row in a metrics table.

### Range Vectors (like SELECT over a time window)

```promql
prometheus_http_requests_total[5m]
```

This returns all values of `prometheus_http_requests_total` over the last 5 minutes. The `[5m]` is the range selector.

**DBA analogy:** `SELECT * FROM pg_stat_activity WHERE query_start > now() - interval '5 minutes'`

### rate() - Per-Second Rates from Counters

```promql
rate(prometheus_http_requests_total[5m])
```

The `rate()` function calculates the per-second rate of increase over the time window. This is critical because most metrics are counters (always increasing), and you want to know the rate of change, not the absolute value.

**DBA analogy:** If `pg_stat_statements.calls` is 50,000 at 10:00 and 55,000 at 10:05, the rate is 1,000 calls / 300 seconds = 3.33 queries per second. `rate()` does this math for you.

### Aggregate Functions

```promql
sum(rate(prometheus_http_requests_total[5m]))
```

**DBA analogy:** `SELECT SUM(rate) FROM ...` - aggregate across all labels.

```promql
avg(prometheus_http_requests_total)
```

Other aggregations: `sum`, `avg`, `max`, `min`, `count`, `stddev` - same as SQL aggregate functions.

### Filtering with Labels (like WHERE clauses)

```promql
prometheus_http_requests_total{handler="/api/v1/query"}
```

The curly braces `{}` filter by label values. This is equivalent to a WHERE clause.

```promql
prometheus_http_requests_total{handler=~"/api/.*"}
```

The `=~` operator uses regular expressions. This matches any handler starting with `/api/`.

**DBA analogy:**
- `{handler="/api/v1/query"}` is like `WHERE handler = '/api/v1/query'`
- `{handler=~"/api/.*"}` is like `WHERE handler LIKE '/api/%'`
- `{handler!=""}` is like `WHERE handler IS NOT NULL AND handler != ''`

---

## Step 7: Metric Types

Prometheus has four metric types. Understanding them is critical for writing correct queries.

### Counter

**What:** A value that only goes up (and resets to 0 on restart).
**Examples:** Total requests served, total errors, total bytes sent.
**DBA analogy:** `pg_stat_statements.calls` - it only increases. You care about the rate of change, not the absolute value.
**How to query:** Always use `rate()` or `increase()` on counters.

```promql
# CORRECT: per-second rate of HTTP requests
rate(prometheus_http_requests_total[5m])

# WRONG: raw counter value (meaningless - just keeps going up)
prometheus_http_requests_total
```

### Gauge

**What:** A value that goes up and down.
**Examples:** Current temperature, current connection count, memory usage.
**DBA analogy:** `pg_stat_activity` connection count - it goes up when connections open and down when they close.
**How to query:** Use the raw value directly. `rate()` does not make sense on gauges.

```promql
# CORRECT: current value
process_resident_memory_bytes

# Also useful: change over time
delta(process_resident_memory_bytes[1h])
```

### Histogram

**What:** Samples observations and counts them in configurable buckets.
**Examples:** Request durations, response sizes.
**DBA analogy:** Like `pg_stat_statements` buckets - "how many queries took 0-1ms, 1-10ms, 10-100ms, etc."
**How to query:** Use `histogram_quantile()` for percentiles.

```promql
# 95th percentile of HTTP request duration
histogram_quantile(0.95, rate(prometheus_http_request_duration_seconds_bucket[5m]))
```

### Summary

**What:** Similar to histogram but calculates quantiles on the client side.
**DBA analogy:** Pre-calculated percentiles (like pg_stat_statements.mean_exec_time).
**When to use:** When you need precise quantiles and the client can calculate them. Histograms are more flexible and generally preferred.

---

## Step 8: Labels - The WHERE Clause Dimensions

Every metric in Prometheus has labels that provide dimensions. Labels are key-value pairs attached to each metric.

**Example metric with labels:**

```
postgresql_connections{datname="production", state="active", instance="db1:9187"} 42
postgresql_connections{datname="production", state="idle", instance="db1:9187"} 15
postgresql_connections{datname="staging", state="active", instance="db2:9187"} 3
```

**DBA analogy:** This is like having a `pg_stat_activity` view where `datname`, `state`, and `instance` are columns you can filter on with WHERE clauses.

**Query examples:**

```promql
# All connections on production database
postgresql_connections{datname="production"}

# Only active connections
postgresql_connections{state="active"}

# Active connections on production
postgresql_connections{datname="production", state="active"}

# Total active connections across all databases
sum(postgresql_connections{state="active"})

# Connections grouped by database
sum by (datname) (postgresql_connections)
```

**`sum by (label)` is like GROUP BY:**

```promql
# DBA analogy: SELECT datname, SUM(connections) FROM ... GROUP BY datname
sum by (datname) (postgresql_connections)
```

---

## Step 9: Alert Rules in Prometheus

**Analogy:** Alert rules are like CHECK constraints that run on a schedule. If the condition is true for a specified duration, Prometheus fires an alert.

Alert rules are defined in a separate YAML file. Let us create one.

**On your Mac, in a new terminal:**

```bash
vi ~/lab-prometheus/alert_rules.yml
```

Add this content:

```yaml
groups:
  - name: prometheus_self_monitoring
    rules:
      # Alert if Prometheus itself is down
      - alert: PrometheusTargetDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Target {{ $labels.instance }} is down"
          description: "{{ $labels.job }} target {{ $labels.instance }} has been down for more than 1 minute."

      # Alert if Prometheus is using too much memory
      - alert: PrometheusHighMemory
        expr: process_resident_memory_bytes > 1e9
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "Prometheus using more than 1 GB RAM"
          description: "Current memory usage: {{ $value | humanize1024 }}B"
```

**What each field means:**

| Field | Purpose | DBA Analogy |
|---|---|---|
| `alert` | Name of the alert | Like naming a monitoring check |
| `expr` | PromQL expression that triggers the alert | The CHECK constraint condition |
| `for` | How long the condition must be true before firing | Like a "must fail N consecutive checks" threshold |
| `labels.severity` | Categorize the alert priority | P1/P2/P3 classification |
| `annotations` | Human-readable description | The alert message body |

Now update prometheus.yml to load the alert rules:

```bash
vi ~/lab-prometheus/prometheus.yml
```

Add the `rule_files` section:

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
```

Restart Prometheus (Ctrl+C in the Prometheus terminal, then start it again):

```bash
prometheus --config.file=$HOME/lab-prometheus/prometheus.yml \
  --storage.tsdb.path=$HOME/lab-prometheus/data \
  --web.listen-address=":9090"
```

Verify alert rules loaded:

1. Go to [http://localhost:9090/alerts](http://localhost:9090/alerts)
2. You should see your two alert rules listed
3. Both should show `0 active` (nothing is triggering them)

---

## Step 10: Explore the Prometheus Web UI

Take a few minutes to explore the key pages:

**1. Graph page** (http://localhost:9090/graph)
- This is where you write PromQL queries
- The "Table" tab shows current values
- The "Graph" tab shows values over time
- Try: `rate(prometheus_http_requests_total[5m])` and click the Graph tab

**2. Targets page** (http://localhost:9090/targets)
- Shows all configured scrape targets and their status
- Green "UP" means healthy
- Red "DOWN" means unreachable

**3. Alerts page** (http://localhost:9090/alerts)
- Shows all configured alert rules
- States: inactive (green), pending (yellow), firing (red)

**4. Configuration page** (http://localhost:9090/config)
- Shows the current prometheus.yml configuration
- Useful for verifying your config loaded correctly

**5. Status pages** (http://localhost:9090/status)
- Runtime info, build info, TSDB stats
- TSDB stats shows storage usage and series count

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Prometheus purpose | Collects numeric metrics from all systems - like pg_stat views for everything |
| Pull model | Prometheus scrapes targets on a schedule - like polling pg_stat_activity |
| prometheus.yml | Configuration file defining scrape targets and intervals |
| PromQL | SQL for metrics - instant vectors, range vectors, rate(), aggregations |
| Metric types | Counter (use rate()), gauge (use raw value), histogram (use quantile()), summary |
| Labels | Dimensions on metrics - filter with {} like WHERE clauses |
| rate() | Calculates per-second change from cumulative counters |
| sum by (label) | Aggregation equivalent to GROUP BY |
| Alert rules | PromQL expressions that fire notifications when true for a duration |
| Web UI | Graph for queries, Targets for health, Alerts for alert status |

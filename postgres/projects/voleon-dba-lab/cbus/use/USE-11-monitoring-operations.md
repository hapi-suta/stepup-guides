# USE Exercise 11: Monitoring Operations

| | |
|---|---|
| **Time** | 110 minutes total (five exercises) |
| **Servers** | pg-ops (34.228.32.17), pg-primary (100.26.54.122), pg-replica (54.144.241.128), pg-container (34.228.73.232) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |
| **Interview prep** | Ed Byrne - Senior Systems Infrastructure Engineer, The Voleon Group |

## What You'll Practice

- Querying live metrics with PromQL through the Prometheus HTTP API
- Writing custom alert rules from scratch and validating them with promtool
- Building a Grafana dashboard via the API (no clicking in the UI)
- Managing maintenance silences and alert lifecycle in Alertmanager
- Running a full incident response drill from failure to resolution

## Prerequisites

- Completed BUILD-08 (Prometheus/Grafana) and BUILD-13 (Alertmanager)
- Prometheus running on pg-ops:9090
- Grafana running on pg-ops:3000
- Alertmanager running on pg-ops:9093
- postgres_exporter on pg-primary:9187 and pg-replica:9187
- node_exporter on all four nodes:9100

---

## Exercise 1: PromQL Diagnostic Challenge (20 minutes)

**Scenario:** Users report slow queries on quantdb. Your job is to use Prometheus to diagnose the bottleneck. You will run 10 PromQL queries one at a time through the Prometheus HTTP API and interpret each result.

### Step 1.1: Connect to pg-ops

SSH into pg-ops. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.228.32.17
```

All queries in this exercise run on **pg-ops**, as **ec2-user**.

### Step 1.2: Query 1 - Active Connection Count

Check how many connections are open on quantdb right now.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_stat_activity_count{datname="quantdb", state="active"}' \
  | python3 -m json.tool
```

The `--data-urlencode` flag URL-encodes the query string so special characters like `{` and `"` are transmitted correctly. The result is a JSON object with a `result` array.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": {
                    "datname": "quantdb",
                    "instance": "172.31.19.86:9187",
                    "state": "active"
                },
                "value": [ 1750200000, "3" ]
            }
        ]
    }
}
```

The second element of `"value"` is the count. If you see more than 20, connections are piling up. If you see 0, no active queries are running right now.

### Step 1.3: Query 2 - Idle in Transaction Count

Connections stuck in `idle in transaction` state are a red flag. They hold locks and prevent autovacuum.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_stat_activity_count{datname="quantdb", state="idle in transaction"}' \
  | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "datname": "quantdb", "state": "idle in transaction" },
                "value": [ 1750200000, "0" ]
            }
        ]
    }
}
```

A value of `0` is healthy. If you see `5` or more, the application is not committing transactions promptly.

### Step 1.4: Query 3 - Transaction Rate (commits per second)

Check how fast quantdb is processing work.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(pg_stat_database_xact_commit{datname="quantdb"}[5m])' \
  | python3 -m json.tool
```

`rate()` calculates the per-second increase of a counter over a 5-minute window. This is the commit rate in transactions per second (TPS).

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750200000, "12.4" ]
            }
        ]
    }
}
```

### Step 1.5: Query 4 - Rollback Rate

A high rollback rate means the application is encountering errors.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(pg_stat_database_xact_rollback{datname="quantdb"}[5m])' \
  | python3 -m json.tool
```

If rollbacks are more than 5% of total transactions, investigate application errors.

### Step 1.6: Query 5 - Cache Hit Ratio

A cache hit ratio below 95% means too many queries are hitting disk instead of shared_buffers.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_stat_database_blks_hit{datname="quantdb"} / (pg_stat_database_blks_hit{datname="quantdb"} + pg_stat_database_blks_read{datname="quantdb"}) * 100' \
  | python3 -m json.tool
```

`blks_hit` are reads from shared_buffers (fast). `blks_read` are reads from disk (slow). Dividing hit by total and multiplying by 100 gives the cache hit percentage.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "datname": "quantdb", "instance": "172.31.19.86:9187" },
                "value": [ 1750200000, "98.7" ]
            }
        ]
    }
}
```

A value of `98.7` means 98.7% of block reads were served from cache. Anything below 95 is a concern.

### Step 1.7: Query 6 - Replication Lag

Check if the replica is falling behind. A lagging replica means failover is unsafe.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_replication_lag' \
  | python3 -m json.tool
```

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "instance": "172.31.22.69:9187" },
                "value": [ 1750200000, "0.05" ]
            }
        ]
    }
}
```

A value of `0.05` means the replica is 50 milliseconds behind. If you see values above 30 seconds, replication is struggling.

### Step 1.8: Query 7 - CPU Usage on pg-primary

Check CPU pressure on the database server.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle", instance="172.31.19.86:9100"}[5m])) * 100)' \
  | python3 -m json.tool
```

This subtracts idle CPU percentage from 100 to get used CPU percentage. The `avg by (instance)` averages across all CPU cores on the server.

Expected output (yours will differ):

```json
{
    "status": "success",
    "data": {
        "resultType": "vector",
        "result": [
            {
                "metric": { "instance": "172.31.19.86:9100" },
                "value": [ 1750200000, "23.5" ]
            }
        ]
    }
}
```

A value of `23.5` means pg-primary is using 23.5% of CPU. Above 80% is high load.

### Step 1.9: Query 8 - Disk Reads on pg-primary

High disk read I/O during slow queries means data is not in cache.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(node_disk_reads_completed_total{instance="172.31.19.86:9100"}[5m])' \
  | python3 -m json.tool
```

This gives disk read operations per second. During a slow query storm, this number spikes.

### Step 1.10: Query 9 - Longest Running Transaction

Check if any query has been running unusually long.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_stat_activity_max_tx_duration{datname="quantdb"}' \
  | python3 -m json.tool
```

The value is in seconds. If this shows `300` or more, a query has been running for 5 minutes or longer.

### Step 1.11: Query 10 - WAL Generation Rate

High WAL generation means a lot of writes are happening, which can cause replication lag.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=rate(pg_wal_stat_wal_bytes[5m])' \
  | python3 -m json.tool
```

The value is in bytes per second. If you see more than 50 million (50MB/s), WAL generation is high.

### Step 1.12: Interpret Your Results

Review all 10 query results and fill in this table:

| Metric | Your Value | Status |
|--------|-----------|--------|
| Active connections | | Green < 20, Red > 50 |
| Idle in transaction | | Green = 0, Red > 5 |
| Commit rate (TPS) | | Depends on baseline |
| Rollback rate | | Green < 1%, Red > 5% |
| Cache hit ratio | | Green > 98%, Red < 95% |
| Replication lag | | Green < 1s, Red > 30s |
| CPU usage % | | Green < 60%, Red > 80% |
| Disk reads/s | | Compare to baseline |
| Max transaction duration | | Green < 30s, Red > 300s |
| WAL bytes/s | | Green < 10MB/s, Red > 50MB/s |

If one metric is red, that is your bottleneck. Start there.

---

## Exercise 2: Alert Rule Development (25 minutes)

**Scenario:** Your current alert_rules.yml covers basic health checks but is missing rules for cache hit ratio, long-running queries, WAL generation, replication slot lag, and stale backups. Write these 5 rules from scratch, validate them, and load them into Prometheus.

### Step 2.1: Review Existing Rules

On **pg-ops**, as **ec2-user**:

```bash
cat /opt/prometheus/alert_rules.yml
```

Study the format. Each rule has these fields:
- `alert` - the alert name (no spaces, PascalCase is conventional)
- `expr` - the PromQL expression. When this evaluates to a non-empty result, the alert fires.
- `for` - how long the condition must be true before the alert transitions from `pending` to `firing`
- `labels` - key-value pairs attached to the alert (commonly `severity: warning` or `severity: critical`)
- `annotations` - human-readable text for the notification (summary and description)

### Step 2.2: Write the Five New Alert Rules

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/custom_alerts.yml
```

Press `i` to enter insert mode. Type the following exactly:

```yaml
groups:
  - name: custom_pg_alerts
    interval: 1m
    rules:

      # Rule 1: Cache hit ratio below 95%
      - alert: CacheHitRatioLow
        expr: >
          pg_stat_database_blks_hit{datname="quantdb"}
          / (
            pg_stat_database_blks_hit{datname="quantdb"}
            + pg_stat_database_blks_read{datname="quantdb"}
          ) * 100 < 95
        for: 5m
        labels:
          severity: warning
          database: quantdb
        annotations:
          summary: "Cache hit ratio low on {{ $labels.instance }}"
          description: >
            Cache hit ratio for quantdb is {{ $value | printf "%.1f" }}%.
            This means queries are hitting disk instead of shared_buffers.
            Consider increasing shared_buffers or adding indexes.
          runbook: "Check pg_statio_user_tables for tables with high heap_blks_read."

      # Rule 2: Long-running active queries (over 5 minutes)
      - alert: LongRunningQueries
        expr: pg_stat_activity_max_tx_duration{datname="quantdb", state="active"} > 300
        for: 1m
        labels:
          severity: warning
          database: quantdb
        annotations:
          summary: "Long-running query on {{ $labels.instance }}"
          description: >
            A query on quantdb has been running for {{ $value | printf "%.0f" }} seconds
            (threshold is 300 seconds / 5 minutes).
            Long queries block autovacuum and hold locks.
          runbook: "Run SELECT pid, query, now() - pg_stat_activity.query_start AS duration FROM pg_stat_activity WHERE state = 'active' AND datname = 'quantdb' ORDER BY duration DESC;"

      # Rule 3: WAL generation rate above 50MB/s
      - alert: WALGenerationHigh
        expr: rate(pg_wal_stat_wal_bytes[5m]) > 52428800
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High WAL generation on {{ $labels.instance }}"
          description: >
            WAL is being generated at {{ $value | humanize }}B/s.
            Threshold is 50MB/s (52428800 bytes/s).
            This can cause replication lag and WAL disk pressure.
          runbook: "Check pg_stat_statements for high-write queries. Check for bulk loads or mass updates."

      # Rule 4: Inactive replication slots
      - alert: ReplicationSlotInactive
        expr: pg_replication_slots_active == 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Inactive replication slot on {{ $labels.instance }}"
          description: >
            Replication slot {{ $labels.slot_name }} is inactive.
            An inactive slot prevents WAL recycling. The pg_wal directory will grow
            until the slot is consumed or dropped.
          runbook: "Run SELECT slot_name, active, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal FROM pg_replication_slots WHERE NOT active;"

      # Rule 5: Backup staleness - using pg_stat_archiver last archived time as a proxy
      # If archiver has stopped or failed, archive_count stops incrementing.
      - alert: BackupStale
        expr: >
          time() - pg_stat_archiver_last_archived_time > 86400
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "WAL archiving has stalled on {{ $labels.instance }}"
          description: >
            The last successful WAL archive was more than 24 hours ago
            ({{ $value | humanizeDuration }} ago).
            This likely means pgbackrest archiving is failing.
            Backups may be incomplete and PITR may be unavailable.
          runbook: "Run SELECT last_archived_wal, last_archived_time, last_failed_wal, last_failed_time FROM pg_stat_archiver; then check /opt/pgsql/log/ for archiver errors."
```

Press `Esc`, then type `:wq` and press `Enter` to save.

### Step 2.3: Validate the Rules Before Loading

Never load alert rules without validating them first. A YAML syntax error will prevent Prometheus from reloading.

On **pg-ops**, as **ec2-user**:

```bash
/opt/prometheus/promtool check rules /tmp/custom_alerts.yml
```

`promtool` is shipped with every Prometheus release. The `check rules` subcommand validates YAML structure and PromQL expression syntax. It does not check whether the metric names actually exist in your Prometheus database.

Expected output (yours will differ):

```
Checking /tmp/custom_alerts.yml
  SUCCESS: 5 rules found
```

If you see `SUCCESS: 5 rules found`, all rules are syntactically valid. If you see an error like `yaml: line 12: did not find expected key`, fix the indentation at that line and re-validate.

### Step 2.4: Copy the Rules File into Place

On **pg-ops**, as **ec2-user**:

```bash
sudo cp /tmp/custom_alerts.yml /opt/prometheus/custom_alert_rules.yml
```

```bash
sudo chown ec2-user:ec2-user /opt/prometheus/custom_alert_rules.yml
```

### Step 2.5: Add the File to prometheus.yml

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /opt/prometheus/prometheus.yml
```

Find the `rule_files:` section. Press `i` to enter insert mode. Add the new file below any existing entries:

```yaml
rule_files:
  - "alert_rules.yml"
  - "custom_alert_rules.yml"
```

Press `Esc`, then type `:wq` and press `Enter` to save.

Validate the full Prometheus config before reloading:

```bash
/opt/prometheus/promtool check config /opt/prometheus/prometheus.yml
```

Expected output (yours will differ):

```
Checking /opt/prometheus/prometheus.yml
  SUCCESS: 2 rule files found
 SUCCESS: /opt/prometheus/alert_rules.yml
 SUCCESS: /opt/prometheus/custom_alert_rules.yml
```

### Step 2.6: Reload Prometheus

On **pg-ops**, as **ec2-user**:

```bash
sudo systemctl reload prometheus
```

`systemctl reload` sends a SIGHUP signal to Prometheus. Prometheus re-reads its config and rule files without restarting, so there is no gap in metric collection.

Wait 5 seconds for the reload to complete, then verify the rules are loaded:

```bash
curl -s http://localhost:9090/api/v1/rules | python3 -m json.tool | grep -E '"name"' | head -20
```

Expected output (yours will differ):

```json
            "name": "CacheHitRatioLow",
            "name": "LongRunningQueries",
            "name": "WALGenerationHigh",
            "name": "ReplicationSlotInactive",
            "name": "BackupStale",
```

All five rule names should appear.

### Step 2.7: Verify in the Prometheus UI

Open your browser and go to:

```
http://34.228.32.17:9090/alerts
```

You should see your five new alert rules listed. Rules that have never fired will show as `0 active`. Rules whose conditions are currently true will show as `pending` or `firing`.

If `ReplicationSlotInactive` is firing, check if you have any replication slots and whether they are active:

```bash
curl -s http://localhost:9090/api/v1/query \
  --data-urlencode 'query=pg_replication_slots_active' \
  | python3 -m json.tool
```

---

## Exercise 3: Grafana Dashboard Build (30 minutes)

**Scenario:** Ed asks: "Build me a DBA operations dashboard." Instead of clicking through the UI, you will use the Grafana HTTP API to create it programmatically. This is the production way - dashboards as code, not hand-crafted in a browser.

### Step 3.1: Get the Prometheus Data Source UID

Before building the dashboard, you need the UID of the Prometheus data source that Grafana knows about.

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:3000/api/datasources \
  -u admin:admin \
  | python3 -m json.tool
```

Expected output (yours will differ):

```json
[
    {
        "id": 1,
        "uid": "prometheus",
        "name": "Prometheus",
        "type": "prometheus",
        "url": "http://localhost:9090",
        ...
    }
]
```

Note the `"uid"` value. It is often `"prometheus"` if you followed BUILD-08. You will use this UID in the dashboard JSON below. If your UID is different (e.g., `"abc123xyz"`), replace `"prometheus"` with your actual UID throughout the JSON below.

### Step 3.2: Create the Dashboard JSON File

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/dba-ops-dashboard.json
```

Press `i` to enter insert mode and type the following. This creates a six-panel dashboard with a template variable for instance selection.

```json
{
  "dashboard": {
    "title": "DBA Operations",
    "tags": ["postgresql", "dba", "voleon"],
    "timezone": "browser",
    "refresh": "30s",
    "time": {
      "from": "now-1h",
      "to": "now"
    },
    "templating": {
      "list": [
        {
          "name": "instance",
          "label": "PG Instance",
          "type": "query",
          "datasource": { "type": "prometheus", "uid": "prometheus" },
          "query": "label_values(pg_up, instance)",
          "refresh": 2,
          "multi": false,
          "includeAll": true,
          "allValue": ".*"
        }
      ]
    },
    "panels": [
      {
        "id": 1,
        "title": "Active Connections",
        "type": "stat",
        "gridPos": { "h": 4, "w": 6, "x": 0, "y": 0 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "sum(pg_stat_activity_count{datname=\"quantdb\", state=\"active\", instance=~\"$instance\"})",
            "legendFormat": "Active",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "short",
            "color": { "mode": "thresholds" },
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 20 },
                { "color": "red", "value": 50 }
              ]
            }
          }
        },
        "options": { "reduceOptions": { "calcs": ["lastNotNull"] }, "orientation": "auto", "textMode": "auto", "colorMode": "background" }
      },
      {
        "id": 2,
        "title": "Transaction Rate (commits/s and rollbacks/s)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 18, "x": 6, "y": 0 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "rate(pg_stat_database_xact_commit{datname=\"quantdb\", instance=~\"$instance\"}[5m])",
            "legendFormat": "Commits/s - {{instance}}",
            "refId": "A"
          },
          {
            "expr": "rate(pg_stat_database_xact_rollback{datname=\"quantdb\", instance=~\"$instance\"}[5m])",
            "legendFormat": "Rollbacks/s - {{instance}}",
            "refId": "B"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "ops",
            "custom": { "lineInterpolation": "smooth" }
          }
        }
      },
      {
        "id": 3,
        "title": "Cache Hit Ratio",
        "type": "gauge",
        "gridPos": { "h": 4, "w": 6, "x": 0, "y": 4 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "pg_stat_database_blks_hit{datname=\"quantdb\", instance=~\"$instance\"} / (pg_stat_database_blks_hit{datname=\"quantdb\", instance=~\"$instance\"} + pg_stat_database_blks_read{datname=\"quantdb\", instance=~\"$instance\"}) * 100",
            "legendFormat": "{{instance}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "color": { "mode": "thresholds" },
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "red", "value": null },
                { "color": "yellow", "value": 90 },
                { "color": "green", "value": 95 }
              ]
            }
          }
        },
        "options": { "reduceOptions": { "calcs": ["lastNotNull"] } }
      },
      {
        "id": 4,
        "title": "Replication Lag (bytes behind primary)",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 12, "x": 0, "y": 8 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "pg_replication_lag",
            "legendFormat": "Lag (seconds) - {{instance}}",
            "refId": "A"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "s",
            "custom": { "lineInterpolation": "smooth" },
            "thresholds": {
              "mode": "absolute",
              "steps": [
                { "color": "green", "value": null },
                { "color": "yellow", "value": 5 },
                { "color": "red", "value": 30 }
              ]
            }
          }
        }
      },
      {
        "id": 5,
        "title": "Top Databases by Size",
        "type": "table",
        "gridPos": { "h": 8, "w": 12, "x": 12, "y": 8 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "topk(10, pg_database_size_bytes{instance=~\"$instance\"})",
            "legendFormat": "{{datname}}",
            "refId": "A",
            "instant": true
          }
        ],
        "fieldConfig": {
          "defaults": { "unit": "bytes" },
          "overrides": [
            {
              "matcher": { "id": "byName", "options": "Value" },
              "properties": [{ "id": "displayName", "value": "Size" }]
            }
          ]
        },
        "options": { "sortBy": [{ "displayName": "Size", "desc": true }] }
      },
      {
        "id": 6,
        "title": "CPU and Memory",
        "type": "timeseries",
        "gridPos": { "h": 8, "w": 24, "x": 0, "y": 16 },
        "datasource": { "type": "prometheus", "uid": "prometheus" },
        "targets": [
          {
            "expr": "100 - (avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\", instance=~\"172.31.19.86:9100|172.31.22.69:9100\"}[5m])) * 100)",
            "legendFormat": "CPU % - {{instance}}",
            "refId": "A"
          },
          {
            "expr": "100 - (node_memory_MemAvailable_bytes{instance=~\"172.31.19.86:9100|172.31.22.69:9100\"} / node_memory_MemTotal_bytes{instance=~\"172.31.19.86:9100|172.31.22.69:9100\"} * 100)",
            "legendFormat": "Memory % - {{instance}}",
            "refId": "B"
          }
        ],
        "fieldConfig": {
          "defaults": {
            "unit": "percent",
            "min": 0,
            "max": 100,
            "custom": { "lineInterpolation": "smooth" }
          }
        }
      }
    ]
  },
  "overwrite": true,
  "folderId": 0
}
```

Press `Esc`, then type `:wq` and press `Enter` to save.

### Step 3.3: Push the Dashboard via the API

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -u admin:admin \
  -d @/tmp/dba-ops-dashboard.json \
  | python3 -m json.tool
```

`-X POST` specifies the HTTP method. `-H "Content-Type: application/json"` tells Grafana the body is JSON. `-u admin:admin` is basic authentication. `-d @/tmp/...` reads the request body from the file.

Expected output (yours will differ):

```json
{
    "id": 3,
    "uid": "dba-ops-xyz123",
    "url": "/d/dba-ops-xyz123/dba-operations",
    "status": "success",
    "version": 1,
    "slug": "dba-operations"
}
```

If `"status": "success"` appears, the dashboard was created.

### Step 3.4: Open the Dashboard in Your Browser

Open your browser and go to:

```
http://34.228.32.17:3000
```

Log in with `admin` / `admin`. Click **Dashboards** in the left sidebar, then find and click **DBA Operations**.

You should see six panels:

1. **Active Connections** (stat) - a single large number, color-coded green/yellow/red
2. **Transaction Rate** (timeseries) - two lines: commit rate and rollback rate
3. **Cache Hit Ratio** (gauge) - green above 95%, yellow 90-95%, red below 90%
4. **Replication Lag** (timeseries) - lag in seconds over time
5. **Top Databases by Size** (table) - sorted largest to smallest
6. **CPU and Memory** (timeseries) - overlaid lines for CPU% and Memory% on each PG server

### Step 3.5: Use the Template Variable

At the top of the dashboard you will see a dropdown labeled **PG Instance**. It is pre-populated with all instances that expose `pg_up` metrics. Select `172.31.19.86:9187` (pg-primary) and verify the panels filter to show only that instance's data.

Select **All** to see all instances together.

Template variables eliminate the need to build separate dashboards per server. One dashboard covers the entire cluster.

---

## Exercise 4: Alertmanager Operations (15 minutes)

**Scenario:** You need to do maintenance on pg-replica. You will use Alertmanager's API to create a silence so alerts for pg-replica don't fire during the work, then expire the silence when done.

### Step 4.1: List All Currently Active Alerts

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
```

This calls the Alertmanager v2 API to retrieve all alerts that Alertmanager has received from Prometheus. Each alert in the response includes its labels, annotations, current state, and whether it is silenced.

Expected output (yours will differ):

```json
[
    {
        "labels": {
            "alertname": "WatchdogAlert",
            "severity": "none"
        },
        "status": {
            "state": "active",
            "silencedBy": [],
            "inhibitedBy": []
        },
        ...
    }
]
```

If the list is empty, no alerts are currently firing. The Watchdog alert (if you set it up) fires continuously as a heartbeat to confirm Alertmanager is receiving data.

### Step 4.2: Create a 2-Hour Silence for pg-replica

Create a silence that will suppress all alerts where the `instance` label matches the replica's private IP.

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "instance",
        "value": "172.31.22.69",
        "isRegex": true,
        "isEqual": true
      }
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
    "endsAt": "'$(date -u -d "+2 hours" +%Y-%m-%dT%H:%M:%S.000Z)'",
    "createdBy": "happy",
    "comment": "Planned maintenance on pg-replica - applying OS patches"
  }' \
  | python3 -m json.tool
```

The `$()` syntax runs a command and substitutes its output inline. `date -u` prints UTC time. The `startsAt` and `endsAt` fields use ISO 8601 format.

Expected output (yours will differ):

```json
{
    "silenceID": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

Save the `silenceID` value. You will need it to expire the silence early.

### Step 4.3: Verify the Silence Is Active

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/api/v2/silences \
  | python3 -m json.tool \
  | grep -A10 '"state": "active"'
```

Expected output (yours will differ):

```json
    "status": {
        "state": "active"
    },
    "comment": "Planned maintenance on pg-replica - applying OS patches",
    "createdBy": "happy",
```

The silence is in `"state": "active"`. Any matching alerts will now show as `"silencedBy"` in the alerts API.

### Step 4.4: Check Which Alerts Are Being Silenced

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/api/v2/alerts?silenced=true | python3 -m json.tool
```

The `?silenced=true` query parameter includes silenced alerts in the response (they are normally hidden). Look for alerts where `"silencedBy"` contains your silence ID.

If no alerts are firing for pg-replica right now, you will see an empty list. That is fine - the silence is waiting to catch any that do fire.

### Step 4.5: Expire the Silence Early

Maintenance finished ahead of schedule. Delete the silence now instead of waiting 2 hours.

On **pg-ops**, as **ec2-user**:

Replace the silence ID below with the one from Step 4.2:

```bash
SILENCE_ID="a1b2c3d4-e5f6-7890-abcd-ef1234567890"
```

```bash
curl -s -X DELETE http://localhost:9093/api/v2/silences/${SILENCE_ID}
```

A successful DELETE returns an empty response body (HTTP 200). Verify it is gone:

```bash
curl -s http://localhost:9093/api/v2/silences \
  | python3 -m json.tool \
  | grep -c '"state": "active"'
```

Expected output (yours will differ):

```
0
```

If the count is `0`, no active silences remain. Alerts for pg-replica will now fire normally.

### Step 4.6: Check the Alertmanager Web UI

Open your browser and go to:

```
http://34.228.32.17:9093
```

Click **Silences** in the top navigation. You should see your silence listed with status **Expired** (not Active).

Click **Alerts** to see all currently firing alerts and their states.

---

## Exercise 5: Incident Response Simulation (20 minutes)

**Scenario:** You are the on-call DBA. At 2:47 AM, an alert fires: postgres_exporter on pg-primary is down. Prometheus can no longer see PostgreSQL metrics. Walk through the full incident lifecycle from first alert to resolution.

### Step 5.1: Simulate the Failure

SSH into pg-primary to stop the exporter. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

```bash
sudo systemctl stop postgres_exporter
```

Confirm it stopped:

```bash
sudo systemctl status postgres_exporter | head -6
```

Expected output (yours will differ):

```
   postgres_exporter.service - Prometheus PostgreSQL Exporter
   Loaded: loaded (/usr/lib/systemd/system/postgres_exporter.service; enabled; ...)
   Active: inactive (dead) since Wed 2026-06-18 02:47:00 UTC; 3s ago
  Process: 12345 ExecStart=/usr/local/bin/postgres_exporter (code=killed, signal=TERM)
 Main PID: 12345 (code=killed, signal=TERM)
```

`Active: inactive (dead)` confirms the service is stopped.

```bash
exit
```

### Step 5.2: Monitor the Alert Lifecycle - Pending State

Go back to pg-ops. On **pg-ops**, as **ec2-user**:

Wait 30-60 seconds for Prometheus to miss its next scrape, then check the targets:

```bash
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool \
  | grep -A5 '9187'
```

Expected output (yours will differ):

```json
                "scrapeUrl": "http://172.31.19.86:9187/metrics",
                "health": "down",
                "lastError": "Get \"http://172.31.19.86:9187/metrics\": dial tcp 172.31.19.86:9187: connect: connection refused",
```

The target is now `"health": "down"`. Prometheus is recording the failure.

Check if a `PostgresDown` alert (or similar) is in pending state:

```bash
curl -s http://localhost:9090/api/v1/alerts \
  | python3 -m json.tool \
  | grep -B2 -A8 '"state": "pending"'
```

Expected output (yours will differ):

```json
{
    "labels": {
        "alertname": "PostgresDown",
        "instance": "172.31.19.86:9187",
        "severity": "critical"
    },
    "state": "pending",
    "activeAt": "2026-06-18T02:47:45Z",
```

The `"state": "pending"` means the condition is true but the `for` duration has not passed yet. The alert is not yet sent to Alertmanager.

### Step 5.3: Wait for the Firing State

On **pg-ops**, as **ec2-user**:

Wait for the `for` duration defined in the alert rule (usually 1-5 minutes). Then check again:

```bash
curl -s http://localhost:9090/api/v1/alerts \
  | python3 -m json.tool \
  | grep -B2 -A8 '"state": "firing"'
```

Expected output (yours will differ):

```json
{
    "labels": {
        "alertname": "PostgresDown",
        "instance": "172.31.19.86:9187",
        "severity": "critical"
    },
    "state": "firing",
    "activeAt": "2026-06-18T02:47:45Z",
```

The alert has transitioned from `pending` to `firing`. Alertmanager has now received this alert.

You can also check the Prometheus alerts page in your browser at:

```
http://34.228.32.17:9090/alerts
```

Look for the `PostgresDown` alert highlighted in red.

### Step 5.4: Check Alertmanager Has Received the Alert

On **pg-ops**, as **ec2-user**:

```bash
curl -s http://localhost:9093/api/v2/alerts | python3 -m json.tool
```

Expected output (yours will differ):

```json
[
    {
        "labels": {
            "alertname": "PostgresDown",
            "instance": "172.31.19.86:9187",
            "severity": "critical"
        },
        "status": {
            "state": "active",
            "silencedBy": [],
            "inhibitedBy": []
        },
        "annotations": {
            "summary": "PostgreSQL exporter is down on 172.31.19.86:9187"
        },
        ...
    }
]
```

The alert is in Alertmanager with `"state": "active"`. In production, Alertmanager would have sent a notification to PagerDuty or Slack by now.

### Step 5.5: Acknowledge and Add a Working Silence

While you investigate and fix the issue, create a short silence so repeated notifications do not pile up.

On **pg-ops**, as **ec2-user**:

```bash
curl -s -X POST http://localhost:9093/api/v2/silences \
  -H "Content-Type: application/json" \
  -d '{
    "matchers": [
      {
        "name": "alertname",
        "value": "PostgresDown",
        "isRegex": false,
        "isEqual": true
      },
      {
        "name": "instance",
        "value": "172.31.19.86:9187",
        "isRegex": false,
        "isEqual": true
      }
    ],
    "startsAt": "'$(date -u +%Y-%m-%dT%H:%M:%S.000Z)'",
    "endsAt": "'$(date -u -d "+30 minutes" +%Y-%m-%dT%H:%M:%S.000Z)'",
    "createdBy": "happy",
    "comment": "Investigating and fixing postgres_exporter down on pg-primary - INC-2026-0618"
  }' \
  | python3 -m json.tool
```

Record the silence ID from the response.

### Step 5.6: Fix the Issue

SSH into pg-primary. On your **local machine**, as your local user:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@100.26.54.122
```

On **pg-primary**, as **ec2-user**:

Check the service logs to understand why it went down (in a real incident, look for a root cause):

```bash
sudo journalctl -u postgres_exporter --no-pager -n 30
```

`journalctl` reads the systemd journal. `-u postgres_exporter` filters to only that service's logs. `--no-pager` prints all output without pausing. `-n 30` limits to the last 30 lines.

Restart the exporter:

```bash
sudo systemctl start postgres_exporter
```

Verify it is running:

```bash
sudo systemctl status postgres_exporter | head -5
```

Expected output (yours will differ):

```
   Active: active (running) since Wed 2026-06-18 02:55:00 UTC; 2s ago
```

Confirm it is serving metrics:

```bash
curl -s http://localhost:9187/metrics | grep pg_up
```

Expected output (yours will differ):

```
pg_up 1
```

A value of `1` means postgres_exporter connected to PostgreSQL successfully.

```bash
exit
```

### Step 5.7: Watch the Alert Resolve

Go back to pg-ops. On **pg-ops**, as **ec2-user**:

Wait 30-60 seconds for Prometheus to scrape the target again, then check:

```bash
curl -s http://localhost:9090/api/v1/targets \
  | python3 -m json.tool \
  | grep -A3 '9187.*19.86\|19.86.*9187' \
  | grep health
```

Expected output (yours will differ):

```json
                "health": "up",
```

The target is back to `"health": "up"`.

Check that the alert has resolved in Prometheus:

```bash
curl -s http://localhost:9090/api/v1/alerts \
  | python3 -m json.tool \
  | grep -c '"state": "firing"'
```

Expected output (yours will differ):

```
0
```

Zero firing alerts means the PostgresDown alert has resolved.

### Step 5.8: Expire the Working Silence

Now that the issue is fixed, expire the silence early.

On **pg-ops**, as **ec2-user**:

```bash
SILENCE_ID="<your silence ID from Step 5.5>"
```

```bash
curl -s -X DELETE http://localhost:9093/api/v2/silences/${SILENCE_ID}
```

### Step 5.9: Document the Incident Timeline

Write your timeline now while it is fresh. This is what you do after every incident.

On **pg-ops**, as **ec2-user**:

```bash
vi /tmp/incident-report-2026-0618.txt
```

Press `i` to enter insert mode. Fill in the actual times from your exercise:

```
INCIDENT REPORT - 2026-06-18
Title: postgres_exporter Down on pg-primary

Timeline:
- 02:47:00 UTC - postgres_exporter stopped (simulated)
- 02:47:30 UTC - Prometheus scrape fails, target marked "down"
- 02:48:00 UTC - PostgresDown alert transitions to "pending"
- 02:50:00 UTC - Alert transitions to "firing", Alertmanager notified
- 02:51:00 UTC - On-call DBA acknowledged alert, created 30m silence
- 02:51:30 UTC - SSH to pg-primary, checked journalctl logs
- 02:52:00 UTC - Root cause identified: (fill in)
- 02:55:00 UTC - postgres_exporter restarted
- 02:55:30 UTC - Prometheus target back to "up", alert resolved
- 02:56:00 UTC - Working silence expired

Root Cause:
  (describe what caused the exporter to stop - manual stop in this drill)

Impact:
  - Monitoring blind spot on pg-primary for 8 minutes
  - No database outage - PostgreSQL itself remained running

Remediation:
  - Restarted postgres_exporter
  - Verified pg_up = 1 on pg-primary

Follow-up Actions:
  - Review postgres_exporter Restart= policy in systemd unit
  - Confirm alerting pipeline delivered notification within expected SLA
```

Press `Esc`, then type `:wq` and press `Enter` to save.

This post-mortem format is exactly what you will be expected to produce at Voleon.

---

## Summary

| Exercise | Duration | Skill Practiced | Interview Question It Answers |
|---|---|---|---|
| 1. PromQL Diagnostic Challenge | 20 min | 10 targeted PromQL queries via API | "How do you diagnose a slow query report?" |
| 2. Alert Rule Development | 25 min | Write, validate, load 5 custom alert rules | "How do you add new alerts?" |
| 3. Grafana Dashboard Build | 30 min | Dashboard JSON via API, template variables | "Build me a monitoring dashboard" |
| 4. Alertmanager Operations | 15 min | Silence lifecycle via v2 API | "How do you handle maintenance windows?" |
| 5. Incident Response Simulation | 20 min | Full alert lifecycle from failure to resolution | "Walk me through an incident" |

Each exercise produces a concrete artifact: running queries, loaded alert rules, a live dashboard, an expired silence, and a written post-mortem. These are the deliverables Ed Byrne is evaluating.

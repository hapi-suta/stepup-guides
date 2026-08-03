# Tier 8 - Build Guide 03: Observability Pipelines

**Objective:** Export PostgreSQL logs from RDS to CloudWatch Logs, create log metric filters to extract operational signals, query logs with Logs Insights, and build a CloudWatch operational dashboard.
**Time:** 35 minutes
**Level:** Expert
**infra_required:** true - Requires a running RDS PostgreSQL or Aurora PostgreSQL instance.
**Prerequisites:** A running RDS or Aurora PostgreSQL instance. IAM permissions for CloudWatch Logs and RDS modify operations.

---

## 1. Export PostgreSQL Logs to CloudWatch Logs

RDS can publish logs to CloudWatch Logs in near real-time. This enables log search, metric extraction, alerting, and long-term retention without managing a logging server.

### Configure log export (Console)

1. Open the RDS console.
2. Select **Databases** and click your instance identifier.
3. Click **Modify**.
4. Scroll to the **Log exports** section.
5. Check **PostgreSQL log** (also check **Upgrade log** if this is a long-running instance).
6. Click **Continue** and apply during next maintenance window or immediately.

### Configure log export (CLI)

```bash
aws rds modify-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --cloudwatch-logs-export-configuration EnableLogTypes=postgresql \
  --apply-immediately \
  --region [REGION]
```

For Aurora clusters, target the cluster identifier:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [CLUSTER-ID] \
  --cloudwatch-logs-export-configuration EnableLogTypes=postgresql \
  --apply-immediately \
  --region [REGION]
```

### Enable slow query logging (parameter group)

Exporting logs is only useful if you configure PostgreSQL to log meaningful events. The most valuable setting is slow query logging.

Find the parameter group attached to your instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text \
  --region [REGION]
```

Modify the key logging parameters:

```bash
# Log queries taking longer than 1000ms (1 second)
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters \
    ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate \
    ParameterName=log_connections,ParameterValue=1,ApplyMethod=immediate \
    ParameterName=log_disconnections,ParameterValue=1,ApplyMethod=immediate \
    ParameterName=log_lock_waits,ParameterValue=1,ApplyMethod=immediate \
    ParameterName=log_temp_files,ParameterValue=0,ApplyMethod=immediate \
    ParameterName=log_autovacuum_min_duration,ParameterValue=0,ApplyMethod=immediate \
  --region [REGION]
```

`log_min_duration_statement=1000` logs any query running longer than 1 second. Set this to 500ms for more visibility, or 5000ms to reduce volume on very busy instances.
`log_lock_waits=1` logs any query that waits for a lock.
`log_temp_files=0` logs any query that creates a temp file (indicates a sort or hash that spilled to disk).
`log_autovacuum_min_duration=0` logs all autovacuum runs (set higher to reduce noise on high-churn tables).

### Verify logs are flowing (Console)

1. Open **CloudWatch** console.
2. Select **Log groups** under **Logs**.
3. Look for a log group named: `/aws/rds/instance/[instance-id]/postgresql`

Allow 2-5 minutes after enabling for the first log entries to appear.

### Verify logs are flowing (CLI)

```bash
aws logs describe-log-groups \
  --log-group-name-prefix /aws/rds/instance/[INSTANCE-ID] \
  --region [REGION]
```

Expected output (yours will differ):
```json
{
  "logGroups": [
    {
      "logGroupName": "/aws/rds/instance/prod-pg-primary/postgresql",
      "creationTime": 1705329600000,
      "retentionInDays": 30,
      "storedBytes": 204800
    }
  ]
}
```

Set a log retention policy to control CloudWatch Logs storage costs:

```bash
aws logs put-retention-policy \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --retention-in-days 90 \
  --region [REGION]
```

90 days is a reasonable default. HIPAA requires 6 years - adjust accordingly.

---

## 2. Create Log Metric Filters

Metric filters watch a log group for a pattern and increment a CloudWatch custom metric each time the pattern matches. This converts log data into actionable metrics that can drive alarms.

### Create a deadlock metric filter (Console)

1. Open **CloudWatch** console.
2. Select **Log groups**.
3. Click the log group `/aws/rds/instance/[INSTANCE-ID]/postgresql`.
4. Click **Metric filters** tab.
5. Click **Create metric filter**.
6. In the **Filter pattern** box, enter: `deadlock detected`
7. Click **Test pattern** to verify it matches log lines if any exist.
8. Click **Next**.
9. Set:
   - Filter name: `pg-deadlock-count`
   - Metric namespace: `RDS/PostgreSQL/Custom`
   - Metric name: `DeadlockCount`
   - Metric value: `1`
   - Unit: `Count`
10. Click **Create metric filter**.

### Create metric filters (CLI)

```bash
# Deadlock metric filter
aws logs put-metric-filter \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-name pg-deadlock-count \
  --filter-pattern "deadlock detected" \
  --metric-transformations \
    metricName=DeadlockCount,metricNamespace=RDS/PostgreSQL/Custom,metricValue=1,unit=Count \
  --region [REGION]
```

```bash
# Autovacuum runs metric filter
aws logs put-metric-filter \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-name pg-autovacuum-runs \
  --filter-pattern "automatic vacuum of table" \
  --metric-transformations \
    metricName=AutovacuumRuns,metricNamespace=RDS/PostgreSQL/Custom,metricValue=1,unit=Count \
  --region [REGION]
```

```bash
# Authentication failure metric filter
aws logs put-metric-filter \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-name pg-auth-failures \
  --filter-pattern "authentication failed" \
  --metric-transformations \
    metricName=AuthFailureCount,metricNamespace=RDS/PostgreSQL/Custom,metricValue=1,unit=Count \
  --region [REGION]
```

```bash
# Transaction wraparound warning filter
aws logs put-metric-filter \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-name pg-wraparound-warning \
  --filter-pattern "transaction ID wraparound" \
  --metric-transformations \
    metricName=WraparoundWarningCount,metricNamespace=RDS/PostgreSQL/Custom,metricValue=1,unit=Count \
  --region [REGION]
```

```bash
# Temp file creation (spill to disk) filter
aws logs put-metric-filter \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-name pg-temp-files \
  --filter-pattern "temporary file" \
  --metric-transformations \
    metricName=TempFileCount,metricNamespace=RDS/PostgreSQL/Custom,metricValue=1,unit=Count \
  --region [REGION]
```

### Create a CloudWatch Alarm on the deadlock metric

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name rds-deadlock-alert-[INSTANCE-ID] \
  --alarm-description "RDS deadlock detected on [INSTANCE-ID]" \
  --namespace RDS/PostgreSQL/Custom \
  --metric-name DeadlockCount \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --ok-actions [SNS-TOPIC-ARN] \
  --treat-missing-data notBreaching \
  --region [REGION]
```

`--period 300` evaluates the metric over a 5-minute window.
`--threshold 1` triggers when even one deadlock is detected.
`--treat-missing-data notBreaching` prevents false alarms during periods with no log activity.

---

## 3. CloudWatch Logs Insights Queries

Logs Insights is an interactive query engine for your log data. Use it for incident investigation and ad-hoc analysis.

### Open Logs Insights (Console)

1. Open **CloudWatch** console.
2. Click **Logs Insights** under **Logs**.
3. In the **Select log group(s)** dropdown, select `/aws/rds/instance/[INSTANCE-ID]/postgresql`.
4. Set the time range to the last 24 hours.

### Query: Find the top 10 slowest queries

Paste this query and click **Run query**:

```
fields @timestamp, @message
| filter @message like /duration:/
| parse @message "duration: * ms  statement: *" as duration_ms, statement
| stats max(duration_ms) as max_duration_ms, count(*) as occurrences by statement
| sort max_duration_ms desc
| limit 10
```

This parses the duration and statement from slow query log lines and surfaces the worst offenders.

### Query: Count errors by type in the last hour

```
fields @timestamp, @message
| filter @message like /ERROR/
| parse @message "ERROR:  *" as error_message
| stats count(*) as error_count by error_message
| sort error_count desc
| limit 20
```

### Query: Find connection churn (connects + disconnects per minute)

```
fields @timestamp, @message
| filter @message like /connection received/ or @message like /disconnection/
| stats count() as connection_events by bin(1m)
| sort @timestamp asc
```

High connection churn indicates that the application is not using connection pooling. Each new connection has overhead - CPU and memory allocation on the PostgreSQL side.

### Query: Autovacuum activity summary

```
fields @timestamp, @message
| filter @message like /automatic vacuum/
| parse @message "automatic vacuum of table \"*\": index scans: *, pages: * removed, * remain" as table_name, index_scans, pages_removed, pages_remain
| stats count(*) as vacuum_runs, sum(pages_removed) as total_pages_removed by table_name
| sort vacuum_runs desc
| limit 20
```

Tables with very high vacuum run counts may need autovacuum tuning (more aggressive settings or manual VACUUM).

### Query: Lock wait events

```
fields @timestamp, @message
| filter @message like /still waiting for lock/
| stats count(*) as lock_wait_events by bin(5m)
| sort @timestamp asc
```

A spike in lock wait events correlates with lock contention. Cross-reference with application deployment timestamps or batch job schedules.

### Run a Logs Insights query (CLI)

Start the query:

```bash
aws logs start-query \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --start-time $(date -u -v-24H +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /deadlock/ | limit 20' \
  --region [REGION]
```

This returns a query ID. Retrieve results:

```bash
aws logs get-query-results \
  --query-id [QUERY-ID] \
  --region [REGION]
```

---

## 4. Build an Operational Dashboard

A CloudWatch dashboard provides a single view of fleet health. Create one dashboard per cluster or one shared dashboard for the entire fleet.

### Create a dashboard (Console)

1. Open **CloudWatch** console.
2. Click **Dashboards** in the left navigation.
3. Click **Create dashboard**.
4. Name it `RDS-Operations-[ENV]` (e.g., `RDS-Operations-Production`).
5. Click **Create dashboard**.
6. Add widgets by clicking the **+** button.

**Recommended widgets:**

Widget 1 - Line chart: CPU Utilization
- Metric: `AWS/RDS` > `CPUUtilization` > select your instance(s)
- Period: 1 minute
- Statistic: Average

Widget 2 - Line chart: Database Connections
- Metric: `AWS/RDS` > `DatabaseConnections`
- Add a horizontal annotation at your `max_connections` threshold (e.g., 80% of max)

Widget 3 - Line chart: Read and Write Latency
- Metrics: `ReadLatency` and `WriteLatency` on the same chart
- Period: 1 minute
- Alert annotation at 20ms

Widget 4 - Line chart: Free Storage Space
- Metric: `FreeStorageSpace`
- Alert annotation at 20% of provisioned storage

Widget 5 - Line chart: Replica Lag
- Metric: `AuroraReplicaLag` (for Aurora) or `ReplicaLag` (for RDS read replicas)
- Alert annotation at 30 seconds

Widget 6 - Number widget: Custom deadlock metric
- Metric: `RDS/PostgreSQL/Custom` > `DeadlockCount`
- Sum over 1 hour

Widget 7 - Alarm status widget
- Add all your RDS-related CloudWatch Alarms

### Create a dashboard (CLI)

```bash
aws cloudwatch put-dashboard \
  --dashboard-name RDS-Operations-Production \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "x": 0, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "CPU Utilization",
          "metrics": [
            ["AWS/RDS", "CPUUtilization", "DBInstanceIdentifier", "[INSTANCE-ID]"]
          ],
          "period": 60,
          "stat": "Average",
          "view": "timeSeries",
          "region": "[REGION]"
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 0, "width": 12, "height": 6,
        "properties": {
          "title": "Database Connections",
          "metrics": [
            ["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "[INSTANCE-ID]"]
          ],
          "period": 60,
          "stat": "Maximum",
          "view": "timeSeries",
          "region": "[REGION]"
        }
      },
      {
        "type": "metric",
        "x": 0, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "Read and Write Latency (ms)",
          "metrics": [
            ["AWS/RDS", "ReadLatency", "DBInstanceIdentifier", "[INSTANCE-ID]", {"label": "Read"}],
            ["AWS/RDS", "WriteLatency", "DBInstanceIdentifier", "[INSTANCE-ID]", {"label": "Write"}]
          ],
          "period": 60,
          "stat": "Average",
          "view": "timeSeries",
          "region": "[REGION]"
        }
      },
      {
        "type": "metric",
        "x": 12, "y": 6, "width": 12, "height": 6,
        "properties": {
          "title": "Free Storage Space (bytes)",
          "metrics": [
            ["AWS/RDS", "FreeStorageSpace", "DBInstanceIdentifier", "[INSTANCE-ID]"]
          ],
          "period": 300,
          "stat": "Minimum",
          "view": "timeSeries",
          "region": "[REGION]"
        }
      }
    ]
  }' \
  --region [REGION]
```

---

## Summary

- Log exports to CloudWatch Logs require enabling both the export on the instance and configuring PostgreSQL parameters (`log_min_duration_statement`, `log_lock_waits`, etc.) to generate useful log content.
- Metric filters extract operational signals from log streams. Use a consistent namespace (`RDS/PostgreSQL/Custom`) so filters from multiple instances appear in the same metric namespace.
- CloudWatch Logs Insights enables powerful ad-hoc queries during incident investigation. Save frequently used queries as they cannot be retrieved from the API after the session.
- Dashboards should show the metrics that answer "is this database healthy right now?" in one view - CPU, connections, latency, free storage, replica lag, and any custom signals you have extracted.

**Next:** [Guide 04 - Incident Response Runbooks](./04-incident-response-runbooks.md)

# BUILD 04 - Cloud SQL for PostgreSQL: Monitoring and Logging

## What You Will Build

A monitoring and alerting setup for Cloud SQL using Cloud Monitoring, Query Insights, Cloud Logging, and custom alert policies. You will know how to identify slow queries, track performance metrics, and get notified when something goes wrong.

---

## Prerequisites

- Completed BUILD 01 (instance `suta-pg-lab` exists and is running)
- `gcloud` CLI authenticated and project set
- Enable monitoring APIs

---

## Step 1 - Enable Required APIs

Enable Cloud Monitoring and Cloud Logging APIs.

```bash
gcloud services enable monitoring.googleapis.com
```

```bash
gcloud services enable logging.googleapis.com
```

Expected output (yours will differ):

```
Operation "operations/acf.p2-123456789-abc123" finished successfully.
```

---

## Step 2 - View Cloud SQL Metrics via gcloud

Cloud SQL automatically sends metrics to Cloud Monitoring. No agent installation needed.

List available Cloud SQL metrics. The `--filter` flag narrows to Cloud SQL metrics only.

```bash
gcloud monitoring metrics-descriptors list --filter="metric.type:cloudsql.googleapis.com/database" --format="table(type,description)" --limit=20
```

Expected output (yours will differ):

```
TYPE                                                          DESCRIPTION
cloudsql.googleapis.com/database/cpu/utilization              CPU utilization
cloudsql.googleapis.com/database/disk/bytes_used              Disk bytes used
cloudsql.googleapis.com/database/disk/utilization             Disk utilization
cloudsql.googleapis.com/database/memory/utilization           Memory utilization
cloudsql.googleapis.com/database/network/connections          Number of connections
cloudsql.googleapis.com/database/postgresql/num_backends      Number of backends
...
```

Key metrics to monitor:

| Metric | What It Tells You | Alert Threshold |
|---|---|---|
| cpu/utilization | CPU usage (0.0 to 1.0) | > 0.8 for 5 min |
| disk/utilization | Disk usage (0.0 to 1.0) | > 0.85 |
| memory/utilization | RAM usage (0.0 to 1.0) | > 0.9 |
| network/connections | Active connections | > 80% of max_connections |
| postgresql/num_backends | PostgreSQL backend count | > 80% of max_connections |
| replication/replica_byte_lag | Replication lag in bytes | > 1 GB |

---

## Step 3 - Query a Specific Metric

Read the CPU utilization for the last hour. This uses the Cloud Monitoring time series API.

```bash
gcloud monitoring time-series read \
  --filter='metric.type="cloudsql.googleapis.com/database/cpu/utilization" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --interval-start-time=$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --interval-end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --format="table(points.interval.startTime,points.value.doubleValue)"
```

On Linux, replace `-v-1H` with `-d '1 hour ago'`:

```bash
gcloud monitoring time-series read \
  --filter='metric.type="cloudsql.googleapis.com/database/cpu/utilization" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --interval-start-time=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --interval-end-time=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --format="table(points.interval.startTime,points.value.doubleValue)"
```

Expected output (yours will differ):

```
START_TIME                    VALUE
2026-04-19T12:00:00Z          0.05
2026-04-19T12:01:00Z          0.03
2026-04-19T12:02:00Z          0.04
...
```

---

## Step 4 - Enable Query Insights

Query Insights is Cloud SQL's equivalent of pg_stat_statements. It tracks query performance without installing extensions.

Enable Query Insights on your instance.

```bash
gcloud sql instances patch suta-pg-lab \
  --insights-config-query-insights-enabled \
  --insights-config-query-string-length=4096 \
  --insights-config-record-application-tags \
  --insights-config-record-client-address
```

Flags explained:
- `--insights-config-query-insights-enabled`: Turns on Query Insights
- `--insights-config-query-string-length`: Maximum query length to capture (default 1024)
- `--insights-config-record-application-tags`: Records application name from connection string
- `--insights-config-record-client-address`: Records the client IP for each query

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Verify Query Insights is enabled.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.insightsConfig)"
```

Expected output (yours will differ):

```yaml
settings:
  insightsConfig:
    queryInsightsEnabled: true
    queryStringLength: 4096
    recordApplicationTags: true
    recordClientAddress: true
```

---

## Step 5 - Generate Load for Query Insights

Connect to the database and run some queries to generate data for Query Insights.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Create a larger table for testing.

```sql
CREATE TABLE load_test (
    id SERIAL PRIMARY KEY,
    data TEXT,
    value NUMERIC,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

Insert 100,000 rows. The `generate_series` function creates rows efficiently.

```sql
INSERT INTO load_test (data, value)
SELECT
    md5(random()::text),
    random() * 1000
FROM generate_series(1, 100000);
```

Expected output (yours will differ):

```
INSERT 0 100000
```

Run a slow query (no index on `value` column).

```sql
SELECT data, value FROM load_test WHERE value BETWEEN 500 AND 501 ORDER BY value;
```

Run it several times to generate statistics.

```sql
SELECT count(*), avg(value) FROM load_test WHERE data LIKE 'a%';
```

```sql
SELECT data, value FROM load_test ORDER BY value DESC LIMIT 10;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 6 - View Query Insights Data

Query Insights data is visible in the Cloud Console, but you can also query it via the Cloud Monitoring API.

Check pg_stat_statements (if the extension is enabled).

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

```sql
SELECT
    query,
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    rows
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

Expected output (yours will differ):

```
                        query                         | calls | total_ms | avg_ms | rows
------------------------------------------------------+-------+----------+--------+-------
 INSERT INTO load_test (data, value) SELECT ...       |     1 |  2345.67 | 2345.67| 100000
 SELECT data, value FROM load_test WHERE value ...    |     3 |   456.78 |  152.26|    300
 SELECT count(*), avg(value) FROM load_test ...       |     1 |   234.56 |  234.56|      1
...
```

Type `\q` to exit psql.

```
\q
```

---

## Step 7 - Configure Slow Query Logging

Set database flags to log slow queries. The `log_min_duration_statement` flag logs any query taking longer than the specified milliseconds.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=log_min_duration_statement=1000,log_statement=ddl,log_connections=on,log_disconnections=on,log_lock_waits=on
```

Flags explained:
- `log_min_duration_statement=1000`: Log queries taking more than 1 second (1000 ms)
- `log_statement=ddl`: Log all DDL statements (CREATE, ALTER, DROP)
- `log_connections=on`: Log each new connection
- `log_disconnections=on`: Log each disconnection
- `log_lock_waits=on`: Log when a query waits for a lock

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

---

## Step 8 - View Logs in Cloud Logging

Read PostgreSQL logs from Cloud Logging. The `--resource-names` flag scopes to your instance.

```bash
gcloud logging read 'resource.type="cloudsql_database" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --limit=20 \
  --format="table(timestamp,textPayload)"
```

Expected output (yours will differ):

```
TIMESTAMP                    TEXT_PAYLOAD
2026-04-19T12:30:00.000Z    [1234]: [1-1] db=suta_lab,user=postgres LOG: duration: 2345.670 ms statement: INSERT INTO...
2026-04-19T12:29:00.000Z    [1234]: [1-1] db=suta_lab,user=postgres LOG: connection authorized: user=postgres database=suta_lab
...
```

Filter for slow queries only.

```bash
gcloud logging read 'resource.type="cloudsql_database" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab" AND textPayload:"duration"' \
  --limit=10 \
  --format="table(timestamp,textPayload)"
```

Filter for error messages.

```bash
gcloud logging read 'resource.type="cloudsql_database" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab" AND severity>=ERROR' \
  --limit=10 \
  --format="table(timestamp,severity,textPayload)"
```

---

## Step 9 - Enable Database Audit Logging

Cloud Audit Logs track who did what to your Cloud SQL resources (API calls like creating instances, changing flags, etc.). This is enabled by default for Admin Activity.

Enable Data Access audit logging for Cloud SQL. This tracks database-level operations.

```bash
gcloud projects get-iam-policy [PROJECT_ID] --format=json > /tmp/policy.json
```

This outputs the current IAM policy. You need to add an audit config for Cloud SQL.

View the current audit config.

```bash
gcloud logging read 'protoPayload.serviceName="sqladmin.googleapis.com"' \
  --limit=10 \
  --format="table(timestamp,protoPayload.methodName,protoPayload.authenticationInfo.principalEmail)"
```

Expected output (yours will differ):

```
TIMESTAMP                    METHOD_NAME                              PRINCIPAL_EMAIL
2026-04-19T12:00:00.000Z    cloudsql.instances.patch                 user@example.com
2026-04-19T11:50:00.000Z    cloudsql.instances.create                user@example.com
...
```

This shows all Cloud SQL API calls - who created or modified instances.

---

## Step 10 - Create Alert Policies

Create an alert for high CPU utilization. This triggers when CPU exceeds 80% for 5 minutes.

```bash
gcloud monitoring policies create \
  --display-name="Cloud SQL CPU > 80%" \
  --condition-display-name="CPU utilization high" \
  --condition-filter='metric.type="cloudsql.googleapis.com/database/cpu/utilization" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --condition-threshold-value=0.8 \
  --condition-threshold-comparison=COMPARISON_GT \
  --condition-threshold-duration=300s \
  --combiner=OR
```

Expected output (yours will differ):

```
Created alert policy [projects/my-project/alertPolicies/12345678901234567890].
```

Create an alert for disk utilization over 85%.

```bash
gcloud monitoring policies create \
  --display-name="Cloud SQL Disk > 85%" \
  --condition-display-name="Disk utilization high" \
  --condition-filter='metric.type="cloudsql.googleapis.com/database/disk/utilization" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --condition-threshold-value=0.85 \
  --condition-threshold-comparison=COMPARISON_GT \
  --condition-threshold-duration=300s \
  --combiner=OR
```

Create an alert for high connection count.

```bash
gcloud monitoring policies create \
  --display-name="Cloud SQL Connections > 80%" \
  --condition-display-name="Connection count high" \
  --condition-filter='metric.type="cloudsql.googleapis.com/database/network/connections" AND resource.labels.database_id="[PROJECT_ID]:suta-pg-lab"' \
  --condition-threshold-value=80 \
  --condition-threshold-comparison=COMPARISON_GT \
  --condition-threshold-duration=300s \
  --combiner=OR
```

List all alert policies.

```bash
gcloud monitoring policies list --format="table(displayName,enabled,conditions.displayName)"
```

Expected output (yours will differ):

```
DISPLAY_NAME                    ENABLED  CONDITIONS
Cloud SQL CPU > 80%             True     CPU utilization high
Cloud SQL Disk > 85%            True     Disk utilization high
Cloud SQL Connections > 80%     True     Connection count high
```

---

## Step 11 - Create a Notification Channel

Alerts need a notification channel (email, Slack, PagerDuty, etc.). Create an email channel.

```bash
gcloud monitoring channels create \
  --display-name="DBA Email" \
  --type=email \
  --channel-labels=email_address=[YOUR_EMAIL]
```

Expected output (yours will differ):

```
Created notification channel [projects/my-project/notificationChannels/1234567890].
```

Get the channel ID.

```bash
gcloud monitoring channels list --format="value(name)"
```

Expected output (yours will differ):

```
projects/my-project/notificationChannels/1234567890
```

Update an alert policy to use the notification channel. Replace `[POLICY_ID]` and `[CHANNEL_ID]` with your values.

```bash
gcloud monitoring policies update [POLICY_ID] \
  --notification-channels=[CHANNEL_ID]
```

---

## Step 12 - pgbench for Load Testing

Install pgbench (it comes with PostgreSQL client tools).

Initialize pgbench tables. The `-i` flag initializes, `-s` sets the scale factor (number of rows = scale * 100,000).

```bash
pgbench -h 127.0.0.1 -U postgres -d suta_lab -i -s 10
```

Expected output (yours will differ):

```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done
vacuuming...
creating primary keys...
done in 15.23 s
```

Run a 60-second load test. The `-c` flag sets concurrent connections, `-j` sets threads, `-T` sets duration in seconds.

```bash
pgbench -h 127.0.0.1 -U postgres -d suta_lab -c 10 -j 2 -T 60
```

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 10
number of threads: 2
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 12345
number of failed transactions: 0 (0.000%)
latency average = 48.621 ms
initial connection time = 234.567 ms
tps = 205.671234 (without initial connection time)
```

After the load test, check your metrics in Cloud Monitoring. CPU and connection count should have spiked.

---

## Summary

| Task | Command |
|---|---|
| List metrics | `gcloud monitoring metrics-descriptors list --filter="cloudsql"` |
| Enable Query Insights | `gcloud sql instances patch --insights-config-query-insights-enabled` |
| Set slow query log | `--database-flags=log_min_duration_statement=1000` |
| Read logs | `gcloud logging read 'resource.type="cloudsql_database"'` |
| Create alert | `gcloud monitoring policies create` |
| Create notification | `gcloud monitoring channels create --type=email` |
| Load test | `pgbench -c 10 -j 2 -T 60` |

You now have monitoring, logging, Query Insights, and alerting configured for your Cloud SQL instance.

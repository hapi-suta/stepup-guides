# USE 05 - Performance Insights

## Objective

Enable Performance Insights, generate database load with pgbench, identify top wait events and slow queries, and set up a CloudWatch alarm for CPU utilization.

---

## Exercise

You will:
1. Verify Performance Insights is enabled
2. Initialize and run pgbench
3. Query Performance Insights for top wait events
4. Find the slowest queries
5. Create a CPU alarm

---

## Step-by-Step

### 1. Verify Performance Insights is enabled

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{PI_Enabled:PerformanceInsightsEnabled,Retention:PerformanceInsightsRetentionPeriod}" \
    --output table
```

Expected output:

```
--------------------------------------
|       DescribeDBInstances          |
+--------------+---------------------+
| PI_Enabled   |     Retention       |
+--------------+---------------------+
|  True        |  7                  |
+--------------+---------------------+
```

If PI_Enabled is False, enable it:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --enable-performance-insights \
    --performance-insights-retention-period 7 \
    --apply-immediately
```

### 2. Initialize pgbench

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

Create a pgbench database:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Once connected, create the pgbench database:

```sql
CREATE DATABASE pgbench_test;
```

Exit psql:

```sql
\q
```

Initialize pgbench tables with a scale factor of 10:

```bash
pgbench -h "${RDS_ENDPOINT}" -U sutaadmin -d pgbench_test -i -s 10
```

The `-i` flag initializes the pgbench tables. `-s 10` sets scale factor 10, which creates about 1 million rows in pgbench_accounts. This gives enough data to generate meaningful load.

Expected output (yours will differ):

```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 2.34 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 5.67 s (drop tables 0.12 s, create tables 0.05 s, client-side generate 2.34 s, vacuum 1.89 s, primary keys 1.27 s).
```

### 3. Generate load

Run a 60-second benchmark with 10 clients:

```bash
pgbench -h "${RDS_ENDPOINT}" -U sutaadmin -d pgbench_test -c 10 -j 2 -T 60 -P 10
```

Flag breakdown:
- `-c 10` - 10 concurrent client connections
- `-j 2` - 2 worker threads
- `-T 60` - run for 60 seconds
- `-P 10` - print progress every 10 seconds

Expected output (yours will differ):

```
pgbench (15.4)
starting vacuum...end.
progress: 10.0 s, 312.5 tps, lat 31.89 ms stddev 18.45, 0 failed
progress: 20.0 s, 298.3 tps, lat 33.45 ms stddev 19.12, 0 failed
progress: 30.0 s, 305.1 tps, lat 32.71 ms stddev 17.89, 0 failed
progress: 40.0 s, 310.7 tps, lat 32.15 ms stddev 18.23, 0 failed
progress: 50.0 s, 302.4 tps, lat 33.02 ms stddev 19.45, 0 failed
progress: 60.0 s, 308.9 tps, lat 32.34 ms stddev 18.67, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 10
number of threads: 2
maximum number of seconds: 60
number of transactions actually processed: 18258
number of failed transactions: 0 (0.000%)
latency average = 32.59 ms
latency stddev = 18.64 ms
initial connection time = 145.23 ms
tps = 304.30 (without initial connection time)
```

### 4. Get the DBI resource ID

Performance Insights uses the DbiResourceId, not the instance identifier:

```bash
DBI_RESOURCE_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DbiResourceId" --output text)
```

```bash
echo "${DBI_RESOURCE_ID}"
```

Expected output (yours will differ):

```
db-ABCDEFGHIJKLMNOPQRSTUVWXYZ
```

### 5. Query top wait events

```bash
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier "${DBI_RESOURCE_ID}" \
    --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.wait_event", "Limit": 10}}]' \
    --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period-in-seconds 60 \
    --query "MetricList[0].DataPoints[-1].Value"
```

This returns the average active sessions (AAS) from the most recent data point. A value above the number of vCPUs means the database is overloaded.

To see the breakdown by wait event:

```bash
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier "${DBI_RESOURCE_ID}" \
    --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.wait_event", "Limit": 5}}]' \
    --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period-in-seconds 60
```

Look for these in the output:
- **CPU** - queries executing on CPU (healthy if dominant)
- **IO:DataFileRead** - reading data from disk (may need more RAM)
- **Lock:transactionid** - row lock contention (application issue)
- **LWLock:BufferMapping** - shared buffer contention (may need tuning)

### 6. Find slow queries via pg_stat_statements

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d pgbench_test -p 5432
```

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
```

```sql
SELECT
    calls,
    round(total_exec_time::numeric, 2) AS total_ms,
    round(mean_exec_time::numeric, 2) AS avg_ms,
    round(stddev_exec_time::numeric, 2) AS stddev_ms,
    rows,
    substring(query, 1, 60) AS query_preview
FROM pg_stat_statements
WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'pgbench_test')
ORDER BY mean_exec_time DESC
LIMIT 10;
```

This finds the slowest queries by average execution time, filtered to the pgbench_test database. `stddev_ms` shows execution time variance - high variance suggests inconsistent performance.

Expected output (yours will differ):

```
 calls  | total_ms  | avg_ms | stddev_ms | rows   | query_preview
--------+-----------+--------+-----------+--------+----------------------------------------------
  18258 |  45123.45 |   2.47 |      1.89 |  18258 | UPDATE pgbench_accounts SET abalance = abal
  18258 |  23456.78 |   1.28 |      0.95 |  18258 | UPDATE pgbench_tellers SET tbalance = tbalan
  18258 |  12345.67 |   0.68 |      0.45 |  18258 | UPDATE pgbench_branches SET bbalance = bbala
  18258 |   8901.23 |   0.49 |      0.32 |  18258 | INSERT INTO pgbench_history (tid, bid, aid,
  18258 |   5678.90 |   0.31 |      0.21 |  18258 | SELECT abalance FROM pgbench_accounts WHERE
```

Exit psql:

```sql
\q
```

### 7. Query top SQL via Performance Insights API

```bash
aws pi get-resource-metrics \
    --service-type RDS \
    --identifier "${DBI_RESOURCE_ID}" \
    --metric-queries '[{"Metric": "db.load.avg", "GroupBy": {"Group": "db.sql", "Limit": 5}}]' \
    --start-time "$(date -u -v-15M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period-in-seconds 300
```

The `GroupBy db.sql` breaks down load by SQL statement. Look at the `Dimensions` in the output - it includes a `db.sql.statement` field showing the actual query text.

### 8. Check CPU via CloudWatch

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --start-time "$(date -u -v-30M +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 60 \
    --statistics Average Maximum \
    --query "sort_by(Datapoints, &Timestamp)[-5:].{Time:Timestamp,AvgCPU:Average,MaxCPU:Maximum}" \
    --output table
```

You should see CPU spikes during the pgbench run.

Expected output (yours will differ):

```
------------------------------------------------------
|              GetMetricStatistics                   |
+--------+----------------------------+-------------+
| AvgCPU |           Time             |   MaxCPU    |
+--------+----------------------------+-------------+
|  45.2  | 2024-01-15T14:20:00+00:00  |  62.3       |
|  68.7  | 2024-01-15T14:21:00+00:00  |  78.9       |
|  72.1  | 2024-01-15T14:22:00+00:00  |  85.4       |
|  65.3  | 2024-01-15T14:23:00+00:00  |  73.2       |
|  12.4  | 2024-01-15T14:24:00+00:00  |  18.7       |
+--------+----------------------------+-------------+
```

### 9. Create a CPU alarm

```bash
TOPIC_ARN=$(aws sns create-topic --name suta-rds-perf-alerts --query "TopicArn" --output text)
```

```bash
aws cloudwatch put-metric-alarm \
    --alarm-name suta-rds-cpu-high \
    --alarm-description "CPU above 75% for 10 minutes" \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=suta-pg-lab \
    --statistic Average \
    --period 300 \
    --threshold 75 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --alarm-actions "${TOPIC_ARN}" \
    --ok-actions "${TOPIC_ARN}"
```

This alarms when average CPU exceeds 75% for two consecutive 5-minute periods (10 minutes total).

Verify the alarm:

```bash
aws cloudwatch describe-alarms \
    --alarm-names suta-rds-cpu-high \
    --query "MetricAlarms[0].{Name:AlarmName,State:StateValue,Threshold:Threshold}" \
    --output table
```

Expected output:

```
--------------------------------------
|         DescribeAlarms             |
+------------------+---------+-------+
|       Name       |  State  |Threshold|
+------------------+---------+---------+
| suta-rds-cpu-high| OK      | 75.0    |
+------------------+---------+---------+
```

---

## Clean Up

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
DROP DATABASE pgbench_test;
```

```sql
\q
```

```bash
aws cloudwatch delete-alarms \
    --alarm-names suta-rds-cpu-high
```

```bash
aws sns delete-topic \
    --topic-arn "${TOPIC_ARN}"
```

---

## Key Takeaway

Performance Insights shows you what your database is waiting on (wait events) and which queries are responsible (top SQL). Combined with pg_stat_statements, you can identify and fix performance bottlenecks. Always set CloudWatch alarms for CPU and storage - do not rely on checking manually.

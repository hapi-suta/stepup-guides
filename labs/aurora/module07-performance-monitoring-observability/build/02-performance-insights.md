# Build 02 - Performance Insights

**Time:** 40 minutes
**Goal:** Enable Performance Insights, read the DB Load dashboard, identify top SQL and wait events, and query PI data programmatically via the API.
**Prerequisites:** Aurora PostgreSQL cluster `devops-lab-cluster` running. `$CLUSTER_ID`, `$WRITER_INSTANCE`, `$REGION` set. psql access to the database.

---

## Step 1 - Enable Performance Insights via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click **Databases** and select your writer instance.
3. Click **Modify**.
4. Scroll to the **Performance Insights** section.
5. Check **Enable Performance Insights**.
6. Set **Retention period** to **7 days** (free tier). For production, use 1 month or longer.
7. Set **AWS KMS key** to **Default** unless your security policy requires a custom key.
8. Click **Continue**, then **Apply immediately**, then **Modify DB Instance**.

> **Concept:** Performance Insights samples the database every second. It records which SQL statements were executing and what each session was waiting on. The 7-day free tier is sufficient for most short-term investigations. Paid retention (up to 2 years) lets you compare performance across release cycles and seasonal patterns.

---

## Step 2 - Enable Performance Insights via CLI

If you prefer the CLI or want to script this for multiple instances:

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately \
  --region "$REGION"
```

Each flag explained:
- `--enable-performance-insights`: Turns on the PI feature.
- `--performance-insights-retention-period 7`: Keep 7 days of per-second data. Valid values: 7 (free), or paid: 31 through 731.
- `--apply-immediately`: Apply now without waiting for the maintenance window.

Wait for the instance to be available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --region "$REGION"
```

Expected output (yours will differ):
```
(no output - the command exits silently when the instance is available)
```

---

## Step 3 - Generate Load So You Have Data to Look At

Connect to your Aurora database:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create a test table and load data:

```sql
CREATE TABLE IF NOT EXISTS perf_test (
    id SERIAL PRIMARY KEY,
    user_id INT,
    amount NUMERIC(12,2),
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

```sql
INSERT INTO perf_test (user_id, amount, status)
SELECT
    (random() * 10000)::INT,
    (random() * 1000)::NUMERIC(12,2),
    CASE (random() * 3)::INT
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'completed'
        ELSE 'failed'
    END
FROM generate_series(1, 500000);
```

Run a slow query (no index on status, forces a sequential scan):

```sql
SELECT count(*), status
FROM perf_test
WHERE amount > 500
GROUP BY status
ORDER BY count(*) DESC;
```

Run it repeatedly for 30 seconds so PI captures the pattern:

```sql
\watch 2
```

This runs the previous query every 2 seconds. Wait 30 seconds, then press Ctrl+C to stop.

---

## Step 4 - Navigate the Performance Insights Dashboard

1. Go to the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click your writer instance.
3. Click the **Performance Insights** tab.

The dashboard has three main sections:

**Top section - Counter metrics:**
- Shows CloudWatch metrics overlaid with PI data.
- Use the dropdown to switch between CPU, connections, latency, and other metrics.

**Middle section - DB Load graph:**
- The most important chart. Shows Average Active Sessions (AAS) over time.
- The horizontal line is your vCPU count.
- The colored bands show which wait event type contributed to load.
- Hover over any point to see the breakdown.

**Bottom section - Top dimensions:**
- Tabs for Top SQL, Top waits, Top hosts, Top users, Top databases.
- Shows which SQL statements, wait events, clients, and users contributed most to DB Load.

**What to look for:**
- Is DB Load above the vCPU line? If yes, the database is saturated.
- What color dominates the DB Load graph? Blue = CPU. Red = I/O. Orange = Lock.
- Which SQL statement contributes the most DB Load?

---

## Step 5 - Drill Into a Specific Query

1. In the **Top SQL** table at the bottom, click on the sequential scan query you ran.
2. You will see:
   - **DB Load by wait**: How this query's load breaks down by wait event
   - **Executions per minute**: How often it ran
   - **Average latency**: Average duration per execution
   - **Rows examined per execution**: How many rows it scanned

3. Click **View more details** to see the full query text.

> **Concept:** Performance Insights normalizes queries. It replaces literal values with `$1`, `$2`, etc. This means 1,000 different `SELECT ... WHERE id = 42` type queries all appear as one normalized query. This is what you want - you see the pattern, not individual parameter values.

---

## Step 6 - Understand Wait Event Categories

In the DB Load graph, expand the legend and click different wait event types.

| Color | Wait Category | Common Wait Events | What It Means |
|-------|--------------|-------------------|---------------|
| Blue | CPU | (no specific wait event) | Actively computing - check for seq scans |
| Red | IO | DataFileRead, WALWrite, BufFileRead | Storage I/O - cache misses or temp spills |
| Orange | Lock | relation, tuple, transactionid | Lock contention - blocking queries |
| Yellow | LWLock | buffer_mapping, WALWrite | Internal PostgreSQL lock contention |
| Purple | Client | ClientRead, ClientWrite | Waiting for client - network or slow app |
| Gray | Other | Various | Miscellaneous waits |

When you ran the sequential scan above, you likely see `IO:DataFileRead` (reading from storage because data is not cached) and `CPU` (computing the aggregate).

---

## Step 7 - Query Performance Insights Data via API

The PI API lets you extract data programmatically for custom dashboards or automated analysis.

Get your DBI resource ID (different from the instance ID):

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$WRITER_INSTANCE" \
  --query "DBInstances[0].DbiResourceId" \
  --output text \
  --region "$REGION"
```

Expected output (yours will differ):
```
db-ABCDEF1234567890ABCDEF
```

Save it:

```bash
export DBI_RESOURCE_ID="db-ABCDEF1234567890ABCDEF"
```

Get DB Load for the last hour:

```bash
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier "$DBI_RESOURCE_ID" \
  --metric-queries '[{"Metric":"db.load.avg"}]' \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period-in-seconds 60 \
  --region "$REGION"
```

`--period-in-seconds 60`: Aggregate data into 60-second buckets.
`--metric-queries`: Specifies which PI metrics to retrieve. `db.load.avg` is the Average Active Sessions metric.

Expected output (yours will differ):
```json
{
    "AlignedStartTime": "2026-06-09T13:00:00+00:00",
    "AlignedEndTime": "2026-06-09T14:00:00+00:00",
    "Identifier": "db-ABCDEF1234567890ABCDEF",
    "MetricList": [
        {
            "Key": {"Metric": "db.load.avg"},
            "DataPoints": [
                {"Timestamp": "2026-06-09T13:00:00+00:00", "Value": 0.18},
                {"Timestamp": "2026-06-09T13:01:00+00:00", "Value": 0.22},
                ...
            ]
        }
    ]
}
```

---

## Step 8 - Get Top SQL via API

```bash
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier "$DBI_RESOURCE_ID" \
  --metric-queries '[
    {
      "Metric": "db.load.avg",
      "GroupBy": {"Group": "db.sql", "Dimensions": ["db.sql.statement"], "Limit": 5}
    }
  ]' \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period-in-seconds 3600 \
  --region "$REGION"
```

`"Limit": 5`: Return only the top 5 SQL statements by DB Load.
`"Group": "db.sql"`: Group results by SQL statement.
`--period-in-seconds 3600`: One data point for the entire hour.

---

## Step 9 - Get Top Wait Events via API

```bash
aws pi get-resource-metrics \
  --service-type RDS \
  --identifier "$DBI_RESOURCE_ID" \
  --metric-queries '[
    {
      "Metric": "db.load.avg",
      "GroupBy": {"Group": "db.wait_event", "Dimensions": ["db.wait_event.name", "db.wait_event.type"], "Limit": 10}
    }
  ]' \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period-in-seconds 3600 \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "MetricList": [
        {
            "Key": {
                "Metric": "db.load.avg",
                "Dimensions": {
                    "db.wait_event.name": "DataFileRead",
                    "db.wait_event.type": "IO"
                }
            },
            "DataPoints": [
                {"Timestamp": "...", "Value": 0.42}
            ]
        }
    ]
}
```

---

## Step 10 - Verify pg_stat_statements is Loaded

Performance Insights Top SQL provides better detail when `pg_stat_statements` is loaded:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_stat_statements';"
```

Expected output (yours will differ):
```
       extname       | extversion
---------------------+------------
 pg_stat_statements  | 1.10
```

If `pg_stat_statements` is not listed, you will enable it in Build 04.

---

## Cleanup

Remove the test data when you are done:

```sql
DROP TABLE IF EXISTS perf_test;
```

---

## Summary

You have:
- Enabled Performance Insights with 7-day retention
- Generated load and observed it in the PI dashboard
- Learned to read the DB Load chart and wait event breakdown
- Drilled into wait events and top SQL
- Queried PI data programmatically via the AWS CLI

Performance Insights is your first stop in any performance investigation. Learn to read the DB Load chart and wait event breakdown before looking at anything else.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| DB Load | Average Active Sessions - how many sessions were actively working at any moment |
| vCPU line | The horizontal line on the PI dashboard showing your instance's CPU capacity |
| Wait event | What a session is waiting on when not actively using CPU |
| Top SQL | Queries contributing most DB Load (not necessarily the slowest individual queries) |
| DBI Resource ID | Internal PI identifier (format: db-XXXX). Different from the instance ID |
| Normalization | PI replaces literal values with $1, $2 to group similar queries together |
| AAS | Average Active Sessions - the unit of measurement for DB Load |

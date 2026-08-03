# Build 02 - CloudWatch Database Insights (formerly Performance Insights)

**Time:** 45 minutes
**Goal:** Enable Database Insights, read the DB Load dashboard, identify top SQL and wait events, use fleet-level monitoring, view SQL execution plans, and query metrics programmatically via the API.
**Prerequisites:** RDS PostgreSQL or Aurora PostgreSQL instance. `$DB_INSTANCE_ID`, `$REGION` set. psql access to the database.

---

## What Changed: Performance Insights is now Database Insights

AWS renamed Performance Insights to **CloudWatch Database Insights** in late 2025. The PI console redirects to the new Database Insights experience starting June 30, 2026.

What is different:
- **Two tiers:** Standard (free, 24-hour retention) and Advanced (paid, up to 2 years retention)
- **Fleet dashboard:** See all your databases in one view - no more clicking into each instance
- **SQL execution plans:** View EXPLAIN plans directly in the console (Advanced tier)
- **Cross-account monitoring:** Monitor databases across AWS accounts from a single pane
- **CloudWatch integration:** Metrics, alarms, and dashboards all in one place

The core concepts (DB Load, wait events, top SQL) are the same. The API calls changed from `aws pi` to `aws cloudwatch`.

---

## Step 1 - Understand Standard vs Advanced Tiers

Before enabling anything, know the difference:

| Feature | Standard (Free) | Advanced (Paid) |
|---------|-----------------|-----------------|
| Retention | 24 hours | 1 month to 2 years |
| DB Load graph | Yes | Yes |
| Top SQL | Yes (normalized text only) | Yes (full text + execution plans) |
| Wait events | Yes | Yes |
| SQL execution plans | No | Yes |
| Fleet dashboard | Yes | Yes |
| Cross-account | No | Yes |
| OS-level metrics | Basic (5 CloudWatch metrics) | Enhanced (50+ OS metrics at 1-second granularity) |
| Pricing | Free | ~$22.50/month per vCPU |

**For this lab:** Start with Standard (free). You can upgrade to Advanced later without downtime.

---

## Step 2 - Enable Database Insights via Console

1. Open the [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/).
2. In the left menu, click **Database Insights**.
3. Click **Enable Database Insights** (or go to RDS > Databases > your instance > Modify).
4. Select your tier:
   - **Standard** for free 24-hour monitoring
   - **Advanced** for extended retention and execution plans
5. If you chose Advanced, set the **Retention period** (1 month to 2 years).
6. Click **Save changes**.

You can also enable it from the RDS console during instance creation or modification - the setting is under the **Monitoring** section (formerly called "Performance Insights").

---

## Step 3 - Enable Database Insights via CLI

### Standard tier (free)

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately \
  --region "$REGION"
```

Each flag explained:
- `--enable-performance-insights`: Turns on Database Insights (the CLI flag name has not changed yet).
- `--performance-insights-retention-period 7`: Keep 7 days of data. Standard tier supports up to 7 days free (use `7`). Advanced tier supports 31 to 731 days.
- `--apply-immediately`: Do not wait for the maintenance window.

> **Note:** The CLI still uses the `performance-insights` flag names. AWS has not renamed them yet. The Console calls it "Database Insights" but the API/CLI calls it "Performance Insights." They are the same feature.

### Advanced tier (paid)

```bash
aws rds modify-db-instance \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --enable-performance-insights \
  --performance-insights-retention-period 731 \
  --apply-immediately \
  --region "$REGION"
```

The only difference is the retention period. Any value above 7 automatically puts you on the Advanced tier.

Wait for the instance to be available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

---

## Step 4 - Generate Load So You Have Data to Look At

Connect to your database and generate some activity:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

Create a test table:

```sql
CREATE TABLE IF NOT EXISTS perf_test (
    id SERIAL PRIMARY KEY,
    user_id INT,
    amount NUMERIC(12,2),
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

Insert a large amount of data:

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

Run a slow query (no index, sequential scan):

```sql
SELECT count(*), status
FROM perf_test
WHERE amount > 500
GROUP BY status
ORDER BY count(*) DESC;
```

Run it several times:

```sql
\watch 2
```

Wait 30 seconds, then press Ctrl+C to stop.

---

## Step 5 - Navigate the Database Insights Dashboard

1. Go to the [CloudWatch Console](https://console.aws.amazon.com/cloudwatch/).
2. In the left menu, click **Database Insights**.
3. You will see the **Fleet view** first - a list of all your RDS/Aurora instances with their current DB Load.
4. Click your instance to drill into the detail view.

The detail dashboard has three main sections:

**Top section - Counter metrics:**
- Shows standard CloudWatch metrics overlaid with Database Insights data
- Toggle between metrics using the dropdown (CPU, connections, IOPS, etc.)

**Middle section - DB Load graph:**
- The most important chart. Shows average active sessions (AAS) over time.
- The horizontal red line is your vCPU count - your capacity ceiling
- The colored bands show which wait event type contributed to load
- Hover over any point to see the breakdown

**Bottom section - Top SQL / Top waits / Top hosts / Top users:**
- Shows the SQL statements, wait events, clients, and users contributing most to DB Load

Look for these things in your dashboard:
- Is DB Load above the vCPU line? (overloaded database)
- What color dominates the DB Load graph? (IO = storage problem, CPU = query problem, Lock = contention)
- Which SQL statement contributes most DB Load?

---

## Step 6 - Use the Fleet Dashboard

The fleet dashboard is new in Database Insights. It shows all your databases in one view.

1. In CloudWatch, click **Database Insights** in the left menu.
2. You see a table of all your RDS and Aurora instances.
3. Each row shows:
   - Instance name
   - Engine and version
   - Current DB Load (as a bar chart)
   - Top wait event
   - Status

This is useful when you manage many databases and need to quickly identify which one is having a problem. In Performance Insights, you had to click into each instance individually.

**Filter by engine:**
Click the filter dropdown to show only PostgreSQL instances, or only Aurora instances.

**Sort by DB Load:**
Click the "DB Load" column header to sort by current load. The hottest database appears at the top.

---

## Step 7 - Drill Into a Specific Query

1. In the **Top SQL** table at the bottom, click on the query you inserted data with or the sequential scan query.
2. You will see:
   - **DB Load by wait**: How this query's load breaks down by wait event
   - **Executions per minute**: How often it ran
   - **Average latency**: Average duration
   - **Rows examined per execution**: How many rows it scanned

3. Click **View more details** to see the full query text.

> **Concept:** Database Insights normalizes queries - it replaces literal values with `$1`, `$2`, etc. This means 1,000 different `SELECT ... WHERE id = 42` type queries all appear as one normalized query. This is exactly what you want: you see the pattern, not individual parameter values.

---

## Step 8 - View SQL Execution Plans (Advanced Tier Only)

If you enabled the Advanced tier, you can view EXPLAIN plans directly in the console.

1. In the **Top SQL** table, click a query.
2. Click the **Execution plans** tab.
3. You see the plan PostgreSQL chose for this query - same information as running `EXPLAIN (ANALYZE)` in psql.
4. Look for:
   - **Seq Scan** on large tables (missing index)
   - **Nested Loop** with high row estimates (inefficient join)
   - **Sort** with high cost (missing index for ORDER BY)

This is extremely useful during incidents. You do not need to connect to the database to see what plan a slow query is using - you can see it directly in CloudWatch.

> **Note:** Execution plans are captured automatically for top SQL statements. You do not need to run EXPLAIN manually. The plan shown is the actual plan used during execution, not an estimate.

---

## Step 9 - Understand Wait Event Categories

In the DB Load graph, expand the legend and click on different wait event types to understand what they mean.

| Color | Wait Category | Common Wait Events |
|-------|--------------|-------------------|
| Red | IO | DataFileRead, WALWrite, BufFileRead |
| Orange | Lock | relation, tuple, transactionid |
| Yellow | LWLock | buffer_mapping, WALWrite |
| Blue | CPU | (no specific wait event - active on CPU) |
| Purple | Client | ClientRead, ClientWrite |
| Gray | Other | Various |

When you ran the sequential scan above, you likely see `IO:DataFileRead` (reading from disk) and `CPU` (computing the aggregate).

---

## Step 10 - Query Database Insights Data via API

The PI API lets you extract data programmatically for custom dashboards or automated analysis.

Get your DBI resource ID (different from the instance ID):

```bash
aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
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

Expected output (yours will differ):
```json
{
    "AlignedStartTime": "2024-01-31T11:00:00+00:00",
    "AlignedEndTime": "2024-01-31T12:00:00+00:00",
    "Identifier": "db-ABCDEF1234567890ABCDEF",
    "MetricList": [
        {
            "Key": {"Metric": "db.load.avg"},
            "DataPoints": [
                {"Timestamp": "2024-01-31T11:00:00+00:00", "Value": 0.18},
                {"Timestamp": "2024-01-31T11:01:00+00:00", "Value": 0.22},
                ...
            ]
        }
    ]
}
```

> **Note:** The `aws pi` CLI commands still work. AWS has not deprecated them. You can also use `aws cloudwatch get-metric-data` to query Database Insights metrics through the CloudWatch API - same data, different access path.

---

## Step 11 - Get Top SQL via API

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

---

## Step 12 - Get Top Wait Events via API

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
                {"Timestamp": "...", "Value": 1.42}
            ]
        }
    ]
}
```

---

## Step 13 - Enable pg_stat_statements for Richer Top SQL

Database Insights Top SQL is more detailed when `pg_stat_statements` is loaded. Verify it is enabled:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name "$(aws rds describe-db-instances --db-instance-identifier "$DB_INSTANCE_ID" --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" --output text --region "$REGION")" \
  --query "Parameters[?ParameterName=='shared_preload_libraries'].ParameterValue" \
  --output text \
  --region "$REGION"
```

Expected output (yours will differ):
```
pg_stat_statements
```

If `pg_stat_statements` is not listed, you will add it in Build 05.

---

## Step 14 - Cross-Account Monitoring (Advanced Tier)

If you manage databases across multiple AWS accounts, Database Insights Advanced tier supports cross-account monitoring through CloudWatch.

**Setup overview:**
1. Create a **monitoring account** (the account where you view dashboards)
2. In each **source account**, create an IAM role that trusts the monitoring account
3. In the monitoring account, add the source accounts under **CloudWatch > Settings > Cross-account cross-region**
4. Database Insights fleet dashboard now shows databases from all linked accounts

This is a significant advantage over the old Performance Insights, which required you to log into each account separately.

> **Note:** Cross-account setup is an account-level configuration, not a database-level one. You set it up once and all databases in the linked accounts appear in the fleet view.

---

## Cleanup

To remove the test data when you are done:

```sql
DROP TABLE IF EXISTS perf_test;
```

---

## Summary

You have:
- Enabled Database Insights (the replacement for Performance Insights)
- Understood the difference between Standard (free) and Advanced (paid) tiers
- Used the fleet dashboard to see all databases at once
- Generated load and observed it in the DB Load dashboard
- Drilled into wait events and top SQL
- Viewed SQL execution plans in the console (Advanced tier)
- Queried metrics programmatically via the AWS CLI

Database Insights is your first stop in any performance investigation. Learn to read the DB Load chart and wait event breakdown before looking at anything else.

---

## Migration from Performance Insights

If you are currently using Performance Insights:
- **No migration needed.** Database Insights replaces PI automatically. Your existing retention settings carry over.
- The PI console URL redirects to the Database Insights console after June 30, 2026.
- The `aws pi` CLI commands continue to work - same data, same API.
- Existing CloudWatch alarms based on PI metrics continue to fire.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| DB Load | Average Active Sessions - how many sessions were working at any moment |
| vCPU line | DB Load target - exceeding it means the database is saturated |
| Wait event | What a session is waiting on when not using CPU |
| Top SQL | Queries contributing most DB Load (not necessarily the slowest individual queries) |
| DBI Resource ID | Internal identifier for PI API calls (format: db-XXXX, different from instance ID) |
| Normalization | Replaces literal values with $1, $2 to group similar queries together |
| Standard tier | Free, 24-hour retention, basic monitoring |
| Advanced tier | Paid (~$22.50/vCPU/mo), up to 2-year retention, execution plans, cross-account |
| Fleet dashboard | Single view of all databases - new in Database Insights |

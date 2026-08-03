# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 02: Aurora Serverless v2 Capacity Design and Troubleshooting

**Objective:** Create an Aurora Serverless v2 cluster, configure ACU ranges for a realistic workload, monitor scaling events in CloudWatch, troubleshoot scaling delays, and analyze the cost break-even versus provisioned instances.
**Time:** 40 minutes
**Prerequisites:** Tier 1 VPC with at least two subnets in different availability zones. Understanding of Aurora cluster architecture.
**Infrastructure:** You will create a new Aurora PostgreSQL Serverless v2 cluster and tear it down at the end.

---

## 1. Understand ACU Ranges Before Creating Anything

Do not create the cluster without thinking through the ACU range first. Changing the range later is online, but starting with a reasonable baseline is faster.

**Use this sizing heuristic:**

1. What is your expected peak connection count? Divide by 100 to get a rough minimum ACU floor for connection handling. A database expecting 500 concurrent connections needs at least 5 ACUs at peak.
2. What is your baseline steady-state workload? If queries are mostly indexed reads, 2 ACUs handles a lot. Write-heavy or analytical workloads need more.
3. Set minimum to the ACU value that handles your expected steady-state load.
4. Set maximum to 20-30% above your expected peak load.

For this lab, you will use min=0.5, max=8. This is a reasonable development/staging range and keeps costs low.

---

## 2. Create an Aurora Serverless v2 Cluster

### Console

1. Go to the **RDS** console.
2. Click **Create database**.
3. Under **Choose a database creation method**, select **Standard create**.
4. Under **Engine options**, select **Aurora (PostgreSQL Compatible)**.
5. Under **Engine version**, select the latest Aurora PostgreSQL version available (e.g., Aurora PostgreSQL 16.x).
6. Under **Templates**, select **Dev/Test**.
7. Under **Settings**:
   - **DB cluster identifier**: `tier7-asv2-lab`
   - **Master username**: `postgres`
   - **Master password**: Set a password and note it.
8. Under **Instance configuration**:
   - Click **Serverless**.
   - Set **Minimum Aurora capacity units**: `0.5`
   - Set **Maximum Aurora capacity units**: `8`
9. Under **Availability and durability**, select **Don't create an Aurora Replica** (for cost in this lab). In production, always enable a replica.
10. Under **Connectivity**:
    - Select your VPC from Tier 1.
    - Select your DB subnet group.
    - Under **Public access**, select **Yes** (for lab access convenience - not for production).
    - Under **VPC security group**, select your existing RDS security group or create one with port 5432 open to your IP.
11. Leave all other settings at defaults.
12. Click **Create database**.

Cluster creation takes approximately 5-10 minutes.

### CLI

**Step 1.** Create the DB cluster:

```bash
aws rds create-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --engine aurora-postgresql \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password [YOUR-PASSWORD] \
  --db-subnet-group-name [YOUR-SUBNET-GROUP] \
  --vpc-security-group-ids [YOUR-SECURITY-GROUP-ID] \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=8 \
  --region [REGION]
```

The `--serverless-v2-scaling-configuration` flag accepts min and max ACU values. This is the parameter that turns on Serverless v2 mode for the cluster.

**Step 2.** Create the Serverless v2 writer instance inside the cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier tier7-asv2-writer \
  --db-cluster-identifier tier7-asv2-lab \
  --engine aurora-postgresql \
  --db-instance-class db.serverless \
  --region [REGION]
```

The `--db-instance-class db.serverless` is the special class designation for Serverless v2 instances. This is what tells the instance to use ACUs instead of a fixed instance size.

**Step 3.** Wait for both cluster and instance to become available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier tier7-asv2-writer \
  --region [REGION]
```

The `aws rds wait` command polls until the instance reaches `available` state. This blocks for up to 30 minutes. Control returns when the instance is ready.

---

## 3. Get the Cluster Endpoint and Connect

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier tier7-asv2-lab \
  --region [REGION] \
  --query 'DBClusters[0].{Endpoint:Endpoint,Port:Port,Status:Status}' \
  --output table
```

Expected output:
```
-----------------------------------------------------------------
|                     DescribeDBClusters                        |
+-----------+---------------------------------------------------+
|  Endpoint |  tier7-asv2-lab.cluster-xxxxxxxx.[REGION].rds.amazonaws.com |
|  Port     |  5432                                             |
|  Status   |  available                                        |
+-----------+---------------------------------------------------+
```

Connect using psql:

```bash
psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres
```

---

## 4. Generate Load and Observe ACU Scaling

You will create a simple table and generate concurrent connections to trigger scaling up.

### Step 1. Create a test schema

Connect to the cluster, then run:

```sql
CREATE TABLE load_test (
  id SERIAL PRIMARY KEY,
  payload TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO load_test (payload)
SELECT repeat('x', 1000)
FROM generate_series(1, 10000);
```

The `generate_series(1, 10000)` function generates 10,000 rows inline. The `repeat('x', 1000)` creates a 1,000-character string for each row to give the table some weight.

### Step 2. Run a concurrent load test

Open a second terminal window. Run this to simulate parallel queries:

```bash
for i in {1..20}; do
  psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres \
    -c "SELECT count(*), avg(length(payload)) FROM load_test WHERE id % 100 = $i;" &
done
wait
echo "Load test complete"
```

The `&` at the end of each psql command runs it in the background. The `wait` command waits for all background jobs to finish before printing the completion message. This fires 20 concurrent queries simultaneously.

### Step 3. Check the ACU metric

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region [REGION]
```

The `ServerlessDatabaseCapacity` metric reports the current ACU value of the Serverless v2 instance. `--statistics Maximum` shows the peak within each period. You should see the value climb from your minimum during the load test.

Expected output (yours will differ):
```json
{
    "Datapoints": [
        {"Timestamp": "...", "Maximum": 0.5, "Unit": "None"},
        {"Timestamp": "...", "Maximum": 1.5, "Unit": "None"},
        {"Timestamp": "...", "Maximum": 3.0, "Unit": "None"},
        {"Timestamp": "...", "Maximum": 2.0, "Unit": "None"}
    ]
}
```

---

## 5. Set Up CloudWatch Dashboard for Serverless v2 Monitoring

### Console

1. Go to **CloudWatch** in the AWS Console.
2. Click **Dashboards** > **Create dashboard**.
3. Name it `tier7-serverless-monitoring`.
4. Click **Create dashboard**.
5. Click **Add widget** > **Line graph**.
6. Click **Browse** under **Metrics**.
7. Navigate to **RDS** > **Per-Database Metrics**.
8. Search for `ServerlessDatabaseCapacity`.
9. Select your cluster identifier.
10. Click **Create widget**.
11. Repeat to add widgets for: `ACUUtilization`, `CPUUtilization`, `DatabaseConnections`.

### CLI - Create the dashboard via JSON

```bash
aws cloudwatch put-dashboard \
  --dashboard-name tier7-serverless-monitoring \
  --dashboard-body '{
    "widgets": [
      {
        "type": "metric",
        "properties": {
          "title": "ACU Capacity",
          "metrics": [
            ["AWS/RDS", "ServerlessDatabaseCapacity", "DBClusterIdentifier", "tier7-asv2-lab"]
          ],
          "period": 60,
          "stat": "Maximum",
          "view": "timeSeries"
        }
      },
      {
        "type": "metric",
        "properties": {
          "title": "ACU Utilization %",
          "metrics": [
            ["AWS/RDS", "ACUUtilization", "DBClusterIdentifier", "tier7-asv2-lab"]
          ],
          "period": 60,
          "stat": "Maximum",
          "view": "timeSeries"
        }
      }
    ]
  }' \
  --region [REGION]
```

---

## 6. Troubleshoot Scaling Delays

### Scenario: Queries are slow after an idle period

This happens when the instance has scaled down toward minimum ACU and the first queries after the idle period hit a cold instance.

**Diagnose:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Minimum \
  --region [REGION]
```

If you see `Minimum` values at or near your configured minimum ACU, the instance is scaling down aggressively. The first queries after the lull are slower because the instance needs to scale up.

**Fix option 1: Raise the minimum ACU.**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=8 \
  --apply-immediately \
  --region [REGION]
```

Raising minimum to 2 ACUs means the instance never drops below that. The first post-idle query will be served by an already-warm 2-ACU instance.

**Fix option 2: Send a keepalive query.**

Add a simple query to your application's health check that runs every 60 seconds. Even `SELECT 1` is enough to keep the instance from scaling below the minimum active threshold.

### Scenario: Queries are slow during traffic spikes (capacity ceiling hit)

**Diagnose:**

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ACUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum \
  --region [REGION]
```

If `ACUUtilization` reaches or exceeds 100%, the instance was at its maximum ACU ceiling. It could not scale further to handle the load.

**Fix: Raise the maximum ACU:**

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=16 \
  --apply-immediately \
  --region [REGION]
```

Maximum ACU changes take effect within minutes without any instance restart.

---

## 7. Cost Analysis: Provisioned vs Serverless v2 Break-Even

### The formula

- **Serverless v2 cost** = Average ACUs * $0.12 per ACU-hour * hours
- **Provisioned cost** = Fixed hourly rate * hours

Prices vary by region. Check the RDS pricing page for your region.

### Example calculation

Suppose your Serverless v2 cluster averages 4 ACUs over a month:

```
Serverless v2:  4 ACUs * $0.12/ACU-hour * 730 hours = $350.40/month
db.t3.large:    $0.182/hour * 730 hours              = $132.86/month
db.r6g.large:   $0.260/hour * 730 hours              = $189.80/month
```

At sustained 4 ACUs, Serverless v2 is more expensive than a provisioned db.r6g.large.

But if your average ACUs are much lower (e.g., 1.5 ACU average due to off-hours quietness):

```
Serverless v2:  1.5 ACUs * $0.12/ACU-hour * 730 hours = $131.40/month
db.t3.large:    $0.182/hour * 730 hours                = $132.86/month
```

At 1.5 average ACUs, Serverless v2 is nearly equivalent in cost to db.t3.large but can burst much higher when needed.

### How to calculate your average ACUs from real data

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 86400 \
  --statistics Average \
  --region [REGION]
```

The `--period 86400` flag aggregates into a single 24-hour average. Multiply by your hourly rate to estimate daily cost.

**Break-even rule of thumb:**
If your average sustained ACUs exceed the ACU equivalent of a provisioned instance (most r-class instances deliver roughly 8-16 "effective ACU" of throughput), provisioned is cheaper. Serverless v2 wins when you have high variability - significant difference between peak and off-peak.

---

## 8. Tear Down

```bash
aws rds delete-db-instance \
  --db-instance-identifier tier7-asv2-writer \
  --skip-final-snapshot \
  --region [REGION]
```

Wait for the instance to be deleted:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier tier7-asv2-writer \
  --region [REGION]
```

Then delete the cluster:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --skip-final-snapshot \
  --region [REGION]
```

The `--skip-final-snapshot` flag deletes without taking a backup. Only use this for lab clusters you do not need to recover.

---

## Summary

What you did in this lab:

- Designed ACU ranges before provisioning.
- Created an Aurora Serverless v2 cluster with a writer instance.
- Generated concurrent load and observed the `ServerlessDatabaseCapacity` metric respond.
- Built a CloudWatch dashboard for ongoing monitoring.
- Diagnosed and fixed both cold-start and ceiling-hit scaling scenarios.
- Calculated the cost break-even between Serverless v2 and provisioned instances.

**Key things to remember:**
- Minimum ACU is your baseline cost floor. Minimum 0 allows scale-to-zero (zero compute cost).
- Maximum ACU is your cost ceiling. Do not set it higher than your wallet allows.
- `ACUUtilization` pegged at 100% means you need to raise the maximum.
- Sustained workloads often favor provisioned instances. Serverless v2 wins on variable or bursty workloads.

---

## 9. Scale-to-Zero (Auto-Pause)

Starting in 2024, Aurora Serverless v2 supports scaling to 0 ACU. When the database has no active connections for a configurable idle period, Aurora pauses the compute layer entirely - you pay only for storage.

### When to Use Scale-to-Zero

- Development and staging databases that sit idle overnight and on weekends
- Internal tools used only during business hours
- Proof-of-concept databases that are accessed occasionally
- Disaster recovery secondaries that are rarely queried

### Enable Scale-to-Zero

Set the minimum ACU to 0:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier tier7-asv2-lab \
  --serverless-v2-scaling-configuration MinCapacity=0,MaxCapacity=8 \
  --apply-immediately \
  --region [REGION]
```

`MinCapacity=0` enables scale-to-zero. When all connections drop and the idle timeout expires, Aurora pauses the instance.

### How Scale-to-Zero Works

```
Active state (serving queries):
  Instance is at 0.5+ ACU, responding normally

All connections close:
  Idle timer starts (configurable, default ~5 minutes)

Idle timeout expires:
  Instance scales to 0 ACU (paused)
  You pay $0 for compute, storage charges continue

New connection arrives:
  Instance resumes from 0 to minimum active ACU
  Resume time: typically 10-25 seconds
  First query experiences this delay
```

### Observe the Pause and Resume

After setting MinCapacity=0, disconnect all sessions from the cluster:

```bash
# Verify no active connections
psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres \
  -c "SELECT count(*) FROM pg_stat_activity WHERE state != 'idle';"
```

Wait 5-10 minutes. Then check the ACU metric:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=tier7-asv2-lab \
  --start-time $(date -u -d '15 minutes ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-15M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Minimum \
  --region [REGION]
```

If you see `Minimum: 0`, the instance has paused.

Now reconnect and measure the resume time:

```bash
time psql -h [CLUSTER-ENDPOINT] -U postgres -d postgres \
  -c "SELECT 1;"
```

Expected output (yours will differ):
```
 ?column?
----------
        1
(1 row)

real    0m15.234s
```

The ~15 second delay is the resume time. Subsequent queries will be fast.

### Cold Start Mitigation

If 10-25 seconds of resume time is not acceptable for your use case:

1. **Use MinCapacity=0.5 instead of 0**: The instance never fully pauses. First-query latency stays under 1 second. Cost: ~$0.06/hour ($44/month) even when idle.

2. **Send a periodic keepalive**: A cron job that runs `SELECT 1` every 3 minutes prevents the pause entirely. This defeats the purpose of scale-to-zero but eliminates cold starts.

3. **Use a connection pooler**: RDS Proxy can queue incoming connections while the instance resumes, returning a connection once the database is available. The application sees higher latency but not an error.

### Cost Impact

```
Scale-to-zero (MinCapacity=0, idle 16 hours/day):
  8 hrs active * 2 ACU avg * $0.12/ACU-hr = $0.192/day
  16 hrs paused * $0 = $0
  Monthly: $0.192 * 30 = $57.60 (compute only)

Always-on (MinCapacity=0.5):
  24 hrs * 0.5 ACU min * $0.12/ACU-hr = $1.44/day
  Monthly: $1.44 * 30 = $43.20 (minimum, even idle)
  + actual usage during active hours
```

For databases that are idle most of the time, scale-to-zero can save 50-80% on compute costs.

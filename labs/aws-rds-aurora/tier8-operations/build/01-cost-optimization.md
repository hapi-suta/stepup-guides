# Tier 8 - Build Guide 01: Cost Optimization

**Objective:** Analyze and optimize RDS/Aurora costs using I/O-Optimized storage selection, Reserved Instance planning, Graviton migration analysis, Serverless v2 cost modeling, and Cost Explorer right-sizing recommendations.
**Time:** 40 minutes
**Level:** Expert
**infra_required:** Partial - Cost Explorer and RI analysis are console-only. You need a running RDS or Aurora instance for some sections.
**Prerequisites:** An AWS account with at least one running RDS or Aurora PostgreSQL instance. Cost Explorer enabled (24-48 hours of billing data helps but is not required to explore the UI).

---

## 1. I/O-Optimized vs Aurora Standard Storage

Aurora offers two storage billing modes. Choosing the wrong one is one of the most common sources of unnecessary cost on Aurora clusters.

### Understanding the pricing model

**Aurora Standard:**
- Storage: ~$0.10 per GB-month
- I/O: $0.20 per 1 million requests

**Aurora I/O-Optimized:**
- Storage: ~$0.225 per GB-month (roughly 2.25x Standard)
- I/O: $0.00 - zero per-I/O charge

The break-even point is when I/O charges in Standard mode equal the additional storage cost in I/O-Optimized mode. AWS estimates this occurs when I/O costs exceed approximately 25% of total Aurora spend. In practice, for a typical OLTP workload doing sustained heavy writes, you cross this threshold quickly.

### How to identify your I/O charges (Console)

1. Open the AWS console and navigate to **Billing and Cost Management**.
2. Select **Cost Explorer** in the left navigation.
3. Set the date range to the previous full month.
4. In the **Filter** panel on the right, set **Service** to `Relational Database Service`.
5. In the **Group by** dropdown, select **Usage type**.
6. Look for line items containing `Aurora:StorageIOUsage`. This is your Aurora I/O charge.

If `Aurora:StorageIOUsage` is more than 25% of your total RDS line on the bill, analyze whether I/O-Optimized would reduce your total cost.

### Calculate the break-even (CLI)

Run this command to see your Aurora cluster storage configuration:

```bash
aws rds describe-db-clusters \
  --query 'DBClusters[?Engine==`aurora-postgresql`].[DBClusterIdentifier,StorageType,AllocatedStorage]' \
  --output table \
  --region [REGION]
```

`StorageType` will be `aurora` (Standard) or `aurora-iopt1` (I/O-Optimized).

Expected output (yours will differ):
```
--------------------------------------------------
|           DescribeDBClusters                   |
+-------------------------+----------+-----------+
|  prod-aurora-cluster    | aurora   |    500    |
|  analytics-cluster      | aurora   |    200    |
+-------------------------+----------+-----------+
```

### Switch an Aurora cluster to I/O-Optimized (Console)

**Warning:** This change takes effect immediately and affects billing. Analyze cost before switching.

1. Open the RDS console.
2. Select **Databases** in the left navigation.
3. Click the Aurora cluster identifier (not an individual instance).
4. Click **Modify**.
5. Scroll to the **Storage** section.
6. Change **Storage type** from `Aurora Standard` to `Aurora I/O Optimized`.
7. Click **Continue**, review the change summary, and apply immediately or during the next maintenance window.

### Switch to I/O-Optimized (CLI)

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [CLUSTER-IDENTIFIER] \
  --storage-type aurora-iopt1 \
  --apply-immediately \
  --region [REGION]
```

`--apply-immediately` applies the change now rather than waiting for the maintenance window. For storage type changes, there is no downtime - the change applies transparently.

---

## 2. Reserved Instance Analysis

Reserved Instances (RIs) reduce On-Demand costs by 30-60% for a 1 or 3-year commitment. The analysis process is the same whether you are evaluating existing instances or planning new ones.

### Get your current On-Demand instance inventory (CLI)

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,Engine,MultiAZ,DBInstanceStatus]' \
  --output table \
  --region [REGION]
```

Expected output (yours will differ):
```
----------------------------------------------------------
|              DescribeDBInstances                       |
+---------------------+---------------+-----+-----------+
|  prod-pg-primary    | db.r6g.2xlarge| ... | available |
|  analytics-reader   | db.r6g.xlarge | ... | available |
+---------------------+---------------+-----+-----------+
```

### Check current Reserved Instance coverage (Console)

1. Open the RDS console.
2. Select **Reserved instances** in the left navigation.
3. Review existing reservations - note instance class, multi-AZ, expiration dates.

### View RI pricing (CLI)

Use this command to see current RI prices for a specific instance class:

```bash
aws rds describe-reserved-db-instances-offerings \
  --db-instance-class db.r6g.2xlarge \
  --product-description "postgresql" \
  --duration 31536000 \
  --offering-type "All Upfront" \
  --region [REGION] \
  --query 'ReservedDBInstancesOfferings[*].[OfferingId,DBInstanceClass,Duration,FixedPrice,UsagePrice,MultiAZ]' \
  --output table
```

`--duration 31536000` is 1 year in seconds. Use `94608000` for 3-year.
`--offering-type` options: `All Upfront`, `Partial Upfront`, `No Upfront`.
`--product-description "postgresql"` filters for PostgreSQL engine only.

Expected output (yours will differ):
```
---------------------------------------------------------------------------
|       DescribeReservedDBInstancesOfferings                              |
+---------+-----------------+----------+-----------+-----------+----------+
|  abc123 | db.r6g.2xlarge  | 31536000 |  5534.00  |  0.0      | False    |
|  def456 | db.r6g.2xlarge  | 31536000 |  3122.00  |  0.0      | True     |
+---------+-----------------+----------+-----------+-----------+----------+
```

`MultiAZ: True` means the RI covers a Multi-AZ deployment (higher price, covers both primary and standby). `MultiAZ: False` covers a single instance.

### Purchase a Reserved Instance (CLI)

After you confirm the offering ID you want:

```bash
aws rds purchase-reserved-db-instances-offering \
  --reserved-db-instances-offering-id [OFFERING-ID] \
  --db-instance-count 1 \
  --region [REGION]
```

`--db-instance-count` sets how many identical instances this reservation covers.

### RI Savings Calculation

For a `db.r6g.2xlarge` running 24/7:
- On-Demand: ~$0.996/hour = ~$8,725/year
- 1-year All Upfront RI: ~$5,534 = saving ~$3,191/year (37%)
- 3-year All Upfront RI: ~$3,888 = saving ~$4,837/year over 3 years

Break-even on 1-year RI occurs at month 7 (after 7 months, the prepaid cost is recovered vs On-Demand).

---

## 3. Graviton vs Intel Cost/Performance Analysis

### Identify Intel instances in your fleet (CLI)

```bash
aws rds describe-db-instances \
  --query 'DBInstances[?contains(DBInstanceClass, `m5`) || contains(DBInstanceClass, `r5`) || contains(DBInstanceClass, `m6i`) || contains(DBInstanceClass, `r6i`)].[DBInstanceIdentifier,DBInstanceClass]' \
  --output table \
  --region [REGION]
```

This filters for common Intel-based instance families (`m5`, `r5`, `m6i`, `r6i`). The Graviton equivalents are `m6g`/`r6g` (Graviton 2) and `m7g`/`r7g` (Graviton 3).

### Price comparison

Check the current price difference for equivalent classes:

```bash
aws rds describe-reserved-db-instances-offerings \
  --product-description "postgresql" \
  --duration 31536000 \
  --offering-type "No Upfront" \
  --region [REGION] \
  --query 'ReservedDBInstancesOfferings[?contains(DBInstanceClass, `r6`) ].[DBInstanceClass,MultiAZ,UsagePrice]' \
  --output table | sort
```

Typical finding: `db.r6g.2xlarge` (Graviton) costs approximately 10% less per hour than `db.r6i.2xlarge` (Intel) for equivalent performance.

### Migrate to Graviton (Console)

Graviton migration requires creating a new instance - you cannot change the instance class directly from Intel to Graviton within the same generation family on existing instances.

**Method 1: Snapshot and restore (requires downtime)**

1. Take a final snapshot of the Intel instance.
2. Restore the snapshot to a new instance, selecting a Graviton instance class.
3. Verify data integrity.
4. Update DNS or application connection string.
5. Delete the old instance.

**Method 2: Blue/Green Deployment (minimal downtime)**

1. Open the RDS console and select your Intel-based instance.
2. Select **Actions > Create Blue/Green Deployment**.
3. In the **Green environment** configuration, change the instance class to the Graviton equivalent (e.g., `db.r6g.2xlarge`).
4. Wait for the Green environment to sync.
5. Click **Switchover** to cut traffic to the new Graviton instance. Switchover typically completes in under 1 minute.

**Method 2: Blue/Green Deployment (CLI)**

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name intel-to-graviton-migration \
  --source [INSTANCE-ARN] \
  --target-db-instance-class db.r6g.2xlarge \
  --region [REGION]
```

After the Green environment is in sync status, initiate the switchover:

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier [BGD-IDENTIFIER] \
  --switchover-timeout 300 \
  --region [REGION]
```

`--switchover-timeout 300` means abort if switchover takes longer than 5 minutes.

---

## 4. Aurora Serverless v2 Cost Modeling

Serverless v2 charges per ACU-second. Before adopting it, model the cost against a comparable provisioned instance.

### Key metrics to gather before modeling

Run these commands against your existing provisioned instance to collect baseline metrics:

```bash
# Average CPU utilization over the last 7 days
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Average \
  --region [REGION]
```

On macOS, replace `date -u -d '7 days ago'` with `date -u -v-7d`.

```bash
# Average database connections over the last 7 days
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Average,Maximum \
  --region [REGION]
```

### Cost model calculation

**Serverless v2 pricing (us-east-1):** ~$0.12 per ACU-hour

1 ACU provides approximately 2 GB RAM and proportional CPU. A `db.r6g.2xlarge` has 64 GB RAM = approximately 32 ACUs.

If your workload runs at an average of 8 ACUs (25% utilization) and peaks at 32 ACUs:

- Average cost: 8 ACUs x $0.12/ACU-hour x 730 hours/month = $700/month
- Provisioned `db.r6g.2xlarge` On-Demand: ~$730/month

For this workload, Serverless v2 provides similar cost with automatic scaling. If average utilization drops to 15% (4-5 ACUs), Serverless v2 saves ~50%.

If average utilization is 80%+ consistently, provisioned is cheaper.

### Enable Serverless v2 on an Aurora cluster (Console)

1. Open the RDS console and select your Aurora PostgreSQL cluster.
2. Click **Add reader** or modify an existing writer instance.
3. Under **Instance configuration**, select **Serverless**.
4. Set **Minimum ACUs** (0.5 minimum, or higher to avoid cold start latency).
5. Set **Maximum ACUs** (cap this to control maximum cost).
6. Apply the change.

### Set Serverless v2 capacity limits (CLI)

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier [CLUSTER-IDENTIFIER] \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=32 \
  --apply-immediately \
  --region [REGION]
```

`MinCapacity=2` means the cluster never scales below 2 ACUs - this avoids cold start latency for production workloads.
`MaxCapacity=32` caps maximum cost. At $0.12/ACU-hour, 32 ACUs = $3.84/hour maximum compute cost.

---

## 5. Right-Sizing with Cost Explorer

### Enable Cost Explorer recommendations (Console)

Cost Explorer generates right-sizing recommendations automatically from the last 14 days of metric data. No configuration is required to view them.

1. Open **Billing and Cost Management**.
2. Select **Cost Explorer**.
3. Click **Rightsizing recommendations** in the left navigation.
4. Filter the service dropdown to **Amazon RDS**.

The recommendations show:
- Current instance type and estimated monthly cost
- Recommended instance type and estimated monthly cost
- Estimated monthly savings
- CPU and memory utilization percentiles that drove the recommendation

### Retrieve right-sizing recommendations (CLI)

```bash
aws ce get-rightsizing-recommendation \
  --service "AmazonRDS" \
  --region us-east-1
```

Note: Cost Explorer APIs are available only in `us-east-1` regardless of where your resources run.

Expected output (yours will differ):
```json
{
  "RightsizingRecommendations": [
    {
      "CurrentInstance": {
        "ResourceId": "arn:aws:rds:...",
        "InstanceDetails": {
          "RDSInstanceDetails": {
            "Family": "r6g",
            "InstanceType": "2xlarge",
            "Region": "us-east-1"
          }
        },
        "MonthlyCost": "730.00"
      },
      "RightsizingType": "Modify",
      "ModifyRecommendationDetail": {
        "TargetInstances": [
          {
            "EstimatedMonthlyCost": "365.00",
            "EstimatedMonthlySavings": "365.00"
          }
        ]
      }
    }
  ]
}
```

### Interpreting recommendations

Treat Cost Explorer recommendations as a starting point, not a final answer. Before downsizing:

1. Check the recommendation's utilization data against your knowledge of peak traffic patterns. 14 days may miss monthly or quarterly peaks.
2. Verify there is headroom for memory-intensive operations like VACUUM on large tables.
3. Test the smaller instance class in a staging environment under realistic load before applying to production.

---

## Summary

| Optimization | When to Use | Estimated Savings |
|--------------|-------------|------------------|
| I/O-Optimized | Aurora I/O > 25% of total Aurora spend | 20-40% on I/O-heavy workloads |
| Reserved Instances | Stable workloads running 24/7 for 1+ years | 30-60% vs On-Demand |
| Graviton migration | Intel-based instances with compatible workloads | 10-20% on compute |
| Serverless v2 | High-variability workloads, dev/test, multi-tenant SaaS | 30-50% on variable load |
| Right-sizing | Instances running below 40% average CPU | 20-50% on over-provisioned instances |

**Next:** [Guide 02 - Fleet Management](./02-fleet-management.md)

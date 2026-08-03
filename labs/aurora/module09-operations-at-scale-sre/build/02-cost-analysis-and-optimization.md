# BUILD 02: Cost Analysis and Optimization

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 60-75 minutes
**Level:** Intermediate

---

## Objective

Analyze the cost profile of your Aurora PostgreSQL cluster and apply the five cost optimization levers: storage pricing model, Reserved Instances, Graviton migration, Serverless v2 evaluation, and right-sizing. By the end of this guide, you will have a documented cost baseline and an optimization plan.

---

## Prerequisites

- Aurora PostgreSQL cluster `devops-lab-cluster` running
- AWS CLI configured with appropriate permissions
- Access to AWS Cost Explorer and Billing console

---

## Section 1: Establish Your Cost Baseline

Before optimizing, you need to know what you are currently spending.

### 1.1 Get Current Instance Details

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].{Engine:Engine,EngineVersion:EngineVersion,StorageType:StorageType,AllocatedStorage:AllocatedStorage,DBClusterMembers:DBClusterMembers[].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}}' \
    --output yaml
```

The `--query` flag uses JMESPath to extract only the fields you need from the full API response. This avoids scrolling through hundreds of lines of output.

Expected output (yours will differ):
```yaml
AllocatedStorage: 20
DBClusterMembers:
- Instance: devops-lab-cluster-instance-1
  IsWriter: true
- Instance: devops-lab-cluster-instance-2
  IsWriter: false
Engine: aurora-postgresql
EngineVersion: '16.4'
StorageType: aurora
```

### 1.2 Get Instance Class Details

```bash
aws rds describe-db-instances \
    --filters Name=db-cluster-id,Values=devops-lab-cluster \
    --query 'DBInstances[].{Instance:DBInstanceIdentifier,Class:DBInstanceClass,AZ:AvailabilityZone,Status:DBInstanceStatus}' \
    --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                      DescribeDBInstances                        |
+-----------+----------------------------+-----------+------------+
|    AZ     |          Class             | Instance  |  Status    |
+-----------+----------------------------+-----------+------------+
| us-east-1a| db.r6g.large              | devops-..1| available  |
| us-east-1b| db.r6g.large              | devops-..2| available  |
+-----------+----------------------------+-----------+------------+
```

### 1.3 Check Storage Configuration

```bash
aws rds describe-db-clusters \
    --db-cluster-identifier devops-lab-cluster \
    --query 'DBClusters[0].{StorageType:StorageType,IOOptimizedNextAllowedModificationTime:IOOptimizedNextAllowedModificationTime}' \
    --output yaml
```

The `IOOptimizedNextAllowedModificationTime` field tells you when you can next switch storage modes. If this field is empty, you have not switched recently and can switch at any time.

---

## Section 2: Analyze I/O Costs (Lever 1)

Aurora offers two storage billing modes. Choosing the wrong one is one of the most common sources of unnecessary cost.

### 2.1 Check Current I/O Volume

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name VolumeReadIOPs \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 86400 \
    --statistics Sum \
    --output table
```

The `--period 86400` flag aggregates data into 24-hour intervals (86400 seconds = 1 day). This gives you daily I/O totals.

Expected output (yours will differ):
```
---------------------------------------------
|          GetMetricStatistics              |
+-------------------------------------------+
||              Datapoints                 ||
|+-----------+----------------------------+|
||   Sum     |        Timestamp           ||
|+-----------+----------------------------+|
|| 45230000  | 2026-06-02T00:00:00Z       ||
|| 48120000  | 2026-06-03T00:00:00Z       ||
|+-----------+----------------------------+|
```

Now check write I/Os:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name VolumeWriteIOPs \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 86400 \
    --statistics Sum \
    --output table
```

### 2.2 Calculate the I/O Cost

Use this formula to estimate your monthly I/O cost:

```
Daily I/O = (VolumeReadIOPs + VolumeWriteIOPs) per day
Monthly I/O = Daily I/O * 30
Monthly I/O Cost = Monthly I/O / 1,000,000 * $0.20
```

For example, if your daily total is 90 million I/Os:
```
Monthly I/O = 90,000,000 * 30 = 2,700,000,000
Monthly I/O Cost = 2,700 * $0.20 = $540/month
```

### 2.3 Compare Standard vs I/O-Optimized

Check your storage volume:

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name VolumeBytesUsed \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Average \
    --output text
```

Calculate both storage costs:

```
Standard storage cost = Volume GB * $0.10/month
I/O-Optimized storage cost = Volume GB * $0.225/month

Standard total = Storage cost + I/O cost
I/O-Optimized total = I/O-Optimized storage cost + $0 (I/O is free)
```

If I/O costs exceed 25% of your total Aurora spend, I/O-Optimized is likely cheaper.

### 2.4 Switch to I/O-Optimized (If Beneficial)

If the analysis shows I/O-Optimized is cheaper:

```bash
aws rds modify-db-cluster \
    --db-cluster-identifier devops-lab-cluster \
    --storage-type aurora-iopt1 \
    --apply-immediately
```

The `--storage-type aurora-iopt1` flag switches to I/O-Optimized mode. The `--apply-immediately` flag applies the change without waiting for the next maintenance window.

This switch is online - no downtime is required.

---

## Section 3: Reserved Instance Analysis (Lever 2)

Reserved Instances reduce On-Demand costs by 30-60% for a 1 or 3-year commitment.

### 3.1 Check Current RI Coverage

```bash
aws rds describe-reserved-db-instances \
    --query 'ReservedDBInstances[].{ID:ReservedDBInstanceId,Class:DBInstanceClass,Count:DBInstanceCount,State:State,Duration:Duration,Offering:OfferingType}' \
    --output table
```

Expected output (yours will differ):
```
(empty table if no RIs purchased)
```

### 3.2 Get Available RI Offerings

```bash
aws rds describe-reserved-db-instances-offerings \
    --db-instance-class db.r6g.large \
    --product-description aurora-postgresql \
    --duration 31536000 \
    --query 'ReservedDBInstancesOfferings[].{ID:ReservedDBInstancesOfferingId,Class:DBInstanceClass,Duration:Duration,Price:FixedPrice,Hourly:UsagePrice,Offering:OfferingType}' \
    --output table
```

The `--duration 31536000` flag filters to 1-year terms (31536000 seconds = 365 days).

Expected output (yours will differ):
```
--------------------------------------------------------------------------------
|                   DescribeReservedDBInstancesOfferings                        |
+----------+--------------+----------+---------+---------+---------------------+
|  Class   |  Duration    | Hourly   |   ID    |  Price  |     Offering        |
+----------+--------------+----------+---------+---------+---------------------+
| db.r6g.l | 31536000     | 0.0      | abc-123 | 1234.00 | All Upfront         |
| db.r6g.l | 31536000     | 0.05     | def-456 |  650.00 | Partial Upfront     |
| db.r6g.l | 31536000     | 0.08     | ghi-789 |    0.00 | No Upfront          |
+----------+--------------+----------+---------+---------+---------------------+
```

### 3.3 Calculate RI Savings

Create a comparison document:

```bash
vi ~/sre-practice/ri-analysis.md
```

Add this content (adjust numbers based on your actual RI offerings):

```markdown
# Reserved Instance Analysis: devops-lab-cluster

## Current On-Demand Cost

| Instance | Class | On-Demand Rate | Monthly Cost | Annual Cost |
|----------|-------|---------------|-------------|------------|
| Writer | db.r6g.large | ~$0.252/hr | ~$184/mo | ~$2,208/yr |
| Reader | db.r6g.large | ~$0.252/hr | ~$184/mo | ~$2,208/yr |
| **Total** | | | **~$368/mo** | **~$4,416/yr** |

## 1-Year All Upfront RI

| Item | Value |
|------|-------|
| Upfront cost (2 instances) | ~$2,468 |
| Monthly cost | $0 |
| Annual cost | ~$2,468 |
| Annual savings | ~$1,948 (44%) |
| Break-even month | ~7 |

## Recommendation

Purchase 2x db.r6g.large 1-year All Upfront RIs if the cluster will run
for at least 7 more months. Savings: approximately $1,948/year.
```

Save and exit vi (`:wq`).

---

## Section 4: Graviton Migration Analysis (Lever 3)

AWS Graviton (ARM-based) instances offer 10-20% better price/performance than equivalent Intel instances.

### 4.1 Check Current Processor Type

```bash
aws rds describe-db-instances \
    --filters Name=db-cluster-id,Values=devops-lab-cluster \
    --query 'DBInstances[].{Instance:DBInstanceIdentifier,Class:DBInstanceClass}' \
    --output table
```

Instance classes with `g` in the family name (like `r6g`, `r7g`, `m7g`) are Graviton. Classes with `i` (like `r6i`, `m6i`) are Intel.

If your cluster already uses Graviton classes (e.g., `db.r6g.large`), you are already on the optimal processor. Skip to Section 5.

### 4.2 Compare Pricing (Intel vs Graviton)

If you are on Intel, check Graviton equivalents:

```bash
aws rds describe-orderable-db-instance-options \
    --engine aurora-postgresql \
    --engine-version 16.4 \
    --db-instance-class db.r7g.large \
    --query 'OrderableDBInstanceOptions[0].{Class:DBInstanceClass,Engine:Engine,MultiAZ:MultiAZCapable}' \
    --output yaml
```

This checks whether `db.r7g.large` is available for your engine version. If it returns results, migration is possible.

### 4.3 Graviton Migration Checklist

Before migrating, verify these items:

```bash
vi ~/sre-practice/graviton-checklist.md
```

```markdown
# Graviton Migration Checklist

## Pre-Migration
- [ ] Verify all extensions are available on Graviton (standard extensions are fine)
- [ ] Test workload on a Graviton staging instance
- [ ] Confirm no custom compiled extensions that need ARM builds
- [ ] Update RI purchases to Graviton instance classes

## Migration Method
- Use Blue/Green deployment for production (minimal downtime)
- Or: Create a snapshot and restore to a new Graviton cluster

## Post-Migration
- [ ] Verify query performance matches or exceeds Intel baseline
- [ ] Update monitoring dashboards with new instance identifiers
- [ ] Update RI purchase plan for Graviton classes
```

Save and exit vi (`:wq`).

---

## Section 5: Right-Sizing Analysis (Lever 4)

Right-sizing means matching your instance class to your actual workload.

### 5.1 Check CPU Utilization

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Average Maximum \
    --output table
```

The `--period 3600` flag gives hourly data points. Review a full week to catch peak traffic patterns.

### 5.2 Check Memory Pressure (Freeable Memory)

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeableMemory \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Average Minimum \
    --output table
```

The `Minimum` statistic shows the lowest freeable memory during each hour. If the minimum is consistently above 50% of total memory, the instance may be over-provisioned.

### 5.3 Check Connection Utilization

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Average Maximum \
    --output table
```

### 5.4 Apply the Right-Sizing Matrix

Use this decision matrix based on your findings:

| Avg CPU | Avg Connections (% of max) | Recommendation |
|---------|---------------------------|----------------|
| < 20% | < 30% | Downsize - over-provisioned |
| 20-60% | 30-60% | Correct size - monitor quarterly |
| 60-80% | 60-80% | Plan upgrade within 6 months |
| > 80% | > 80% | Upgrade now - insufficient headroom |

### 5.5 Modify Instance Class (If Downsizing)

If the analysis shows your instances are over-provisioned, downsize:

```bash
aws rds modify-db-instance \
    --db-instance-identifier devops-lab-cluster-instance-1 \
    --db-instance-class db.r6g.medium \
    --apply-immediately
```

This causes a brief outage (typically 1-3 minutes) as the instance restarts with the new class. Plan this during a maintenance window.

---

## Section 6: Aurora Serverless v2 Evaluation (Lever 5)

Serverless v2 scales automatically and charges by ACU (Aurora Capacity Unit) per second.

### 6.1 Calculate Serverless v2 Cost

1 ACU provides approximately 2 GB RAM. The `db.r6g.large` instance has 16 GB RAM, which equals approximately 8 ACUs.

```
Provisioned On-Demand (db.r6g.large): ~$0.252/hr = ~$184/month
Serverless v2 at 8 ACUs sustained: 8 * $0.12/hr = $0.96/hr = ~$700/month
Serverless v2 at 2 ACUs average: 2 * $0.12/hr = $0.24/hr = ~$175/month
```

Serverless v2 makes sense when:
- Average utilization is below 25% of the provisioned capacity
- The workload has significant idle periods (dev/test environments)
- Traffic is highly variable with long valleys between peaks

For a steady production OLTP workload, provisioned is almost always cheaper.

### 6.2 Check Workload Variability

```bash
aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
    --start-time "$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%S)" \
    --end-time "$(date -u +%Y-%m-%dT%H:%M:%S)" \
    --period 3600 \
    --statistics Average Minimum Maximum \
    --output table
```

If the `Minimum` is consistently near 0% and the `Maximum` spikes to 80%+, the workload is variable and Serverless v2 may be a good fit.

---

## Section 7: Common Cost Traps

### 7.1 Check for Verbose Query Logging

```bash
aws rds describe-db-cluster-parameters \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --query "Parameters[?ParameterName=='log_min_duration_statement'].{Name:ParameterName,Value:ParameterValue}" \
    --output table
```

If the value is `0`, every query is being logged. On a busy instance, this can add $500-$2,000/month in CloudWatch Logs charges.

Fix it by setting the value to `1000` (1 second):

```bash
aws rds modify-db-cluster-parameter-group \
    --db-cluster-parameter-group-name devops-lab-cluster-params \
    --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

### 7.2 Check for Orphaned Snapshots

```bash
aws rds describe-db-cluster-snapshots \
    --db-cluster-identifier devops-lab-cluster \
    --snapshot-type manual \
    --query 'DBClusterSnapshots[].{Snapshot:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Size:AllocatedStorage,Status:Status}' \
    --output table
```

Delete snapshots older than 90 days that are not tagged for long-term retention.

### 7.3 Check CloudWatch Log Retention

```bash
aws logs describe-log-groups \
    --log-group-name-prefix /aws/rds/cluster/devops-lab-cluster \
    --query 'logGroups[].{Name:logGroupName,RetentionDays:retentionInDays,StoredBytes:storedBytes}' \
    --output table
```

If `RetentionDays` is empty, logs are retained forever. Set a 90-day retention policy:

```bash
aws logs put-retention-policy \
    --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
    --retention-in-days 90
```

---

## Section 8: Create the Cost Optimization Plan

### 8.1 Document Your Findings

```bash
vi ~/sre-practice/cost-optimization-plan.md
```

```markdown
# Cost Optimization Plan: devops-lab-cluster

## Current Monthly Cost Estimate
| Component | Cost |
|-----------|------|
| Compute (2x db.r6g.large On-Demand) | $368 |
| Storage (Standard, XX GB) | $XX |
| I/O charges | $XX |
| CloudWatch Logs | $XX |
| Snapshots | $XX |
| **Total** | **$XXX** |

## Optimization Actions

### Immediate (This Week)
- [ ] Set log_min_duration_statement to 1000ms
- [ ] Set CloudWatch log retention to 90 days
- [ ] Delete orphaned snapshots older than 90 days

### Short-Term (This Month)
- [ ] Evaluate I/O-Optimized storage (if I/O > 25% of total)
- [ ] Right-size instances if CPU < 20% average

### Medium-Term (This Quarter)
- [ ] Purchase Reserved Instances for stable workloads
- [ ] Migrate to latest Graviton generation if on Intel

### Quarterly Review
- [ ] Re-evaluate RI coverage and expiration dates
- [ ] Check right-sizing recommendations
- [ ] Audit new cost traps (log volume, snapshot accumulation)

## Estimated Monthly Savings
| Action | Estimated Savings |
|--------|------------------|
| Reserved Instances | $162/mo (44%) |
| Log retention policy | $XX/mo |
| Right-sizing (if applicable) | $XX/mo |
| **Total estimated savings** | **$XXX/mo** |
```

Save and exit vi (`:wq`).

---

## Cleanup

The files created in `~/sre-practice/` are documentation for ongoing cost management. Keep them and update quarterly.

No AWS resources were created in this lab that need cleanup (unless you switched storage type or modified instance class - those are intended changes).

---

## Summary

| What You Did | Why It Matters |
|-------------|---------------|
| Established cost baseline | Cannot optimize what you do not measure |
| Analyzed I/O costs | Wrong storage mode can waste hundreds per month |
| Evaluated Reserved Instances | 30-60% savings on committed workloads |
| Checked Graviton eligibility | 10-20% savings with equal or better performance |
| Assessed right-sizing | Over-provisioned instances waste money silently |
| Evaluated Serverless v2 | Right choice for variable workloads |
| Fixed cost traps | Logging and snapshot accumulation are hidden costs |
| Created optimization plan | Structured approach ensures savings are captured |

**Next:** [BUILD 03 - Automation with Lambda](./03-automation-with-lambda.md)

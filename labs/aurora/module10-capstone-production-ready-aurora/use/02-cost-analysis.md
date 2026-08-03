# Module 10 - Use Exercise 02: Cost Analysis

**Objective:** Calculate the total monthly cost of your Aurora stack, identify the top cost drivers, evaluate optimization opportunities, and produce a cost report with recommendations.
**Time:** 30 minutes
**Level:** Senior / Staff

---

## Context

Your CFO asks: "How much does this database stack cost per month, and can we reduce it?" You need to produce a detailed cost breakdown, not just the Aurora compute cost - but everything: networking, monitoring, backups, and hidden costs.

---

## Exercise

<details>
<summary>Part 1: Compute Costs (click to expand)</summary>

### Task

Calculate the monthly compute cost for the Aurora cluster.

### Data You Need

Look up the current On-Demand price for `db.r6g.large` in us-east-1:

```bash
aws rds describe-orderable-db-instance-options \
  --engine aurora-postgresql \
  --db-instance-class db.r6g.large \
  --query 'OrderableDBInstanceOptions[0].[DBInstanceClass,AvailabilityZones[0].Name]' \
  --output table
```

Use the AWS pricing page or this reference:
- `db.r6g.large` (2 vCPU, 16 GB RAM): approximately $0.240/hour in us-east-1

### Calculation

| Resource | Hourly Rate | Hours/Month | Monthly Cost |
|----------|-------------|-------------|-------------|
| Writer (db.r6g.large) | $0.240 | 730 | $175.20 |
| Reader (db.r6g.large) | $0.240 | 730 | $175.20 |
| **Compute Total** | | | **$350.40** |

### Optimization Question

If you purchased a 1-year All Upfront Reserved Instance for both instances:
- RI price for db.r6g.large: approximately $1,200/year each
- Monthly equivalent: $100/month each
- **Savings: $150.40/month (43%)**

When should you purchase RIs?
- After the cluster has been running for 1-2 months with stable instance sizing
- Only if you are confident the instance class will not change in the next year

</details>

<details>
<summary>Part 2: Storage and I/O Costs (click to expand)</summary>

### Task

Calculate storage and I/O costs.

### Data You Need

Check current storage usage:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 3600 \
  --statistics Maximum \
  --output table
```

Check I/O operations:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeReadIOPs \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-24H '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Sum \
  --output table
```

### Calculation (Aurora Standard)

| Resource | Rate | Usage | Monthly Cost |
|----------|------|-------|-------------|
| Storage | $0.10/GB-month | 100 GB | $10.00 |
| Read I/O | $0.20/million | 200M requests | $40.00 |
| Write I/O | $0.20/million | 300M requests | $60.00 |
| **Storage Total** | | | **$110.00** |

### Optimization Question

Should you switch to I/O-Optimized?

I/O-Optimized calculation:
| Resource | Rate | Usage | Monthly Cost |
|----------|------|-------|-------------|
| Storage | $0.225/GB-month | 100 GB | $22.50 |
| Read I/O | $0.00 | 200M requests | $0.00 |
| Write I/O | $0.00 | 300M requests | $0.00 |
| **I/O-Optimized Total** | | | **$22.50** |

**Savings with I/O-Optimized: $87.50/month (79.5%)**

In this example, I/O costs ($100) far exceed the storage premium ($12.50). Switch to I/O-Optimized.

The real answer depends on your actual I/O volume. Check your bill.

</details>

<details>
<summary>Part 3: Networking Costs (click to expand)</summary>

### Task

Calculate all networking costs.

### Calculation

| Resource | Rate | Usage | Monthly Cost |
|----------|------|-------|-------------|
| NAT Gateway 1 | $0.045/hour | 730 hours | $32.85 |
| NAT Gateway 2 | $0.045/hour | 730 hours | $32.85 |
| NAT data processing | $0.045/GB | 50 GB/month | $2.25 |
| VPC Endpoint (Secrets Manager) | $0.01/hour + $0.01/GB | 730 hours | $7.30 |
| VPC Endpoint (Monitoring) | $0.01/hour | 730 hours | $7.30 |
| VPC Endpoint (Logs) | $0.01/hour | 730 hours | $7.30 |
| S3 Gateway Endpoint | free | - | $0.00 |
| Cross-AZ data transfer | $0.01/GB | 100 GB | $1.00 |
| **Networking Total** | | | **$90.85** |

### Optimization Question

Can you reduce networking costs?
- Reduce to 1 NAT gateway: saves $32.85/month but reduces availability
- Remove VPC endpoints and use NAT for AWS API traffic: saves $21.90/month but increases NAT data processing costs and adds internet dependency to database operations
- Consolidate to 2 AZs: saves cross-AZ transfer but reduces fault tolerance

For production, these costs are justified. For staging, reduce to 1 NAT and fewer endpoints.

</details>

<details>
<summary>Part 4: Monitoring and Backup Costs (click to expand)</summary>

### Task

Calculate monitoring and backup costs.

### Calculation

| Resource | Rate | Usage | Monthly Cost |
|----------|------|-------|-------------|
| CloudWatch Alarms | $0.10/alarm | 8 alarms | $0.80 |
| CloudWatch Dashboard | $3.00/dashboard | 1 dashboard | $3.00 |
| CloudWatch Logs (ingestion) | $0.50/GB | 5 GB/month | $2.50 |
| CloudWatch Logs (storage) | $0.03/GB | 15 GB retained | $0.45 |
| Performance Insights | free tier | 7-day retention | $0.00 |
| Enhanced Monitoring | included | - | $0.00 |
| Automated backup storage | free (up to cluster size) | 100 GB | $0.00 |
| Manual snapshots | $0.021/GB-month | 200 GB (2 snapshots) | $4.20 |
| Cross-region snapshot | $0.021/GB-month | 100 GB in us-west-2 | $2.10 |
| Cross-region copy transfer | $0.02/GB | 100 GB | $2.00 |
| SNS notifications | $0.50/million | <1000 | $0.00 |
| **Monitoring/Backup Total** | | | **$15.05** |

### Optimization Question

Can you reduce monitoring costs?
- Reduce log volume: increase `log_min_duration_statement` from 1000ms to 5000ms
- Reduce log retention: 30 days instead of 90 days
- Delete old manual snapshots
- Reduce cross-region copy frequency from daily to weekly

For production, full monitoring is not negotiable. Optimize log volume only if costs become significant.

</details>

<details>
<summary>Part 5: Total Cost Summary (click to expand)</summary>

### Complete Monthly Cost Breakdown

| Category | Monthly Cost | Percentage |
|----------|-------------|-----------|
| Compute (On-Demand) | $350.40 | 62% |
| Storage and I/O | $110.00 | 19% |
| Networking | $90.85 | 16% |
| Monitoring and Backup | $15.05 | 3% |
| **Total** | **$566.30** | **100%** |

### With All Optimizations Applied

| Optimization | Monthly Savings |
|-------------|----------------|
| Reserved Instances (1-year) | -$150.40 |
| I/O-Optimized storage | -$87.50 |
| Single NAT Gateway | -$32.85 |
| **Total Optimized Cost** | **$295.55** |
| **Total Savings** | **$270.75 (48%)** |

### Annual Cost Comparison

| Configuration | Annual Cost |
|--------------|------------|
| Current (On-Demand, Standard) | $6,795.60 |
| Optimized (RI, I/O-Opt, 1 NAT) | $3,546.60 |
| **Annual Savings** | **$3,249.00** |

</details>

---

## Deliverable

Create a cost report with:

1. **Current monthly cost** - Itemized by category
2. **Top 3 cost drivers** - With specific dollar amounts
3. **Optimization recommendations** - With savings estimates and tradeoffs
4. **12-month projection** - Including expected storage growth
5. **Comparison** - On-Demand vs Optimized vs Serverless v2

This report would be presented to your engineering manager or CFO.

---

## Summary

Cost analysis is a core DBA responsibility. The ability to break down costs, identify optimization opportunities, and present tradeoffs is what separates a DBA who manages databases from one who manages a business-critical asset. Practice this analysis monthly on every production cluster.

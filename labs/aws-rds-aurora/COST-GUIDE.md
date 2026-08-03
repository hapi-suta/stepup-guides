# AWS RDS/Aurora Cost Estimation Guide

This guide helps self-paced students understand what each tier costs and how to keep bills under control.

## Per-Tier Cost Breakdown

| Tier | Resources Created | Instance Class | Approx. Cost/Session |
|------|-------------------|----------------|---------------------|
| 0 | None (concepts only) | N/A | $0.00 |
| 1 | 1 RDS instance, VPC, subnet group | db.t3.micro | $0.00 (Free Tier) |
| 2 | 1 RDS instance, IAM roles, SSL certs | db.t3.micro | $0.00 (Free Tier) |
| 3 | 1 RDS instance, parameter groups | db.t3.micro | $0.00 (Free Tier) |
| 4 | 1 Aurora cluster (writer + reader) | db.t3.medium | $1.50-2.00/hr |
| 5 | 1 Aurora cluster, snapshots, PITR | db.t3.medium | $1.50-2.00/hr |
| 6 | 1 Aurora cluster, PI, Enhanced Monitoring | db.t3.medium | $1.50-2.00/hr |
| 7 | Aurora Serverless v2, read replicas | db.serverless | $0.50-3.00/hr |
| 8 | Multi-region, Global Database | db.t3.medium x2 | $3.00-4.00/hr |

## Total Curriculum Cost Estimate

If you complete every tier from start to finish:

- **Tiers 0-3:** Free (uses db.t3.micro within Free Tier)
- **Tiers 4-8:** ~$15-25 total (assuming 2-3 hour sessions, cleanup after each)
- **Capstone:** ~$5-8 (3-4 hour session)

**Total estimate: $20-35** for the full curriculum.

## Free Tier Eligibility

AWS Free Tier includes 750 hours/month of db.t3.micro for the first 12 months:

- Single-AZ only
- 20 GB General Purpose (SSD) storage
- 20 GB backup storage
- Applies to RDS for PostgreSQL (NOT Aurora)

Tiers 0-3 stay within Free Tier when you use db.t3.micro and clean up after each session.

## "Stop the Bleeding" - Emergency Cleanup

If you forgot to clean up and want to kill everything immediately:

### Delete ALL RDS instances in your account

```bash
# List all RDS instances
aws rds describe-db-instances \
  --query "DBInstances[].DBInstanceIdentifier" \
  --output table

# Delete a specific instance (no final snapshot - lab data only!)
aws rds delete-db-instance \
  --db-instance-identifier YOUR-INSTANCE-ID \
  --skip-final-snapshot \
  --delete-automated-backups
```

### Delete ALL Aurora clusters

```bash
# List Aurora clusters
aws rds describe-db-clusters \
  --query "DBClusters[].DBClusterIdentifier" \
  --output table

# First delete all instances in the cluster
aws rds delete-db-instance \
  --db-instance-identifier YOUR-CLUSTER-INSTANCE-1

# Then delete the cluster itself
aws rds delete-db-cluster \
  --db-cluster-identifier YOUR-CLUSTER-ID \
  --skip-final-snapshot
```

### Nuclear option - delete everything tagged as lab resources

```bash
# If you tagged resources during labs (recommended)
aws rds describe-db-instances \
  --query "DBInstances[?TagList[?Key=='Environment' && Value=='lab']].DBInstanceIdentifier" \
  --output text | tr '\t' '\n' | while read id; do
  echo "Deleting: $id"
  aws rds delete-db-instance \
    --db-instance-identifier "$id" \
    --skip-final-snapshot \
    --delete-automated-backups
done
```

## Cost Monitoring

Check what RDS is costing you right now:

```bash
# Current month RDS spend (updated daily)
aws ce get-cost-and-usage \
  --time-period Start=$(date -u '+%Y-%m-01'),End=$(date -u '+%Y-%m-%d') \
  --granularity MONTHLY \
  --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Relational Database Service"]}}' \
  --metrics BlendedCost \
  --query "ResultsByTime[0].Total.BlendedCost.Amount" \
  --output text

# List running RDS instances and their classes
aws rds describe-db-instances \
  --query "DBInstances[?DBInstanceStatus=='available'].[DBInstanceIdentifier,DBInstanceClass,Engine]" \
  --output table
```

## Cost-Saving Tips

1. **Stop instances between sessions** - A stopped RDS instance costs $0 for compute (storage still charges ~$0.115/GB/month)

   ```bash
   aws rds stop-db-instance --db-instance-identifier my-lab-instance
   ```

   Note: AWS auto-restarts stopped instances after 7 days.

2. **Use db.t3.micro for T0-T3** - Stays within Free Tier

3. **Delete Aurora clusters immediately after T4-T7 labs** - Aurora has no "stop" for clusters older than 7 days, and it charges per-second

4. **Delete snapshots you don't need** - Manual snapshots persist (and charge) after instance deletion

   ```bash
   aws rds describe-db-snapshots \
     --query "DBSnapshots[?SnapshotType=='manual'].[DBSnapshotIdentifier,AllocatedStorage]" \
     --output table
   ```

5. **Use a single region** - Multi-region (T8) costs double. Only create Global Database for that specific lab, then delete immediately.

6. **Set a billing alarm** - Get alerted before surprises

   ```bash
   aws cloudwatch put-metric-alarm \
     --alarm-name "RDS-Spend-Alert" \
     --metric-name EstimatedCharges \
     --namespace AWS/Billing \
     --statistic Maximum \
     --period 21600 \
     --threshold 10 \
     --comparison-operator GreaterThanThreshold \
     --dimensions Name=ServiceName,Value=AmazonRDS \
     --evaluation-periods 1 \
     --alarm-actions arn:aws:sns:us-east-1:YOUR_ACCOUNT_ID:billing-alerts
   ```

## Per-Service Pricing Reference (us-east-1, May 2025)

| Resource | Price |
|----------|-------|
| db.t3.micro (RDS) | $0.017/hr |
| db.t3.medium (RDS) | $0.068/hr |
| db.t3.medium (Aurora) | $0.082/hr |
| Aurora Serverless v2 (per ACU-hr) | $0.12/ACU-hr |
| Aurora I/O-Optimized storage | $0.225/GB-month |
| General Purpose SSD (gp3) | $0.115/GB-month |
| Automated backup (beyond free) | $0.095/GB-month |
| Data transfer (out, first 10 TB) | $0.09/GB |
| Performance Insights (retention > 7 days) | $0/vCPU-month (free tier) |

Prices are approximate and may change. Check [AWS RDS Pricing](https://aws.amazon.com/rds/pricing/) for current rates.

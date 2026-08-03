# SURVIVE Scenario 04: Cost Runaway - Runbook

## Scenario

You receive an alert that AWS costs have spiked. Investigate the Aurora cluster for unnecessary resources driving up costs.

---

## Step 1: Inventory All Cluster Instances

**On your local workstation:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]' \
  --output table \
  --region us-east-1
```

Look for instances with larger instance classes than expected.

---

## Step 2: Calculate Per-Instance Cost

Use these reference prices (us-east-1, On-Demand):
- db.r6g.large: $0.240/hour = $175/month
- db.r6g.xlarge: $0.480/hour = $350/month
- db.r6g.2xlarge: $0.960/hour = $700/month

Multiply the hourly rate by 730 hours for monthly cost.

---

## Step 3: Identify the Oversized Instance

Any instance with a larger class than the writer should be flagged. In this cluster, the standard is `db.r6g.large`.

---

## Step 4: Delete the Oversized Instance

**On your local workstation:**

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-chaos-reader \
  --skip-final-snapshot \
  --region us-east-1
```

---

## Step 5: Find Unnecessary Snapshots

**On your local workstation:**

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --snapshot-type manual \
  --query 'DBClusterSnapshots[*].[DBClusterSnapshotIdentifier,SnapshotCreateTime,AllocatedStorage]' \
  --output table \
  --region us-east-1
```

Delete snapshots that contain "chaos" in the name:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier devops-lab-cluster-chaos-snap-001 \
  --region us-east-1
```

Repeat for each chaos snapshot.

---

## Step 6: Verify Clean State

**On your local workstation:**

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass]' \
  --output table \
  --region us-east-1
```

All instances should be `db.r6g.large`.

---

## Step 7: Document Cost Impact

Calculate:
- Extra cost from oversized reader: $700 - $175 = $525/month wasted
- Extra snapshot storage cost: approximately $2/snapshot/month
- Total waste identified: approximately $531/month

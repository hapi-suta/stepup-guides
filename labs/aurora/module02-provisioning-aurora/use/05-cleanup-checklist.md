# USE 05 - Cleanup Checklist
## Module 02: Provisioning Aurora

**Estimated time:** 20 minutes
**Type:** Verification checklist
**Prerequisite:** Completed any Module 02 exercises

---

## Overview

Aurora resources cost money every minute they run. A single `db.r6g.large` instance costs approximately $0.26/hour - that is $190/month if left running. After completing the lab exercises, you must delete ALL resources to avoid unexpected charges.

This checklist walks you through every resource type created during Module 02 and verifies each is deleted.

---

## Why Order Matters

Aurora resources have dependencies. You must delete in this order:

1. Database instances (readers first, then writer)
2. Aurora cluster
3. Cluster snapshots (if any were created)
4. DB subnet group
5. Security group
6. Parameter groups (cluster and instance)

If you try to delete a cluster while it still has instances, AWS will reject the request. If you try to delete a subnet group while a cluster uses it, AWS will reject that too.

---

## Step 1 - Delete All Reader Instances

List all instances in the cluster:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Role:copy(DBInstanceIdentifier)}" \
  --output table
```

Delete each reader (any instance that is NOT the writer):

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-2 \
  --skip-final-snapshot

aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-reader-1 \
  --skip-final-snapshot
```

Wait for readers to be deleted:

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-reader-2

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-reader-1
```

**Verify:** No readers remain:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].DBInstanceIdentifier" \
  --output text
```

Expected: only the writer instance should remain.

---

## Step 2 - Delete the Writer Instance

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-cluster-writer \
  --skip-final-snapshot

aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-cluster-writer
```

**Verify:** No instances remain:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=devops-lab-cluster" \
  --query "DBInstances[*].DBInstanceIdentifier" \
  --output text
```

Expected: empty (no output).

---

## Step 3 - Delete the Aurora Cluster

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --skip-final-snapshot
```

**Verify:** Cluster is gone:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Status" \
  --output text 2>/dev/null || echo "DELETED"
```

Expected: `DELETED` (or `deleting` if still in progress).

---

## Step 4 - Delete Cluster Snapshots

Check for any snapshots that were created:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusterSnapshots[*].{ID:DBClusterSnapshotIdentifier,Status:Status,Size:AllocatedStorage}" \
  --output table
```

If any exist, delete them:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier SNAPSHOT_ID_HERE
```

**Verify:** No snapshots remain:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusterSnapshots[*].DBClusterSnapshotIdentifier" \
  --output text
```

Expected: empty.

---

## Step 5 - Delete the DB Subnet Group

```bash
aws rds delete-db-subnet-group \
  --db-subnet-group-name devops-lab-subnetgroup
```

**Verify:**

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name devops-lab-subnetgroup \
  --query "DBSubnetGroups[0].DBSubnetGroupName" \
  --output text 2>/dev/null || echo "DELETED"
```

Expected: `DELETED`.

---

## Step 6 - Delete the Security Group

Find and delete the security group:

```bash
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-aurora-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null)

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
  aws ec2 delete-security-group --group-id "$SG_ID"
  echo "Deleted security group $SG_ID"
else
  echo "Security group not found - already deleted"
fi
```

**Verify:**

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-aurora-sg" \
  --query "SecurityGroups[*].GroupId" \
  --output text
```

Expected: empty.

---

## Step 7 - Delete Parameter Groups

Delete the cluster parameter group:

```bash
aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params 2>/dev/null && echo "Deleted" || echo "Not found"

aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg 2>/dev/null && echo "Deleted" || echo "Not found"
```

Delete the instance parameter group:

```bash
aws rds delete-db-parameter-group \
  --db-parameter-group-name devops-lab-custom-instance-pg 2>/dev/null && echo "Deleted" || echo "Not found"
```

**Verify:** List all custom parameter groups (default ones cannot be deleted):

```bash
aws rds describe-db-cluster-parameter-groups \
  --query "DBClusterParameterGroups[?!starts_with(DBClusterParameterGroupName,'default')].DBClusterParameterGroupName" \
  --output text
```

Your lab parameter groups should not appear in this list.

---

## Step 8 - Final Cost Verification

### Check for any remaining RDS resources in your account:

```bash
echo "=== RDS Instances ==="
aws rds describe-db-instances \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" \
  --output table

echo ""
echo "=== Aurora Clusters ==="
aws rds describe-db-clusters \
  --query "DBClusters[*].{ID:DBClusterIdentifier,Status:Status}" \
  --output table

echo ""
echo "=== Cluster Snapshots ==="
aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query "DBClusterSnapshots[*].{ID:DBClusterSnapshotIdentifier,Cluster:DBClusterIdentifier}" \
  --output table
```

If any resources with `devops-lab` in the name still exist, go back and delete them.

### Check AWS Cost Explorer (optional but recommended):

1. Go to AWS Console - Billing - Cost Explorer
2. Filter by Service: Amazon Relational Database Service
3. Group by: Usage Type
4. Look for any charges from today

If you see ongoing charges for Aurora instances, something was not deleted. Check all regions - resources in a different region than your default will not show up in region-specific CLI commands.

---

## Cleanup Verification Summary

Check each box after verifying:

| Resource | Command to Verify | Status |
|----------|-------------------|--------|
| Reader instances | `aws rds describe-db-instances --filters ...` | Deleted / Not Found |
| Writer instance | `aws rds describe-db-instances --filters ...` | Deleted / Not Found |
| Aurora cluster | `aws rds describe-db-clusters ...` | Deleted / Not Found |
| Cluster snapshots | `aws rds describe-db-cluster-snapshots ...` | None remaining |
| DB subnet group | `aws rds describe-db-subnet-groups ...` | Deleted / Not Found |
| Security group | `aws ec2 describe-security-groups ...` | Deleted / Not Found |
| Cluster parameter groups | `aws rds describe-db-cluster-parameter-groups ...` | Deleted / Not Found |
| Instance parameter groups | `aws rds describe-db-parameter-groups ...` | Deleted / Not Found |

If all rows show "Deleted / Not Found", you are done. No ongoing charges.

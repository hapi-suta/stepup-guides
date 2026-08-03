# Build 06 - Cleanup and Cost Control
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 15 minutes
**Difficulty:** Beginner
**Cost:** This guide saves you money by deleting lab resources
**Prerequisite:** Builds 01-05 complete (running Aurora cluster with 1 writer + 2 readers)

---

## What You Will Do

You will delete all Aurora resources created in this module. The order matters - you must delete instances before the cluster, and the cluster before dependent resources. By the end you will:

- Have deleted all three instances and the cluster
- Have deleted the custom parameter groups
- Know how to verify nothing is still running
- Know how to check Cost Explorer for lab charges

> **Warning:** This guide permanently deletes your lab resources. Make sure you have completed all exercises before proceeding.

---

## Why Order Matters

Aurora resources have dependencies. You cannot delete a cluster that still has instances. You cannot delete a parameter group that is attached to a cluster. The correct order is:

```
1. Delete reader instances (both)
2. Delete writer instance
3. Delete cluster (skip final snapshot)
4. Delete custom parameter groups
5. Delete subnet group (if created for this lab)
6. Delete security group (if created for this lab)
7. Verify everything is gone
```

---

## Part A - Delete the Reader Instances

Delete readers first, then the writer. Deleting the writer while readers exist causes Aurora to promote a reader to writer, which is unnecessary during cleanup.

### Step 1 - Delete the Second Reader

**In your terminal** (local machine):

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-reader-2 \
  --skip-final-snapshot
```

What each flag does:

- `--db-instance-identifier devops-lab-reader-2` - the instance to delete.
- `--skip-final-snapshot` - do not create a backup snapshot before deleting. For a lab, this saves time and cost. In production, you would want a final snapshot.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-reader-2",
        "DBInstanceStatus": "deleting",
        ...
    }
}
```

### Step 2 - Delete the First Reader

**In your terminal** (local machine):

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --skip-final-snapshot
```

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-reader-1",
        "DBInstanceStatus": "deleting",
        ...
    }
}
```

### Step 3 - Wait for Reader Deletion to Complete

**In your terminal** (local machine):

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-reader-2
```

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-reader-1
```

Each wait command blocks until the instance is fully deleted. This typically takes 3 to 5 minutes per instance. You can run both in separate terminal tabs to wait in parallel.

---

## Part B - Delete the Writer Instance

### Step 1 - Delete the Writer

**In your terminal** (local machine):

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-writer-1 \
  --skip-final-snapshot
```

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-writer-1",
        "DBInstanceStatus": "deleting",
        ...
    }
}
```

### Step 2 - Wait for Writer Deletion

**In your terminal** (local machine):

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-writer-1
```

---

## Part C - Delete the Cluster

With all instances deleted, you can now delete the cluster itself. The cluster holds the shared storage volume.

### Step 1 - Delete the Cluster

**In your terminal** (local machine):

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --skip-final-snapshot
```

What each flag does:

- `--db-cluster-identifier devops-lab-cluster` - the cluster to delete.
- `--skip-final-snapshot` - do not create a snapshot of the storage volume before deleting. For a lab, this is fine. In production, use `--final-db-snapshot-identifier my-final-snapshot` instead.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "Status": "deleting",
        ...
    }
}
```

> **Note:** If you get an error saying deletion protection is enabled, run this first:
> ```bash
> aws rds modify-db-cluster \
>   --db-cluster-identifier devops-lab-cluster \
>   --no-deletion-protection \
>   --apply-immediately
> ```
> Then retry the delete command.

### Step 2 - Verify the Cluster is Gone

**In your terminal** (local machine):

Wait about 1 to 2 minutes, then check:

```bash
aws rds describe-db-clusters \
  --query "DBClusters[?DBClusterIdentifier=='devops-lab-cluster'].{ID:DBClusterIdentifier,Status:Status}" \
  --output table
```

Expected output when deletion is complete:
```
(no output - cluster no longer exists)
```

If you still see the cluster with status `deleting`, wait another minute and try again.

---

## Part D - Delete Parameter Groups

Custom parameter groups cannot be deleted while they are attached to a cluster. Now that the cluster is deleted, you can remove them.

### Step 1 - Delete the Cluster Parameter Group

**In your terminal** (local machine):

```bash
aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params
```

This command returns no output on success.

### Step 2 - Delete the Instance Parameter Group

**In your terminal** (local machine):

```bash
aws rds delete-db-parameter-group \
  --db-parameter-group-name devops-lab-instance-params
```

This command returns no output on success.

### Step 3 - Verify Parameter Groups Are Gone

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-parameter-groups \
  --query "DBClusterParameterGroups[?contains(DBClusterParameterGroupName, 'devops-lab')].DBClusterParameterGroupName" \
  --output table
```

Expected output:
```
(no output - parameter group no longer exists)
```

```bash
aws rds describe-db-parameter-groups \
  --query "DBParameterGroups[?contains(DBParameterGroupName, 'devops-lab')].DBParameterGroupName" \
  --output table
```

Expected output:
```
(no output - parameter group no longer exists)
```

---

## Part E - Delete Subnet Group and Security Group (Optional)

Only delete these if you created them specifically for this lab and do not need them for other modules.

### Delete the Subnet Group

**In your terminal** (local machine):

```bash
aws rds delete-db-subnet-group \
  --db-subnet-group-name devops-lab-subnet-group
```

> **Note:** If you get an error saying the subnet group is in use, another RDS resource may still be using it. Check with `aws rds describe-db-instances` and `aws rds describe-db-clusters`.

### Delete the Security Group

**In your terminal** (local machine):

First, get the security group ID:

```bash
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=devops-lab-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text)
```

```bash
echo "Deleting security group: $SG_ID"
```

```bash
aws ec2 delete-security-group \
  --group-id "$SG_ID"
```

This command returns no output on success.

> **Note:** If you plan to continue with Module 03, keep the subnet group and security group. You will reuse them.

---

## Part F - Verify Nothing is Running

This is the most important step. A forgotten Aurora instance can cost $2+/day.

### Step 1 - Check for Any Running Clusters

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --query "DBClusters[*].{ID:DBClusterIdentifier,Status:Status,Engine:Engine}" \
  --output table
```

Expected output:
```
(empty table or no devops-lab entries)
```

If you see `devops-lab-cluster` in this list, it has not been fully deleted yet. Wait a few minutes and check again.

### Step 2 - Check for Any Running Instances

**In your terminal** (local machine):

```bash
aws rds describe-db-instances \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Status:DBInstanceStatus,Class:DBInstanceClass}" \
  --output table
```

Expected output:
```
(empty table or no devops-lab entries)
```

If you see any `devops-lab-*` instances, they have not finished deleting. Wait and check again.

### Step 3 - Check for Automated Snapshots

Aurora creates automated snapshots during the backup retention period. These are deleted automatically when the cluster is deleted (since we set `--skip-final-snapshot`). But if you created manual snapshots, those remain.

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-snapshots \
  --query "DBClusterSnapshots[?contains(DBClusterIdentifier, 'devops-lab')].{ID:DBClusterSnapshotIdentifier,Type:SnapshotType,Status:Status}" \
  --output table
```

Expected output:
```
(empty table)
```

If you see manual snapshots, delete them:

```bash
aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier SNAPSHOT_ID_HERE
```

---

## Part G - Check Cost Explorer

It takes 24 hours for charges to appear in Cost Explorer, but you can check it the next day to confirm you are not being charged.

### Console Steps

**In the AWS Console** (Cost Management):

1. Go to https://console.aws.amazon.com
2. In the search bar, type `Cost Explorer` and click it.
3. In the left sidebar, click **Cost Explorer**.
4. Set the date range to include today and the past 7 days.
5. Click **Service** in the "Group by" dropdown.
6. Look for **Amazon Relational Database Service** in the chart.
7. Click on it to see the breakdown.

You should see charges for the time your Aurora instances were running. After deletion, no new charges should accrue.

### Typical Lab Costs

| Resource | Rate | Duration | Cost |
|----------|------|----------|------|
| db.t3.medium writer | ~$0.082/hour | 3 hours | ~$0.25 |
| db.t3.medium reader-1 | ~$0.082/hour | 3 hours | ~$0.25 |
| db.t3.medium reader-2 | ~$0.082/hour | 1 hour | ~$0.08 |
| Aurora storage | ~$0.10/GB/month | Minimal | ~$0.01 |
| **Total** | | | **~$0.59** |

If you left instances running overnight (12 hours), the cost would be approximately $2.95.

---

## Cleanup Checklist

Use this checklist to confirm everything is deleted:

- [ ] `devops-lab-reader-2` instance deleted
- [ ] `devops-lab-reader-1` instance deleted
- [ ] `devops-lab-writer-1` instance deleted
- [ ] `devops-lab-cluster` cluster deleted
- [ ] `devops-lab-cluster-params` cluster parameter group deleted
- [ ] `devops-lab-instance-params` instance parameter group deleted
- [ ] `devops-lab-subnet-group` subnet group deleted (optional)
- [ ] `devops-lab-sg` security group deleted (optional)
- [ ] No manual snapshots remaining
- [ ] `aws rds describe-db-clusters` shows no devops-lab entries
- [ ] `aws rds describe-db-instances` shows no devops-lab entries

---

## Summary

| What You Did | CLI Command |
|-------------|-------------|
| Deleted reader instances | `aws rds delete-db-instance --skip-final-snapshot` |
| Deleted writer instance | `aws rds delete-db-instance --skip-final-snapshot` |
| Deleted cluster | `aws rds delete-db-cluster --skip-final-snapshot` |
| Deleted parameter groups | `aws rds delete-db-cluster-parameter-group` + `delete-db-parameter-group` |
| Deleted subnet/security groups | `aws rds delete-db-subnet-group` + `aws ec2 delete-security-group` |
| Verified cleanup | `aws rds describe-db-clusters` + `describe-db-instances` |

**Module 02 complete.** You have provisioned an Aurora cluster via Console and CLI, configured parameter groups, connected and verified endpoints, added readers, and cleaned up all resources.

# SURVIVE 03 - Major Version Upgrade Failure
## Runbook: Rollback via Pre-Upgrade Snapshot

**Scenario:** A major version upgrade from PostgreSQL 15 to 16 completed but broke the application. The `uuid-ossp` extension was not upgraded and `uuid_generate_v4()` calls are failing. The team has decided to roll back.

**What the student sees:**
```
Application error: function uuid_generate_v4() does not exist
Line: INSERT INTO sessions (id) VALUES (uuid_generate_v4())
PostgreSQL 16 is running but the application cannot function.
A pre-upgrade snapshot exists.
```

---

## Your Objective

Roll back to the pre-upgrade state using the available snapshot within **30 minutes**.

---

## Step 1 - Confirm the Problem

Check the current cluster state:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{Status:Status,Version:EngineVersion}' \
  --output table
```

Confirm the pre-upgrade snapshot exists:

```bash
aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, `pre-upgrade`)].{ID:DBClusterSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

Record the snapshot ID.

---

## Step 2 - Make the Rollback Decision

Before restoring, document your answers:

1. When was the pre-upgrade snapshot taken?
2. How much data was written between the snapshot and the failed upgrade?
3. What is the plan for data written during the upgrade window?
4. Who needs to be notified of the rollback decision?

For this lab, assume data loss for the upgrade window is acceptable.

---

## Step 3 - Find and Set the Snapshot ID

```bash
export SNAPSHOT_ID=$(aws rds describe-db-cluster-snapshots \
  --db-cluster-identifier $CLUSTER_ID \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, `survive03-pre-upgrade`)].DBClusterSnapshotIdentifier' \
  --output text)

echo "Rolling back from snapshot: $SNAPSHOT_ID"
```

---

## Step 4 - Restore the Pre-Upgrade Snapshot to a New Cluster

```bash
export ROLLBACK_CLUSTER="devops-lab-survive03-rollback"
export ROLLBACK_INSTANCE="devops-lab-survive03-inst"

aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $ROLLBACK_CLUSTER \
  --snapshot-identifier $SNAPSHOT_ID \
  --engine aurora-postgresql \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --region $AWS_REGION
```

Add an instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --db-cluster-identifier $ROLLBACK_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION
```

Wait for both:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $ROLLBACK_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --region $AWS_REGION
```

---

## Step 5 - Verify the Rollback Cluster

Get the endpoint:

```bash
export ROLLBACK_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $ROLLBACK_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)
```

Verify the PostgreSQL version:

```bash
psql -h $ROLLBACK_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

Verify the application tables:

```bash
psql -h $ROLLBACK_HOST -U postgres -d postgres << 'EOF'
SELECT COUNT(*) AS user_count FROM app_users;
SELECT COUNT(*) AS config_count FROM app_config;
SELECT key, value FROM app_config ORDER BY key;
EOF
```

---

## Step 6 - Perform the Application Cutover

Update your application's connection string to point to the rollback cluster.

Option A - Update the application connection string (preferred):
- Change the DB_HOST environment variable in your application
- Redeploy or restart the application

Option B - Rename the clusters (controlled environments only):
```bash
# Rename the broken cluster
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --new-db-cluster-identifier "${CLUSTER_ID}-broken-upgrade" \
  --apply-immediately \
  --region $AWS_REGION

# Wait for rename
aws rds wait db-cluster-available \
  --db-cluster-identifier "${CLUSTER_ID}-broken-upgrade" \
  --region $AWS_REGION

# Rename the rollback cluster to the original name
aws rds modify-db-cluster \
  --db-cluster-identifier $ROLLBACK_CLUSTER \
  --new-db-cluster-identifier $CLUSTER_ID \
  --apply-immediately \
  --region $AWS_REGION

aws rds wait db-cluster-available \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION
```

---

## Step 7 - Document the Root Cause

```
ROOT CAUSE ANALYSIS
====================

Failure: uuid_generate_v4() not available after major upgrade
Root cause: uuid-ossp extension installed_version not updated

Fix for next attempt:
1. Before upgrade, check all extensions:
   SELECT name, installed_version, default_version
   FROM pg_available_extensions WHERE installed_version IS NOT NULL;
2. After upgrade, immediately run:
   ALTER EXTENSION "uuid-ossp" UPDATE;
3. Test uuid_generate_v4() in post-upgrade validation
4. Add extension update to post-upgrade checklist
```

---

## Step 8 - Ensure Backups Are Configured on the Restored Cluster

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

---

## Step 9 - Cleanup the Broken Cluster

After confirming the rollback is stable (at least 30 minutes):

```bash
# Delete instances first
aws rds delete-db-instance \
  --db-instance-identifier "${CLUSTER_ID}-broken-upgrade-instance-1" \
  --skip-final-snapshot \
  --region $AWS_REGION

# Then delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier "${CLUSTER_ID}-broken-upgrade" \
  --skip-final-snapshot \
  --region $AWS_REGION
```

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. The pre-upgrade snapshot is not optional - it is your only rollback path
2. Always test major upgrades on a clone BEFORE running on production
3. Extension compatibility checks must be part of the pre-upgrade checklist
4. After a major upgrade, run ALTER EXTENSION ... UPDATE for ALL installed extensions
5. Rollback restores to the snapshot state - data written during the upgrade window is lost
6. Document the root cause analysis immediately while details are fresh

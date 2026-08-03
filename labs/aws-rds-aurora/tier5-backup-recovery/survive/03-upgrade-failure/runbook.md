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

First, confirm what you are working with:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Version:EngineVersion}' \
  --output table
```

Confirm the pre-upgrade snapshot exists:

```bash
aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `pre-upgrade`)].{ID:DBSnapshotIdentifier,Created:SnapshotCreateTime,Status:Status}' \
  --output table
```

Record the snapshot ID.

---

## Step 2 - Make the Rollback Decision

Before restoring, answer these questions (document your answers):

1. When was the pre-upgrade snapshot taken?
2. How much data was written between the snapshot and the failed upgrade?
3. What is the plan for recovering any data written during the upgrade window?
4. Who needs to be notified of the rollback decision?

For this lab, assume data loss for the upgrade window is acceptable. In production, you would need to account for all writes during the upgrade.

---

## Step 3 - Find and Set the Snapshot ID

```bash
export SNAPSHOT_ID=$(aws rds describe-db-snapshots \
  --db-instance-identifier $DB_INSTANCE \
  --snapshot-type manual \
  --region $AWS_REGION \
  --query 'DBSnapshots[?contains(DBSnapshotIdentifier, `survive03-pre-upgrade`)].DBSnapshotIdentifier' \
  --output text)

echo "Rolling back from snapshot: $SNAPSHOT_ID"
```

---

## Step 4 - Restore the Pre-Upgrade Snapshot to a New Instance

```bash
export ROLLBACK_INSTANCE="suta-t5-survive03-rollback"

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --db-snapshot-identifier $SNAPSHOT_ID \
  --db-instance-class db.t3.micro \
  --db-subnet-group-name $DB_SUBNET_GROUP \
  --vpc-security-group-ids $VPC_SG_ID \
  --no-publicly-accessible \
  --region $AWS_REGION
```

Wait for the rollback instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --region $AWS_REGION
```

---

## Step 5 - Verify the Rollback Instance

Get the endpoint:

```bash
export ROLLBACK_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
```

Verify the PostgreSQL version (should be 15.x):

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

Verify uuid-ossp works:

```bash
psql -h $ROLLBACK_HOST -U postgres -d postgres \
  -c "SELECT uuid_generate_v4();"
```

Expected: returns a UUID without errors.

---

## Step 6 - Perform the Application Cutover

Update your application's connection string to point to the rollback instance. In this lab, we simulate this by renaming the instances.

Option A - Update the application connection string (preferred in production):
- Change the DB_HOST environment variable in your application
- Redeploy or restart the application to pick up the new host

Option B - Rename the instances (more disruptive, for controlled environments):
```bash
# Rename the broken instance out of the way
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --new-db-instance-identifier "${DB_INSTANCE}-broken-upgrade" \
  --apply-immediately \
  --region $AWS_REGION

# Wait for rename
aws rds wait db-instance-available \
  --db-instance-identifier "${DB_INSTANCE}-broken-upgrade" \
  --region $AWS_REGION

# Rename the rollback instance to the original name
aws rds modify-db-instance \
  --db-instance-identifier $ROLLBACK_INSTANCE \
  --new-db-instance-identifier $DB_INSTANCE \
  --apply-immediately \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION
```

> **Note:** Renaming changes the instance identifier but the DNS endpoint may take a few minutes to update. Applications using the endpoint hostname will reconnect automatically.

---

## Step 7 - Fix the Root Cause (Do NOT Forget This)

The upgrade failed because `uuid-ossp` was not upgraded. Document what should be done before the next upgrade attempt:

```
ROOT CAUSE ANALYSIS
====================

Failure: uuid_generate_v4() not available after major upgrade
Root cause: uuid-ossp extension installed_version was not updated after upgrade

Fix for next attempt:
1. On the pre-upgrade instance, check: SELECT name, installed_version, default_version
   FROM pg_available_extensions WHERE installed_version IS NOT NULL;
2. After upgrade, immediately run: ALTER EXTENSION "uuid-ossp" UPDATE;
3. Test uuid_generate_v4() in a post-upgrade validation step
4. Add extension update to post-upgrade checklist (see BUILD 04)
```

---

## Step 8 - Re-enable Backups on the Restored Instance

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --backup-retention-period 14 \
  --apply-immediately \
  --region $AWS_REGION
```

---

## Step 9 - Cleanup the Broken Upgraded Instance

After confirming the rollback is stable (at least 30 minutes), delete the broken instance:

```bash
aws rds delete-db-instance \
  --db-instance-identifier "${DB_INSTANCE}-broken-upgrade" \
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
5. Rollback restores to the snapshot state - any data written during the upgrade window is lost
6. Document your rollback decision and the root cause analysis immediately

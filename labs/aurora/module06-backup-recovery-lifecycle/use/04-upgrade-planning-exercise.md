# USE 04 - Upgrade Planning Exercise
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 40 minutes
**Format:** Planning exercise + hands-on pre-checks. You write the upgrade plan before executing.
**Goal:** Produce a complete, signed-off upgrade plan for a major version upgrade of an Aurora PostgreSQL cluster.

---

## Scenario

You manage the database for [CLIENT], a mid-sized SaaS company. Their Aurora PostgreSQL cluster is running version `15.4`. The team wants to upgrade to PostgreSQL 16 by end of quarter.

You need to:
1. Determine if an upgrade is safe
2. Document every step
3. Get sign-off from the engineering lead before proceeding

---

## Part 1 - Gather Information

### Step 1.1 - Check the Current State

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
```

Collect all relevant information:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{
    Engine: Engine,
    Version: EngineVersion,
    Status: Status,
    BackupRetention: BackupRetentionPeriod,
    MaintenanceWindow: PreferredMaintenanceWindow,
    ClusterParamGroup: DBClusterParameterGroup
  }' \
  --output table
```

Record all values.

### Step 1.2 - List Available Upgrade Targets

```bash
export CURRENT_VERSION=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].EngineVersion' \
  --output text)

echo "Current version: $CURRENT_VERSION"
```

```bash
aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --engine-version $CURRENT_VERSION \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[*].{Version:EngineVersion,Major:IsMajorVersionUpgrade}' \
  --output table
```

Identify the latest available PostgreSQL 16 version. Record it.

### Step 1.3 - Audit Installed Extensions

```bash
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT name, default_version, installed_version, comment FROM pg_available_extensions WHERE installed_version IS NOT NULL ORDER BY name;"
```

For each extension, verify it is available in the target version:

```bash
export TARGET_VERSION="16.4"

aws rds describe-db-engine-versions \
  --engine aurora-postgresql \
  --engine-version $TARGET_VERSION \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].SupportedFeatureNames'
```

### Step 1.4 - Check for Custom Functions

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres << 'EOF'
SELECT routine_schema, routine_name, routine_type
FROM information_schema.routines
WHERE routine_type IN ('FUNCTION', 'PROCEDURE')
AND routine_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY routine_name;
EOF
```

### Step 1.5 - Check the Cluster Parameter Group

```bash
export PARAM_GROUP=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].DBClusterParameterGroup' \
  --output text)

echo "Current parameter group: $PARAM_GROUP"
```

If using a custom parameter group, list the modified parameters:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name $PARAM_GROUP \
  --region $AWS_REGION \
  --query 'Parameters[?IsModifiable==`true` && ParameterValue!=null].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}' \
  --output table
```

---

## Part 2 - Write the Upgrade Plan

Use the information from Part 1 to fill in this template. Do NOT start the upgrade until the plan is written and reviewed.

```
MAJOR VERSION UPGRADE PLAN
============================
Prepared by: [YOUR NAME]
Date prepared: [DATE]
Reviewed by: [ENGINEERING LEAD]
Sign-off date: [DATE]

TARGET
------
Cluster: [CLUSTER_ID]
From: Aurora PostgreSQL [CURRENT_VERSION]
To: Aurora PostgreSQL [TARGET_VERSION]
Method: [ ] In-place  [ ] Blue/Green
Scheduled window: [DAY, DATE, TIME UTC]
Estimated duration: [X] minutes

RISK ASSESSMENT
---------------
Risk level: [ ] Low  [ ] Medium  [ ] High
Justification: [EXPLAIN]

Extensions verified: [ ] Yes  [ ] N/A
Custom parameter group needed: [ ] Yes  [ ] No
Application tested on target version: [ ] Yes  [ ] No

PRE-UPGRADE STEPS (T-7 days)
------------------------------
[ ] 1. Test upgrade on a cluster clone
[ ] 2. Create parameter group for target version (if custom)
[ ] 3. Application team completes compatibility testing
[ ] 4. Schedule maintenance window
[ ] 5. Prepare rollback procedure

DAY OF UPGRADE
--------------
[ ] 6. Verify no long-running transactions
[ ] 7. Notify application team
[ ] 8. Take pre-upgrade manual snapshot
[ ] 9. Wait for snapshot to reach "available"
[ ] 10. Initiate upgrade
[ ] 11. Monitor CloudWatch for errors
[ ] 12. Wait for cluster to return to "available"

POST-UPGRADE VALIDATION
------------------------
[ ] 13. SELECT version();
[ ] 14. Verify all extensions
[ ] 15. Run ANALYZE on all tables
[ ] 16. Run application smoke tests
[ ] 17. Monitor for 30 minutes

ROLLBACK PROCEDURE
------------------
Trigger condition: [WHAT CAUSES A ROLLBACK]
Rollback snapshot: [SNAPSHOT NAME]
Expected rollback time: [X] minutes

CONTACTS
--------
DBA: [NAME]
Engineering: [NAME]
Incident channel: [CHANNEL]
```

---

## Part 3 - Test the Upgrade on a Clone

### Step 3.1 - Take a Snapshot and Restore to a Test Cluster

```bash
export TEST_SNAPSHOT="devops-lab-upgrade-test-$(date +%Y%m%d)"
export TEST_CLUSTER="devops-lab-upgrade-test"
export TEST_INSTANCE="devops-lab-upgrade-test-inst"

aws rds create-db-cluster-snapshot \
  --db-cluster-identifier $CLUSTER_ID \
  --db-cluster-snapshot-identifier $TEST_SNAPSHOT \
  --region $AWS_REGION

aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier $TEST_SNAPSHOT \
  --region $AWS_REGION
```

Restore to a test cluster:

```bash
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier $TEST_CLUSTER \
  --snapshot-identifier $TEST_SNAPSHOT \
  --engine aurora-postgresql \
  --region $AWS_REGION

aws rds create-db-instance \
  --db-instance-identifier $TEST_INSTANCE \
  --db-cluster-identifier $TEST_CLUSTER \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql \
  --region $AWS_REGION

aws rds wait db-cluster-available \
  --db-cluster-identifier $TEST_CLUSTER \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier $TEST_INSTANCE \
  --region $AWS_REGION
```

### Step 3.2 - Upgrade the Test Cluster

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $TEST_CLUSTER \
  --engine-version $TARGET_VERSION \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region $AWS_REGION
```

`--allow-major-version-upgrade` is required for major upgrades. AWS makes you explicitly opt in.

Record the start time. Wait for completion:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier $TEST_CLUSTER \
  --region $AWS_REGION
```

Record the end time. Calculate the upgrade duration.

### Step 3.3 - Validate the Test Upgrade

```bash
export TEST_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $TEST_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

psql -h $TEST_HOST -U postgres -d postgres << 'EOF'
SELECT version();

SELECT name, installed_version FROM pg_available_extensions
WHERE installed_version IS NOT NULL;

SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY tablename;

ANALYZE;
EOF
```

### Step 3.4 - Cleanup Test Cluster

```bash
aws rds delete-db-instance \
  --db-instance-identifier $TEST_INSTANCE \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds wait db-instance-deleted \
  --db-instance-identifier $TEST_INSTANCE \
  --region $AWS_REGION

aws rds delete-db-cluster \
  --db-cluster-identifier $TEST_CLUSTER \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-cluster-snapshot \
  --db-cluster-snapshot-identifier $TEST_SNAPSHOT \
  --region $AWS_REGION
```

---

## Part 4 - Reflection Questions

Answer these in writing:

1. Why is `--allow-major-version-upgrade` a required flag? What problem does it solve?

2. If the test upgrade succeeds but production fails, what are the most likely causes?

3. After a major upgrade, `pg_stat_user_tables` shows dramatically different row estimates. Why? What should you do?

4. Your manager asks: "Can we roll back?" What is your honest answer?

5. Would you recommend in-place upgrade or Blue/Green for this cluster? Justify your answer.

---

## Summary

A good upgrade plan:
- Is written and reviewed before touching production
- Has been tested on a real clone of production data
- Includes explicit rollback steps with the snapshot identifier pre-recorded
- Has named contacts for every stakeholder
- Defines clear conditions for declaring success or triggering rollback
- Includes post-upgrade tasks (ANALYZE, extension updates, monitoring)

# USE 04 - Upgrade Planning
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 40 minutes
**Format:** Planning exercise + hands-on pre-checks. You write the upgrade plan before executing.
**Goal:** Produce a complete, signed-off upgrade plan for a major version upgrade from PostgreSQL 15 to 16.

---

## Scenario

You manage the database for [CLIENT], a mid-sized SaaS company. Their RDS PostgreSQL instance is running version `15.12`. AWS has announced that version 15 reaches end of life in November 2028, but your team wants to be on version 16 by Q3 2025.

The engineering team has asked you to plan the upgrade. You need to:
1. Determine if an upgrade is safe
2. Document every step
3. Get sign-off from the engineering lead before proceeding

---

## Part 1 - Gather Information (Pre-Planning Phase)

Before writing the plan, collect the facts.

### Step 1.1 - Check the Current State

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export AWS_REGION="us-east-1"
```

Collect all relevant information in one pass:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{
    Engine: Engine,
    Version: EngineVersion,
    Class: DBInstanceClass,
    Storage: AllocatedStorage,
    MultiAZ: MultiAZ,
    BackupRetention: BackupRetentionPeriod,
    MaintenanceWindow: PreferredMaintenanceWindow,
    AutoMinorUpgrade: AutoMinorVersionUpgrade,
    ParamGroup: DBParameterGroups[0].DBParameterGroupName,
    Status: DBInstanceStatus
  }' \
  --output table
```

Record all values.

### Step 1.2 - List Available Upgrade Targets

```bash
export CURRENT_VERSION=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].EngineVersion' \
  --output text)

aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version $CURRENT_VERSION \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[*].{Version:EngineVersion,Major:IsMajorVersionUpgrade}' \
  --output table
```

Identify the latest available PostgreSQL 16 version. Record it.

### Step 1.3 - Audit Installed Extensions

```bash
export DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT name, default_version, installed_version, comment FROM pg_available_extensions WHERE installed_version IS NOT NULL ORDER BY name;"
```

For each extension, verify it is available in PostgreSQL 16. Check:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version "16.2" \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].SupportedFeatureNames'
```

### Step 1.4 - Check for Deprecated Functions

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
-- Check for uses of functions that changed in PG16
-- PG16 removed some legacy functions
SELECT routine_schema, routine_name, routine_type
FROM information_schema.routines
WHERE routine_type IN ('FUNCTION', 'PROCEDURE')
AND routine_schema NOT IN ('pg_catalog', 'information_schema')
ORDER BY routine_name;
EOF
```

### Step 1.5 - Check the Parameter Group

```bash
export PARAM_GROUP=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text)

echo "Current parameter group: $PARAM_GROUP"
```

If using a custom parameter group (anything that does not start with `default.`), you need to create a new one for PG16:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name $PARAM_GROUP \
  --region $AWS_REGION \
  --query 'Parameters[?IsModifiable==`true` && ParameterValue!=null].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}' \
  --output table
```

List every custom parameter. You need to recreate these in the PG16 parameter group.

---

## Part 2 - Write the Upgrade Plan

Use the information from Part 1 to fill in this template. Do NOT start the actual upgrade until the plan is written and reviewed.

```
MAJOR VERSION UPGRADE PLAN
============================
Prepared by: [YOUR NAME]
Date prepared: [DATE]
Reviewed by: [ENGINEERING LEAD NAME]
Sign-off date: [DATE]

TARGET
------
Instance: [DB_INSTANCE]
From: PostgreSQL [CURRENT_VERSION]
To: PostgreSQL [TARGET_VERSION]
Scheduled window: [DAY, DATE, TIME UTC]
Estimated duration: [X] minutes

RISK ASSESSMENT
---------------
Risk level: [ ] Low  [ ] Medium  [ ] High
Justification: [EXPLAIN YOUR RISK RATING]

Extensions verified for PG16: [ ] Yes  [ ] N/A
Custom parameter group needed: [ ] Yes  [ ] No (using default)
Application tested on PG16: [ ] Yes  [ ] No (add to plan)
Rollback tested on clone: [ ] Yes  [ ] No

PRE-UPGRADE STEPS (T-7 days)
------------------------------
[ ] Step 1: Test upgrade on a clone (see testing section below)
[ ] Step 2: Create new parameter group for PG16 (if custom params used)
[ ] Step 3: Application team completes compatibility testing on clone
[ ] Step 4: Confirm upgrade window with all stakeholders
[ ] Step 5: Set maintenance window to upgrade window

PRE-UPGRADE STEPS (Day of upgrade, before window)
---------------------------------------------------
[ ] Step 6: Verify no long-running transactions
[ ] Step 7: Notify application team - maintenance starts in 1 hour
[ ] Step 8: Take a manual snapshot: [SNAPSHOT_NAME]
[ ] Step 9: Wait for snapshot to reach "available" status
[ ] Step 10: Record snapshot identifier for rollback use

UPGRADE EXECUTION (During window)
----------------------------------
[ ] Step 11: Initiate upgrade via CLI or Console
[ ] Step 12: Monitor CloudWatch for errors
[ ] Step 13: Wait for instance to return to "available"

POST-UPGRADE VALIDATION
------------------------
[ ] Step 14: Connect and run: SELECT version();
[ ] Step 15: Verify all extensions at correct version
[ ] Step 16: Run application smoke test suite
[ ] Step 17: Check CloudWatch for any new error patterns
[ ] Step 18: Monitor for 30 minutes before declaring success

ROLLBACK PROCEDURE (if needed)
--------------------------------
Trigger condition: [DESCRIBE WHAT WOULD CAUSE YOU TO ROLL BACK]
Rollback snapshot: [SNAPSHOT_NAME]

aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier [ROLLBACK_INSTANCE_NAME] \
  --db-snapshot-identifier [SNAPSHOT_NAME] \
  --region [REGION]

Expected rollback time: [X] minutes
Application cutover after rollback: [STEPS]

CONTACTS
---------
DBA on call: [NAME] - [PHONE/SLACK]
Engineering lead: [NAME] - [PHONE/SLACK]
Incident channel: [SLACK CHANNEL]
Escalation: [MANAGER NAME]
```

---

## Part 3 - Test the Upgrade on a Clone

Before executing on production, test the upgrade path on a clone.

### Step 3.1 - Create a Snapshot-Based Clone

For upgrade testing, use a snapshot restore rather than a fast clone. This is because you are testing the upgrade process itself, not just the data.

```bash
export PRE_UPGRADE_SNAPSHOT="suta-t5-upgrade-test-$(date +%Y%m%d)"

aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION

aws rds wait db-snapshot-available \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION
```

Restore to a test instance:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier "suta-t5-upgrade-test-hfa" \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --db-instance-class db.t3.micro \
  --region $AWS_REGION

aws rds wait db-instance-available \
  --db-instance-identifier "suta-t5-upgrade-test-hfa" \
  --region $AWS_REGION
```

### Step 3.2 - Upgrade the Test Instance

```bash
export TARGET_VERSION="16.2"

aws rds modify-db-instance \
  --db-instance-identifier "suta-t5-upgrade-test-hfa" \
  --engine-version $TARGET_VERSION \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region $AWS_REGION
```

Record the start time. Record when it completes.

### Step 3.3 - Validate the Test Upgrade

```bash
export TEST_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier "suta-t5-upgrade-test-hfa" \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $TEST_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

Run your application test suite against the test instance. Check:

```bash
psql -h $TEST_HOST -U postgres -d postgres << 'EOF'
-- All extensions should be present
SELECT name, installed_version FROM pg_available_extensions
WHERE installed_version IS NOT NULL;

-- All tables should have the correct row counts
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY tablename;

-- Run ANALYZE to update statistics (always do this after major upgrade)
ANALYZE;
EOF
```

### Step 3.4 - Document Test Results

Fill in this section of the plan:

```
UPGRADE TEST RESULTS (from clone test)
=======================================

Test instance: suta-t5-upgrade-test-hfa
Test date: [DATE]

Upgrade duration: [X] minutes
Extensions after upgrade: [LIST]
Row counts match pre-upgrade: [ ] Yes  [ ] No
Application smoke tests: [ ] PASS  [ ] FAIL
Application test failures: [LIST ANY FAILURES]

Decision:
[ ] Proceed with production upgrade as planned
[ ] Delay - issues found: [DESCRIBE]
```

### Step 3.5 - Cleanup Test Instance

```bash
aws rds delete-db-instance \
  --db-instance-identifier "suta-t5-upgrade-test-hfa" \
  --skip-final-snapshot \
  --region $AWS_REGION

aws rds delete-db-snapshot \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION
```

---

## Part 4 - Reflection Questions

Answer these in writing before moving on:

1. Why is `--allow-major-version-upgrade` a required flag? What problem does forcing this explicit opt-in solve?

2. If the upgrade on the test clone succeeded but the production upgrade fails, what are the most likely causes of the difference?

3. You discover that one extension (`pg_hint_plan`) is not supported in PostgreSQL 16 by AWS. What are your options? List at least three.

4. Your manager asks: "Can we roll back the upgrade if something goes wrong?" What is your honest answer, including the trade-offs?

5. After a major upgrade, pg_stat_user_tables shows dramatically different row estimates. Why? What should you do?

---

## Summary

A good upgrade plan:
- Is written and reviewed before touching production
- Has been tested on a real clone of production data
- Includes explicit rollback steps with the snapshot identifier pre-recorded
- Has named contacts for every stakeholder
- Defines clear conditions for declaring success or triggering rollback
- Includes post-upgrade tasks (ANALYZE, extension updates, monitoring)

The planning process is as important as the upgrade itself.

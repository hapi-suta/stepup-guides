# BUILD 04 - Engine Version Upgrades
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 45 minutes
**Goal:** Check available upgrade versions, run pre-upgrade checks, perform a minor version upgrade, plan a major version upgrade, and understand the rollback strategy.

**Warning:** Major version upgrades cannot be reversed in-place. Always take a manual snapshot before upgrading. This is covered in Step 3.

**Prerequisites:**
- An RDS PostgreSQL instance (db.t3.micro)
- AWS CLI configured with rds permissions
- At least one version upgrade available (check in Step 2)

---

## Step 1 - Set Your Variables

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export AWS_REGION="us-east-1"
export PRE_UPGRADE_SNAPSHOT="suta-t5-pre-upgrade-$(date +%Y%m%d)"
```

---

## Step 2 - Check the Current Version and Available Upgrades

### Check Current Version

### Console

1. Open **RDS > Databases**.
2. Click your instance.
3. Under **Configuration**, look for **Engine version** (e.g., `16.6`).

### CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Engine:Engine,EngineVersion:EngineVersion,AutoMinorVersionUpgrade:AutoMinorVersionUpgrade}' \
  --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------
|               DescribeDBInstances                   |
+------------------------+----------------------------+
|  AutoMinorVersionUpgrade | true                     |
|  Engine                  | postgres                 |
|  EngineVersion           | 15.4                     |
+------------------------+----------------------------+
```

`AutoMinorVersionUpgrade: true` means AWS will automatically apply minor version upgrades during your maintenance window. Set to `false` to control this yourself.

### Check Available Upgrade Targets

Store your current version:

```bash
export CURRENT_VERSION=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].EngineVersion' \
  --output text)

echo "Current version: $CURRENT_VERSION"
```

List valid upgrade targets for your current version:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version $CURRENT_VERSION \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[*].{TargetVersion:EngineVersion,MajorVersionUpgrade:IsMajorVersionUpgrade,AutoUpgrade:AutoUpgrade}' \
  --output table
```

`ValidUpgradeTarget` lists every version you can upgrade to from your current version.
`IsMajorVersionUpgrade` tells you if the upgrade crosses a major version boundary.
`AutoUpgrade` indicates if AWS will apply this upgrade automatically.

Expected output (yours will differ):

```
---------------------------------------------------------------------
|               DescribeDBEngineVersions                            |
+---------------------+------------------------+--------------------+
|  AutoUpgrade        |  MajorVersionUpgrade   |  TargetVersion     |
+---------------------+------------------------+--------------------+
|  True               |  False                 |  15.5              |
|  True               |  False                 |  15.6              |
|  False              |  True                  |  16.1              |
|  False              |  True                  |  16.2              |
+---------------------+------------------------+--------------------+
```

Minor upgrades (16.4 -> 16.6) have `AutoUpgrade: True`.
Major upgrades (15.x -> 16.x) have `AutoUpgrade: False` - these are never automatic.

---

## Step 3 - Take a Pre-Upgrade Snapshot (Required)

Before ANY upgrade - minor or major - take a manual snapshot. This is your rollback point.

```bash
aws rds create-db-snapshot \
  --db-instance-identifier $DB_INSTANCE \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION
```

Wait for the snapshot to complete:

```bash
aws rds wait db-snapshot-available \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION
```

Confirm it is ready:

```bash
aws rds describe-db-snapshots \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION \
  --query 'DBSnapshots[0].{Status:Status,Created:SnapshotCreateTime}' \
  --output table
```

Expected output:

```
-------------------------------------------
|         DescribeDBSnapshots             |
+----------+------------------------------+
|  Created |  2025-05-30T08:14:22.000Z    |
|  Status  |  available                   |
+----------+------------------------------+
```

---

## Step 4 - Run Pre-Upgrade Checks

Before upgrading, check for known incompatibilities.

### Check Installed Extensions

Connect to your database and list extensions:

```bash
export DB_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE installed_version IS NOT NULL ORDER BY name;"
```

Expected output (yours will differ):

```
        name        | default_version | installed_version
--------------------+-----------------+-------------------
 pg_stat_statements | 1.10            | 1.10
 pgcrypto           | 1.3             | 1.3
 plpgsql            | 1.0             | 1.0
(3 rows)
```

Cross-reference each extension against the target version's supported extensions:

```bash
export TARGET_VERSION="15.6"

aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version $TARGET_VERSION \
  --region $AWS_REGION \
  --query 'DBEngineVersions[0].SupportedFeatureNames' \
  --output text
```

Also check the RDS documentation for the target version's extension support matrix.

### Check for Deprecated Functions

For major version upgrades, connect and check for use of deprecated functions:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT routine_schema, routine_name FROM information_schema.routines WHERE routine_type = 'FUNCTION' ORDER BY routine_name LIMIT 20;"
```

For PostgreSQL 16 specifically, check for removed functions:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT pg_get_function_result(oid) FROM pg_proc WHERE proname IN ('to_timestamp', 'to_char') LIMIT 5;"
```

### Check Parameter Groups

List custom parameters that differ from defaults:

```bash
export PARAM_GROUP=$(aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].DBParameterGroups[0].DBParameterGroupName' \
  --output text)

echo "Parameter group: $PARAM_GROUP"
```

If you use the default parameter group (`default.postgres15`), you must create a new one for the target version (`default.postgres16` will be assigned automatically during major upgrade). If you have a custom group, you need to create a new custom group for the target version.

---

## Step 5 - Perform a Minor Version Upgrade

Minor upgrades are low risk. They still require a reboot.

Set the target minor version:

```bash
export TARGET_MINOR_VERSION="15.6"
```

Replace with an actual available minor version from Step 2.

### Console

1. Click your instance in RDS.
2. Click **Modify**.
3. Under **DB engine version**, select the target minor version from the dropdown.
4. Scroll down and click **Continue**.
5. Select **Apply during the next scheduled maintenance window** or **Apply immediately**.
6. Click **Modify DB Instance**.

### CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --engine-version $TARGET_MINOR_VERSION \
  --apply-immediately \
  --region $AWS_REGION
```

`--engine-version` specifies the exact target version string.
`--apply-immediately` causes the upgrade (and reboot) to happen now instead of at the next maintenance window.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-t5-primary-hfa",
        "DBInstanceStatus": "upgrading",
        "PendingModifiedValues": {
            "EngineVersion": "15.6"
        }
    }
}
```

Wait for the upgrade to complete (the instance reboots during this process):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION
```

Verify the new version:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].EngineVersion'
```

Expected output:

```
"15.6"
```

---

## Step 6 - Plan a Major Version Upgrade

Major upgrades cross a major version boundary (e.g., 15 -> 16). They carry more risk and require a formal plan.

### Pre-Upgrade Checklist

Work through this checklist before every major upgrade:

```
PRE-MAJOR-UPGRADE CHECKLIST
============================

[ ] 1. Manual snapshot taken (your rollback point)
[ ] 2. All extensions verified as available in target version
[ ] 3. Custom parameter group created for target version
[ ] 4. Application tested against target version on a clone
[ ] 5. Application team informed of maintenance window
[ ] 6. Rollback procedure documented and shared
[ ] 7. Monitoring alerts reviewed (may need threshold adjustments)
[ ] 8. pg_upgrade pre-check run on a test instance first
[ ] 9. Read release notes for breaking changes:
        https://www.postgresql.org/docs/release/
[ ] 10. Upgrade scheduled in low-traffic window
```

### Create a Custom Parameter Group for the Target Version

If you use the default parameter group, skip this step. AWS handles it automatically.

If you have a custom parameter group for your current version, create a new one for the target:

```bash
export TARGET_MAJOR_VERSION="16"

aws rds create-db-parameter-group \
  --db-parameter-group-name "suta-t5-pg${TARGET_MAJOR_VERSION}-params" \
  --db-parameter-group-family "postgres${TARGET_MAJOR_VERSION}" \
  --description "Custom params for PostgreSQL ${TARGET_MAJOR_VERSION} upgrade" \
  --region $AWS_REGION
```

`--db-parameter-group-family` must match the exact family name for the target version.

Then migrate your custom parameters from the old group to the new one. Review each parameter - some may have changed defaults or been removed in the new version.

### Execute the Major Version Upgrade

```bash
export TARGET_MAJOR_ENGINE_VERSION="16.2"

aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --engine-version $TARGET_MAJOR_ENGINE_VERSION \
  --allow-major-version-upgrade \
  --apply-immediately \
  --region $AWS_REGION
```

`--allow-major-version-upgrade` is a required flag for major upgrades. AWS makes you explicitly opt in so you cannot do this accidentally.

> **Concept:** Major upgrades take longer than minor upgrades. A typical db.t3.micro may take 10-20 minutes. Larger instances can take 30+ minutes. Plan your maintenance window accordingly.

Wait for the upgrade:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION
```

Verify the new major version:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].EngineVersion'
```

---

## Step 7 - Post-Upgrade Validation

After any upgrade, run these checks:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                    version
-------------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.2 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-17), 64-bit
(1 row)
```

Check extensions updated correctly:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT name, installed_version, default_version FROM pg_available_extensions WHERE installed_version IS NOT NULL;"
```

If any extension shows `installed_version` less than `default_version`, update it:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "ALTER EXTENSION pg_stat_statements UPDATE;"
```

Run a quick sanity check on your data:

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT schemaname, tablename, pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename;"
```

---

## Step 8 - Rollback Strategy

You cannot downgrade an RDS instance in-place. Rollback means restoring from the pre-upgrade snapshot.

```
ROLLBACK PROCEDURE (if upgrade breaks your application)
========================================================

1. Stop application traffic (or route to read replica if you have one)

2. Create a new instance from your pre-upgrade snapshot:
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier suta-t5-rollback-hfa \
     --db-snapshot-identifier suta-t5-pre-upgrade-20250530 \
     --region us-east-1

3. Wait for the restored instance to become available

4. Verify data integrity on the restored instance

5. Update application connection string to the restored instance

6. Test application fully

7. If OK, delete the failed upgraded instance

8. Rename or keep the restored instance as your new primary

IMPORTANT: Any data written between upgrade start and rollback is LOST.
This is why you want the upgrade window to be as short as possible,
and why you should stop writes during a major upgrade if possible.
```

---

## Step 9 - Disable Auto Minor Version Upgrade (Optional)

If you want to control when minor upgrades happen instead of letting AWS do it automatically:

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --no-auto-minor-version-upgrade \
  --region $AWS_REGION
```

`--no-auto-minor-version-upgrade` disables automatic minor upgrades. You will then need to apply minor upgrades manually using the steps in Step 5.

---

## Cleanup

The pre-upgrade snapshot can be kept for 30 days after a successful upgrade as a safety net, then deleted:

```bash
aws rds delete-db-snapshot \
  --db-snapshot-identifier $PRE_UPGRADE_SNAPSHOT \
  --region $AWS_REGION
```

---

## Summary

You can now:
- Check the current engine version and list all available upgrade targets
- Identify which upgrades are minor vs major
- Run pre-upgrade checks for extensions and parameter groups
- Take a pre-upgrade snapshot as a rollback point
- Perform a minor version upgrade with apply-immediately
- Plan and execute a major version upgrade with `--allow-major-version-upgrade`
- Describe the rollback procedure (restore from pre-upgrade snapshot)

**Next:** BUILD 05 - Blue/Green Deployments

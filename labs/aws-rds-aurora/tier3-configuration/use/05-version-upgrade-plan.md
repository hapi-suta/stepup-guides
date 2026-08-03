# USE 05 - Version Upgrade Plan

**Time:** 20 minutes (planning exercise - minimal hands-on)
**Level:** Intermediate
**Prerequisite:** BUILD 07 completed

---

## Scenario

[CLIENT]'s production database is running PostgreSQL 14 on RDS. PostgreSQL 14 reaches AWS standard support end in February 2027. The database must be upgraded to PostgreSQL 16 before that date.

**Current state:**
- Engine: PostgreSQL 14.12
- Instance: db.r6g.2xlarge
- Storage: 800 GB gp3
- Database size: 320 GB
- Extensions in use: pg_stat_statements, pgaudit, postgis, pg_repack
- Running: 24/7 with a 4-hour weekend maintenance window

Your job is to build a complete upgrade plan that the team can execute safely.

---

## Step 1 - Gather Current State

Before planning anything, document exactly what you have.

**Check current version:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres -c "SELECT version();"
```

**List all installed extensions:**

```sql
SELECT name, installed_version, default_version
FROM pg_available_extensions
WHERE installed_version IS NOT NULL
ORDER BY name;
```

Write down every extension and its version. You will check each one against the target version.

**List all databases on the instance:**

```sql
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
WHERE datistemplate = false
ORDER BY pg_database_size(datname) DESC;
```

**Find the largest tables (upgrade time is proportional to data size):**

```sql
SELECT
  schemaname || '.' || relname AS table_name,
  pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(oid) DESC
LIMIT 10;
```

**Check for any active long-running transactions:**

```sql
SELECT pid, now() - query_start AS duration, state, LEFT(query, 80) AS query
FROM pg_stat_activity
WHERE query_start < now() - interval '5 minutes'
  AND state != 'idle'
ORDER BY duration DESC;
```

---

## Step 2 - Check Extension Compatibility

Each extension must be available on the target PostgreSQL version. AWS controls this.

**Check what's available on PostgreSQL 16:**

```bash
# Create a temporary PostgreSQL 16 instance to check
aws rds create-db-instance \
  --db-instance-identifier upgrade-test-pg16 \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --engine-version 16.4 \
  --master-username postgres \
  --master-user-password [TEMP-PASSWORD] \
  --db-subnet-group-name [YOUR-SUBNET-GROUP] \
  --no-publicly-accessible \
  --storage-type gp3 \
  --allocated-storage 20
```

**Wait for the test instance:**

```bash
aws rds wait db-instance-available \
  --db-instance-identifier upgrade-test-pg16
```

**Connect and check extension availability:**

```bash
psql -h [TEST-INSTANCE-ENDPOINT] -U postgres -d postgres
```

```sql
SELECT name, default_version
FROM pg_available_extensions
WHERE name IN ('pg_stat_statements', 'pgaudit', 'postgis', 'pg_repack')
ORDER BY name;
```

**Record the results:**

| Extension | PG14 Version | PG16 Available? | PG16 Version |
|---|---|---|---|
| pg_stat_statements | 1.9 | | |
| pgaudit | 14.0 | | |
| postgis | 3.3.x | | |
| pg_repack | 1.4.8 | | |

Fill in the right two columns from your test instance query.

**Delete the test instance when done:**

```bash
aws rds delete-db-instance \
  --db-instance-identifier upgrade-test-pg16 \
  --skip-final-snapshot
```

---

## Step 3 - Check for PostgreSQL 16 Breaking Changes

PostgreSQL 14 to 16 spans two major versions. Read the release notes for both 15 and 16.

**Key changes between PG14 and PG16 to check:**

1. **pg_stat_activity.query_id column** (new in PG14, enhanced in PG16) - check if your monitoring queries reference specific column names that changed

2. **Default privileges** - verify application users still have the permissions they need after upgrade

3. **Case-sensitive collations** - if you use ICU collations, check for any changes

4. **Logical replication** - if you use logical replication, verify subscriber compatibility

5. **JSON handling** - some JSON functions changed behavior; test your JSON queries

**Write a compatibility test script for your application:**

```sql
-- Test all critical application queries
-- Add your actual production queries here

-- Example: Test a complex query that the app relies on
EXPLAIN (ANALYZE, BUFFERS)
SELECT /* your critical query here */ ;

-- Example: Test JSON operations if your app uses them
SELECT '{"key": "value"}'::jsonb -> 'key';

-- Example: Test PostGIS if you use it
SELECT ST_AsText(ST_MakePoint(-73.9857, 40.7484));
```

---

## Step 4 - Build the Upgrade Timeline

A major upgrade from PG14 to PG16 should not be a same-day decision.

### Recommended Timeline

```
Week 1-2: Preparation
  - [ ] Document all extensions and verify PG16 compatibility
  - [ ] Restore a snapshot to a PG16 test instance (see Step 5)
  - [ ] Run application test suite against PG16 test instance
  - [ ] Fix any compatibility issues found

Week 3: Test Upgrade Dry Run
  - [ ] Restore a fresh snapshot to test instance
  - [ ] Perform the upgrade on the test instance
  - [ ] Measure actual upgrade time (for maintenance window planning)
  - [ ] Verify all extensions work post-upgrade
  - [ ] Run full application integration tests

Week 4: Staging Upgrade
  - [ ] Upgrade staging environment to PG16
  - [ ] Run staging for 1 week with real workload patterns
  - [ ] Monitor for anomalies in pg_stat_statements
  - [ ] Fix any performance regressions

Week 5: Production Upgrade
  - [ ] Notify all teams of maintenance window
  - [ ] Take final snapshot before upgrade
  - [ ] Execute upgrade during maintenance window
  - [ ] Verify and monitor post-upgrade
```

---

## Step 5 - Restore a Snapshot to a PG16 Test Instance

You cannot in-place test a major upgrade. The safe approach is to restore an existing snapshot to a new PG16 instance.

> **Important:** AWS allows snapshot restores to a higher major version. It does NOT allow you to upgrade the original instance without downtime.

```bash
# Get the latest snapshot of your production instance
aws rds describe-db-snapshots \
  --db-instance-identifier [YOUR-PROD-INSTANCE] \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].DBSnapshotIdentifier' \
  --output text
```

```bash
# Restore to a new PG16 instance
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier upgrade-test-from-snap \
  --db-snapshot-identifier [SNAPSHOT-ID-FROM-ABOVE] \
  --db-instance-class db.t3.medium \
  --engine-version 16.4 \
  --no-publicly-accessible \
  --db-subnet-group-name [YOUR-SUBNET-GROUP]
```

Replace `[SNAPSHOT-ID-FROM-ABOVE]` with the snapshot identifier returned from the previous command.

```bash
# Wait for the restore to complete (can take 20-60 minutes for large databases)
aws rds wait db-instance-available \
  --db-instance-identifier upgrade-test-from-snap
```

**After restore - run your compatibility tests:**

```bash
psql -h [TEST-INSTANCE-ENDPOINT] -U [USERNAME] -d [DBNAME]
```

```sql
-- Verify all extensions still work
\dx

-- Run your application's critical queries
-- Check pg_stat_statements data carried over
SELECT COUNT(*) FROM pg_stat_statements;

-- Verify PostGIS if used
SELECT PostGIS_Full_Version();

-- Verify pgaudit is still configured
SHOW pgaudit.log;
```

---

## Step 6 - Execute the Production Upgrade

Once testing is complete, execute the production upgrade.

### Pre-Upgrade Checklist

```
Before starting:
  [ ] Final manual snapshot taken
  [ ] All team leads notified
  [ ] Maintenance window confirmed
  [ ] Application can be put in maintenance mode
  [ ] Rollback plan documented (restore from pre-upgrade snapshot)
  [ ] On-call coverage confirmed for post-upgrade monitoring
```

### The Upgrade Command

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-PROD-INSTANCE] \
  --engine-version 16.4 \
  --allow-major-version-upgrade \
  --apply-immediately
```

The `--allow-major-version-upgrade` flag is required for major version upgrades. Without it, AWS returns an error as a safety check.

### Monitor the Upgrade

```bash
# Check upgrade status
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-PROD-INSTANCE] \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Version:EngineVersion}'
```

Expected output during upgrade:
```json
{
    "Status": "upgrading",
    "Version": "14.12"
}
```

Expected output when complete:
```json
{
    "Status": "available",
    "Version": "16.4"
}
```

```bash
# Wait for completion
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-PROD-INSTANCE]
```

---

## Step 7 - Post-Upgrade Verification

After the upgrade completes, verify everything before re-enabling application traffic.

```sql
-- Confirm version
SELECT version();

-- Confirm all extensions are installed
\dx

-- Check parameter group is still attached correctly
-- (verify in console or CLI)

-- Confirm pg_stat_statements has data
SELECT COUNT(*) FROM pg_stat_statements;

-- Run the application health check queries
```

```bash
# Check the parameter group status
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-PROD-INSTANCE] \
  --query 'DBInstances[0].DBParameterGroups'
```

Confirm `ParameterApplyStatus: in-sync`. If it shows `pending-reboot`, a second reboot may be needed.

---

## Rollback Plan

If the upgrade fails or the application breaks:

```
Option 1 - Restore pre-upgrade snapshot (data loss to snapshot time):
  - aws rds restore-db-instance-from-db-snapshot
  - Point application to restored instance endpoint
  - Acceptable if the upgrade window was short

Option 2 - AWS support (if upgrade itself failed mid-way):
  - Contact AWS support immediately
  - They can assist with recovery from a failed major upgrade

Note: You CANNOT downgrade a PostgreSQL major version in place.
      Point-in-time restore (PITR) to before the upgrade is your rollback.
```

---

## Upgrade Summary Table

| Phase | Action | Estimated Time |
|---|---|---|
| Preparation | Extension check, test instance, app tests | 1-2 weeks |
| Dry run | Snapshot restore + upgrade test | 1 day |
| Staging | Upgrade staging, 1 week soak | 1-2 weeks |
| Pre-upgrade | Snapshot + notifications | 30 minutes |
| Upgrade | `modify-db-instance --engine-version` | 15-45 minutes |
| Post-upgrade | Verification + monitoring | 30 minutes |
| **Total elapsed** | | **3-4 weeks** |

---

## Discussion Questions

1. Why can't you just restore a PG14 snapshot directly to PG16 without creating a new instance?

2. The upgrade fails at 60% completion. The database is in an unknown state. What is your immediate next action?

3. Your app team says they need zero downtime for the upgrade. Is that possible with RDS major version upgrades? What alternatives exist?

4. After the upgrade, queries that were fast on PG14 are 3x slower on PG16. What is the most likely cause and first step to investigate?

5. A developer says "just run the upgrade - it only takes a few minutes." What is wrong with this approach?

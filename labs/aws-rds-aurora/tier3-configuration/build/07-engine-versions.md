# BUILD 07 - Engine Versions

**Time:** 20 minutes
**Goal:** List available PostgreSQL versions on RDS, understand major vs minor version differences, check your current version, plan an upgrade path, and understand the Preview Environment.

---

## Prerequisites

- AWS CLI configured
- RDS PostgreSQL instance running
- psql access

---

## Part 1 - List Available Engine Versions

### Console Steps

1. Open the AWS Console and go to **RDS**.
2. Click **Databases** in the left sidebar.
3. Click **Create database** (you won't actually create one - just explore).
4. Under **Engine options**, select **PostgreSQL**.
5. The **Version** dropdown shows all available versions.
6. Click **Cancel** when done exploring.

### CLI Steps

**List all available PostgreSQL major versions:**

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[*].MajorEngineVersion' \
  --output text | tr '\t' '\n' | sort -u
```

The `tr '\t' '\n'` command converts the tab-separated output into one version per line. The `sort -u` removes duplicates.

Expected output (yours will differ):
```
13
14
15
16
17
```

**List all available versions including minor versions:**

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[*].{Version:EngineVersion,Status:Status}' \
  --output table
```

Expected output (yours will differ):
```
----------------------------
|DescribeDBEngineVersions  |
+-------+------------------+
|Status |     Version      |
+-------+------------------+
|available| 13.18          |
|available| 14.15          |
|available| 15.10          |
|available| 16.6           |
|available| 17.2           |
+-------+------------------+
```

**Filter to only the latest minor version of each major:**

JMESPath does not support grouping, so the AWS CLI alone cannot do this in one query. Use a shell pipeline instead:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --query 'DBEngineVersions[*].EngineVersion' \
  --output text | tr '\t' '\n' | sort -V | \
  awk -F'.' '{if (major != $1) {if (NR>1) print prev; major=$1} prev=$0} END {print prev}'
```

The `sort -V` sorts version strings correctly (so `9.6` < `10` < `13` < `17`). The `awk` command tracks the current major version and prints only the last (highest) version it sees for each major - which, after the sort, is the latest minor for that major.

Expected output (yours will differ):
```
13.18
14.15
15.10
16.6
17.2
```

**List versions available in your specific region:**

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --region [YOUR-REGION] \
  --query 'DBEngineVersions[*].EngineVersion' \
  --output table
```

Replace `[YOUR-REGION]` with your AWS region (e.g., `us-east-1`).

---

## Part 2 - Check Your Current Version

### In the Console

1. Go to **RDS > Databases**.
2. Click on your instance.
3. On the **Configuration** tab, look for **Engine version**.

### Via CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].{EngineVersion:EngineVersion,AutoMinorVersionUpgrade:AutoMinorVersionUpgrade,PendingModifiedValues:PendingModifiedValues}' \
  --output json
```

Expected output (yours will differ):
```json
{
    "EngineVersion": "16.4",
    "AutoMinorVersionUpgrade": true,
    "PendingModifiedValues": {}
}
```

`AutoMinorVersionUpgrade: true` means AWS will automatically upgrade your minor version during maintenance windows. This is on by default - be aware of it.

### In psql

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres -c "SELECT version();"
```

Expected output (yours will differ):
```
                                                    version
---------------------------------------------------------------------------------------------------------------
 PostgreSQL 16.4 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 9.5.0 20211210, 64-bit
(1 row)
```

```sql
-- Just the version number
SELECT current_setting('server_version');
```

Expected output (yours will differ):
```
 current_setting
-----------------
 16.4
(1 row)
```

---

## Part 3 - Major vs Minor Versions

Understanding the difference matters for planning maintenance.

| | Minor Upgrade | Major Upgrade |
|---|---|---|
| Example | 16.3 -> 16.4 | 15.x -> 16.x |
| Downtime | Brief restart (1-3 min) | Longer (5-30+ min) |
| Backwards compatible | Always | Not guaranteed |
| Data format change | No | Sometimes |
| Extension compatibility | No risk | Must verify |
| Can rollback | Reboot to previous minor | Very difficult |
| Trigger | Automatic or manual | Manual only |

### Check If a Minor Upgrade Is Available

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].PendingModifiedValues.EngineVersion'
```

If output is null, you are on the latest minor version.

### Check Available Upgrade Targets

This command shows what versions your current instance can upgrade to:

```bash
aws rds describe-db-engine-versions \
  --engine postgres \
  --engine-version [YOUR-CURRENT-VERSION] \
  --query 'DBEngineVersions[0].ValidUpgradeTarget[*].{Version:EngineVersion,Major:IsMajorVersionUpgrade,AutoUpgrade:AutoUpgrade}' \
  --output table
```

Replace `[YOUR-CURRENT-VERSION]` with your current version like `16.4`.

Expected output (yours will differ):
```
----------------------------------------------------
|          DescribeDBEngineVersions                |
+-------+----------------+-------------------------+
| Auto  |   Major        |         Version         |
+-------+----------------+-------------------------+
| False |  False         |  16.5                   |
| False |  False         |  16.6                   |
| False |  True          |  17.2                   |
+-------+----------------+-------------------------+
```

- Rows with `Major: False` are minor version upgrades (safe)
- Rows with `Major: True` are major version upgrades (plan carefully)

---

## Part 4 - Perform a Minor Version Upgrade

Minor upgrades are low risk. Always test in non-production first.

### Console Steps

1. Go to **RDS > Databases**.
2. Select your instance.
3. Click **Modify**.
4. Scroll to **Engine version** under **DB engine version**.
5. Select the newer minor version from the dropdown.
6. Click **Continue**.
7. Choose when to apply:
   - **Apply during next scheduled maintenance window** - safer for production
   - **Apply immediately** - causes an immediate restart
8. Click **Modify DB instance**.

### CLI Steps

**Step 1 - Apply the minor version upgrade:**

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --engine-version [TARGET-VERSION] \
  --allow-major-version-upgrade false \
  --apply-immediately
```

Replace `[TARGET-VERSION]` with the target minor version. The `--allow-major-version-upgrade false` flag is a safety guard - it prevents accidental major upgrades.

**Step 2 - Wait for the instance to complete the upgrade:**

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

**Step 3 - Confirm the new version:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].EngineVersion'
```

---

## Part 5 - Plan a Major Version Upgrade (Overview)

> **Note:** Major version upgrades are covered in depth in [USE 05 - Version Upgrade Plan](../use/05-version-upgrade-plan.md). This section gives the overview.

### The Major Upgrade Checklist

Before upgrading from PostgreSQL 15 to 16 (for example):

```
1. Check extension compatibility
   - Every extension must have a version available for the target PG version
   - Check: SELECT name, default_version FROM pg_available_extensions;
   - Then check AWS docs for the target version's supported extensions

2. Check for deprecated syntax or removed features
   - Read the PostgreSQL release notes for each version between current and target
   - Key place: https://www.postgresql.org/docs/release/

3. Run pg_upgrade compatibility check (for self-managed)
   - On RDS, AWS handles this, but you can verify with pre-upgrade checks

4. Test in a non-production environment first
   - Restore a snapshot to a new instance with the target version
   - Run your full application test suite

5. Plan your maintenance window
   - Major upgrade requires longer downtime than minor
   - Estimate based on database size: roughly 1-5 min per GB for large databases

6. Notify stakeholders
   - Downtime window confirmed?
   - Rollback plan ready?
```

---

## Part 6 - Preview Environment

AWS runs a PostgreSQL Preview Environment where new major versions are available before GA.

**Why use it:**
- Test your app against the next major version months before it's required
- Verify extension compatibility early
- Find breaking changes with no production risk

**Key limitations:**
- Not for production workloads
- Databases may be deleted when the version reaches GA
- Not all regions available
- Some features may not be fully supported

### Access the Preview Environment

```bash
# List versions available in the preview environment
aws rds describe-db-engine-versions \
  --engine postgres \
  --include-all \
  --query 'DBEngineVersions[?Status==`preview`].{Version:EngineVersion,Status:Status}' \
  --output table
```

Expected output (yours will differ):
```
-----------------------------
|DescribeDBEngineVersions   |
+-------------+-------------+
|   Status    |   Version   |
+-------------+-------------+
|  preview    |  17.x       |
+-------------+-------------+
```

> **Note:** The preview environment uses a separate RDS console endpoint. Check the AWS documentation for the current preview region and URL.

---

## Auto Minor Version Upgrade Setting

AWS can automatically upgrade your instance to the latest minor version during your maintenance window.

**Check the current setting:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].AutoMinorVersionUpgrade'
```

**Disable auto minor version upgrades (for more control):**

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --no-auto-minor-version-upgrade \
  --apply-immediately
```

**Enable auto minor version upgrades:**

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --auto-minor-version-upgrade \
  --apply-immediately
```

> **Recommendation for production:** Disable auto minor version upgrades. Test each minor version before applying. Unexpected reboots during maintenance windows can surprise application teams.

---

## Summary

| Task | Command |
|---|---|
| List available versions | `aws rds describe-db-engine-versions --engine postgres` |
| Check current version | `aws rds describe-db-instances ... --query EngineVersion` |
| Find upgrade targets | `describe-db-engine-versions --engine-version [CURRENT]` |
| Apply minor upgrade | `aws rds modify-db-instance --engine-version [TARGET]` |
| Control auto minor upgrades | `--auto-minor-version-upgrade` or `--no-auto-minor-version-upgrade` |

---

## Next Steps

- [USE 05 - Version Upgrade Plan](../use/05-version-upgrade-plan.md)
- [SURVIVE Scenarios](../survive/)
- [Interview Questions](../interview/tier3-interview-questions.md)

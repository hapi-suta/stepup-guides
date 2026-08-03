# BUILD 01 - Parameter Groups

**Time:** 40 minutes
**Goal:** Create a custom parameter group, modify parameters, understand apply timing, and reboot to apply static changes.

---

## Prerequisites

- RDS PostgreSQL instance running (db.t3.micro is fine)
- AWS CLI configured (`aws configure`)
- psql available on your machine or a jump host
- Your instance endpoint, username, and password

---

## Part 1 - Create a Custom DB Parameter Group (RDS PostgreSQL)

### Console Steps

1. Open the AWS Console and go to **RDS**.
2. In the left sidebar, click **Parameter groups**.
3. Click the orange **Create parameter group** button.
4. Fill in the form:
   - **Parameter group family:** `postgres16` (match your engine version)
   - **Type:** `DB Parameter Group`
   - **Group name:** `tier3-custom-pg16`
   - **Description:** `Custom parameter group for tier3 labs`
5. Click **Create**.

You will see your new group in the list with Status: `in-sync`.

---

### CLI Steps

**Step 1 - Create the parameter group.**

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --db-parameter-group-family postgres16 \
  --description "Custom parameter group for tier3 labs"
```

The `--db-parameter-group-family` flag specifies the PostgreSQL major version family. Use `postgres16` for PostgreSQL 16.x.

Expected output (yours will differ):
```
{
    "DBParameterGroup": {
        "DBParameterGroupName": "tier3-custom-pg16",
        "DBParameterGroupFamily": "postgres16",
        "Description": "Custom parameter group for tier3 labs",
        "DBParameterGroupArn": "arn:aws:rds:us-east-1:123456789012:pg:tier3-custom-pg16"
    }
}
```

**Step 2 - Verify the parameter group was created.**

```bash
aws rds describe-db-parameter-groups \
  --db-parameter-group-name tier3-custom-pg16 \
  --query 'DBParameterGroups[0].{Name:DBParameterGroupName,Family:DBParameterGroupFamily,Description:Description}'
```

Expected output (yours will differ):
```
{
    "Name": "tier3-custom-pg16",
    "Family": "postgres16",
    "Description": "Custom parameter group for tier3 labs"
}
```

---

## Part 2 - Create a Cluster Parameter Group (Aurora PostgreSQL)

Aurora needs a second type: the **cluster parameter group**. This applies to all instances in the Aurora cluster.

> **Concept:** In Aurora, the cluster parameter group holds most settings. The DB parameter group (per-instance) handles only a few instance-specific overrides. When in doubt, put your setting in the cluster parameter group.

### Console Steps

1. In the RDS console, click **Parameter groups** in the left sidebar.
2. Click **Create parameter group**.
3. Fill in the form:
   - **Parameter group family:** `aurora-postgresql16`
   - **Type:** `DB Cluster Parameter Group`
   - **Group name:** `tier3-aurora-cluster-pg16`
   - **Description:** `Aurora cluster parameter group for tier3 labs`
4. Click **Create**.

### CLI Steps

**Step 1 - Create the cluster parameter group.**

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name tier3-aurora-cluster-pg16 \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Aurora cluster parameter group for tier3 labs"
```

The `--db-parameter-group-family` flag uses `aurora-postgresql16` (not `postgres16`) for Aurora clusters.

Expected output (yours will differ):
```
{
    "DBClusterParameterGroup": {
        "DBClusterParameterGroupName": "tier3-aurora-cluster-pg16",
        "DBParameterGroupFamily": "aurora-postgresql16",
        "Description": "Aurora cluster parameter group for tier3 labs",
        "DBClusterParameterGroupArn": "arn:aws:rds:us-east-1:123456789012:cluster-pg:tier3-aurora-cluster-pg16"
    }
}
```

**Step 2 - List both parameter group types to confirm both exist.**

```bash
aws rds describe-db-parameter-groups \
  --query 'DBParameterGroups[?contains(DBParameterGroupName, `tier3`)].DBParameterGroupName'
```

```bash
aws rds describe-db-cluster-parameter-groups \
  --query 'DBClusterParameterGroups[?contains(DBClusterParameterGroupName, `tier3`)].DBClusterParameterGroupName'
```

---

## Part 3 - Static vs Dynamic Parameters

Not all parameters behave the same way. Some take effect immediately. Others need a reboot.

### Check Whether a Parameter is Static or Dynamic

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name tier3-custom-pg16 \
  --query 'Parameters[?ParameterName==`shared_buffers`].{Name:ParameterName,ApplyType:ApplyType,CurrentValue:ParameterValue,Source:Source}'
```

Expected output (yours will differ):
```
[
    {
        "Name": "shared_buffers",
        "ApplyType": "static",
        "CurrentValue": "{DBInstanceClassMemory/32768}",
        "Source": "engine-default"
    }
]
```

The `ApplyType` is `static` - this means you must reboot to apply changes.

Now check a dynamic parameter:

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name tier3-custom-pg16 \
  --query 'Parameters[?ParameterName==`work_mem`].{Name:ParameterName,ApplyType:ApplyType,CurrentValue:ParameterValue}'
```

Expected output (yours will differ):
```
[
    {
        "Name": "work_mem",
        "ApplyType": "dynamic",
        "CurrentValue": "4096"
    }
]
```

The `ApplyType` is `dynamic` - changes apply without a reboot.

### List All Static Parameters

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name tier3-custom-pg16 \
  --query 'Parameters[?ApplyType==`static`].ParameterName' \
  --output table
```

---

## Part 4 - Modify Parameters

### Console Steps - Modify work_mem (Dynamic)

1. In RDS console, click **Parameter groups**.
2. Click on **tier3-custom-pg16**.
3. Click **Edit parameters**.
4. In the search box, type `work_mem`.
5. Change the value from the default to `65536` (64 MB in kilobytes).
6. Click **Save changes**.

### CLI Steps - Modify a Dynamic Parameter

**Step 1 - Modify work_mem to 64 MB.**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=work_mem,ParameterValue=65536,ApplyMethod=immediate"
```

The `ApplyMethod=immediate` flag tells AWS to apply this change now for dynamic parameters. For static parameters, `immediate` is ignored - they still wait for reboot.

Expected output (yours will differ):
```
{
    "DBParameterGroupName": "tier3-custom-pg16"
}
```

**Step 2 - Modify log_min_duration_statement to log slow queries.**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

This tells PostgreSQL to log any query that takes longer than 1000 milliseconds (1 second).

**Step 3 - Modify a static parameter (shared_preload_libraries).**

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name tier3-custom-pg16 \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

The `ApplyMethod=pending-reboot` flag tells AWS to save this change and apply it when the instance reboots next. This is the safe choice for static parameters.

---

## Part 5 - Attach the Parameter Group to Your Instance

Your parameter group changes do nothing until you attach the group to an instance.

### Console Steps

1. In RDS console, click **Databases**.
2. Click on your instance name.
3. Click the **Modify** button.
4. Scroll down to **Additional configuration**.
5. Under **DB parameter group**, choose **tier3-custom-pg16**.
6. Scroll down and click **Continue**.
7. Choose **Apply immediately** or **Apply during next scheduled maintenance window**.
8. Click **Modify DB instance**.

### CLI Steps

**Step 1 - Get your instance identifier.**

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].DBInstanceIdentifier' \
  --output table
```

**Step 2 - Attach the parameter group.**

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --db-parameter-group-name tier3-custom-pg16 \
  --apply-immediately
```

Replace `[YOUR-INSTANCE-ID]` with your actual instance identifier from the previous step.

Expected output (yours will differ):
```
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-instance",
        "DBParameterGroups": [
            {
                "DBParameterGroupName": "tier3-custom-pg16",
                "ParameterApplyStatus": "pending-reboot"
            }
        ],
        ...
    }
}
```

Notice `ParameterApplyStatus: "pending-reboot"` - this shows the static parameters have not applied yet.

---

## Part 6 - Compare Parameter Values to Defaults

This is useful when troubleshooting - you want to see what has changed from defaults.

**Find all non-default parameters in your group:**

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name tier3-custom-pg16 \
  --source user \
  --query 'Parameters[*].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}' \
  --output table
```

The `--source user` flag filters to only show parameters you have explicitly changed. Without it, you see hundreds of engine defaults.

Expected output (yours will differ):
```
-------------------------------------------------------------------------
|                       DescribeDBParameters                            |
+---------------------------+----------+------------------+             |
|          Name             |  Value   |   ApplyType      |             |
+---------------------------+----------+------------------+             |
|  log_min_duration_stmt... |  1000    |  dynamic         |             |
|  shared_preload_libraries |  pg_st.. |  static          |             |
|  work_mem                 |  65536   |  dynamic         |             |
+---------------------------+----------+------------------+             |
```

---

## Part 7 - Reboot to Apply Static Parameters

After attaching a parameter group with static parameter changes, you must reboot the instance.

> **Warning:** A reboot causes a brief outage (30-60 seconds for most instances). Always reboot during a maintenance window for production instances.

### Console Steps

1. In RDS console, click **Databases**.
2. Select your instance (checkbox on the left).
3. Click **Actions** at the top.
4. Click **Reboot**.
5. A confirmation dialog appears. Click **Confirm**.

### CLI Steps

**Step 1 - Reboot the instance.**

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

Expected output (yours will differ):
```
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-instance",
        "DBInstanceStatus": "rebooting",
        ...
    }
}
```

**Step 2 - Wait for the instance to come back up.**

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

This command blocks until the instance is available again. It typically takes 1-3 minutes.

**Step 3 - Confirm the parameter applied.**

After the reboot, connect with psql and verify:

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres -c "SHOW shared_preload_libraries;"
```

Expected output (yours will differ):
```
   shared_preload_libraries
-----------------------------
 pg_stat_statements
(1 row)
```

**Step 4 - Check the parameter group status.**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DBParameterGroups'
```

Expected output (yours will differ):
```
[
    {
        "DBParameterGroupName": "tier3-custom-pg16",
        "ParameterApplyStatus": "in-sync"
    }
]
```

`in-sync` means all pending parameters have been applied. You are done.

---

## Summary

| Task | What You Did |
|---|---|
| Created DB parameter group | `aws rds create-db-parameter-group` |
| Created cluster parameter group | `aws rds create-db-cluster-parameter-group` |
| Identified static vs dynamic | `ApplyType` field in describe-db-parameters |
| Modified dynamic param | `ApplyMethod=immediate` - no reboot needed |
| Modified static param | `ApplyMethod=pending-reboot` - reboot required |
| Attached group to instance | `aws rds modify-db-instance` |
| Rebooted to apply | `aws rds reboot-db-instance` then `aws rds wait` |
| Confirmed applied | `ParameterApplyStatus: in-sync` |

---

## Common Mistakes

- **Forgetting to reboot** after changing static parameters. The console shows `pending-reboot` as a warning.
- **Using the default parameter group** in production. You cannot modify it, so you have no safe way to tune your instance.
- **Setting `shared_buffers` too high**. AWS calculates it as a formula based on instance memory. Setting a fixed value too large will prevent the instance from starting after reboot. See SURVIVE scenario 01 for how to recover.
- **Not checking `--source user`** when reviewing changes. Without it, you see every parameter and cannot tell what you changed.

---

## Next Steps

- [BUILD 02 - Option Groups](02-option-groups.md)
- [BUILD 03 - Core Extensions](03-extensions-core.md)
- [USE 01 - Parameter Tuning](../use/01-parameter-tuning.md)

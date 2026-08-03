# Build 03 - Configure Parameter Groups
## Module 02 - Provisioning Aurora (CLI + Console)

**Estimated time:** 30 minutes
**Difficulty:** Beginner
**Cost:** No additional cost (parameter groups are free - you only pay for the running cluster)
**Prerequisite:** Build 02 complete (running Aurora cluster with `devops-lab-cluster`)

---

## What You Will Do

You will create custom parameter groups, modify key parameters, attach them to your cluster, and verify the changes. By the end you will:

- Have a custom cluster parameter group and a custom DB parameter group
- Understand the difference between cluster-level and instance-level parameters
- Know how to modify dynamic and static parameters
- Verify parameter values using psql

---

## Before You Start

You need:
- Your Aurora cluster `devops-lab-cluster` running (from Build 01 or 02)
- Your writer endpoint saved as `$WRITER_ENDPOINT` (or copy it from `aws rds describe-db-clusters`)
- AWS CLI configured
- psql installed

---

## Part A - Create a Custom Cluster Parameter Group

The default parameter group (`default.aurora-postgresql16`) is read-only. You cannot modify any settings in it. To tune your cluster, you must create a custom parameter group.

### Step 1 - Create the Cluster Parameter Group

**In your terminal** (local machine):

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom cluster parameter group for DevOps lab"
```

What each flag does:

- `--db-cluster-parameter-group-name devops-lab-cluster-params` - a unique name for this parameter group.

- `--db-parameter-group-family aurora-postgresql16` - the engine family. For Aurora PostgreSQL 16.x, use `aurora-postgresql16`. This is different from standard RDS PostgreSQL which uses `postgres16`.

- `--description` - a human-readable description. Required by AWS.

Expected output (yours will differ):
```json
{
    "DBClusterParameterGroup": {
        "DBClusterParameterGroupName": "devops-lab-cluster-params",
        "DBParameterGroupFamily": "aurora-postgresql16",
        "Description": "Custom cluster parameter group for DevOps lab",
        "DBClusterParameterGroupArn": "arn:aws:rds:us-east-1:123456789012:cluster-pg:devops-lab-cluster-params"
    }
}
```

### Step 2 - Verify the Parameter Group Was Created

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-parameter-groups \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "DBClusterParameterGroups[0].{Name:DBClusterParameterGroupName,Family:DBParameterGroupFamily}" \
  --output table
```

Expected output (yours will differ):
```
------------------------------------------------------
|         DescribeDBClusterParameterGroups            |
+----------------------+-----------------------------+
|       Family         |           Name              |
+----------------------+-----------------------------+
|  aurora-postgresql16 |  devops-lab-cluster-params   |
+----------------------+-----------------------------+
```

---

## Part B - Create a Custom DB (Instance) Parameter Group

This is optional for most use cases, but it is good practice to create one so you have it ready for instance-level overrides.

### Step 1 - Create the DB Parameter Group

**In your terminal** (local machine):

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name devops-lab-instance-params \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom instance parameter group for DevOps lab"
```

Expected output (yours will differ):
```json
{
    "DBParameterGroup": {
        "DBParameterGroupName": "devops-lab-instance-params",
        "DBParameterGroupFamily": "aurora-postgresql16",
        "Description": "Custom instance parameter group for DevOps lab",
        "DBParameterGroupArn": "arn:aws:rds:us-east-1:123456789012:pg:devops-lab-instance-params"
    }
}
```

---

## Part C - Modify Parameters

### Step 1 - Check Current Default Values

Before changing anything, check what the current defaults are.

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --query "Parameters[?ParameterName=='log_statement'].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType,Source:Source}" \
  --output table
```

Expected output (yours will differ):
```
-----------------------------------------------------------------
|              DescribeDBClusterParameters                       |
+------------+-----------+---------------+-----------------------+
| ApplyType  |   Name    |    Source      |       Value           |
+------------+-----------+---------------+-----------------------+
|  dynamic   | log_statement | engine-default |  none              |
+------------+-----------+---------------+-----------------------+
```

`Source: engine-default` means this value has not been customized. `ApplyType: dynamic` means changes take effect without a reboot.

### Step 2 - Modify log_statement (Dynamic)

This parameter controls which SQL statements appear in the PostgreSQL log.

**In your terminal** (local machine):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters "ParameterName=log_statement,ParameterValue=all,ApplyMethod=immediate"
```

What this does:

- `ParameterName=log_statement` - the PostgreSQL parameter to change.
- `ParameterValue=all` - log every SQL statement. Options are: `none`, `ddl`, `mod`, `all`.
- `ApplyMethod=immediate` - apply this change right away (works because this is a dynamic parameter).

Expected output (yours will differ):
```json
{
    "DBClusterParameterGroupName": "devops-lab-cluster-params"
}
```

### Step 3 - Modify work_mem (Dynamic)

This parameter controls how much memory each sort or hash operation can use.

**In your terminal** (local machine):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters "ParameterName=work_mem,ParameterValue=65536,ApplyMethod=immediate"
```

This sets work_mem to 65536 KB (64 MB). The default is 4096 KB (4 MB).

### Step 4 - Modify log_min_duration_statement (Dynamic)

This logs any query that takes longer than the specified number of milliseconds.

**In your terminal** (local machine):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

This logs any query that takes more than 1000 milliseconds (1 second). The default is `-1` (disabled).

### Step 5 - Modify shared_preload_libraries (Static)

This parameter controls which extensions are loaded when PostgreSQL starts. It is a static parameter - it requires a reboot.

**In your terminal** (local machine):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

What is different:

- `ApplyMethod=pending-reboot` - this tells AWS to save the change but wait for a reboot to apply it. You must use `pending-reboot` for static parameters. Using `immediate` on a static parameter is ignored - it still waits for reboot.

### Step 6 - Verify All Changed Parameters

**In your terminal** (local machine):

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --source user \
  --query "Parameters[*].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}" \
  --output table
```

The `--source user` flag shows only parameters you have explicitly changed. Without it, you see hundreds of engine defaults.

Expected output (yours will differ):
```
---------------------------------------------------------------------
|                  DescribeDBClusterParameters                       |
+-------------------------------+-----------+-----------------------+
|            Name               | ApplyType |       Value           |
+-------------------------------+-----------+-----------------------+
|  log_min_duration_statement   |  dynamic  |  1000                 |
|  log_statement                |  dynamic  |  all                  |
|  shared_preload_libraries     |  static   |  pg_stat_statements   |
|  work_mem                     |  dynamic  |  65536                |
+-------------------------------+-----------+-----------------------+
```

Four parameters changed. Three dynamic (take effect immediately), one static (needs reboot).

---

## Part D - Attach the Parameter Groups to Your Cluster

Your parameter group changes do nothing until you attach the group to your cluster and instances.

### Step 1 - Attach the Cluster Parameter Group

**In your terminal** (local machine):

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --apply-immediately
```

What each flag does:

- `--db-cluster-identifier devops-lab-cluster` - the cluster to modify.
- `--db-cluster-parameter-group-name devops-lab-cluster-params` - the custom parameter group to attach.
- `--apply-immediately` - apply the change now instead of waiting for the next maintenance window.

Expected output (yours will differ):
```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "DBClusterParameterGroup": "devops-lab-cluster-params",
        ...
    }
}
```

### Step 2 - Attach the Instance Parameter Group to Both Instances

**In your terminal** (local machine):

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-writer-1 \
  --db-parameter-group-name devops-lab-instance-params \
  --apply-immediately
```

```bash
aws rds modify-db-instance \
  --db-instance-identifier devops-lab-reader-1 \
  --db-parameter-group-name devops-lab-instance-params \
  --apply-immediately
```

### Step 3 - Check Parameter Group Status

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,ParamStatus:DBClusterParameterGroupStatus}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------
|                DescribeDBClusters                     |
+---------------------+-------------------------------+
|      Instance       |         ParamStatus            |
+---------------------+-------------------------------+
|  devops-lab-writer-1|  pending-reboot                |
|  devops-lab-reader-1|  pending-reboot                |
+---------------------+-------------------------------+
```

`pending-reboot` means the static parameter (`shared_preload_libraries`) has not been applied yet. The dynamic parameters (`log_statement`, `work_mem`, `log_min_duration_statement`) are already active.

---

## Part E - Reboot to Apply Static Parameters

### Step 1 - Reboot the Writer Instance

**In your terminal** (local machine):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier devops-lab-writer-1
```

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "devops-lab-writer-1",
        "DBInstanceStatus": "rebooting",
        ...
    }
}
```

### Step 2 - Wait for the Writer to Come Back

**In your terminal** (local machine):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-writer-1
```

This typically takes 1 to 3 minutes.

### Step 3 - Reboot the Reader Instance

**In your terminal** (local machine):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier devops-lab-reader-1
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-reader-1
```

### Step 4 - Verify Parameter Group Status is in-sync

**In your terminal** (local machine):

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,ParamStatus:DBClusterParameterGroupStatus}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------
|                DescribeDBClusters                     |
+---------------------+-------------------------------+
|      Instance       |         ParamStatus            |
+---------------------+-------------------------------+
|  devops-lab-writer-1|  in-sync                       |
|  devops-lab-reader-1|  in-sync                       |
+---------------------+-------------------------------+
```

`in-sync` means all parameters (including static ones) are applied.

---

## Part F - Verify with psql

### Step 1 - Connect and Check Parameters

**In your terminal** (local machine):

```bash
psql -h $WRITER_ENDPOINT -U labadmin -d labdb -p 5432
```

**In psql** (connected to writer endpoint):

```sql
SHOW work_mem;
```

Expected output:
```
 work_mem
----------
 64MB
(1 row)
```

```sql
SHOW log_statement;
```

Expected output:
```
 log_statement
---------------
 all
(1 row)
```

```sql
SHOW log_min_duration_statement;
```

Expected output:
```
 log_min_duration_statement
----------------------------
 1s
(1 row)
```

```sql
SHOW shared_preload_libraries;
```

Expected output:
```
 shared_preload_libraries
--------------------------
 pg_stat_statements
(1 row)
```

### Step 2 - Check Multiple Parameters at Once

**In psql** (connected to writer endpoint):

```sql
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'work_mem',
    'log_statement',
    'log_min_duration_statement',
    'shared_preload_libraries',
    'max_connections',
    'shared_buffers'
)
ORDER BY name;
```

Expected output (yours will differ):
```
            name             | setting |  unit  |       source
-----------------------------+---------+--------+--------------------
 log_min_duration_statement  | 1000    | ms     | configuration file
 log_statement               | all     |        | configuration file
 max_connections              | 420     |        | configuration file
 shared_buffers               | 32768   | 8kB    | configuration file
 shared_preload_libraries     | pg_stat_statements |  | configuration file
 work_mem                     | 65536   | kB     | configuration file
(6 rows)
```

Notice `source: configuration file` for all parameters. This means they are coming from the parameter group (Aurora translates parameter groups into the configuration file internally).

Exit psql:

```sql
\q
```

---

## Summary

| What You Did | CLI Command |
|-------------|-------------|
| Created cluster parameter group | `aws rds create-db-cluster-parameter-group` |
| Created instance parameter group | `aws rds create-db-parameter-group` |
| Modified dynamic parameters | `ApplyMethod=immediate` (no reboot) |
| Modified static parameters | `ApplyMethod=pending-reboot` (reboot required) |
| Attached cluster group | `aws rds modify-db-cluster` |
| Attached instance group | `aws rds modify-db-instance` |
| Rebooted to apply static params | `aws rds reboot-db-instance` |
| Verified in psql | `SHOW` and `pg_settings` |

**Next:** [Build 04 - Connect and Verify](04-connect-and-verify.md).

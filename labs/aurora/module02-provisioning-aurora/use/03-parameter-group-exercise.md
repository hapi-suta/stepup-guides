# USE 03 - Parameter Group Exercise
## Module 02: Provisioning Aurora

**Estimated time:** 35 minutes
**Type:** Hands-on exercise with requirements
**Prerequisite:** BUILD guides for Module 02 complete, running Aurora cluster

---

## Overview

Aurora PostgreSQL has two levels of parameter groups: cluster-level and instance-level. Some parameters are static (require a reboot to take effect) and some are dynamic (apply immediately). Choosing the wrong type or forgetting to reboot causes confusion - you change a parameter, see no effect, and waste time troubleshooting.

In this exercise you will create custom parameter groups, modify settings, observe the difference between static and dynamic parameters, and verify changes inside PostgreSQL.

---

## Part 1 - Create Custom Parameter Groups

### Task 1A - Create a Cluster Parameter Group

Create a cluster parameter group for your Aurora cluster:

```bash
aws rds create-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom cluster params for parameter group exercise"
```

Verify it was created:

```bash
aws rds describe-db-cluster-parameter-groups \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --query "DBClusterParameterGroups[0].DBClusterParameterGroupName" \
  --output text
```

Expected output:
```
devops-lab-custom-cluster-pg
```

### Task 1B - Create an Instance Parameter Group

Create an instance-level parameter group:

```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name devops-lab-custom-instance-pg \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Custom instance params for parameter group exercise"
```

Verify it:

```bash
aws rds describe-db-parameter-groups \
  --db-parameter-group-name devops-lab-custom-instance-pg \
  --query "DBParameterGroups[0].DBParameterGroupName" \
  --output text
```

Expected output:
```
devops-lab-custom-instance-pg
```

---

## Part 2 - Understand Static vs Dynamic Parameters

Before changing anything, look at how parameters are classified.

### Task 2A - Check a Dynamic Parameter

Look at the `log_statement` parameter:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --query "Parameters[?ParameterName=='log_statement'].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType,IsModifiable:IsModifiable}" \
  --output table
```

Expected output:
```
----------------------------------------------------
|       DescribeDBClusterParameters                |
+----------+-----+---------------+----------------+
| ApplyType| ... | Name          | Value          |
+----------+-----+---------------+----------------+
| dynamic  | ... | log_statement | none           |
+----------+-----+---------------+----------------+
```

`ApplyType: dynamic` means this parameter takes effect immediately - no reboot required.

### Task 2B - Check a Static Parameter

Look at the `shared_buffers` parameter:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --query "Parameters[?ParameterName=='shared_buffers'].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType,IsModifiable:IsModifiable}" \
  --output table
```

Expected output shows `ApplyType: static`. This means changing `shared_buffers` requires a reboot of every instance in the cluster.

### Task 2C - Find All Static Parameters

List all static parameters that are modifiable:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --query "Parameters[?ApplyType=='static' && IsModifiable==\`true\`].ParameterName" \
  --output text
```

Count them. How many static parameters are there?

<details>
<summary>Why this matters</summary>

Every static parameter change requires a cluster reboot. In production, reboots cause brief downtime (10-30 seconds with Aurora failover). You need to batch static parameter changes together and apply them during a maintenance window - not one at a time.

</details>

---

## Part 3 - Modify Dynamic Parameters

### Task 3A - Change log_statement

Modify the cluster parameter group to log all DDL statements (CREATE, ALTER, DROP):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --parameters "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate"
```

### Task 3B - Change log_min_duration_statement

Enable slow query logging - log any query that takes longer than 1 second (1000 milliseconds):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --parameters "ParameterName=log_min_duration_statement,ParameterValue=1000,ApplyMethod=immediate"
```

### Task 3C - Apply the Parameter Group to the Cluster

Attach the custom cluster parameter group to your cluster:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --apply-immediately
```

Check the parameter group status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterParameterGroup" \
  --output text
```

Expected output:
```
devops-lab-custom-cluster-pg
```

---

## Part 4 - Verify Parameters Inside PostgreSQL

### Task 4A - Check Dynamic Parameter Values

Connect to the writer:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

Check the values you changed:

```sql
SHOW log_statement;
```

Expected output:
```
 log_statement
---------------
 ddl
```

```sql
SHOW log_min_duration_statement;
```

Expected output:
```
 log_min_duration_statement
----------------------------
 1s
```

These applied immediately because they are dynamic parameters.

### Task 4B - Test That DDL Logging Works

Create a test table:

```sql
CREATE TABLE param_test (id INT);
```

Now check the PostgreSQL log to see if the DDL was logged. You can check logs through the RDS console or CLI:

```sql
\q
```

```bash
aws rds describe-db-log-files \
  --db-instance-identifier devops-lab-cluster-writer \
  --query "DescribeDBLogFiles[-1].LogFileName" \
  --output text
```

This returns the most recent log file name. Download it:

```bash
LOG_FILE=$(aws rds describe-db-log-files \
  --db-instance-identifier devops-lab-cluster-writer \
  --query "DescribeDBLogFiles[-1].LogFileName" \
  --output text)

aws rds download-db-log-file-portion \
  --db-instance-identifier devops-lab-cluster-writer \
  --log-file-name "$LOG_FILE" \
  --output text | tail -20
```

You should see a line containing `CREATE TABLE param_test` in the log output.

---

## Part 5 - Static Parameter Change and Reboot

### Task 5A - Change a Static Parameter

Modify `shared_preload_libraries` to include `pg_stat_statements` (a query performance monitoring extension):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

Note: we used `ApplyMethod=pending-reboot` because this is a static parameter. Using `immediate` on a static parameter queues the change but it still will not take effect until reboot.

### Task 5B - Check the Pending Reboot Status

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,PendingReboot:IsClusterWriter}" \
  --output table
```

Connect to the writer and verify the extension is NOT loaded yet:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

```sql
SHOW shared_preload_libraries;
```

This will NOT show `pg_stat_statements` yet - the change is pending.

```sql
\q
```

### Task 5C - Reboot the Writer Instance

```bash
aws rds reboot-db-instance \
  --db-instance-identifier devops-lab-cluster-writer
```

Wait for it to become available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-writer
```

### Task 5D - Verify the Static Parameter Took Effect

Connect again and check:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

```sql
SHOW shared_preload_libraries;
```

Expected output:
```
 shared_preload_libraries
--------------------------
 pg_stat_statements
```

Now create the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

SELECT calls, query FROM pg_stat_statements LIMIT 5;
```

This confirms the static parameter change took effect after the reboot.

```sql
\q
```

---

## Part 6 - Compare Cluster vs Instance Parameter Groups

### Questions to Answer

1. You set `log_statement = ddl` in the cluster parameter group. Does this apply to readers too, or only the writer?

<details>
<summary>Answer</summary>

Cluster parameter group settings apply to ALL instances in the cluster - both the writer and all readers. This is different from instance parameter groups, which only affect the specific instance they are attached to.

</details>

2. When would you use an instance parameter group instead of a cluster parameter group?

<details>
<summary>Answer</summary>

Use instance parameter groups when you need different settings on specific instances. For example, you might want more aggressive logging on a reader used for debugging, or a different `work_mem` on a reader dedicated to analytics queries. Instance-level settings override cluster-level settings for the same parameter.

</details>

3. You change a dynamic parameter in the cluster parameter group. Do you need to reboot all instances?

<details>
<summary>Answer</summary>

No. Dynamic parameters take effect immediately on all instances without a reboot. Only static parameters require a reboot.

</details>

4. What happens if the same parameter is set in both the cluster parameter group AND the instance parameter group?

<details>
<summary>Answer</summary>

The instance parameter group value takes precedence for that specific instance. Other instances in the cluster use the cluster parameter group value.

</details>

---

## Cleanup

Remove the custom parameter groups from the cluster and instances, then delete them:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --db-cluster-parameter-group-name default.aurora-postgresql16 \
  --apply-immediately

aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-custom-cluster-pg

aws rds delete-db-parameter-group \
  --db-parameter-group-name devops-lab-custom-instance-pg
```

Drop the test table:

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432 \
  -c "DROP TABLE IF EXISTS param_test;"
```

---

## Key Takeaways

- Aurora has two levels: cluster parameter groups (shared) and instance parameter groups (per-instance)
- Dynamic parameters apply immediately - no reboot needed
- Static parameters require a reboot of each affected instance
- Batch static parameter changes together to minimize reboots
- Instance parameter group settings override cluster parameter group settings
- Always verify parameter changes inside PostgreSQL with `SHOW parameter_name`
- `pg_stat_statements` requires a static parameter change + reboot + `CREATE EXTENSION`

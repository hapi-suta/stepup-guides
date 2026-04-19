# USE 02 - Parameter Groups

## Objective

Create a custom parameter group, modify key PostgreSQL settings, understand the difference between static and dynamic parameters, and verify changes take effect correctly.

---

## Exercise

You have an RDS instance that needs tuning. Modify these parameters:

| Parameter | Value | Type |
|-----------|-------|------|
| shared_buffers | 256 MB | Static (requires reboot) |
| work_mem | 16 MB | Dynamic (immediate) |
| log_statement | ddl | Dynamic (immediate) |
| shared_preload_libraries | pg_stat_statements | Static (requires reboot) |
| log_min_duration_statement | 500 | Dynamic (immediate) |

---

## Step-by-Step

### 1. Record current values

Connect to your instance:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Check current values:

```sql
SHOW shared_buffers;
```

```sql
SHOW work_mem;
```

```sql
SHOW log_statement;
```

```sql
SHOW shared_preload_libraries;
```

```sql
SHOW log_min_duration_statement;
```

Write down each value. You will compare after modifications.

Exit psql:

```sql
\q
```

### 2. Create a new parameter group

```bash
aws rds create-db-parameter-group \
    --db-parameter-group-name suta-pg15-tuned \
    --db-parameter-group-family postgres15 \
    --description "Tuned parameters for SUTA lab"
```

### 3. Set dynamic parameters

Dynamic parameters take effect immediately without a reboot:

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name suta-pg15-tuned \
    --parameters \
        "ParameterName=work_mem,ParameterValue=16384,ApplyMethod=immediate" \
        "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
        "ParameterName=log_min_duration_statement,ParameterValue=500,ApplyMethod=immediate"
```

The `work_mem` value is in KB, so 16384 KB = 16 MB. `log_min_duration_statement` is in milliseconds, so 500 = 0.5 seconds.

### 4. Set static parameters

Static parameters require a reboot to take effect:

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name suta-pg15-tuned \
    --parameters \
        "ParameterName=shared_buffers,ParameterValue=262144,ApplyMethod=pending-reboot" \
        "ParameterName=shared_preload_libraries,ParameterValue=pg_stat_statements,ApplyMethod=pending-reboot"
```

The `shared_buffers` value is in 8 KB pages. 262144 pages x 8 KB = ~2 GB. Note: RDS may cap this based on instance class.

**Important**: If you use `ApplyMethod=immediate` for a static parameter, the command fails.

### 5. Verify parameter values in the group

```bash
aws rds describe-db-parameters \
    --db-parameter-group-name suta-pg15-tuned \
    --query "Parameters[?ParameterName=='work_mem' || ParameterName=='shared_buffers' || ParameterName=='log_statement' || ParameterName=='shared_preload_libraries' || ParameterName=='log_min_duration_statement'].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType,IsModifiable:IsModifiable}" \
    --output table
```

The `ApplyType` column shows `static` or `dynamic`. This tells you whether a reboot is needed.

Expected output (yours will differ):

```
--------------------------------------------------------------------
|                      DescribeDBParameters                        |
+----------------------------------+--------+------+--------------+
|              Name                | Value  | ApplyType | IsModifiable |
+----------------------------------+--------+-----------+--------------+
| log_min_duration_statement       | 500    | dynamic   | true         |
| log_statement                    | ddl    | dynamic   | true         |
| shared_buffers                   | 262144 | static    | true         |
| shared_preload_libraries         | pg_stat_statements | static | true |
| work_mem                         | 16384  | dynamic   | true         |
+----------------------------------+--------+-----------+--------------+
```

### 6. Apply the parameter group to your instance

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --db-parameter-group-name suta-pg15-tuned \
    --apply-immediately
```

This changes the parameter group. Dynamic parameters apply within minutes. Static parameters remain pending until reboot.

### 7. Check pending changes

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].DBParameterGroups[0].{Group:DBParameterGroupName,Status:ParameterApplyStatus}" \
    --output table
```

Expected output:

```
-----------------------------------------------
|            DescribeDBInstances               |
+---------------------+------------------------+
|       Group         |        Status          |
+---------------------+------------------------+
| suta-pg15-tuned     | pending-reboot         |
+---------------------+------------------------+
```

The `pending-reboot` status means static parameters are waiting for a reboot.

### 8. Verify dynamic parameters (before reboot)

Connect and check the dynamic parameters - they should already be updated:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 16MB
(1 row)
```

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 ddl
(1 row)
```

Check shared_buffers (static - should still be the OLD value):

```sql
SHOW shared_buffers;
```

This will show the previous value because the reboot has not happened yet.

Exit psql:

```sql
\q
```

### 9. Reboot to apply static parameters

```bash
aws rds reboot-db-instance \
    --db-instance-identifier suta-pg-lab
```

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

### 10. Verify all parameters after reboot

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SHOW shared_buffers;
```

Now this should reflect the new value (or the maximum allowed for your instance class).

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

```sql
SHOW work_mem;
```

```sql
SHOW log_statement;
```

```sql
SHOW log_min_duration_statement;
```

Compare each value to what you recorded in step 1. All five should be updated.

Exit psql:

```sql
\q
```

---

## Comparison Table

Fill in your values:

| Parameter | Before | After | Type |
|-----------|--------|-------|------|
| shared_buffers | _____ | _____ | Static |
| work_mem | _____ | _____ | Dynamic |
| log_statement | _____ | _____ | Dynamic |
| shared_preload_libraries | _____ | _____ | Static |
| log_min_duration_statement | _____ | _____ | Dynamic |

---

## Key Takeaway

Dynamic parameters take effect immediately when you apply a parameter group. Static parameters require a reboot. Always check `ParameterApplyStatus` to know if a reboot is needed. In production, schedule reboots during maintenance windows.

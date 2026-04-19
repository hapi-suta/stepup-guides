# SURVIVE 02 - Parameter Group Crash

## Symptom

The RDS instance is stuck rebooting or failing to start after a parameter group change. The instance status may show `rebooting`, `incompatible-parameters`, or repeated restart cycles.

---

## Diagnosis

### Step 1 - Check instance status

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,ParamGroup:DBParameterGroups[0].DBParameterGroupName,ParamStatus:DBParameterGroups[0].ParameterApplyStatus}" \
    --output table
```

Look for status `incompatible-parameters` or `rebooting` that does not resolve.

### Step 2 - Check recent events

```bash
aws rds describe-events \
    --source-identifier suta-pg-lab \
    --source-type db-instance \
    --duration 60 \
    --query "Events[*].{Time:Date,Message:Message}" \
    --output table
```

Look for messages about parameter errors or reboot failures.

### Step 3 - Identify the problem parameters

```bash
PARAM_GROUP=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" --output text)
```

Check the current parameter values:

```bash
aws rds describe-db-parameters \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --query "Parameters[?ParameterName=='shared_buffers' || ParameterName=='max_connections'].{Name:ParameterName,Value:ParameterValue,Source:Source}" \
    --output table
```

If `shared_buffers` is set absurdly high or `max_connections` is set to 10000, those are the culprits.

---

## Fix

### Step 4 - Revert the parameters to safe values

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name "${PARAM_GROUP}" \
    --parameters \
        "ParameterName=shared_buffers,ParameterValue=32768,ApplyMethod=pending-reboot" \
        "ParameterName=max_connections,ParameterValue=100,ApplyMethod=pending-reboot"
```

The value 32768 for shared_buffers is in 8 KB pages = 256 MB, which is safe for a db.t3.medium. max_connections=100 is the default.

### Step 5 - Reboot the instance

```bash
aws rds reboot-db-instance \
    --db-instance-identifier suta-pg-lab
```

This forces a fresh reboot with the corrected parameters.

### Step 6 - Wait for the instance

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

If the wait times out, check the status again:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].DBInstanceStatus" \
    --output text
```

### Step 7 - Verify the parameters took effect

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SHOW shared_buffers;
```

Expected output:

```
 shared_buffers
----------------
 256MB
(1 row)
```

```sql
SHOW max_connections;
```

Expected output:

```
 max_connections
-----------------
 100
(1 row)
```

Exit psql:

```sql
\q
```

---

## Prevention

### Step 8 - Test parameters on a non-production instance first

Always apply parameter changes to a test instance before production. Use this pattern:

1. Create a parameter group copy
2. Apply changes to the copy
3. Assign the copy to a test instance
4. Verify the test instance starts correctly
5. Only then apply to production

### Step 9 - Know the safe ranges

| Parameter | db.t3.micro (1GB) | db.t3.medium (4GB) | db.r6g.large (16GB) |
|-----------|-------|-------|-------|
| shared_buffers | 128 MB | 256-512 MB | 4 GB |
| max_connections | 50 | 100 | 200 |
| work_mem | 4 MB | 8-16 MB | 16-32 MB |
| effective_cache_size | 512 MB | 2-3 GB | 12 GB |

---

## Verification

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,ParamStatus:DBParameterGroups[0].ParameterApplyStatus}" \
    --output table
```

Both should show `available` and `in-sync`.

---

## Discussion Questions

1. What is the difference between `incompatible-parameters` and `rebooting` states?
2. Can you modify a parameter group while the instance is in `incompatible-parameters` state?
3. What shared_buffers value is safe for your instance class?
4. How would you prevent this in a CI/CD pipeline?

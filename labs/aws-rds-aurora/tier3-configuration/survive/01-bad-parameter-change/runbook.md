# SURVIVE 01 - Bad Parameter Change

**Difficulty:** Intermediate
**Estimated time:** 20 minutes

---

## The Situation

You arrive Monday morning. Your RDS PostgreSQL instance is not accepting connections. The application is down. You check the AWS console and see:

```
Instance status: incompatible-parameters
```

Developers are paging you. Fix it.

---

## What You Know

- The instance was running fine on Friday
- A junior DBA was practicing parameter changes over the weekend
- The parameter group has been modified recently
- You cannot connect to the database

---

## Your Goal

Restore the instance to `available` status with all connections working.

---

## Constraints

- You cannot restore from a snapshot (the team needs current data)
- You cannot change the instance class
- The fix must not cause data loss

---

## Step 1 - Diagnose the Problem

**Check the instance status:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Version:EngineVersion}' \
  --output json
```

Expected output:
```json
{
    "Status": "incompatible-parameters",
    "Version": "16.x"
}
```

> **Concept:** `incompatible-parameters` means PostgreSQL tried to start but could not because of an invalid parameter value. The engine refused to boot. The instance is alive at the OS level but the PostgreSQL process is not running.

**Check the parameter group for recent changes:**

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --source user \
  --query 'Parameters[*].{Name:ParameterName,Value:ParameterValue,ApplyType:ApplyType}' \
  --output table
```

You will see the parameters that were changed from defaults. Look for anything suspicious - especially `shared_buffers` or `max_connections`.

**Note the suspicious value.** Write it down before you change anything.

---

## Step 2 - Identify the Offending Parameter

In this scenario, `shared_buffers` was set to `7340032` kB (approximately 7 TB). On a db.t3.micro with 1 GB RAM, PostgreSQL cannot allocate this much shared memory. PostgreSQL refused to start.

**Verify this is the problem:**

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --query 'Parameters[?ParameterName==`shared_buffers`].{Name:ParameterName,Value:ParameterValue,Source:Source}' \
  --output table
```

Expected output:
```
---------------------------------------------------------
|              DescribeDBParameters                     |
+------------------+----------+-----------------------+ |
|       Name       |  Value   |        Source         | |
+------------------+----------+-----------------------+ |
|  shared_buffers  | 7340032  |  user                 | |
+------------------+----------+-----------------------+ |
```

`Source: user` confirms this was manually set (not an engine default).

---

## Step 3 - Fix the Parameter

You have two options. Choose the one appropriate to your situation.

### Option A - Reset to Engine Default

This removes the custom value and lets the engine calculate `shared_buffers` based on instance class.

```bash
aws rds reset-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters "ParameterName=shared_buffers,ApplyMethod=pending-reboot"
```

**Verify the reset:**

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --query 'Parameters[?ParameterName==`shared_buffers`].{Name:ParameterName,Value:ParameterValue,Source:Source}' \
  --output table
```

After reset, `Source` should show `engine-default` and `Value` should show the formula `{DBInstanceClassMemory/32768}`.

### Option B - Set a Valid Value

If you need a specific value (not the default), set it to something reasonable. For a 1 GB instance:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [YOUR-PARAMETER-GROUP] \
  --parameters "ParameterName=shared_buffers,ParameterValue=131072,ApplyMethod=pending-reboot"
```

`131072` kB = 128 MB, which is 25% of 512 MB (half of a 1 GB instance after OS overhead).

---

## Step 4 - Reboot the Instance

After fixing the parameter, reboot to apply the change.

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

**Wait for the instance to come back up:**

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID]
```

This may take 2-5 minutes.

---

## Step 5 - Verify Recovery

**Check the instance status:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text
```

Expected output:
```
available
```

**Verify you can connect:**

```bash
psql -h [YOUR-ENDPOINT] -U [YOUR-USERNAME] -d postgres -c "SELECT now(), version();"
```

Expected output (yours will differ):
```
              now              |                    version
-------------------------------+-----------------------------------------------
 2024-01-15 14:32:00.123456+00 | PostgreSQL 16.4 on x86_64-pc-linux-gnu, ...
(1 row)
```

**Check the parameter group is in-sync:**

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DBParameterGroups'
```

Expected output:
```json
[
    {
        "DBParameterGroupName": "tier3-custom-pg16",
        "ParameterApplyStatus": "in-sync"
    }
]
```

---

## Root Cause and Prevention

**Root cause:** `shared_buffers` was set to a value larger than the instance's available memory. PostgreSQL requires shared memory allocation at startup. When it cannot allocate the requested amount, it exits immediately, causing the `incompatible-parameters` state.

**Prevention measures:**

1. **Never set shared_buffers to a fixed large value.** Use the engine default formula `{DBInstanceClassMemory/32768}` or set a value that is at most 25% of the instance's RAM.

2. **Test parameter changes on a non-production instance first.**

3. **Always use `ApplyMethod=pending-reboot`** for static parameters, then verify the value makes sense before rebooting.

4. **Use the RDS Events log** to see why an instance failed to start. Check **RDS > Events** in the console after an incident.

5. **Set up CloudWatch alarms** on the `DatabaseConnections` metric. If connections drop to 0, you get paged immediately.

---

## Run validate.sh to confirm your fix is complete.

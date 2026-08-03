# SURVIVE 04 - Blue/Green Replication Lag Too High
## Runbook: Diagnose and Resolve Lag Before Switchover

**Scenario:** A Blue/Green deployment exists and is ready for switchover. Replication lag is too high. AWS is blocking the switchover. Identify and fix the root cause, then complete the switchover.

**What the student sees:**
```
Attempting switchover...
Error: Replication lag on Green is 47 seconds - too high for safe switchover.
Resolve lag below acceptable threshold and retry.
```

---

## Your Objective

Diagnose the replication lag, fix it, confirm lag is below 5 seconds, and execute the switchover within **30 minutes**.

---

## Step 1 - Confirm the Lag

Get the Green instance endpoint and check lag:

```bash
export BG_ID=$(aws rds describe-blue-green-deployments \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[?Status==`AVAILABLE`].BlueGreenDeploymentIdentifier' \
  --output text | head -1)

echo "Deployment: $BG_ID"
```

Get the Green instance:

```bash
export GREEN_INSTANCE=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].SwitchoverDetails[0].TargetMember' \
  --output text | sed 's|.*db/||')

export GREEN_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $GREEN_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "Green: $GREEN_HOST"
```

Check lag:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag, pg_last_xact_replay_timestamp() AS last_replay;"
```

If lag is > 5 seconds, proceed to Step 2.

---

## Step 2 - Diagnose the Root Cause on Blue

Long replication lag usually has one of these causes:
1. High write volume that Green cannot keep up with
2. A long-running transaction on Blue blocking replication slot advancement
3. Network congestion between Blue and Green
4. Green instance CPU/IO saturation

Check Blue for problematic sessions:

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
-- Check for long-running or idle-in-transaction sessions
SELECT
    pid,
    usename,
    application_name,
    state,
    state_change,
    now() - state_change AS duration,
    left(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
  AND pid <> pg_backend_pid()
ORDER BY state_change ASC;
EOF
```

Expected output showing the blocking session:

```
  pid  | usename  | application_name |       state        |         state_change         | duration | query_snippet
-------+----------+------------------+--------------------+------------------------------+----------+---------------
 12345 | postgres | psql             | idle in transaction| 2025-05-30 15:30:11.000000+00| 00:05:23 | SELECT pg_sleep(300);
```

The `idle in transaction` session is holding the transaction open. Logical replication cannot advance past the LSN of this transaction's start.

Check the replication slot status on Blue:

```bash
psql -h $DB_HOST -U postgres -d postgres << 'EOF'
SELECT
    slot_name,
    plugin,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS replication_lag_bytes
FROM pg_replication_slots
WHERE slot_type = 'logical';
EOF
```

Expected output:

```
 slot_name | plugin | active | restart_lsn | confirmed_flush_lsn | replication_lag_bytes
-----------+--------+--------+-------------+---------------------+----------------------
 rds_logical_replication_...| pgoutput | t | 0/3A000000 | 0/3A000000 | 480 MB
```

A large `replication_lag_bytes` value confirms the slot is backed up.

---

## Step 3 - Terminate the Blocking Session

Once you have identified the problematic PID, terminate it.

> **Important:** In production, contact the application team before terminating sessions. Killing an `idle in transaction` session will roll back any uncommitted work from that session.

```bash
# Replace 12345 with the actual PID from Step 2
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT pg_terminate_backend(12345);"
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
```

`t` means the backend was terminated.

---

## Step 4 - Monitor Lag Drop

After terminating the blocking session, lag should start dropping rapidly:

```bash
watch -n 5 "psql -h $GREEN_HOST -U postgres -d postgres \
  -tAc \"SELECT now() - pg_last_xact_replay_timestamp() AS lag;\""
```

Watch the lag decrease. When it drops below 5 seconds, press Ctrl+C and proceed.

---

## Step 5 - Confirm Lag Is Acceptable

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

Expected output (lag must be below 5 seconds):

```
 replication_lag
-----------------
 00:00:00.823417
```

---

## Step 6 - Execute the Switchover

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION
```

Monitor:

```bash
watch -n 5 "aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].Status' \
  --output text"
```

Wait for `SWITCHOVER_COMPLETED`.

---

## Step 7 - Verify Post-Switchover State

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].{Status:Status,CreateTime:CreateTime}' \
  --output table
```

Connect to the Blue endpoint (now Green running as primary):

```bash
psql -h $DB_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

---

## Cleanup (After 24 hours of confirmation)

```bash
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier $BG_ID \
  --delete-target \
  --region $AWS_REGION
```

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. Logical replication can be blocked by `idle in transaction` sessions on the source
2. Always check `pg_stat_activity` for long-running or stuck sessions before assuming network issues
3. Check `pg_replication_slots` to see actual lag in bytes, not just seconds
4. Terminating an idle-in-transaction session rolls back uncommitted work - check with the app team first
5. Monitor lag continuously during high-write periods before scheduling a switchover
6. Set `idle_in_transaction_session_timeout` in your parameter group to auto-kill stuck transactions (e.g., 5 minutes)

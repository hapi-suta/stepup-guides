# Runbook 07: Slow Query Blocks Partition Maintenance

## Alert
> HIGH: Partition maintenance job for quant.market_data is blocked.
> Cannot DROP old partition or CREATE new partition.
> Error: `ERROR: canceling statement due to lock timeout` or `ERROR: deadlock detected`
> The monthly partition rotation for quant.market_data has not completed. A new month's data cannot be loaded.

---

## Lab Environment

| Node | Public IP | Private IP | Role |
|------|-----------|------------|------|
| pg-primary | 3.90.199.62 | 172.31.19.86 | Primary |
| pg-replica | 3.91.32.84 | 172.31.22.69 | Replica |
| pg-ops | 54.209.143.137 | 172.31.26.19 | Ops/Monitoring |

SSH command: `ssh -i ~/.ssh/id_ed25519 ec2-user@<IP>`

Database: `quantdb`
- `quant.market_data` - partitioned by month, 2024-01 through 2024-12
- `quant.signals` - partitioned by month

---

## Layer 1 - Junior DBA: Assess and Contain

Your job is to confirm there is a lock conflict, identify which query is blocking, and document everything before anyone takes action.

### Step 1 - SSH into the primary

From your local machine:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

### Step 2 - Switch to postgres and connect to quantdb

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

### Step 3 - Check for queries waiting on locks

On **pg-primary**, inside psql:

```sql
SELECT pid, usename, application_name, client_addr,
       wait_event_type, wait_event, state,
       now() - query_start AS duration,
       left(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
ORDER BY duration DESC;
```

Expected output (yours will differ):

```
  pid  | usename  | application_name | client_addr  | wait_event_type | wait_event | state  | duration |                query_snippet
-------+----------+------------------+--------------+-----------------+------------+--------+----------+----------------------------------------------
 12345 | postgres | partition_mgr    | 127.0.0.1    | Lock            | relation   | active | 00:08:23 | DROP TABLE quant.market_data_2024_01
(1 row)
```

This shows the partition maintenance job has been waiting 8 minutes for a lock on the table.

### Step 4 - Check what is holding the lock

On **pg-primary**, inside psql:

```sql
SELECT pid, usename, application_name, client_addr,
       state, wait_event_type, wait_event,
       now() - query_start AS duration,
       left(query, 120) AS query_snippet
FROM pg_stat_activity
WHERE pid != pg_backend_pid()
  AND pid IN (
    SELECT pid FROM pg_locks
    WHERE relation = 'quant.market_data_2024_01'::regclass
      AND granted = true
  );
```

Expected output (yours will differ):

```
  pid  | usename | application_name | client_addr   | state  | wait_event_type | wait_event | duration |                     query_snippet
-------+---------+------------------+---------------+--------+-----------------+------------+----------+------------------------------------------------
 11200 | quant   | quant_analytics  | 172.31.19.200 | active | Client          | ClientRead | 01:42:15 | SELECT date, symbol, close FROM quant.market_data WHERE date >= '2024-01-01'
(1 row)
```

You have found the blocker. A long-running SELECT on `quant.market_data` has been running for 1 hour 42 minutes. It holds a lock that prevents the DDL (DROP TABLE) from acquiring an AccessExclusiveLock.

### Step 5 - Check ALL locks on the market_data partition table for a complete picture

On **pg-primary**, inside psql:

```sql
SELECT l.pid, l.locktype, l.relation::regclass, l.mode, l.granted,
       a.usename, a.state, now() - a.query_start AS duration,
       left(a.query, 80) AS query_snippet
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.relation = 'quant.market_data_2024_01'::regclass
ORDER BY l.granted DESC, duration DESC;
```

Expected output (yours will differ):

```
  pid  | locktype | relation                   |       mode        | granted | usename  | state  | duration | query_snippet
-------+----------+----------------------------+-------------------+---------+----------+--------+----------+----------------------------------------------
 11200 | relation | quant.market_data_2024_01  | AccessShareLock   | t       | quant    | active | 01:42:15 | SELECT date, symbol, close FROM quant.market...
 12345 | relation | quant.market_data_2024_01  | AccessExclusiveLock | f     | postgres | active | 00:08:23 | DROP TABLE quant.market_data_2024_01
(2 rows)
```

`granted = t` means the lock is held. `granted = f` means it is waiting. The SELECT holds `AccessShareLock` and the DROP is waiting for `AccessExclusiveLock`. These conflict.

Note both PIDs. Do not take action yet - this is Layer 1's job to document and hand off.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

You have the blocker's PID (11200) and the blocked DDL's PID (12345). Now assess the impact and decide how to proceed.

### Step 1 - Assess the blocking query in detail

On **pg-primary**, inside psql:

```sql
SELECT pid, usename, application_name, client_addr, backend_start,
       query_start, state_change,
       now() - query_start AS total_duration,
       now() - state_change AS time_in_current_state,
       query
FROM pg_stat_activity
WHERE pid = 11200;
```

Expected output (yours will differ):

```
-[ RECORD 1 ]----------+------------------------------------------------------
pid                    | 11200
usename                | quant
application_name       | quant_analytics
client_addr            | 172.31.19.200
backend_start          | 2024-01-15 13:00:00+00
query_start            | 2024-01-15 13:10:00+00
state_change           | 2024-01-15 13:10:00+00
total_duration         | 01:52:34
time_in_current_state  | 01:52:34
query                  | SELECT date, symbol, open, high, low, close, volume  |
                       | FROM quant.market_data                               |
                       | WHERE date >= '2024-01-01'                           |
                       | ORDER BY symbol, date
```

Key questions to answer before canceling:
- Is this a batch analytics job or an end-user query?
- Is 1:52 runtime expected for this query?
- If we cancel it, will it restart automatically and block again?

### Step 2 - Try the graceful option first: pg_cancel_backend

`pg_cancel_backend` sends a signal that cancels only the current query. The connection stays open. The client will receive an error but can retry.

On **pg-primary**, inside psql:

```sql
SELECT pg_cancel_backend(11200);
```

Expected output:

```
 pg_cancel_backend
-------------------
 t
(1 row)
```

Wait 5 seconds, then check if the partition maintenance job unblocked:

```sql
SELECT pid, state, wait_event_type, wait_event, now() - query_start AS duration,
       left(query, 80) AS query_snippet
FROM pg_stat_activity
WHERE pid = 12345;
```

Expected output if unblocked:

```
  pid  | state  | wait_event_type | wait_event | duration |         query_snippet
-------+--------+-----------------+------------+----------+--------------------------------
 12345 | active |                 |            | 00:00:02 | DROP TABLE quant.market_data_2024_01
(1 row)
```

`wait_event_type` is now NULL, meaning it is no longer waiting on a lock. The DDL is proceeding.

### Step 3 - If pg_cancel_backend did not work, use pg_terminate_backend

Some queries ignore cancel signals (idle-in-transaction, certain client libraries). If the blocker is still present after 15 seconds, terminate it:

On **pg-primary**, inside psql:

```sql
SELECT pg_terminate_backend(11200);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

This kills the entire connection. The client will get a connection error and need to reconnect.

### Step 4 - Verify partition maintenance completes

On **pg-primary**, inside psql:

```sql
SELECT pid, state, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE pid = 12345;
```

If the maintenance job is still running (duration increasing, state = active), it is working. Wait for it to complete. Check the partitions exist correctly:

```sql
SELECT inhrelid::regclass AS partition_name,
       pg_get_expr(c.relpartbound, c.oid) AS partition_range
FROM pg_inherits i
JOIN pg_class c ON c.oid = i.inhrelid
WHERE inhparent = 'quant.market_data'::regclass
ORDER BY partition_name;
```

Expected output (yours will differ):

```
       partition_name         |              partition_range
------------------------------+--------------------------------------------
 quant.market_data_2024_02    | FOR VALUES FROM ('2024-02-01') TO ('2024-03-01')
 quant.market_data_2024_03    | FOR VALUES FROM ('2024-03-01') TO ('2024-04-01')
 ...
 quant.market_data_2024_12    | FOR VALUES FROM ('2024-12-01') TO ('2025-01-01')
(11 rows)
```

The old partition (`2024_01`) should be gone if it was dropped, and the new one should be present.

### Step 5 - Check if the blocking query is already re-running

After canceling, check if the same application reconnected and started the same query again:

```sql
SELECT pid, usename, application_name, now() - query_start AS duration,
       left(query, 100) AS query_snippet
FROM pg_stat_activity
WHERE application_name = 'quant_analytics'
  AND state = 'active';
```

If it restarted with the same long query, note that. This is an application-level problem - the query needs tuning or the job schedule needs to be adjusted. Flag it for the senior DBA.

### Step 6 - Exit psql and postgres

```bash
exit
```

```bash
exit
```

---

## Layer 3 - Senior DBA: Root Cause and Prevent

The immediate issue was resolved by canceling a long-running query. The deeper problem is that partition maintenance has no protection against lock contention and that the analytics query is running without a statement timeout.

### Step 1 - Add lock_timeout to partition maintenance operations

A `lock_timeout` prevents DDL from waiting indefinitely. Instead of blocking all other queries while waiting, it fails fast and can be retried at a better time.

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

Check what the partition maintenance script currently does:

```bash
exit
```

```bash
exit
```

On **pg-ops**, as **ec2-user**:

```bash
cat /opt/scripts/partition_manager.sh
```

Look for the DROP and CREATE statements. They should include `SET lock_timeout` before each DDL statement. If they do not, add it:

```bash
vi /opt/scripts/partition_manager.sh
```

The DDL section should look like this:

```sql
SET lock_timeout = '5s';
DROP TABLE IF EXISTS quant.market_data_2024_01;
SET lock_timeout = '30s';
CREATE TABLE quant.market_data_2024_next PARTITION OF quant.market_data
  FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

With `lock_timeout = '5s'`, the DROP will give up after 5 seconds and exit with an error instead of blocking indefinitely. The maintenance script can then log the failure and retry during the next low-traffic window.

### Step 2 - Add statement_timeout for the analytics role

Long-running analytics queries should have a statement timeout so they cannot hold locks for hours.

On **pg-primary**, as **ec2-user**:

```bash
sudo su - postgres
```

On **pg-primary**, as **postgres**:

```bash
/usr/pgsql-17/bin/psql -d quantdb
```

On **pg-primary**, inside psql:

```sql
ALTER ROLE quant SET statement_timeout = '30min';
```

Expected output:

```
ALTER ROLE
```

This applies to all new connections by the `quant` role. Existing connections are not affected until they reconnect.

Verify it was set:

```sql
SELECT rolname, rolconfig FROM pg_roles WHERE rolname = 'quant';
```

Expected output (yours will differ):

```
 rolname |          rolconfig
---------+------------------------------
 quant   | {statement_timeout=30min}
(1 row)
```

### Step 3 - Add monitoring for long-running queries

On **pg-primary**, inside psql:

```sql
SELECT pid, usename, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE now() - query_start > interval '5 minutes'
  AND state = 'active'
  AND pid != pg_backend_pid()
ORDER BY duration DESC;
```

This is a manual check. To make it automatic, SSH to pg-ops and add a Prometheus alerting rule.

```bash
exit
```

```bash
exit
```

On **pg-ops**, as **ec2-user**:

```bash
sudo vi /etc/prometheus/rules/postgres_alerts.yml
```

Add this rule (or append to the existing rules file):

```yaml
  - alert: LongRunningQuery
    expr: pg_stat_activity_max_tx_duration{datname="quantdb"} > 300
    for: 2m
    labels:
      severity: warning
    annotations:
      summary: "Query running longer than 5 minutes in quantdb on {{ $labels.instance }}"
      description: "A query has been running for {{ $value }}s. Check pg_stat_activity for PIDs blocking DDL."
```

Reload Prometheus:

```bash
systemctl reload prometheus
```

### Step 4 - Schedule partition maintenance during low-traffic windows

Check when analytics jobs typically run:

On **pg-ops**, as **ec2-user**:

```bash
crontab -l | grep partition
```

If the partition maintenance cron is scheduled during business hours, move it to an off-peak window:

```bash
crontab -e
```

Change the schedule. For example, to run at 2:00 AM on the first of each month:

```
0 2 1 * * /opt/scripts/partition_manager.sh >> /var/log/partition_manager.log 2>&1
```

### Step 5 - Add retry logic to the partition maintenance script

On **pg-ops**, as **ec2-user**:

```bash
vi /opt/scripts/partition_manager.sh
```

Wrap the DDL in retry logic. A simplified pattern:

```bash
MAX_RETRIES=3
RETRY_WAIT=300  # 5 minutes between retries

for attempt in $(seq 1 $MAX_RETRIES); do
  echo "Attempt $attempt of $MAX_RETRIES at $(date)"
  if /usr/pgsql-17/bin/psql -d quantdb -c "SET lock_timeout='5s'; DROP TABLE IF EXISTS quant.market_data_2024_01;"; then
    echo "Drop succeeded on attempt $attempt"
    break
  else
    echo "Drop failed on attempt $attempt. Waiting ${RETRY_WAIT}s before retry."
    if [[ $attempt -lt $MAX_RETRIES ]]; then
      sleep $RETRY_WAIT
    fi
  fi
done
```

This gives the DDL three chances, spaced 5 minutes apart, before the maintenance job gives up and alerts.

```bash
exit
```

---

## Summary

### Root Cause

A long-running analytics query (`quant_analytics` role, 1:52 runtime) held an `AccessShareLock` on the `quant.market_data_2024_01` partition table. The monthly partition maintenance job attempted to run `DROP TABLE` on that partition, which requires `AccessExclusiveLock`. Because `AccessExclusiveLock` conflicts with `AccessShareLock`, the DDL queued behind the analytics query. Neither a `statement_timeout` on the analytics role nor a `lock_timeout` on the DDL was configured, so the situation persisted indefinitely.

### Resolution

1. Identified the blocking query (PID 11200) via `pg_stat_activity` and `pg_locks`
2. Used `pg_cancel_backend(11200)` to gracefully cancel the analytics query
3. Confirmed the partition maintenance job (PID 12345) unblocked and completed
4. Verified the partition table structure was correct after maintenance

### Prevention

- Added `lock_timeout = '5s'` to partition maintenance DDL statements so the maintenance job fails fast instead of blocking indefinitely
- Set `statement_timeout = '30min'` on the `quant` role so analytics queries cannot run indefinitely
- Added a Prometheus alert rule firing when any query in quantdb exceeds 5 minutes runtime
- Moved partition maintenance cron job to 2:00 AM on the first of each month
- Added retry logic to partition maintenance script (3 attempts, 5 minutes apart)

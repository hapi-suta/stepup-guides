# Tier 8 - Build Guide 04: Incident Response Runbooks

**Objective:** Build standardized runbooks for six common RDS/Aurora PostgreSQL incidents. Each runbook follows a consistent template covering symptoms, diagnosis, remediation, and prevention.
**Time:** 45 minutes
**Level:** Expert
**infra_required:** Partial - Most runbooks are reference documents. Some diagnostic commands require a running RDS instance to test against.
**Prerequisites:** Tier 8 Build 03 completed. Familiarity with psql, CloudWatch, and the RDS console.

---

## Runbook Template

Every runbook in your organization should follow this structure. Consistency matters because incidents are stressful and cognitive load must be minimized.

```
# Runbook: [Incident Name]
Severity: Critical | High | Medium
Last Updated: [DATE]
Owner: [TEAM NAME]

## Symptoms
## Impact
## Immediate Actions (first 5 minutes)
## Diagnosis
## Remediation
## Verification
## Prevention
## Escalation
```

---

## Runbook 1: Aurora/RDS Failover Event

**Severity:** High (for planned) | Critical (for unplanned)
**Typical Duration:** 30 seconds to 3 minutes (automatic failover)

### Symptoms

- CloudWatch alarm: `RDS-EventSubscription-Failover` fires
- RDS event in CloudWatch Events: `RDS-EVENT-0006` (failover started) and `RDS-EVENT-0002` (failover completed)
- Application errors: `could not connect to server: Connection refused` or `FATAL: the database system is starting up`
- Elevated error rate on application APM for the duration of the failover
- DNS TTL cache on instances not respecting low TTL values may extend the outage window

### Impact

- Writes unavailable for the duration of the failover (30 seconds to 3 minutes)
- Read traffic disrupted if application uses instance endpoints instead of the cluster endpoint
- Any in-flight transactions at the moment of failover are rolled back

### Immediate Actions (first 5 minutes)

1. Do not attempt to intervene in an automatic Aurora failover - it is self-healing. Your job is to monitor and communicate.

2. Confirm the failover is in progress (not a network issue masquerading as a failover):

```bash
aws rds describe-events \
  --source-identifier [CLUSTER-ID] \
  --source-type db-cluster \
  --duration 60 \
  --region [REGION]
```

3. Check which instance is now the writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].DBClusterMembers[?IsClusterWriter==`true`].DBInstanceIdentifier' \
  --output text \
  --region [REGION]
```

4. Post a status update to your incident channel: "Aurora failover in progress for [CLUSTER-ID]. Automatic recovery expected within 2 minutes. Monitoring."

### Diagnosis

After the failover completes, determine root cause:

```bash
# Review RDS events for the last 2 hours
aws rds describe-events \
  --source-identifier [CLUSTER-ID] \
  --source-type db-cluster \
  --duration 120 \
  --region [REGION]
```

Events to look for:
- `RDS-EVENT-0004`: DB instance restarted (may precede failover)
- `RDS-EVENT-0034`: Instance has failed due to an incompatible configuration
- `RDS-EVENT-0049`: Multi-AZ failover completed
- `RDS-EVENT-0051`: Multi-AZ failover started

Check for recent maintenance window activity:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].{MaintenanceWindow:PreferredMaintenanceWindow,PendingModified:PendingModifiedValues}' \
  --region [REGION]
```

### Remediation

If the failover was automatic and successful, remediation is typically:

1. Verify the new writer is accepting connections.
2. Verify the old primary has demoted to a reader.
3. Confirm application connection pools have re-established connections to the new writer via the cluster endpoint.

For applications using instance endpoints (a misconfiguration):

```bash
# Update the application's database connection string to use the cluster endpoint
# Cluster endpoint for Aurora:
aws rds describe-db-clusters \
  --db-cluster-identifier [CLUSTER-ID] \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region [REGION]
```

### Verification

```sql
-- Connect to the cluster endpoint and verify it is now the writer
SELECT pg_is_in_recovery();
-- Expected: f (false = this is the primary)

-- Check recent replication activity
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn
FROM pg_stat_replication;
```

### Prevention

- Applications must use the Aurora cluster endpoint for writes, never instance endpoints.
- Set DNS TTL awareness: use Aurora cluster DNS endpoint which updates within seconds of failover.
- Test failover behavior in staging quarterly.
- Add RDS Event Subscriptions for all failover events routing to your alerting system.
- Use RDS Proxy to absorb connection disruptions during failover.

---

## Runbook 2: Storage Exhaustion

**Severity:** Critical
**Risk:** Writes fail completely when FreeStorageSpace reaches zero. Reads may also fail if temporary files cannot be written.

### Symptoms

- CloudWatch alarm: `FreeStorageSpace` below threshold
- Application errors: `could not write to file` or `ERROR: could not extend file`
- PostgreSQL log: `ERROR: could not write block N of temporary file: No space left on device`
- `FreeStorageSpace` CloudWatch metric trending to zero

### Immediate Actions (first 5 minutes)

1. Confirm storage is the issue:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Minimum \
  --region [REGION]
```

2. Immediately increase storage (this is online and non-disruptive for most instance classes):

**Console:**
- RDS console > Databases > [INSTANCE-ID] > Modify
- Increase **Allocated storage** by a meaningful amount (at least 20% of current allocation)
- Apply immediately

**CLI:**
```bash
aws rds modify-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --allocated-storage [NEW-SIZE-GB] \
  --apply-immediately \
  --region [REGION]
```

Note: RDS allows you to increase storage but not decrease it. Size up with intent.

Storage expansion takes 10-30 minutes. Monitor progress:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].PendingModifiedValues' \
  --region [REGION]
```

### Diagnosis

While the storage expansion runs, identify what consumed space:

```sql
-- Connect to the database and find large tables
SELECT schemaname, relname,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS index_size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;
```

```sql
-- Find large WAL volume (bloat in pg_wal)
-- On RDS you cannot directly query the filesystem, but check for long-running transactions
-- that prevent WAL cleanup:
SELECT pid, now() - xact_start AS xact_duration, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_duration DESC
LIMIT 10;
```

```sql
-- Check for replication slots holding WAL
SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes
FROM pg_replication_slots;
```

An inactive replication slot accumulates WAL indefinitely. Drop it if it is no longer in use:

```sql
SELECT pg_drop_replication_slot('[SLOT-NAME]');
```

### Remediation

1. Storage expansion (in progress from immediate actions).
2. Drop any inactive replication slots that are accumulating WAL.
3. Terminate any long-running transactions holding open XID/WAL:

```sql
SELECT pg_terminate_backend([PID]);
```

4. If table bloat is the cause, schedule a VACUUM FULL on the largest tables (during a maintenance window - VACUUM FULL acquires an exclusive lock):

```sql
VACUUM FULL ANALYZE [TABLE-NAME];
```

### Verification

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Minimum \
  --region [REGION]
```

`FreeStorageSpace` should be increasing after the expansion completes.

### Prevention

- Enable RDS storage autoscaling (set a maximum threshold). This prevents most storage exhaustion events automatically.
- Set CloudWatch alarms at 30% and 15% free storage.
- Monitor and drop inactive replication slots monthly.
- Review table bloat quarterly.
- Enable autovacuum aggressively on high-churn tables to reclaim dead tuple space.

---

## Runbook 3: Connection Storm

**Severity:** Critical
**Risk:** All application requests fail with "too many connections." The database is alive but inaccessible.

### Symptoms

- Application errors: `FATAL: sorry, too many clients already` or `remaining connection slots are reserved for non-replication superuser connections`
- `DatabaseConnections` CloudWatch metric at or above `max_connections`
- Application load spike or deployment event coinciding with the alert

### Immediate Actions (first 5 minutes)

1. Check current connection count vs limit:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region [REGION]
```

2. If you can connect (use a superuser connection - they have reserved slots):

```sql
-- Check max_connections setting
SHOW max_connections;

-- Count connections by state and application name
SELECT application_name, state, count(*)
FROM pg_stat_activity
GROUP BY application_name, state
ORDER BY count DESC;
```

3. Identify idle-in-transaction connections (a major culprit in connection storms):

```sql
SELECT pid, now() - xact_start AS xact_duration, state, query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
ORDER BY xact_duration DESC
LIMIT 20;
```

### Remediation

**Option 1: Terminate idle connections to free slots**

```sql
-- Terminate idle connections older than 10 minutes
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
AND now() - state_change > interval '10 minutes'
AND pid <> pg_backend_pid();
```

```sql
-- Terminate idle-in-transaction connections older than 5 minutes
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND now() - xact_start > interval '5 minutes'
AND pid <> pg_backend_pid();
```

**Option 2: Increase max_connections temporarily (requires restart)**

Only do this if Option 1 does not create enough headroom. Increasing `max_connections` requires a database restart on RDS.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters ParameterName=max_connections,ParameterValue=[NEW-VALUE],ApplyMethod=pending-reboot \
  --region [REGION]
```

Then reboot the instance (brief downtime):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --region [REGION]
```

**Option 3: Route traffic through PgBouncer (proper long-term fix)**

If this is a recurring incident, the root cause is almost always a missing connection pooler. Deploy PgBouncer in front of the database to multiplex application connections.

### Verification

```sql
-- After remediation, confirm connection count is below threshold
SELECT count(*), state FROM pg_stat_activity GROUP BY state;
```

### Prevention

- Deploy PgBouncer or RDS Proxy between application and database. This is non-negotiable for any application with more than a few hundred concurrent users.
- Set `statement_timeout` and `idle_in_transaction_session_timeout` in the parameter group to kill stuck sessions automatically.
- Set `max_connections` to a value the instance can sustain, not the highest possible number.
- Monitor `DatabaseConnections` and alert at 70% of `max_connections`.

---

## Runbook 4: Replication Lag

**Severity:** High (for Aurora readers) | Critical (if reader is a failover target with RPO requirements)
**Risk:** Read replicas serve stale data. If lag is extreme, the replica may not qualify as a viable failover target.

### Symptoms

- CloudWatch alarm: `AuroraReplicaLag` or `ReplicaLag` above threshold
- Application read queries returning stale data
- Lag increasing monotonically (not recovering on its own)

### Diagnosis

```bash
# Check current replica lag from CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=[READER-INSTANCE-ID] \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Maximum \
  --region [REGION]
```

```sql
-- Connect to the writer and check replication status
SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_behind
FROM pg_stat_replication
ORDER BY bytes_behind DESC;
```

Root causes of lag:

1. **Long-running transactions on the primary** block the vacuum and WAL cleanup, increasing replay lag on the replica.
2. **High write rate** exceeding replica's apply throughput - replica is under-provisioned.
3. **Hot standby feedback enabled** on the replica causes it to tell the primary to retain rows it may need, which can cause the primary's autovacuum to skip work.
4. **Logical replication slots** hold WAL - confirm no inactive slots on the primary.

### Remediation

For lag caused by long-running transactions on the primary:

```sql
-- Find and terminate long-running transactions (confirm with app team first)
SELECT pid, now() - xact_start AS xact_duration, query
FROM pg_stat_activity
WHERE state != 'idle'
AND xact_start < now() - interval '30 minutes'
ORDER BY xact_duration DESC;

SELECT pg_terminate_backend([PID]);
```

For lag caused by replica under-provisioning:

```bash
# Scale up the reader instance
aws rds modify-db-instance \
  --db-instance-identifier [READER-INSTANCE-ID] \
  --db-instance-class db.r6g.4xlarge \
  --apply-immediately \
  --region [REGION]
```

### Verification

After remediation, lag should trend toward zero on the CloudWatch metric. It may take 10-30 minutes to fully recover depending on accumulated lag.

### Prevention

- Size read replicas at least as large as the writer. In practice, readers doing heavy analytical queries should be larger.
- Alert on lag > 30 seconds as a warning, > 5 minutes as critical.
- Set `max_standby_streaming_delay = -1` on replicas only if acceptable for your workload (allows replicas to wait indefinitely rather than cancel conflicting queries, which can increase lag differently).
- Use `statement_timeout` on the primary to prevent queries that would hold transactions open for extended periods.

---

## Runbook 5: Autovacuum / Wraparound Emergency

**Severity:** Critical
**Risk:** If the transaction ID age of any database reaches 2^31 (approximately 2.1 billion), PostgreSQL will shut down to protect data integrity. This is called transaction ID wraparound.

### Symptoms

- PostgreSQL log: `WARNING: database "dbname" must be vacuumed within N transactions`
- PostgreSQL log: `ERROR: database is not accepting commands to avoid wraparound data loss`
- CloudWatch custom metric `WraparoundWarningCount` firing
- `age(datfrozenxid)` > 1.5 billion when you query `pg_database`

### Immediate Actions (first 5 minutes)

1. Check wraparound proximity immediately:

```sql
SELECT datname,
       age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS transactions_remaining,
       round(age(datfrozenxid) * 100.0 / 2000000000, 2) AS pct_of_limit
FROM pg_database
ORDER BY xid_age DESC;
```

If `pct_of_limit` > 90%, this is a P0 incident requiring immediate action.

2. Check which tables have not been frozen recently:

```sql
SELECT schemaname, relname,
       greatest(age(relfrozenxid), age(relminmxid)) AS table_xid_age,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE relkind = 'r'
AND greatest(age(relfrozenxid), age(relminmxid)) > 1000000000
ORDER BY table_xid_age DESC
LIMIT 20;
```

### Remediation

**Phase 1: Manual VACUUM FREEZE on the most affected tables**

```sql
-- This freezes tuple XIDs, directly reducing wraparound risk
-- WARNING: This can be I/O intensive. Run during low-traffic periods if possible.
VACUUM FREEZE VERBOSE [SCHEMA].[TABLE-NAME];
```

For emergency wraparound, run VACUUM FREEZE on the entire database:

```sql
VACUUM FREEZE;
-- This locks no tables but will be very I/O intensive.
-- Monitor pg_stat_progress_vacuum for progress.
```

**Phase 2: Temporarily boost autovacuum aggressiveness**

Modify the parameter group to allow autovacuum to work faster:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAMETER-GROUP-NAME] \
  --parameters \
    ParameterName=autovacuum_vacuum_cost_delay,ParameterValue=2,ApplyMethod=immediate \
    ParameterName=autovacuum_max_workers,ParameterValue=6,ApplyMethod=immediate \
    ParameterName=autovacuum_vacuum_cost_limit,ParameterValue=800,ApplyMethod=immediate \
  --region [REGION]
```

`autovacuum_vacuum_cost_delay=2` (ms) speeds up autovacuum by reducing the sleep between I/O operations. Default is 20ms.
`autovacuum_max_workers=6` allows more parallel autovacuum workers.
`autovacuum_vacuum_cost_limit=800` increases the work done per unit time.

**Phase 3: Monitor progress**

```sql
-- Monitor VACUUM progress in real time
SELECT pid, phase, heap_blks_total, heap_blks_vacuumed,
       round(heap_blks_vacuumed * 100.0 / NULLIF(heap_blks_total, 0), 2) AS pct_complete,
       num_dead_tuples
FROM pg_stat_progress_vacuum;
```

### Verification

After VACUUM FREEZE completes, re-check wraparound proximity:

```sql
SELECT datname, age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS transactions_remaining
FROM pg_database
ORDER BY xid_age DESC;
```

The `xid_age` values should be significantly lower after successful freezing.

### Prevention

- Monitor `age(datfrozenxid)` as a standard metric. Alert at 500 million, page at 1 billion.
- Set `autovacuum_freeze_max_age = 200000000` (200 million) - this is more aggressive than the default 200 million. Trigger freezing earlier.
- Never disable autovacuum.
- On very high-churn tables, use per-table autovacuum settings to vacuum more frequently.
- Set `vacuum_freeze_min_age = 5000000` to freeze tuples earlier.

---

## Runbook 6: citext vs text Index Bypass

**Severity:** Medium (performance) | High (if causing query timeouts or full table scans at scale)
**Risk:** Queries bypass indexes silently, causing sequential scans on large tables, leading to high CPU and slow response times.

### Symptoms

- Specific queries are suddenly slow after a schema change or extension installation
- `EXPLAIN` shows `Seq Scan` on a table that has an index on the queried column
- The column is type `text` but queries use `citext` functions or vice versa
- Or: the column is type `citext` but the index was created as a `text` index or uses the default `btree` operator class

### Diagnosis

```sql
-- Check if citext extension is installed
SELECT * FROM pg_extension WHERE extname = 'citext';

-- Check the data type of the column in question
SELECT column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_name = '[TABLE-NAME]'
AND column_name = '[COLUMN-NAME]';

-- Check the index definition
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = '[TABLE-NAME]';

-- Run EXPLAIN to see if the index is being used
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM [TABLE-NAME] WHERE [COLUMN-NAME] = 'SearchValue';
```

A `Seq Scan` on a table with an index is the key signal.

**Common scenarios:**

1. Column is `text`, queried with `lower([COLUMN-NAME]) = lower('value')` or `[COLUMN-NAME] ILIKE 'value'`. The index on `text` without a functional index on `lower()` will be bypassed.

2. Column is `citext`, but index was created without the `citext_ops` operator class (or the index was created before `citext` was installed and recreated).

3. Column is `text`, index exists, but queries use `citext` casting: `[COLUMN-NAME]::citext = 'value'`. The cast changes the operator and the planner cannot use the plain `text` index.

### Remediation

**Fix 1: Create a functional index for case-insensitive text**

If the column is `text` and queries use `lower()`:

```sql
CREATE INDEX CONCURRENTLY idx_[TABLE]_[COLUMN]_lower
ON [TABLE-NAME] (lower([COLUMN-NAME]));
```

Then rewrite the query to use `lower([COLUMN-NAME]) = lower('search_value')` consistently.

**Fix 2: Convert column to citext and rebuild index**

If the intent is always case-insensitive comparison, convert the column:

```sql
-- Requires table lock - plan for a maintenance window on large tables
CREATE EXTENSION IF NOT EXISTS citext;

ALTER TABLE [TABLE-NAME]
ALTER COLUMN [COLUMN-NAME] TYPE citext
USING [COLUMN-NAME]::citext;

-- Drop and recreate the index with the citext operator class
DROP INDEX CONCURRENTLY idx_[TABLE]_[COLUMN];
CREATE INDEX CONCURRENTLY idx_[TABLE]_[COLUMN]_citext
ON [TABLE-NAME] ([COLUMN-NAME] citext_ops);
```

**Fix 3: Use CONCURRENTLY to avoid locking during index creation**

For large tables in production, always use `CONCURRENTLY`:

```sql
CREATE INDEX CONCURRENTLY idx_[TABLE]_[COLUMN]_citext
ON [TABLE-NAME] USING btree ([COLUMN-NAME] citext_ops);
```

`CONCURRENTLY` builds the index without locking writes. It takes longer but does not cause downtime.

### Verification

```sql
-- After the index is created, re-run EXPLAIN
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM [TABLE-NAME] WHERE [COLUMN-NAME] = 'SearchValue';
```

The plan should now show `Index Scan` or `Index Only Scan` instead of `Seq Scan`.

### Prevention

- During schema reviews, explicitly document whether case-insensitive comparisons are needed and whether `citext` or functional indexes are the chosen approach.
- Add pg query review to your CI pipeline - catch sequential scans on large tables in testing before they reach production.
- After any extension installation that changes operator semantics, audit indexes on affected column types.

---

## Summary

| Incident | First Check | First Action | Root Cause Pattern |
|----------|-------------|--------------|-------------------|
| Failover | RDS Events API | Monitor, do not intervene | AZ failure, instance failure, manual trigger |
| Storage exhaustion | FreeStorageSpace metric | Increase allocated storage immediately | Bloat, inactive replication slots, WAL accumulation |
| Connection storm | DatabaseConnections metric | Terminate idle/idle-in-transaction sessions | Missing connection pooler, connection leak |
| Replication lag | AuroraReplicaLag metric | Find and terminate long-running transactions on primary | Long transactions, high write rate, under-provisioned replica |
| Wraparound | age(datfrozenxid) | VACUUM FREEZE, boost autovacuum | Disabled or under-configured autovacuum, very high write rate |
| Index bypass | EXPLAIN plan | Create appropriate functional or citext index | Operator class mismatch, type mismatch between column and query |

**Next:** [Guide 05 - Capacity Planning with pgbench](./05-capacity-planning-pgbench.md)

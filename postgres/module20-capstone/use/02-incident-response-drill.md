# Use 02: Incident Response Drill

Five incident scenarios presented as on-call tickets. Triage each one, diagnose the root cause, fix it, and write a post-incident review. Each scenario is time-boxed to 15 minutes.

---

## Instructions

1. Start a timer for each scenario (15 minutes)
2. Read the ticket
3. Diagnose using the tools available
4. Fix the issue
5. Write a brief post-incident review using the template at the bottom
6. Move to the next scenario

You will be graded on:
- Time to first meaningful diagnostic command
- Correct root cause identification
- Quality of the fix (does it prevent recurrence?)
- Post-incident review completeness

---

## Scenario 1: Application Cannot Connect

**Priority**: P1 - Critical
**Reporter**: Application Team
**Time**: 02:17 AM

**Ticket**:

> The application is returning "FATAL: remaining connection slots are reserved for non-replication superuser connections" since 2:15 AM. All API endpoints are returning 503. Customer-facing impact.

### Your task:

1. Identify how many connections are open and what they are doing
2. Find the root cause (what is consuming all connections?)
3. Restore service immediately
4. Prevent recurrence

### Hints (only read if stuck after 5 minutes):

Check pg_stat_activity grouped by state. Look for `idle in transaction` connections. Check if pgBouncer is running. Check application deploy history.

### Diagnostic commands to start with:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT state, count(*) FROM pg_stat_activity GROUP BY state ORDER BY count DESC;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT usename, application_name, state, count(*) FROM pg_stat_activity GROUP BY 1, 2, 3 ORDER BY count DESC LIMIT 10;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pid, usename, state, now() - xact_start AS txn_age, left(query, 60) FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY txn_age DESC;"
```

### Expected fix:

Terminate idle-in-transaction connections older than 5 minutes:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND now() - xact_start > interval '5 minutes';"
```

Set a timeout to prevent recurrence:

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM SET idle_in_transaction_session_timeout = '300000';"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

```bash
exit
```

---

## Scenario 2: Replication Lag Spiking

**Priority**: P2 - High
**Reporter**: Monitoring Alert
**Time**: 10:45 AM

**Ticket**:

> Alert: ReplicationLagHigh - Replication lag has been above 30 seconds for the past 10 minutes. The standby was in sync earlier this morning. No recent deployments.

### Your task:

1. Confirm the lag and measure it precisely
2. Determine if the issue is on the primary (sending) or standby (replaying)
3. Fix it
4. Verify lag returns to zero

### Diagnostic commands to start with:

On the **primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state, sent_lsn, write_lsn, flush_lsn, replay_lsn, pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes FROM pg_stat_replication;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_current_wal_lsn();"
```

On the **standby**:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn(), pg_last_xact_replay_timestamp(), now() - pg_last_xact_replay_timestamp() AS replay_delay;"
```

Check for recovery conflicts:

```bash
/usr/pgsql-16/bin/psql -c "SELECT datname, confl_tablespace, confl_lock, confl_snapshot, confl_bufferpin, confl_deadlock FROM pg_stat_database_conflicts;"
```

```bash
exit
```

### Common root causes:

- Long-running query on standby blocking replay (check `confl_snapshot`)
- Network issue between primary and standby
- Standby disk I/O saturated (check `iostat`)
- Large batch operation on primary generating lots of WAL

---

## Scenario 3: Sudden Slow Queries

**Priority**: P2 - High
**Reporter**: Application Team
**Time**: 3:30 PM

**Ticket**:

> API response times jumped from 50ms to 2000ms at 3:25 PM. The orders endpoint is the worst affected. No code changes deployed today.

### Your task:

1. Identify the slow queries
2. Determine why they became slow (what changed?)
3. Fix the immediate issue
4. Prevent recurrence

### Diagnostic commands to start with:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT pid, now() - query_start AS runtime, state, wait_event_type, wait_event, left(query, 80) FROM pg_stat_activity WHERE state = 'active' AND pid != pg_backend_pid() ORDER BY runtime DESC;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT left(query, 60), calls, round(mean_exec_time::numeric, 1) AS avg_ms, round(max_exec_time::numeric, 1) AS max_ms FROM pg_stat_statements WHERE dbid = (SELECT oid FROM pg_database WHERE datname = 'appdb') ORDER BY mean_exec_time DESC LIMIT 10;"
```

Check for missing indexes:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname, relname, seq_scan, idx_scan, seq_tup_read FROM pg_stat_user_tables WHERE seq_scan > 100 AND seq_tup_read > 10000 ORDER BY seq_tup_read DESC LIMIT 10;"
```

Check for table bloat:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT schemaname, relname, n_live_tup, n_dead_tup, round(n_dead_tup::numeric / greatest(n_live_tup, 1) * 100, 1) AS dead_pct, last_autovacuum FROM pg_stat_user_tables WHERE n_dead_tup > 1000 ORDER BY dead_pct DESC;"
```

Check for plan changes (statistics reset):

```bash
/usr/pgsql-16/bin/psql -d appdb -c "EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM app.orders WHERE customer_id = 42;"
```

```bash
exit
```

### Common root causes:

- Autovacuum fell behind, stale statistics caused bad plans
- Index was dropped accidentally
- Table bloat causing sequential scans
- Lock contention from a concurrent migration

---

## Scenario 4: Disk Space Critical

**Priority**: P1 - Critical
**Reporter**: Monitoring Alert
**Time**: 11:00 PM

**Ticket**:

> Alert: DiskUsageHigh - Root filesystem is 94% full. PostgreSQL may stop accepting writes if it reaches 100%.

### Your task:

1. Identify what is consuming disk space
2. Free space immediately (without data loss)
3. Prevent recurrence
4. Document what you removed and why

### Diagnostic commands to start with:

```bash
df -h
```

```bash
du -sh /opt/pgsql/data
```

```bash
du -sh /opt/pgsql/wal
```

```bash
du -sh /opt/pgsql/log
```

```bash
du -sh /opt/pgsql/backup
```

Check for WAL accumulation:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes FROM pg_replication_slots ORDER BY retained_bytes DESC;"
```

Check for old log files:

```bash
ls -lhS /opt/pgsql/log/ | head -10
```

```bash
exit
```

### Emergency actions (in order of safety):

1. Remove old PostgreSQL logs (oldest first)
2. Expire old backups: `pgbackrest --stanza=prod expire`
3. Drop inactive replication slots
4. VACUUM FULL on bloated tables (last resort - locks the table)
5. Increase volume size (if cloud)

---

## Scenario 5: Data Inconsistency Reported

**Priority**: P2 - High
**Reporter**: Business Team
**Time**: 9:00 AM

**Ticket**:

> Finance reports that order totals for yesterday do not match between the main dashboard (reads from primary) and the analytics dashboard (reads from standby). The difference is about 50 orders.

### Your task:

1. Verify the discrepancy exists
2. Determine root cause (replication lag, split-brain, stale read?)
3. Fix the issue
4. Explain to the business team what happened

### Diagnostic commands to start with:

On the **primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*), sum(total_cents) FROM app.orders WHERE created_at >= now() - interval '1 day';"
```

On the **standby**:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*), sum(total_cents) FROM app.orders WHERE created_at >= now() - interval '1 day';"
```

Check replication lag:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_last_xact_replay_timestamp(), now() - pg_last_xact_replay_timestamp() AS lag;"
```

Check if standby had recovery conflicts:

```bash
/usr/pgsql-16/bin/psql -c "SELECT * FROM pg_stat_database_conflicts WHERE datname = 'appdb';"
```

```bash
exit
```

### Common root causes:

- Replication lag (standby is behind)
- The analytics query used a snapshot from before all yesterday's data was committed
- A long-running transaction on the standby delayed replay
- Timezone mismatch between the two queries (UTC vs local)

---

## Post-Incident Review Template

Copy this template for each scenario:

```
## Post-Incident Review

### Incident: [Scenario title]
### Duration: [Time from alert to resolution]
### Severity: [P1/P2/P3]

### Timeline
- HH:MM - Alert fired / ticket created
- HH:MM - First responder acknowledged
- HH:MM - Root cause identified
- HH:MM - Fix applied
- HH:MM - Verified resolved

### Root Cause
[What caused the incident - be specific]

### Fix Applied
[Exact commands or changes made]

### Impact
- Users affected: [number/description]
- Data loss: [yes/no, how much]
- Duration of impact: [time]

### Prevention
1. [Action item to prevent recurrence]
2. [Action item to detect faster next time]
3. [Action item to automate the fix]

### Lessons Learned
- What went well:
- What could be improved:
```

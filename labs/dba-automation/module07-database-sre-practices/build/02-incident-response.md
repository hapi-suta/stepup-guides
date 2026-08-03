# BUILD 02: Incident Response for Database Outages

**Module 07: Database SRE Practices**
**Estimated Time: 60-75 minutes**

---

## What You Will Learn

How to structure your response to database incidents - from the moment an alert fires to the post-incident review that prevents recurrence.

---

## Incident Severity Levels

Not every problem is an emergency. Severity levels help you prioritize response and communication.

| Severity | Name | Database Examples | Response Time | Who is Notified |
|----------|------|------------------|---------------|----------------|
| **SEV1** | Critical | Primary database down, all writes failing, data loss risk | Immediate (< 5 min) | On-call DBA, engineering lead, management |
| **SEV2** | Major | Standby down (HA degraded), severe performance degradation, replication broken | 15 min | On-call DBA, engineering team |
| **SEV3** | Minor | Slow queries affecting some users, disk 85% full, connection pool near limit | 1 hour | DBA team (Slack/email) |
| **SEV4** | Cosmetic | Non-critical monitoring gap, minor config drift, unused index | Next business day | DBA backlog |

**DBA Analogy:** Think of these like PostgreSQL log levels:
- SEV1 = PANIC (system is unusable)
- SEV2 = FATAL (significant functionality broken)
- SEV3 = WARNING (something needs attention soon)
- SEV4 = NOTICE (informational, handle when convenient)

---

## Step 1: The Incident Commander Role

When a SEV1 or SEV2 hits, someone needs to take charge. The Incident Commander (IC) coordinates the response.

**DBA Analogy:** The IC is the DBA who takes charge during an outage. They do not fix the problem themselves - they coordinate the people who do.

### Incident Commander Responsibilities

1. **Declare the incident:** "This is a SEV1. I am the Incident Commander."
2. **Coordinate responders:** Assign tasks - "Alice, check replication. Bob, check disk space."
3. **Communicate status updates:** Every 15 minutes to stakeholders.
4. **Make decisions:** "We are failing over to the standby. Go."
5. **Track timeline:** Document what happened and when.
6. **Declare resolution:** "The incident is resolved. We will schedule a post-incident review."

### Communication During Incidents

```
TEMPLATE: Status Update

INCIDENT: [Brief description]
SEVERITY: SEV[1/2]
STATUS: [Investigating / Identified / Mitigating / Resolved]
IMPACT: [What is broken for users]
CURRENT ACTIONS: [What the team is doing right now]
NEXT UPDATE: [When the next update will be posted]
IC: [Name]
```

**Example:**

```
INCIDENT: Primary database connection failures
SEVERITY: SEV1
STATUS: Identified
IMPACT: All write operations failing. Read traffic degraded.
CURRENT ACTIONS: Patroni detected failure, automatic failover in progress.
  Standby pg-standby-1 is being promoted.
NEXT UPDATE: 15 minutes (or sooner if status changes)
IC: Happy
```

---

## Step 2: Runbook-Driven Response

A runbook is a documented procedure for responding to a specific incident type. Instead of debugging from scratch every time, you follow a tested procedure.

**DBA Analogy:** You have probably written internal docs like "what to do when replication breaks" or "how to handle a full disk." A runbook is that, but structured and tested.

---

## Step 3: Runbook - Connection Spike

```bash
mkdir -p ~/dba-labs/sre-practice/runbooks
vi ~/dba-labs/sre-practice/runbooks/connection-spike.md
```

```markdown
# Runbook: Connection Spike

## Trigger
Alert: Active connections > 80% of max_connections

## Severity
SEV2 (SEV1 if connections = max_connections)

## Impact
New connections are refused. Applications see "FATAL: too many connections" errors.

## Diagnosis

### Step 1: Check current connection count

    SELECT
        count(*) AS total,
        count(*) FILTER (WHERE state = 'active') AS active,
        count(*) FILTER (WHERE state = 'idle') AS idle,
        count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn,
        (SELECT setting::int FROM pg_settings WHERE name = 'max_connections') AS max_conn
    FROM pg_stat_activity;

### Step 2: Identify the source of connections

    SELECT
        client_addr,
        usename,
        datname,
        count(*) AS conn_count,
        count(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_txn
    FROM pg_stat_activity
    GROUP BY client_addr, usename, datname
    ORDER BY conn_count DESC
    LIMIT 20;

### Step 3: Check for idle-in-transaction connections (these hold locks)

    SELECT
        pid,
        usename,
        state,
        now() - state_change AS idle_duration,
        left(query, 100) AS last_query
    FROM pg_stat_activity
    WHERE state = 'idle in transaction'
    ORDER BY state_change ASC;

## Mitigation

### Option A: Kill idle-in-transaction connections (safe)

    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE state = 'idle in transaction'
      AND now() - state_change > interval '10 minutes';

### Option B: Kill idle connections from the top consumer

    SELECT pg_terminate_backend(pid)
    FROM pg_stat_activity
    WHERE client_addr = 'X.X.X.X'  -- Replace with top consumer
      AND state = 'idle'
      AND now() - state_change > interval '5 minutes';

### Option C: Temporarily increase max_connections (if memory allows)

    ALTER SYSTEM SET max_connections = 300;
    -- Requires restart - use only as last resort

## Prevention
- Deploy PgBouncer for connection pooling
- Set idle_in_transaction_session_timeout = '5min' in postgresql.conf
- Configure statement_timeout = '60s' for application users
- Monitor connection count with alerting at 70% and 85% thresholds

## Escalation
If connections remain maxed after killing idle sessions, escalate to SEV1
and investigate application-level connection leaks.
```

---

## Step 4: Runbook - Replication Lag

```bash
vi ~/dba-labs/sre-practice/runbooks/replication-lag.md
```

```markdown
# Runbook: Replication Lag

## Trigger
Alert: Replication lag > 30 seconds on any standby

## Severity
SEV2 (SEV1 if lag > 5 minutes and standby is serving read traffic)

## Impact
Read replicas return stale data. If the primary fails, failover would lose
recent transactions (up to the lag amount).

## Diagnosis

### Step 1: Check lag on primary

    SELECT
        client_addr,
        application_name,
        state,
        sent_lsn,
        write_lsn,
        flush_lsn,
        replay_lsn,
        pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
        write_lag,
        flush_lag,
        replay_lag
    FROM pg_stat_replication;

### Step 2: Check standby replay status (on the standby)

    SELECT
        pg_is_in_recovery() AS is_standby,
        pg_last_wal_receive_lsn() AS received_lsn,
        pg_last_wal_replay_lsn() AS replayed_lsn,
        pg_last_xact_replay_timestamp() AS last_replay_time,
        extract(epoch FROM now() - pg_last_xact_replay_timestamp()) AS lag_seconds;

### Step 3: Check what the standby is doing

    -- On the standby: is it replaying or stuck?
    SELECT * FROM pg_stat_wal_receiver;

    -- Check for long-running queries on standby that block replay
    SELECT pid, state, now() - query_start AS duration, left(query, 100)
    FROM pg_stat_activity
    WHERE state = 'active'
    ORDER BY query_start ASC
    LIMIT 10;

### Step 4: Check WAL generation rate on primary

    -- High WAL generation can outpace standby replay
    SELECT
        pg_wal_lsn_diff(pg_current_wal_lsn(), '0/0') / 1024 / 1024 AS wal_total_mb,
        pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn) / 1024 AS unsent_kb
    FROM pg_stat_replication;

## Mitigation

### If standby is stuck on a long query:
Kill the blocking query on the standby:

    SELECT pg_cancel_backend(pid);

### If WAL is not being received:
Check network between primary and standby.
Check if wal_sender is running on primary:

    SELECT * FROM pg_stat_activity WHERE backend_type = 'walsender';

### If standby fell too far behind:
The standby may need to be rebuilt:

    pg_basebackup -h primary-host -U replicator -D /var/lib/pgsql/16/data -R -P

### If caused by high write volume:
Consider temporarily increasing wal_sender_timeout and adjusting
max_wal_size to retain more WAL.

## Prevention
- Set hot_standby_feedback = on (prevents vacuum conflicts)
- Configure max_standby_streaming_delay = '30s'
- Monitor WAL generation rate and standby network throughput
- Size standby hardware to match primary

## Escalation
If lag exceeds 5 minutes and cannot be resolved in 15 minutes,
consider taking the standby out of the read pool and rebuilding it.
```

---

## Step 5: Runbook - Disk Full

```bash
vi ~/dba-labs/sre-practice/runbooks/disk-full.md
```

```markdown
# Runbook: Disk Full

## Trigger
Alert: Disk usage > 90% on data or WAL partition

## Severity
SEV1 (PostgreSQL will crash if disk reaches 100%)

## Impact
At 100% disk, PostgreSQL cannot write WAL or data. The database crashes
and may require recovery. Write operations fail immediately.

## Diagnosis

### Step 1: Check disk usage

    df -h /var/lib/pgsql
    df -h /var/lib/pgsql/16/data/pg_wal

### Step 2: Find what is consuming space

    -- Check database sizes
    SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database ORDER BY pg_database_size(datname) DESC;

    -- Check largest tables
    SELECT
        schemaname || '.' || relname AS table_name,
        pg_size_pretty(pg_total_relation_size(relid)) AS total_size
    FROM pg_stat_user_tables
    ORDER BY pg_total_relation_size(relid) DESC
    LIMIT 20;

### Step 3: Check WAL retention

    -- How much WAL is retained?
    du -sh /var/lib/pgsql/16/data/pg_wal/
    ls -la /var/lib/pgsql/16/data/pg_wal/ | wc -l

### Step 4: Check for bloat

    SELECT
        schemaname || '.' || relname AS table_name,
        n_dead_tup,
        n_live_tup,
        round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 1) AS dead_pct
    FROM pg_stat_user_tables
    WHERE n_dead_tup > 10000
    ORDER BY n_dead_tup DESC;

## Mitigation (in order of safety)

### Option A: Clean up old WAL (if archive is confirmed)

    -- Check if WAL has been archived
    SELECT * FROM pg_stat_archiver;

    -- If archive is healthy, old WAL is safe to remove
    pg_archivecleanup /var/lib/pgsql/16/data/pg_wal 0000000100000001000000XX

### Option B: Clean up old logs

    du -sh /var/lib/pgsql/16/data/log/
    # Remove logs older than 7 days
    find /var/lib/pgsql/16/data/log/ -name "*.log" -mtime +7 -delete

### Option C: Vacuum bloated tables

    VACUUM (VERBOSE) large_bloated_table;

### Option D: Drop known temp/staging tables

    DROP TABLE IF EXISTS tmp_import_data;
    DROP TABLE IF EXISTS old_backup_table;

### Option E: Add disk (last resort, requires downtime or LVM)

    -- If on AWS, expand EBS volume
    -- If on LVM, extend the logical volume

## Prevention
- Alert at 70% disk usage (warning) and 85% (critical)
- Configure log_rotation_age = '1d' and log_rotation_size = '100MB'
- Set archive_cleanup_command in recovery.conf / standby
- Schedule weekly disk usage reports
- Use autovacuum aggressively on high-churn tables

## Escalation
If disk > 95% and no quick wins available, failover to a standby
with more disk space. Do NOT let the primary reach 100%.
```

---

## Step 6: Blameless Post-Incident Reviews

After every SEV1 and SEV2 incident, conduct a post-incident review (PIR). The goal is to understand what happened and prevent recurrence - not to assign blame.

**DBA Analogy:** This is NOT "who broke it?" It IS "what allowed it to break, and how do we prevent it?"

### Post-Incident Review Template

```bash
vi ~/dba-labs/sre-practice/templates/post-incident-review.md
```

```markdown
# Post-Incident Review: [Incident Title]

**Date:** [Date of incident]
**Duration:** [Start time] to [Resolution time] ([Total duration])
**Severity:** SEV[X]
**Incident Commander:** [Name]

## Summary
[2-3 sentences describing what happened and the impact]

## Timeline
| Time (UTC) | Event |
|-----------|-------|
| HH:MM | Alert triggered: [description] |
| HH:MM | IC acknowledged, investigation started |
| HH:MM | Root cause identified: [description] |
| HH:MM | Mitigation applied: [description] |
| HH:MM | Service restored, monitoring confirmed |
| HH:MM | Incident declared resolved |

## Impact
- **Users affected:** [Number or percentage]
- **Duration of impact:** [Time]
- **Data loss:** [Yes/No - if yes, describe]
- **Error budget consumed:** [X minutes of Y remaining]
- **Revenue impact:** [Estimate if known]

## Root Cause
[Detailed technical description of why the incident occurred.
Not "someone made a mistake" but "the system allowed X to happen because Y"]

## Contributing Factors
- [Factor 1: e.g., "No monitoring on WAL disk usage"]
- [Factor 2: e.g., "Autovacuum was disabled on the large table"]
- [Factor 3: e.g., "Runbook for this scenario did not exist"]

## What Went Well
- [e.g., "Automatic failover worked as expected"]
- [e.g., "IC was on scene within 3 minutes"]
- [e.g., "Communication was clear and timely"]

## What Went Wrong
- [e.g., "No alert existed for this failure mode"]
- [e.g., "Runbook was outdated and referenced wrong file paths"]
- [e.g., "Took 20 minutes to identify root cause"]

## Action Items
| ID | Action | Owner | Priority | Due Date |
|----|--------|-------|----------|----------|
| 1 | [Action] | [Name] | P1/P2/P3 | [Date] |
| 2 | [Action] | [Name] | P1/P2/P3 | [Date] |
| 3 | [Action] | [Name] | P1/P2/P3 | [Date] |

## Lessons Learned
[Key takeaways that should be shared with the broader team]
```

---

## Step 7: MTTD, MTTR, and MTTF Metrics

These metrics track your incident response effectiveness over time:

| Metric | Full Name | What It Measures | How to Improve |
|--------|-----------|-----------------|----------------|
| **MTTD** | Mean Time to Detect | How long before you know something is wrong | Better monitoring, lower alert thresholds |
| **MTTR** | Mean Time to Respond | How long from detection to first human action | Faster paging, better on-call rotation |
| **MTTR** | Mean Time to Recover | How long from detection to full resolution | Better runbooks, automated remediation |
| **MTTF** | Mean Time to Failure | How long between incidents | Root cause fixes, chaos engineering |

**DBA Analogy:**
- MTTD = How long before you notice replication is broken?
- MTTR (respond) = How long before a DBA starts investigating?
- MTTR (recover) = How long before replication is fixed?
- MTTF = How long between replication failures?

### Tracking These Metrics

```sql
-- Example: incident tracking table
CREATE TABLE incident_log (
    incident_id SERIAL PRIMARY KEY,
    severity VARCHAR(5) NOT NULL,
    title TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    root_cause TEXT,
    action_items TEXT[]
);

-- Calculate MTTD, MTTR
SELECT
    severity,
    count(*) AS incident_count,
    round(avg(extract(epoch FROM responded_at - detected_at) / 60), 1) AS avg_mttd_minutes,
    round(avg(extract(epoch FROM resolved_at - detected_at) / 60), 1) AS avg_mttr_minutes
FROM incident_log
WHERE detected_at > now() - interval '90 days'
GROUP BY severity
ORDER BY severity;
```

---

## Step 8: Practical - Write Three Runbooks

Using the templates and examples above, write runbooks for three common database incidents. Store them in `~/dba-labs/sre-practice/runbooks/`.

Each runbook should include:
1. Trigger condition (what alert fires?)
2. Severity classification
3. Impact description
4. Step-by-step diagnosis queries
5. Mitigation options (ordered by safety)
6. Prevention measures
7. Escalation criteria

Suggested incidents:
- **Connection spike** (completed above)
- **Replication lag** (completed above)
- **Disk full** (completed above)

Additional runbooks to write as practice:
- Long-running transaction blocking others
- High CPU from a runaway query
- Patroni failover did not complete

---

## What You Learned

| Topic | Key Takeaway |
|-------|-------------|
| Severity levels | SEV1 (critical) through SEV4 (cosmetic) - prioritize response |
| Incident Commander | One person coordinates the response, does not debug |
| Communication | Structured status updates every 15 minutes during SEV1/SEV2 |
| Runbooks | Pre-written procedures for common incidents - follow, do not improvise |
| Connection spike runbook | Identify source, kill idle-in-transaction, consider PgBouncer |
| Replication lag runbook | Check WAL position, kill blocking queries, rebuild standby if needed |
| Disk full runbook | Clean WAL, clean logs, vacuum bloat, add disk |
| Blameless PIR | "What allowed it to break?" not "who broke it?" |
| PIR template | Timeline, root cause, contributing factors, action items |
| MTTD / MTTR | Measure and improve detection and recovery times |

---

**Next:** BUILD 03 - Chaos Engineering for Databases - break things on purpose to find weaknesses before they cause real outages.

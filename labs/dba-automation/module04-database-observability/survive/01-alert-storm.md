# SURVIVE 01: The Alert Storm at 3 AM

**Module 04 - Database Observability**
**Difficulty:** Intermediate
**Time Limit:** 30 minutes

---

## The Scenario

It is 3:07 AM. Your phone explodes with PagerDuty notifications. In the span of 2 minutes, you receive these alerts:

1. **CRITICAL** - `PostgreSQLDiskSpaceCritical` - Free storage below 5% on `db-primary`
2. **CRITICAL** - `PostgreSQLCheckpointsTooFrequent` - Requested checkpoints rate exceeding 0.1/s on `db-primary`
3. **WARNING** - `PostgreSQLHighWALGeneration` - WAL generation rate > 100 MB/s on `db-primary`
4. **CRITICAL** - `PostgreSQLReplicationLag` - Replication lag > 60 seconds on `db-replica-1`
5. **WARNING** - `PostgreSQLHighDeadTuples` - Dead tuple ratio > 15% on `orders` table on `db-primary`
6. **WARNING** - `PostgreSQLAutovacuumBlocked` - Autovacuum cannot run on `db-primary`
7. **CRITICAL** - `PostgreSQLWriteErrors` - Write error rate > 1% on `db-primary`

You are on-call. Your application team is not aware of any deployments or unusual activity.

**Your job:** Triage the root cause, silence cascading alerts, fix the problem, and prevent recurrence.

---

## The Alert Cascade Explained

Before diving into fixes, understand the chain reaction:

```
ROOT CAUSE: Storage filling up
    |
    +-> Cannot write new WAL segments -> Checkpoint frequency increases
    |                                      |
    +-> Autovacuum cannot run            +-> More WAL generated (vicious cycle)
    |   (needs disk space to write)
    |       |
    |       +-> Dead tuples accumulate
    |
    +-> Replica falls behind (WAL backlog)
    |
    +-> Eventually: writes fail (no disk space)
```

**This is a single problem (storage full) manifesting as 7 different alerts.** If you try to fix each alert individually, you will waste time. Find the root cause first.

---

## Your Tasks

### Task 1: Triage - Find the Root Cause (5 minutes)

Do NOT start fixing things yet. Assess first.

1. Check which alerts share the same instance:
   - All alerts reference `db-primary`
   - The replication lag alert references `db-replica-1` but the cause is on the primary

2. Identify the root cause by asking: "Which of these alerts, if fixed, would resolve all the others?"
   - If disk space is restored, WAL can write normally, checkpoints normalize, autovacuum runs, dead tuples get cleaned, replication catches up, writes resume
   - **Root cause: disk space**

3. Verify with a quick check:
   ```bash
   # Check disk usage
   psql -h db-primary -U postgres -c "
     SELECT
       pg_size_pretty(pg_database_size(datname)) AS size,
       datname
     FROM pg_database
     ORDER BY pg_database_size(datname) DESC;
   "
   ```

### Task 2: Silence Non-Root-Cause Alerts (5 minutes)

The cascading alerts are noise. They distract you from fixing the real problem and they will resolve on their own once you fix disk space.

**In Alertmanager (http://localhost:9093):**

1. Click **New Silence**
2. Set matchers:
   - `instance = db-primary`
3. Set duration: 2 hours (gives you time to fix and verify)
4. Add a comment: "Cascading alerts from disk space issue. Investigating root cause."
5. Click **Create**

This silences ALL alerts for `db-primary` for 2 hours. After fixing the root cause, you can remove the silence early.

**Alternative: Silence specific alerts instead of all**

If you want to keep the disk space alert active (to confirm when it resolves), silence only the cascading ones:

```
Matchers:
  alertname =~ "PostgreSQLCheckpointsTooFrequent|PostgreSQLHighWALGeneration|PostgreSQLReplicationLag|PostgreSQLHighDeadTuples|PostgreSQLAutovacuumBlocked"
  instance = db-primary
```

### Task 3: Fix the Root Cause (15 minutes)

**Step 1: Identify what consumed the disk space**

```sql
-- Largest databases
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size
FROM pg_database
ORDER BY pg_database_size(datname) DESC;

-- Largest tables in the main database
SELECT
  schemaname || '.' || relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  n_dead_tup,
  last_autovacuum
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 10;
```

**Step 2: Check for WAL bloat from replication slots**

```sql
-- Replication slots can prevent WAL cleanup
SELECT
  slot_name,
  slot_type,
  active,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

If an inactive replication slot is retaining gigabytes of WAL, drop it:

```sql
-- Only drop if you are sure the slot is not needed
SELECT pg_drop_replication_slot('inactive_slot_name');
```

**Step 3: Emergency space recovery**

```sql
-- Kill any long-running transactions blocking vacuum
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
AND xact_start < now() - interval '30 minutes';

-- Run vacuum on the most bloated tables (frees dead tuple space)
VACUUM VERBOSE orders;

-- If you have temp tables or large log tables, truncate or drop them
-- TRUNCATE releases space immediately, DELETE does not (needs vacuum)
TRUNCATE TABLE application_logs;
```

**Step 4: Verify space is recovering**

```sql
-- Monitor free space
SELECT pg_size_pretty(pg_database_size('production')) AS db_size;
```

**Step 5: Verify cascading issues resolve**

```sql
-- Check replication is catching up
SELECT
  client_addr,
  state,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS lag
FROM pg_stat_replication;

-- Check autovacuum is running again
SELECT
  relname,
  last_autovacuum,
  n_dead_tup
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Task 4: Remove the Silence and Verify (5 minutes)

1. Go to Alertmanager (http://localhost:9093)
2. Click **Silences** tab
3. Find your silence and click **Expire** to remove it
4. Verify alerts are resolving:
   - Disk space alert should have cleared or be improving
   - Replication lag should be decreasing
   - WAL generation should be normalizing
   - Checkpoint frequency should be dropping

---

## Root Cause Analysis

After the incident, fill out this template:

```
Incident: Alert Storm - Disk Space Exhaustion
Severity: Critical
Duration: [TIME FROM FIRST ALERT TO ALL CLEAR]
Impact: Write errors for [DURATION], replication lag peaked at [SECONDS]

Timeline:
- 03:07: First alert (disk space critical)
- 03:07-03:09: 6 cascading alerts fire
- 03:10: On-call DBA acknowledged
- 03:12: Root cause identified (disk space)
- 03:13: Non-root-cause alerts silenced
- 03:15: Started emergency cleanup
- [TIME]: Disk space recovered
- [TIME]: All alerts resolved
- [TIME]: Silence removed

Root Cause: [SPECIFIC - e.g., "Inactive replication slot retained 80 GB of WAL"]

Action Items:
- [ ] Set up CloudWatch/Prometheus alert for disk usage at 70% (warning) and 85% (critical)
- [ ] Add monitoring for inactive replication slots
- [ ] Implement WAL retention limits
- [ ] Add storage autoscaling (if RDS) or automated volume expansion
- [ ] Review alert grouping to reduce storm noise
```

---

## Prevention - Better Alert Design

The alert storm happened because each symptom had its own independent alert. Better design:

**1. Use Alertmanager grouping:**
```yaml
route:
  group_by: ['instance']
  group_wait: 1m
```
This groups all alerts for the same instance into one notification.

**2. Use inhibition rules:**
```yaml
inhibit_rules:
  - source_match:
      alertname: 'PostgreSQLDiskSpaceCritical'
    target_match_re:
      alertname: 'PostgreSQLCheckpointsTooFrequent|PostgreSQLHighWALGeneration|PostgreSQLAutovacuumBlocked'
    equal: ['instance']
```
This says: "If disk space is critical, suppress checkpoint/WAL/vacuum alerts for the same instance because they are symptoms, not causes."

**3. Add predictive alerts:**
```yaml
- alert: PostgreSQLDiskSpacePrediction
  expr: predict_linear(node_filesystem_free_bytes[6h], 24 * 3600) < 0
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Disk will be full in 24 hours on {{ $labels.instance }}"
```

---

## Validation

You have succeeded when:

1. You correctly identified disk space as the root cause (not replication, not vacuum, not checkpoints)
2. You silenced cascading alerts to reduce noise
3. You freed disk space and verified writes resume
4. You can explain why a single problem (disk space) caused 7 different alerts
5. You have documented at least 2 prevention measures (predictive alerting, inhibition rules)

# SURVIVE 01: Migration Lock Timeout

**Module 08: CI/CD for Database Changes**
**Difficulty:** Medium
**Estimated Time:** 30 minutes
**Cluster:** devops-lab-cluster

---

## The Scenario

It is 2:30 PM on a Tuesday. Your CI/CD pipeline deployed a migration to production:

```sql
ALTER TABLE transactions ADD COLUMN status VARCHAR(20) DEFAULT 'pending';
```

The `transactions` table has 500,000 rows. The ALTER TABLE should complete in milliseconds (Aurora/PG 11+ does not rewrite the table for ADD COLUMN with DEFAULT). But it is not completing.

The application team reports:
- All queries on the `transactions` table are hanging
- API response times spiked from 50ms to 30+ seconds
- PgBouncer shows connections piling up in "waiting" state

You check and discover: a long-running analytics query started 2 minutes before the migration. The ALTER TABLE is queued behind it, and every new query is queued behind the ALTER TABLE.

**The lock queue cascade is in effect.**

---

## Setup

Run the inject script to create the scenario:

**On your Mac terminal:**

```bash
export AURORA_ENDPOINT=YOUR_AURORA_ENDPOINT
export DB_USER=postgres
```

```bash
chmod +x inject.sh
```

```bash
./inject.sh
```

The script creates the database, starts a long-running query, and starts a blocked ALTER TABLE.

---

## Your Mission

1. **Identify the blocking query** and its PID
2. **Assess the lock queue** - how many sessions are waiting?
3. **Decide: wait or kill?**
4. **Resolve the situation**
5. **Rewrite the migration** with proper safeguards

---

## Investigation

### Step 1: Check Active Queries

**On your Mac terminal:**

```bash
psql -h YOUR_AURORA_ENDPOINT -U postgres -d survive_lock_timeout
```

```sql
SELECT
    pid,
    state,
    wait_event_type,
    wait_event,
    left(query, 80) AS query,
    now() - query_start AS duration
FROM pg_stat_activity
WHERE datname = 'survive_lock_timeout'
  AND state != 'idle'
ORDER BY query_start;
```

You should see:
- The long-running SELECT (state: `active`, no wait event)
- The ALTER TABLE (state: `active`, wait_event_type: `Lock`)
- Any additional blocked queries (wait_event_type: `Lock`)

### Step 2: Find the Blocking Relationship

```sql
SELECT
    blocked_locks.pid     AS blocked_pid,
    left(blocked_activity.query, 60) AS blocked_query,
    blocking_locks.pid    AS blocking_pid,
    left(blocking_activity.query, 60) AS blocking_query,
    now() - blocking_activity.query_start AS blocking_duration
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity
    ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.relation = blocked_locks.relation
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity
    ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted;
```

This shows which PID is blocking which PID.

### Step 3: Count Waiting Sessions

```sql
SELECT count(*) AS waiting_sessions
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND datname = 'survive_lock_timeout';
```

---

## Decision

### Wait If:
- The blocking query is almost done (check progress)
- The lock queue has fewer than 5 sessions
- It is a maintenance window with no user traffic

### Kill If:
- The lock queue is growing
- Application users are affected
- The blocking query has been running for minutes with no end in sight

**For this scenario: kill it.** The application is degraded and users are seeing timeouts.

---

## Resolution

### Step 4: Cancel the Blocking Query

Find the PID of the long-running SELECT:

```sql
SELECT pid, left(query, 80), now() - query_start AS duration
FROM pg_stat_activity
WHERE datname = 'survive_lock_timeout'
  AND query LIKE '%pg_sleep%'
  AND state = 'active';
```

Note the PID and cancel it:

```sql
SELECT pg_cancel_backend(REPLACE_WITH_PID);
```

- `pg_cancel_backend()` sends SIGINT to the process - cancels the current query but keeps the connection.

If `pg_cancel_backend` does not work within a few seconds, force terminate:

```sql
SELECT pg_terminate_backend(REPLACE_WITH_PID);
```

- `pg_terminate_backend()` sends SIGTERM - kills the entire connection.

### Step 5: Verify the Lock Queue Cleared

```sql
SELECT count(*) AS waiting_sessions
FROM pg_stat_activity
WHERE wait_event_type = 'Lock'
  AND datname = 'survive_lock_timeout';
```

Expected: 0 waiting sessions.

### Step 6: Verify the ALTER TABLE Completed

```sql
\d transactions
```

Check that the `status` column exists. If the ALTER TABLE was also cancelled when you terminated the blocking query, you need to re-run it:

```sql
SET lock_timeout = '5s';
ALTER TABLE transactions ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'pending';
```

### Step 7: Write the Corrected Migration

The original migration had no lock_timeout. The corrected version:

```sql
-- flyway:executeInTransaction=false
SET lock_timeout = '5s';
SET statement_timeout = '300s';

ALTER TABLE transactions ADD COLUMN IF NOT EXISTS status VARCHAR(20) DEFAULT 'pending';
```

The `SET lock_timeout = '5s'` means: if the ALTER TABLE cannot acquire its lock within 5 seconds, it fails immediately instead of blocking the lock queue. You can retry during a quieter period.

```sql
\q
```

---

## Prevention

After resolving the incident, add these safeguards:

1. **Every migration must include `SET lock_timeout = '5s';`** - Add this to your CI lint step
2. **Schedule long-running analytics queries** during off-peak hours, not during deployment windows
3. **Add a pre-migration check** that scans for long-running transactions:

```sql
-- Run before migration: abort if any query has been running > 5 minutes
SELECT count(*) FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes'
  AND datname = current_database();
```

4. **Set `idle_in_transaction_session_timeout`** at the cluster level to automatically kill idle transactions that hold locks

---

## Validation

Run the validation script to confirm the scenario is fully resolved.

```bash
chmod +x validate.sh
```

```bash
./validate.sh
```

All checks should show PASS.

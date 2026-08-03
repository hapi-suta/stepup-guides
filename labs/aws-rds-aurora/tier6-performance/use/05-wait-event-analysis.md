# USE 05 - Diagnose a Performance Issue from Wait Events

**Time:** 45 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 02, 03 complete. Performance Insights enabled.

---

## Objective

Given a database showing a performance issue (described only in vague terms - "the database is slow"), use the wait event analysis methodology to identify the exact root cause and implement a fix without being given any hints about what the problem is.

This exercise trains the end-to-end diagnosis workflow you will use in production incidents.

---

## Setup - Inject a Hidden Problem

The instructor runs this script (or you run it, then wait 5 minutes before looking at the output):

```sql
-- Reset all stats first for a clean baseline
SELECT pg_stat_statements_reset();

-- Setup
DROP TABLE IF EXISTS accounts CASCADE;
DROP TABLE IF EXISTS ledger CASCADE;

CREATE TABLE accounts (
    account_id BIGSERIAL PRIMARY KEY,
    owner TEXT NOT NULL,
    balance NUMERIC(15,2) NOT NULL DEFAULT 0,
    account_type TEXT NOT NULL,
    opened_at DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TABLE ledger (
    entry_id BIGSERIAL PRIMARY KEY,
    account_id BIGINT NOT NULL,
    amount NUMERIC(15,2) NOT NULL,
    entry_type TEXT NOT NULL,
    recorded_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ledger_account ON ledger(account_id);

INSERT INTO accounts (owner, balance, account_type)
SELECT
    'Owner ' || g,
    (random() * 100000)::NUMERIC(15,2),
    CASE (g % 3) WHEN 0 THEN 'checking' WHEN 1 THEN 'savings' ELSE 'investment' END
FROM generate_series(1, 500000) g;

INSERT INTO ledger (account_id, amount, entry_type)
SELECT
    (random() * 500000 + 1)::BIGINT,
    (random() * 1000 - 500)::NUMERIC(15,2),
    CASE (random() * 2)::INT WHEN 0 THEN 'credit' ELSE 'debit' END
FROM generate_series(1, 3000000);

ANALYZE accounts, ledger;
```

Now inject the hidden problem (one of these will be injected - you do not know which):

**Problem A - Lock contention:**

```sql
-- Session A (leave this open for 5 minutes)
BEGIN;
LOCK TABLE accounts IN SHARE MODE;
SELECT pg_sleep(300);
-- Do NOT commit
```

**Problem B - Missing index causing sequential scans:**

```sql
-- Drop a key index silently
DROP INDEX IF EXISTS idx_ledger_account;

-- Run many queries that now do sequential scans
DO $$
BEGIN
    FOR i IN 1..50 LOOP
        PERFORM count(*) FROM ledger WHERE account_id = (random() * 500000)::BIGINT;
        PERFORM pg_sleep(0.1);
    END LOOP;
END $$;
```

**Problem C - work_mem spills:**

```sql
SET work_mem = '1MB';

DO $$
BEGIN
    FOR i IN 1..20 LOOP
        PERFORM account_type, sum(balance), count(*)
        FROM accounts
        GROUP BY account_type
        ORDER BY sum(balance) DESC;
    END LOOP;
END $$;
```

The instructor chooses one problem and injects it. Your job is to diagnose which problem it is and fix it.

---

## Task 1 - Triage: Is This a Database Problem?

First, confirm the database is the bottleneck (not the network or application):

```bash
# Check if queries are completing or hanging
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT now();" 2>&1
```

If this takes more than 2 seconds, the database itself has a problem.

Check the current DB Load in Performance Insights (AWS Console > RDS > Performance Insights > your instance).

Is DB Load:
- Below the vCPU line: database is not saturated, problem is likely application or network
- At or above the vCPU line: database is saturated, proceed with diagnosis

---

## Task 2 - Identify the Dominant Wait Event

In Performance Insights, look at the DB Load graph for the last 15 minutes.

Which color dominates?
- Red (IO) -> storage or cache problem
- Orange/Yellow (Lock/LWLock) -> contention problem
- Blue (CPU) -> compute problem (query inefficiency)
- Purple (Client) -> application is slow to receive results

Record the dominant wait event name from the legend.

Also run this live query:

```sql
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions,
    array_agg(DISTINCT left(query, 60)) AS sample_queries
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
GROUP BY 1, 2
ORDER BY sessions DESC;
```

---

## Task 3 - Narrow Down the Root Cause

Based on the dominant wait event, run the appropriate diagnostic:

**If Lock:relation or Lock:tuple:**

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.state AS blocked_state,
    left(blocked.query, 80) AS blocked_query,
    now() - blocked.state_change AS blocked_for,
    blocking.pid AS blocking_pid,
    left(blocking.query, 80) AS blocking_query,
    now() - blocking.xact_start AS blocking_txn_age
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

**If IO:DataFileRead:**

```sql
-- Check which queries are reading from disk
SELECT
    left(query, 80) AS query_snippet,
    shared_blks_read,
    shared_blks_hit,
    round(shared_blks_read::numeric / nullif(shared_blks_read + shared_blks_hit, 0) * 100, 1) AS disk_read_pct
FROM pg_stat_statements
WHERE shared_blks_read > 0
  AND query NOT LIKE '%pg_stat_statements%'
ORDER BY shared_blks_read DESC
LIMIT 5;
```

**If IO:BufFileRead (sort spills):**

```sql
SELECT
    left(query, 80) AS query_snippet,
    temp_blks_written,
    round(mean_exec_time::numeric, 0) AS avg_ms
FROM pg_stat_statements
WHERE temp_blks_written > 0
ORDER BY temp_blks_written DESC
LIMIT 5;
```

---

## Task 4 - Identify the Specific Query or Session

For lock problems:

```sql
-- Get details about the blocking session
SELECT
    pid,
    usename,
    application_name,
    now() - xact_start AS txn_age,
    now() - state_change AS state_age,
    state,
    left(query, 100) AS current_query
FROM pg_stat_activity
WHERE pid = [BLOCKING_PID];  -- replace with actual PID from Task 3
```

For IO problems:

```sql
-- Get the full query text of the top disk reader
SELECT query
FROM pg_stat_statements
ORDER BY shared_blks_read DESC
LIMIT 1;
```

---

## Task 5 - Implement the Fix

Based on your diagnosis, implement the correct fix:

**Fix for Lock:relation:**

```sql
-- First confirm it is safe to kill (the transaction is not a legitimate long-running job)
SELECT pid, now() - xact_start AS age, query FROM pg_stat_activity WHERE pid = [PID];

-- Then terminate
SELECT pg_terminate_backend([BLOCKING_PID]);
```

**Fix for IO:DataFileRead (missing index):**

```sql
-- Check what indexes exist on the table
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'ledger';

-- Add the missing index
CREATE INDEX CONCURRENTLY idx_ledger_account ON ledger(account_id);

-- Verify the plan now uses the index
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM ledger WHERE account_id = 12345;
```

**Fix for IO:BufFileRead (work_mem):**

```sql
-- Increase work_mem for the session
SET work_mem = '64MB';

-- Or for permanent fix, update the parameter group
-- Then verify the sort no longer spills
EXPLAIN (ANALYZE, BUFFERS)
SELECT account_type, sum(balance), count(*)
FROM accounts
GROUP BY account_type
ORDER BY sum(balance) DESC;
-- Look for: Sort Method: quicksort Memory: XXkB (not "external merge Disk")
```

---

## Task 6 - Verify the Fix

After applying the fix, wait 2 minutes, then:

1. Check Performance Insights: is DB Load back below the vCPU line?
2. Check wait events: did the dominant wait event disappear?
3. Run the pg_stat_statements query from Task 2 again: are the problematic queries gone?

```sql
-- Final state check
SELECT
    wait_event_type,
    wait_event,
    count(*) AS sessions
FROM pg_stat_activity
WHERE state != 'idle'
  AND pid != pg_backend_pid()
GROUP BY 1, 2
ORDER BY sessions DESC;
```

Expected output after fix (yours will differ):
```
 wait_event_type | wait_event | sessions
-----------------+------------+----------
(0 rows)
```

No waiting sessions means the problem is resolved.

---

## Write-Up (Required)

Fill this out as if you were writing an incident post-mortem:

```
INCIDENT SUMMARY
================
Detected at: ___
Duration: ___
Impact: ___

ROOT CAUSE
==========
Wait event observed: ___
Specific query/session: ___
Why it happened: ___

RESOLUTION
==========
Immediate action taken: ___
Permanent fix applied: ___
Time to resolution: ___

PREVENTION
==========
What alarm would have caught this earlier: ___
What process change prevents this: ___
```

---

## Cleanup

```sql
DROP TABLE IF EXISTS ledger;
DROP TABLE IF EXISTS accounts;
SELECT pg_stat_statements_reset();
```

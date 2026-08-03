---
layout: default
title: "Build 02 - Oracle to EPAS Production Scenarios"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 5
locked: "no"
---

# Build 02: Oracle to EPAS Production Scenarios

## What You Are Doing

You are working through 15 production scenarios pulled from real enterprise environments. Each scenario drops you into a situation that an Oracle DBA would handle instinctively - and asks you to solve it the EPAS way.

This is not a mapping worksheet. This is on-call training. By the end, your Oracle reflexes start redirecting to EPAS solutions automatically.

**Mode:** Theory only - no server needed.

**Time:** 90 minutes.

**Prerequisite:** Read Concepts 03 (Oracle to EPAS Bridge) first. Try each scenario without looking at the bridge doc. Then check the answer key.

**How to use this exercise:**
1. Read the scenario context carefully - it sets up WHY this matters
2. Note the Oracle approach - this is what your muscle memory wants to do
3. Write the EPAS approach BEFORE opening the answer key
4. Score yourself honestly. The scenarios you miss are the ones that will bite you in production.

---

## Daily Operations (Scenarios 1-5)

### Scenario 1: The Friday Afternoon Deployment Gone Wrong

**Context:** It is 4:45 PM on Friday. The CardAuth application team just deployed a new release. Within minutes, the application dashboard shows response times spiking from 15ms to 2,300ms. The team lead messages you: "Database is slow, we're getting timeouts, users are seeing failed transactions." You need to find what is happening RIGHT NOW on the database.

**The Oracle approach:**

```sql
SELECT sid, serial#, username, sql_id, event, wait_class,
       seconds_in_wait, status, machine
FROM v$session
WHERE type = 'USER' AND status = 'ACTIVE'
ORDER BY seconds_in_wait DESC;
```

Then you would pull the SQL text from `v$sql` using the `sql_id` and check `v$session_wait` for I/O or lock contention.

**Your EPAS approach:** What queries do you run? What columns matter most? How do you get the actual SQL text?

_______________________________________________

_______________________________________________

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 1</summary>

```sql
SELECT pid, usename, client_addr, state,
       wait_event_type, wait_event,
       now() - query_start AS query_duration,
       left(query, 200) AS query_snippet
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND state = 'active'
ORDER BY query_start;
```

**Key differences from Oracle:**

- `pg_stat_activity` is your `v$session`. It contains everything - session info, current query text, wait events - in one view. No need to join `v$session` to `v$sql`.
- The `query` column contains the FULL SQL text (not a sql_id that you look up elsewhere). Use `left(query, 200)` to truncate for readability.
- The `state` column tells you what the backend is doing: `active` (running a query), `idle` (waiting for next query), `idle in transaction` (transaction open, no query running - this is dangerous).
- `wait_event_type` and `wait_event` replace Oracle's `v$session_wait`. Common values: `Lock` / `relation` (waiting for table lock), `IO` / `DataFileRead` (reading from disk), `LWLock` / `buffer_content` (contention on a shared buffer).
- `now() - query_start` gives you how long the current query has been running. Queries over 30 seconds on an OLTP system are almost always the problem.

**What to look for in this scenario:** After a deployment, the usual suspects are:
1. Missing indexes on new queries (you will see long-running sequential scans)
2. Lock contention from schema migrations (DDL locks blocking DML)
3. Connection pool exhaustion (many backends in `idle in transaction` state, new connections being rejected)

To dig deeper into locks specifically:

```sql
SELECT blocked.pid AS blocked_pid,
       blocked.query AS blocked_query,
       blocking.pid AS blocking_pid,
       blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid
JOIN pg_locks kl ON kl.locktype = bl.locktype
  AND kl.relation = bl.relation AND kl.pid != bl.pid
JOIN pg_stat_activity blocking ON kl.pid = blocking.pid
WHERE NOT bl.granted;
```

</details>

---

### Scenario 2: The Session That Will Not Die

**Context:** The nightly ETL job from the data warehouse team started at 11 PM and was supposed to finish by 1 AM. It is now 6 AM. The ETL session is showing `idle in transaction` status. The application team is reporting that certain tables are "getting slower and slower." You check and find that autovacuum has been unable to clean dead tuples on those tables for the past 7 hours because of this open transaction.

**The Oracle approach:**

```sql
-- Find the session
SELECT sid, serial#, username, status, last_call_et
FROM v$session WHERE username = 'ETL_USER';

-- Kill it
ALTER SYSTEM KILL SESSION '287,45922' IMMEDIATE;

-- If that doesn't work
ALTER SYSTEM DISCONNECT SESSION '287,45922' IMMEDIATE;
```

**Your EPAS approach:** How do you find the session? How do you kill it? What is the difference between a "cancel" and a "terminate"? Which do you use here and why?

_______________________________________________

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 2</summary>

**Step 1: Find the session.**

```sql
SELECT pid, usename, state, query,
       now() - xact_start AS transaction_age,
       now() - state_change AS idle_in_txn_duration
FROM pg_stat_activity
WHERE usename = 'etl_user'
  AND state = 'idle in transaction';
```

The critical column is `xact_start` - this tells you when the transaction began. If `now() - xact_start` returns `07:00:00`, this transaction has been open for 7 hours. Combined with `state = 'idle in transaction'`, this means the session opened a transaction, did some work, and then stopped - without committing or rolling back.

**Step 2: Terminate the session.**

EPAS gives you two options:

```sql
-- Option A: Cancel the current query (gentle)
SELECT pg_cancel_backend(pid);

-- Option B: Terminate the entire connection (forceful)
SELECT pg_terminate_backend(pid);
```

**Which to use here:** `pg_terminate_backend()`. Here is why:

- `pg_cancel_backend()` cancels the currently running query, but the SESSION stays connected and the TRANSACTION stays open. Since this session is `idle in transaction`, there is no running query to cancel - `pg_cancel_backend()` would do nothing useful.
- `pg_terminate_backend()` kills the entire connection. The open transaction is rolled back, locks are released, and autovacuum can immediately begin cleaning the dead tuples.

This is different from Oracle where `KILL SESSION` and `DISCONNECT SESSION` have different escalation behaviors. In EPAS, `pg_terminate_backend()` is decisive and immediate.

**Prevention for next time:**

Set `idle_in_transaction_session_timeout` in `postgresql.conf`:

```sql
ALTER SYSTEM SET idle_in_transaction_session_timeout = '30min';
SELECT pg_reload_conf();
```

This automatically terminates any session that has been `idle in transaction` for more than 30 minutes. Oracle has no equivalent to this - in Oracle, idle sessions do not cause the same damage because UNDO handles versioning separately from the heap.

</details>

---

### Scenario 3: The Config Change That Requires Planning

**Context:** The performance team has completed their analysis and recommends three parameter changes for the CardAuth production EPAS instance:

1. Increase `shared_buffers` from 8 GB to 16 GB
2. Increase `work_mem` from 32 MB to 64 MB
3. Enable `pg_stat_statements` extension

You need to determine: which changes require a restart, which require just a reload, and what is the safest way to make these changes permanent.

**The Oracle approach:**

```sql
-- Check if parameter is dynamic
SELECT name, issys_modifiable FROM v$parameter
WHERE name IN ('sga_target', 'sort_area_size');

-- Make the change
ALTER SYSTEM SET sga_target = 16G SCOPE=BOTH;
```

In Oracle, `SCOPE=BOTH` means the change is applied immediately AND persisted to SPFILE.

**Your EPAS approach:** For each of the three changes, what is the process? Which ones require downtime?

| Change | Requires restart or reload? | How to apply it |
|:-------|:---------------------------|:----------------|
| shared_buffers 8 GB -> 16 GB | ___ | ___ |
| work_mem 32 MB -> 64 MB | ___ | ___ |
| Enable pg_stat_statements | ___ | ___ |

<details markdown="block">
<summary>Answer Key - Scenario 3</summary>

| Change | Restart or Reload? | How to apply |
|:-------|:-------------------|:-------------|
| shared_buffers 8 GB -> 16 GB | **RESTART required** | `ALTER SYSTEM SET shared_buffers = '16GB';` then stop and start the service. Shared memory is allocated at postmaster startup and cannot be resized while running. |
| work_mem 32 MB -> 64 MB | **RELOAD only** | `ALTER SYSTEM SET work_mem = '64MB'; SELECT pg_reload_conf();` Takes effect for new queries immediately. Existing sessions pick it up on their next query. |
| Enable pg_stat_statements | **RESTART required** | Add `pg_stat_statements` to `shared_preload_libraries` in postgresql.conf, then restart. After restart, connect and run `CREATE EXTENSION IF NOT EXISTS pg_stat_statements;` |

**How to check if a parameter requires a restart:**

```sql
SELECT name, context FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'shared_preload_libraries');
```

The `context` column tells you:
- `postmaster` = requires full restart (like shared_buffers, shared_preload_libraries)
- `sighup` = requires reload only (like work_mem, log_min_duration_statement)
- `user` = can be set per-session without any server-level action
- `superuser` = can be set per-session but only by superusers

This is the EPAS equivalent of Oracle's `issys_modifiable` column. The key difference: `ALTER SYSTEM SET` in EPAS always writes to `postgresql.auto.conf` (equivalent to SPFILE) but does NOT apply the change to running sessions for `postmaster`-level parameters. You must restart separately.

There is no `SCOPE=BOTH` equivalent in EPAS. `ALTER SYSTEM SET` always persists the change. `pg_reload_conf()` applies it if the parameter supports it. If the parameter requires a restart, you must do that yourself.

**Operational note:** Since shared_buffers requires a restart, you should batch it with the pg_stat_statements change (which also requires a restart). Apply both, restart once. The work_mem change can be applied separately with just a reload.

</details>

---

### Scenario 4: The Database Size Audit

**Context:** Finance has asked for a quarterly storage report. They need: total database sizes, the top 10 largest tables across all databases, and index-to-table size ratios to identify over-indexed tables. In Oracle, you would pull this from DBA_SEGMENTS and DBA_INDEXES. How do you produce this report in EPAS?

**The Oracle approach:**

```sql
-- Database size
SELECT sum(bytes)/1024/1024/1024 AS size_gb FROM dba_data_files;

-- Largest tables
SELECT owner, segment_name, bytes/1024/1024 AS size_mb
FROM dba_segments WHERE segment_type = 'TABLE'
ORDER BY bytes DESC FETCH FIRST 10 ROWS ONLY;

-- Index-to-table ratio
SELECT i.index_name, i.table_name,
       seg_i.bytes/seg_t.bytes AS idx_to_tbl_ratio
FROM dba_indexes i
JOIN dba_segments seg_i ON seg_i.segment_name = i.index_name
JOIN dba_segments seg_t ON seg_t.segment_name = i.table_name;
```

**Your EPAS approach:** Write the three queries.

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 4</summary>

**Database sizes:**

```sql
SELECT datname,
       pg_size_pretty(pg_database_size(datname)) AS total_size
FROM pg_database
WHERE NOT datistemplate
ORDER BY pg_database_size(datname) DESC;
```

**Top 10 largest tables (within current database):**

```sql
SELECT schemaname, relname AS table_name,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
       pg_size_pretty(pg_relation_size(relid)) AS table_only,
       pg_size_pretty(pg_indexes_size(relid)) AS indexes_only
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 10;
```

**Index-to-table size ratio:**

```sql
SELECT schemaname, relname AS table_name,
       pg_size_pretty(pg_relation_size(relid)) AS table_size,
       pg_size_pretty(pg_indexes_size(relid)) AS index_size,
       CASE WHEN pg_relation_size(relid) > 0
            THEN round(pg_indexes_size(relid)::numeric /
                        pg_relation_size(relid), 2)
            ELSE 0
       END AS index_to_table_ratio
FROM pg_stat_user_tables
WHERE pg_relation_size(relid) > 0
ORDER BY pg_indexes_size(relid)::numeric / NULLIF(pg_relation_size(relid), 0) DESC;
```

**Key differences from Oracle:**

- There is no `DBA_SEGMENTS` in EPAS. Use `pg_relation_size()` (table data only), `pg_indexes_size()` (all indexes on a table), and `pg_total_relation_size()` (table + indexes + TOAST + FSM).
- `pg_total_relation_size()` is what you usually want for reporting - it includes everything associated with the table. `pg_relation_size()` alone can be misleading because it excludes indexes and TOAST data.
- The `pg_size_pretty()` function converts bytes to human-readable format (KB, MB, GB). Use it for reports, but sort by the raw byte values.
- **Cross-database limitation:** Unlike Oracle where you can query DBA_SEGMENTS across all schemas in the database, in EPAS each database is fully isolated. To get the top 10 tables across all databases, you need to connect to each database separately and run the query, or use `dblink` / `postgres_fdw` to query across databases. This is a fundamental architectural difference - Oracle's multi-schema single-database vs. PostgreSQL's multi-database approach.

An index-to-table ratio above 2.0 means your indexes take up more than twice the space of the actual data. This usually indicates over-indexing - common after Oracle migrations where every column had an index "just in case."

</details>

---

### Scenario 5: The Slow Query That Needs a Plan

**Context:** A developer reports that a query against the `merchant_transactions` table takes 45 seconds. It used to take 200ms. They ask you to "check the execution plan." In Oracle, you would use `EXPLAIN PLAN` and `dbms_xplan.display_cursor` to see the actual execution plan with runtime statistics.

**The Oracle approach:**

```sql
-- Get the plan for a specific SQL_ID from cursor cache
SELECT * FROM TABLE(dbms_xplan.display_cursor('abc123def', NULL, 'ALLSTATS LAST'));
```

Or:

```sql
EXPLAIN PLAN FOR
SELECT * FROM merchant_transactions WHERE merchant_id = 42 AND txn_date > SYSDATE - 7;
SELECT * FROM TABLE(dbms_xplan.display);
```

**Your EPAS approach:** How do you get BOTH the estimated plan AND the actual runtime statistics? What is the most useful form of EXPLAIN to run and why?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 5</summary>

**Estimated plan only (safe to run anytime):**

```sql
EXPLAIN
SELECT * FROM merchant_transactions
WHERE merchant_id = 42 AND txn_date > CURRENT_DATE - 7;
```

**Actual plan with runtime statistics (the one you actually want):**

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT * FROM merchant_transactions
WHERE merchant_id = 42 AND txn_date > CURRENT_DATE - 7;
```

**Why `ANALYZE, BUFFERS` matters:**

- `EXPLAIN` alone shows the planner's ESTIMATE - what it thinks will happen. This is like reading the map.
- `EXPLAIN ANALYZE` EXECUTES the query and shows what ACTUALLY happened - actual row counts, actual time, actual loops. This is like driving the route and recording the trip.
- `BUFFERS` adds buffer hit/read counts, showing how much data came from cache vs. disk. This is the critical performance diagnostic.

**Reading the output:**

```
Seq Scan on merchant_transactions  (cost=0.00..458321.00 rows=15234 width=128)
                                   (actual time=0.031..44892.456 rows=14998 loops=1)
  Filter: ((merchant_id = 42) AND (txn_date > '2026-05-31'::date))
  Rows Removed by Filter: 48723156
  Buffers: shared hit=12340 read=382456
```

This tells you:
- The planner estimated 15,234 rows. It got 14,998 - estimate was accurate.
- BUT it is doing a **Seq Scan** (full table scan) instead of an index scan, filtering out 48.7 million rows to find 15,000.
- `shared hit=12340 read=382456` means only 12K pages were in cache, 382K had to be read from disk.

**The fix:** Create a composite index:

```sql
CREATE INDEX idx_merch_txn_date
ON merchant_transactions (merchant_id, txn_date);
```

Then re-run `EXPLAIN ANALYZE` to confirm the planner uses it.

**Critical warning:** `EXPLAIN ANALYZE` actually EXECUTES the query. If the query is an UPDATE or DELETE, it will modify data. Always wrap destructive statements in a transaction:

```sql
BEGIN;
EXPLAIN (ANALYZE, BUFFERS)
UPDATE merchant_transactions SET status = 'void' WHERE txn_id = 12345;
ROLLBACK;  -- undo the change, keep the plan output
```

In Oracle, `EXPLAIN PLAN FOR` never executes the statement - it only generates the plan. In EPAS, `EXPLAIN` (without ANALYZE) also does not execute. But `EXPLAIN ANALYZE` does. This catches Oracle DBAs by surprise.

</details>

---

## Backup and Recovery (Scenarios 6-8)

### Scenario 6: The 3 AM Recovery Call

**Context:** It is 3:12 AM on Saturday. The on-call application engineer calls you: "A deployment script ran a DELETE without a WHERE clause on the `card_profiles` table in production at 2:58 AM. We need that data back." The table had 12 million rows. The backup infrastructure uses Barman with continuous WAL archiving. The last full backup was at 11 PM Friday.

**The Oracle approach:**

```
RMAN> RESTORE DATABASE;
RMAN> RECOVER DATABASE UNTIL TIME "TO_DATE('2026-06-07 02:57:00','YYYY-MM-DD HH24:MI:SS')";
SQL> ALTER DATABASE OPEN RESETLOGS;
```

Or, if you are lucky, use Flashback:
```sql
FLASHBACK TABLE card_profiles TO TIMESTAMP (SYSTIMESTAMP - INTERVAL '15' MINUTE);
```

**Your EPAS approach:** Walk through the full recovery process. You cannot flash back in EPAS - so what do you do? Do you recover the entire production database, or is there a smarter approach?

_______________________________________________

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 6</summary>

**The smart approach: Recover to a separate instance, then extract just the table.**

You do NOT want to point-in-time recover the production database to 2:57 AM because that would lose every legitimate transaction from 2:58 AM to now. Instead:

**Step 1: Recover to a temporary instance on a different server (or different port).**

```bash
# On the recovery server, restore the backup and recover to 2:57 AM
barman recover \
  --target-time "2026-06-07 02:57:00+00" \
  --remote-ssh-command "ssh enterprisedb@recovery-server" \
  cardauth-primary latest /var/lib/edb/as16/data_recovery
```

Barman does the equivalent of Oracle's RESTORE + RECOVER in one command:
1. Copies the base backup to the target directory
2. Copies and replays all archived WAL segments up to the target time
3. Creates a `recovery.signal` file and sets `recovery_target_time` in `postgresql.auto.conf`

**Step 2: Start the recovered instance on a different port.**

```bash
# On the recovery server
/usr/edb/as16/bin/pg_ctl start -D /var/lib/edb/as16/data_recovery \
  -o '-p 5555'
```

**Step 3: Export just the card_profiles table from the recovered instance.**

```bash
/usr/edb/as16/bin/pg_dump -h localhost -p 5555 -U enterprisedb \
  -t card_profiles -Fc cardauth > /tmp/card_profiles_recovery.dump
```

**Step 4: Import the table into production.**

```bash
# First, rename or truncate the (now empty) table in production
# Then restore the data
/usr/edb/as16/bin/pg_restore -h localhost -p 5444 -U enterprisedb \
  -d cardauth --data-only --table=card_profiles /tmp/card_profiles_recovery.dump
```

**Step 5: Shut down and remove the temporary recovery instance.**

**Why this is better than recovering the whole production database:**

- Production stays online throughout the recovery
- No legitimate transactions are lost
- You recover just the data you need
- Total downtime: zero (for the production instance)

**EPAS does not have Flashback.** There is no equivalent to Oracle's `FLASHBACK TABLE`. The closest alternative is if you have a logical replication subscriber with a time delay (e.g., a 1-hour delayed standby), but that requires advance planning.

**Prevention for next time:** Use `pg_stat_statements` to identify destructive queries and consider implementing a trigger or pgAudit to log all DELETE and TRUNCATE operations. Also consider `statement_timeout` limits on production roles to prevent queries that affect millions of rows.

</details>

---

### Scenario 7: The Backup Verification Drill

**Context:** The security team requires monthly backup verification. You must prove that you can restore the most recent backup, that the data is consistent, and that the restore process is documented. In Oracle, you would run `RMAN VALIDATE` and schedule periodic restore tests. What does this process look like with Barman?

**The Oracle approach:**

```
RMAN> VALIDATE BACKUPSET 1234;
RMAN> RESTORE DATABASE VALIDATE;
```

**Your EPAS approach:** What Barman commands do you run for the monthly verification? What do you check after a test restore?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 7</summary>

**Monthly backup verification checklist:**

**Step 1: Check backup catalog health.**

```bash
barman check cardauth-primary
```

This validates: SSH connectivity to the EPAS server, PostgreSQL connectivity, WAL archiving status, backup retention compliance, disk space on the Barman server, replication slot health, and more. If any check shows `FAILED`, investigate before proceeding.

**Step 2: List available backups and verify the most recent one.**

```bash
barman list-backup cardauth-primary
barman show-backup cardauth-primary latest
```

`show-backup` displays the backup's begin/end WAL positions, begin/end timestamps, size, and status. Confirm the backup completed successfully.

**Step 3: Verify backup integrity.**

```bash
barman verify-backup cardauth-primary latest
```

This checks that all data files in the backup match their expected checksums. Equivalent to Oracle's `VALIDATE BACKUPSET`. If data page checksums are enabled on the EPAS instance (they should be), Barman also verifies those.

**Step 4: Test a full restore to a separate location.**

```bash
barman recover \
  --target-time "$(date -u '+%Y-%m-%d %H:%M:%S+00')" \
  cardauth-primary latest /var/lib/edb/as16/data_verify
```

**Step 5: Start the recovered instance and verify data.**

```bash
/usr/edb/as16/bin/pg_ctl start -D /var/lib/edb/as16/data_verify -o '-p 5556'

# Run consistency checks
/usr/edb/as16/bin/edb-psql -p 5556 -U enterprisedb -d cardauth -c "
  SELECT count(*) FROM card_profiles;
  SELECT count(*) FROM merchant_transactions;
  SELECT max(txn_date) FROM merchant_transactions;
"
```

Verify that the row counts match production (within the window of the backup) and that the most recent transaction timestamp matches what you expect.

**Step 6: Check for corruption.**

```bash
# If amcheck extension is installed
/usr/edb/as16/bin/edb-psql -p 5556 -U enterprisedb -d cardauth -c "
  CREATE EXTENSION IF NOT EXISTS amcheck;
  SELECT bt_index_check(c.oid)
  FROM pg_index i
  JOIN pg_class c ON i.indexrelid = c.oid
  WHERE c.relkind = 'i';
"
```

This validates every B-tree index for structural consistency. Oracle has `ANALYZE INDEX ... VALIDATE STRUCTURE` - `amcheck` is the EPAS equivalent.

**Step 7: Clean up and document.**

```bash
/usr/edb/as16/bin/pg_ctl stop -D /var/lib/edb/as16/data_verify
rm -rf /var/lib/edb/as16/data_verify
```

Document the results: backup ID, restore duration, row counts verified, any issues found. This is your audit trail for the security team.

</details>

---

### Scenario 8: The Archiver Alert

**Context:** Your monitoring system fires an alert: "WAL archiving has been failing for the past 45 minutes on cardauth-primary." The `pg_stat_archiver` view shows `failed_count = 147` and climbing. If archiving stays broken, pg_wal will grow until the disk fills up, and the database will crash. You need to diagnose and fix this immediately.

**The Oracle approach:**

```sql
SELECT dest_id, status, error FROM v$archive_dest WHERE status = 'ERROR';
-- Then check alert.log for ORA-16014 / ORA-00257 errors
```

**Your EPAS approach:** How do you diagnose the archiver failure? Where do you look for error messages? What are the three most common causes?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 8</summary>

**Step 1: Check what the archiver is trying to do.**

```sql
SELECT archived_count, failed_count,
       last_archived_wal, last_archived_time,
       last_failed_wal, last_failed_time,
       stats_reset
FROM pg_stat_archiver;
```

This tells you: how many WAL segments have been archived successfully, how many have failed, the name of the last successful and last failed WAL segment, and when the failures started.

**Step 2: Check the archive_command setting.**

```sql
SHOW archive_command;
```

Common configurations:
- `barman-wal-archive primary-barman-server cardauth-primary %p` (Barman WAL archive)
- `cp %p /mnt/archive/%f` (simple copy)
- `aws s3 cp %p s3://bucket/wal/%f` (S3 archive)

**Step 3: Check the server log for error details.**

```bash
# Check the EPAS log files
tail -100 /var/lib/edb/as16/data/log/edb-$(date +%Y-%m-%d)*.log | grep -i "archive\|ERROR"
```

The server log contains the exact error message from the `archive_command` execution. This is equivalent to Oracle's alert.log.

**The three most common causes:**

**Cause 1: Backup server unreachable.** If using Barman, the Barman server might be down, the SSH key might have expired, or a firewall rule changed. The archive_command tries to ship WAL via SSH and fails. Fix: verify SSH connectivity, restart Barman if needed, check network/firewall.

**Cause 2: Disk full on the archive destination.** The backup server or S3 bucket has no space. The archive_command fails because it cannot write the WAL file. Fix: free space on the destination, add storage, or purge old archives with `barman delete`.

**Cause 3: Permission change.** Someone changed file permissions on the archive directory, or the IAM role for S3 was modified, or the SSH key was rotated without updating the EPAS server. Fix: verify the enterprisedb OS user can write to the destination.

**Immediate mitigation while you diagnose:**

If you cannot fix the root cause quickly, temporarily switch to a local archive to prevent pg_wal from filling the disk:

```sql
ALTER SYSTEM SET archive_command = 'cp %p /var/lib/edb/archive_emergency/%f';
SELECT pg_reload_conf();
```

This buys you time. The WAL segments will be copied locally instead of failing. Once the real archive destination is fixed, switch back and manually ship the emergency-archived segments to the backup server.

**Key difference from Oracle:** In Oracle, archive destinations are managed by the database with automatic retry and multiple destination support. In EPAS, `archive_command` is a simple shell command that either succeeds (exit 0) or fails (non-zero exit). There is no built-in retry with backoff, no multiple destinations. The archiver just keeps retrying the same failed segment until the command succeeds. This simplicity means you need external monitoring to catch failures quickly.

</details>

---

## High Availability (Scenarios 9-11)

### Scenario 9: Is This Server the Primary or the Standby?

**Context:** You are paged in the middle of the night. The alert says "high CPU on cardauth-db-02." You SSH into the server but you are not sure if this is the primary or the standby. You need to know before you take any action - running VACUUM on a standby is pointless, and accidentally promoting a healthy standby would be catastrophic.

**The Oracle approach:**

```sql
SELECT database_role, open_mode, switchover_status FROM v$database;
-- Returns: PRIMARY / PHYSICAL STANDBY
```

**Your EPAS approach:** What is the single most reliable way to determine if you are on a primary or standby? Are there other ways, and why are they less reliable?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 9</summary>

**The one reliable method:**

```sql
SELECT pg_is_in_recovery();
```

- Returns `false` = this is the **primary** (not in recovery mode, accepting writes)
- Returns `true` = this is a **standby** (in recovery mode, replaying WAL from primary)

This function checks the actual internal state of the database process. It does not depend on configuration files, hostnames, AWS tags, or anything external.

**Less reliable alternatives and why they fail:**

- **Checking the hostname** (e.g., "db-02 must be the standby"): Hostnames can be wrong after a failover. If EFM promoted db-02 to primary last month and nobody updated the hostname, the hostname lies.
- **Checking for `standby.signal` file**: This file exists on standbys, but if recovery is complete (e.g., after promotion), it gets removed. It tells you what the server WAS, not what it IS.
- **Checking AWS tags**: Tags require external API calls and can be stale. If EFM promoted the standby automatically at 2 AM, the AWS tags still say "standby" until someone updates them.
- **Checking `pg_stat_replication`**: If you see rows in `pg_stat_replication`, this server is probably a primary (it is sending WAL to replicas). But a primary with no standbys would show zero rows, and you might mistakenly think it is a standby.
- **Trying to write**: Running `CREATE TEMP TABLE test()` will fail on a standby with "cannot execute CREATE TABLE in a read-only transaction." This works but is crude - `pg_is_in_recovery()` is cleaner.

**Always use `pg_is_in_recovery()`.** Make it the first thing you run when you SSH into any EPAS server. It takes milliseconds and tells you the truth.

</details>

---

### Scenario 10: The Replication Lag Emergency

**Context:** Your monitoring dashboard shows replication lag on the CardAuth standby has jumped from the normal 50ms to 47 minutes and climbing. The standby is used for read-only reporting queries. The reporting team is seeing stale data, and if the primary fails right now, promoting the standby would mean losing 47 minutes of transactions. You need to diagnose why the standby fell behind and decide what action to take.

**The Oracle approach:**

```sql
-- On Data Guard primary
SELECT name, value, time_computed
FROM v$dataguard_stats WHERE name = 'apply lag';

-- Check MRP status
SELECT process, status, sequence#, block#
FROM v$managed_standby WHERE process = 'MRP0';
```

**Your EPAS approach:** How do you measure the exact lag? What are the most common causes? How do you decide between "wait for it to catch up" and "rebuild the standby from scratch"?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 10</summary>

**Measuring lag - run this on the PRIMARY:**

```sql
SELECT client_addr, application_name, state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS byte_lag,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;
```

Key columns:
- `sent_lsn` vs. `replay_lsn`: the gap between what the primary sent and what the standby has applied. `byte_lag` shows this in bytes.
- `replay_lag`: time-based lag measurement. "47 minutes" means the standby is replaying WAL from 47 minutes ago.
- `state`: should be `streaming`. If it shows `catchup`, the standby is behind and actively catching up. If it shows `backup`, something is wrong.

**Measuring lag - run this on the STANDBY:**

```sql
SELECT now() - pg_last_xact_replay_timestamp() AS replay_lag;
```

This shows the wall-clock time since the last replayed transaction. Simple and effective.

**The four most common causes of replication lag:**

**Cause 1: Heavy query on the standby is blocking replay.** If `hot_standby_feedback` is enabled and a long-running reporting query holds a snapshot, WAL replay pauses to avoid conflicting with the query. Check `pg_stat_activity` on the standby for long-running queries. Solution: cancel the query with `pg_cancel_backend()` or set `max_standby_streaming_delay` to limit how long replay waits.

**Cause 2: Standby I/O is saturated.** The standby disk cannot write data pages fast enough to keep up with WAL replay. Check `iostat` or `iotop` on the standby. This often happens when the standby has slower storage than the primary (e.g., primary on NVMe, standby on EBS gp2). Solution: upgrade standby storage.

**Cause 3: Network bottleneck between primary and standby.** The WAL stream is not arriving fast enough. Check network throughput and latency. Solution: check for network saturation, consider WAL compression (`wal_compression = on` on the primary).

**Cause 4: Standby was paused.** Someone ran `SELECT pg_wal_replay_pause();` on the standby (common during backups or maintenance) and forgot to resume. Check with `SELECT pg_is_wal_replay_paused();` on the standby. Solution: `SELECT pg_wal_replay_resume();`

**Decision framework: Wait vs. Rebuild?**

- If the lag is **growing** and you identified a fixable cause (long query, paused replay): fix the cause, let the standby catch up. It will process WAL faster than real-time and close the gap.
- If the lag is **growing** and the cause is fundamental (slow storage, undersized standby): you need infrastructure changes. The standby will never catch up without them.
- If the standby **lost its replication slot** (primary recycled WAL that the standby still needs): the standby will show errors like "requested WAL segment has already been removed." You must rebuild: `pg_basebackup` from the primary to create a fresh standby.
- Rule of thumb: if the standby is less than `max_wal_size * 3` behind in bytes, it will likely catch up. If it is further behind than your WAL retention, rebuild.

</details>

---

### Scenario 11: The Planned Switchover

**Context:** The infrastructure team needs to perform hardware maintenance on the CardAuth primary server this weekend. You need to do a graceful switchover - promote the standby to primary, and demote the old primary to standby - with minimal downtime. The application uses PgBouncer for connection pooling, and EFM manages the cluster.

**The Oracle approach:**

```
-- Check readiness
DGMGRL> VALIDATE DATABASE 'cardauth_standby';

-- Execute switchover
DGMGRL> SWITCHOVER TO 'cardauth_standby';

-- After maintenance, switchover back
DGMGRL> SWITCHOVER TO 'cardauth_primary';
```

Data Guard handles the demotion and promotion automatically.

**Your EPAS approach:** What is the step-by-step process for a planned switchover with EFM? What happens to client connections? What is the expected downtime?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 11</summary>

**Pre-switchover checklist:**

1. Verify replication is caught up (lag should be zero or near-zero):
```sql
-- On primary
SELECT client_addr, replay_lag FROM pg_stat_replication;
```

2. Verify EFM cluster health:
```bash
/usr/edb/efm-4.8/bin/efm cluster-status cardauth
```
All nodes should show `UP`. The primary, standby, and witness should all be visible.

3. Notify the application team. Even with PgBouncer, there will be a brief connection disruption.

**The switchover command:**

```bash
# Run from any EFM node (primary, standby, or witness)
/usr/edb/efm-4.8/bin/efm promote cardauth -switchover
```

**What EFM does behind the scenes:**

1. Stops the old primary's EPAS instance gracefully (clean shutdown, checkpoint)
2. Waits for the standby to replay all remaining WAL (ensures zero data loss)
3. Promotes the standby to primary (`pg_promote()` internally)
4. Reconfigures the old primary as a standby (creates `standby.signal`, sets `primary_conninfo`)
5. Starts the old primary as a new standby
6. Updates the cluster Virtual IP (VIP) or calls the hook script to update PgBouncer/DNS

**What happens to client connections:**

- PgBouncer connections to the old primary are dropped
- If PgBouncer is configured to follow the EFM VIP (or if EFM calls a hook script to update PgBouncer's config), new connections automatically route to the new primary
- Applications experience a brief disconnection (typically 10-30 seconds for the promotion itself, plus whatever time PgBouncer takes to reconnect)
- Applications with retry logic reconnect automatically. Applications without retry logic need manual intervention.

**Expected downtime:** 10-30 seconds for the database switchover. Total application impact depends on how quickly PgBouncer/DNS updates propagate.

**After maintenance - switching back (if desired):**

The same process in reverse. The old primary (now standby) has been replicating from the new primary. Run `efm promote cardauth -switchover` again to swap roles back.

**Key difference from Oracle Data Guard:**

Oracle DG Broker's switchover is tightly integrated - it manages the entire process including role transitions, redo transport, and database opening. EFM is simpler - it promotes and configures, but the application routing (VIP, DNS, PgBouncer) requires either EFM hook scripts or manual configuration. This is less automated than Oracle DG but gives you more control over the routing layer.

**Important:** Unlike Oracle where `SWITCHOVER` implies zero-data-loss, in EPAS you must verify replication lag is zero BEFORE running the switchover. EFM does wait for replay to complete, but if the standby is hours behind, the switchover will hang for hours while it catches up. Always verify lag first.

</details>

---

## Performance and Troubleshooting (Scenarios 12-15)

### Scenario 12: The Table That Keeps Growing

**Context:** The `audit_events` table in the CardAuth database was 50 GB six months ago. It is now 180 GB, even though you have a nightly purge job that deletes records older than 90 days. The DELETE job runs successfully every night and removes about 2 million rows. But the table size on disk never shrinks. The application team is complaining about slow full table scans on this table.

**The Oracle approach:**

Oracle automatically manages high-water mark and segment space. If needed:
```sql
ALTER TABLE audit_events ENABLE ROW MOVEMENT;
ALTER TABLE audit_events SHRINK SPACE CASCADE;
```

Or use online table redefinition to reorganize.

**Your EPAS approach:** Why is the table not shrinking? What is the EPAS concept behind this? What are your options to reclaim the space, and which is safest for production?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 12</summary>

**Why the table is not shrinking: MVCC and dead tuples.**

This is the single biggest architectural difference between Oracle and EPAS for DBA operations.

In Oracle, when you DELETE a row, the row is removed and the space is reusable (after UNDO processing). In EPAS, when you DELETE a row, the row is NOT removed. Instead, it is marked as "dead" (the `xmax` field is set to the deleting transaction's XID). The dead row stays in the data file. This is how EPAS implements MVCC (Multi-Version Concurrency Control) - other transactions that started before the DELETE can still see the old row.

VACUUM removes dead tuples and marks the space as reusable for future INSERTs. But `VACUUM` does NOT shrink the file on disk. It only makes space available within the existing file. The file size never decreases from regular VACUUM.

Your nightly DELETE removes 2 million rows. VACUUM (or autovacuum) cleans up the dead tuples. But if 2 million new rows are inserted AND 2 million old rows are deleted every day, the table grows because:
1. New rows may not fit in the holes left by deleted rows (especially if row sizes differ)
2. If autovacuum runs AFTER the inserts (but before it can clean up), new pages are allocated
3. Over time, the table has low "fill factor" - lots of partially-filled pages

**Your options to reclaim space:**

**Option 1: `VACUUM FULL audit_events`**

```sql
VACUUM FULL audit_events;
```

This rewrites the entire table to a new file, compacting it. The 180 GB table might shrink to 60 GB. BUT: it takes an **ACCESS EXCLUSIVE lock** on the table for the entire duration. On a 180 GB table, this could take 30-60 minutes. During that time, NO queries can read or write to the table. For a production system, this is usually unacceptable.

**Option 2: `pg_repack` extension (recommended for production)**

```bash
pg_repack -d cardauth -t audit_events
```

`pg_repack` does the same thing as `VACUUM FULL` (rewrites the table) but WITHOUT holding an exclusive lock for the entire operation. It only holds a brief lock at the beginning and end. This is the production-safe option. It is equivalent to Oracle's online table redefinition.

**Option 3: Table partitioning (the correct long-term fix)**

Instead of DELETE + VACUUM, partition the `audit_events` table by month:

```sql
CREATE TABLE audit_events (
    event_id bigint,
    event_time timestamptz,
    ...
) PARTITION BY RANGE (event_time);

CREATE TABLE audit_events_2026_04 PARTITION OF audit_events
    FOR VALUES FROM ('2026-04-01') TO ('2026-05-01');
-- etc.
```

Then instead of `DELETE WHERE event_time < now() - interval '90 days'`, you simply:

```sql
DROP TABLE audit_events_2026_03;
```

`DROP TABLE` is instant. No dead tuples. No bloat. No VACUUM needed. This is the same pattern Oracle DBAs use with partitioned tables and `ALTER TABLE ... DROP PARTITION` - and it is just as effective in EPAS.

**The lesson:** In EPAS, high-volume DELETE is expensive. Design for partition drops whenever possible.

</details>

---

### Scenario 13: The Missing Statistics Problem

**Context:** After a large data migration into the `merchant_profiles` table (12 million rows loaded via `COPY`), all queries against the table are using sequential scans instead of index scans. The indexes exist and are valid. The explain plans show the planner estimating 1 row for a query that returns 50,000 rows. Something is wrong with the planner's information.

**The Oracle approach:**

```sql
-- Oracle autogathers stats, but after bulk loads:
EXEC DBMS_STATS.GATHER_TABLE_STATS('CARDAUTH', 'MERCHANT_PROFILES',
     estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
     cascade => TRUE);
```

**Your EPAS approach:** What happened? Why is the planner wrong? What do you run, and how do you verify it worked?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 13</summary>

**What happened:** The `COPY` command loaded 12 million rows but did NOT update the table statistics in `pg_statistic`. The planner still has the old statistics (from before the load, when the table had fewer rows or different data distribution). It thinks the table has far fewer rows than it actually does, so it underestimates selectivity and chooses sequential scans.

Autovacuum will eventually run `ANALYZE` on the table (because it detects the large number of inserts), but it may take minutes to hours depending on `autovacuum_analyze_threshold` and `autovacuum_analyze_scale_factor` settings.

**The fix:**

```sql
ANALYZE merchant_profiles;
```

This is the EPAS equivalent of `DBMS_STATS.GATHER_TABLE_STATS`. It samples the table, computes column statistics (most common values, histograms, null fractions, distinct value counts), and stores them in `pg_statistic`. The planner uses these statistics for every subsequent query plan.

To analyze with verbose output (shows what it is doing):

```sql
ANALYZE VERBOSE merchant_profiles;
```

**How to verify it worked:**

```sql
-- Check that stats are current
SELECT schemaname, relname, n_live_tup, last_analyze, last_autoanalyze
FROM pg_stat_user_tables
WHERE relname = 'merchant_profiles';
```

`n_live_tup` should show approximately 12 million. `last_analyze` should show the current timestamp.

Then re-run the problematic query with `EXPLAIN`:

```sql
EXPLAIN SELECT * FROM merchant_profiles WHERE region_code = 'US-EAST';
```

The `rows` estimate should now be close to the actual count. The planner should switch from Seq Scan to Index Scan (assuming an index on `region_code` exists and the selectivity justifies it).

**Best practice for bulk loads:**

Always run `ANALYZE` immediately after any bulk data operation (COPY, INSERT ... SELECT, large UPDATE). Do not wait for autovacuum.

```sql
COPY merchant_profiles FROM '/tmp/merchants.csv' CSV;
ANALYZE merchant_profiles;
```

In Oracle, `DBMS_STATS.GATHER_TABLE_STATS` with `cascade => TRUE` also gathers index statistics. In EPAS, `ANALYZE tablename` gathers statistics for the table AND all its indexes in one command. The `cascade` behavior is the default.

</details>

---

### Scenario 14: The Lock Chain Investigation

**Context:** At 10:15 AM on Monday, the CardAuth application starts timing out. You check `pg_stat_activity` and see 45 backends in `active` state, all waiting on locks. The wait_event shows `Lock` / `transactionid`. This is a lock chain - one session is blocking another, which is blocking another, and so on. You need to find the ROOT blocker - the one session at the top of the chain that is holding the lock everyone else is waiting for.

**The Oracle approach:**

```sql
-- Find the blocking tree
SELECT level, sid, serial#, blocking_session, sql_id, event
FROM v$session
START WITH blocking_session IS NULL AND sid IN (
    SELECT blocking_session FROM v$session WHERE blocking_session IS NOT NULL
)
CONNECT BY PRIOR sid = blocking_session;
```

Oracle's hierarchical query with `CONNECT BY` makes this straightforward.

**Your EPAS approach:** How do you find the root blocker? EPAS does not have `CONNECT BY` in `pg_stat_activity` - so what is the equivalent approach?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 14</summary>

**Step 1: Find who is blocking whom.**

```sql
SELECT
    blocked.pid AS blocked_pid,
    blocked.usename AS blocked_user,
    blocked.state AS blocked_state,
    left(blocked.query, 80) AS blocked_query,
    now() - blocked.query_start AS blocked_duration,
    blocking.pid AS blocking_pid,
    blocking.usename AS blocking_user,
    blocking.state AS blocking_state,
    left(blocking.query, 80) AS blocking_query,
    now() - blocking.xact_start AS blocking_txn_age
FROM pg_stat_activity blocked
JOIN pg_locks bl ON bl.pid = blocked.pid AND NOT bl.granted
JOIN pg_locks kl ON kl.locktype = bl.locktype
    AND kl.database IS NOT DISTINCT FROM bl.database
    AND kl.relation IS NOT DISTINCT FROM bl.relation
    AND kl.page IS NOT DISTINCT FROM bl.page
    AND kl.tuple IS NOT DISTINCT FROM bl.tuple
    AND kl.virtualxid IS NOT DISTINCT FROM bl.virtualxid
    AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
    AND kl.classid IS NOT DISTINCT FROM bl.classid
    AND kl.objid IS NOT DISTINCT FROM bl.objid
    AND kl.objsubid IS NOT DISTINCT FROM bl.objsubid
    AND kl.pid != bl.pid
    AND kl.granted
JOIN pg_stat_activity blocking ON kl.pid = blocking.pid
ORDER BY blocking_txn_age DESC;
```

**Step 2: Find the ROOT blocker.**

The root blocker is the `blocking_pid` that does NOT appear as a `blocked_pid` in the results. Alternatively, use a recursive CTE (the EPAS equivalent of Oracle's `CONNECT BY`):

```sql
WITH RECURSIVE lock_chain AS (
    -- Base case: sessions that are blocking others but not blocked themselves
    SELECT blocking.pid, blocking.usename, blocking.state, blocking.query,
           blocking.xact_start, 0 AS depth,
           blocking.pid::text AS chain
    FROM pg_stat_activity blocking
    WHERE blocking.pid IN (
        SELECT kl.pid FROM pg_locks kl
        JOIN pg_locks bl ON kl.locktype = bl.locktype
            AND kl.database IS NOT DISTINCT FROM bl.database
            AND kl.relation IS NOT DISTINCT FROM bl.relation
            AND kl.transactionid IS NOT DISTINCT FROM bl.transactionid
            AND kl.pid != bl.pid AND kl.granted AND NOT bl.granted
    )
    AND blocking.pid NOT IN (
        SELECT bl.pid FROM pg_locks bl WHERE NOT bl.granted
    )

    UNION ALL

    -- Recursive case: sessions blocked by the previous level
    SELECT blocked.pid, blocked.usename, blocked.state, blocked.query,
           blocked.xact_start, lc.depth + 1,
           lc.chain || ' -> ' || blocked.pid::text
    FROM lock_chain lc
    JOIN pg_locks kl ON kl.pid = lc.pid AND kl.granted
    JOIN pg_locks bl ON bl.locktype = kl.locktype
        AND bl.database IS NOT DISTINCT FROM kl.database
        AND bl.relation IS NOT DISTINCT FROM kl.relation
        AND bl.transactionid IS NOT DISTINCT FROM kl.transactionid
        AND bl.pid != kl.pid AND NOT bl.granted
    JOIN pg_stat_activity blocked ON bl.pid = blocked.pid
)
SELECT pid, usename, state, left(query, 60) AS query,
       now() - xact_start AS txn_age, depth, chain
FROM lock_chain
ORDER BY chain, depth;
```

**What the root blocker typically looks like:**

The root blocker almost always has `state = 'idle in transaction'`. It grabbed a lock (via UPDATE, DELETE, or explicit LOCK TABLE), then stopped doing anything - but its transaction is still open, so the lock is held. Meanwhile, 45 other backends are queued behind it.

**Step 3: Kill the root blocker.**

```sql
SELECT pg_terminate_backend(<root_blocker_pid>);
```

All 45 blocked sessions will immediately unblock and proceed. The terminated session's transaction is rolled back.

**Prevention:**

```sql
-- Kill idle-in-transaction sessions after 5 minutes
ALTER SYSTEM SET idle_in_transaction_session_timeout = '5min';

-- Kill individual queries that run longer than 30 seconds
ALTER SYSTEM SET statement_timeout = '30s';

SELECT pg_reload_conf();
```

**Note on EPAS vs. Oracle:** EPAS supports `CONNECT BY` in EDB-SPL mode for regular data queries, but `pg_stat_activity` and `pg_locks` are system views that work best with standard SQL. The `WITH RECURSIVE` CTE is the standard PostgreSQL approach and works identically in EPAS.

**Practical shortcut:** In a real emergency at 10:15 AM, skip the fancy recursive CTE. Run the simple blocking query from Step 1, look for the `blocking_pid` with the oldest `blocking_txn_age` and `state = 'idle in transaction'`, and terminate it. You can investigate the root cause after the fire is out.

</details>

---

### Scenario 15: The XID Wraparound Countdown

**Context:** Your monitoring system fires a critical alert: "XID age on table `txn_log` in database `cardauth` has reached 1.8 billion. Wraparound shutdown in approximately 350 million transactions." At the current transaction rate of 1,200 TPS, that is roughly 3.4 days before the database SHUTS ITSELF DOWN and refuses all write operations. This is not a warning - this is a countdown to a hard outage.

**The Oracle approach:**

Oracle does not have this problem. Oracle uses SCN (System Change Number) which is a 48-bit counter with automatic reset capabilities. XID wraparound is a PostgreSQL/EPAS-specific concept with no Oracle equivalent.

**Your EPAS approach:** What is XID wraparound? Why does it happen? What is the emergency procedure to prevent the shutdown? What is the long-term fix?

_______________________________________________

<details markdown="block">
<summary>Answer Key - Scenario 15</summary>

**What is XID wraparound?**

PostgreSQL/EPAS uses 32-bit transaction IDs (XIDs). Every INSERT, UPDATE, or DELETE consumes one XID. The total XID space is ~4.3 billion, but because PostgreSQL uses modular arithmetic to compare XIDs, only ~2.1 billion XIDs can be "in the past" at any time. When a table has tuples with XIDs that are more than 2.1 billion transactions old, those tuples would "wrap around" and appear to be from the FUTURE - making them invisible to all transactions, effectively losing data.

To prevent this, PostgreSQL has a safety mechanism: VACUUM FREEZE. It rewrites old XIDs to a special "frozen" XID that is always considered "in the past." If vacuum cannot freeze old enough tuples (because something blocks it), the database eventually refuses all new writes to prevent data loss.

**Why it happened here:**

The most common causes are:
1. **Long-running transactions preventing VACUUM from freezing tuples.** A session that has been idle-in-transaction for days holds a snapshot that prevents VACUUM from marking any tuple created after that snapshot as frozen.
2. **Autovacuum disabled or throttled too aggressively.** If `autovacuum_freeze_max_age` is not reached, autovacuum may not prioritize freezing.
3. **VACUUM running but taking too long on a massive table.** If the table has 500 million rows and VACUUM processes 10 million rows/hour, it takes 50 hours - during which the XID counter keeps advancing.

**Emergency procedure (you have 3.4 days):**

**Step 1: Kill any long-running transactions that might block VACUUM.**

```sql
SELECT pid, usename, state,
       now() - xact_start AS txn_age, query
FROM pg_stat_activity
WHERE state IN ('idle in transaction', 'active')
  AND xact_start < now() - interval '1 hour'
ORDER BY xact_start;

-- Kill them
SELECT pg_terminate_backend(pid) FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND xact_start < now() - interval '1 hour';
```

**Step 2: Run manual aggressive VACUUM FREEZE on the offending table.**

```sql
-- Increase maintenance_work_mem for this session to speed up vacuum
SET maintenance_work_mem = '2GB';

-- Run vacuum freeze - this rewrites old XIDs to frozen
VACUUM (FREEZE, VERBOSE) txn_log;
```

This can take hours on a large table. Monitor progress:

```sql
SELECT relname,
       pg_size_pretty(pg_total_relation_size(oid)) AS size,
       age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relname = 'txn_log';
```

The `xid_age` should decrease as VACUUM FREEZE progresses.

**Step 3: Check all other tables in the database.**

```sql
SELECT relname, age(relfrozenxid) AS xid_age,
       pg_size_pretty(pg_total_relation_size(oid)) AS size
FROM pg_class
WHERE relkind = 'r'
ORDER BY age(relfrozenxid) DESC
LIMIT 20;
```

Any table with `xid_age` above 1 billion needs attention.

**Step 4: Check all databases.**

```sql
SELECT datname, age(datfrozenxid) AS db_xid_age
FROM pg_database
ORDER BY age(datfrozenxid) DESC;
```

The database-level frozen XID is the oldest across all tables. Even template databases can block wraparound.

**Long-term prevention:**

1. **Monitor XID age continuously.** Alert at 500 million (warning) and 1 billion (critical). Never let it reach 1.5 billion.
2. **Tune autovacuum for large tables.** Lower `autovacuum_freeze_max_age` from default 200 million to 100 million for high-churn tables.
3. **Set `idle_in_transaction_session_timeout`** to prevent long-running transactions.
4. **Consider table partitioning** for high-volume tables like `txn_log`. Dropping old partitions removes their XIDs entirely - no VACUUM needed.

**The hard truth for Oracle DBAs:** XID wraparound does not exist in Oracle, and there is no way to eliminate the risk in EPAS - only manage it. This is the #1 PostgreSQL failure mode that catches Oracle DBAs off-guard. Build monitoring for it from day one.

</details>

---

## Scoring

Count how many scenarios you answered correctly (or close to correctly) WITHOUT looking at the answer key or the bridge doc:

| Score | Assessment |
|:------|:-----------|
| 13-15 | Exceptional. Your Oracle-to-EPAS translation is production-ready. Move to Module 02. |
| 10-12 | Strong foundation. Re-read the answer keys for the ones you missed. Focus on the WHY, not just the commands. |
| 7-9 | Expected for week 1. The scenarios you missed are the ones most likely to bite you in production. Study them twice. |
| 4-6 | Re-read Concepts 03 (Oracle to EPAS Bridge), then redo this exercise. Pay special attention to the "Key differences" in each answer. |
| 0-3 | No shame - this is week 1 and EPAS is genuinely different from Oracle. Re-read all three Concepts docs, then redo this exercise with the bridge doc open as a reference. |

---

## How To Know You Are Done

You can handle all of the following without referencing any documentation:

- **Find and kill a stuck session** using `pg_stat_activity` and `pg_terminate_backend()`
- **Diagnose a slow query** using `EXPLAIN (ANALYZE, BUFFERS)` and read the output
- **Determine primary vs. standby** with `pg_is_in_recovery()`
- **Measure replication lag** from both the primary and standby perspectives
- **Recover a single table** from a Barman backup to a temporary instance
- **Explain why DELETE does not shrink tables** in EPAS and know the three options (VACUUM FULL, pg_repack, partitioning)
- **Explain XID wraparound** to a non-DBA and describe the monitoring/prevention strategy

If any of these are shaky, re-read the specific scenario and its answer key. These 15 scenarios cover about 80% of what you will encounter in your first month managing EPAS at Mastercard.

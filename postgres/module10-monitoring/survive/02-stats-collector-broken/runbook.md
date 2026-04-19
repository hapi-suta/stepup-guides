# Scenario 02 - Stats Collector Broken

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Monitoring dashboards are showing stale data.
pg_stat_activity shows no active queries even during load.
pg_stat_user_tables shows zero for seq_scan and idx_scan.
The Pulse dashboard Health Check panel shows no activity.
```

---

## Key Concepts for Revision

- **track_activities** - When `on`, PostgreSQL records what each backend process is currently executing in shared memory. This is what populates `pg_stat_activity.query` and `query_start`. When `off`, the query text and timing columns are NULL for all sessions - you see the sessions but not what they are doing.

- **track_counts** - When `on`, PostgreSQL counts row operations (inserts, updates, deletes, reads) per table and index. This populates `pg_stat_user_tables.seq_scan`, `idx_scan`, `n_live_tup`, `n_dead_tup`, and all the tuple counters. When `off`, all those counters stop incrementing. Autovacuum also relies on `track_counts` to know which tables need vacuuming - disabling it can cause autovacuum to stop doing useful work.

- **Reload vs restart for these parameters** - Both `track_activities` and `track_counts` have `sighup` context, meaning a reload is sufficient to apply changes. You do not need a restart.

- **Stats collector architecture** - In PostgreSQL 14 and earlier, a separate `stats collector` process gathered these statistics. In PostgreSQL 15+, this was replaced with shared memory statistics, which are faster and do not require a separate process. Either way, the `track_*` parameters control what gets tracked.

---

## Diagnostic Steps

### Step 1 - Confirm the dashboards are stale

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Run a query that should show up in pg_stat_activity.

```sql
SELECT query, state FROM pg_stat_activity WHERE usename = 'postgres';
```

Expected output when broken (yours will differ):

```
 query | state
-------+-------
       | idle
(1 row)
```

The query column is NULL or empty - `track_activities` is off.

### Step 2 - Check pg_stat_user_tables

```sql
SELECT relname, seq_scan, idx_scan FROM pg_stat_user_tables WHERE relname = 'orders';
```

Expected output when broken:

```
 relname | seq_scan | idx_scan
---------+----------+----------
 orders  |        0 |        0
(1 row)
```

All zero counters despite recent activity - `track_counts` is off.

### Step 3 - Check the current settings

```sql
SHOW track_activities;
```

Expected output when broken:

```
 track_activities
------------------
 off
(1 row)
```

```sql
SHOW track_counts;
```

Expected output when broken:

```
 track_counts
--------------
 off
(1 row)
```

```sql
\q
```

### Step 4 - Confirm via postgresql.auto.conf

```bash
grep -E 'track_activities|track_counts' /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):

```
track_activities = 'off'
track_counts = 'off'
```

```bash
exit
```

---

## Resolution

### Step 1 - Re-enable track_activities

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET track_activities = on;"
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Re-enable track_counts

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET track_counts = on;"
```

Expected output:

```
ALTER SYSTEM
```

### Step 3 - Reload the configuration (no restart needed)

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 4 - Verify the settings are now on

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW track_activities;"
```

Expected output:

```
 track_activities
------------------
 on
(1 row)
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW track_counts;"
```

Expected output:

```
 track_counts
--------------
 on
(1 row)
```

### Step 5 - Verify pg_stat_activity is now showing data

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pid, usename, state, left(query,40) FROM pg_stat_activity WHERE usename IS NOT NULL;"
```

Expected output (yours will differ):

```
  pid  | usename  | state | left
-------+----------+-------+----------------------------------------------
   412 | postgres | active| SELECT pid, usename, state, left(query,40) ..
(1 row)
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- track_activities is on
- track_counts is on
- pg_stat_activity returns rows
- pg_stat_database has active stats

---

## Interview Discussion Points

1. **What impact does track_counts = off have on autovacuum?** - Autovacuum decides which tables to vacuum based on the dead tuple count in `pg_stat_user_tables.n_dead_tup`. If `track_counts` is off, dead tuples are not counted, so autovacuum sees zero dead tuples everywhere and stops doing useful work. Over time, table bloat accumulates and query performance degrades. In extreme cases, transaction ID wraparound can occur if vacuum stops entirely.

2. **Is there any data loss from having track_counts disabled for a period of time?** - The live data in the database is unaffected - `track_counts` only controls statistics collection. However, the statistics counters do not backfill. You lose the count of inserts, updates, deletes, and scans that occurred while tracking was disabled. After re-enabling, the counters start accumulating from that point forward.

3. **What is the overhead of enabling track_activities and track_counts?** - Both parameters have very low overhead. `track_activities` writes the current query text to shared memory per-backend (a few bytes per process per query). `track_counts` increments counters in shared memory per row operation. The overhead is typically less than 1% of total CPU, which is why PostgreSQL ships with them enabled by default.

4. **What other track_* parameters exist and what do they control?** - `track_io_timing` = measures actual I/O time per block read/write (requires OS support, adds small overhead). `track_wal_io_timing` = measures WAL I/O time. `track_functions` = tracks per-function call statistics in `pg_stat_user_functions` (options: `none`, `pl`, `all`). `track_commit_timestamp` = records the commit time of each transaction, required for conflict resolution in some replication setups.

5. **Why might someone intentionally disable these parameters?** - On extremely high-throughput servers, even the small overhead of shared memory writes adds up. Some teams disable them during load tests to eliminate noise. Others disable `track_activities` in environments with sensitive data to prevent query text from appearing in `pg_stat_activity`. In practice, re-enabling them is almost always worth the overhead.

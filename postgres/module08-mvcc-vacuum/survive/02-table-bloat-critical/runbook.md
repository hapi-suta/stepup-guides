# Scenario 02 - Table Bloat Critical

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Table 'critical_bloat' has approximately 80% dead tuples.
The Pulse dashboard shows critical dead ratio.
Disk usage is growing. Investigate and remediate.
```

---

## Key Concepts for Revision

- **Dead tuple ratio as a bloat metric** - The ratio `n_dead_tup / (n_live_tup + n_dead_tup)` gives you the fraction of tuple slots occupied by dead rows. At 80%, the table is extremely inefficient - the database must read 5x more data than necessary during sequential scans. Autovacuum normally prevents this, so an 80% dead ratio means autovacuum is misconfigured, blocked, or disabled.

- **VACUUM vs VACUUM FULL decision** - Regular VACUUM reclaims space for internal reuse but does not shrink the file. VACUUM FULL physically rewrites the table and returns space to the OS, but holds an exclusive lock. For a table at 80% dead: first run VACUUM to assess (does it clear quickly?). Then decide if VACUUM FULL is needed based on whether new inserts will reuse the space or if the table has permanently shrunk.

- **pgstattuple for accurate bloat measurement** - `pg_stat_user_tables` uses planner statistics (approximate). `pgstattuple` does a full heap scan and gives exact dead tuple percentages. Always use `pgstattuple` to confirm before running VACUUM FULL on production tables.

- **Why autovacuum missed this** - Common reasons autovacuum did not clean this table: (1) autovacuum_vacuum_scale_factor is too high for a large table, (2) a long-running transaction is blocking cleanup, (3) autovacuum workers are all busy with other tables, (4) autovacuum is disabled for this table via `reloptions`.

---

## Diagnostic Steps

### Step 1 - Check dead tuple count

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       round(100.0 * n_dead_tup / NULLIF(n_live_tup + n_dead_tup, 0), 2) AS dead_pct,
       pg_size_pretty(pg_total_relation_size('critical_bloat')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'critical_bloat';
```

Expected output (yours will differ):

```
    relname    | n_live_tup | n_dead_tup | dead_pct | total_size
---------------+------------+------------+----------+------------
 critical_bloat|       4000 |      16000 |    80.00 |    2248 kB
(1 row)
```

Dead ratio of ~80% confirms critical bloat.

### Step 2 - Confirm with pgstattuple

```sql
SELECT dead_tuple_count,
       round(dead_tuple_percent::numeric, 2) AS dead_pct,
       round(free_percent::numeric, 2) AS free_pct
FROM pgstattuple('critical_bloat');
```

Expected output (yours will differ):

```
 dead_tuple_count | dead_pct | free_pct
------------------+----------+----------
            16000 |    42.30 |     0.50
(1 row)
```

### Step 3 - Check if autovacuum is enabled for this table

```sql
SELECT relname, reloptions
FROM pg_class
WHERE relname = 'critical_bloat';
```

Check if `autovacuum_enabled = false` appears in reloptions. If it does, autovacuum was explicitly disabled for this table.

### Step 4 - Check if a long transaction is blocking vacuum

```sql
SELECT pid, now() - xact_start AS txn_age, query
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
  AND state != 'idle'
ORDER BY xact_start
LIMIT 5;
```

A transaction running for many minutes would prevent VACUUM from removing tuples visible to that transaction.

```bash
exit
```

---

## Resolution

### Step 1 - Run VACUUM on the bloated table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
VACUUM VERBOSE critical_bloat;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.critical_bloat"
INFO:  "critical_bloat": removed 16000 row versions in 111 pages
VACUUM
```

### Step 2 - Check dead tuple count after VACUUM

```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_total_relation_size('critical_bloat')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'critical_bloat';
```

Expected output (yours will differ):

```
    relname    | n_live_tup | n_dead_tup | total_size
---------------+------------+------------+------------
 critical_bloat|       4000 |          0 |    2248 kB
(1 row)
```

### Step 3 - Decide whether VACUUM FULL is needed

If the table has permanently shrunk (you deleted 80% and do not expect it to grow back), VACUUM FULL makes sense to return the space. If new data will fill the table again, regular VACUUM is sufficient.

For this scenario, the table had 20,000 rows and now has 4,000 - it genuinely shrank. Run VACUUM FULL to reclaim disk:

```sql
VACUUM FULL critical_bloat;
```

### Step 4 - Verify final size

```sql
SELECT pg_size_pretty(pg_relation_size('critical_bloat')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 456 kB
(1 row)
```

### Step 5 - Fix the root cause

If autovacuum was disabled for this table, re-enable it:

```sql
ALTER TABLE critical_bloat RESET (autovacuum_enabled);
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
- critical_bloat table exists
- critical_bloat dead tuples below 500
- VACUUM was run on critical_bloat recently
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **How do you decide whether to run VACUUM or VACUUM FULL on a bloated table?** - Run regular VACUUM first - it is fast and non-blocking. If the table has permanently shrunk (you deleted most of the data and do not expect inserts to fill it again), then VACUUM FULL to return space to the OS. If the table will grow again soon, VACUUM FULL wastes time because new inserts will just refill the freed pages.

2. **What are the signs that autovacuum is not keeping up with a table?** - Dead tuple ratio climbing above 20% is the first sign. `last_autovacuum` timestamp being hours or days old on an active table is another. High and growing `pg_total_relation_size` on a table whose row count has not changed means bloat is accumulating.

3. **Can you run VACUUM on a table that is being actively written to?** - Yes. Regular VACUUM takes a ShareUpdateExclusiveLock, which allows concurrent reads and writes. Only VACUUM FULL takes an AccessExclusiveLock that blocks all access.

4. **What would you check first if VACUUM ran but did not remove the expected dead tuples?** - Check for long-running transactions. A transaction that started before the dead tuples were created is holding back cleanup. PostgreSQL cannot remove tuples that are still visible to any active transaction. Query `pg_stat_activity` and look at `xact_start` to find the oldest transaction.

5. **What is the difference between `n_dead_tup` in `pg_stat_user_tables` and `dead_tuple_percent` from `pgstattuple`?** - `n_dead_tup` is an estimate maintained by the statistics collector - it is approximate and updated asynchronously. `pgstattuple` performs a full heap scan and gives exact numbers. For a quick check, `pg_stat_user_tables` is fine. For a critical decision (like whether to run VACUUM FULL), use `pgstattuple` for accuracy.

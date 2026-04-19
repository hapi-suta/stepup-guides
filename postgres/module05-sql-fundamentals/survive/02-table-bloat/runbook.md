# Scenario 02 - Table Bloat

**Severity:** MEDIUM
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: The bloat_demo table has accumulated dead tuples.
Table size is growing but row count is not. Queries are
slower because PostgreSQL must skip over dead rows.
Autovacuum has not cleaned this table.
```

---

## Key Concepts for Revision

- **MVCC and dead tuples** - PostgreSQL never overwrites a row in-place. Every UPDATE creates a new version of the row and marks the old version as "dead" (invisible to current transactions). Dead rows remain on disk until VACUUM reclaims them. Without vacuuming, a heavily updated table grows without bound even if the logical row count stays constant.

- **autovacuum** - PostgreSQL's autovacuum daemon runs in the background and vacuums tables when they accumulate enough dead tuples. It can be disabled per-table with `ALTER TABLE SET (autovacuum_enabled = false)`. Autovacuum may also fall behind on very busy tables or be blocked by long-running transactions.

- **pg_stat_user_tables** - The view `pg_stat_user_tables` shows `n_dead_tup` (dead tuple count) and `n_live_tup` (live tuple count) per table. The columns `last_vacuum` and `last_autovacuum` show when the table was last cleaned.

- **VACUUM vs VACUUM FULL** - `VACUUM` marks dead space as reusable but does not return disk space to the OS. `VACUUM FULL` rewrites the entire table, returning disk space but requiring an `ACCESS EXCLUSIVE` lock (no reads or writes during the operation). Use `VACUUM` for routine maintenance and `VACUUM FULL` only when you must reclaim disk and can tolerate the lock.

- **Bloat impact on queries** - A bloated table has dead rows scattered throughout its pages. Sequential scans must read every page including those full of dead rows. Index scans must visit heap pages that may contain mostly dead versions. Both increase I/O and slow queries.

---

## Diagnostic Steps

### Step 1 - Check dead tuple count

Log in and connect:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check the table statistics:

```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup | last_vacuum | last_autovacuum
------------+------------+------------+-------------+-----------------
 bloat_demo |      10000 |     200000 |             |
(1 row)
```

`n_dead_tup` is much larger than `n_live_tup`. `last_vacuum` is NULL - the table has never been vacuumed. `last_autovacuum` is NULL - autovacuum has not touched it.

### Step 2 - Compare physical size vs row count

```sql
SELECT pg_size_pretty(pg_total_relation_size('bloat_demo')) AS total_size,
       (SELECT COUNT(*) FROM bloat_demo) AS live_rows;
```

Expected output (yours will differ):

```
 total_size | live_rows
------------+-----------
 35 MB      |     10000
(1 row)
```

35MB for 10,000 rows is far too large. The bloat is real.

### Step 3 - Check the bloat ratio

```sql
SELECT n_dead_tup::FLOAT / NULLIF(n_live_tup + n_dead_tup, 0) * 100 AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';
```

Expected output (yours will differ):

```
    dead_pct
-----------------
 95.238095238095
(1 row)
```

95% of all tuples in the table are dead.

### Step 4 - Verify autovacuum is disabled

```sql
SELECT reloptions FROM pg_class WHERE relname = 'bloat_demo';
```

Expected output:

```
         reloptions
----------------------------
 {autovacuum_enabled=false}
(1 row)
```

Autovacuum is explicitly disabled on this table. That is why it has not cleaned up.

---

## Resolution

### Step 1 - Re-enable autovacuum on the table

```sql
ALTER TABLE bloat_demo RESET (autovacuum_enabled);
```

Verify:

```sql
SELECT reloptions FROM pg_class WHERE relname = 'bloat_demo';
```

Expected output:

```
 reloptions
------------

(1 row)
```

NULL means the setting is back to the server default (autovacuum enabled).

### Step 2 - Run VACUUM manually

Do not wait for autovacuum - run VACUUM now to clear the dead tuples immediately. The `VERBOSE` option shows what VACUUM does:

```sql
VACUUM VERBOSE bloat_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.bloat_demo"
INFO:  scanned index "bloat_demo_pkey" to remove 200000 row versions
INFO:  "bloat_demo": removed 200000 row versions in 1120 pages
INFO:  "bloat_demo": found 200000 removable, 10000 nonremovable row versions in 1130 out of 1130 pages
...
VACUUM
```

### Step 3 - Verify dead tuples are cleared

```sql
SELECT relname, n_live_tup, n_dead_tup, last_vacuum
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup |          last_vacuum
------------+------------+------------+-------------------------------
 bloat_demo |      10000 |          0 | 2024-01-20 16:00:00+00
(1 row)
```

`n_dead_tup` is now 0 and `last_vacuum` is populated.

### Step 4 - Check table size after VACUUM

```sql
SELECT pg_size_pretty(pg_total_relation_size('bloat_demo')) AS total_size;
```

Expected output (yours will differ):

```
 total_size
------------
 35 MB
(1 row)
```

Note: `VACUUM` reclaims space for reuse within PostgreSQL but may not return disk space to the OS immediately. The size on disk stays roughly the same. Run `VACUUM FULL` if you need to return space to the OS (requires an exclusive lock).

```sql
\q
```

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- `bloat_demo` table exists
- `n_dead_tup` for `bloat_demo` is below 1000
- `last_vacuum` is not NULL (table was vacuumed)
- `autovacuum_enabled` is not set to false

---

## Interview Discussion Points

1. **Why does PostgreSQL keep dead tuples instead of updating rows in place?** - MVCC requires that each transaction sees a consistent snapshot of the data. If PostgreSQL overwrote the old row version immediately, concurrent transactions reading the old snapshot would see corrupt or missing data. Dead tuples are the cost of giving every transaction its own consistent view of the world without locking readers out.

2. **What is the difference between VACUUM, VACUUM ANALYZE, and VACUUM FULL?** - `VACUUM` removes dead tuples and marks pages as reusable. `VACUUM ANALYZE` does all that plus updates the planner statistics (equivalent to running ANALYZE separately). `VACUUM FULL` rewrites the entire table, compacting it and returning space to the OS, but requires an ACCESS EXCLUSIVE lock. Use VACUUM routinely, VACUUM ANALYZE when statistics are stale, and VACUUM FULL only during maintenance windows when you need the disk space back.

3. **How does long-running transaction affect VACUUM?** - VACUUM can only reclaim rows that are no longer visible to any current or future transaction. If a transaction started 2 hours ago, any row versions created after that transaction started cannot be vacuumed - even if they are logically dead. This is called "transaction ID horizon" or "relfrozenxid". A single long-running transaction can prevent VACUUM from cleaning the entire database.

4. **How do you identify tables with high bloat without running VACUUM VERBOSE?** - Query `pg_stat_user_tables` for tables where `n_dead_tup` is large relative to `n_live_tup`. The pgstattuple extension provides more accurate bloat measurements. Third-party tools like `pgbloat` query the raw page storage metadata.

5. **What autovacuum settings would you tune for a high-UPDATE table?** - Lower `autovacuum_vacuum_scale_factor` (e.g., 0.01 instead of the default 0.2) to trigger autovacuum sooner. Increase `autovacuum_vacuum_cost_delay` to 0 or reduce it to let autovacuum run faster at the cost of more I/O impact. Set these per-table using `ALTER TABLE ... SET (autovacuum_vacuum_scale_factor = 0.01)` to avoid changing global settings.

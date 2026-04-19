# Scenario 07 - TOAST Table Bloat

**Severity:** MEDIUM
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Table toast_bloat_demo has excessive TOAST storage.
Repeated large text updates have bloated the TOAST table.
Disk usage on the data tablespace is growing unexpectedly.
```

---

## Key Concepts for Revision

- **TOAST (The Oversized-Attribute Storage Technique)** - PostgreSQL stores large column values (over ~2KB) in a separate TOAST table rather than inline in the main heap. Each table with variable-length columns gets a companion `pg_toast.pg_toast_NNNNN` table. When you UPDATE a row with a large text column, the old TOAST chunks become dead tuples in the TOAST table - but VACUUM on the parent table is what cleans them up.

- **TOAST bloat is invisible at first glance** - `pg_stat_user_tables` shows dead tuples for the parent table, but the real disk waste is in the TOAST table. You need to check TOAST table sizes explicitly using `pg_relation_size()` with the `'main'` and `'toast'` forks, or use `pg_total_relation_size()` minus `pg_relation_size()`.

- **VACUUM the parent, not the TOAST table directly** - You cannot run `VACUUM pg_toast.pg_toast_NNNNN` directly. Instead, you VACUUM the parent table and PostgreSQL automatically vacuums the associated TOAST table. This is a common gotcha for beginners.

- **REINDEX after heavy TOAST bloat** - TOAST tables have their own indexes. After vacuuming away large amounts of dead TOAST data, the TOAST index may still be bloated. Running `REINDEX TABLE toast_bloat_demo` rebuilds both the main table indexes and the TOAST index.

- **pg_table_size vs pg_relation_size** - `pg_relation_size()` returns only the main fork (heap). `pg_table_size()` includes the main fork plus TOAST plus free space map. `pg_total_relation_size()` adds indexes on top of that. Comparing these tells you how much is TOAST vs main data.

---

## Diagnostic Steps

### Step 1 - Connect to PostgreSQL

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 2 - Check the parent table for dead tuples

```sql
SELECT relname, n_live_tup, n_dead_tup,
       last_vacuum, last_autovacuum
FROM pg_stat_user_tables
WHERE relname = 'toast_bloat_demo';
```

Expected output (yours will differ):

```
     relname      | n_live_tup | n_dead_tup | last_vacuum | last_autovacuum
------------------+------------+------------+-------------+-----------------
 toast_bloat_demo |       2000 |       4000 |             |
(1 row)
```

You will see dead tuples from the two UPDATE statements that ran during injection.

### Step 3 - Check TOAST table size vs main table size

```sql
SELECT
    c.relname AS table_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS main_size,
    pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
WHERE c.relname = 'toast_bloat_demo';
```

Expected output (yours will differ):

```
    table_name    | main_size | toast_size | total_size
------------------+-----------+------------+------------
 toast_bloat_demo | 256 kB    | 48 MB      | 49 MB
(1 row)
```

The TOAST table is much larger than the main table because the text columns store their data in TOAST.

### Step 4 - Identify the TOAST table name

```sql
SELECT c.relname AS parent_table,
       t.relname AS toast_table
FROM pg_class c
JOIN pg_class t ON t.oid = c.reltoastrelid
WHERE c.relname = 'toast_bloat_demo';
```

Expected output (yours will differ):

```
   parent_table   |    toast_table
------------------+--------------------
 toast_bloat_demo | pg_toast_16401
(1 row)
```

Note the TOAST table name - you will check its size again after the fix.

```bash
exit
```

---

## Resolution

### Step 1 - VACUUM the parent table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

VACUUM the parent table. PostgreSQL will automatically vacuum the associated TOAST table.

```sql
VACUUM VERBOSE toast_bloat_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.toast_bloat_demo"
INFO:  finished vacuuming "public.toast_bloat_demo": index scans: 1
...
VACUUM
```

### Step 2 - Check that dead tuples are gone

```sql
SELECT relname, n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'toast_bloat_demo';
```

Expected output (yours will differ):

```
     relname      | n_live_tup | n_dead_tup
------------------+------------+------------
 toast_bloat_demo |       2000 |          0
(1 row)
```

### Step 3 - Rebuild indexes (including TOAST index)

After removing dead TOAST tuples, the TOAST index may still be bloated. Rebuild it.

```sql
REINDEX TABLE toast_bloat_demo;
```

Expected output:

```
REINDEX
```

### Step 4 - Verify TOAST table size reduced

```sql
SELECT
    c.relname AS table_name,
    pg_size_pretty(pg_relation_size(c.oid)) AS main_size,
    pg_size_pretty(pg_relation_size(c.reltoastrelid)) AS toast_size,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
WHERE c.relname = 'toast_bloat_demo';
```

The TOAST size should be significantly smaller now. Regular VACUUM frees pages for reuse but does not return them to the OS - the file size may not shrink, but the space is now available for reuse.

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
- toast_bloat_demo has zero dead tuples
- TOAST table size is reasonable
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Why can you not VACUUM a TOAST table directly?** - TOAST tables live in the `pg_toast` schema and are internal PostgreSQL objects. PostgreSQL manages them automatically when you VACUUM the parent table. Attempting `VACUUM pg_toast.pg_toast_NNNNN` directly will fail with a permission error because only superuser internals can touch toast relations during a parent VACUUM. The correct approach is always to VACUUM the parent.

2. **When would VACUUM FULL be justified for TOAST bloat?** - Regular VACUUM marks dead pages as reusable but does not shrink the file on disk. If the TOAST table grew to 50GB and after cleanup only 5GB is live data, the file stays 50GB - just with 45GB of reusable space. If you need to reclaim that disk space back to the OS (for example, the disk is nearly full), VACUUM FULL rewrites the table and its TOAST table compactly. The tradeoff is an ACCESS EXCLUSIVE lock on the table for the entire duration.

3. **How do you monitor TOAST bloat proactively?** - Compare `pg_table_size(oid) - pg_relation_size(oid)` (which gives TOAST + FSM size) against the expected data volume. If TOAST is 10x the main table for a table with modest text columns, something is wrong. You can also check `pg_statio_user_tables.toast_blks_hit` and `toast_blks_read` to see TOAST I/O activity.

4. **Can you control which columns get TOASTed?** - Yes. Each column has a TOAST strategy: `EXTENDED` (compress then store out-of-line), `EXTERNAL` (out-of-line without compression), `MAIN` (try to keep inline, compress if needed), or `PLAIN` (never TOAST). You set it with `ALTER TABLE t ALTER COLUMN c SET STORAGE EXTERNAL`. For columns you rarely read but frequently update, `EXTERNAL` avoids compression overhead.

5. **What is the relationship between TOAST chunk size and TOAST bloat?** - Each TOAST chunk is about 2KB (one-quarter of a page). A 100KB text value gets split into roughly 50 chunks. When that value is updated, all 50 old chunks become dead tuples. This means TOAST bloat grows proportionally to the size of the values being updated, not just the number of rows - one row update on a 1MB text column creates ~500 dead TOAST tuples.

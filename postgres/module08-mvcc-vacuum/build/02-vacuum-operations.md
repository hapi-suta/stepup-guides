# Build 02 - Vacuum Operations

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 25-30 minutes

---

## What You Will Learn

- The difference between VACUUM and VACUUM FULL
- How to run VACUUM manually and read its verbose output
- How VACUUM reclaims space by marking dead tuples as reusable
- How VACUUM FULL physically compacts the table (with the cost of an exclusive lock)
- Key autovacuum parameters and what they control
- How to watch dead tuple counts drop on the Pulse dashboard after VACUUM runs

---

> **Concept: What does VACUUM actually do?**
> VACUUM scans a table's pages and marks dead tuples as free space. Those page slots become available for future INSERTs and UPDATEs to reuse. VACUUM does NOT shrink the file on disk (the OS-level file size stays the same) - it just marks internal space as reusable. VACUUM FULL is different: it rewrites the entire table into a new file, physically returning space to the OS, but it requires an exclusive lock for the entire duration.

---

## Step 1 - Log in to NODE1

```bash
ssh -i ~/student.pem ec2-user@<NODE1_IP>
```

---

## Step 2 - Switch to the postgres user

```bash
sudo -iu postgres
```

---

## Step 3 - Connect to stepup_store

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 4 - Create a table and generate dead tuples

```sql
CREATE TABLE vacuum_demo (
  id   serial PRIMARY KEY,
  val  text
);
```

Insert 10,000 rows:

```sql
INSERT INTO vacuum_demo (val)
SELECT 'row_' || generate_series(1, 10000);
```

Expected output (yours will differ):

```
INSERT 0 10000
```

Now update all rows to create 10,000 dead tuples:

```sql
UPDATE vacuum_demo SET val = val || '_updated';
```

Expected output (yours will differ):

```
UPDATE 10000
```

---

## Step 5 - Check dead tuple count before VACUUM

```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_total_relation_size('vacuum_demo')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'vacuum_demo';
```

Expected output (yours will differ):

```
   relname   | n_live_tup | n_dead_tup | total_size
-------------+------------+------------+------------
 vacuum_demo |      10000 |      10000 |    2136 kB
(1 row)
```

Note the total size and dead tuple count. You should see roughly equal live and dead tuples.

---

## Step 6 - Check the Pulse dashboard

Open your browser to `http://<NODE1_IP>:8080` and navigate to the MVCC/Vacuum panel. Watch `vacuum_demo` show up with a high dead tuple count. Note the dead ratio - it should be near 50%.

---

## Step 7 - Run VACUUM VERBOSE

`VACUUM VERBOSE` prints a detailed report of what it did - how many pages it scanned, how many dead tuples it removed, and how much space it freed.

```sql
VACUUM VERBOSE vacuum_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.vacuum_demo"
INFO:  scanned index "vacuum_demo_pkey" to remove 10000 row versions
DETAIL:  CPU: user: 0.02 s, system: 0.01 s, elapsed: 0.05 s
INFO:  "vacuum_demo": removed 10000 row versions in 55 pages
DETAIL:  CPU: user: 0.01 s, system: 0.00 s, elapsed: 0.03 s
INFO:  index scan bypassed: 10000 dead item identifiers removed without scanning index
INFO:  "vacuum_demo": found 10000 removable, 10000 nonremovable row versions in 110 out of 110 pages
DETAIL:  0 dead row versions cannot be removed yet, oldest xmin: 750
VACUUM
```

> **Concept: Reading VACUUM VERBOSE output**
> The key line is "removed N row versions in N pages" - that tells you how many dead tuples were cleaned up. "0 dead row versions cannot be removed yet" means there are no long-running transactions holding back cleanup. If you see a nonzero "cannot be removed yet" count, a long-running transaction is pinning old tuple versions.

---

## Step 8 - Check dead tuple count after VACUUM

```sql
SELECT relname, n_live_tup, n_dead_tup,
       pg_size_pretty(pg_total_relation_size('vacuum_demo')) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'vacuum_demo';
```

Expected output (yours will differ):

```
   relname   | n_live_tup | n_dead_tup | total_size
-------------+------------+------------+------------
 vacuum_demo |      10000 |          0 |    2136 kB
(1 row)
```

Dead tuples are gone. Notice the total size is the same as before. VACUUM freed the space internally but did not shrink the file.

---

## Step 9 - Watch the Pulse dashboard update

Refresh the Pulse MVCC/Vacuum panel. The dead tuple count for `vacuum_demo` should now show 0 or a very small number.

---

## Step 10 - Understand the space reclaim difference

To physically return space to the OS you need VACUUM FULL. First, note the current size:

```sql
SELECT pg_size_pretty(pg_relation_size('vacuum_demo')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 1552 kB
(1 row)
```

---

## Step 11 - Generate dead tuples again for the VACUUM FULL comparison

```sql
UPDATE vacuum_demo SET val = val || '_again';
```

---

## Step 12 - Run VACUUM FULL

VACUUM FULL rewrites the entire table into a new physical file. This requires an ACCESS EXCLUSIVE lock - no reads or writes can happen while it runs.

```sql
VACUUM FULL VERBOSE vacuum_demo;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.vacuum_demo"
INFO:  "vacuum_demo": found 10000 removable, 10000 nonremovable row versions
INFO:  "vacuum_demo": page count before 110, page count after 55
VACUUM
```

---

## Step 13 - Check size after VACUUM FULL

```sql
SELECT pg_size_pretty(pg_relation_size('vacuum_demo')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 776 kB
(1 row)
```

The file shrank because VACUUM FULL wrote only the live tuples into a new, compact file.

> **Concept: When to use VACUUM FULL**
> VACUUM FULL is a last resort for tables that have grown severely bloated and will not shrink back through normal VACUUM. The trade-off is an exclusive lock for the entire operation - on a busy production table, this can mean minutes or hours of total downtime. For production use, `pg_repack` (covered in Build 05) can do the same job online without an exclusive lock.

---

## Step 14 - Autovacuum parameters

Connect to psql and look at the key autovacuum parameters:

```sql
SELECT name, setting, unit, short_desc
FROM pg_settings
WHERE name IN (
  'autovacuum',
  'autovacuum_vacuum_threshold',
  'autovacuum_vacuum_scale_factor',
  'autovacuum_naptime',
  'autovacuum_max_workers'
);
```

Expected output (yours will differ):

```
              name               | setting | unit |                      short_desc
---------------------------------+---------+------+-------------------------------------------------------
 autovacuum                      | on      |      | Starts the autovacuum subprocess.
 autovacuum_max_workers          | 3       |      | Sets the maximum number of simultaneously running ...
 autovacuum_naptime              | 60      | s    | Time to sleep between autovacuum runs.
 autovacuum_vacuum_scale_factor  | 0.2     |      | Fraction of reltuples before a VACUUM is triggered.
 autovacuum_vacuum_threshold     | 50      |      | Min number of dead tuples before a VACUUM is triggered.
(5 rows)
```

> **Concept: Autovacuum trigger formula**
> Autovacuum runs VACUUM on a table when: `n_dead_tup > autovacuum_vacuum_threshold + (autovacuum_vacuum_scale_factor * n_live_tup)`. With defaults, that means autovacuum kicks in when dead tuples exceed 50 + (0.2 * row count). For a 100-row table that is 70 dead tuples. For a 1,000,000-row table that is 200,050 dead tuples - which can be a LOT of bloat before cleanup runs. Large tables often need per-table tuning.

---

## Step 15 - Check last autovacuum time for vacuum_demo

```sql
SELECT relname,
       last_vacuum,
       last_autovacuum,
       vacuum_count,
       autovacuum_count
FROM pg_stat_user_tables
WHERE relname = 'vacuum_demo';
```

Expected output (yours will differ):

```
   relname   |          last_vacuum          | last_autovacuum | vacuum_count | autovacuum_count
-------------+-------------------------------+-----------------+--------------+------------------
 vacuum_demo | 2026-04-19 14:23:11.123456+00 |                 |            2 |                0
(1 row)
```

`last_vacuum` reflects the manual VACUUM you ran. `last_autovacuum` would show when autovacuum last ran on this table.

---

## Step 16 - Exit psql and postgres user

```sql
\q
```

```bash
exit
```

```bash
exit
```

---

## Summary

- VACUUM removes dead tuples and makes their space reusable but does not shrink the on-disk file
- VACUUM FULL physically rewrites the table, shrinks the file, but requires an exclusive lock
- VACUUM VERBOSE shows exactly how many pages were scanned and how many dead tuples were removed
- Autovacuum triggers when dead tuples exceed `threshold + (scale_factor * live_tuples)`
- The Pulse dashboard drops dead tuple counts in real time after VACUUM runs

---

## Next Step

Continue to **Build 03 - Autovacuum Tuning** to learn how to configure autovacuum workers and per-table settings.

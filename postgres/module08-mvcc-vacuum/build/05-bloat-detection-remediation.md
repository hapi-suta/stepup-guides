# Build 05 - Bloat Detection and Remediation

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 30-35 minutes

---

## What You Will Learn

- The difference between table bloat and index bloat
- How to measure bloat with `pgstattuple` and `pg_stat_user_tables`
- How to use the dead tuple ratio from the Pulse MVCC/Vacuum panel
- When to choose VACUUM vs VACUUM FULL vs pg_repack
- How to detect and fix index bloat with REINDEX

---

> **Concept: Table bloat vs index bloat**
> Table bloat is unused space inside the heap file caused by dead tuples not yet reclaimed. Index bloat is wasted space inside index B-tree structures caused by deleted index entries. Both grow over time when tables are heavily updated or deleted. Table bloat is cleaned by VACUUM. Index bloat is cleaned by REINDEX or VACUUM (which also scans indexes). The key difference is that bloated indexes still work correctly - they just waste I/O and memory. Bloated tables slow down sequential scans because PostgreSQL must read more pages than necessary.

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

## Step 4 - Install the pgstattuple extension

`pgstattuple` provides detailed tuple-level statistics about how much of each page is actually being used vs wasted.

```sql
CREATE EXTENSION IF NOT EXISTS pgstattuple;
```

Expected output (yours will differ):

```
CREATE EXTENSION
```

---

## Step 5 - Create a bloated table

```sql
CREATE TABLE bloat_demo (
  id    serial PRIMARY KEY,
  val   text
);
```

Insert 50,000 rows:

```sql
INSERT INTO bloat_demo (val)
SELECT 'data_' || generate_series(1, 50000);
```

Expected output (yours will differ):

```
INSERT 0 50000
```

Delete 40,000 of them (80% deletion rate creates heavy bloat):

```sql
DELETE FROM bloat_demo WHERE id <= 40000;
```

Expected output (yours will differ):

```
DELETE 40000
```

---

## Step 6 - Measure bloat with pgstattuple

`pgstattuple` scans the entire heap and reports what fraction of each page contains live data vs dead data.

```sql
SELECT * FROM pgstattuple('bloat_demo');
```

Expected output (yours will differ):

```
 table_len | tuple_count | tuple_len | tuple_percent | dead_tuple_count | dead_tuple_len | dead_tuple_percent | free_space | free_percent
-----------+-------------+-----------+---------------+------------------+----------------+--------------------+------------+--------------
   3686400 |       10000 |    390000 |         10.58 |            40000 |        1560000 |              42.32 |    1528768 |        41.49
(1 row)
```

> **Concept: Reading pgstattuple output**
> `dead_tuple_percent` shows what fraction of the table's space is occupied by dead tuples. `free_percent` shows the space that has already been freed by a previous VACUUM but has not yet been reused. In this case, about 42% of the table is dead tuples - classic bloat. `tuple_percent` shows that only 10% of the table is live data.

---

## Step 7 - Check dead tuple ratio via pg_stat_user_tables

The Pulse dashboard reads this same query:

```sql
SELECT relname,
       n_live_tup,
       n_dead_tup,
       CASE WHEN n_live_tup + n_dead_tup > 0
            THEN round(100.0 * n_dead_tup / (n_live_tup + n_dead_tup), 2)
            ELSE 0
       END AS dead_ratio_pct,
       pg_size_pretty(pg_total_relation_size(relid)) AS total_size
FROM pg_stat_user_tables
WHERE relname = 'bloat_demo';
```

Expected output (yours will differ):

```
  relname   | n_live_tup | n_dead_tup | dead_ratio_pct | total_size
------------+------------+------------+----------------+------------
 bloat_demo |      10000 |      40000 |          80.00 |    4024 kB
(1 row)
```

Dead ratio of 80% means the table is severely bloated. The Pulse dashboard shows this same percentage in the top bloated tables panel.

---

## Step 8 - Check table size before vacuum

```sql
SELECT pg_size_pretty(pg_relation_size('bloat_demo')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 3600 kB
(1 row)
```

---

## Step 9 - Run regular VACUUM

Regular VACUUM reclaims space for reuse but does not shrink the file.

```sql
VACUUM bloat_demo;
```

---

## Step 10 - Check size after regular VACUUM

```sql
SELECT pg_size_pretty(pg_relation_size('bloat_demo')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 3600 kB
(1 row)
```

The file size did not change. The space is now marked reusable internally, but the OS still sees the same file size.

---

## Step 11 - Check pgstattuple again to see free space

```sql
SELECT dead_tuple_count, dead_tuple_percent, free_space, free_percent
FROM pgstattuple('bloat_demo');
```

Expected output (yours will differ):

```
 dead_tuple_count | dead_tuple_percent | free_space | free_percent
------------------+--------------------+------------+--------------
                0 |               0.00 |    2860032 |        77.54
(1 row)
```

Dead tuples are gone (0 dead_tuple_count). But free_percent is now 77% - that space is available for reuse by future inserts, but the file did not shrink.

---

## Step 12 - Run VACUUM FULL to physically shrink

```sql
VACUUM FULL bloat_demo;
```

---

## Step 13 - Check size after VACUUM FULL

```sql
SELECT pg_size_pretty(pg_relation_size('bloat_demo')) AS heap_size;
```

Expected output (yours will differ):

```
 heap_size
-----------
 424 kB
(1 row)
```

The file shrank from ~3.6 MB to ~424 kB because VACUUM FULL rewrote only the live tuples.

---

## Step 14 - Detect index bloat with pgstatindex

Create a heavily-deleted index scenario on bloat_demo:

```sql
CREATE INDEX idx_bloat_demo_val ON bloat_demo (val);
```

Insert more rows then delete them to create index bloat:

```sql
INSERT INTO bloat_demo (val)
SELECT 'stale_' || generate_series(1, 10000);
```

```sql
DELETE FROM bloat_demo WHERE val LIKE 'stale_%';
```

---

## Step 15 - Measure index bloat with pgstatindex

```sql
SELECT * FROM pgstatindex('idx_bloat_demo_val');
```

Expected output (yours will differ):

```
 version | tree_level | index_size | root_block_no | internal_pages | leaf_pages | empty_pages | deleted_pages | avg_leaf_density | leaf_fragmentation
---------+------------+------------+---------------+----------------+------------+-------------+---------------+------------------+--------------------
       4 |          1 |     368640 |             3 |              1 |         44 |           0 |             0 |            40.93 |              17.08
(1 row)
```

> **Concept: Index bloat indicators**
> `avg_leaf_density` shows what percentage of each leaf page is actually storing index entries. A value of 40% means 60% of each index page is wasted space. After heavy deletes, index pages are mostly empty but not removed. `leaf_fragmentation` above 30% generally indicates the index should be rebuilt.

---

## Step 16 - Run REINDEX to rebuild the index

`REINDEX INDEX` rebuilds the index from scratch, reclaiming all wasted space. On PostgreSQL 12+, `REINDEX CONCURRENTLY` rebuilds without locking.

```sql
REINDEX INDEX CONCURRENTLY idx_bloat_demo_val;
```

Expected output (yours will differ):

```
REINDEX
```

---

## Step 17 - Check index density after REINDEX

```sql
SELECT avg_leaf_density, leaf_fragmentation
FROM pgstatindex('idx_bloat_demo_val');
```

Expected output (yours will differ):

```
 avg_leaf_density | leaf_fragmentation
------------------+--------------------
            88.52 |               0.00
(1 row)
```

Density is back up to ~88% and fragmentation is 0.

---

## Step 18 - Understand pg_repack as the production alternative

`pg_repack` is an extension (not installed in this lab, but common in production) that rebuilds tables and indexes online - without the exclusive lock that VACUUM FULL and REINDEX require.

The general workflow is:

1. Install: `dnf install pg_repack16`
2. Install extension: `CREATE EXTENSION pg_repack;`
3. Run: `/usr/pgsql-16/bin/pg_repack -d stepup_store -t bloat_demo`

`pg_repack` works by creating a new copy of the table in the background, syncing changes as they come in, then doing a brief lock-swap at the end. The lock swap typically takes milliseconds instead of minutes.

> **Concept: VACUUM FULL vs pg_repack**
> VACUUM FULL holds an ACCESS EXCLUSIVE lock for the entire duration of the table rewrite. On a 100 GB table, that could be 30-60 minutes of complete downtime. `pg_repack` does the same physical rewrite but only takes a brief exclusive lock at the very end to swap the table. For production tables that cannot afford downtime, `pg_repack` is the standard tool.

---

## Step 19 - Check Pulse dashboard top bloated tables

Open your browser to `http://<NODE1_IP>:8080` and navigate to the MVCC/Vacuum panel. You should see `bloat_demo` in the top bloated tables list before you ran VACUUM FULL. After VACUUM FULL it should no longer appear at the top (or show 0% dead ratio).

---

## Step 20 - Exit psql and postgres user

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

- Table bloat: dead tuples filling heap pages - measured with `pgstattuple` and `pg_stat_user_tables`
- Index bloat: deleted index entries leaving sparse B-tree pages - measured with `pgstatindex`
- VACUUM reclaims dead tuple space for internal reuse but does not shrink the file
- VACUUM FULL physically rewrites the table, shrinks the file, but locks the table exclusively
- REINDEX rebuilds index files from scratch; use REINDEX CONCURRENTLY to avoid read/write locks
- `pg_repack` is the production-safe alternative to VACUUM FULL - no extended exclusive lock
- The Pulse MVCC/Vacuum panel shows dead ratio and top bloated tables in real time

---

## Module Complete

You have completed all 5 BUILD guides for Module 08 - MVCC & Vacuum. Proceed to the USE exercises to practice these concepts hands-on.

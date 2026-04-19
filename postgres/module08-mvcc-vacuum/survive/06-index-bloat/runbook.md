# Scenario 06 - Index Bloat

**Severity:** MEDIUM
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Index idx_email on index_bloat_demo is bloated.
90,000 rows were deleted. The index is still large.
Queries on email column are slower than expected.
Index needs to be rebuilt.
```

---

## Key Concepts for Revision

- **Index bloat after mass deletes** - When rows are deleted, their index entries become "dead" in the B-tree but the pages are not immediately reused. Unlike heap bloat, index bloat is not fully cleaned by VACUUM alone. VACUUM marks the index entries as deleted and removes them from the B-tree structure during a scan, but the physical pages stay the same size. The `avg_leaf_density` drops - each page has fewer entries than it should.

- **pgstatindex for index bloat measurement** - `pgstatindex('idx_name')` does a full scan of the index and reports `avg_leaf_density` (what fraction of each leaf page is used). A healthy, freshly built index is 80-90%. Below 50% indicates significant bloat. `leaf_fragmentation` shows how scattered the leaf pages are.

- **REINDEX CONCURRENTLY** - Rebuilds the index from scratch while the table remains fully readable and writable. It builds a new index alongside the old one, then swaps them in a brief lock window. This is the preferred approach for production systems. Plain `REINDEX` takes a `ShareLock` which blocks writes.

- **When does regular VACUUM help with index bloat?** - VACUUM does clean up deleted index entries during an index scan pass. For moderate bloat, running VACUUM regularly is enough. For severe bloat (after a large batch delete), REINDEX is faster because it builds from scratch rather than compacting in place.

---

## Diagnostic Steps

### Step 1 - Check index size vs table size

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT relname,
       pg_size_pretty(pg_relation_size(relid))         AS table_size,
       pg_size_pretty(pg_indexes_size(relid))          AS index_size,
       n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'index_bloat_demo';
```

Expected output (yours will differ):

```
      relname      | table_size | index_size | n_live_tup
-------------------+------------+------------+------------
 index_bloat_demo  | 456 kB     | 4096 kB    |      10000
(1 row)
```

The index is 4 MB but the table is only 456 kB with 10,000 live rows. That is a red flag - the index is 9x larger than the heap.

### Step 2 - Measure index density with pgstatindex

```sql
SELECT version,
       tree_level,
       pg_size_pretty(index_size::bigint) AS index_size,
       leaf_pages,
       deleted_pages,
       round(avg_leaf_density::numeric, 2) AS avg_leaf_density,
       round(leaf_fragmentation::numeric, 2) AS leaf_fragmentation
FROM pgstatindex('idx_email');
```

Expected output (yours will differ):

```
 version | tree_level | index_size | leaf_pages | deleted_pages | avg_leaf_density | leaf_fragmentation
---------+------------+------------+------------+---------------+------------------+--------------------
       4 |          2 | 4096 kB    |        498 |             0 |            16.42 |              64.13
(1 row)
```

`avg_leaf_density` of 16% means 84% of every index page is wasted space. This index needs to be rebuilt.

```bash
exit
```

---

## Resolution

### Step 1 - Rebuild the index concurrently

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
REINDEX INDEX CONCURRENTLY idx_email;
```

Expected output (yours will differ):

```
REINDEX
```

This takes longer than a regular REINDEX because it must build the index without blocking reads or writes. On a busy table, this is the right choice.

### Step 2 - Check index density after REINDEX

```sql
SELECT round(avg_leaf_density::numeric, 2) AS avg_leaf_density,
       round(leaf_fragmentation::numeric, 2) AS leaf_fragmentation,
       pg_size_pretty(index_size::bigint) AS index_size
FROM pgstatindex('idx_email');
```

Expected output (yours will differ):

```
 avg_leaf_density | leaf_fragmentation | index_size
------------------+--------------------+------------
            88.14 |               0.00 | 456 kB
(1 row)
```

Density is back to ~88% and fragmentation is 0. The index shrank from 4 MB to 456 kB.

### Step 3 - Verify queries can use the index

```sql
EXPLAIN SELECT email FROM index_bloat_demo WHERE email = 'user_1@example.com';
```

Expected output (yours will differ):

```
                                    QUERY PLAN
----------------------------------------------------------------------------------
 Index Only Scan using idx_email on index_bloat_demo  (cost=0.29..8.31 rows=1 ...)
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
- idx_email index exists
- idx_email avg_leaf_density above 60 percent
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **Why does VACUUM not fully fix index bloat?** - VACUUM cleans index entries marked as deleted and reclaims them for reuse within the B-tree structure. But if a large fraction of the index was deleted, VACUUM does not physically compact pages or reduce the index file size. The pages remain allocated with low density. REINDEX rebuilds from scratch, creating a tight, compact index.

2. **What is the difference between REINDEX and REINDEX CONCURRENTLY?** - `REINDEX` takes a `ShareLock` on the table, blocking writes but allowing reads. `REINDEX CONCURRENTLY` builds a new index alongside the old one, allowing both reads and writes throughout. At the end, it takes a brief lock to swap the old index for the new one. CONCURRENTLY is slower and uses more temporary disk space but is non-disruptive.

3. **How do you detect index bloat without pgstatindex?** - Compare index size to expected size: `pg_indexes_size / n_live_tup` gives average bytes per row in indexes. For a text column with an average 30-char value, a healthy B-tree index should be roughly 50-100 bytes per row. If it is 400 bytes per row, the index is bloated. Also check: if the index is many times larger than the heap, that is a strong signal.

4. **Can index bloat cause incorrect query results?** - No. A bloated index still returns correct results - it just wastes I/O and memory because PostgreSQL must read more pages to find the same number of entries. Performance degrades but correctness is maintained.

5. **After a large batch delete, should you REINDEX or run VACUUM?** - If you deleted more than 30-40% of the rows in one batch, REINDEX CONCURRENTLY is usually faster and more effective than waiting for VACUUM to clean up the index. VACUUM cleans entries incrementally; REINDEX rebuilds in one pass. For ongoing steady-state deletions, regular VACUUM is sufficient.

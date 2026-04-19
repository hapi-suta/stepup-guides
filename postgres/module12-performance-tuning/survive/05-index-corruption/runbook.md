# Scenario 05 - Index Corruption

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Queries on the accounts table are returning
intermittent errors. Some lookups by account_num
fail with 'could not read block' or return wrong
results. The application team reports data inconsistencies.
```

---

## Key Concepts for Revision

- **Indexes are separate physical files** - Each index in PostgreSQL is stored as a separate file on disk, identified by its OID. The heap (table data) and each index have independent files. Corruption in an index file does not affect the actual table data - only the index's ability to locate rows correctly.

- **amcheck extension detects index corruption** - The `amcheck` extension provides `bt_index_check()` and `bt_index_parent_check()` functions that verify B-tree index structural integrity. `bt_index_check()` is a lightweight check. `bt_index_parent_check()` is more thorough but holds a heavier lock. These should be run periodically on production databases.

- **REINDEX rebuilds the index from scratch** - `REINDEX INDEX idx_name` drops the corrupted index structure and rebuilds it by scanning the heap table. The rebuilt index is guaranteed consistent with the table data. `REINDEX CONCURRENTLY` can rebuild without locking writes but takes longer.

- **pg_relation_filepath() maps objects to disk files** - This function returns the relative path (from PGDATA) to the physical file backing a table or index. Useful for correlating database objects to OS-level files during corruption investigations.

- **How corruption happens** - Common causes: storage hardware failures (bad sectors, controller bugs), OS crashes during writes, filesystem bugs, someone manually editing data files, incomplete backups restored incorrectly. PostgreSQL checksums (enabled at initdb) can detect page-level corruption proactively.

---

## Diagnostic Steps

### Step 1 - Try a query that uses the index

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT * FROM chaos5_accounts WHERE account_num = 'ACC-000001';
```

You may see an error like:

```
WARNING:  could not read block 1 in file ...
ERROR:  invalid page in block 1 of relation ...
```

Or the query may return wrong results silently if the corruption is in leaf pages.

### Step 2 - Install the amcheck extension

```sql
CREATE EXTENSION IF NOT EXISTS amcheck;
```

Expected output:

```
CREATE EXTENSION
```

The `amcheck` extension ships with PostgreSQL but must be explicitly created in each database.

### Step 3 - Run a B-tree integrity check on the suspect index

```sql
SELECT bt_index_check('idx_chaos5_account_num');
```

Expected output (yours will differ):

```
ERROR:  index "idx_chaos5_account_num" contains unexpected zero page at block 1
```

The error confirms the index is corrupted. The exact message depends on which bytes were damaged.

### Step 4 - Verify the table data is intact

The table (heap) is a separate file. Check that the data is still readable with a sequential scan:

```sql
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SELECT count(*) FROM chaos5_accounts;
```

Expected output:

```
 count
-------
  5000
(1 row)
```

All 5000 rows are intact. Only the index is corrupted.

```sql
RESET enable_indexscan;
RESET enable_bitmapscan;
```

---

## Resolution

### Step 1 - REINDEX the corrupted index

```sql
REINDEX INDEX idx_chaos5_account_num;
```

Expected output:

```
REINDEX
```

This drops the corrupted index structure and rebuilds it by scanning all rows in `chaos5_accounts`. The new index is consistent with the current table data.

### Step 2 - Verify the rebuilt index passes amcheck

```sql
SELECT bt_index_check('idx_chaos5_account_num');
```

Expected output:

```
 bt_index_check
----------------

(1 row)
```

No error means the index structure is valid. A NULL return is the expected success response.

### Step 3 - Verify queries work through the index

```sql
EXPLAIN (ANALYZE) SELECT * FROM chaos5_accounts WHERE account_num = 'ACC-000001';
```

Expected output (yours will differ):

```
                            QUERY PLAN
-------------------------------------------------------------------
 Index Scan using idx_chaos5_account_num on chaos5_accounts  (cost=...)
   Index Cond: ((account_num)::text = 'ACC-000001'::text)
   Planning Time: 0.100 ms
   Execution Time: 0.030 ms
(4 rows)
```

The query uses the index and returns results without errors.

### Step 4 - Run a broader check on all indexes in the table

```sql
SELECT bt_index_check(c.oid)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'chaos5_accounts'::regclass;
```

Expected output (yours will differ):

```
 bt_index_check
----------------

(2 rows)
```

All indexes on the table pass integrity checks.

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- amcheck extension exists
- bt_index_check passes on idx_chaos5_account_num
- Query using the index returns correct results
- No errors in query execution

---

## Interview Discussion Points

1. **How would you detect index corruption proactively before users report errors?** - Enable data checksums at `initdb` time (`initdb --data-checksums`). PostgreSQL will then verify page checksums on every read and log warnings for corrupted pages. Schedule periodic `amcheck` runs via cron or pg_cron. Monitor the PostgreSQL log for `invalid page` warnings. Use `pg_stat_database` to watch `checksum_failures` (PG 12+).

2. **What is the difference between REINDEX and REINDEX CONCURRENTLY?** - `REINDEX` takes an exclusive lock on the table, blocking all writes during the rebuild. It is faster but causes downtime. `REINDEX CONCURRENTLY` builds a new index alongside the old one without blocking writes, then swaps them atomically. It takes longer and uses more disk space temporarily, but is suitable for production tables that cannot tolerate write locks.

3. **Can table (heap) data also be corrupted?** - Yes. Heap corruption is more serious because the actual data is lost, not just the lookup structure. `pg_amcheck` (PG 14+ command-line tool) can check both heap and index pages. Heap corruption typically requires restoring from backup. There is no equivalent of REINDEX for heap data.

4. **Should you enable data checksums on existing clusters?** - PG 12+ supports `pg_checksums --enable` on a stopped cluster. This is a one-time operation that writes checksums to every data page. It requires downtime proportional to database size. For large databases, plan for the I/O impact. Once enabled, there is a small (1-2%) CPU overhead on every page read/write.

5. **What if REINDEX fails because the table itself is corrupted?** - If the heap is also corrupted, REINDEX will fail because it cannot read the source rows. In that case, you need to restore from backup. If only a few pages are corrupted, `pg_surgery` extension (PG 14+) can mark specific heap tuples as dead, allowing you to salvage the remaining data before a full restore.

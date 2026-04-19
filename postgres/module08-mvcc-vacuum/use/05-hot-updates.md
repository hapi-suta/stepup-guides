# Use Exercise 05 - HOT Updates

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Demonstrate HOT (Heap-Only Tuple) updates. Show how fillfactor affects HOT update rate and understand why HOT updates reduce bloat and index work.

---

> **Background: What is a HOT update?**
> A HOT update is a special optimization PostgreSQL uses when updating a row that has no indexed columns changing. Instead of writing the new tuple to a different page (which would require updating every index), PostgreSQL writes the new tuple to the same page as the old one and links them with a chain pointer. This means no index update is needed. HOT updates only work when there is free space on the current page - which is why fillfactor matters.

---

## Setup

```bash
ssh -i ~/student.pem ec2-user@<NODE1_IP>
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Create two tables: one default fillfactor, one with 70% fillfactor

Default fillfactor (100%) fills pages completely. No room for HOT updates.

```sql
CREATE TABLE hot_test_full (
  id      serial PRIMARY KEY,
  indexed_col  text,
  payload text
) WITH (fillfactor = 100);
```

70% fillfactor leaves 30% of each page empty - space for HOT updates.

```sql
CREATE TABLE hot_test_hot (
  id           serial PRIMARY KEY,
  indexed_col  text,
  payload      text
) WITH (fillfactor = 70);
```

Add a non-primary-key index on indexed_col for both tables (this index does NOT need updating during a HOT update of payload):

```sql
CREATE INDEX ON hot_test_full (indexed_col);
```

```sql
CREATE INDEX ON hot_test_hot (indexed_col);
```

---

## Task 2 - Insert the same data into both tables

```sql
INSERT INTO hot_test_full (indexed_col, payload)
SELECT 'cat_' || (i % 10), 'data_' || i
FROM generate_series(1, 5000) AS i;
```

```sql
INSERT INTO hot_test_hot (indexed_col, payload)
SELECT 'cat_' || (i % 10), 'data_' || i
FROM generate_series(1, 5000) AS i;
```

---

## Task 3 - Check baseline stats

```sql
SELECT relname,
       n_tup_upd,
       n_tup_hot_upd,
       n_live_tup,
       n_dead_tup
FROM pg_stat_user_tables
WHERE relname IN ('hot_test_full', 'hot_test_hot')
ORDER BY relname;
```

Both tables should show 0 updates so far.

---

## Task 4 - Update only the non-indexed column (payload) on both tables

These updates change `payload` but NOT `indexed_col`. PostgreSQL will attempt HOT updates because no indexed column changed.

```sql
UPDATE hot_test_full SET payload = payload || '_v2';
```

```sql
UPDATE hot_test_hot SET payload = payload || '_v2';
```

---

## Task 5 - Compare HOT update rates

```sql
SELECT relname,
       n_tup_upd       AS total_updates,
       n_tup_hot_upd   AS hot_updates,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 2) AS hot_pct,
       n_dead_tup
FROM pg_stat_user_tables
WHERE relname IN ('hot_test_full', 'hot_test_hot')
ORDER BY relname;
```

Expected outcome: `hot_test_hot` should show a higher `hot_pct` than `hot_test_full`.

`hot_test_full` has fillfactor=100 - pages are packed, so there is no room on the same page for the new tuple version. PostgreSQL cannot do HOT - it writes the new version to a different page and must update the index.

`hot_test_hot` has fillfactor=70 - 30% of each page is reserved. PostgreSQL can write the new tuple version on the same page as the old one. No index update is needed.

---

## Task 6 - Check index size to see the difference

```sql
SELECT relname,
       pg_size_pretty(pg_indexes_size(relid)) AS index_size,
       pg_size_pretty(pg_relation_size(relid)) AS heap_size
FROM pg_stat_user_tables
WHERE relname IN ('hot_test_full', 'hot_test_hot')
ORDER BY relname;
```

**Question:** Is the index size different between the two tables? HOT updates avoid adding new entries to the index, so `hot_test_hot` indexes should grow less after the updates.

---

## Task 7 - Run a second round of updates to amplify the difference

```sql
UPDATE hot_test_full SET payload = payload || '_v3';
```

```sql
UPDATE hot_test_hot SET payload = payload || '_v3';
```

```sql
SELECT relname,
       n_tup_upd,
       n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 2) AS hot_pct,
       n_dead_tup
FROM pg_stat_user_tables
WHERE relname IN ('hot_test_full', 'hot_test_hot')
ORDER BY relname;
```

**Question:** After the second round of updates, what happened to the hot_pct for `hot_test_hot`? Did it change? (Hint: pages may now be full even with fillfactor=70 - VACUUM is needed to reclaim space for future HOT updates.)

---

## Task 8 - VACUUM and run a third round

Run VACUUM to reclaim the dead tuples and make space available again for HOT:

```sql
VACUUM hot_test_hot;
```

```sql
UPDATE hot_test_hot SET payload = payload || '_v4';
```

```sql
SELECT relname,
       n_tup_upd,
       n_tup_hot_upd,
       round(100.0 * n_tup_hot_upd / NULLIF(n_tup_upd, 0), 2) AS hot_pct
FROM pg_stat_user_tables
WHERE relname = 'hot_test_hot';
```

**Question:** Did HOT rate recover after VACUUM freed up space on pages?

---

## Task 9 - Understand the trade-off

fillfactor=70 means each page is initially only 70% full. This means:

- Each INSERT uses more disk space (30% of every page is reserved)
- But updates to non-indexed columns stay on the same page (HOT updates)
- Less index bloat, less I/O for high-update tables

For a table that gets many updates to non-indexed columns, fillfactor=70-80 is a good default. For insert-only tables, fillfactor=100 is more space-efficient.

---

## Cleanup

```sql
DROP TABLE hot_test_full;
```

```sql
DROP TABLE hot_test_hot;
```

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

## Key Takeaways

- HOT updates write new tuple versions to the same page as the old version - no index entry is added
- HOT only works when: the updated column is NOT indexed AND there is free space on the same page
- `fillfactor` reserves space on each page for future updates - lower fillfactor = more HOT updates
- `pg_stat_user_tables.n_tup_hot_upd` shows how many HOT updates have occurred
- VACUUM reclaims dead tuple space, restoring room for future HOT updates
- High HOT update rates mean less index bloat and lower I/O for write-heavy workloads

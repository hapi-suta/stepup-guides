# Use Exercise 06 - Visibility Map

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Use the `pg_visibility` extension to inspect the visibility map. Show how VACUUM marks pages as all-visible, and understand what the visibility map is used for.

---

> **Background: What is the visibility map?**
> PostgreSQL maintains a visibility map (VM) for every table - a compact bitmap file with one bit per heap page. If a page's bit is set in the VM, it means every tuple on that page is visible to all current and future transactions (no dead tuples, no in-progress transactions). PostgreSQL can skip these pages entirely during index-only scans and during the freeze phase of VACUUM. The VM dramatically speeds up large-table queries when most pages are already all-visible.

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

## Task 1 - Install pg_visibility

```sql
CREATE EXTENSION IF NOT EXISTS pg_visibility;
```

Expected output (yours will differ):

```
CREATE EXTENSION
```

---

## Task 2 - Create a table and populate it

```sql
CREATE TABLE vm_demo (
  id   serial PRIMARY KEY,
  val  text
);
```

```sql
INSERT INTO vm_demo (val)
SELECT 'page_' || i FROM generate_series(1, 2000) AS i;
```

---

## Task 3 - Check visibility map before VACUUM

`pg_visibility_map` returns one row per heap page. The `all_visible` column is true when every tuple on the page is visible to all transactions.

```sql
SELECT blkno, all_visible, all_frozen
FROM pg_visibility_map('vm_demo')
ORDER BY blkno
LIMIT 10;
```

Expected output (yours will differ):

```
 blkno | all_visible | all_frozen
-------+-------------+------------
     0 | f           | f
     1 | f           | f
     2 | f           | f
     3 | f           | f
     4 | f           | f
(5 rows)
```

No pages are all-visible yet. Fresh inserts are done by transactions that may still be "in progress" from older snapshots, so the VM bits are not set yet.

---

## Task 4 - Count all-visible vs not-visible pages

```sql
SELECT
  count(*)                                    AS total_pages,
  count(*) FILTER (WHERE all_visible)         AS all_visible_pages,
  count(*) FILTER (WHERE NOT all_visible)     AS not_visible_pages,
  count(*) FILTER (WHERE all_frozen)          AS all_frozen_pages
FROM pg_visibility_map('vm_demo');
```

Expected output (yours will differ):

```
 total_pages | all_visible_pages | not_visible_pages | all_frozen_pages
-------------+-------------------+-------------------+------------------
          11 |                 0 |                11 |                0
(1 row)
```

0 all-visible pages. VACUUM has not run yet.

---

## Task 5 - Run VACUUM to set visibility map bits

```sql
VACUUM vm_demo;
```

---

## Task 6 - Check visibility map after VACUUM

```sql
SELECT
  count(*)                                    AS total_pages,
  count(*) FILTER (WHERE all_visible)         AS all_visible_pages,
  count(*) FILTER (WHERE NOT all_visible)     AS not_visible_pages,
  count(*) FILTER (WHERE all_frozen)          AS all_frozen_pages
FROM pg_visibility_map('vm_demo');
```

Expected output (yours will differ):

```
 total_pages | all_visible_pages | not_visible_pages | all_frozen_pages
-------------+-------------------+-------------------+------------------
          11 |                11 |                 0 |                0
(1 row)
```

All 11 pages are now all-visible. VACUUM checked each page, confirmed all tuples are visible to all transactions, and set the VM bit.

---

## Task 7 - Update some rows and watch VM bits clear

```sql
UPDATE vm_demo SET val = val || '_changed' WHERE id <= 100;
```

```sql
SELECT
  count(*)                                AS total_pages,
  count(*) FILTER (WHERE all_visible)     AS all_visible_pages,
  count(*) FILTER (WHERE NOT all_visible) AS not_visible_pages
FROM pg_visibility_map('vm_demo');
```

Expected output (yours will differ):

```
 total_pages | all_visible_pages | not_visible_pages
-------------+-------------------+-------------------
          11 |                 9 |                 2
(1 row)
```

The pages that contained the updated rows no longer have all_visible=true because they now have dead tuples on them.

---

## Task 8 - Use pg_check_visible to inspect specific pages

You can check individual pages to see why they are not all-visible:

```sql
SELECT blkno, all_visible
FROM pg_visibility_map('vm_demo')
WHERE NOT all_visible;
```

Expected output (yours will differ):

```
 blkno | all_visible
-------+-------------
     0 | f
     1 | f
(2 rows)
```

These are the pages where the updated rows live.

---

## Task 9 - VACUUM again and watch bits restore

```sql
VACUUM vm_demo;
```

```sql
SELECT
  count(*) FILTER (WHERE all_visible) AS all_visible_pages,
  count(*) FILTER (WHERE NOT all_visible) AS not_visible_pages
FROM pg_visibility_map('vm_demo');
```

All bits should be set to all-visible again.

---

## Task 10 - Run VACUUM FREEZE and check all_frozen

`VACUUM FREEZE` marks pages as all-frozen in addition to all-visible. All-frozen pages are safe from XID wraparound and can be skipped during future freeze scans.

```sql
VACUUM FREEZE vm_demo;
```

```sql
SELECT
  count(*) FILTER (WHERE all_visible)     AS all_visible_pages,
  count(*) FILTER (WHERE all_frozen)      AS all_frozen_pages
FROM pg_visibility_map('vm_demo');
```

Expected output (yours will differ):

```
 all_visible_pages | all_frozen_pages
-------------------+------------------
                11 |               11
(1 row)
```

All pages are now both all-visible and all-frozen. VACUUM can skip these entirely in future runs.

---

## Task 11 - Understand index-only scan benefit

When all pages are all-visible, PostgreSQL can satisfy some queries from the index alone without touching the heap. Create an index and test:

```sql
CREATE INDEX ON vm_demo (val);
```

Check if the query uses an index-only scan:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT val FROM vm_demo WHERE val LIKE 'page_1%';
```

Look for "Index Only Scan" in the EXPLAIN output. If the visibility map bits are set, PostgreSQL does not need to visit the heap to verify tuple visibility - it trusts the VM.

---

## Cleanup

```sql
DROP TABLE vm_demo;
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

- The visibility map is a bitmap with one bit per heap page, stored in a separate file (`_vm` suffix)
- A page is all-visible when every tuple on it is visible to all current and future transactions
- VACUUM sets VM bits after cleaning a page; UPDATE/DELETE clears bits on modified pages
- all-visible pages can be skipped during VACUUM scans and enable index-only scans
- VACUUM FREEZE additionally sets the all-frozen bit - these pages are safe from wraparound
- `pg_visibility_map()` lets you inspect every page's VM state directly

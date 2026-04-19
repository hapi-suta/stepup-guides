# Use Exercise 03 - VACUUM FULL vs Regular VACUUM

**Module:** 08 - MVCC & Vacuum
**Node:** NODE1 only
**Database:** stepup_store
**Time:** 20-25 minutes

---

## Goal

Compare disk space before and after VACUUM vs VACUUM FULL. Measure the difference in file size and understand when each approach is appropriate.

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

## Task 1 - Create and populate a test table

```sql
CREATE TABLE vacuum_compare (
  id    serial PRIMARY KEY,
  label text,
  val   numeric
);
```

```sql
INSERT INTO vacuum_compare (label, val)
SELECT 'item_' || i, random() * 1000
FROM generate_series(1, 20000) AS i;
```

---

## Task 2 - Record the clean baseline size

```sql
SELECT
  pg_size_pretty(pg_relation_size('vacuum_compare'))            AS heap_size,
  pg_size_pretty(pg_indexes_size('vacuum_compare'))             AS index_size,
  pg_size_pretty(pg_total_relation_size('vacuum_compare'))      AS total_size;
```

Write down all three values. This is your clean starting point with 20,000 live rows.

---

## Task 3 - Delete 75% of the rows to create heavy bloat

```sql
DELETE FROM vacuum_compare WHERE id % 4 != 0;
```

Expected output (yours will differ):

```
DELETE 15000
```

Now only 5,000 rows remain but the table still holds space for all 20,000.

---

## Task 4 - Check size after delete (before any VACUUM)

```sql
SELECT
  pg_size_pretty(pg_relation_size('vacuum_compare'))       AS heap_size,
  pg_size_pretty(pg_total_relation_size('vacuum_compare')) AS total_size,
  n_live_tup,
  n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'vacuum_compare';
```

The heap_size should be close to the original 20,000-row size. The dead tuple count should be around 15,000.

---

## Task 5 - Run regular VACUUM and measure

```sql
VACUUM VERBOSE vacuum_compare;
```

Check size immediately after:

```sql
SELECT
  pg_size_pretty(pg_relation_size('vacuum_compare'))       AS heap_size_after_vacuum,
  pg_size_pretty(pg_total_relation_size('vacuum_compare')) AS total_size_after_vacuum;
```

**Question:** Did the heap size shrink? Compare to the value you recorded in Task 4.

---

## Task 6 - Verify dead tuples are gone

```sql
SELECT n_live_tup, n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'vacuum_compare';
```

Dead tuples should be 0 now. But the file is still the same size - the space is just marked free for reuse.

---

## Task 7 - Run VACUUM FULL and measure

```sql
VACUUM FULL VERBOSE vacuum_compare;
```

Expected output (yours will differ):

```
INFO:  vacuuming "public.vacuum_compare"
INFO:  "vacuum_compare": found 15000 removable, 5000 nonremovable row versions
INFO:  "vacuum_compare": page count before 111, page count after 28
VACUUM
```

Note the page count drop - "before 111, after 28" shows the physical shrink.

```sql
SELECT
  pg_size_pretty(pg_relation_size('vacuum_compare'))       AS heap_size_after_vacuum_full,
  pg_size_pretty(pg_total_relation_size('vacuum_compare')) AS total_size_after_vacuum_full;
```

---

## Task 8 - Compare all three measurements

Fill in this table based on your measurements:

| Metric | After insert (baseline) | After VACUUM | After VACUUM FULL |
|---|---|---|---|
| Heap size | ? | ? | ? |
| Total size | ? | ? | ? |
| Dead tuples | 0 | 0 | 0 |

**Question:** Why does VACUUM FULL result in a smaller file than the original 20,000-row baseline?

(Hint: the original insert left some free space in pages too. VACUUM FULL packs rows more tightly.)

---

## Task 9 - Test locking behavior

VACUUM FULL holds an exclusive lock. Demonstrate this by opening a second terminal.

In terminal 1, start VACUUM FULL on a larger dataset:

```sql
VACUUM FULL vacuum_compare;
```

In terminal 2, try to query the table while VACUUM FULL is running:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT count(*) FROM vacuum_compare;
```

**Question:** What happened? Did the query hang or complete immediately?

Once VACUUM FULL finishes in terminal 1, the query in terminal 2 will unblock. This demonstrates the exclusive lock cost.

---

## Task 10 - Check who is blocking whom

In terminal 2 (while VACUUM FULL is still running in terminal 1), run this in another connection:

```sql
SELECT blocked.pid AS blocked_pid,
       blocker.pid AS blocker_pid,
       blocked.query AS blocked_query,
       blocker.query AS blocker_query
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocker
  ON blocker.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE blocked.wait_event_type = 'Lock';
```

This shows the lock chain - VACUUM FULL is the blocker, the SELECT is the blocked query.

---

## Cleanup

```sql
DROP TABLE vacuum_compare;
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

- Regular VACUUM: dead tuples removed, space marked reusable, file size unchanged
- VACUUM FULL: table rewritten, file shrinks, but table is locked exclusively for the entire duration
- Use regular VACUUM for routine cleanup - autovacuum handles this automatically
- Use VACUUM FULL only for severe bloat on tables with acceptable downtime windows
- For production tables with zero downtime requirements, use `pg_repack` instead of VACUUM FULL

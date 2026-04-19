# Use Exercise 06 - Workload Profiling

Profile the Pulse application's workload: read vs write ratio, most frequent queries, I/O patterns, and missing index candidates.

**Server:** NODE1 only

---

## What You Will Do

Use pg_stat_statements, pg_stat_user_tables, pg_stat_user_indexes, and pg_statio_user_tables to build a complete picture of what the Pulse app is doing to the database.

---

## Setup

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Confirm Pulse is running on port 8080.

```
curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/
```

Expected output:

```
200
```

Reset all statistics so you profile from a clean baseline.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_stat_reset();"
```

Expected output:

```
 pg_stat_reset
---------------

(1 row)
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_stat_statements_reset();"
```

Expected output:

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

Wait 2-5 minutes for Pulse to generate meaningful traffic against the database, then run the profiling queries below.

---

## Step 1 - Read vs Write Ratio Per Table

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT
  relname AS table_name,
  seq_scan,
  idx_scan,
  n_tup_ins AS inserts,
  n_tup_upd AS updates,
  n_tup_del AS deletes,
  (n_tup_ins + n_tup_upd + n_tup_del) AS total_writes,
  (seq_scan + idx_scan) AS total_reads,
  CASE
    WHEN (n_tup_ins + n_tup_upd + n_tup_del) = 0 THEN 'read-only'
    WHEN (seq_scan + idx_scan) = 0 THEN 'write-only'
    ELSE round(
      ((seq_scan + idx_scan)::numeric /
       nullif(n_tup_ins + n_tup_upd + n_tup_del, 0)), 1
    ) || ':1 reads per write'
  END AS read_write_ratio
FROM pg_stat_user_tables
WHERE schemaname = 'public'
ORDER BY total_reads DESC;
```

Expected output (yours will differ):

```
   table_name   | seq_scan | idx_scan | inserts | updates | deletes | total_writes | total_reads | read_write_ratio
----------------+----------+----------+---------+---------+---------+--------------+-------------+------------------
 customers      |       12 |       85 |       0 |       0 |       0 |            0 |          97 | read-only
 products       |        8 |       42 |       0 |       0 |       0 |            0 |          50 | read-only
 orders         |        5 |       38 |       2 |       8 |       0 |           10 |          43 | 4.3:1 reads per write
 order_items    |        3 |       22 |       5 |       0 |       0 |            5 |          25 | 5.0:1 reads per write
 audit_log      |        0 |        0 |      45 |       0 |       0 |           45 |           0 | write-only
(5 rows)
```

Note which tables are read-heavy (candidates for caching and indexes) vs write-heavy (candidates for minimizing index count and tuning WAL).

---

## Step 2 - Sequential Scan Tables (Missing Index Candidates)

```sql
SELECT
  relname AS table_name,
  seq_scan,
  seq_tup_read,
  idx_scan,
  CASE WHEN seq_scan = 0 THEN 0
    ELSE round(seq_tup_read::numeric / seq_scan, 0)
  END AS avg_rows_per_seq_scan
FROM pg_stat_user_tables
WHERE schemaname = 'public'
  AND seq_scan > 0
ORDER BY seq_tup_read DESC;
```

Expected output (yours will differ):

```
  table_name  | seq_scan | seq_tup_read | idx_scan | avg_rows_per_seq_scan
--------------+----------+--------------+----------+-----------------------
 customers    |       12 |         2400 |       85 |                   200
 orders       |        5 |          250 |       38 |                    50
 products     |        8 |          400 |       42 |                    50
(3 rows)
```

`avg_rows_per_seq_scan` tells you how many rows the database reads per sequential scan. If this is large and the queries are selective (returning few rows), a missing index is likely. If this equals the table size, the scan is probably a full-table read (correct behavior for small tables or aggregate queries).

Cross-reference with pg_stat_statements to find which specific queries are causing the seq scans.

---

## Step 3 - Unused and Low-Use Indexes

```sql
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan,
  pg_size_pretty(pg_relation_size(indexname::regclass)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY idx_scan ASC, pg_relation_size(indexname::regclass) DESC;
```

Expected output (yours will differ):

```
 schemaname |  tablename   |          indexname           | idx_scan | index_size
------------+--------------+------------------------------+----------+------------
 public     | audit_log    | audit_log_pkey               |        0 | 8 kB
 public     | orders       | idx_orders_created_brin      |        0 | 8 kB
 public     | customers    | idx_customers_email_lower    |        1 | 8 kB
 public     | orders       | orders_pkey                  |       38 | 16 kB
(4 rows)
```

Indexes with `idx_scan = 0` that have been active for more than a few hours are candidates for removal. Every index has a write cost. Unused indexes slow down inserts and updates for no benefit.

---

## Step 4 - I/O Patterns - Heap vs Index Reads

```sql
SELECT
  relname AS table_name,
  heap_blks_read,
  heap_blks_hit,
  idx_blks_read,
  idx_blks_hit,
  CASE WHEN (heap_blks_read + heap_blks_hit) = 0 THEN NULL
    ELSE round(
      heap_blks_hit::numeric / (heap_blks_read + heap_blks_hit) * 100, 1
    )
  END AS heap_hit_pct,
  CASE WHEN (idx_blks_read + idx_blks_hit) = 0 THEN NULL
    ELSE round(
      idx_blks_hit::numeric / (idx_blks_read + idx_blks_hit) * 100, 1
    )
  END AS idx_hit_pct
FROM pg_statio_user_tables
WHERE schemaname = 'public'
ORDER BY (heap_blks_read + idx_blks_read) DESC;
```

Expected output (yours will differ):

```
  table_name  | heap_blks_read | heap_blks_hit | idx_blks_read | idx_blks_hit | heap_hit_pct | idx_hit_pct
--------------+----------------+---------------+---------------+--------------+--------------+-------------
 orders       |              2 |            48 |             1 |           75 |         96.0 |        98.7
 customers    |              1 |            95 |             0 |           85 |         99.0 |       100.0
 products     |              0 |            42 |             0 |           42 |        100.0 |       100.0
(3 rows)
```

`heap_hit_pct` and `idx_hit_pct` below 95% indicate tables or indexes that are being read from disk frequently. This suggests:
- `shared_buffers` is too small for the working set, or
- The data is too large to fit in cache (a hardware limitation)

Also check the Pulse Performance panel at `http://<NODE1-IP>:8080` and compare its cache hit ratio to what you calculated here. They should match.

---

## Step 5 - Most Frequent Queries from pg_stat_statements

```sql
SELECT
  calls,
  round(total_exec_time::numeric / calls, 2) AS avg_exec_ms,
  round(total_exec_time::numeric, 1) AS total_exec_ms,
  left(query, 80) AS query_snippet
FROM pg_stat_statements
WHERE userid = (SELECT oid FROM pg_roles WHERE rolname = 'postgres')
  AND calls > 0
ORDER BY calls DESC
LIMIT 10;
```

Expected output (yours will differ):

```
 calls | avg_exec_ms | total_exec_ms |                      query_snippet
-------+-------------+---------------+--------------------------------------------------
   145 |        0.12 |          17.4 | SELECT id, total_amount FROM orders WHERE status
    88 |        0.08 |           7.0 | SELECT id, name, price FROM products WHERE categ
    52 |        0.18 |           9.4 | SELECT * FROM customers WHERE id = $1
     8 |        4.20 |          33.6 | SELECT c.email, p.name, SUM(oi.quantity * oi.un
(4 rows)
```

Columns to act on:
- High `calls` with high `avg_exec_ms` = top optimization priority (multiply for highest impact)
- High `calls` with low `avg_exec_ms` = good, but check if an index is keeping it fast
- Low `calls` with very high `avg_exec_ms` = batch/report queries, tune separately

---

## Step 6 - Write Your Profiling Report

Based on what you found, fill in this template before leaving the exercise.

```
## stepup_store Workload Profile - [DATE]

### Read/Write Ratio
- Most read-heavy table: ____________ (__ reads per write)
- Most write-heavy table: ____________

### Cache Performance
- Overall heap hit ratio: ____________%
- Tables with poor hit ratio: ____________

### Missing Index Candidates
- Tables with high seq_tup_read and selective queries: ____________

### Unused Indexes (removal candidates)
- ____________

### Top Query by Call Count
- Query: ____________
- Calls: __ avg time: __ ms

### Top Query by Total Time
- Query: ____________
- Total time: __ ms
```

```
\q
```

```
exit
```

---

## Checkpoint

- [ ] You reset stats and waited for Pulse to generate traffic
- [ ] You identified the read vs write ratio for each table
- [ ] You found at least one seq scan table and checked if it needs an index
- [ ] You identified any unused indexes
- [ ] You measured heap and index hit percentages
- [ ] Your profiling report is filled in

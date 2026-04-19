# Scenario 01 - Missing Index

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Customer order lookup queries are running slow.
The Pulse dashboard is timing out when loading customer order history.
Queries that used to take <1ms now take hundreds of milliseconds.
```

---

## Key Concepts for Revision

- **Sequential scan vs index scan** - A sequential scan reads every row in the table from start to finish. For a table with 80,000 rows, PostgreSQL must read all 80,000 rows even if only 800 belong to the customer you are looking for. An index scan follows a B-Tree structure directly to the matching rows - far fewer pages read.

- **Why indexes can disappear** - An index can be dropped explicitly (`DROP INDEX`), removed by `REINDEX` if it fails partway through, or invalidated during schema migrations. Monitoring query execution time over time catches this before it becomes a crisis.

- **EXPLAIN ANALYZE shows the problem** - Before fixing anything, run `EXPLAIN ANALYZE` on the slow query. `Seq Scan` in the plan confirms there is no index being used. `Rows Removed by Filter` shows how many rows were read and discarded.

- **CREATE INDEX CONCURRENTLY** - In production, `CREATE INDEX CONCURRENTLY` builds the index without taking an Access Share Lock that would block writes. Regular `CREATE INDEX` briefly locks the table. For active tables, always use CONCURRENTLY.

- **pg_stat_user_indexes** - The view `pg_stat_user_indexes` shows index usage counts. An index with zero scans since the last statistics reset may be unused. An index that used to have high scan counts and now has zero has been dropped or recreated.

---

## Diagnostic Steps

### Step 1 - Connect and run the slow query with EXPLAIN ANALYZE

Log in to the server:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Open psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Run the customer order lookup query with the query plan:

```sql
EXPLAIN ANALYZE SELECT * FROM orders_chaos WHERE customer_id = 5;
```

Expected output (yours will differ):

```
 Seq Scan on orders_chaos  (cost=0.00..1820.00 rows=800 width=60)
                            (actual time=0.050..180.000 rows=800 loops=1)
   Filter: (customer_id = 5)
   Rows Removed by Filter: 79200
 Planning Time: 0.150 ms
 Execution Time: 182.000 ms
```

`Seq Scan` confirms no index. `Rows Removed by Filter: 79200` shows how much wasted work the database is doing.

### Step 2 - Check what indexes exist on the table

```sql
SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'orders_chaos';
```

Expected output (yours will differ):

```
   indexname    |                     indexdef
----------------+-------------------------------------------------
 orders_chaos_pkey | CREATE UNIQUE INDEX orders_chaos_pkey ON orders_chaos USING btree (order_id)
(1 row)
```

Only the primary key index exists. The index on `customer_id` is missing.

### Step 3 - Check the table size to understand impact

```sql
SELECT pg_size_pretty(pg_total_relation_size('orders_chaos')) AS table_size;
```

Expected output (yours will differ):

```
 table_size
------------
 6432 kB
(1 row)
```

Exit psql:

```sql
\q
```

---

## Resolution

### Step 1 - Create the missing index

Still as the postgres user:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Create the index. Use CONCURRENTLY in production to avoid blocking writes:

```sql
CREATE INDEX CONCURRENTLY idx_orders_chaos_customer ON orders_chaos (customer_id);
```

Expected output:

```
CREATE INDEX
```

### Step 2 - Confirm the index was created

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders_chaos';
```

Expected output (yours will differ):

```
          indexname           |                     indexdef
------------------------------+--------------------------------------------------
 orders_chaos_pkey            | CREATE UNIQUE INDEX orders_chaos_pkey ON ...
 idx_orders_chaos_customer    | CREATE INDEX idx_orders_chaos_customer ON orders_chaos USING btree (customer_id)
(2 rows)
```

### Step 3 - Verify the query now uses the index

```sql
EXPLAIN ANALYZE SELECT * FROM orders_chaos WHERE customer_id = 5;
```

Expected output (yours will differ):

```
 Bitmap Heap Scan on orders_chaos  (cost=18.00..850.00 rows=800 width=60)
                                    (actual time=0.500..2.200 rows=800 loops=1)
   Recheck Cond: (customer_id = 5)
   ->  Bitmap Index Scan on idx_orders_chaos_customer  (cost=0.00..17.80 rows=800 width=0)
         Index Cond: (customer_id = 5)
 Planning Time: 0.250 ms
 Execution Time: 2.400 ms
```

Execution time dropped from ~182ms to ~2ms. The `Bitmap Index Scan` confirms the index is being used.

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script from the survive directory:

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- `orders_chaos` table exists
- Index `idx_orders_chaos_customer` exists on `orders_chaos`
- EXPLAIN plan for customer query does not contain "Seq Scan"

---

## Interview Discussion Points

1. **How do you detect a missing index in production without being told there is a performance problem?** - Monitor `pg_stat_statements` for queries with high `mean_exec_time` or high `total_exec_time`. Set up alerts on slow query logs (`log_min_duration_statement`). Track the `calls` and `total_exec_time` columns over time - a query that suddenly gets slower without more calls suggests a plan change like a dropped index.

2. **When would you NOT create an index on a column that appears in many WHERE clauses?** - If the column has very low cardinality (few distinct values), like a boolean or a status column with 3 possible values, an index may not help. PostgreSQL's planner estimates that fetching 30% of the table via an index is slower than a sequential scan due to random I/O. Partial indexes (WHERE status = 'pending') work better for low-cardinality columns where you only care about specific values.

3. **What is the difference between CREATE INDEX and CREATE INDEX CONCURRENTLY?** - Regular `CREATE INDEX` takes an `AccessShareLock` that prevents writes during the build. On a busy table, this means a maintenance window. `CREATE INDEX CONCURRENTLY` builds the index in the background, requiring only brief locks to swap the new index into place. The tradeoff is that CONCURRENTLY takes longer to complete and cannot be run inside a transaction.

4. **Can you add an index to a table without a downtime window?** - Yes, using `CREATE INDEX CONCURRENTLY`. The index is built while normal reads and writes continue. If the concurrent build fails, it leaves an `INVALID` index that must be dropped. Check `pg_indexes` for `valid = false` after a concurrent build.

5. **How do you find all unused indexes in a database?** - Query `pg_stat_user_indexes WHERE idx_scan = 0`. Be aware that `idx_scan` resets to 0 after `pg_stat_reset()` or a server restart. Allow the server to run under normal load for at least one full business cycle before trusting these numbers as "unused".

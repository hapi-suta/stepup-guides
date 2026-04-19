# Scenario 02 - Missing Index on orders Table

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Orders page loading very slowly.
Lookups by order ID are timing out in the application.
The development team ran a migration script earlier today.
Something may have gone wrong.
```

---

## Key Concepts for Revision

- **Primary key = unique constraint + index** - A primary key in PostgreSQL is two things at once: a NOT NULL UNIQUE constraint on the column, and a B-tree index that enforces it. Dropping the constraint also drops the index. Without the index, every lookup by `orders.id` becomes a sequential scan of the entire table.

- **EXPLAIN to diagnose** - Before touching anything, run EXPLAIN on the slow query. A Seq Scan on orders for a single-row lookup is the immediate signal that the primary key index is missing.

- **pg_indexes view** - `SELECT * FROM pg_indexes WHERE tablename = 'orders'` shows every index on the table. Missing a row with `indexname LIKE '%pkey'` is a clear indicator.

- **Recreating a primary key while the table is in use** - `ALTER TABLE orders ADD PRIMARY KEY (id)` acquires an `ACCESS EXCLUSIVE` lock, blocking all reads and writes until the index build completes. On large tables, use `CREATE UNIQUE INDEX CONCURRENTLY` first to build the index without blocking, then `ALTER TABLE orders ADD CONSTRAINT orders_pkey PRIMARY KEY USING INDEX idx_orders_id_unique` to attach it.

- **Foreign key cascade effects** - If `order_items.order_id` references `orders.id`, dropping the primary key on orders may also drop the foreign key constraint (depending on CASCADE settings). Check for orphaned foreign keys after restoring the primary key.

---

## Diagnostic Steps

### Step 1 - Run EXPLAIN on the slow query

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
EXPLAIN SELECT * FROM orders WHERE id = 1;
```

Expected output (yours will differ):

```
                      QUERY PLAN
-------------------------------------------------------
 Seq Scan on orders  (cost=0.00..12.50 rows=1 width=72)
   Filter: (id = 1)
(2 rows)
```

Seq Scan on a primary key lookup = missing index.

### Step 2 - Check what indexes exist on orders

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
   indexname    |                  indexdef
----------------+----------------------------------------------
 idx_orders_status | CREATE INDEX idx_orders_status ON orders ...
(1 row)
```

The `orders_pkey` row is missing. Primary key index was dropped.

### Step 3 - Check for primary key constraint

```sql
SELECT conname, contype FROM pg_constraint WHERE conrelid = 'orders'::regclass;
```

Expected output (yours will differ):

```
 conname | contype
---------+---------
(0 rows)
```

No constraints at all on orders. Both the PK constraint and its index are gone.

```sql
\q
```

---

## Resolution

### Step 1 - Recreate the primary key constraint

For the small orders table in this lab, a direct `ADD PRIMARY KEY` is safe.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER TABLE orders ADD PRIMARY KEY (id);"
```

Expected output:

```
ALTER TABLE
```

If the table were large (millions of rows), use CONCURRENTLY to avoid locking:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "CREATE UNIQUE INDEX CONCURRENTLY idx_orders_id_unique ON orders(id);"
```

Then attach it:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER TABLE orders ADD CONSTRAINT orders_pkey PRIMARY KEY USING INDEX idx_orders_id_unique;"
```

### Step 2 - Verify the index exists

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders' AND indexname LIKE '%pkey';"
```

Expected output:

```
  indexname   |                      indexdef
--------------+----------------------------------------------
 orders_pkey  | CREATE UNIQUE INDEX orders_pkey ON orders USING btree (id)
(1 row)
```

### Step 3 - Confirm EXPLAIN now shows index scan

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "EXPLAIN SELECT * FROM orders WHERE id = 1;"
```

Expected output (yours will differ):

```
                                  QUERY PLAN
------------------------------------------------------------------------------
 Index Scan using orders_pkey on orders  (cost=0.14..8.16 rows=1 width=72)
   Index Cond: (id = 1)
(2 rows)
```

### Step 4 - Verify foreign key constraints

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT conname, contype, confrelid::regclass FROM pg_constraint WHERE conrelid = 'order_items'::regclass;"
```

Confirm the foreign key from order_items back to orders is still present.

```bash
exit
```

---

## Validation

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- orders.id has a primary key or unique index
- Lookup by orders.id uses index scan
- Can query orders table
- order_items foreign key to orders is intact

---

## Interview Discussion Points

1. **How do you add a primary key to a large table without downtime?** - Use `CREATE UNIQUE INDEX CONCURRENTLY` to build the index in the background while the table remains readable and writable. This takes longer but does not block. Once the index is built, use `ALTER TABLE ... ADD CONSTRAINT ... PRIMARY KEY USING INDEX` to attach it - this step does take a brief exclusive lock, but it is very fast since the index is already built.

2. **What is the difference between a primary key and a unique index?** - A primary key adds both a NOT NULL constraint and a unique B-tree index. A unique index only enforces uniqueness - the column can still be NULL (and multiple NULLs are allowed because NULL != NULL). Primary keys are used by foreign key constraints in other tables.

3. **Can a table have no indexes at all? What are the consequences?** - Yes. A heap table with no indexes is called a "heap-only" table. All lookups require a full sequential scan. Inserts are fast (no index maintenance), but any SELECT with a WHERE clause is O(n) in the row count. This is acceptable for tiny lookup tables but catastrophic for growing tables.

4. **How would you detect a missing index across all tables in a database?** - Query `pg_stat_user_tables` for tables where `seq_scan` is high and `idx_scan` is low. Cross-reference with `pg_statio_user_tables` for high `heap_blks_read`. Then check those tables' column statistics to see which columns are queried often but have no index.

5. **After restoring the primary key, is there anything else to check?** - Yes: (1) check that foreign keys in child tables still reference the restored constraint, (2) run ANALYZE on the table to refresh statistics, (3) check pg_stat_user_tables to confirm idx_scan starts climbing as queries use the new index, (4) verify application query latency returned to normal.

# Module 14 - Table Partitioning
## Guide 03: Partition Indexes, Constraints, and Performance

**Objective:** Create indexes on partitioned tables, understand how indexes propagate to partitions, work with unique constraints that include the partition key, understand foreign key limitations, and compare query performance between partitioned and non-partitioned tables.

**Time:** 35-40 minutes

**Prerequisites:**
- Completed Guide 01 and 02
- `orders_partitioned` table with monthly partitions for 2024 and 2025
- `stepup_store` database with data in the original `orders` table

---

## 1. How Indexes Work on Partitioned Tables

In a non-partitioned table, you create one index. In a partitioned table, you create one index definition on the parent - PostgreSQL automatically creates a matching index on each existing partition, and on any new partition you create in the future.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

First, check whether the partitioned table has any indexes right now:

```sql
SELECT indexname, tablename
FROM pg_indexes
WHERE tablename LIKE 'orders_partitioned%'
   OR tablename LIKE 'orders_202%'
ORDER BY tablename, indexname;
```

Expected output (yours will differ):

```
 indexname | tablename
-----------+-----------
(0 rows)
```

No indexes yet. Create an index on `customer_id` at the parent level. The `ON ONLY` clause is NOT used here - you want it to propagate to all partitions:

```sql
CREATE INDEX idx_orders_part_customer
    ON orders_partitioned (customer_id);
```

Expected output (yours will differ - this may take a moment):

```
CREATE INDEX
```

Now check how many indexes were created:

```sql
SELECT indexname, tablename
FROM pg_indexes
WHERE tablename LIKE 'orders_partitioned%'
   OR tablename LIKE 'orders_202%'
ORDER BY tablename, indexname;
```

Expected output (yours will differ):

```
         indexname              |    tablename
--------------------------------+------------------
 orders_2024_02_customer_id_idx | orders_2024_02
 orders_2024_03_customer_id_idx | orders_2024_03
 orders_2024_04_customer_id_idx | orders_2024_04
 ...
 orders_partitioned_customer... | orders_partitioned
(18 rows)
```

One index definition on the parent created one index on every partition automatically. If you add a new partition tomorrow, it will also automatically get this index.

> **Concept - Index propagation**
> When you create an index on a partitioned table without `ON ONLY`, PostgreSQL creates the index on the parent AND on each child partition. The parent-level index is called a "partitioned index" - it is a logical wrapper that the planner uses. The actual work happens on the per-partition indexes. When you add a new partition, the partition automatically inherits all indexes from the parent. This is one of the major advantages of declarative partitioning over inheritance partitioning, where you had to create indexes on each child manually.

Create an index on `status` and `order_date` together (composite index):

```sql
CREATE INDEX idx_orders_part_status_date
    ON orders_partitioned (status, order_date);
```

Expected output:

```
CREATE INDEX
```

Create an index only on a specific partition (not the parent). Sometimes you need a partition-specific index for a query pattern unique to that partition:

```sql
CREATE INDEX idx_orders_2024_12_region
    ON orders_2024_12 (region);
```

Expected output:

```
CREATE INDEX
```

This index exists only on `orders_2024_12`. It was not propagated to other partitions because you created it directly on the child table, not the parent.

---

## 2. Unique Constraints on Partitioned Tables

This is where partitioned tables have an important restriction: **unique constraints and primary keys MUST include the partition key column.**

Try creating a unique constraint on `order_id` alone (without `order_date`):

```sql
ALTER TABLE orders_partitioned
    ADD CONSTRAINT uq_orders_part_id UNIQUE (order_id);
```

Expected output:

```
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  UNIQUE constraint on table "orders_partitioned" lacks column "order_date" which is part of the partition key.
```

The error is clear. Now create the unique constraint including the partition key:

```sql
ALTER TABLE orders_partitioned
    ADD CONSTRAINT uq_orders_part_id_date UNIQUE (order_id, order_date);
```

Expected output:

```
ALTER TABLE
```

> **Concept - Why unique constraints must include the partition key**
> PostgreSQL enforces unique constraints per-partition. Each child table checks uniqueness only within its own rows. If you had a unique constraint on `order_id` alone, two rows with the same `order_id` but different `order_date` values could land in different partitions and PostgreSQL would not catch the duplicate. By requiring the partition key in the constraint, you ensure uniqueness is meaningful: the same `(order_id, order_date)` combination can only appear once across the entire partitioned table (because a given `order_date` can only route to one partition). This limitation also applies to PRIMARY KEY constraints.

Try to add a primary key on `order_id` alone to confirm the same restriction:

```sql
ALTER TABLE orders_partitioned
    ADD CONSTRAINT pk_orders_partitioned PRIMARY KEY (order_id);
```

Expected output:

```
ERROR:  unique constraint on partitioned table must include all partitioning columns
DETAIL:  PRIMARY KEY constraint on table "orders_partitioned" lacks column "order_date" which is part of the partition key.
```

Add a primary key that includes the partition key:

```sql
ALTER TABLE orders_partitioned
    ADD CONSTRAINT pk_orders_partitioned PRIMARY KEY (order_id, order_date);
```

Expected output:

```
ALTER TABLE
```

Verify the constraint exists on the parent and all partitions:

```sql
SELECT conname, contype, conrelid::regclass AS table_name
FROM pg_constraint
WHERE conname LIKE 'pk_orders%'
ORDER BY table_name;
```

Expected output (yours will differ):

```
         conname          | contype |    table_name
--------------------------+---------+------------------
 pk_orders_partitioned    |   p     | orders_partitioned
 orders_2024_02_pkey      |   p     | orders_2024_02
 orders_2024_03_pkey      |   p     | orders_2024_03
 ...
(17 rows)
```

---

## 3. Foreign Keys with Partitioned Tables

Foreign keys TO a partitioned table have restrictions. A table can reference a partitioned table only if the foreign key includes the partition key.

Create a test table that references the partitioned orders table:

```sql
CREATE TABLE order_notes (
    note_id    serial PRIMARY KEY,
    order_id   integer NOT NULL,
    order_date date    NOT NULL,
    note_text  text
);
```

Add a foreign key that includes the partition key (`order_date`):

```sql
ALTER TABLE order_notes
    ADD CONSTRAINT fk_order_notes_order
    FOREIGN KEY (order_id, order_date)
    REFERENCES orders_partitioned (order_id, order_date);
```

Expected output:

```
ALTER TABLE
```

Try a foreign key that omits the partition key:

```sql
CREATE TABLE order_notes_bad (
    note_id  serial PRIMARY KEY,
    order_id integer NOT NULL,
    FOREIGN KEY (order_id) REFERENCES orders_partitioned (order_id)
);
```

Expected output:

```
ERROR:  there is no unique constraint matching given keys for referenced table "orders_partitioned"
```

> **Concept - Foreign keys and partitioned tables**
> Before PostgreSQL 12, foreign keys TO a partitioned table were not supported at all. PG12 added support, but with the restriction that the referenced column(s) must form a unique key that includes the partition key - which means your application must carry the partition key through to the referencing table. This is a real design constraint. If your application only knows `order_id` and not `order_date`, you cannot use a foreign key to a partitioned table. In that case, you either keep the foreign key relationship on the non-partitioned version, or enforce integrity at the application level.

Clean up the test objects:

```sql
DROP TABLE order_notes;
```

```sql
DROP TABLE order_notes_bad;
```

---

## 4. Performance Comparison: Partitioned vs Non-Partitioned

Now compare query performance between the original non-partitioned `orders` table and the `orders_partitioned` table. First, load the 2024 data into the partitioned table so there is actual data to compare:

```sql
INSERT INTO orders_partitioned
SELECT * FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
INSERT 0 487643
```

Check the row count loaded:

```sql
SELECT COUNT(*) FROM orders_partitioned;
```

Expected output (yours will differ):

```
 count
--------
 487643
(1 row)
```

Run EXPLAIN ANALYZE on the non-partitioned table for a one-month filter:

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders
WHERE order_date >= '2024-06-01' AND order_date < '2024-07-01';
```

Expected output (yours will differ):

```
                                      QUERY PLAN
-------------------------------------------------------------------------------------
 Aggregate  (cost=12841.00..12841.01 rows=1 width=8) (actual time=89.432..89.433 rows=1 loops=1)
   ->  Seq Scan on orders  (cost=0.00..12823.50 rows=7000 width=0)
         Filter: ((order_date >= '2024-06-01'::date) AND (order_date < '2024-07-01'::date))
         Rows Removed by Filter: 1475300
 Planning Time: 0.412 ms
 Execution Time: 89.891 ms
```

Now run the same query against the partitioned table:

```sql
EXPLAIN ANALYZE
SELECT COUNT(*) FROM orders_partitioned
WHERE order_date >= '2024-06-01' AND order_date < '2024-07-01';
```

Expected output (yours will differ):

```
                                      QUERY PLAN
-------------------------------------------------------------------------------------
 Aggregate  (cost=1283.45..1283.46 rows=1 width=8) (actual time=8.234..8.234 rows=1 loops=1)
   ->  Seq Scan on orders_2024_06 orders_partitioned_1  (cost=0.00..1276.50 rows=6500 width=0)
 Planning Time: 2.341 ms
 Execution Time: 8.891 ms
```

The partitioned table scanned only `orders_2024_06` (one partition, ~1/12th the data). Execution time dropped from ~90ms to ~9ms for this workload. Planning time increased slightly because the planner must evaluate 18 partition bounds, but the execution savings are substantial.

> **Concept - When partitioning helps vs hurts performance**
> Partitioning helps when: (1) queries regularly filter by the partition key, and (2) those filters eliminate large portions of the data. Partitioning can hurt when: (1) queries never filter by the partition key (all partitions scanned every time), (2) there are too many partitions and planning overhead becomes significant, or (3) the table is too small - partitioning overhead is not worth it for tables under ~10 million rows. The break-even point is roughly when a full table scan costs more than scanning 1-2 partitions plus planning overhead.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

You have completed Guide 03. Verify you understand the following:

- [ ] You can create an index on a partitioned parent table and understand it propagates to all partitions automatically
- [ ] You can create a partition-specific index directly on a child table when needed
- [ ] You can explain why unique constraints on partitioned tables must include the partition key
- [ ] You can add a PRIMARY KEY constraint that satisfies the partition key requirement
- [ ] You can add a FOREIGN KEY that references a partitioned table (with partition key included)
- [ ] You understand that foreign keys to partitioned tables were not supported before PG12
- [ ] You can use EXPLAIN ANALYZE to measure and compare query performance between partitioned and non-partitioned tables
- [ ] You can articulate when partitioning helps and when it hurts performance

---

Proceed to **Guide 04 - Partition Maintenance**

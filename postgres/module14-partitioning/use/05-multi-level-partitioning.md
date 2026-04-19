# Exercise 05: Multi-Level Partitioning

**Duration:** 25 minutes
**Objective:** Create a two-level partitioned table - RANGE by `order_date` at the top level, LIST by `status` at the second level. Verify pruning works at both levels.

**Prerequisites:**
- Module 14 Guides 01-04 complete
- `stepup_store` database

---

## Background

PostgreSQL supports sub-partitioning: each partition of a partitioned table can itself be partitioned. This is called two-level (or multi-level) partitioning. A typical use case is range-by-date at the top level combined with list-by-status or list-by-region at the second level.

Multi-level partitioning enables pruning at two levels: a query filtering on both `order_date` and `status` can prune to a single sub-partition out of potentially dozens. The trade-off is management complexity - you now have partitions * sub-partitions tables to manage.

In this exercise you build a two-level structure:
- Level 1: RANGE on `order_date` (quarterly, not monthly, to keep the exercise manageable)
- Level 2: LIST on `status` (5 sub-partitions per quarter)

---

## Step 1: Create the Top-Level Partitioned Table

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Create the top-level partitioned table with quarterly RANGE partitioning:

```sql
CREATE TABLE orders_multilevel (
    order_id     integer       NOT NULL,
    customer_id  integer,
    order_date   date          NOT NULL,
    status       varchar(20)   NOT NULL,
    total_amount numeric(10,2),
    region       varchar(50)
) PARTITION BY RANGE (order_date);
```

Expected output:

```
CREATE TABLE
```

---

## Step 2: Create Quarterly Top-Level Partitions

Each quarterly partition is itself partitioned by `status`. The `PARTITION BY LIST (status)` clause on the partition definition makes it a sub-partitioned partition:

Create Q1 2024 as a sub-partitioned table:

```sql
CREATE TABLE orders_ml_2024_q1
    PARTITION OF orders_multilevel
    FOR VALUES FROM ('2024-01-01') TO ('2024-04-01')
    PARTITION BY LIST (status);
```

Expected output:

```
CREATE TABLE
```

Create Q2 2024:

```sql
CREATE TABLE orders_ml_2024_q2
    PARTITION OF orders_multilevel
    FOR VALUES FROM ('2024-04-01') TO ('2024-07-01')
    PARTITION BY LIST (status);
```

Create Q3 2024:

```sql
CREATE TABLE orders_ml_2024_q3
    PARTITION OF orders_multilevel
    FOR VALUES FROM ('2024-07-01') TO ('2024-10-01')
    PARTITION BY LIST (status);
```

Create Q4 2024:

```sql
CREATE TABLE orders_ml_2024_q4
    PARTITION OF orders_multilevel
    FOR VALUES FROM ('2024-10-01') TO ('2025-01-01')
    PARTITION BY LIST (status);
```

Verify the top-level structure:

```sql
\d+ orders_multilevel
```

Expected output (yours will differ):

```
         Partitioned table "public.orders_multilevel"
...
Partition key: RANGE (order_date)
Partitions: orders_ml_2024_q1 FOR VALUES FROM ('2024-01-01') TO ('2024-04-01'), PARTITIONED,
            orders_ml_2024_q2 FOR VALUES FROM ('2024-04-01') TO ('2024-07-01'), PARTITIONED,
            ...
```

The word `PARTITIONED` after each child means those children are themselves partitioned - they are sub-partitioned parents.

---

## Step 3: Create Status Sub-Partitions for Q1 2024

Each quarterly partition needs one sub-partition per status value. Create them for Q1 2024:

```sql
CREATE TABLE orders_ml_2024_q1_completed
    PARTITION OF orders_ml_2024_q1
    FOR VALUES IN ('completed');
```

```sql
CREATE TABLE orders_ml_2024_q1_pending
    PARTITION OF orders_ml_2024_q1
    FOR VALUES IN ('pending');
```

```sql
CREATE TABLE orders_ml_2024_q1_shipped
    PARTITION OF orders_ml_2024_q1
    FOR VALUES IN ('shipped');
```

```sql
CREATE TABLE orders_ml_2024_q1_cancelled
    PARTITION OF orders_ml_2024_q1
    FOR VALUES IN ('cancelled');
```

```sql
CREATE TABLE orders_ml_2024_q1_refunded
    PARTITION OF orders_ml_2024_q1
    FOR VALUES IN ('refunded');
```

Create a default sub-partition to catch any unexpected status values:

```sql
CREATE TABLE orders_ml_2024_q1_other
    PARTITION OF orders_ml_2024_q1
    DEFAULT;
```

Repeat the sub-partition creation for Q2 2024:

```sql
CREATE TABLE orders_ml_2024_q2_completed PARTITION OF orders_ml_2024_q2 FOR VALUES IN ('completed');
```

```sql
CREATE TABLE orders_ml_2024_q2_pending   PARTITION OF orders_ml_2024_q2 FOR VALUES IN ('pending');
```

```sql
CREATE TABLE orders_ml_2024_q2_shipped   PARTITION OF orders_ml_2024_q2 FOR VALUES IN ('shipped');
```

```sql
CREATE TABLE orders_ml_2024_q2_cancelled PARTITION OF orders_ml_2024_q2 FOR VALUES IN ('cancelled');
```

```sql
CREATE TABLE orders_ml_2024_q2_refunded  PARTITION OF orders_ml_2024_q2 FOR VALUES IN ('refunded');
```

```sql
CREATE TABLE orders_ml_2024_q2_other     PARTITION OF orders_ml_2024_q2 DEFAULT;
```

Repeat for Q3 2024:

```sql
CREATE TABLE orders_ml_2024_q3_completed PARTITION OF orders_ml_2024_q3 FOR VALUES IN ('completed');
```

```sql
CREATE TABLE orders_ml_2024_q3_pending   PARTITION OF orders_ml_2024_q3 FOR VALUES IN ('pending');
```

```sql
CREATE TABLE orders_ml_2024_q3_shipped   PARTITION OF orders_ml_2024_q3 FOR VALUES IN ('shipped');
```

```sql
CREATE TABLE orders_ml_2024_q3_cancelled PARTITION OF orders_ml_2024_q3 FOR VALUES IN ('cancelled');
```

```sql
CREATE TABLE orders_ml_2024_q3_refunded  PARTITION OF orders_ml_2024_q3 FOR VALUES IN ('refunded');
```

```sql
CREATE TABLE orders_ml_2024_q3_other     PARTITION OF orders_ml_2024_q3 DEFAULT;
```

Repeat for Q4 2024:

```sql
CREATE TABLE orders_ml_2024_q4_completed PARTITION OF orders_ml_2024_q4 FOR VALUES IN ('completed');
```

```sql
CREATE TABLE orders_ml_2024_q4_pending   PARTITION OF orders_ml_2024_q4 FOR VALUES IN ('pending');
```

```sql
CREATE TABLE orders_ml_2024_q4_shipped   PARTITION OF orders_ml_2024_q4 FOR VALUES IN ('shipped');
```

```sql
CREATE TABLE orders_ml_2024_q4_cancelled PARTITION OF orders_ml_2024_q4 FOR VALUES IN ('cancelled');
```

```sql
CREATE TABLE orders_ml_2024_q4_refunded  PARTITION OF orders_ml_2024_q4 FOR VALUES IN ('refunded');
```

```sql
CREATE TABLE orders_ml_2024_q4_other     PARTITION OF orders_ml_2024_q4 DEFAULT;
```

Count the total number of leaf-level tables (the actual storage partitions):

```sql
SELECT COUNT(*) AS total_leaf_partitions
FROM pg_class
WHERE relname LIKE 'orders_ml_2024%'
AND relkind = 'r';
```

Expected output:

```
 total_leaf_partitions
-----------------------
                    24
(1 row)
```

24 leaf partitions: 4 quarters x 5 status values + 4 default sub-partitions.

> **Concept - Multi-level partitioning management complexity**
> For 4 quarters x 6 sub-partitions, you have 24 physical tables to manage. Extend this to monthly (12 months x 6 = 72 tables) and the management burden grows quickly. Each table has its own VACUUM cycles, statistics, and storage files. Before choosing multi-level partitioning, ask: "Does a composite index on (order_date, status) achieve the same pruning benefit with less complexity?" Often it does. Use multi-level partitioning only when partition elimination at both levels genuinely reduces IO significantly - typically when each sub-partition is still large enough (millions of rows) that scanning it is expensive.

---

## Step 4: Load Data and Verify Routing

Load 2024 data from the `orders` table - PostgreSQL will route each row to the correct quarter AND status sub-partition:

```sql
INSERT INTO orders_multilevel
SELECT order_id, customer_id, order_date, status, total_amount, region
FROM orders
WHERE order_date >= '2024-01-01' AND order_date < '2025-01-01';
```

Expected output (yours will differ):

```
INSERT 0 487643
```

Verify routing - check where a specific row landed:

```sql
SELECT tableoid::regclass AS actual_partition, order_id, order_date, status
FROM orders_multilevel
WHERE order_date = '2024-06-15' AND status = 'completed'
LIMIT 3;
```

Expected output (yours will differ):

```
       actual_partition        | order_id | order_date |  status
-------------------------------+----------+------------+-----------
 orders_ml_2024_q2_completed   |    10234 | 2024-06-15 | completed
 orders_ml_2024_q2_completed   |    10241 | 2024-06-15 | completed
 orders_ml_2024_q2_completed   |    10258 | 2024-06-15 | completed
(3 rows)
```

Rows from June 2024 (Q2) with status 'completed' landed in `orders_ml_2024_q2_completed`.

---

## Step 5: Prove Two-Level Pruning

Run EXPLAIN on a query that filters on both partition keys:

```sql
EXPLAIN
SELECT COUNT(*) FROM orders_multilevel
WHERE order_date >= '2024-07-01' AND order_date < '2024-10-01'
AND status = 'pending';
```

Expected output (yours will differ):

```
                     QUERY PLAN
-----------------------------------------------------
 Aggregate  (cost=...)
   ->  Seq Scan on orders_ml_2024_q3_pending  (cost=...)
         Filter: (...)
(3 rows)
```

Only ONE leaf partition scanned out of 24. Two-level pruning eliminated 23 other partitions.

Run the same query filtering on only the date (no status filter) to see partial pruning:

```sql
EXPLAIN
SELECT COUNT(*) FROM orders_multilevel
WHERE order_date >= '2024-07-01' AND order_date < '2024-10-01';
```

Expected output (yours will differ):

```
                     QUERY PLAN
-----------------------------------------------------
 Aggregate  (cost=...)
   ->  Append  (cost=...)
         ->  Seq Scan on orders_ml_2024_q3_completed
         ->  Seq Scan on orders_ml_2024_q3_pending
         ->  Seq Scan on orders_ml_2024_q3_shipped
         ->  Seq Scan on orders_ml_2024_q3_cancelled
         ->  Seq Scan on orders_ml_2024_q3_refunded
         ->  Seq Scan on orders_ml_2024_q3_other
(8 rows)
```

6 sub-partitions scanned (Q3 only). The other 3 quarters were pruned at level 1.

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

- [ ] You created a two-level partitioned table: RANGE at level 1, LIST at level 2
- [ ] You understand that a sub-partitioned parent has both `PARTITION OF` and `PARTITION BY` in its definition
- [ ] You verified that inserts route to the correct leaf partition at both levels
- [ ] You proved that filtering on both partition keys prunes to a single leaf partition (two-level pruning)
- [ ] You proved that filtering on only the top-level key prunes at level 1 but scans all sub-partitions within the matching quarter
- [ ] You can articulate the management complexity trade-off of multi-level partitioning vs a composite index

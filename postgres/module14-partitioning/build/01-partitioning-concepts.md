# Module 14 - Table Partitioning
## Guide 01: Partitioning Concepts and Your First Partitioned Table

**Objective:** Understand what declarative partitioning is, when to use it, and create a partitioned version of the orders table using range partitioning with monthly partitions. Verify partition pruning with EXPLAIN.

**Time:** 35-40 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432 with PGDATA at `/opt/pgsql/data`
- `stepup_store` database with the `orders` table (populated by the Pulse worker)
- Pulse dashboard running on port 8080

---

## 1. Understand What Partitioning Solves

Before touching the database, look at the orders table you will be working with.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to the `stepup_store` database:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check how many rows are in the orders table:

```sql
SELECT COUNT(*) FROM orders;
```

Expected output (yours will differ):

```
  count
---------
 1482300
(1 row)
```

Check the date range of the data:

```sql
SELECT MIN(order_date), MAX(order_date) FROM orders;
```

Expected output (yours will differ):

```
    min     |    max
------------+------------
 2023-01-01 | 2025-03-31
(1 row)
```

Check the table size on disk:

```sql
SELECT pg_size_pretty(pg_total_relation_size('orders'));
```

Expected output (yours will differ):

```
 pg_size_pretty
----------------
 312 MB
(1 row)
```

> **Concept - Why partition at all?**
> As tables grow into hundreds of millions of rows, two problems emerge. First, queries that touch only a slice of the data (e.g., "all orders from January 2025") must scan the entire table unless you have very selective indexes - and even then, the planner sometimes chooses a sequential scan. Second, maintenance operations like VACUUM, ANALYZE, and index rebuilds take longer because they work the entire table at once. Partitioning splits one logical table into multiple physical tables (partitions), each holding a subset of the data. Queries that filter on the partition key touch only the relevant partitions. Maintenance runs per-partition.

Exit psql:

```sql
\q
```

---

## 2. The Three Partition Types

PostgreSQL 16 supports three partitioning strategies for declarative partitioning:

| Strategy | Use When | Example |
|----------|----------|---------|
| `RANGE` | Data has a natural ordering you query with ranges | Dates, timestamps, integer IDs |
| `LIST` | Data falls into a known set of discrete values | Country codes, status values, region names |
| `HASH` | You want to spread data evenly with no natural key | User IDs for load distribution, archive by hash |

The orders table has `order_date` as a natural range key - most queries filter by date range. Range partitioning by month is the right choice here.

> **Concept - Declarative vs. inheritance partitioning**
> Before PostgreSQL 10, the only way to partition was through table inheritance - a complex manual process where you created child tables, wrote CHECK constraints, and maintained triggers to route inserts. PostgreSQL 10 introduced declarative partitioning (`PARTITION BY`), which lets the database engine handle routing, pruning, and constraint enforcement automatically. Always use declarative partitioning on PG10 and above. Inheritance partitioning exists only for backwards compatibility.

---

## 3. Create a Partitioned Version of the Orders Table

You will create `orders_partitioned` as a new partitioned table. In Guide 02 you will migrate the data into it. For now, you are learning the syntax.

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

First, look at the existing orders table structure so you can match it exactly:

```sql
\d orders
```

Expected output (yours will differ):

```
                          Table "public.orders"
    Column    |            Type             | Nullable |      Default
--------------+-----------------------------+----------+-------------------
 order_id     | integer                     | not null | nextval(...)
 customer_id  | integer                     |          |
 order_date   | date                        | not null |
 status       | character varying(20)       |          |
 total_amount | numeric(10,2)               |          |
 region       | character varying(50)       |          |
Indexes:
    "orders_pkey" PRIMARY KEY, btree (order_id)
```

Create the partitioned parent table. The `PARTITION BY RANGE (order_date)` clause is what makes this a partitioned table - the parent table itself holds no data:

```sql
CREATE TABLE orders_partitioned (
    order_id     integer        NOT NULL,
    customer_id  integer,
    order_date   date           NOT NULL,
    status       varchar(20),
    total_amount numeric(10,2),
    region       varchar(50)
) PARTITION BY RANGE (order_date);
```

Expected output:

```
CREATE TABLE
```

Verify the table was created as a partitioned table:

```sql
\d+ orders_partitioned
```

Expected output (yours will differ):

```
                   Partitioned table "public.orders_partitioned"
    Column    |       Type        | Nullable | Default | Storage  | Stats target
--------------+-------------------+----------+---------+----------+--------------
 order_id     | integer           | not null |         | plain    |
 customer_id  | integer           |          |         | plain    |
 order_date   | date              | not null |         | plain    |
 status       | character varying |          |         | extended |
 total_amount | numeric           |          |         | plain    |
 region       | character varying |          |         | extended |
Partition key: RANGE (order_date)
Number of partitions: 0 (Use \d+ to list them.)
```

Notice `Partition key: RANGE (order_date)` and `Number of partitions: 0`. The parent table is just a routing shell - it has no partitions yet and cannot hold any data until you create them.

> **Concept - The parent table is a shell**
> In declarative partitioning, the parent table (`orders_partitioned`) defines the schema and partition key, but it never stores rows directly. All data lives in the child partition tables. If you try to insert a row with no matching partition, PostgreSQL raises an error (unless you have a default partition). This is different from inheritance partitioning, where the parent could hold unmatched rows.

---

## 4. Create Monthly Partitions

Each partition covers an exclusive date range: `FOR VALUES FROM (inclusive start) TO (exclusive end)`. A row with `order_date = '2024-01-31'` belongs in the January 2024 partition because its range is `FROM '2024-01-01' TO '2024-02-01'`.

Create the January 2024 partition:

```sql
CREATE TABLE orders_2024_01
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');
```

Expected output:

```
CREATE TABLE
```

Create the February 2024 partition:

```sql
CREATE TABLE orders_2024_02
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-02-01') TO ('2024-03-01');
```

Expected output:

```
CREATE TABLE
```

Create the March 2024 partition:

```sql
CREATE TABLE orders_2024_03
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-03-01') TO ('2024-04-01');
```

Expected output:

```
CREATE TABLE
```

Create the Q2 2024 partitions:

```sql
CREATE TABLE orders_2024_04
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-04-01') TO ('2024-05-01');
```

```sql
CREATE TABLE orders_2024_05
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-05-01') TO ('2024-06-01');
```

```sql
CREATE TABLE orders_2024_06
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-06-01') TO ('2024-07-01');
```

Create the Q3 2024 partitions:

```sql
CREATE TABLE orders_2024_07
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-07-01') TO ('2024-08-01');
```

```sql
CREATE TABLE orders_2024_08
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-08-01') TO ('2024-09-01');
```

```sql
CREATE TABLE orders_2024_09
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-09-01') TO ('2024-10-01');
```

Create the Q4 2024 partitions:

```sql
CREATE TABLE orders_2024_10
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-10-01') TO ('2024-11-01');
```

```sql
CREATE TABLE orders_2024_11
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-11-01') TO ('2024-12-01');
```

```sql
CREATE TABLE orders_2024_12
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2024-12-01') TO ('2025-01-01');
```

Create Q1 2025 partitions:

```sql
CREATE TABLE orders_2025_01
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-01-01') TO ('2025-02-01');
```

```sql
CREATE TABLE orders_2025_02
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-02-01') TO ('2025-03-01');
```

```sql
CREATE TABLE orders_2025_03
    PARTITION OF orders_partitioned
    FOR VALUES FROM ('2025-03-01') TO ('2025-04-01');
```

Verify all partitions are visible:

```sql
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS partition_bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
ORDER BY child.relname;
```

Expected output (yours will differ):

```
  partition_name  |                      partition_bounds
------------------+------------------------------------------------------
 orders_2024_01   | FOR VALUES FROM ('2024-01-01') TO ('2024-02-01')
 orders_2024_02   | FOR VALUES FROM ('2024-02-01') TO ('2024-03-01')
 orders_2024_03   | FOR VALUES FROM ('2024-03-01') TO ('2024-04-01')
 ...
 orders_2025_03   | FOR VALUES FROM ('2025-03-01') TO ('2025-04-01')
(15 rows)
```

---

## 5. Insert Test Data and Verify Routing

Insert a test order and verify it lands in the correct partition:

```sql
INSERT INTO orders_partitioned (order_id, customer_id, order_date, status, total_amount, region)
VALUES (9999999, 1, '2024-06-15', 'completed', 99.99, 'Northeast');
```

Expected output:

```
INSERT 0 1
```

Check which partition holds that row. The `tableoid::regclass` trick returns the name of the actual physical table the row is stored in:

```sql
SELECT tableoid::regclass AS partition_name, order_id, order_date
FROM orders_partitioned
WHERE order_id = 9999999;
```

Expected output:

```
 partition_name  | order_id | order_date
-----------------+----------+------------
 orders_2024_06  |  9999999 | 2024-06-15
(1 row)
```

The June 2024 partition received the row automatically. You did not specify a partition - PostgreSQL routed it based on the `order_date` value and the partition bounds.

---

## 6. Prove Partition Pruning with EXPLAIN

Partition pruning is when the planner eliminates partitions that cannot possibly contain rows matching your WHERE clause. You verify pruning by reading the EXPLAIN output.

Run EXPLAIN on a query that filters by a single month:

```sql
EXPLAIN SELECT * FROM orders_partitioned WHERE order_date = '2024-06-15';
```

Expected output (yours will differ):

```
                             QUERY PLAN
--------------------------------------------------------------------
 Append  (cost=0.00..5.57 rows=1 width=78)
   ->  Seq Scan on orders_2024_06 orders_partitioned_1
         Filter: (order_date = '2024-06-15'::date)
(3 rows)
```

Only `orders_2024_06` appears in the plan. The other 14 partitions were pruned - the planner knew they cannot contain rows where `order_date = '2024-06-15'` based on their bounds.

Now run EXPLAIN on a query with NO date filter to see the difference:

```sql
EXPLAIN SELECT * FROM orders_partitioned WHERE status = 'completed';
```

Expected output (yours will differ):

```
                             QUERY PLAN
--------------------------------------------------------------------
 Append  (cost=0.00.....)
   ->  Seq Scan on orders_2024_01 orders_partitioned_1
         Filter: ((status)::text = 'completed'::text)
   ->  Seq Scan on orders_2024_02 orders_partitioned_2
         Filter: ((status)::text = 'completed'::text)
   ...
   ->  Seq Scan on orders_2025_03 orders_partitioned_15
         Filter: ((status)::text = 'completed'::text)
(31 rows)
```

All 15 partitions appear because `status` is not the partition key. PostgreSQL cannot prune based on a column it does not use for partitioning.

> **Concept - Partition pruning requires the partition key in the WHERE clause**
> Pruning only works when your WHERE clause includes a condition on the partition key (`order_date` in this case). A filter on `status`, `region`, or `customer_id` alone forces a scan of all partitions. This is a critical design consideration: choose your partition key to match your most common query filter. If you typically query by region, a LIST partition on region might be better than a RANGE on date.

Clean up the test row:

```sql
DELETE FROM orders_partitioned WHERE order_id = 9999999;
```

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

You have completed Guide 01. Verify you understand the following:

- [ ] You can explain the difference between RANGE, LIST, and HASH partitioning and when to use each
- [ ] You can explain why declarative partitioning replaced inheritance partitioning
- [ ] You can create a partitioned parent table with `CREATE TABLE ... PARTITION BY RANGE`
- [ ] You understand that the parent table is a shell - all data lives in child partitions
- [ ] You can create monthly partitions using `FOR VALUES FROM ... TO` with exclusive upper bounds
- [ ] You can verify which partition a row landed in using `tableoid::regclass`
- [ ] You can prove partition pruning is working using EXPLAIN
- [ ] You understand that pruning only works when the WHERE clause filters on the partition key

---

Proceed to **Guide 02 - Managing Partitions**

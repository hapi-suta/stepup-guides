# Exercise 01: Design a Partition Scheme

**Duration:** 20 minutes
**Objective:** Analyze the `orders` table access patterns and design the optimal partition strategy. Justify your choice with data from the database.

**Prerequisites:** `stepup_store` database running. `orders` table populated by the Pulse worker.

---

## Background

Before partitioning any table in production, you must answer three questions:

1. **What are the most common query filters?** - The partition key must match your most frequent WHERE clause columns.
2. **How large will each partition be?** - Partitions that are too large defeat the purpose; partitions that are too small create planning overhead.
3. **What is the data lifecycle?** - How long do you keep data? Do you archive or delete old data?

In this exercise you gather that evidence from the actual database, then write up your partition design.

---

## Step 1: Examine the Access Pattern

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check which columns have the widest variety of values (high cardinality columns are candidates for partition keys):

```sql
SELECT
    'order_date'   AS column_name,
    COUNT(DISTINCT order_date) AS distinct_values
FROM orders
UNION ALL
SELECT 'status',         COUNT(DISTINCT status)      FROM orders
UNION ALL
SELECT 'region',         COUNT(DISTINCT region)       FROM orders
UNION ALL
SELECT 'customer_id',    COUNT(DISTINCT customer_id)  FROM orders
ORDER BY distinct_values DESC;
```

Expected output (yours will differ):

```
  column_name  | distinct_values
---------------+-----------------
 customer_id   |           45231
 order_date    |             820
 region        |              12
 status        |               5
(4 rows)
```

Check the date distribution - how many orders per month:

```sql
SELECT
    DATE_TRUNC('month', order_date) AS month,
    COUNT(*) AS order_count
FROM orders
GROUP BY 1
ORDER BY 1;
```

Expected output (yours will differ):

```
         month          | order_count
------------------------+-------------
 2023-01-01 00:00:00+00 |       38741
 2023-02-01 00:00:00+00 |       35290
 2023-03-01 00:00:00+00 |       41200
 ...
 2025-03-01 00:00:00+00 |       43901
(27 rows)
```

Check the row counts per region:

```sql
SELECT
    region,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders
GROUP BY region
ORDER BY order_count DESC;
```

Expected output (yours will differ):

```
    region    | order_count | pct
--------------+-------------+------
 Northeast    |      287410 | 19.4
 Southeast    |      264821 | 17.8
 Midwest      |      241003 | 16.2
 West         |      223491 | 15.1
 Southwest    |      198321 | 13.4
 Northwest    |      154892 | 10.4
 ...
(12 rows)
```

Check the row counts per status:

```sql
SELECT
    status,
    COUNT(*) AS order_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM orders
GROUP BY status
ORDER BY order_count DESC;
```

Expected output (yours will differ):

```
   status    | order_count | pct
-------------+-------------+------
 completed   |      890412 | 60.1
 pending     |      297841 | 20.1
 shipped     |      222310 | 15.0
 cancelled   |       55201 |  3.7
 refunded    |       16536 |  1.1
(5 rows)
```

Check what the most common query pattern looks like by inspecting `pg_stat_statements` (requires the extension to be enabled):

```sql
SELECT
    calls,
    mean_exec_time::numeric(10,2) AS avg_ms,
    LEFT(query, 100) AS query_sample
FROM pg_stat_statements
WHERE query ILIKE '%orders%'
ORDER BY calls DESC
LIMIT 5;
```

Expected output (yours will differ - if pg_stat_statements is not installed, skip this step):

```
 calls | avg_ms | query_sample
-------+--------+----------------------------------------------------------
  8241 |   2.34 | SELECT * FROM orders WHERE order_date >= $1 AND order_date < $2
  5102 |  15.21 | SELECT SUM(total_amount) FROM orders WHERE order_date = $1...
  2841 |   0.89 | SELECT COUNT(*) FROM orders WHERE status = $1
   941 |  34.12 | SELECT * FROM orders WHERE customer_id = $1 ORDER BY order...
(4 rows)
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

## Step 2: Write Your Design Recommendation

Based on the data you gathered, answer the following questions in writing. There is a reference answer below each question - try to answer before reading it.

---

**Question 1: Which partition strategy (RANGE, LIST, or HASH) would you use for the orders table and why?**

Write your answer here before reading below.

---

**Reference Answer:**

RANGE partitioning on `order_date` is the best choice for this table. The evidence:

- The most common queries filter by `order_date` range (from `pg_stat_statements`).
- Date is a natural ordering column - RANGE partitioning maps directly to time-based queries.
- Monthly partitions align with business reporting periods and archival schedules.
- `status` has only 5 distinct values - LIST partitioning on status would create 5 partitions that all get queried together constantly (no pruning benefit).
- `region` has 12 values with uneven distribution - LIST on region could work for region-specific reporting but does not help the most frequent date-range queries.
- `customer_id` has 45,231 distinct values - HASH on customer_id would spread load evenly but completely breaks date-range pruning.

---

**Question 2: What should the partition granularity be - daily, monthly, or yearly?**

Write your answer here before reading below.

---

**Reference Answer:**

Monthly is the right granularity for this dataset. The evidence:

- ~38,000-44,000 orders per month means each monthly partition is roughly 25-35 MB (manageable size).
- Daily would create 365+ partitions per year. At 1,300+ rows per day, each daily partition is ~1 MB - too small. Planning overhead would be significant.
- Yearly would create 2-3 partitions total. Each partition would be 400+ MB and hold 12 months of data. A query for "orders in June 2024" would still scan the entire 2024 partition.
- Monthly gives you the right balance: each partition is large enough that per-partition overhead is amortized, small enough that pruning eliminates meaningful amounts of data, and aligns with natural archival cycles (archive 2+ year old data monthly).

---

**Question 3: Do you need a default partition? When would you remove it?**

Write your answer here before reading below.

---

**Reference Answer:**

Yes, create a default partition. The Pulse worker inserts orders continuously. If the next month's partition does not exist yet when a new-month row arrives, the insert will fail without a default partition. The default partition is a safety net.

Remove the default partition only after your partition management automation is proven reliable and you have added monitoring alerts for "rows in default partition > 0". In practice, leave the default partition in place permanently and treat it as an early-warning system.

---

**Question 4: If you were to also partition by region for reporting purposes, how would you implement it?**

Write your answer here before reading below.

---

**Reference Answer:**

You would use sub-partitioning (two-level partitioning): RANGE by `order_date` at the top level, LIST by `region` at the second level. Each monthly partition would have 12 sub-partitions (one per region). This is covered in USE Exercise 05. The trade-off is complexity: you go from 15 partitions to 180 (15 months x 12 regions). For most workloads, a composite index on `(order_date, region)` is simpler and sufficient.

---

## Checkpoint

- [ ] You can explain why RANGE on `order_date` is better than LIST on `status` for this workload
- [ ] You can justify monthly vs daily vs yearly granularity using actual row counts
- [ ] You understand the role of the default partition as a safety net
- [ ] You can articulate the trade-offs of multi-level partitioning vs a composite index

# Use Exercise 06 - Baseline Comparison

Capture a performance baseline before making a change, apply a change, then compare the before and after metrics to measure the impact.

**Run on:** NODE1

---

## Your Mission

You cannot prove that a change helped (or did not hurt) without a before measurement. Every production DBA keeps baselines. In this exercise you will:

1. Capture a baseline using pg_stat_statements and pg_stat_database
2. Apply a change (add an index to a slow query)
3. Run the same workload again
4. Capture a post-change snapshot and compare

---

## Instructions

SSH into NODE1 and switch to the postgres user.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

---

## Part A - Set Up the Test Query

Find a query in `stepup_store` that does a sequential scan on orders. Connect to psql.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check the orders table for a column without an index.

```sql
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
   indexname    |                         indexdef
----------------+-----------------------------------------------------------
 orders_pkey    | CREATE UNIQUE INDEX orders_pkey ON public.orders USING btree (id)
 orders_status  | CREATE INDEX orders_status ON public.orders USING btree (status)
(2 rows)
```

If there is no index on `customer_id`, that is your target column. If `customer_id` is already indexed, pick a different column from the orders table that has no index.

Confirm the test query does a sequential scan.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 100;
```

Expected output (yours will differ - look for "Seq Scan"):

```
                                              QUERY PLAN
------------------------------------------------------------------------------------------------------
 Seq Scan on orders  (cost=0.00..2400.00 rows=12 width=64) (actual time=0.042..18.432 rows=12 loops=1)
   Filter: (customer_id = 100)
   Rows Removed by Filter: 99988
   Buffers: shared hit=1240
 Planning Time: 0.124 ms
 Execution Time: 18.651 ms
(6 rows)
```

---

## Part B - Capture the Baseline

Reset pg_stat_statements for a clean measurement.

```sql
SELECT pg_stat_statements_reset();
```

Run the test query 100 times to populate statistics.

```sql
SELECT count(*) FROM (
  SELECT * FROM orders WHERE customer_id IN (SELECT generate_series(1, 100))
) t;
```

Wait for it to finish, then capture the baseline metrics. Save the output.

```sql
\o /tmp/baseline.txt
SELECT
    left(query, 80) AS query,
    calls,
    round(total_exec_time::numeric, 0) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    shared_blks_read,
    shared_blks_hit
FROM pg_stat_statements
WHERE query ILIKE '%orders%customer_id%'
ORDER BY total_exec_time DESC
LIMIT 5;
\o
\! cat /tmp/baseline.txt
```

Also capture the current table stats.

```sql
\o /tmp/table_baseline.txt
SELECT relname, seq_scan, idx_scan, n_live_tup
FROM pg_stat_user_tables
WHERE relname = 'orders';
\o
\! cat /tmp/table_baseline.txt
```

---

## Part C - Apply the Change

Create an index on the `customer_id` column.

```sql
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
```

Expected output:

```
CREATE INDEX
```

Confirm the index was created.

```sql
SELECT indexname FROM pg_indexes WHERE tablename = 'orders' AND indexname = 'idx_orders_customer_id';
```

Expected output:

```
        indexname
------------------------
 idx_orders_customer_id
(1 row)
```

---

## Part D - Capture Post-Change Metrics

Reset statistics again to get a clean post-change measurement.

```sql
SELECT pg_stat_statements_reset();
```

```sql
SELECT pg_stat_reset();
```

Run the same workload as before.

```sql
SELECT count(*) FROM (
  SELECT * FROM orders WHERE customer_id IN (SELECT generate_series(1, 100))
) t;
```

Capture the post-change metrics.

```sql
\o /tmp/after.txt
SELECT
    left(query, 80) AS query,
    calls,
    round(total_exec_time::numeric, 0) AS total_ms,
    round(mean_exec_time::numeric, 2) AS mean_ms,
    shared_blks_read,
    shared_blks_hit
FROM pg_stat_statements
WHERE query ILIKE '%orders%customer_id%'
ORDER BY total_exec_time DESC
LIMIT 5;
\o
\! cat /tmp/after.txt
```

---

## Part E - Compare

Run EXPLAIN again to confirm the index is being used.

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE customer_id = 100;
```

Expected output (yours will differ - look for "Index Scan"):

```
                                                     QUERY PLAN
-------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_orders_customer_id on orders  (cost=0.29..8.31 rows=12 width=64) (actual time=0.022..0.041 rows=12 loops=1)
   Index Cond: (customer_id = 100)
   Buffers: shared hit=4
 Planning Time: 0.210 ms
 Execution Time: 0.062 ms
(5 rows)
```

Now do a side-by-side comparison.

```sql
\! echo "=== BEFORE ===" && cat /tmp/baseline.txt && echo "=== AFTER ===" && cat /tmp/after.txt
```

---

## Part F - Write Your Comparison Report

In the psql shell, use `\! vi /tmp/comparison_report.txt` to write a short report covering:

1. What was the baseline mean execution time?
2. What is the post-change mean execution time?
3. What is the percentage improvement?
4. Did blocks read from disk change? By how much?
5. Would you deploy this change to production? What else would you check?

Exit psql.

```sql
\q
```

```
exit
```

---

## Checkpoint

- [ ] Identified a query doing a sequential scan
- [ ] Reset stats and ran a workload to populate the baseline
- [ ] Saved baseline metrics for pg_stat_statements and pg_stat_user_tables
- [ ] Created the index
- [ ] Reset stats and ran the same workload post-change
- [ ] Ran EXPLAIN after the change and confirmed index use
- [ ] Did a side-by-side comparison
- [ ] Wrote a short comparison report with percentage improvement

---

This is the last USE exercise. Proceed to the SURVIVE scenarios.

Proceed to: [Survive 01 - Logging Disabled](../survive/01-logging-disabled/runbook.md)

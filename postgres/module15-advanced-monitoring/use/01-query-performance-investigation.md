# Use Exercise 01 - Query Performance Investigation

**Module:** 15 - Advanced Monitoring
**Estimated Time:** 40 minutes
**Prerequisite:** Build Guides 01-04 complete

---

## Objective

Use `pg_stat_statements` and Grafana together to find a deliberately slow query, understand why it is slow, and verify the fix using the same tools.

---

## Background

In production, you rarely know in advance which query is causing a problem. You get a report: "The app feels slow." Your job is to find the guilty query using monitoring data, not guesswork.

In this exercise you will:
1. Plant a slow query in the workload
2. Use pg_stat_statements to identify it
3. Find it on the Grafana dashboard
4. Fix it with an index
5. Verify the fix through metrics

---

## Part 1 - Generate a baseline workload

Log in to pg-primary.

```bash
ssh -i your-key.pem ec2-user@<your-server-ip>
```

Reset pg_stat_statements so you start fresh.

```bash
sudo -i -u postgres
```

```bash
psql -d stepup_store -c "SELECT pg_stat_statements_reset();"
```

Run a normal pgbench workload for 2 minutes.

```bash
/usr/pgsql-16/bin/pgbench -c 5 -T 120 -d stepup_store
```

---

## Part 2 - Plant a slow query

Switch to postgres user and connect to stepup_store.

```bash
psql -d stepup_store
```

Create a table that lacks a proper index to simulate a real-world oversight.

```sql
CREATE TABLE IF NOT EXISTS order_events (
  id          bigserial PRIMARY KEY,
  order_id    bigint    NOT NULL,
  event_type  text      NOT NULL,
  created_at  timestamptz DEFAULT now(),
  payload     jsonb
);
```

Insert 500,000 rows.

```sql
INSERT INTO order_events (order_id, event_type, payload)
SELECT
  (random() * 1000000)::bigint,
  (ARRAY['placed','shipped','delivered','cancelled'])[ceil(random()*4)::int],
  jsonb_build_object('amount', random() * 500)
FROM generate_series(1, 500000);
```

This will take about 30-60 seconds. Expected output (yours will differ):

```
INSERT 0 500000
```

Now create a function that simulates application code doing a full table scan.

```sql
CREATE OR REPLACE FUNCTION find_order_events(p_order_id bigint)
RETURNS TABLE(id bigint, event_type text, created_at timestamptz)
LANGUAGE sql STABLE AS $$
  SELECT id, event_type, created_at
  FROM order_events
  WHERE order_id = p_order_id
  ORDER BY created_at DESC;
$$;
```

Exit psql.

```sql
\q
```

---

## Part 3 - Generate slow query traffic

Run this loop from the postgres user to call the slow function repeatedly for 3 minutes.

```bash
for i in $(seq 1 180); do
  psql -d stepup_store -c "SELECT * FROM find_order_events($((RANDOM % 1000000 + 1))) LIMIT 5;" > /dev/null 2>&1
  sleep 1
done &
```

The `&` runs the loop in the background. While it runs, proceed to Part 4.

---

## Part 4 - Use pg_stat_statements to identify the slow query

```bash
psql -d stepup_store
```

Query for the top statements by mean execution time.

```sql
SELECT
  left(query, 100)                          AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 2)         AS mean_ms,
  round(total_exec_time::numeric, 2)        AS total_ms,
  shared_blks_read
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 5;
```

**Your task:** Identify which query has the highest mean execution time and the highest `shared_blks_read`. Write down:

1. The query text
2. Its mean execution time
3. Its shared_blks_read count

---

## Part 5 - Run EXPLAIN ANALYZE on the slow query

Use the order_id value `12345` as an example. Run the actual query with EXPLAIN ANALYZE to see the query plan.

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, event_type, created_at
FROM order_events
WHERE order_id = 12345
ORDER BY created_at DESC;
```

Expected output (yours will differ):

```
                                                         QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------
 Sort  (cost=12843.21..12843.29 rows=32 width=24) (actual time=89.234..89.234 rows=0 loops=1)
   Sort Key: created_at DESC
   Sort Method: quicksort  Memory: 25kB
   Buffers: shared read=3182
   ->  Seq Scan on order_events  (cost=0.00..12842.50 rows=32 width=24) (actual time=89.231..89.231 rows=0 loops=1)
         Filter: (order_id = 12345)
         Rows Removed by Filter: 500000
         Buffers: shared read=3182
 Planning Time: 0.082 ms
 Execution Time: 89.241 ms
```

**Key observations:**
- `Seq Scan on order_events` - PostgreSQL scanned every single row
- `Rows Removed by Filter: 500000` - it read all 500,000 rows and discarded nearly all of them
- `shared read=3182` - blocks had to be fetched from disk or OS cache

---

## Part 6 - Check the slow query in Grafana

Open Grafana in your browser at `http://<your-server-ip>:3000`.

1. Navigate to the PostgreSQL dashboard
2. Look at the **Cache Hit Ratio** panel - it should have dropped during your slow query generation
3. Look at the **Tuple Operations** panel - you should see sequential scan activity

---

## Part 7 - Fix the problem with an index

Create an index on the `order_id` column, which is the column used in the WHERE clause.

```sql
CREATE INDEX CONCURRENTLY idx_order_events_order_id
  ON order_events (order_id, created_at DESC);
```

The `CONCURRENTLY` option builds the index without locking the table for writes - safe to run on production tables.

Expected output (yours will differ):

```
CREATE INDEX
```

---

## Part 8 - Run EXPLAIN ANALYZE again

```sql
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
SELECT id, event_type, created_at
FROM order_events
WHERE order_id = 12345
ORDER BY created_at DESC;
```

Expected output (yours will differ):

```
                                                               QUERY PLAN
----------------------------------------------------------------------------------------------------------------------------------------
 Index Scan using idx_order_events_order_id on order_events  (cost=0.42..8.44 rows=1 width=24) (actual time=0.041..0.041 rows=0 loops=1)
   Index Cond: (order_id = 12345)
   Buffers: shared hit=3
 Planning Time: 0.180 ms
 Execution Time: 0.052 ms
```

**Key changes after the index:**
- `Index Scan` replaced `Seq Scan` - PostgreSQL now uses the index
- Execution time dropped from ~89ms to ~0.05ms
- `shared hit=3` - only 3 buffer blocks accessed, all from cache

---

## Part 9 - Reset pg_stat_statements and measure again

```sql
SELECT pg_stat_statements_reset();
```

Exit psql and run the slow function again for 1 minute to collect new stats.

```sql
\q
```

```bash
for i in $(seq 1 60); do
  psql -d stepup_store -c "SELECT * FROM find_order_events($((RANDOM % 1000000 + 1))) LIMIT 5;" > /dev/null 2>&1
  sleep 1
done
```

Then check pg_stat_statements again for mean_exec_time.

```bash
psql -d stepup_store -c "
SELECT
  left(query, 100) AS query_snippet,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 5;"
```

The mean_exec_time for the `find_order_events` query should now be under 1ms.

---

## Reflection Questions

Answer these in your notes:

1. What was the mean execution time before and after the index?
2. What does a `Seq Scan` in an EXPLAIN plan tell you about the query?
3. Why does `shared_blks_read` decrease after adding an index?
4. Why should you use `CREATE INDEX CONCURRENTLY` in production instead of `CREATE INDEX`?
5. How would you use Grafana's time range selector to correlate the slow query period with the cache hit ratio drop?

---

## Cleanup

```bash
sudo -i -u postgres
psql -d stepup_store -c "DROP TABLE order_events CASCADE;"
exit
```

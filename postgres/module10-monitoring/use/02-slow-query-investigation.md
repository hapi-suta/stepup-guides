# Use Exercise 02 - Slow Query Investigation

Given a pg_stat_statements output, identify the 3 worst queries and explain why each one is problematic.

**Run on:** NODE1

---

## Your Mission

Reading numbers from pg_stat_statements is easy. Knowing which numbers matter and what to do about them is the skill. In this exercise you will:

1. Generate a realistic pg_stat_statements dataset by running a mix of queries
2. Identify the 3 worst queries using three different ranking methods
3. Explain what makes each one bad and what you would do about it

---

## Instructions

SSH into NODE1 and switch to the postgres user.

```
ssh -i <your-key.pem> ec2-user@<NODE1-IP>
```

```
sudo -iu postgres
```

### Step 1 - Reset stats to start clean

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_stat_statements_reset();"
```

Expected output:

```
 pg_stat_statements_reset
--------------------------

(1 row)
```

### Step 2 - Generate a workload

Run these queries to populate pg_stat_statements with a realistic mix. Run them from psql:

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Run the first query 1000 times using `generate_series` to simulate repeated traffic:

```sql
SELECT count(*) FROM orders WHERE status = 'pending'
FROM generate_series(1, 1000);
```

Run a slow analytical query that does a full table scan and join:

```sql
SELECT o.id, o.status, sum(oi.quantity * oi.price) AS total
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id, o.status
ORDER BY total DESC;
```

Run it again to give it more calls:

```sql
SELECT o.id, o.status, sum(oi.quantity * oi.price) AS total
FROM orders o
JOIN order_items oi ON o.id = oi.order_id
GROUP BY o.id, o.status
ORDER BY total DESC;
```

Run a sleep to simulate a slow one-off operation:

```sql
SELECT pg_sleep(3);
```

Run a simple fast query many times:

```sql
SELECT id, status FROM orders WHERE id = 1
FROM generate_series(1, 5000);
```

Exit psql.

```sql
\q
```

### Step 3 - Query pg_stat_statements three ways

Open psql again.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

**Ranking 1: By total execution time**

```sql
SELECT left(query, 80) AS query,
       calls,
       round(total_exec_time::numeric, 0) AS total_ms,
       round(mean_exec_time::numeric, 0) AS mean_ms
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 5;
```

**Ranking 2: By mean execution time (minimum 2 calls)**

```sql
SELECT left(query, 80) AS query,
       calls,
       round(mean_exec_time::numeric, 0) AS mean_ms,
       round(total_exec_time::numeric, 0) AS total_ms
FROM pg_stat_statements
WHERE calls >= 2
ORDER BY mean_exec_time DESC
LIMIT 5;
```

**Ranking 3: By I/O (blocks read from disk)**

```sql
SELECT left(query, 80) AS query,
       calls,
       shared_blks_read,
       shared_blks_hit,
       round(shared_blks_hit * 100.0 / nullif(shared_blks_hit + shared_blks_read, 0), 1) AS cache_hit_pct
FROM pg_stat_statements
ORDER BY shared_blks_read DESC
LIMIT 5;
```

---

## Your Analysis

After running all three rankings, answer these questions in writing (you can write directly in psql with `\! vi /tmp/analysis.txt`, or discuss with your instructor):

**Question 1:** Which query ranks worst by total time? What is the business impact of a query that accumulates large total time? Would you fix this before or after a query with high mean time?

**Question 2:** Which query has the highest mean execution time? If this query is called by a user-facing API, what is the user experience impact? What is your first hypothesis for why it is slow?

**Question 3:** Which query reads the most blocks from disk (lowest cache_hit_pct)? What does that tell you? What would you look at next - the EXPLAIN plan or the table structure?

**Question 4:** A query runs 50,000 times per day with a mean time of 0.5ms. Another runs 10 times per day with a mean time of 800ms. Which do you fix first? Show the math.

---

## Checkpoint

- [ ] Reset pg_stat_statements before generating the workload
- [ ] Ran all three ranking queries
- [ ] Identified the worst query by each method
- [ ] Answered all four analysis questions

---

Proceed to: [Use Exercise 03 - Connection Audit](./03-connection-audit.md)

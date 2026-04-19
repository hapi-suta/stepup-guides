# Use Exercise 03 - Query Rewrite

Rewrite five poorly-written queries for better performance without changing the results. Compare EXPLAIN ANALYZE output before and after each rewrite.

**Server:** NODE1 only

---

## Setup

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Switch to postgres.

```
sudo -iu postgres
```

Connect to stepup_store.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Rewrite 1 - Eliminate SELECT *

**Original query:** The application fetches all customer columns just to display the name in a dropdown.

```sql
EXPLAIN ANALYZE SELECT * FROM customers WHERE id = 15;
```

Note the plan, the `width`, and whether an Index Only Scan is possible.

**Your task:** Rewrite the query to fetch only `id`, `first_name`, `last_name`.

After rewriting, run EXPLAIN ANALYZE again. The `width` should drop and you should see `Index Only Scan` if the primary key covers those columns (it does not by default - check whether an INCLUDE index would help here).

**Verify correctness:** Both queries must return the same customer row.

---

## Rewrite 2 - Fix Function on Indexed Column

**Original query:** Finds orders created today using a date-extracting function.

```sql
EXPLAIN ANALYZE
SELECT id, total_amount
FROM orders
WHERE date(created_at) = CURRENT_DATE;
```

Note whether the index on `created_at` is used. It will not be - `date(created_at)` wraps the column in a function.

**Your task:** Rewrite the WHERE clause to use a range condition instead, so an existing B-tree index on `created_at` can be used.

**Hint:** `CURRENT_DATE` is the start of today. `CURRENT_DATE + 1` is the start of tomorrow.

After rewriting, run EXPLAIN ANALYZE and confirm the index is used.

**Verify correctness:** Both queries must return the same rows for the current date.

---

## Rewrite 3 - Replace Correlated Subquery with JOIN

**Original query:** Fetches each customer's most recent order date using a correlated subquery.

```sql
EXPLAIN ANALYZE
SELECT c.email,
  (SELECT MAX(created_at) FROM orders o WHERE o.customer_id = c.id) AS last_order_date
FROM customers c;
```

Check the `loops` count in the SubPlan node. It should equal the number of customers.

**Your task:** Rewrite using a LEFT JOIN and GROUP BY (or a window function) to compute the same result without the correlated subquery.

After rewriting, run EXPLAIN ANALYZE and confirm `loops=1` for all nodes.

**Verify correctness:** Run both queries and compare the output with `EXCEPT` to confirm zero differences.

```sql
-- Paste this after writing your new query to check for differences:
-- (original)
SELECT c.email, (SELECT MAX(created_at) FROM orders o WHERE o.customer_id = c.id) AS last_order_date
FROM customers c
EXCEPT
-- (your rewrite)
SELECT c.email, MAX(o.created_at) AS last_order_date
FROM customers c LEFT JOIN orders o ON o.customer_id = c.id
GROUP BY c.email;
```

Expected output (zero rows means they match):

```
 email | last_order_date
-------+-----------------
(0 rows)
```

---

## Rewrite 4 - Replace OR with UNION ALL

**Original query:** Finds customers who placed either a large order OR who are in a specific city.

```sql
EXPLAIN ANALYZE
SELECT DISTINCT c.id, c.email
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.total_amount > 400
   OR c.city = 'Chicago';
```

Note whether the plan uses a Seq Scan or indexes. The OR typically prevents index use across different columns.

**Your task:** Rewrite using UNION (or UNION ALL + deduplication) so each branch can use its own index.

After rewriting, run EXPLAIN ANALYZE and confirm the plan uses Index Scans in both branches.

**Verify correctness:** Both queries must return the same set of customers. Use `EXCEPT` in both directions to check.

---

## Rewrite 5 - Remove DISTINCT When Not Needed

**Original query:** The developer added DISTINCT defensively even though the join is already unique.

```sql
EXPLAIN ANALYZE
SELECT DISTINCT c.id, c.email, c.first_name
FROM customers c
JOIN orders o ON o.customer_id = c.id
WHERE o.id = 25;
```

Note the extra `HashAggregate` or `Unique` node the DISTINCT adds.

**Your task:** Determine whether DISTINCT is needed here. If a customer has only one row in customers, and the join condition is on orders.id (unique primary key), then each customer appears at most once. Rewrite without DISTINCT.

After rewriting, run EXPLAIN ANALYZE. The `Unique` or `HashAggregate` node should be gone.

**Verify correctness:** Both queries must return the same rows.

---

## Summary Check

After completing all five rewrites, run this to confirm pg_stat_statements captured your work.

```sql
SELECT calls, round(mean_exec_time::numeric, 2) AS avg_ms, left(query, 70) AS query
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

```
\q
```

```
exit
```

---

## Checkpoint

- [ ] All five rewrites produce identical results to the original queries
- [ ] All five rewrites show a better plan in EXPLAIN ANALYZE (no Seq Scan where an index was available, no SubPlan loops)
- [ ] You can explain in one sentence WHY each original was slow
- [ ] Rewrite 3 was verified with the EXCEPT check and returned 0 rows

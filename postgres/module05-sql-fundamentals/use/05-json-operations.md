# Exercise 05: JSON Operations

**Duration:** 25 minutes
**Objective:** Query JSONB columns to extract fields, filter by JSON values, aggregate JSON data, and understand when to add a GIN index.

**Prerequisites:** Build guide 05 (advanced SQL) complete.

---

## Background

`stepup_store` does not ship with a pre-built audit table, so this exercise has you build one. In a real system, a table like this is typically populated by an application layer or a database trigger that snapshots the old and new row on every INSERT, UPDATE, and DELETE, storing both as JSONB. Here you will create the table and seed it by hand, then practice PostgreSQL's native JSONB operators against it - the query patterns are identical to what you would write against a live, trigger-populated audit log.

The `audit_log` columns you will create are: `log_id`, `table_name`, `operation`, `old_data` (JSONB), `new_data` (JSONB), `changed_by`, `changed_at`.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Create the table:

```sql
CREATE TABLE audit_log (
  log_id      SERIAL PRIMARY KEY,
  table_name  VARCHAR(50),
  operation   VARCHAR(20),
  old_data    JSONB,
  new_data    JSONB,
  changed_by  VARCHAR(100),
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

Seed it with 8 order-creation events and 7 status-change events. Note that log entry for order 208 is deliberately missing `total_amount` - you will use that gap in the Stretch section:

```sql
INSERT INTO audit_log (table_name, operation, new_data, changed_by, changed_at) VALUES
  ('orders', 'INSERT', '{"order_id": 201, "customer_id": 1, "total_amount": 125.97, "status": "pending"}', 'app_service', '2026-08-01 09:12:00+00'),
  ('orders', 'INSERT', '{"order_id": 202, "customer_id": 2, "total_amount": 89.99,  "status": "pending"}', 'app_service', '2026-08-01 09:45:00+00'),
  ('orders', 'INSERT', '{"order_id": 203, "customer_id": 1, "total_amount": 249.50, "status": "pending"}', 'app_service', '2026-08-01 14:03:00+00'),
  ('orders', 'INSERT', '{"order_id": 204, "customer_id": 3, "total_amount": 599.99, "status": "pending"}', 'app_service', '2026-08-02 09:30:00+00'),
  ('orders', 'INSERT', '{"order_id": 205, "customer_id": 2, "total_amount": 149.99, "status": "pending"}', 'app_service', '2026-08-02 16:20:00+00'),
  ('orders', 'INSERT', '{"order_id": 206, "customer_id": 4, "total_amount": 89.99,  "status": "pending"}', 'app_service', '2026-08-03 09:05:00+00'),
  ('orders', 'INSERT', '{"order_id": 207, "customer_id": 1, "total_amount": 199.99, "status": "pending"}', 'app_service', '2026-08-03 09:55:00+00'),
  ('orders', 'INSERT', '{"order_id": 208, "customer_id": 5, "status": "pending"}', 'app_service', '2026-08-03 20:10:00+00');
```

```sql
INSERT INTO audit_log (table_name, operation, old_data, new_data, changed_by, changed_at) VALUES
  ('orders', 'UPDATE', '{"order_id": 201, "status": "pending"}', '{"order_id": 201, "status": "shipped"}',   'fulfillment_bot', '2026-08-02 10:00:00+00'),
  ('orders', 'UPDATE', '{"order_id": 201, "status": "shipped"}', '{"order_id": 201, "status": "delivered"}', 'fulfillment_bot', '2026-08-04 08:00:00+00'),
  ('orders', 'UPDATE', '{"order_id": 202, "status": "pending"}', '{"order_id": 202, "status": "cancelled"}', 'support_agent',   '2026-08-02 11:15:00+00'),
  ('orders', 'UPDATE', '{"order_id": 203, "status": "pending"}', '{"order_id": 203, "status": "shipped"}',   'fulfillment_bot', '2026-08-03 10:30:00+00'),
  ('orders', 'UPDATE', '{"order_id": 203, "status": "shipped"}', '{"order_id": 203, "status": "delivered"}', 'fulfillment_bot', '2026-08-05 09:00:00+00'),
  ('orders', 'UPDATE', '{"order_id": 204, "status": "pending"}', '{"order_id": 204, "status": "cancelled"}', 'support_agent',   '2026-08-03 09:40:00+00'),
  ('orders', 'UPDATE', '{"order_id": 206, "status": "pending"}', '{"order_id": 206, "status": "shipped"}',   'fulfillment_bot', '2026-08-04 09:10:00+00');
```

First, look at a sample of the data to understand the structure:

```sql
SELECT operation, new_data FROM audit_log ORDER BY log_id LIMIT 10;
```

Expected output (JSONB reorders keys internally - shortest key first - so do not expect the insertion order back):

```
 operation |                                     new_data
-----------+------------------------------------------------------------------------------------
 INSERT    | {"status": "pending", "order_id": 201, "customer_id": 1, "total_amount": 125.97}
 INSERT    | {"status": "pending", "order_id": 202, "customer_id": 2, "total_amount": 89.99}
 INSERT    | {"status": "pending", "order_id": 203, "customer_id": 1, "total_amount": 249.50}
 INSERT    | {"status": "pending", "order_id": 204, "customer_id": 3, "total_amount": 599.99}
 INSERT    | {"status": "pending", "order_id": 205, "customer_id": 2, "total_amount": 149.99}
 INSERT    | {"status": "pending", "order_id": 206, "customer_id": 4, "total_amount": 89.99}
 INSERT    | {"status": "pending", "order_id": 207, "customer_id": 1, "total_amount": 199.99}
 INSERT    | {"status": "pending", "order_id": 208, "customer_id": 5}
 UPDATE    | {"status": "shipped", "order_id": 201}
 UPDATE    | {"status": "delivered", "order_id": 201}
(10 rows)
```

---

## Task 1: Extract and Display Fields

Write a query that shows the `order_id` and `total_amount` from every `INSERT` operation on the orders table. The `new_data` payload looks like:

```json
{"order_id": 201, "customer_id": 1, "total_amount": 125.97, "status": "pending"}
```

Requirements:
- Filter for `operation = 'INSERT'` and `table_name = 'orders'`
- Only include rows where `total_amount` is present (order 208 is missing it - skip it here)
- Extract `order_id` as an integer
- Extract `total_amount` as a numeric value rounded to 2 decimal places
- Order by `order_id` ascending

### Answer

```sql
SELECT
  (new_data ->> 'order_id')::INTEGER AS order_id,
  ROUND((new_data ->> 'total_amount')::NUMERIC, 2) AS order_total
FROM audit_log
WHERE operation = 'INSERT'
  AND table_name = 'orders'
  AND new_data ? 'total_amount'
ORDER BY order_id ASC;
```

Expected output:

```
 order_id | order_total
----------+-------------
      201 |      125.97
      202 |       89.99
      203 |      249.50
      204 |      599.99
      205 |      149.99
      206 |       89.99
      207 |      199.99
(7 rows)
```

Order 208 is excluded because it has no `total_amount` key - without the `new_data ? 'total_amount'` guard, casting a missing key (`NULL ->> ... ::NUMERIC`) would return NULL rather than erroring, but it is clearer to filter it out explicitly.

---

## Task 2: Find Status Changes for a Specific Order

When an order is updated, both `old_data` and `new_data` are captured. Write a query that returns all status changes for `order_id = 201`, showing the old status and new status.

### Answer

```sql
SELECT
  changed_at,
  old_data ->> 'status' AS old_status,
  new_data ->> 'status' AS new_status
FROM audit_log
WHERE operation = 'UPDATE'
  AND table_name = 'orders'
  AND (new_data ->> 'order_id')::INTEGER = 201
  AND old_data ->> 'status' IS DISTINCT FROM new_data ->> 'status'
ORDER BY changed_at ASC;
```

Expected output:

```
       changed_at       | old_status | new_status
------------------------+------------+------------
 2026-08-02 10:00:00+00 | pending    | shipped
 2026-08-04 08:00:00+00 | shipped    | delivered
(2 rows)
```

Order 201 went pending -> shipped -> delivered. `IS DISTINCT FROM` is used instead of `<>` because it treats NULL safely - a plain `<>` would silently drop rows where either side is NULL.

---

## Task 3: Revenue by Customer from Audit Log

Write a query that:
1. Counts how many `INSERT` events exist per unique `customer_id` in `new_data`
2. Sums the `total_amount` field per customer
3. Shows the top 5 customers by revenue from the log

This should produce results similar to a join against the `orders` table - but derived purely from the JSON payload.

### Answer

```sql
SELECT
  (new_data ->> 'customer_id')::INTEGER AS customer_id,
  COUNT(*) AS order_count,
  ROUND(SUM((new_data ->> 'total_amount')::NUMERIC), 2) AS total_revenue
FROM audit_log
WHERE operation = 'INSERT'
  AND table_name = 'orders'
  AND new_data ? 'customer_id'
  AND new_data ? 'total_amount'
GROUP BY (new_data ->> 'customer_id')::INTEGER
ORDER BY total_revenue DESC
LIMIT 5;
```

Expected output:

```
 customer_id | order_count | total_revenue
-------------+-------------+---------------
           3 |           1 |        599.99
           1 |           3 |        575.46
           2 |           2 |        239.98
           4 |           1 |         89.99
(4 rows)
```

Only 4 rows appear because only 4 distinct customers show up across the 7 INSERT events that have both `customer_id` and `total_amount` (customer 5's order 208 is excluded - it is missing `total_amount`).

---

## Task 4: Containment Filter and GIN Index

### Part A - Containment Query

Use the `@>` operator to find all log entries where `new_data` contains `{"status": "cancelled"}`:

```sql
SELECT log_id, changed_at, new_data
FROM audit_log
WHERE new_data @> '{"status": "cancelled"}';
```

Expected output:

```
 log_id |       changed_at       |                 new_data
--------+------------------------+-------------------------------------------
     11 |  2026-08-02 11:15:00+00 | {"status": "cancelled", "order_id": 202}
     14 |  2026-08-03 09:40:00+00 | {"status": "cancelled", "order_id": 204}
(2 rows)
```

### Part B - Check the Plan

Run EXPLAIN to see if an index is used:

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log WHERE new_data @> '{"status": "cancelled"}';
```

Expected output:

```
                      QUERY PLAN
-----------------------------------------------------------
 Seq Scan on audit_log  (cost=0.00..12.00 rows=2 width=36)
   Filter: (new_data @> '{"status": "cancelled"}'::jsonb)
(2 rows)
```

`Seq Scan` confirms the `@>` operator is not using an index yet - there isn't one on `new_data`.

### Part C - Create a GIN Index

```sql
CREATE INDEX idx_audit_new_data_gin ON audit_log USING GIN (new_data);
```

Run EXPLAIN again:

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log WHERE new_data @> '{"status": "cancelled"}';
```

Expected output:

```
                     QUERY PLAN
----------------------------------------------------------
 Seq Scan on audit_log  (cost=0.00..1.19 rows=1 width=36)
   Filter: (new_data @> '{"status": "cancelled"}'::jsonb)
(2 rows)
```

With only 15 rows in this table, the planner still picks `Seq Scan` even with the GIN index in place - scanning 15 rows directly is cheaper than an index lookup. This matches what you saw in build guide 05: an index existing does not mean PostgreSQL will use it on a small table. The GIN index becomes the winning plan once the table holds enough rows (typically thousands+) that a full scan is measurably more expensive than the index path. Do not assume a `CREATE INDEX` "worked" just because it ran without error - always re-run EXPLAIN to confirm.

---

## Task 5: Build a Pivot from JSON

Write a query that shows, for each `operation` type, how many events occurred. Then extend it to show events per hour of day across all operation types.

**Part A:**

```sql
SELECT operation, COUNT(*) AS event_count
FROM audit_log
GROUP BY operation
ORDER BY event_count DESC;
```

Expected output:

```
 operation | event_count
-----------+-------------
 INSERT    |           8
 UPDATE    |           7
(2 rows)
```

**Part B:**

```sql
SELECT
  EXTRACT(HOUR FROM changed_at)::INT AS hour_of_day,
  operation,
  COUNT(*) AS event_count
FROM audit_log
GROUP BY hour_of_day, operation
ORDER BY hour_of_day, event_count DESC;
```

Expected output:

```
 hour_of_day | operation | event_count
-------------+-----------+-------------
           8 | UPDATE    |           1
           9 | INSERT    |           5
           9 | UPDATE    |           3
          10 | UPDATE    |           2
          11 | UPDATE    |           1
          14 | INSERT    |           1
          16 | INSERT    |           1
          20 | INSERT    |           1
(8 rows)
```

---

## Stretch: Find Rows Missing a Required Key in new_data

Find all `INSERT` events on orders that are missing the `total_amount` field in their `new_data`. These would be data quality problems.

**Hint:** Use `NOT (new_data ? 'total_amount')` or `new_data ->> 'total_amount' IS NULL`.

### Answer

```sql
SELECT log_id, changed_at, new_data
FROM audit_log
WHERE operation = 'INSERT'
  AND table_name = 'orders'
  AND NOT (new_data ? 'total_amount');
```

Expected output:

```
 log_id |       changed_at       |                         new_data
--------+------------------------+-----------------------------------------------------------
      8 | 2026-08-03 20:10:00+00 | {"status": "pending", "order_id": 208, "customer_id": 5}
(1 row)
```

This is order 208, seeded at the top of this guide with `total_amount` deliberately omitted - exactly the kind of row Task 1 and Task 3 had to filter out.

---

## Cleanup

```sql
DROP TABLE IF EXISTS audit_log;
```

---

## Exit

```sql
\q
```

```bash
exit
```

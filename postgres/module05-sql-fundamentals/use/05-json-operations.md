# Exercise 05: JSON Operations

**Duration:** 25 minutes
**Objective:** Query the `audit_log` JSONB columns to extract fields, filter by JSON values, aggregate JSON data, and understand when to add a GIN index.

**Prerequisites:** Build guide 05 (advanced SQL) complete.

---

## Background

The `stepup_store` database has an `audit_log` table populated by a trigger on the `orders` table. Every INSERT, UPDATE, and DELETE is captured with the old and new row data stored as JSONB. Your job is to extract meaningful data from this JSON using PostgreSQL's native JSONB operators.

The `audit_log` columns are: `log_id`, `table_name`, `operation`, `old_data` (JSONB), `new_data` (JSONB), `changed_by`, `changed_at`.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

First, look at a sample of the data to understand the structure:

```sql
SELECT operation, new_data FROM audit_log LIMIT 10;
```

---

## Task 1: Extract and Display Fields

Write a query that shows the `order_id` and `total_amount` from every `INSERT` operation on the orders table. The `new_data` payload looks like:

```json
{"order_id": 1, "customer_id": 5, "total_amount": 125.97, "status": "completed", "quantity": 2, "order_date": "2026-04-15", "tenant_id": null}
```

Requirements:
- Filter for `operation = 'INSERT'` and `table_name = 'orders'`
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
ORDER BY order_id ASC;
```

---

## Task 2: Find Status Changes for a Specific Order

When an order is updated, both `old_data` and `new_data` are captured. Write a query that returns all status changes for `order_id = 1`, showing the old status and new status.

### Answer

```sql
SELECT
  changed_at,
  old_data ->> 'status' AS old_status,
  new_data ->> 'status' AS new_status
FROM audit_log
WHERE operation = 'UPDATE'
  AND table_name = 'orders'
  AND (new_data ->> 'order_id')::INTEGER = 1
  AND old_data ->> 'status' IS DISTINCT FROM new_data ->> 'status'
ORDER BY changed_at ASC;
```

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

---

## Task 4: Containment Filter and GIN Index

### Part A - Containment Query

Use the `@>` operator to find all log entries where `new_data` contains `{"status": "cancelled"}`:

```sql
SELECT log_id, changed_at, new_data
FROM audit_log
WHERE new_data @> '{"status": "cancelled"}';
```

### Part B - Check the Plan

Run EXPLAIN to see if an index is used:

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log WHERE new_data @> '{"status": "cancelled"}';
```

If you see `Seq Scan`, the `@>` operator is not using an index.

### Part C - Create a GIN Index

```sql
CREATE INDEX idx_audit_new_data_gin ON audit_log USING GIN (new_data);
```

Run EXPLAIN again:

```sql
EXPLAIN SELECT log_id, new_data FROM audit_log WHERE new_data @> '{"status": "cancelled"}';
```

With the GIN index, the plan should switch to a `Bitmap Index Scan on idx_audit_new_data_gin`.

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

---

## Exit

```sql
\q
```

```bash
exit
```

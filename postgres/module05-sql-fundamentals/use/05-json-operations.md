# Exercise 05: JSON Operations

**Duration:** 25 minutes
**Objective:** Query the `audit_log` JSONB column to extract fields, filter by JSON values, aggregate JSON data, and understand when to add a GIN index.

**Prerequisites:** Build guide 05 (advanced SQL) complete.

---

## Background

The Pulse app writes every significant event to `audit_log.payload` as JSONB. Business analysts want to query this log to understand usage patterns. Your job is to extract meaningful data from unstructured JSON using PostgreSQL's native JSONB operators.

Connect before starting:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

First, look at a sample of the data to understand the payload structure:

```sql
SELECT event_type, payload FROM audit_log LIMIT 10;
```

---

## Task 1: Extract and Display Fields

Write a query that shows the `order_id` and `total` from every `order_created` event. The payload looks like:

```json
{"order_id": 1, "customer_id": 5, "total": 125.97, "status": "pending"}
```

Requirements:
- Filter for `event_type = 'order_created'` rows
- Extract `order_id` as an integer
- Extract `total` as a numeric value rounded to 2 decimal places
- Order by `order_id` ascending

### Answer

```sql
SELECT
  (payload ->> 'order_id')::INTEGER AS order_id,
  ROUND((payload ->> 'total')::NUMERIC, 2) AS order_total
FROM audit_log
WHERE event_type = 'order_created'
ORDER BY order_id ASC;
```

---

## Task 2: Find Status Changes for a Specific Order

The `order_updated` payload looks like:

```json
{"order_id": 3, "field": "status", "old": "pending", "new": "completed"}
```

Write a query that returns all status change events for `order_id = 1`, showing the old status and new status.

### Answer

```sql
SELECT
  logged_at,
  payload ->> 'old' AS old_status,
  payload ->> 'new' AS new_status
FROM audit_log
WHERE event_type = 'order_updated'
  AND payload ->> 'field' = 'status'
  AND (payload ->> 'order_id')::INTEGER = 1
ORDER BY logged_at ASC;
```

---

## Task 3: Revenue by Event Count

Write a query that:
1. Counts how many `order_created` events exist per unique `customer_id` in the payload
2. Sums the `total` field per customer
3. Shows the top 5 customers by revenue from the log

This should produce results similar to a join against the `orders` table - but derived purely from the JSON payload.

### Answer

```sql
SELECT
  (payload ->> 'customer_id')::INTEGER AS customer_id,
  COUNT(*) AS order_count,
  ROUND(SUM((payload ->> 'total')::NUMERIC), 2) AS total_revenue
FROM audit_log
WHERE event_type = 'order_created'
  AND payload ? 'customer_id'
  AND payload ? 'total'
GROUP BY (payload ->> 'customer_id')::INTEGER
ORDER BY total_revenue DESC
LIMIT 5;
```

---

## Task 4: Containment Filter and GIN Index

### Part A - Containment Query

Use the `@>` operator to find all log entries where the payload contains `{"status": "cancelled"}`:

```sql
SELECT log_id, logged_at, payload
FROM audit_log
WHERE payload @> '{"status": "cancelled"}';
```

### Part B - Check the Plan

Run EXPLAIN to see if an index is used:

```sql
EXPLAIN SELECT log_id, payload FROM audit_log WHERE payload @> '{"field": "status"}';
```

If you see `Seq Scan`, the `@>` operator is not using an index.

### Part C - Create a GIN Index

```sql
CREATE INDEX idx_audit_payload_gin ON audit_log USING GIN (payload);
```

Run EXPLAIN again:

```sql
EXPLAIN SELECT log_id, payload FROM audit_log WHERE payload @> '{"field": "status"}';
```

With the GIN index, the plan should switch to a `Bitmap Index Scan on idx_audit_payload_gin`.

---

## Task 5: Build a Pivot from JSON

Write a query that shows, for each `event_type`, how many events occurred. Then extend it to show events per hour of day across all event types.

**Part A:**

```sql
SELECT event_type, COUNT(*) AS event_count
FROM audit_log
GROUP BY event_type
ORDER BY event_count DESC;
```

**Part B:**

```sql
SELECT
  EXTRACT(HOUR FROM logged_at)::INT AS hour_of_day,
  event_type,
  COUNT(*) AS event_count
FROM audit_log
GROUP BY hour_of_day, event_type
ORDER BY hour_of_day, event_count DESC;
```

---

## Stretch: Find Payloads Missing a Required Key

Find all `order_created` events that are missing the `total` field in their payload. These would be data quality problems.

**Hint:** Use `NOT (payload ? 'total')` or `payload ->> 'total' IS NULL`.

### Answer

```sql
SELECT log_id, logged_at, payload
FROM audit_log
WHERE event_type = 'order_created'
  AND NOT (payload ? 'total');
```

---

## Exit

```sql
\q
```

```bash
exit
```

# USE 04 - Tune Autovacuum for Large Tables

**Time:** 45 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 10 complete. Custom parameter group applied.

---

## Objective

Given three large tables with different write patterns, apply the correct per-table autovacuum settings for each, trigger and verify autovacuum behavior, and prevent TXID wraparound on the highest-risk table.

---

## Setup - Create Three Tables with Different Patterns

```sql
-- Table 1: High-volume INSERT/UPDATE (e.g., order statuses)
CREATE TABLE orders_hot (
    order_id BIGSERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    status TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Table 2: Append-only (e.g., event log) - very few dead tuples
CREATE TABLE events_log (
    event_id BIGSERIAL PRIMARY KEY,
    event_type TEXT NOT NULL,
    payload JSONB,
    logged_at TIMESTAMPTZ DEFAULT now()
);

-- Table 3: Large, rarely updated (e.g., historical archive)
CREATE TABLE orders_archive (
    order_id BIGINT PRIMARY KEY,
    customer_id INT NOT NULL,
    status TEXT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    archived_at TIMESTAMPTZ DEFAULT now()
);

-- Load data
INSERT INTO orders_hot (customer_id, status, amount)
SELECT
    (random() * 50000)::INT,
    CASE (random() * 3)::INT WHEN 0 THEN 'pending' WHEN 1 THEN 'processing' ELSE 'completed' END,
    (random() * 500)::NUMERIC(12,2)
FROM generate_series(1, 1000000);

INSERT INTO events_log (event_type, payload)
SELECT
    CASE (random() * 4)::INT WHEN 0 THEN 'login' WHEN 1 THEN 'purchase' WHEN 2 THEN 'view' ELSE 'search' END,
    ('{"user_id": ' || (random() * 50000)::INT || ', "ts": "' || now()::TEXT || '"}')::JSONB
FROM generate_series(1, 2000000);

INSERT INTO orders_archive (order_id, customer_id, status, amount)
SELECT
    g,
    (random() * 100000)::INT,
    'completed',
    (random() * 1000)::NUMERIC(12,2)
FROM generate_series(1, 5000000) g;

ANALYZE orders_hot, events_log, orders_archive;
```

---

## Task 1 - Establish the Baseline

Before tuning, understand where each table stands:

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze,
    age(relfrozenxid) AS xid_age,
    pg_size_pretty(pg_total_relation_size(relid)) AS size
FROM pg_stat_user_tables
WHERE relname IN ('orders_hot', 'events_log', 'orders_archive')
ORDER BY relname;
```

Write down the baseline values. You need them for comparison after tuning.

---

## Task 2 - Simulate Write Activity

Generate dead tuples in orders_hot:

```sql
-- Simulate 6 rounds of order status updates (creates dead tuples)
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..6 LOOP
        UPDATE orders_hot
        SET status = CASE status
            WHEN 'pending' THEN 'processing'
            WHEN 'processing' THEN 'completed'
            ELSE 'pending'
        END,
        updated_at = now()
        WHERE order_id % 5 = i % 5;

        RAISE NOTICE 'Round % complete', i;
        PERFORM pg_sleep(1);
    END LOOP;
END $$;
```

Check dead tuple accumulation:

```sql
SELECT
    relname,
    n_live_tup,
    n_dead_tup,
    round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
WHERE relname = 'orders_hot';
```

Expected output (yours will differ):
```
    relname    | n_live_tup | n_dead_tup | dead_pct
---------------+------------+------------+----------
 orders_hot    |    1000000 |     600000 |    37.50
```

37.5% dead tuples. With default autovacuum_vacuum_scale_factor=0.2, vacuum triggered at 20% dead. It should have already run - but it may not have had time. The critical point is that it is now above 20%, so autovacuum will run within the next naptime interval.

---

## Task 3 - Apply Per-Table Settings

**Table 1 (orders_hot): High urgency - vacuum aggressively:**

```sql
ALTER TABLE orders_hot SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 500,
    autovacuum_analyze_scale_factor = 0.005,
    autovacuum_analyze_threshold = 250,
    autovacuum_vacuum_cost_delay = 2,
    autovacuum_vacuum_cost_limit = 800
);
```

Reasoning: 1% threshold means autovacuum runs when 10,000 of 1M rows are dead. Cost delay=2ms makes it run aggressively. High cost limit allows more work per pass.

**Table 2 (events_log): Append-only - relax vacuum, more frequent analyze:**

```sql
ALTER TABLE events_log SET (
    autovacuum_vacuum_scale_factor = 0.5,
    autovacuum_vacuum_threshold = 10000,
    autovacuum_analyze_scale_factor = 0.01,
    autovacuum_analyze_threshold = 1000,
    autovacuum_vacuum_cost_delay = 20
);
```

Reasoning: Since this table is append-only (no updates or deletes in production), dead tuples accumulate only from HOT updates. High vacuum threshold saves resources. Frequent analyze keeps statistics fresh as new rows arrive.

**Table 3 (orders_archive): Large, rarely updated - freeze aggressively:**

```sql
ALTER TABLE orders_archive SET (
    autovacuum_vacuum_scale_factor = 0.01,
    autovacuum_vacuum_threshold = 1000,
    autovacuum_vacuum_insert_scale_factor = 0.1,
    autovacuum_freeze_max_age = 100000000,
    autovacuum_vacuum_cost_delay = 10
);
```

`autovacuum_freeze_max_age = 100000000`: Start aggressive freeze when XID age reaches 100M (default 200M). Important for a large archive that does not get vacuumed often.

---

## Task 4 - Manually Vacuum and Check Results

Trigger vacuum on orders_hot to verify settings took effect:

```sql
VACUUM (VERBOSE, ANALYZE) orders_hot;
```

Expected output (yours will differ):
```
INFO:  vacuuming "public.orders_hot"
INFO:  scanned index "orders_hot_pkey" to remove 600000 row versions
INFO:  "orders_hot": removed 600000 row versions in 8334 pages
INFO:  "orders_hot": found 600000 removable, 1000000 nonremovable row versions
...
```

Check the table after vacuum:

```sql
SELECT
    relname,
    n_dead_tup,
    last_vacuum,
    age(relfrozenxid) AS xid_age
FROM pg_stat_user_tables
WHERE relname = 'orders_hot';
```

Expected output (yours will differ):
```
    relname    | n_dead_tup |          last_vacuum           | xid_age
---------------+------------+--------------------------------+---------
 orders_hot    |          0 | 2024-01-31 14:23:01.123456+00  |   12345
```

`n_dead_tup = 0` confirms vacuum ran successfully.

---

## Task 5 - Freeze the Archive Table

The archive table has 5M rows that may have accumulated XID age:

```sql
-- Check XID age
SELECT
    relname,
    age(relfrozenxid) AS xid_age
FROM pg_class
WHERE relname = 'orders_archive';

-- Freeze all old tuples
VACUUM (FREEZE, VERBOSE, ANALYZE) orders_archive;
```

Expected output (yours will differ):
```
INFO:  aggressively vacuuming "public.orders_archive"
INFO:  scanned index "orders_archive_pkey" to remove 0 row versions
INFO:  "orders_archive": found 0 removable, 5000000 nonremovable row versions
INFO:  "orders_archive": page 0 now contains 0 newly dead item identifiers
INFO:  vacuuming "pg_toast_12345"
INFO:  "orders_archive": VACUUM found 5000000 pages with 0 dead tuples...
```

Verify XID age dropped:

```sql
SELECT
    relname,
    age(relfrozenxid) AS xid_age_after_freeze
FROM pg_class
WHERE relname = 'orders_archive';
```

The XID age should now be very low (near 0) since all tuples are frozen.

---

## Task 6 - Monitor Autovacuum is Running

Run more updates on orders_hot and watch autovacuum pick them up:

```sql
-- Create enough dead tuples to trigger autovacuum (threshold = 500 with our new settings)
UPDATE orders_hot SET status = 'processing' WHERE order_id % 100 = 0;
```

Wait 2-3 minutes (naptime = 60s, autovacuum will wake up and check), then:

```sql
SELECT
    schemaname,
    relname,
    last_autovacuum,
    autovacuum_count,
    n_dead_tup
FROM pg_stat_user_tables
WHERE relname = 'orders_hot';
```

If `last_autovacuum` has updated, autovacuum is working with the new thresholds.

---

## Completion Checklist

- [ ] Measured baseline dead tuple counts and XID ages for all 3 tables
- [ ] Applied aggressive settings to orders_hot (1% scale factor, 2ms cost delay)
- [ ] Applied relaxed settings to events_log (50% scale factor, append-only optimization)
- [ ] Applied freeze-priority settings to orders_archive
- [ ] Ran VACUUM FREEZE on orders_archive and confirmed XID age near 0
- [ ] Confirmed autovacuum picked up orders_hot within 2 minutes of generating dead tuples

---

## Cleanup

```sql
DROP TABLE IF EXISTS orders_hot;
DROP TABLE IF EXISTS events_log;
DROP TABLE IF EXISTS orders_archive;
```

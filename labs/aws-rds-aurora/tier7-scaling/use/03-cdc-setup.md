# Tier 7 - USE Exercise 03: CDC Setup

**Exercise type:** Hands-on implementation
**Time:** 40 minutes
**Goal:** Build a complete CDC (Change Data Capture) event stream from Aurora PostgreSQL, design an event schema, and wire it to a downstream consumer.
**Prerequisites:** Build 05 completed. Two RDS PostgreSQL instances with logical replication configured.

---

## Overview

You will implement a CDC architecture where:
1. Changes to the `orders` table generate structured events in an `outbox` table.
2. Those events replicate to a subscriber database via logical replication.
3. A consumer reads from the subscriber and processes events.
4. You monitor lag and handle the case where the consumer falls behind.

---

## Part 1: Design the Outbox Pattern

The Outbox Pattern avoids dual-write consistency problems. Instead of writing to the database AND publishing an event in the same operation (which can fail halfway), you write ONLY to the database. The database then serves as the event source.

**Step 1.** Create the outbox table on the source:

```sql
CREATE TABLE outbox_events (
  event_id        UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  aggregate_type  VARCHAR(50) NOT NULL,  -- e.g., 'ORDER', 'CUSTOMER'
  aggregate_id    BIGINT NOT NULL,        -- the ID of the entity that changed
  event_type      VARCHAR(100) NOT NULL,  -- e.g., 'ORDER_CREATED', 'ORDER_SHIPPED'
  payload         JSONB NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  processed       BOOLEAN DEFAULT FALSE,
  processed_at    TIMESTAMPTZ
);

CREATE INDEX outbox_events_unprocessed ON outbox_events (created_at)
  WHERE NOT processed;

CREATE INDEX outbox_events_aggregate ON outbox_events (aggregate_type, aggregate_id);
```

**Step 2.** Create triggers that populate the outbox automatically:

```sql
-- Trigger for order created
CREATE OR REPLACE FUNCTION outbox_order_created()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
  VALUES (
    'ORDER',
    NEW.order_id,
    'ORDER_CREATED',
    jsonb_build_object(
      'order_id',    NEW.order_id,
      'customer_id', NEW.customer_id,
      'sku',         NEW.product_sku,
      'quantity',    NEW.quantity,
      'price',       NEW.unit_price,
      'status',      NEW.status,
      'created_at',  NEW.created_at
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_created_outbox
  AFTER INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION outbox_order_created();

-- Trigger for order status change
CREATE OR REPLACE FUNCTION outbox_order_status_changed()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status <> NEW.status THEN
    INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
    VALUES (
      'ORDER',
      NEW.order_id,
      'ORDER_STATUS_CHANGED',
      jsonb_build_object(
        'order_id',   NEW.order_id,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'changed_at', NOW()
      )
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER order_status_change_outbox
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION outbox_order_status_changed();
```

**Step 3.** Test the outbox:

```sql
-- Insert a new order
INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
VALUES (42, 'SKU-OUTBOX-TEST', 2, 49.99, 'pending')
RETURNING order_id;

-- Update the status
UPDATE orders SET status = 'processing' WHERE product_sku = 'SKU-OUTBOX-TEST';
UPDATE orders SET status = 'shipped'    WHERE product_sku = 'SKU-OUTBOX-TEST';

-- Check the outbox
SELECT event_type, aggregate_id, payload, created_at
FROM outbox_events
WHERE aggregate_type = 'ORDER'
ORDER BY created_at;
```

Expected output (3 rows: created, status->processing, status->shipped):
```
      event_type       | aggregate_id |            payload             |          created_at
----------------------+--------------+--------------------------------+----------------------------
 ORDER_CREATED        |          502 | {"order_id": 502, ...}         | 2024-03-15 15:00:00+00
 ORDER_STATUS_CHANGED |          502 | {"old_status": "pending", ...} | 2024-03-15 15:00:01+00
 ORDER_STATUS_CHANGED |          502 | {"old_status": "processing",...}| 2024-03-15 15:00:02+00
(3 rows)
```

---

## Part 2: Replicate the Outbox to the Subscriber

Add `outbox_events` to the publication so changes replicate to the subscriber.

**On the source:**

```sql
-- Add outbox to the existing publication
ALTER PUBLICATION tier7_pub ADD TABLE outbox_events;
```

**On the target (subscriber),** create the outbox table schema:

```sql
CREATE TABLE outbox_events (
  event_id        UUID PRIMARY KEY,
  aggregate_type  VARCHAR(50) NOT NULL,
  aggregate_id    BIGINT NOT NULL,
  event_type      VARCHAR(100) NOT NULL,
  payload         JSONB NOT NULL,
  created_at      TIMESTAMPTZ,
  processed       BOOLEAN DEFAULT FALSE,
  processed_at    TIMESTAMPTZ
);

CREATE INDEX outbox_events_unprocessed ON outbox_events (created_at)
  WHERE NOT processed;
```

**On the target,** refresh the subscription to pick up the new table:

```sql
ALTER SUBSCRIPTION tier7_sub REFRESH PUBLICATION;
```

**Verify replication is working:**

On the target, within seconds of the source INSERT:

```sql
SELECT COUNT(*) FROM outbox_events;
```

Should match the count on the source.

---

## Part 3: Build the Event Consumer

Create a consumer script that reads unprocessed outbox events from the subscriber and marks them processed.

**Step 1.** Create the consumer function on the subscriber:

```sql
-- On the subscriber database
CREATE OR REPLACE FUNCTION consume_outbox_events(batch_size INTEGER DEFAULT 100)
RETURNS TABLE(event_id UUID, event_type VARCHAR, result TEXT) AS $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT *
    FROM outbox_events
    WHERE NOT processed
    ORDER BY created_at
    LIMIT batch_size
    FOR UPDATE SKIP LOCKED
  LOOP
    -- Process the event (in reality this would call an external API or insert into another table)
    RAISE NOTICE 'Processing event %: % for aggregate %', rec.event_id, rec.event_type, rec.aggregate_id;

    -- Mark as processed
    UPDATE outbox_events
    SET processed = TRUE, processed_at = NOW()
    WHERE outbox_events.event_id = rec.event_id;

    event_id   := rec.event_id;
    event_type := rec.event_type;
    result     := 'PROCESSED';
    RETURN NEXT;
  END LOOP;
END;
$$ LANGUAGE plpgsql;
```

The `FOR UPDATE SKIP LOCKED` clause is critical: it prevents two concurrent consumer processes from processing the same event. If one consumer has a row locked, other consumers skip it rather than wait.

**Step 2.** Run the consumer:

```sql
SELECT * FROM consume_outbox_events(50);
```

Expected output:
```
              event_id              |     event_type       |  result
------------------------------------+----------------------+-----------
 a1b2c3d4-...                       | ORDER_CREATED        | PROCESSED
 e5f6g7h8-...                       | ORDER_STATUS_CHANGED | PROCESSED
 i9j0k1l2-...                       | ORDER_STATUS_CHANGED | PROCESSED
(3 rows)
```

**Step 3.** Verify events are marked processed:

```sql
SELECT processed, COUNT(*) FROM outbox_events GROUP BY processed;
```

Expected output:
```
 processed | count
-----------+-------
 t         |     3
(1 row)
```

---

## Part 4: Monitor CDC Lag

**Step 1.** On the source, check the replication slot lag:

```sql
SELECT
  slot_name,
  active,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  ) AS consumer_lag
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

**Step 2.** Create a lag monitoring view on the source:

```sql
CREATE VIEW replication_health AS
SELECT
  slot_name,
  active AS is_consuming,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
  ) AS wal_retained,
  pg_size_pretty(
    pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)
  ) AS consumer_lag,
  CASE
    WHEN NOT active THEN 'WARNING: slot is not actively consuming'
    WHEN pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn) > 1073741824 THEN 'WARNING: lag exceeds 1 GiB'
    ELSE 'OK'
  END AS health_status
FROM pg_replication_slots
WHERE slot_type = 'logical';
```

```sql
SELECT * FROM replication_health;
```

**Step 3.** Simulate a consumer falling behind:

On the target, pause the subscription:

```sql
ALTER SUBSCRIPTION tier7_sub DISABLE;
```

On the source, generate a burst of events:

```sql
-- Insert 1000 orders rapidly
INSERT INTO orders (customer_id, product_sku, quantity, unit_price, status)
SELECT
  (RANDOM() * 999 + 1)::INTEGER,
  'SKU-BURST-' || gs,
  1,
  19.99,
  'pending'
FROM generate_series(1, 1000) gs;
```

Check lag on the source:

```sql
SELECT * FROM replication_health;
```

You should see `consumer_lag` growing.

Re-enable the subscription and watch lag drain:

```sql
-- On the target:
ALTER SUBSCRIPTION tier7_sub ENABLE;

-- On the source, poll every 5 seconds:
SELECT slot_name, pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag
FROM pg_replication_slots;
```

---

## Part 5: Operational Questions

Answer these after completing the hands-on work:

1. The `FOR UPDATE SKIP LOCKED` clause in the consumer prevents duplicate processing. What would happen WITHOUT it if two consumer processes ran simultaneously?

2. You have 1 million unprocessed outbox events because the consumer was offline for 2 days. The consumer restarts with `batch_size=100`. How long will it take to catch up if each batch takes 500ms to process? What would you change to speed this up?

3. The source database disk is 95% full. There are no downstream consumers - all replication slots are unconsumed. What is the immediate action you take and why?

4. A new table, `shipments`, is added to the source database. Does it automatically appear in the subscription? What must you do to add it?

5. You want to ensure CDC events are never lost even if the subscriber goes offline for up to 7 days. What storage capacity must you provision on the source to guarantee this? What information do you need to calculate this?

---

## Validation Checklist

- [ ] `outbox_events` table exists on both source and subscriber.
- [ ] Triggers fire correctly - inserting an order creates an `ORDER_CREATED` event in the outbox.
- [ ] Updating order status creates an `ORDER_STATUS_CHANGED` event.
- [ ] Events replicate from source outbox to subscriber outbox within 5 seconds.
- [ ] `consume_outbox_events()` function marks events as processed.
- [ ] `replication_health` view shows `OK` status when the subscription is active.
- [ ] You observed lag grow when the subscription was paused and drain when re-enabled.

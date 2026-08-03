# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 05: Logical Replication and CDC Patterns

**Objective:** Configure logical replication between two RDS PostgreSQL instances, create publications and subscriptions, monitor replication slot lag, and understand CDC patterns for event-driven architectures.
**Time:** 50 minutes
**Prerequisites:** Two RDS PostgreSQL instances in the same region (or accessible to each other). Both must be on PostgreSQL 10+. Logical replication parameter enabled on the source.
**Infrastructure:** You will use two RDS instances. Create a second `db.t3.micro` or `db.t3.small` instance for the subscriber if you do not have one.

---

## 1. Architecture Overview

In this lab:
- **Source (Publisher)**: The primary database where writes happen. We call it `rds-source`.
- **Destination (Subscriber)**: The database that receives replicated changes. We call it `rds-target`.

Logical replication uses the WAL. The source decodes WAL changes into row-level events and streams them to the subscriber via a replication slot.

Unlike read replicas (which replicate the entire instance), logical replication can replicate specific tables and databases. The subscriber is a writable database - you can have local tables that are not replicated.

---

## 2. Prepare the Source Instance

### Enable Logical Replication

If you completed Build 03, your source cluster already has `rds.logical_replication=1`. Verify:

Connect to the source database:

```sql
SHOW wal_level;
SHOW max_replication_slots;
SHOW max_wal_senders;
```

Expected output:
```
 wal_level
-----------
 logical
(1 row)

 max_replication_slots
-----------------------
 10
(1 row)

 max_wal_senders
-----------------
 10
(1 row)
```

If `wal_level` is not `logical`, apply the parameter group change from Build 03, Step A2 before continuing.

### Create the Source Schema and Data

```sql
-- Connect to the source database

CREATE DATABASE replication_lab;

\c replication_lab

CREATE TABLE products (
  product_id   SERIAL PRIMARY KEY,
  sku          VARCHAR(50) UNIQUE NOT NULL,
  name         VARCHAR(200) NOT NULL,
  price        NUMERIC(10,2) NOT NULL,
  stock_count  INTEGER NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE product_events (
  event_id    SERIAL PRIMARY KEY,
  product_id  INTEGER NOT NULL,
  event_type  VARCHAR(50) NOT NULL,
  old_price   NUMERIC(10,2),
  new_price   NUMERIC(10,2),
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO products (sku, name, price, stock_count)
SELECT
  'SKU-' || gs,
  'Product ' || gs,
  (RANDOM() * 100 + 5)::NUMERIC(10,2),
  (RANDOM() * 500)::INTEGER
FROM generate_series(1, 500) gs;
```

### Create a Replication User

Do not use the master user for replication. Create a dedicated user.

```sql
CREATE USER replicator WITH REPLICATION LOGIN PASSWORD '[REPLICATION-PASSWORD]';

GRANT USAGE ON SCHEMA public TO replicator;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO replicator;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO replicator;
```

The `REPLICATION` attribute is required for a user to create replication connections. The `SELECT` grants are needed for the initial data copy (the subscription copies the existing rows before starting to stream WAL).

---

## 3. Create the Publication on the Source

A publication defines what gets replicated. You can publish all tables, specific tables, or specific operations (INSERT, UPDATE, DELETE).

### Console - No direct console support

Publications and subscriptions are PostgreSQL objects created via SQL. There is no RDS console interface for them.

### SQL

Connect to `replication_lab` on the source:

**Step 1.** Create a publication for all tables:

```sql
CREATE PUBLICATION tier7_pub
  FOR TABLE products, product_events
  WITH (publish = 'insert, update, delete');
```

The `FOR TABLE` clause specifies which tables to include. The `WITH (publish = ...)` clause specifies which operation types to include. Omitting this defaults to all three.

**Step 2.** Verify the publication:

```sql
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete
FROM pg_publication;
```

Expected output:
```
   pubname   | puballtables | pubinsert | pubupdate | pubdelete
-------------+--------------+-----------+-----------+-----------
 tier7_pub   | f            | t         | t         | t
(1 row)
```

**Step 3.** Check which tables are included:

```sql
SELECT tablename FROM pg_publication_tables WHERE pubname = 'tier7_pub';
```

Expected output:
```
    tablename
-----------------
 product_events
 products
(1 row)
```

---

## 4. Prepare the Target Instance

Connect to the target RDS PostgreSQL instance.

### Create the Target Schema

The subscriber database must have the same table schema as the publisher. Logical replication does NOT copy DDL - only data. You must create the tables manually on the target.

```sql
CREATE DATABASE replication_lab;

\c replication_lab

-- Same DDL as source (without inserting seed data)
CREATE TABLE products (
  product_id   SERIAL PRIMARY KEY,
  sku          VARCHAR(50) UNIQUE NOT NULL,
  name         VARCHAR(200) NOT NULL,
  price        NUMERIC(10,2) NOT NULL,
  stock_count  INTEGER NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE product_events (
  event_id    SERIAL PRIMARY KEY,
  product_id  INTEGER NOT NULL,
  event_type  VARCHAR(50) NOT NULL,
  old_price   NUMERIC(10,2),
  new_price   NUMERIC(10,2),
  recorded_at TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 5. Create the Subscription on the Target

Connect to `replication_lab` on the **target** instance.

**Step 1.** Create the subscription:

```sql
CREATE SUBSCRIPTION tier7_sub
  CONNECTION 'host=[SOURCE-ENDPOINT] port=5432 dbname=replication_lab user=replicator password=[REPLICATION-PASSWORD] sslmode=require'
  PUBLICATION tier7_pub
  WITH (copy_data = true);
```

Breaking down the options:
- `CONNECTION`: Standard libpq connection string pointing to the source.
- `PUBLICATION tier7_pub`: The name of the publication on the source to subscribe to.
- `copy_data = true`: Copy all existing rows from the source tables before starting to stream new changes. Set to `false` if you have already seeded the target data separately.

**Step 2.** Check the subscription status:

```sql
SELECT subname, subenabled, subslotname, substatus
FROM pg_stat_subscription;
```

Expected output:
```
  subname   | subenabled |   subslotname   | substatus
------------+------------+-----------------+-----------
 tier7_sub  | t          | tier7_sub       | streaming
(1 row)
```

The `streaming` status means the subscription is connected and receiving WAL changes.

**Step 3.** Verify data was copied from the source:

```sql
SELECT COUNT(*) FROM products;
```

Expected output:
```
 count
-------
   500
(1 row)
```

The 500 rows from the source were copied during the initial sync.

---

## 6. Test Replication

### Test INSERT

On the **source**:

```sql
\c replication_lab

INSERT INTO products (sku, name, price, stock_count)
VALUES ('SKU-NEW-001', 'New Product Alpha', 29.99, 100);
```

On the **target**, within a few seconds:

```sql
SELECT * FROM products WHERE sku = 'SKU-NEW-001';
```

Expected output:
```
 product_id |    sku      |        name         | price | stock_count |         updated_at
------------+-------------+---------------------+-------+-------------+----------------------------
        501 | SKU-NEW-001 | New Product Alpha   | 29.99 |         100 | 2024-03-15 14:30:00+00
(1 row)
```

### Test UPDATE

On the **source**:

```sql
UPDATE products SET price = 34.99, updated_at = NOW() WHERE sku = 'SKU-NEW-001';
```

On the **target**:

```sql
SELECT sku, price FROM products WHERE sku = 'SKU-NEW-001';
```

Expected output:
```
    sku      | price
-------------+-------
 SKU-NEW-001 | 34.99
(1 row)
```

### Test DELETE

On the **source**:

```sql
DELETE FROM products WHERE sku = 'SKU-NEW-001';
```

On the **target**:

```sql
SELECT COUNT(*) FROM products WHERE sku = 'SKU-NEW-001';
```

Expected output:
```
 count
-------
     0
(1 row)
```

---

## 7. Monitor Replication Slots and Lag

### On the Source

Replication slots track how far the subscriber has consumed WAL. Monitor them closely.

**Step 1.** Check active slots:

```sql
SELECT
  slot_name,
  plugin,
  slot_type,
  database,
  active,
  restart_lsn,
  confirmed_flush_lsn,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag_size
FROM pg_replication_slots;
```

Expected output:
```
  slot_name  |  plugin   | slot_type |    database    | active | restart_lsn | confirmed_flush_lsn | lag_size
-------------+-----------+-----------+----------------+--------+-------------+---------------------+----------
 tier7_sub   | pgoutput  | logical   | replication_lab| t      | 0/3000000   | 0/3000028           | 0 bytes
(1 row)
```

The `lag_size` column shows how much WAL has accumulated that the subscriber has not yet consumed. `0 bytes` means fully caught up.

**Step 2.** Check via CloudWatch (for RDS):

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name OldestReplicationSlotLag \
  --dimensions Name=DBInstanceIdentifier,Value=[SOURCE-INSTANCE-IDENTIFIER] \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Maximum \
  --region [REGION]
```

The `OldestReplicationSlotLag` metric reports WAL lag in megabytes. Any value above 1,000 MB (1 GiB) warrants investigation.

### Create a CloudWatch Alarm for Slot Lag

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "[SOURCE-INSTANCE]-replication-lag-high" \
  --alarm-description "Logical replication slot lag exceeding 5 GiB" \
  --metric-name OldestReplicationSlotLag \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=[SOURCE-INSTANCE-IDENTIFIER] \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 5120 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:[REGION]:[ACCOUNT-ID]:rds-storage-alerts \
  --region [REGION]
```

The threshold `5120` is 5 GiB in megabytes. Adjust based on your storage headroom.

### Simulate Lag

On the **target**, pause the subscription:

```sql
ALTER SUBSCRIPTION tier7_sub DISABLE;
```

On the **source**, generate changes:

```sql
UPDATE products SET price = price * 1.1;
UPDATE products SET stock_count = stock_count - 10 WHERE stock_count > 10;
```

Check the lag:

```sql
SELECT
  slot_name,
  pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), confirmed_flush_lsn)) AS lag_size
FROM pg_replication_slots
WHERE slot_name = 'tier7_sub';
```

Expected output (lag has grown because the subscription was paused):
```
  slot_name  | lag_size
-------------+----------
 tier7_sub   | 2856 kB
(1 row)
```

Re-enable the subscription to let it catch up:

```sql
ALTER SUBSCRIPTION tier7_sub ENABLE;
```

---

## 8. CDC Pattern: Building an Event Stream

Logical replication enables CDC. Here is a practical pattern: capture all product price changes as events.

On the **source**, create a trigger to log price changes:

```sql
CREATE OR REPLACE FUNCTION log_price_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.price <> NEW.price THEN
    INSERT INTO product_events (product_id, event_type, old_price, new_price)
    VALUES (NEW.product_id, 'PRICE_CHANGE', OLD.price, NEW.price);
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER product_price_change_cdc
  AFTER UPDATE OF price ON products
  FOR EACH ROW
  EXECUTE FUNCTION log_price_change();
```

Now update a product price on the source:

```sql
UPDATE products SET price = 59.99 WHERE product_id = 1;
```

Check the event log on the source:

```sql
SELECT * FROM product_events WHERE product_id = 1;
```

Expected output:
```
 event_id | product_id | event_type   | old_price | new_price |        recorded_at
----------+------------+--------------+-----------+-----------+----------------------------
        1 |          1 | PRICE_CHANGE |     42.15 |     59.99 | 2024-03-15 14:45:00+00
(1 row)
```

Within seconds, check on the **target** - both the product price change AND the event row should have replicated:

```sql
SELECT p.price, pe.event_type, pe.old_price, pe.new_price
FROM products p
JOIN product_events pe ON p.product_id = pe.product_id
WHERE p.product_id = 1;
```

Both the data change and the event record replicate together because they were part of the same transaction. This is the foundation of CDC-driven event architectures: the event table is the event bus.

### Consuming CDC Events

A consumer application (or tool like Debezium) would:
1. Connect to the source using a replication slot with the `pgoutput` or `wal2json` plugin.
2. Stream row-level change events.
3. Publish those events to Kafka, SQS, or another message bus.
4. Downstream services subscribe to the message bus and react to changes.

The key advantage: the database is the source of truth for events. No application code is needed to publish events - the WAL is the event stream.

---

## 9. Tear Down

On the **target**, drop the subscription:

```sql
DROP SUBSCRIPTION tier7_sub;
```

Dropping the subscription also drops the replication slot on the source. Verify:

```sql
-- On the source:
SELECT slot_name FROM pg_replication_slots;
```

The result should be empty (or not include `tier7_sub`).

On the **source**, drop the publication:

```sql
DROP PUBLICATION tier7_pub;
```

---

## Summary

What you did in this lab:

- Enabled logical replication on the source RDS instance.
- Created a dedicated replication user with the minimum required privileges.
- Created a publication specifying which tables and operations to replicate.
- Created a subscription on the target, which triggered an initial data copy followed by ongoing streaming.
- Tested INSERT, UPDATE, and DELETE replication in real time.
- Monitored replication slot lag using `pg_replication_slots` and CloudWatch `OldestReplicationSlotLag`.
- Set up a CloudWatch alarm for slot lag.
- Simulated lag by pausing the subscription and observed recovery.
- Built a CDC event log using triggers that replicate alongside data changes.

**Key things to remember:**
- Logical replication does NOT replicate DDL. Schema changes on the source must be applied manually to the target before replicating the data change.
- Replication slots hold WAL on the source until the subscriber consumes it. An unconsumed slot + high write volume = disk full. Always monitor `OldestReplicationSlotLag`.
- Drop unused replication slots immediately. They are a silent disk consumer.
- Tables without primary keys need `REPLICA IDENTITY FULL` set or UPDATE/DELETE will fail on the subscriber.
- The `streaming` status in `pg_stat_subscription` confirms the subscription is active. If it shows `down` or `connecting`, check network connectivity and credentials.

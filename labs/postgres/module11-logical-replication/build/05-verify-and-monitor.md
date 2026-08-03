# Build 05 - Verify and Monitor Replication

Confirm the data synced, watch live changes flow, and learn how to monitor replication health.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

---

## Verify the Initial Data Sync

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

When a subscription is created, it automatically copies all existing data from the published tables. This is called the **initial table synchronization**.

Check the row count on the subscriber.

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):
```
 count
-------
    20
(1 row)
```

All 20 rows were copied from the publisher. Verify the actual data.

```sql
SELECT * FROM products ORDER BY id LIMIT 5;
```

Expected output (yours will differ):
```
 id |   name    | price |         created_at
----+-----------+-------+----------------------------
  1 | Product 1 | 45.23 | 2026-06-01 14:30:00.123456
  2 | Product 2 | 12.87 | 2026-06-01 14:30:00.123456
  3 | Product 3 | 78.91 | 2026-06-01 14:30:00.123456
  4 | Product 4 |  3.45 | 2026-06-01 14:30:00.123456
  5 | Product 5 | 56.00 | 2026-06-01 14:30:00.123456
...
```

The data matches the publisher.

---

## Test Live Replication

Leave the psql session open on the subscriber. Switch to your **publisher terminal** (pg-suta-labs-1).

On **pg-suta-labs-1**, as **ec2-user**, reconnect if needed:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Insert 5 new rows on the publisher.

```sql
INSERT INTO products (name, price) VALUES
    ('Laptop Stand', 49.99),
    ('USB-C Hub', 35.50),
    ('Webcam HD', 79.00),
    ('Desk Lamp', 22.75),
    ('Cable Organizer', 12.99);
```

Expected output (yours will differ):
```
INSERT 0 5
```

Switch to your **subscriber terminal** (pg-suta-labs-2). You should still have psql open on labdb.

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Check the count.

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):
```
 count
-------
    25
(1 row)
```

Check the new rows.

```sql
SELECT * FROM products WHERE id > 20 ORDER BY id;
```

Expected output (yours will differ):
```
 id |      name       | price |         created_at
----+-----------------+-------+----------------------------
 21 | Laptop Stand    | 49.99 | 2026-06-01 14:45:00.123456
 22 | USB-C Hub       | 35.50 | 2026-06-01 14:45:00.123456
 23 | Webcam HD       | 79.00 | 2026-06-01 14:45:00.123456
 24 | Desk Lamp       | 22.75 | 2026-06-01 14:45:00.123456
 25 | Cable Organizer | 12.99 | 2026-06-01 14:45:00.123456
...
```

The 5 new rows appeared on the subscriber automatically. Logical replication is working.

---

## Monitor Replication

### On the Subscriber

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Check the subscription status. The `pg_stat_subscription` view shows the replication worker.

```sql
SELECT subname, pid, relid, received_lsn, last_msg_send_time, last_msg_receipt_time
FROM pg_stat_subscription;
```

Expected output (yours will differ):
```
   subname    |  pid  | relid | received_lsn |     last_msg_send_time      |   last_msg_receipt_time
--------------+-------+-------+--------------+-----------------------------+-----------------------------
 products_sub | 12345 |       | 0/5A000168   | 2026-06-01 14:50:00.123456  | 2026-06-01 14:50:00.234567
(1 row)
```

- `pid` - the process ID of the logical replication worker.
- `received_lsn` - the last WAL position received from the publisher.
- A non-null `pid` means the worker is running and connected.

### On the Publisher

Switch to your **publisher terminal** (pg-suta-labs-1).

Still as **postgres** on **pg-suta-labs-1** in the psql session on labdb:

```sql
SELECT pid, usename, application_name, client_addr, state, sent_lsn, write_lsn
FROM pg_stat_replication;
```

Expected output (yours will differ):
```
  pid  | usename    | application_name | client_addr    | state     | sent_lsn   | write_lsn
-------+------------+------------------+----------------+-----------+------------+-----------
 23456 | replicator | products_sub     | 172.31.x.x    | streaming | 0/5A000168 | 0/5A000168
(1 row)
```

- `application_name = products_sub` - this is the logical replication connection (named after the subscription).
- `state = streaming` - the publisher is actively streaming changes to the subscriber.

Check the replication slot created for logical replication.

```sql
SELECT slot_name, plugin, slot_type, active, restart_lsn
FROM pg_replication_slots;
```

Expected output (yours will differ):
```
  slot_name    |  plugin  | slot_type | active | restart_lsn
---------------+----------+-----------+--------+-------------
 standby_slot  |          | physical  | f      | 0/5A000060
 products_sub  | pgoutput | logical   | t      | 0/5A000060
(2 rows)
```

You may see the old `standby_slot` from streaming replication - that is expected. The important row is `products_sub`:

- `slot_type = logical` - this is a logical replication slot (vs physical).
- `plugin = pgoutput` - the built-in logical decoding output plugin.
- `active = t` - the subscriber is currently connected and consuming changes.

---

## Exit Both Terminals

On the **publisher terminal** (pg-suta-labs-1), exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

Do the same on the **subscriber terminal** (pg-suta-labs-2):

```sql
\q
```

```bash
exit
```

---

## Summary

You have successfully:

1. Changed wal_level from `replica` to `logical` on the publisher
2. Created a `products` table with 20 sample rows
3. Created a publication (`products_pub`) on the publisher
4. Promoted the standby to an independent server
5. Created the same table structure on the subscriber
6. Created a subscription (`products_sub`) that connects to the publisher
7. Verified initial data sync (20 rows copied automatically)
8. Tested live replication (5 new rows appeared on subscriber)
9. Monitored replication using pg_stat_subscription and pg_stat_replication

**Key takeaway**: Unlike physical replication where the standby is a read-only clone of everything, logical replication lets you pick specific tables and the subscriber remains a fully independent, read-write server.

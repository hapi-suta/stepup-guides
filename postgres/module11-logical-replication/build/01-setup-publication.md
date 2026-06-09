# Build: Set Up Logical Replication (40 min)

In this lab you will set up logical replication between two PostgreSQL servers. The publisher (source) will send changes from a single table to the subscriber (target) over a logical replication connection.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

**Important**: Before starting, confirm which node is the actual primary. If roles were flipped in a previous lab, adjust accordingly.

---

## Step 1: Identify the Current Primary

On **pg-suta-labs-1**, as **ec2-user**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@pg-suta-labs-1
```

Switch to the postgres user.

```bash
sudo su - postgres
```

Check if this node is the primary (not in recovery).

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

The result should be `f` (false), meaning this is the primary. If it returns `t`, then pg-suta-labs-2 is your actual primary - swap the node names in all steps below.

Exit back to ec2-user.

```bash
exit
```

---

## Step 2: Check the Current wal_level on the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Query the current wal_level setting.

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

Expected output (yours will differ):
```
 wal_level
-----------
 replica
(1 row)
```

The value is `replica`. Logical replication requires `logical`. We need to change this and restart PostgreSQL.

Exit back to ec2-user.

```bash
exit
```

---

## Step 3: Change wal_level to logical on the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to root. We need root to edit the PostgreSQL configuration file.

```bash
sudo su -
```

Open postgresql.conf in vi.

```bash
vi /var/lib/pgsql/16/data/postgresql.conf
```

Find the wal_level line. In vi, type `/wal_level` and press Enter to search for it.

Change the line to:

```
wal_level = logical
```

If the line is commented out (starts with `#`), remove the `#` and set the value.

Save and exit vi by pressing Esc, then typing `:wq` and pressing Enter.

Exit back to ec2-user.

```bash
exit
```

---

## Step 4: Restart PostgreSQL on the Publisher

On **pg-suta-labs-1**, as **ec2-user**:

Changing wal_level requires a full restart (reload is not enough).

```bash
sudo systemctl restart postgresql-16
```

Verify PostgreSQL is running.

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):
```
   Active: active (running) since Sun 2026-06-01 ...
   ...
```

Confirm the status shows `active (running)`.

---

## Step 5: Verify wal_level Is Now logical

On **pg-suta-labs-1**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Check the wal_level.

```bash
/usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

Expected output (yours will differ):
```
 wal_level
-----------
 logical
(1 row)
```

The value should now be `logical`. If it still shows `replica`, go back to Step 3 and make sure you edited the correct file and saved it.

---

## Step 6: Create a Test Table on the Publisher

Still as **postgres** on **pg-suta-labs-1**:

We will create a `products` table for this logical replication demo. We are not using the existing `employees` table - we want a clean table to work with.

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Create the products table. The SERIAL type auto-creates a sequence for the id column.

```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    created_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

---

## Step 7: Insert Sample Data on the Publisher

Still in the psql session on **pg-suta-labs-1** as **postgres** on labdb:

Insert 20 sample rows. The generate_series function creates 20 numbered rows in one statement.

```sql
INSERT INTO products (name, price)
SELECT
    'Product ' || gs,
    round((random() * 100)::numeric, 2)
FROM generate_series(1, 20) AS gs;
```

Expected output (yours will differ):
```
INSERT 0 20
```

Verify the data.

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

Check a few rows.

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

---

## Step 8: Create a Publication

Still in the psql session on **pg-suta-labs-1** as **postgres** on labdb:

A publication defines which tables the publisher will broadcast. We are creating a publication called `products_pub` that includes only the `products` table.

```sql
CREATE PUBLICATION products_pub FOR TABLE products;
```

Expected output (yours will differ):
```
CREATE PUBLICATION
```

Now grant the replicator user SELECT access on the products table. The subscription will connect as `replicator`, and it needs to read the table data for the initial copy.

```sql
GRANT SELECT ON products TO replicator;
```

Expected output (yours will differ):
```
GRANT
```

---

## Step 9: Verify the Publication

Still in the psql session on **pg-suta-labs-1** as **postgres** on labdb:

Query the pg_publication system catalog to confirm the publication exists.

```sql
SELECT pubname, puballtables, pubinsert, pubupdate, pubdelete, pubtruncate
FROM pg_publication;
```

Expected output (yours will differ):
```
   pubname    | puballtables | pubinsert | pubupdate | pubdelete | pubtruncate
--------------+--------------+-----------+-----------+-----------+-------------
 products_pub | f            | t         | t         | t         | t
(1 row)
```

- `puballtables = f` means we are NOT publishing all tables (just the ones we specified).
- `pubinsert, pubupdate, pubdelete, pubtruncate` are all `t` - all operation types will be replicated.

Check which tables are in the publication.

```sql
SELECT * FROM pg_publication_tables;
```

Expected output (yours will differ):
```
   pubname    | schemaname | tablename | attnames | rowfilter
--------------+------------+-----------+----------+-----------
 products_pub | public     | products  |          |
(1 row)
```

The `attnames` and `rowfilter` columns are empty because we are publishing all columns with no row filter.

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

---

## Step 10: Prepare the Subscriber Node

Now we switch to pg-suta-labs-2 (the subscriber). Open a new terminal or SSH into pg-suta-labs-2.

On **pg-suta-labs-2**, as **ec2-user**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@pg-suta-labs-2
```

**Important**: Before we can set up logical replication, the subscriber must be an independent, standalone PostgreSQL server - NOT a physical streaming replica. If pg-suta-labs-2 is currently a streaming replica of pg-suta-labs-1, you need to promote it first.

Switch to the postgres user.

```bash
sudo su - postgres
```

Check if this node is a standby (in recovery).

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

If the result is `t` (true), this is a streaming replica. You must promote it to make it standalone.

```bash
/usr/pgsql-16/bin/pg_ctl promote -D /var/lib/pgsql/16/data
```

Expected output (yours will differ):
```
waiting for server to promote.... done
server promoted
```

Verify it is now standalone.

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

Exit back to ec2-user.

```bash
exit
```

---

## Step 11: Change wal_level to logical on the Subscriber

On **pg-suta-labs-2**, as **ec2-user**:

This is best practice - it allows the subscriber to act as a publisher later if needed.

Switch to root.

```bash
sudo su -
```

Open postgresql.conf.

```bash
vi /var/lib/pgsql/16/data/postgresql.conf
```

Find the wal_level line (type `/wal_level` in vi) and change it to:

```
wal_level = logical
```

Save and exit vi (Esc, then `:wq`).

Exit back to ec2-user.

```bash
exit
```

Restart PostgreSQL.

```bash
sudo systemctl restart postgresql-16
```

Verify it is running.

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):
```
   Active: active (running) since Sun 2026-06-01 ...
   ...
```

---

## Step 12: Create the Table Structure on the Subscriber

On **pg-suta-labs-2**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Logical replication does NOT replicate DDL (schema changes). The table must already exist on the subscriber with the same column structure.

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

**If the table already exists** (because pg-suta-labs-2 was a physical replica and had a copy of everything), drop it first so we start clean.

```sql
DROP TABLE IF EXISTS products;
```

Create the products table with the exact same structure as the publisher.

```sql
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    created_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

Verify it is empty.

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):
```
 count
-------
     0
(1 row)
```

The table is empty. The subscription will copy the initial data automatically.

---

## Step 13: Create a Subscription

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

This is where the magic happens. The subscription tells the subscriber to connect to the publisher, pull the initial data, and then keep listening for new changes.

First, clean up any stale subscription metadata that may have been copied when pg-suta-labs-2 was a physical replica:

```sql
DROP SUBSCRIPTION IF EXISTS products_sub;
```

Now create the subscription:

```sql
CREATE SUBSCRIPTION products_sub
    CONNECTION 'host=pg-suta-labs-1 port=5432 dbname=labdb user=replicator password=StrongPass123'
    PUBLICATION products_pub;
```

- `products_sub` - the name we are giving this subscription.
- `host=pg-suta-labs-1` - the publisher's hostname (from /etc/hosts).
- `user=replicator` - the replication user that already exists on the publisher.
- `PUBLICATION products_pub` - the name of the publication we created on the publisher.

Expected output (yours will differ):
```
NOTICE:  created replication slot "products_sub" on publisher
CREATE SUBSCRIPTION
```

The NOTICE tells you that PostgreSQL automatically created a replication slot on the publisher. This slot ensures the publisher retains WAL until the subscriber has consumed it.

---

## Step 14: Verify the Subscription

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Check the subscription exists.

```sql
SELECT subname, subenabled, subconninfo, subpublications
FROM pg_subscription;
```

Expected output (yours will differ):
```
   subname    | subenabled |                              subconninfo                               | subpublications
--------------+------------+------------------------------------------------------------------------+-----------------
 products_sub | t          | host=pg-suta-labs-1 port=5432 dbname=labdb user=replicator password=... | {products_pub}
(1 row)
```

- `subenabled = t` means the subscription is active.

---

## Step 15: Verify the Initial Data Sync

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

## Step 16: Test Live Replication

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

## Step 17: Monitor Replication

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

## Step 18: Exit Both Terminals

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

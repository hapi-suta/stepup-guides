# Survive: Sequences Not Synced After Logical Replication (7 min)

## The Scenario

You have been using logical replication to migrate data from an old server to a new server. The data looks perfect - all 25 rows are on the subscriber. You cut over to the subscriber as the new primary. A user tries to insert a new row and gets:

```
ERROR:  duplicate key value violates unique constraint "products_pkey"
DETAIL:  Key (id)=(1) already exists.
```

The sequence on the subscriber is at 1, not at 26 where it should be.

---

## Step 1: See the Problem

On **pg-suta-labs-2**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Check the current sequence value. The products table uses a SERIAL column, which creates a sequence called `products_id_seq`.

```sql
SELECT last_value FROM products_id_seq;
```

Expected output (yours will differ):
```
 last_value
------------
          1
(1 row)
```

The sequence is at 1. But the table has 25 rows with IDs up to 25.

Check the highest ID in the table.

```sql
SELECT max(id) FROM products;
```

Expected output (yours will differ):
```
 max
-----
  25
(1 row)
```

The data was replicated, but the sequence was not. This is because **logical replication does not sync sequences** - it only replicates row data (INSERT, UPDATE, DELETE).

Try inserting a row to see the error.

```sql
INSERT INTO products (name, price) VALUES ('Test Sequence', 5.00);
```

Expected output (yours will differ):
```
ERROR:  duplicate key value violates unique constraint "products_pkey"
DETAIL:  Key (id)=(1) already exists.
```

The sequence generated id=1, which already exists. The INSERT fails.

---

## Step 2: Fix the Sequence

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Use the `setval` function to set the sequence to the current maximum ID value. The second argument is the value that was last used, so the next call to `nextval` will return max(id) + 1.

```sql
SELECT setval('products_id_seq', (SELECT max(id) FROM products));
```

Expected output (yours will differ):
```
 setval
--------
     25
(1 row)
```

The sequence is now set to 25. The next auto-generated ID will be 26.

Verify the fix.

```sql
SELECT last_value FROM products_id_seq;
```

Expected output (yours will differ):
```
 last_value
------------
         25
(1 row)
```

---

## Step 3: Test the Fix

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

Insert a new row. It should get id=26 automatically.

```sql
INSERT INTO products (name, price) VALUES ('Test Sequence', 5.00);
```

Expected output (yours will differ):
```
INSERT 0 1
```

Verify.

```sql
SELECT * FROM products ORDER BY id DESC LIMIT 3;
```

Expected output (yours will differ):
```
 id |      name       | price |         created_at
----+-----------------+-------+----------------------------
 26 | Test Sequence   |  5.00 | 2026-06-01 15:20:00.123456
 25 | Cable Organizer | 12.99 | 2026-06-01 14:45:00.123456
 24 | Desk Lamp       | 22.75 | 2026-06-01 14:45:00.123456
...
```

The new row got id=26. The sequence is working correctly.

---

## Step 4: Fix ALL Sequences at Once (Production Method)

Still as **postgres** on **pg-suta-labs-2** in the psql session on labdb:

In a real migration, you might have dozens of tables with sequences. Here is a query that generates the `setval` command for every sequence in the database.

```sql
SELECT 'SELECT setval(''' || sequencename || ''', COALESCE((SELECT max(id) FROM ' ||
       replace(sequencename, '_id_seq', '') || '), 1));' AS fix_command
FROM pg_sequences
WHERE schemaname = 'public';
```

This generates a setval command for each sequence by deriving the table name from the sequence name (strips `_id_seq`). Copy and run each line it outputs.

Expected output (yours will differ):
```
                                   fix_command
----------------------------------------------------------------------------------
 SELECT setval('products_id_seq', COALESCE((SELECT max(id) FROM products), 1));
 SELECT setval('orders_id_seq', COALESCE((SELECT max(id) FROM orders), 1));
(2 rows)
```

A simpler approach is to just list all sequences and fix them one by one. The `pg_sequences` view lists all sequences.

```sql
SELECT sequencename, last_value FROM pg_sequences WHERE schemaname = 'public';
```

Expected output (yours will differ):
```
   sequencename   | last_value
------------------+------------
 products_id_seq  |         26
 orders_id_seq    |
(2 rows)
```

A NULL `last_value` means the sequence was never called on this server - the data was replicated but the sequence was not. For each sequence with NULL or a value lower than the table's max ID, run the setval command.

Fix the orders sequence.

```sql
SELECT setval('orders_id_seq', (SELECT max(id) FROM orders));
```

Expected output (yours will differ):
```
 setval
--------
     11
(1 row)
```

---

## Step 5: Understand the Prevention Strategy

Before cutting over from a publisher to a subscriber, ALWAYS run this checklist:

1. **Stop writes on the publisher** - Make sure no new data is coming in.
2. **Wait for replication to catch up** - Check `pg_stat_subscription` until `received_lsn` matches the publisher's `pg_current_wal_lsn()`.
3. **Sync all sequences** - Run setval for every sequence.
4. **Drop the subscription** - So the subscriber no longer tries to connect back.
5. **Redirect applications** - Point your app to the new server.

The sequence sync step is easy to forget and causes immediate failures after cutover. Make it part of your migration runbook.

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

---

## Quick Reference

| Command | What It Does |
|---------|-------------|
| `SELECT last_value FROM products_id_seq;` | Check current sequence value |
| `SELECT max(id) FROM products;` | Check highest ID in the table |
| `SELECT setval('products_id_seq', (SELECT max(id) FROM products));` | Fix the sequence |
| `SELECT sequencename, last_value FROM pg_sequences;` | List all sequences and their values |

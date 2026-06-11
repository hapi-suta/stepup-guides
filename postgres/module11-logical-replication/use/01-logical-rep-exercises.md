# Use: Logical Replication Exercises (20 min)

These exercises build on the logical replication setup from the BUILD lab. You should have:
- A `products_pub` publication on the publisher (pg-suta-labs-1)
- A `products_sub` subscription on the subscriber (pg-suta-labs-2)
- The `products` table replicating between both nodes

---

## Exercise 1: Add and Remove Tables from a Publication (8 min)

**Goal**: Create a second table, add it to the existing publication, verify it replicates, then remove the original table from the publication.

### Part A: Create the orders table on the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Create an orders table.

```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    total NUMERIC(10,2),
    ordered_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

Insert some sample data. This inserts 10 orders referencing random product IDs.

```sql
INSERT INTO orders (product_id, quantity, total)
SELECT
    (random() * 19 + 1)::int,
    (random() * 5 + 1)::int,
    round((random() * 200)::numeric, 2)
FROM generate_series(1, 10);
```

Expected output (yours will differ):
```
INSERT 0 10
```

Grant SELECT on orders to the replicator user. The subscription connects as replicator and needs to read the table.

```sql
GRANT SELECT ON orders TO replicator;
```

### Part B: Add orders to the publication

Still as **postgres** on **pg-suta-labs-1** in the psql session on labdb:

Add the orders table to the existing publication. The ALTER PUBLICATION command modifies which tables are included.

```sql
ALTER PUBLICATION products_pub ADD TABLE orders;
```

Expected output (yours will differ):
```
ALTER PUBLICATION
```

Verify both tables are in the publication.

```sql
SELECT * FROM pg_publication_tables WHERE pubname = 'products_pub';
```

Expected output (yours will differ):
```
   pubname    | schemaname | tablename
--------------+------------+-----------
 products_pub | public     | products
 products_pub | public     | orders
(2 rows)
```

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

### Part C: Create orders table on the Subscriber and refresh

On **pg-suta-labs-2**, as **ec2-user**, switch to the postgres user.

```bash
sudo su - postgres
```

Connect to labdb.

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Create the same orders table on the subscriber. Remember - logical replication does NOT replicate DDL, so you must create the table manually.

```sql
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    total NUMERIC(10,2),
    ordered_at TIMESTAMP DEFAULT now()
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

Now tell the subscription to refresh. This picks up the new table that was added to the publication. The `copy_data` option tells it to copy existing rows from the new table.

```sql
ALTER SUBSCRIPTION products_sub REFRESH PUBLICATION;
```

Expected output (yours will differ):
```
ALTER SUBSCRIPTION
```

Wait a few seconds, then check if the orders data arrived.

```sql
SELECT count(*) FROM orders;
```

Expected output (yours will differ):
```
 count
-------
    10
(1 row)
```

The 10 orders were copied from the publisher.

### Part D: Remove products from the publication

**Note**: For this section, keep two terminal windows open - one connected to the publisher (pg-suta-labs-1) and one to the subscriber (pg-suta-labs-2). We will switch between them frequently.

Switch to your **publisher terminal** (pg-suta-labs-1). As **ec2-user**, switch to the postgres user and connect to labdb:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Remove the products table from the publication. This stops replicating products but keeps replicating orders.

```sql
ALTER PUBLICATION products_pub DROP TABLE products;
```

Expected output (yours will differ):
```
ALTER PUBLICATION
```

Verify only orders remains.

```sql
SELECT * FROM pg_publication_tables WHERE pubname = 'products_pub';
```

Expected output (yours will differ):
```
   pubname    | schemaname | tablename
--------------+------------+-----------
 products_pub | public     | orders
(1 row)
```

Switch to your **subscriber terminal** (pg-suta-labs-2). As **postgres** on labdb:

Tell the subscription to refresh so it picks up the change.

```sql
ALTER SUBSCRIPTION products_sub REFRESH PUBLICATION;
```

Expected output (yours will differ):
```
ALTER SUBSCRIPTION
```

Switch to your **publisher terminal** (pg-suta-labs-1). Still as **postgres** on labdb. Insert a row into products.

```sql
INSERT INTO products (name, price) VALUES ('Test Removal', 1.00);
```

Switch to your **subscriber terminal** (pg-suta-labs-2). Still as **postgres** on labdb. Check if the new products row appeared (it should NOT, because products was removed from the publication).

```sql
SELECT count(*) FROM products;
```

The count should not have increased. Products is no longer being replicated.

Switch to your **publisher terminal** (pg-suta-labs-1). Insert an order.

```sql
INSERT INTO orders (product_id, quantity, total) VALUES (1, 3, 29.97);
```

Switch to your **subscriber terminal** (pg-suta-labs-2). Check if the order was replicated.

```sql
SELECT count(*) FROM orders;
```

Expected output (yours will differ):
```
 count
-------
    11
(1 row)
```

The order was replicated. Products was not. You have selective control over what replicates.

Exit psql and the postgres user on **both** terminals.

On the subscriber terminal:

```sql
\q
```

```bash
exit
```

On the publisher terminal:

```sql
\q
```

```bash
exit
```

---

## Exercise 2: Row Filtering (6 min)

**Goal**: Create a publication that only replicates rows matching a WHERE condition. This is a PostgreSQL 15+ feature.

### On the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to postgres and connect to labdb.

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

First, add products back to the existing publication (we removed it in Exercise 1).

```sql
ALTER PUBLICATION products_pub ADD TABLE products;
```

Now create a separate publication with a row filter. This publication only sends products where the price is greater than 50.00.

```sql
CREATE PUBLICATION filtered_pub FOR TABLE products WHERE (price > 50.00);
```

Expected output (yours will differ):
```
CREATE PUBLICATION
```

Verify the publication and its filter.

```sql
SELECT pubname, rowfilter
FROM pg_publication_tables
WHERE pubname = 'filtered_pub';
```

Expected output (yours will differ):
```
   pubname    |    rowfilter
--------------+-----------------
 filtered_pub | (price > 50.00)
(1 row)
```

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

### On the Subscriber

On **pg-suta-labs-2**, as **ec2-user**, switch to postgres and connect to labdb.

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Create a new table to receive only filtered rows. We use a separate table so we can clearly see the difference.

```sql
CREATE TABLE products_expensive (
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

Create a subscription for the filtered publication. We need to map the subscriber's `products_expensive` table to the publisher's `products` table. Unfortunately, logical replication requires matching table names. So instead, let's subscribe directly using the products table.

We will create a second subscription pointing at the filtered publication. But since our `products` table is already subscribed via `products_sub`, we will use a workaround - create the subscription on a separate database or drop the existing one for this exercise.

For simplicity, let's observe the feature by checking what the publisher would send. Exit psql.

```sql
\q
```

A simpler demonstration: count how many existing rows match the filter.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM products WHERE price > 50.00;"
```

Expected output (yours will differ):
```
 count
-------
     8
(1 row)
```

When a subscriber connects to `filtered_pub`, it would only receive those 8 rows in the initial sync, and only future INSERTs/UPDATEs where `price > 50.00`.

**Key takeaway**: Row filtering lets you publish a subset of rows. This is useful when you only want a remote office to see local data, or a reporting server to get high-value transactions.

Exit back to ec2-user.

```bash
exit
```

---

## Exercise 3: Column Lists (6 min)

**Goal**: Create a publication that only replicates selected columns from a table. This is a PostgreSQL 15+ feature.

### On the Publisher

On **pg-suta-labs-1**, as **ec2-user**, switch to postgres and connect to labdb.

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Create a publication that only includes the `id` and `name` columns from the products table. The `price` and `created_at` columns will NOT be replicated.

```sql
CREATE PUBLICATION partial_pub FOR TABLE products (id, name);
```

Expected output (yours will differ):
```
CREATE PUBLICATION
```

Verify the column list.

```sql
SELECT pubname, schemaname, tablename, attnames
FROM pg_publication_tables
WHERE pubname = 'partial_pub';
```

Expected output (yours will differ):
```
   pubname   | schemaname | tablename | attnames
-------------+------------+-----------+-----------
 partial_pub | public     | products  | {id,name}
(1 row)
```

Only `id` and `name` are in the `attnames` list. The `price` and `created_at` columns are excluded.

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

### On the Subscriber

On **pg-suta-labs-2**, as **ec2-user**, switch to postgres and connect to labdb.

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

To subscribe to `partial_pub`, the subscriber's table must have at least the columns being published (`id` and `name`). The table CAN have extra columns - they will just be NULL or get their default values.

Create a table with only the published columns.

```sql
CREATE TABLE products_partial (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL
);
```

Expected output (yours will differ):
```
CREATE TABLE
```

**Note**: To actually subscribe, the table name must match (`products`), not `products_partial`. Since `products` is already subscribed via another subscription, we are demonstrating the concept here.

If you wanted to test this end-to-end, you would:
1. Drop the existing `products_sub` subscription
2. Drop and recreate the `products` table with only `id` and `name` columns
3. Create a new subscription pointing at `partial_pub`

**Key takeaway**: Column lists let you replicate only the columns a subscriber needs. This is useful for:
- Excluding sensitive columns (like `ssn` or `salary`) from a reporting replica
- Reducing network bandwidth by skipping large TEXT or BYTEA columns
- Sending only relevant columns to downstream systems

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

---

## Cleanup (Optional)

If you want to clean up the extra publications created in these exercises:

On the **publisher** (pg-suta-labs-1), as **ec2-user**, switch to the postgres user and connect to labdb:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Drop the extra publications:

```sql
DROP PUBLICATION IF EXISTS filtered_pub;
DROP PUBLICATION IF EXISTS partial_pub;
```

Exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

On the **subscriber** (pg-suta-labs-2), as **ec2-user**, switch to the postgres user and connect to labdb:

```bash
sudo su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb
```

Drop the extra tables:

```sql
DROP TABLE IF EXISTS products_expensive;
DROP TABLE IF EXISTS products_partial;
```

Exit psql and the postgres user:

```sql
\q
```

```bash
exit
```

---

## Summary

| Exercise | Feature | PostgreSQL Version | Use Case |
|----------|---------|-------------------|----------|
| 1 | Add/Remove tables | 10+ | Control which tables replicate at any time |
| 2 | Row filtering (WHERE) | 15+ | Replicate only rows matching a condition |
| 3 | Column lists | 15+ | Replicate only selected columns |

These features make logical replication very flexible compared to physical replication, where you get everything or nothing.

# Build 02 - Create the Publication

Now create a table with sample data on the publisher and publish it so a subscriber can receive its changes.

**Nodes:**
- **pg-suta-labs-1** - the publisher (source of changes)
- **pg-suta-labs-2** - the subscriber (receives changes)

---

## Create a Test Table on the Publisher

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

## Insert Sample Data on the Publisher

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

## Create a Publication

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

## Verify the Publication

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

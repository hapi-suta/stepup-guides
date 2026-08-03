# BUILD 06 - Foreign Data Wrappers

**Time:** 30 minutes
**Goal:** Install postgres_fdw, connect to a second RDS instance, and query remote data as if it were local.

---

## Prerequisites

- Two RDS PostgreSQL instances running (or one instance you will self-connect to simulate the setup)
- Both instances accessible from the same VPC (or with appropriate security group rules)
- psql access to both instances
- AWS CLI configured

---

## Setup: Two-Instance Architecture

This lab requires a "local" and a "remote" instance.

```
Your Application / psql
         |
         v
+-------------------+        postgres_fdw        +-------------------+
|   LOCAL RDS       | --------------------------> |   REMOTE RDS      |
|   (your primary)  |       TCP port 5432         |   (data source)   |
|                   |                             |                   |
| Foreign Table     |                             | Real Table        |
| (local proxy)     |                             | (actual data)     |
+-------------------+                             +-------------------+
```

If you only have one instance, you can still do this lab by connecting the FDW back to the same instance (different database). This is shown where relevant.

---

## Part 1 - Set Up the Remote Instance

First, prepare the remote instance with some data to query.

**Connect to the REMOTE instance:**

```bash
psql -h [REMOTE-ENDPOINT] -U [REMOTE-USERNAME] -d postgres
```

**Create a database on the remote instance:**

```sql
CREATE DATABASE inventory_db;
```

**Connect to that database:**

```sql
\c inventory_db
```

**Create a table with sample data:**

```sql
CREATE TABLE products (
  id          serial PRIMARY KEY,
  sku         text UNIQUE NOT NULL,
  name        text NOT NULL,
  quantity    integer NOT NULL DEFAULT 0,
  unit_price  numeric(10,2) NOT NULL,
  updated_at  timestamptz DEFAULT now()
);

INSERT INTO products (sku, name, quantity, unit_price) VALUES
  ('SKU-001', 'Widget A',      150, 9.99),
  ('SKU-002', 'Widget B',       75, 14.99),
  ('SKU-003', 'Gadget Pro',     30, 49.99),
  ('SKU-004', 'Gadget Mini',   200, 24.99),
  ('SKU-005', 'Super Tool',     12, 99.99);
```

**Create a read-only user for the FDW connection:**

```sql
CREATE USER fdw_reader WITH PASSWORD '[STRONG-PASSWORD]';
GRANT CONNECT ON DATABASE inventory_db TO fdw_reader;
GRANT USAGE ON SCHEMA public TO fdw_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO fdw_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO fdw_reader;
```

Replace `[STRONG-PASSWORD]` with a strong password. You will use this in the user mapping later.

> **Concept:** Always create a dedicated, least-privilege user for FDW connections. Never use your admin user. If the FDW connection is compromised, the attacker only gets read access.

---

## Part 2 - Install postgres_fdw on the Local Instance

**Connect to the LOCAL instance:**

```bash
psql -h [LOCAL-ENDPOINT] -U [LOCAL-USERNAME] -d postgres
```

**Install the extension:**

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
```

postgres_fdw does not require preloading. It activates immediately.

**Verify:**

```sql
SELECT name, installed_version
FROM pg_available_extensions
WHERE name = 'postgres_fdw';
```

Expected output (yours will differ):
```
     name     | installed_version
--------------+-------------------
 postgres_fdw | 1.1
(1 row)
```

---

## Part 3 - Create the Foreign Server

The foreign server object defines the connection details for the remote database.

```sql
CREATE SERVER inventory_remote
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (
    host '[REMOTE-ENDPOINT]',
    port '5432',
    dbname 'inventory_db'
  );
```

Replace `[REMOTE-ENDPOINT]` with the actual RDS endpoint of your remote instance.

**Verify the server was created:**

```sql
SELECT srvname, srvowner::regrole, srvoptions
FROM pg_foreign_server;
```

Expected output (yours will differ):
```
      srvname      | srvowner |                     srvoptions
-------------------+----------+----------------------------------------------------
 inventory_remote  | postgres | {host=my-remote.abc123.us-east-1.rds.amazonaws.com,
                   |          |  port=5432,dbname=inventory_db}
(1 row)
```

---

## Part 4 - Create a User Mapping

The user mapping tells PostgreSQL which credentials to use when connecting to the remote server. It maps your local user to the remote `fdw_reader` user.

```sql
CREATE USER MAPPING FOR [LOCAL-USERNAME]
  SERVER inventory_remote
  OPTIONS (
    user 'fdw_reader',
    password '[STRONG-PASSWORD]'
  );
```

Replace `[LOCAL-USERNAME]` with your local PostgreSQL username (the one you connected as), and `[STRONG-PASSWORD]` with the password you set for `fdw_reader` on the remote instance.

> **Important:** The password is stored in plain text in the PostgreSQL catalog. Restrict access to `pg_user_mappings` view to protect it.

**Verify the user mapping:**

```sql
SELECT *
FROM pg_user_mappings;
```

Expected output (yours will differ):
```
 umid | srvid |      srvname      | umuser |        umoptions
------+-------+-------------------+--------+---------------------------
  123 |   456 | inventory_remote  |     10 | {user=fdw_reader,password=...}
(1 row)
```

---

## Part 5 - Create a Foreign Table

A foreign table is a local object that acts as a proxy for the remote table.

### Option A - Create Foreign Table Manually

```sql
CREATE FOREIGN TABLE remote_products (
  id          integer,
  sku         text,
  name        text,
  quantity    integer,
  unit_price  numeric(10,2),
  updated_at  timestamptz
)
SERVER inventory_remote
OPTIONS (
  schema_name 'public',
  table_name 'products'
);
```

The `OPTIONS (schema_name, table_name)` clause points this local proxy to the actual table on the remote server.

### Option B - Import Foreign Schema (Easier for Many Tables)

Instead of defining each foreign table by hand, import all tables from a remote schema at once:

```sql
CREATE SCHEMA IF NOT EXISTS remote_inventory;

IMPORT FOREIGN SCHEMA public
FROM SERVER inventory_remote
INTO remote_inventory;
```

This creates foreign tables for every table in the remote `public` schema, placing them in your local `remote_inventory` schema.

**List the imported foreign tables:**

```sql
SELECT foreign_table_schema, foreign_table_name, foreign_server_name
FROM information_schema.foreign_tables;
```

Expected output (yours will differ):
```
 foreign_table_schema | foreign_table_name | foreign_server_name
----------------------+--------------------+---------------------
 remote_inventory     | products           | inventory_remote
(1 row)
```

---

## Part 6 - Query Remote Data

**Simple select from the foreign table:**

```sql
SELECT *
FROM remote_products
ORDER BY id;
```

Expected output (yours will differ):
```
 id |   sku   |    name    | quantity | unit_price |         updated_at
----+---------+------------+----------+------------+----------------------------
  1 | SKU-001 | Widget A   |      150 |       9.99 | 2024-01-15 10:30:00+00
  2 | SKU-002 | Widget B   |       75 |      14.99 | 2024-01-15 10:30:00+00
  3 | SKU-003 | Gadget Pro |       30 |      49.99 | 2024-01-15 10:30:00+00
  4 | SKU-004 | Gadget Mini|      200 |      24.99 | 2024-01-15 10:30:00+00
  5 | SKU-005 | Super Tool |       12 |      99.99 | 2024-01-15 10:30:00+00
(5 rows)
```

PostgreSQL connected to the remote server, ran the query there, and returned the results.

**Filter on a remote column:**

```sql
SELECT sku, name, quantity
FROM remote_products
WHERE quantity < 50;
```

Expected output (yours will differ):
```
   sku   |    name    | quantity
---------+------------+----------
 SKU-003 | Gadget Pro |       30
 SKU-005 | Super Tool |       12
(2 rows)
```

This filter is pushed down to the remote server - only matching rows come back over the network.

**Aggregate across remote data:**

```sql
SELECT
  count(*) AS total_skus,
  sum(quantity) AS total_inventory,
  round(avg(unit_price), 2) AS avg_price
FROM remote_products;
```

Expected output (yours will differ):
```
 total_skus | total_inventory | avg_price
------------+-----------------+-----------
          5 |             467 |     39.99
(1 row)
```

---

## Part 7 - Join Local and Remote Data

Create a local table to join with remote data:

```sql
CREATE TABLE local_orders (
  id         serial PRIMARY KEY,
  sku        text NOT NULL,
  quantity   integer NOT NULL,
  order_date date DEFAULT current_date
);

INSERT INTO local_orders (sku, quantity) VALUES
  ('SKU-001', 10),
  ('SKU-003', 5),
  ('SKU-005', 2);
```

**Join local orders with remote product data:**

```sql
SELECT
  lo.id AS order_id,
  lo.sku,
  rp.name AS product_name,
  lo.quantity AS ordered,
  rp.quantity AS in_stock,
  rp.unit_price,
  lo.quantity * rp.unit_price AS order_total
FROM local_orders lo
JOIN remote_products rp ON lo.sku = rp.sku
ORDER BY lo.id;
```

Expected output (yours will differ):
```
 order_id |   sku   | product_name | ordered | in_stock | unit_price | order_total
----------+---------+--------------+---------+----------+------------+-------------
        1 | SKU-001 | Widget A     |      10 |      150 |       9.99 |       99.90
        2 | SKU-003 | Gadget Pro   |       5 |       30 |      49.99 |      249.95
        3 | SKU-005 | Super Tool   |       2 |       12 |      99.99 |      199.98
(3 rows)
```

---

## Part 8 - Performance Considerations

### Use EXPLAIN to See What Gets Pushed Down

```sql
EXPLAIN (VERBOSE, ANALYZE)
SELECT sku, name, quantity
FROM remote_products
WHERE quantity < 50;
```

Look for `Remote SQL:` in the output - this shows what query runs on the remote server.

Expected output (yours will differ):
```
                     QUERY PLAN
-------------------------------------------------------------------
 Foreign Scan on public.remote_products  (cost=100.00..150.00 ...)
   Output: sku, name, quantity
   Remote SQL: SELECT sku, name, quantity FROM public.products
               WHERE (quantity < 50)
```

The `WHERE` clause was pushed to the remote server. Only 2 rows came over the network.

### What Does NOT Push Down

- Complex expressions or functions not available on the remote
- Joins where one side is local and the other is remote (the local side fetches all remote rows first)
- Aggregations in some cases

**Example of a join that does NOT push down efficiently:**

```sql
EXPLAIN (VERBOSE)
SELECT lo.sku, rp.name
FROM local_orders lo
JOIN remote_products rp ON lo.sku = rp.sku;
```

Look at the plan - PostgreSQL will fetch all rows from `remote_products` and then join locally. For large tables, this is expensive.

### FDW Performance Guidelines

| Situation | Recommendation |
|---|---|
| Filter on remote indexed column | Good - pushes down |
| Aggregate remote data | Good - pushes down in simple cases |
| Join large local + large remote | Risky - may fetch all remote rows |
| Many parallel queries using FDW | Each uses a connection - pool carefully |
| Large result sets | Watch network bandwidth |

---

## Cleanup

```sql
-- On local instance
DROP FOREIGN TABLE IF EXISTS remote_products;
DROP SCHEMA IF EXISTS remote_inventory CASCADE;
DROP USER MAPPING IF EXISTS FOR [LOCAL-USERNAME] SERVER inventory_remote;
DROP SERVER IF EXISTS inventory_remote;
DROP EXTENSION IF EXISTS postgres_fdw;
DROP TABLE IF EXISTS local_orders;
```

```sql
-- On remote instance, in inventory_db
DROP TABLE IF EXISTS products;
DROP USER IF EXISTS fdw_reader;
```

---

## Summary

| Object | Purpose | Command |
|---|---|---|
| Extension | Enable FDW capability | `CREATE EXTENSION postgres_fdw` |
| Foreign Server | Define remote connection | `CREATE SERVER` |
| User Mapping | Map local user to remote credentials | `CREATE USER MAPPING` |
| Foreign Table | Local proxy for remote table | `CREATE FOREIGN TABLE` or `IMPORT FOREIGN SCHEMA` |

---

## Next Steps

- [BUILD 07 - Engine Versions](07-engine-versions.md)
- [USE 04 - Cross-Database Queries](../use/04-cross-database-queries.md)

# USE 04 - Cross-Database Queries with postgres_fdw

**Time:** 25 minutes
**Level:** Intermediate
**Prerequisite:** BUILD 06 completed

---

## Scenario

[COMPANY] has two separate RDS instances:
- **Orders DB** - tracks customer orders (your "local" instance)
- **Inventory DB** - tracks product stock levels (your "remote" instance)

The finance team needs a combined report that joins order data with current inventory. They cannot migrate the data to a single database right now (different teams own each system). Your job is to set up postgres_fdw so the Orders DB can query the Inventory DB in real time.

---

## Architecture

```
Finance Team's Report Query
           |
           v
+---------------------+        FDW         +----------------------+
|   ORDERS DB (local) | -----------------> |  INVENTORY DB (remote)|
|---------------------|   TCP 5432         |----------------------|
| orders              |                    | products             |
| customers           |                    | stock_levels         |
| [remote_inventory]  |<-- foreign tables  | warehouses           |
+---------------------+                    +----------------------+
```

---

## Part 1 - Set Up the Inventory DB (Remote)

Connect to your **remote** RDS instance.

```bash
psql -h [REMOTE-ENDPOINT] -U [REMOTE-USERNAME] -d postgres
```

**Create the inventory database:**

```sql
CREATE DATABASE inventory_db;
\c inventory_db
```

**Create the schema and tables:**

```sql
CREATE TABLE products (
  product_id    text PRIMARY KEY,
  product_name  text NOT NULL,
  unit_cost     numeric(10,2) NOT NULL,
  category      text
);

CREATE TABLE warehouses (
  warehouse_id   text PRIMARY KEY,
  warehouse_name text NOT NULL,
  location       text
);

CREATE TABLE stock_levels (
  id           serial PRIMARY KEY,
  product_id   text REFERENCES products(product_id),
  warehouse_id text REFERENCES warehouses(warehouse_id),
  quantity     integer NOT NULL DEFAULT 0,
  last_updated timestamptz DEFAULT now()
);
```

**Load sample data:**

```sql
INSERT INTO products VALUES
  ('PROD-001', 'Wireless Keyboard', 29.50, 'electronics'),
  ('PROD-002', 'USB-C Hub',         18.75, 'electronics'),
  ('PROD-003', 'Desk Lamp',         12.00, 'office'),
  ('PROD-004', 'Ergonomic Chair',   185.00, 'furniture'),
  ('PROD-005', 'Notebook Set',       8.50, 'office');

INSERT INTO warehouses VALUES
  ('WH-EAST', 'East Coast Warehouse', 'Newark, NJ'),
  ('WH-WEST', 'West Coast Warehouse', 'Reno, NV');

INSERT INTO stock_levels (product_id, warehouse_id, quantity) VALUES
  ('PROD-001', 'WH-EAST', 450),
  ('PROD-001', 'WH-WEST', 320),
  ('PROD-002', 'WH-EAST', 180),
  ('PROD-002', 'WH-WEST',  95),
  ('PROD-003', 'WH-EAST', 600),
  ('PROD-003', 'WH-WEST', 410),
  ('PROD-004', 'WH-EAST',  12),
  ('PROD-004', 'WH-WEST',   8),
  ('PROD-005', 'WH-EAST', 900),
  ('PROD-005', 'WH-WEST', 750);
```

**Create the FDW read-only user:**

```sql
CREATE USER fdw_report_user WITH PASSWORD '[STRONG-PASSWORD]';
GRANT CONNECT ON DATABASE inventory_db TO fdw_report_user;
GRANT USAGE ON SCHEMA public TO fdw_report_user;
GRANT SELECT ON products, warehouses, stock_levels TO fdw_report_user;
```

---

## Part 2 - Set Up the Orders DB (Local)

Connect to your **local** RDS instance.

```bash
psql -h [LOCAL-ENDPOINT] -U [LOCAL-USERNAME] -d postgres
```

**Create the orders database:**

```sql
CREATE DATABASE orders_db;
\c orders_db
```

**Create local tables:**

```sql
CREATE TABLE customers (
  customer_id  serial PRIMARY KEY,
  name         text NOT NULL,
  email        text UNIQUE NOT NULL,
  region       text
);

CREATE TABLE orders (
  order_id     serial PRIMARY KEY,
  customer_id  integer REFERENCES customers(customer_id),
  product_id   text NOT NULL,
  quantity     integer NOT NULL,
  unit_price   numeric(10,2) NOT NULL,
  order_date   date NOT NULL DEFAULT current_date,
  status       text DEFAULT 'pending'
);
```

**Load sample order data:**

```sql
INSERT INTO customers (name, email, region) VALUES
  ('Alice Johnson', 'alice@example.com', 'EAST'),
  ('Bob Smith',     'bob@example.com',   'WEST'),
  ('Carol Davis',   'carol@example.com', 'EAST'),
  ('Dave Wilson',   'dave@example.com',  'WEST');

INSERT INTO orders (customer_id, product_id, quantity, unit_price, order_date) VALUES
  (1, 'PROD-001', 2, 79.99, '2024-01-10'),
  (1, 'PROD-003', 1, 34.99, '2024-01-10'),
  (2, 'PROD-001', 1, 79.99, '2024-01-11'),
  (2, 'PROD-004', 1, 299.99, '2024-01-11'),
  (3, 'PROD-002', 3, 49.99, '2024-01-12'),
  (4, 'PROD-005', 10, 12.99, '2024-01-12'),
  (1, 'PROD-001', 1, 79.99, '2024-01-14'),
  (3, 'PROD-004', 2, 299.99, '2024-01-14');
```

---

## Part 3 - Set Up the FDW Connection

Still connected to orders_db on the local instance.

**Install postgres_fdw:**

```sql
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
```

**Create the foreign server:**

```sql
CREATE SERVER inventory_server
  FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (
    host '[REMOTE-ENDPOINT]',
    port '5432',
    dbname 'inventory_db',
    fetch_size '1000'
  );
```

The `fetch_size` option controls how many rows are fetched per batch when PostgreSQL reads from the remote server. The default is 100. Increasing it reduces round-trips for large result sets.

**Create the user mapping:**

```sql
CREATE USER MAPPING FOR [LOCAL-USERNAME]
  SERVER inventory_server
  OPTIONS (
    user 'fdw_report_user',
    password '[STRONG-PASSWORD]'
  );
```

**Import all tables from the remote inventory database:**

```sql
CREATE SCHEMA remote_inventory;

IMPORT FOREIGN SCHEMA public
FROM SERVER inventory_server
INTO remote_inventory;
```

**Verify the foreign tables are visible:**

```sql
\d remote_inventory.*
```

Expected output (yours will differ):
```
Foreign table "remote_inventory.products"
   Column    |     Type      | ...
-------------+---------------+
 product_id  | text          |
 product_name| text          |
 unit_cost   | numeric(10,2) |
 category    | text          |
Server: inventory_server
...
```

---

## Part 4 - Run Cross-Database Reports

**Report 1 - Orders with product details:**

```sql
SELECT
  o.order_id,
  c.name AS customer,
  o.product_id,
  p.product_name,
  o.quantity AS ordered,
  o.unit_price AS sale_price,
  p.unit_cost,
  round((o.unit_price - p.unit_cost) * o.quantity, 2) AS gross_profit,
  o.order_date
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN remote_inventory.products p ON o.product_id = p.product_id
ORDER BY o.order_date, o.order_id;
```

**Report 2 - Check if ordered items are in stock:**

```sql
SELECT
  o.order_id,
  c.name AS customer,
  c.region,
  p.product_name,
  o.quantity AS qty_ordered,
  sl.quantity AS current_stock,
  w.warehouse_name,
  CASE
    WHEN sl.quantity >= o.quantity THEN 'FULFILLABLE'
    WHEN sl.quantity > 0 THEN 'PARTIAL'
    ELSE 'OUT OF STOCK'
  END AS fulfillment_status
FROM orders o
JOIN customers c ON o.customer_id = c.customer_id
JOIN remote_inventory.products p ON o.product_id = p.product_id
JOIN remote_inventory.stock_levels sl ON o.product_id = sl.product_id
JOIN remote_inventory.warehouses w ON sl.warehouse_id = w.warehouse_id
WHERE o.status = 'pending'
  AND w.warehouse_id = CASE WHEN c.region = 'EAST' THEN 'WH-EAST' ELSE 'WH-WEST' END
ORDER BY fulfillment_status, o.order_id;
```

**Report 3 - Sales summary with inventory cost:**

```sql
SELECT
  p.category,
  COUNT(DISTINCT o.order_id) AS order_count,
  SUM(o.quantity) AS units_sold,
  round(SUM(o.quantity * o.unit_price), 2) AS total_revenue,
  round(SUM(o.quantity * p.unit_cost), 2) AS total_cost,
  round(SUM(o.quantity * (o.unit_price - p.unit_cost)), 2) AS total_profit
FROM orders o
JOIN remote_inventory.products p ON o.product_id = p.product_id
GROUP BY p.category
ORDER BY total_profit DESC;
```

Expected output (yours will differ):
```
  category   | order_count | units_sold | total_revenue | total_cost | total_profit
-------------+-------------+------------+---------------+------------+--------------
 furniture   |           3 |          4 |       1199.96 |     740.00 |       459.96
 electronics |           5 |          8 |        679.90 |     243.00 |       436.90
 office      |           2 |         11 |        164.89 |      93.50 |        71.39
(3 rows)
```

---

## Part 5 - Performance Analysis

Use EXPLAIN to understand what is happening across the network.

```sql
EXPLAIN (VERBOSE, ANALYZE)
SELECT o.order_id, p.product_name
FROM orders o
JOIN remote_inventory.products p ON o.product_id = p.product_id
WHERE p.category = 'electronics';
```

Look for:
- `Foreign Scan on remote_inventory.products` - confirms FDW is being used
- `Remote SQL:` - shows the query that ran on the remote server
- `Filter:` appearing locally vs remotely (local = more data transferred)

Expected output (yours will differ):
```
Hash Join  (cost=...)
  ->  Seq Scan on orders o  (...)
  ->  Hash  (...)
      ->  Foreign Scan on remote_inventory.products p  (...)
            Remote SQL: SELECT product_id, product_name, unit_cost, category
                        FROM public.products
                        WHERE ((category = 'electronics'))
```

The category filter was pushed to the remote server. Only electronics rows came back over the network.

---

## Part 6 - Materialized View for Repeated Reports

If this report runs frequently and the inventory data doesn't change constantly, a materialized view avoids repeated FDW queries.

```sql
CREATE MATERIALIZED VIEW product_cost_cache AS
SELECT product_id, product_name, unit_cost, category
FROM remote_inventory.products;

CREATE INDEX ON product_cost_cache (product_id);
```

Now queries join against the local materialized view instead of going over the network each time.

**Refresh when inventory data changes:**

```sql
REFRESH MATERIALIZED VIEW product_cost_cache;
```

**Use the cached data in the report:**

```sql
SELECT
  p.category,
  SUM(o.quantity * o.unit_price) AS revenue,
  SUM(o.quantity * p.unit_cost) AS cost
FROM orders o
JOIN product_cost_cache p ON o.product_id = p.product_id
GROUP BY p.category;
```

---

## Discussion Questions

1. The finance team wants live data. Should you use the foreign table directly or a materialized view? What are the trade-offs?

2. The remote Inventory DB team plans to rename the `stock_levels` table to `inventory`. How does this affect your FDW setup?

3. A report joins `orders` (local, 5 million rows) with `remote_inventory.products` (remote, 500 rows). Which direction does data flow? Is this efficient?

4. The `fdw_report_user` password is stored in `pg_user_mappings`. How do you protect this from other database users?

5. What happens to existing queries using FDW if the remote RDS instance is rebooted?

---

## Cleanup

```sql
-- On local instance
DROP MATERIALIZED VIEW IF EXISTS product_cost_cache;
DROP SCHEMA IF EXISTS remote_inventory CASCADE;
DROP USER MAPPING IF EXISTS FOR [LOCAL-USERNAME] SERVER inventory_server;
DROP SERVER IF EXISTS inventory_server;
DROP EXTENSION IF EXISTS postgres_fdw CASCADE;
DROP TABLE IF EXISTS orders;
DROP TABLE IF EXISTS customers;
```

```sql
-- On remote instance (inventory_db)
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM fdw_report_user;
DROP USER IF EXISTS fdw_report_user;
```

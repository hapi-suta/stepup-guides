# Use 05 - Least Privilege Exercise

**Time:** 25 minutes
**Prerequisite:** Build 05 (Role-Based Access Control)

---

## Scenario

[COMPANY] is launching a new e-commerce platform on Aurora. Three teams need database access with very different requirements:

1. **Product Catalog Service** - read/write to products and categories tables
2. **Customer Support Dashboard** - read-only to orders, customers, and support_tickets
3. **Data Engineering Team** - read-only to everything, plus ability to create temporary tables in a staging schema

Design and implement a minimum-privilege role hierarchy for all three teams.

---

## Setup

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
```

Connect as master user and create the database structure:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

```sql
CREATE DATABASE ecommercedb;
\c ecommercedb

CREATE SCHEMA catalog;
CREATE SCHEMA sales;
CREATE SCHEMA support;
CREATE SCHEMA staging;

CREATE TABLE catalog.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    sku TEXT UNIQUE
);

CREATE TABLE catalog.categories (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    parent_id INT REFERENCES catalog.categories(id)
);

CREATE TABLE sales.orders (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    total NUMERIC(10,2),
    status TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE sales.customers (
    id SERIAL PRIMARY KEY,
    email TEXT UNIQUE,
    full_name TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE support.tickets (
    id SERIAL PRIMARY KEY,
    customer_id INT NOT NULL,
    subject TEXT,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO catalog.products (name, price, sku) VALUES
    ('Widget A', 19.99, 'WGT-001'),
    ('Widget B', 29.99, 'WGT-002');

INSERT INTO catalog.categories (name) VALUES ('Electronics'), ('Accessories');

INSERT INTO sales.customers (email, full_name) VALUES
    ('alice@example.com', 'Alice Johnson'),
    ('bob@example.com', 'Bob Smith');

INSERT INTO sales.orders (customer_id, total, status) VALUES
    (1, 49.98, 'shipped'),
    (2, 29.99, 'pending');

INSERT INTO support.tickets (customer_id, subject) VALUES
    (1, 'Missing item in order'),
    (2, 'Product return request');
```

---

## Task 1 - Design the Role Hierarchy

Before writing any SQL, answer these questions:

1. How many group roles do you need?
2. What should each group role be named?
3. What grants does each group role get?
4. How many login roles do you need?
5. Should login roles get direct grants or group membership?

<details>
<summary>Solution - Role Design</summary>

**Group roles (NOLOGIN):**
- `catalog_readwrite` - SELECT, INSERT, UPDATE on catalog schema tables
- `support_readonly` - SELECT on sales and support schema tables
- `data_readonly` - SELECT on all schemas, plus CREATE in staging

**Login roles:**
- `catalog_service` - member of `catalog_readwrite`
- `support_dashboard` - member of `support_readonly`
- `data_engineer` - member of `data_readonly`

Using group roles lets you add more users later without touching table grants.

</details>

---

## Task 2 - Create the Group Roles

Create the three group roles with the correct grants. Do not give them LOGIN.

<details>
<summary>Solution</summary>

```sql
-- Group role for product catalog service
CREATE ROLE catalog_readwrite NOLOGIN;
GRANT USAGE ON SCHEMA catalog TO catalog_readwrite;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA catalog TO catalog_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA catalog TO catalog_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog
    GRANT SELECT, INSERT, UPDATE ON TABLES TO catalog_readwrite;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog
    GRANT USAGE, SELECT ON SEQUENCES TO catalog_readwrite;

-- Group role for customer support dashboard
CREATE ROLE support_readonly NOLOGIN;
GRANT USAGE ON SCHEMA sales TO support_readonly;
GRANT USAGE ON SCHEMA support TO support_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA sales TO support_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA support TO support_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA sales
    GRANT SELECT ON TABLES TO support_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA support
    GRANT SELECT ON TABLES TO support_readonly;

-- Group role for data engineering
CREATE ROLE data_readonly NOLOGIN;
GRANT USAGE ON SCHEMA catalog TO data_readonly;
GRANT USAGE ON SCHEMA sales TO data_readonly;
GRANT USAGE ON SCHEMA support TO data_readonly;
GRANT USAGE, CREATE ON SCHEMA staging TO data_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA catalog TO data_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA sales TO data_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA support TO data_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA catalog
    GRANT SELECT ON TABLES TO data_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA sales
    GRANT SELECT ON TABLES TO data_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA support
    GRANT SELECT ON TABLES TO data_readonly;
```

</details>

---

## Task 3 - Create the Login Roles

Create login roles and assign them to groups.

<details>
<summary>Solution</summary>

```sql
CREATE ROLE catalog_service WITH LOGIN PASSWORD 'CatalogPass1!';
GRANT CONNECT ON DATABASE ecommercedb TO catalog_service;
GRANT catalog_readwrite TO catalog_service;

CREATE ROLE support_dashboard WITH LOGIN PASSWORD 'SupportPass1!';
GRANT CONNECT ON DATABASE ecommercedb TO support_dashboard;
GRANT support_readonly TO support_dashboard;

CREATE ROLE data_engineer WITH LOGIN PASSWORD 'DataPass1!';
GRANT CONNECT ON DATABASE ecommercedb TO data_engineer;
GRANT data_readonly TO data_engineer;
```

</details>

---

## Task 4 - Test Each Role

Test each role to verify it has the correct access. For each test, note whether it succeeds or fails.

**Test catalog_service:**

```bash
PGPASSWORD='CatalogPass1!' psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=ecommercedb user=catalog_service sslmode=require"
```

```sql
-- Should SUCCEED
INSERT INTO catalog.products (name, price, sku) VALUES ('Widget C', 39.99, 'WGT-003');
SELECT * FROM catalog.products;
UPDATE catalog.products SET price = 42.99 WHERE sku = 'WGT-003';

-- Should FAIL
SELECT * FROM sales.orders;
DELETE FROM catalog.products WHERE sku = 'WGT-003';
DROP TABLE catalog.products;
```

<details>
<summary>Expected results</summary>

- INSERT: succeeds
- SELECT on catalog: succeeds
- UPDATE: succeeds
- SELECT on sales: fails (permission denied)
- DELETE: fails (not granted - only SELECT, INSERT, UPDATE)
- DROP: fails (not owner)

</details>

**Test support_dashboard:**

```bash
PGPASSWORD='SupportPass1!' psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=ecommercedb user=support_dashboard sslmode=require"
```

```sql
-- Should SUCCEED
SELECT * FROM sales.orders;
SELECT * FROM sales.customers;
SELECT * FROM support.tickets;

-- Should FAIL
INSERT INTO sales.orders (customer_id, total, status) VALUES (1, 10.00, 'test');
SELECT * FROM catalog.products;
```

<details>
<summary>Expected results</summary>

- SELECT on sales/support: succeeds
- INSERT on sales: fails (SELECT only)
- SELECT on catalog: fails (no USAGE grant on catalog schema)

</details>

**Test data_engineer:**

```bash
PGPASSWORD='DataPass1!' psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=ecommercedb user=data_engineer sslmode=require"
```

```sql
-- Should SUCCEED
SELECT * FROM catalog.products;
SELECT * FROM sales.orders;
SELECT * FROM support.tickets;
CREATE TABLE staging.temp_analysis (id INT, metric TEXT);

-- Should FAIL
INSERT INTO sales.orders (customer_id, total, status) VALUES (1, 10.00, 'test');
DROP TABLE catalog.products;
```

<details>
<summary>Expected results</summary>

- SELECT on all schemas: succeeds
- CREATE in staging: succeeds
- INSERT on sales: fails (SELECT only)
- DROP on catalog: fails (not owner)

</details>

---

## Task 5 - Audit the Final State

Run the audit query to verify the complete privilege map:

```sql
SELECT
    grantee,
    table_schema,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee IN ('catalog_readwrite', 'support_readonly', 'data_readonly',
                   'catalog_service', 'support_dashboard', 'data_engineer')
  AND table_schema IN ('catalog', 'sales', 'support', 'staging')
GROUP BY grantee, table_schema, table_name
ORDER BY grantee, table_schema, table_name;
```

<details>
<summary>Expected output</summary>

```
     grantee       | table_schema | table_name  |        privileges
-------------------+--------------+-------------+-----------------------
 catalog_readwrite | catalog      | categories  | INSERT, SELECT, UPDATE
 catalog_readwrite | catalog      | products    | INSERT, SELECT, UPDATE
 data_readonly     | catalog      | categories  | SELECT
 data_readonly     | catalog      | products    | SELECT
 data_readonly     | sales        | customers   | SELECT
 data_readonly     | sales        | orders      | SELECT
 data_readonly     | support      | tickets     | SELECT
 support_readonly  | sales        | customers   | SELECT
 support_readonly  | sales        | orders      | SELECT
 support_readonly  | support      | tickets     | SELECT
```

Notice: login roles (catalog_service, support_dashboard, data_engineer) do not appear because their access comes through group membership, not direct grants.

</details>

---

## Task 6 - Add a New Team Member

A new developer joins the catalog team. Add them with minimal work.

<details>
<summary>Solution</summary>

```sql
CREATE ROLE carol WITH LOGIN PASSWORD 'CarolPass1!';
GRANT CONNECT ON DATABASE ecommercedb TO carol;
GRANT catalog_readwrite TO carol;
```

That's it - three lines. Carol inherits all the catalog permissions through the group role. No table-level grants needed.

To remove Carol later:

```sql
REVOKE catalog_readwrite FROM carol;
REVOKE CONNECT ON DATABASE ecommercedb FROM carol;
```

</details>

---

## Task 7 - Document the Role Hierarchy

Draw or write out the complete role hierarchy showing:
- Which group roles exist
- What each group role grants
- Which login roles are members of which groups

<details>
<summary>Solution - Role hierarchy diagram</summary>

```
ecommercedb
|
+-- catalog_readwrite (NOLOGIN)
|   |-- catalog.products: SELECT, INSERT, UPDATE
|   |-- catalog.categories: SELECT, INSERT, UPDATE
|   |-- Members: catalog_service, carol
|
+-- support_readonly (NOLOGIN)
|   |-- sales.orders: SELECT
|   |-- sales.customers: SELECT
|   |-- support.tickets: SELECT
|   |-- Members: support_dashboard
|
+-- data_readonly (NOLOGIN)
    |-- catalog.*: SELECT
    |-- sales.*: SELECT
    |-- support.*: SELECT
    |-- staging: USAGE + CREATE
    |-- Members: data_engineer
```

</details>

---

## Clean Up

```sql
\c postgres
REVOKE CONNECT ON DATABASE ecommercedb FROM catalog_service, support_dashboard, data_engineer, carol;
DROP DATABASE ecommercedb;
DROP ROLE carol;
DROP ROLE catalog_service;
DROP ROLE support_dashboard;
DROP ROLE data_engineer;
DROP ROLE catalog_readwrite;
DROP ROLE support_readonly;
DROP ROLE data_readonly;
```

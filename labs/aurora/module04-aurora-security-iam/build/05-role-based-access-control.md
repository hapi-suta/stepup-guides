# Build 05 - Role-Based Access Control

**Time:** 35 minutes
**Goal:** Create PostgreSQL roles with least-privilege permissions on your Aurora cluster, use group roles, and understand Row-Level Security basics.

---

## Before You Start

Read `concepts/01-database-security-layers.md` (Layer 3 - Authorization).

You need:
- A running Aurora PostgreSQL cluster
- psql installed
- Your cluster endpoint, master username, and master password

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export CLUSTER_PORT="5432"
export MASTER_USER="postgres"
export MASTER_DB="postgres"
```

---

## Step 1 - Connect to Your Aurora Cluster

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=$MASTER_USER \
  --dbname=$MASTER_DB
```

psql will prompt for a password. Enter your master password.

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

> **Concept:** The `=>` prompt means you are connected as a regular user. On Aurora, even the master user is not a true superuser - you will always see `=>` instead of `=#`.

---

## Step 2 - See What Roles Already Exist

```sql
\du
```

`\du` is a psql shortcut that lists all database roles.

Expected output (yours will differ):

```
                                   List of roles
 Role name     |            Attributes            |           Member of
---------------+----------------------------------+---------------------------
 postgres      | Create role, Create DB           | {rds_superuser}
 rds_superuser | Cannot login                     | {}
 rdsadmin      | Superuser, Create role, ...      | {}
```

The `rdsadmin` role is used internally by AWS. Do not modify it.
The `postgres` user (your master user) is a member of `rds_superuser`.

---

## Step 3 - Create an Application Database and Schema

Create the application database:

```sql
CREATE DATABASE appdb;
```

Connect to it:

```sql
\c appdb
```

Create a schema for the application:

```sql
CREATE SCHEMA app;
```

Create tables to test with:

```sql
CREATE TABLE app.orders (
    id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    amount NUMERIC(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

```sql
CREATE TABLE app.products (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    price NUMERIC(10,2),
    sku TEXT UNIQUE
);
```

```sql
INSERT INTO app.products (name, price, sku) VALUES
    ('Widget A', 19.99, 'WGT-001'),
    ('Widget B', 29.99, 'WGT-002');
```

---

## Step 4 - Create an Application Role (Least Privilege)

Create the application role:

```sql
CREATE ROLE app_user WITH LOGIN PASSWORD 'StrongPass1!';
```

`CREATE ROLE` creates a new role.
`WITH LOGIN` allows this role to log in as a user.
`PASSWORD` sets the initial password.

Grant only what the app needs:

```sql
GRANT CONNECT ON DATABASE appdb TO app_user;
```

This lets the role connect to the database. Without this, nothing else matters.

```sql
GRANT USAGE ON SCHEMA app TO app_user;
```

`USAGE` on a schema lets the role see and access objects inside it. Without this, the role cannot reach any tables.

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
```

This grants read and write access on all current tables in the `app` schema.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
```

`ALTER DEFAULT PRIVILEGES` means any new table created in the `app` schema will automatically get these grants. Without this, new tables would be inaccessible.

```sql
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_user;
```

Sequences power SERIAL columns (like the `id` column). The app needs this to insert rows.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
GRANT USAGE, SELECT ON SEQUENCES TO app_user;
```

---

## Step 5 - Verify the Application Role

Open a second terminal and test the new role:

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=app_user \
  --dbname=appdb
```

Enter the password `StrongPass1!` when prompted.

Test that it can insert:

```sql
INSERT INTO app.orders (customer_name, amount) VALUES ('Test Customer', 99.99);
```

Expected output:

```
INSERT 0 1
```

Test that it can select:

```sql
SELECT * FROM app.orders;
```

Expected output (yours will differ):

```
 id | customer_name  | amount |          created_at
----+----------------+--------+------------------------------
  1 | Test Customer  |  99.99 | 2026-06-09 14:23:11.456789+00
```

Test that it CANNOT drop tables (it should not be able to):

```sql
DROP TABLE app.orders;
```

Expected output:

```
ERROR:  must be owner of table orders
```

Good. The app user cannot drop tables.

Exit:

```sql
\q
```

---

## Step 6 - Create a Read-Only Role

Go back to your master user session. Create a read-only role:

```sql
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'ReadOnly1!';
```

```sql
GRANT CONNECT ON DATABASE appdb TO readonly_user;
```

```sql
GRANT USAGE ON SCHEMA app TO readonly_user;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA app TO readonly_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
GRANT SELECT ON TABLES TO readonly_user;
```

Verify it cannot insert:

```bash
PGPASSWORD='ReadOnly1!' psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=readonly_user \
  --dbname=appdb \
  --command="INSERT INTO app.orders (customer_name, amount) VALUES ('Hack', 0);"
```

Expected output:

```
ERROR:  permission denied for table orders
```

---

## Step 7 - Create a Group Role (Recommended Pattern)

Instead of granting permissions to individual users, create a group role. Then add users to the group.

```sql
CREATE ROLE app_readwrite NOLOGIN;
```

`NOLOGIN` means this role is a group - it cannot log in directly.

```sql
GRANT USAGE ON SCHEMA app TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_readwrite;
```

Create users and add them to the group:

```sql
CREATE ROLE alice WITH LOGIN PASSWORD 'AlicePass1!';
GRANT CONNECT ON DATABASE appdb TO alice;
GRANT app_readwrite TO alice;
```

```sql
CREATE ROLE bob WITH LOGIN PASSWORD 'BobPass1!';
GRANT CONNECT ON DATABASE appdb TO bob;
GRANT app_readwrite TO bob;
```

Now if you need to revoke access for Alice:

```sql
REVOKE app_readwrite FROM alice;
```

You do not need to touch any table-level grants. The group handles it.

> **Concept:** This is the "role as group" pattern. It is the standard way to manage permissions in PostgreSQL. Think of `app_readwrite` like an Active Directory group.

---

## Step 8 - REVOKE Privileges

REVOKE is the opposite of GRANT. Use it to remove specific privileges.

Remove DELETE from `app_user` (maybe the app should not delete data):

```sql
REVOKE DELETE ON ALL TABLES IN SCHEMA app FROM app_user;
```

Remove all write access from a role:

```sql
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app FROM readonly_user;
```

> **Note:** REVOKE only removes privileges that were directly granted. It does not affect privileges inherited through group membership.

---

## Step 9 - Row-Level Security (RLS) Basics

RLS lets you restrict which rows a user can see, not just which tables.

Create a multi-tenant table:

```sql
CREATE TABLE app.tenant_data (
    id SERIAL PRIMARY KEY,
    tenant_id INT NOT NULL,
    data TEXT NOT NULL
);
```

```sql
INSERT INTO app.tenant_data (tenant_id, data) VALUES
    (1, 'Tenant 1 secret data'),
    (1, 'Tenant 1 more data'),
    (2, 'Tenant 2 secret data'),
    (2, 'Tenant 2 more data');
```

Enable RLS on the table:

```sql
ALTER TABLE app.tenant_data ENABLE ROW LEVEL SECURITY;
```

Create a policy that restricts rows based on a session variable:

```sql
CREATE POLICY tenant_isolation ON app.tenant_data
    USING (tenant_id = current_setting('app.tenant_id')::int);
```

`USING` defines the condition. Only rows where `tenant_id` matches the session variable are visible.

Grant access to app_user:

```sql
GRANT SELECT, INSERT ON app.tenant_data TO app_user;
GRANT USAGE, SELECT ON SEQUENCE app.tenant_data_id_seq TO app_user;
```

Test as app_user. Open a second terminal:

```bash
PGPASSWORD='StrongPass1!' psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=app_user \
  --dbname=appdb
```

Set the tenant context and query:

```sql
SET app.tenant_id = '1';
SELECT * FROM app.tenant_data;
```

Expected output:

```
 id | tenant_id |        data
----+-----------+---------------------
  1 |         1 | Tenant 1 secret data
  2 |         1 | Tenant 1 more data
```

Only tenant 1 rows are visible. Tenant 2 data is hidden.

Now switch tenant:

```sql
SET app.tenant_id = '2';
SELECT * FROM app.tenant_data;
```

Expected output:

```
 id | tenant_id |        data
----+-----------+---------------------
  3 |         2 | Tenant 2 secret data
  4 |         2 | Tenant 2 more data
```

Only tenant 2 rows are visible now.

Exit:

```sql
\q
```

> **Note:** RLS policies do not apply to the table owner or superusers. The master user can always see all rows. This is a safety feature.

---

## Step 10 - Audit Permissions

To see what privileges a role has on tables:

```sql
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('app_user', 'readonly_user', 'alice', 'bob')
ORDER BY grantee, table_name;
```

Expected output (yours will differ):

```
   grantee    | table_schema | table_name  | privilege_type
--------------+--------------+-------------+----------------
 app_user     | app          | orders      | INSERT
 app_user     | app          | orders      | SELECT
 app_user     | app          | orders      | UPDATE
 readonly_user| app          | orders      | SELECT
 ...
```

---

## What You Built

- A dedicated `appdb` database with an `app` schema
- An `app_user` role with INSERT/UPDATE/SELECT (not DROP, not more)
- A `readonly_user` role with SELECT only
- A group role (`app_readwrite`) pattern for scalable permission management
- Row-Level Security on a multi-tenant table
- An audit query to review granted privileges

---

## Clean Up (Optional)

```sql
-- Run as master user, connect to postgres database first
\c postgres
REVOKE ALL ON DATABASE appdb FROM app_user, readonly_user, alice, bob;
DROP ROLE alice;
DROP ROLE bob;
DROP ROLE app_user;
DROP ROLE readonly_user;
DROP ROLE app_readwrite;
DROP DATABASE appdb;
```

---

## Key Rules to Remember

1. Never grant more than an application needs
2. Use group roles - not direct table grants to individual users
3. Always set `ALTER DEFAULT PRIVILEGES` or new tables will be inaccessible
4. The master user should not be the application user
5. `GRANT ALL` is almost never the right answer
6. Use RLS for multi-tenant data isolation within shared tables

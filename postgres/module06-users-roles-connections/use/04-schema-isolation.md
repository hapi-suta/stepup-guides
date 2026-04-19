# Exercise 04 - Schema Isolation

**Module:** 06 - Users, Roles & Connections
**Time:** 20 minutes

---

## Scenario

A company has two teams: the payments team and the inventory team. Both teams share the same PostgreSQL database but must not access each other's data. You will create separate schemas and grant each team access to only their schema.

---

## Setup

```bash
ssh -i your-key.pem ec2-user@NODE1
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Create schemas for each team

```sql
CREATE SCHEMA IF NOT EXISTS payments;
```

```sql
CREATE SCHEMA IF NOT EXISTS inventory;
```

Expected output for each:

```
CREATE SCHEMA
```

---

## Task 2 - Create tables in each schema

```sql
CREATE TABLE IF NOT EXISTS payments.transactions (
  id          serial PRIMARY KEY,
  order_id    integer,
  amount      numeric(10,2),
  status      text,
  created_at  timestamp DEFAULT now()
);
```

```sql
CREATE TABLE IF NOT EXISTS inventory.stock (
  id          serial PRIMARY KEY,
  product_id  integer,
  quantity    integer,
  warehouse   text,
  updated_at  timestamp DEFAULT now()
);
```

Expected output for each:

```
CREATE TABLE
```

---

## Task 3 - Create team roles

```sql
CREATE ROLE payments_team NOLOGIN;
```

```sql
CREATE ROLE inventory_team NOLOGIN;
```

```sql
CREATE ROLE payments_user WITH LOGIN PASSWORD 'pay123';
```

```sql
CREATE ROLE inventory_user WITH LOGIN PASSWORD 'inv123';
```

```sql
GRANT payments_team TO payments_user;
```

```sql
GRANT inventory_team TO inventory_user;
```

---

## Task 4 - Grant schema-scoped access

Grant access to the payments team:

```sql
GRANT CONNECT ON DATABASE stepup_store TO payments_team;
```

```sql
GRANT USAGE ON SCHEMA payments TO payments_team;
```

```sql
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA payments TO payments_team;
```

Grant access to the inventory team:

```sql
GRANT CONNECT ON DATABASE stepup_store TO inventory_team;
```

```sql
GRANT USAGE ON SCHEMA inventory TO inventory_team;
```

```sql
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA inventory TO inventory_team;
```

Do NOT grant either team access to the other's schema.

---

## Task 5 - Set default search_path per team

```sql
ALTER ROLE payments_user SET search_path TO payments, public;
```

```sql
ALTER ROLE inventory_user SET search_path TO inventory, public;
```

This means `SELECT * FROM transactions` (without schema prefix) will automatically look in the payments schema for payments_user.

---

## Task 6 - Test payments_user isolation

In a second terminal:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U payments_user -d stepup_store
```

```sql
SELECT * FROM transactions LIMIT 5;
```

This should work (search_path resolves to payments.transactions).

```sql
SELECT * FROM inventory.stock LIMIT 5;
```

Expected output:

```
ERROR:  permission denied for schema inventory
```

---

## Task 7 - Test inventory_user isolation

In a third terminal:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U inventory_user -d stepup_store
```

```sql
SELECT * FROM stock LIMIT 5;
```

This should work (search_path resolves to inventory.stock).

```sql
SELECT * FROM payments.transactions LIMIT 5;
```

Expected output:

```
ERROR:  permission denied for schema payments
```

---

## Task 8 - Verify schema ownership

Back in the postgres terminal:

```sql
SELECT schema_name, schema_owner
FROM information_schema.schemata
WHERE schema_name IN ('payments', 'inventory');
```

Expected output:

```
 schema_name | schema_owner
-------------+--------------
 inventory   | postgres
 payments    | postgres
```

---

## Task 9 - Clean up

```sql
DROP TABLE payments.transactions;
DROP TABLE inventory.stock;
DROP SCHEMA payments;
DROP SCHEMA inventory;
REVOKE payments_team FROM payments_user;
REVOKE inventory_team FROM inventory_user;
DROP ROLE payments_user;
DROP ROLE inventory_user;
DROP ROLE payments_team;
DROP ROLE inventory_team;
```

```bash
\q
```

```bash
exit
```

---

## Review Questions

1. Why did we set search_path on the role instead of relying on the session default?
2. What happens if both teams need read access to a shared `public` reference table?
3. If you grant USAGE on a schema to a role, can that role see the table names inside the schema without SELECT privilege?

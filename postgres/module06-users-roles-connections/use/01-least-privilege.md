# Exercise 01 - Least Privilege Role Hierarchy

**Module:** 06 - Users, Roles & Connections
**Time:** 20 minutes

---

## Scenario

You are the DBA for a retail application. Three types of users need database access:

- **Reporting team** - read-only access to all tables
- **Application backend** - read and write access to orders and customers
- **Senior developers** - full DDL rights within the app schema

Your task is to design and implement a role hierarchy that follows least privilege.

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

## Task 1 - Create group roles (no LOGIN)

Group roles define privileges. Members inherit them. The group roles themselves never connect.

```sql
CREATE ROLE app_read NOLOGIN;
```

```sql
CREATE ROLE app_write NOLOGIN;
```

```sql
CREATE ROLE app_admin NOLOGIN;
```

---

## Task 2 - Grant privileges to group roles

Grant read-only to app_read:

```sql
GRANT CONNECT ON DATABASE stepup_store TO app_read;
```

```sql
GRANT USAGE ON SCHEMA public TO app_read;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_read;
```

Grant read-write to app_write (inherits nothing from app_read directly - grant explicitly):

```sql
GRANT CONNECT ON DATABASE stepup_store TO app_write;
```

```sql
GRANT USAGE ON SCHEMA public TO app_write;
```

```sql
GRANT SELECT, INSERT, UPDATE ON TABLE orders TO app_write;
```

```sql
GRANT SELECT, INSERT, UPDATE ON TABLE customers TO app_write;
```

```sql
GRANT SELECT ON TABLE products TO app_write;
```

Grant DDL to app_admin:

```sql
GRANT CONNECT ON DATABASE stepup_store TO app_admin;
```

```sql
GRANT ALL ON SCHEMA public TO app_admin;
```

```sql
GRANT ALL ON ALL TABLES IN SCHEMA public TO app_admin;
```

---

## Task 3 - Create login users and assign them to groups

```sql
CREATE ROLE reporter_alice WITH LOGIN PASSWORD 'alice123';
```

```sql
CREATE ROLE backend_bob WITH LOGIN PASSWORD 'bob123';
```

```sql
CREATE ROLE dev_carol WITH LOGIN PASSWORD 'carol123';
```

```sql
GRANT app_read TO reporter_alice;
```

```sql
GRANT app_write TO backend_bob;
```

```sql
GRANT app_admin TO dev_carol;
```

---

## Task 4 - Test each role

Open three terminals and test each login user.

**Test reporter_alice (read-only):**

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U reporter_alice -d stepup_store
```

```sql
SELECT count(*) FROM orders;
```

This should succeed.

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount) VALUES (1, 1, 1, 9.99);
```

Expected output:

```
ERROR:  permission denied for table orders
```

**Test backend_bob (read-write on orders):**

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U backend_bob -d stepup_store
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount) VALUES (1, 1, 1, 9.99);
```

This should succeed.

```sql
DROP TABLE orders;
```

Expected output:

```
ERROR:  must be owner of table orders
```

**Test dev_carol (admin):**

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U dev_carol -d stepup_store
```

```sql
CREATE TABLE test_schema_check (id serial PRIMARY KEY);
```

This should succeed.

```sql
DROP TABLE test_schema_check;
```

---

## Task 5 - Verify role membership

Back in the postgres terminal:

```sql
SELECT r.rolname AS member, g.rolname AS group_role
FROM pg_auth_members am
JOIN pg_roles r ON am.member = r.oid
JOIN pg_roles g ON am.roleid = g.oid
WHERE g.rolname IN ('app_read', 'app_write', 'app_admin')
ORDER BY g.rolname, r.rolname;
```

Expected output (yours will differ):

```
   member      | group_role
---------------+------------
 dev_carol     | app_admin
 reporter_alice| app_read
 backend_bob   | app_write
```

---

## Task 6 - Clean up

First, remove the login roles from their groups:

```sql
REVOKE app_read FROM reporter_alice;
```

```sql
REVOKE app_write FROM backend_bob;
```

```sql
REVOKE app_admin FROM dev_carol;
```

Drop the login roles:

```sql
DROP ROLE reporter_alice;
```

```sql
DROP ROLE backend_bob;
```

```sql
DROP ROLE dev_carol;
```

Revoke table-level privileges from the group roles:

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_read;
```

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_write;
```

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_admin;
```

Revoke schema-level privileges:

```sql
REVOKE ALL ON SCHEMA public FROM app_read;
```

```sql
REVOKE ALL ON SCHEMA public FROM app_write;
```

```sql
REVOKE ALL ON SCHEMA public FROM app_admin;
```

Revoke database-level privileges:

```sql
REVOKE ALL ON DATABASE stepup_store FROM app_read;
```

```sql
REVOKE ALL ON DATABASE stepup_store FROM app_write;
```

```sql
REVOKE ALL ON DATABASE stepup_store FROM app_admin;
```

Drop the group roles:

```sql
DROP ROLE app_read;
```

```sql
DROP ROLE app_write;
```

```sql
DROP ROLE app_admin;
```

```bash
\q
```

```bash
exit
```

---

## Review Questions

1. Why did we create group roles without LOGIN instead of just creating users with the right privileges directly?
2. What would happen if backend_bob tried to access a table added to the schema tomorrow (no default privileges set)?
3. Why does dev_carol still not have SUPERUSER even though she has app_admin?

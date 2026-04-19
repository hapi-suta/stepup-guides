# Build 01 - Privilege Hierarchy

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- How PostgreSQL organizes privileges in layers: cluster, database, schema, table, column, and row
- The GRANT and REVOKE syntax for each layer
- What the PUBLIC role is and why it matters
- How to use has_table_privilege() to check access programmatically
- How to create a test schema with restricted access

---

> **Concept: The Privilege Hierarchy**
> PostgreSQL enforces access control at six levels. Starting from the top: cluster-level attributes (SUPERUSER, CREATEDB) control what a role can do across all databases. Database-level privileges (CONNECT, CREATE, TEMP) control whether a role can enter a specific database. Schema-level privileges (USAGE, CREATE) control whether a role can see or create objects within a schema. Table-level privileges (SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER) control row-level operations. Column-level privileges (SELECT, INSERT, UPDATE) restrict access to specific columns. Row-level security (RLS) is the final gate, filtering which rows a role can see within a table. Every query must pass all of these checks in order.

---

> **Concept: The PUBLIC Role**
> PostgreSQL has a special built-in role called PUBLIC. Every role is automatically a member of PUBLIC. Any privilege granted to PUBLIC is available to every role in the cluster. By default, PostgreSQL grants CONNECT on databases and USAGE on the public schema to PUBLIC. This means all roles can connect to any database and see objects in the public schema unless you explicitly revoke these defaults. CIS benchmarks recommend revoking the CREATE privilege on the public schema from PUBLIC.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

This switches you to the `postgres` operating system account. The `-i` flag gives you a login shell which loads the correct environment. The `-u postgres` flag specifies the target user.

---

## Step 3 - Connect to PostgreSQL

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

The full path is required because `/usr/pgsql-16/bin` is not in the default PATH. The `-p 5432` flag specifies the port. The `-d stepup_store` flag selects the database.

Expected output (yours will differ):

```
psql (16.3)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - Review your existing roles

```sql
\du
```

This lists all roles in the cluster. You should see `postgres` and any roles created in Module 06 such as `app_user`, `readonly_user`, and `admin_user`.

Expected output (yours will differ):

```
                                   List of roles
 Role name     |                         Attributes
---------------+------------------------------------------------------------
 admin_user    | Create role, Create DB
 app_user      | 20 connections
 postgres      | Superuser, Create role, Create DB, Replication, Bypass RLS
 readonly_user |
```

---

## Step 5 - Check database-level privileges

```sql
SELECT datname, datacl FROM pg_database WHERE datname = 'stepup_store';
```

The `datacl` column shows the access control list for the database. Each entry uses the format `grantee=privileges/grantor`. An empty grantee means PUBLIC.

Expected output (yours will differ):

```
   datname    |              datacl
--------------+----------------------------------
 stepup_store | {=Tc/postgres,postgres=CTc/postgres}
```

The `T` stands for TEMP, `c` stands for CONNECT, `C` stands for CREATE.

---

## Step 6 - Check schema-level privileges

```sql
SELECT nspname, nspacl FROM pg_namespace WHERE nspname = 'public';
```

Expected output (yours will differ):

```
 nspname |     nspacl
---------+----------------
 public  | {postgres=UC/postgres,=U/postgres}
```

The `=U/postgres` entry means PUBLIC has USAGE on the public schema, granted by postgres. This is a default that should be reviewed for production systems.

---

## Step 7 - Check table-level privileges on a specific table

```sql
SELECT grantee, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'orders' AND table_schema = 'public';
```

Expected output (yours will differ):

```
 grantee  | privilege_type | is_grantable
----------+----------------+--------------
 postgres | INSERT         | YES
 postgres | SELECT         | YES
 postgres | UPDATE         | YES
 postgres | DELETE         | YES
(4 rows)
```

---

## Step 8 - Use has_table_privilege() to check access

```sql
SELECT has_table_privilege('app_user', 'orders', 'SELECT');
```

This function returns true if the specified role has the given privilege on the table. It respects inherited privileges through role membership.

Expected output:

```
 has_table_privilege
------------------------
 f
(1 row)
```

The result is `f` (false) because we have not granted any privilege to `app_user` yet.

---

## Step 9 - Grant SELECT on the orders table to app_user

```sql
GRANT SELECT ON TABLE orders TO app_user;
```

The `GRANT` command gives a privilege to a role. The `ON TABLE` clause specifies the object type.

Expected output:

```
GRANT
```

---

## Step 10 - Verify the grant took effect

```sql
SELECT has_table_privilege('app_user', 'orders', 'SELECT');
```

Expected output:

```
 has_table_privilege
------------------------
 t
(1 row)
```

---

## Step 11 - Grant multiple privileges at once

```sql
GRANT INSERT, UPDATE ON TABLE orders TO app_user;
```

You can list multiple privilege types in a single GRANT statement. This is equivalent to running separate GRANT statements for each privilege.

Expected output:

```
GRANT
```

---

## Step 12 - Grant a column-level privilege

Column-level privileges are more restrictive than table-level. You can allow a role to SELECT only specific columns.

```sql
GRANT SELECT (order_id, status, total_amount) ON TABLE orders TO readonly_user;
```

This grants `readonly_user` the ability to SELECT only the `id`, `status`, and `total_amount` columns. Attempting to SELECT other columns will fail.

Expected output:

```
GRANT
```

---

## Step 13 - Create a restricted test schema

```sql
CREATE SCHEMA restricted_data;
```

This creates a new schema. By default, only the owner (postgres) can use it.

Expected output:

```
CREATE SCHEMA
```

---

## Step 14 - Create a table in the restricted schema

```sql
CREATE TABLE restricted_data.sensitive_records (
    id          SERIAL PRIMARY KEY,
    employee_id INTEGER NOT NULL,
    salary      NUMERIC(10,2),
    ssn         TEXT,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

Expected output:

```
CREATE TABLE
```

---

## Step 15 - Confirm app_user cannot see the restricted schema

Open a new terminal session as app_user to test access. First exit psql but stay as the postgres OS user:

```sql
\q
```

Connect as app_user:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U app_user
```

Try to query the restricted table:

```sql
SELECT * FROM restricted_data.sensitive_records;
```

Expected output:

```
ERROR:  permission denied for schema restricted_data
```

Even though the table exists, `app_user` cannot see inside `restricted_data` because it has no USAGE privilege on that schema. The schema acts as a security boundary.

---

## Step 16 - Exit app_user session

```sql
\q
```

---

## Step 17 - Connect back as postgres

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 18 - Revoke a privilege

```sql
REVOKE UPDATE ON TABLE orders FROM app_user;
```

`REVOKE` removes a privilege. The role immediately loses that privilege - no restart or session reset is needed.

Expected output:

```
REVOKE
```

---

## Step 19 - Verify the revoke

```sql
SELECT has_table_privilege('app_user', 'orders', 'UPDATE');
```

Expected output:

```
 has_table_privilege
------------------------
 f
(1 row)
```

---

## Step 20 - Check all table privileges for a role using information_schema

```sql
SELECT table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'app_user'
ORDER BY table_schema, table_name, privilege_type;
```

This query gives you a full picture of every table-level privilege held by a specific role across all schemas.

Expected output (yours will differ):

```
 table_schema | table_name | privilege_type
--------------+------------+----------------
 public       | orders     | INSERT
 public       | orders     | SELECT
(2 rows)
```

---

## Step 21 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Summary

| Privilege Layer | Object | Controlled By |
|-----------------|--------|---------------|
| Cluster | Role attributes | SUPERUSER, CREATEDB, CREATEROLE |
| Database | Database | CONNECT, CREATE, TEMP |
| Schema | Schema | USAGE, CREATE |
| Table | Table | SELECT, INSERT, UPDATE, DELETE, TRUNCATE |
| Column | Column | SELECT, INSERT, UPDATE |
| Row | Rows within table | Row-Level Security policies |

Each layer is a gate. A role must pass every gate between itself and the data it wants to access. Missing USAGE on a schema blocks access to all objects inside it, even if the role has SELECT on specific tables.

---

## Interview Discussion Points

1. **What happens if you GRANT SELECT on a table but the role has no USAGE on the schema?** - The grant is stored but has no effect. The role receives "permission denied for schema" when it tries to access the table. USAGE on the schema is required before any object-level privileges can be exercised. This is a common mistake when onboarding new roles.

2. **What does granting a privilege to PUBLIC mean?** - It makes that privilege available to every role in the cluster, including roles that are created in the future. Granting SELECT on a public table to PUBLIC means anyone who can connect to the database can read that table. This is almost never what you want in a multi-tenant or production system.

3. **How is GRANT OPTION different from just having a privilege?** - WITH GRANT OPTION allows the grantee to grant that same privilege to other roles. Without it, the role can use the privilege but cannot delegate it. This creates privilege chains that can be hard to audit - one misconfigured GRANT OPTION can result in unexpected access spreading through the role hierarchy.

4. **Explain the difference between table-level and column-level SELECT privileges.** - Table-level SELECT allows reading all columns. Column-level SELECT restricts which columns can be read. You cannot mix them on the same table for the same grantee in a way that grants less than table-level - if a role has table-level SELECT, the column-level grant adds nothing. Column-level SELECT is most useful when you want to share partial data without sharing the whole table.

5. **How do you find all privileges a specific role has across an entire database?** - Query `information_schema.role_table_grants` for table and column privileges, `information_schema.role_schema_grants` for schema privileges (or pg_namespace.nspacl), and `pg_database` for database-level access. For a complete picture including inherited privileges through role membership, you may need to recurse through pg_auth_members.

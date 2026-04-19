# Scenario 05 - Default Privileges Missing

**Severity:** MEDIUM
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application cannot access the inventory or
shipments tables. Error: permission denied for table.
The DBA created these tables but the app cannot read them.
Existing tables like products and orders work fine.
```

---

## Key Concepts for Revision

- **New tables do not inherit grants** - When a superuser creates a new table, no other role has access to it by default. Existing grants on other tables do not carry over. Each new table requires explicit `GRANT` statements - unless `ALTER DEFAULT PRIVILEGES` is configured.

- **ALTER DEFAULT PRIVILEGES automates future grants** - `ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_user` means every future table created in the `public` schema automatically gets a SELECT grant to `app_user`. This prevents the "forgot to grant" problem.

- **Default privileges are per-creator** - `ALTER DEFAULT PRIVILEGES FOR ROLE postgres` only applies to tables created by `postgres`. If another role creates tables, separate default privileges must be set for that role.

- **Existing tables are not affected** - `ALTER DEFAULT PRIVILEGES` only affects objects created after the command runs. You must still manually grant access to any existing tables that were created without default privileges.

---

## Diagnostic Steps

### Step 1 - Reproduce the error as app_user

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SET ROLE app_user;
```

```sql
SELECT * FROM inventory LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table inventory
```

```sql
RESET ROLE;
```

### Step 2 - Check what grants exist on the new tables

```sql
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_name IN ('inventory', 'shipments')
  AND grantee != 'postgres'
ORDER BY table_name, grantee;
```

Expected output:

```
 grantee | table_name | privilege_type
---------+------------+----------------
(0 rows)
```

No grants exist for any non-owner role. That is the problem.

### Step 3 - Check current default privileges

```sql
SELECT defaclrole::regrole AS role,
       defaclnamespace::regnamespace AS schema,
       defaclobjtype AS object_type,
       defaclacl AS acl
FROM pg_default_acl;
```

Expected output:

```
 role | schema | object_type | acl
------+--------+-------------+-----
(0 rows)
```

No default privileges are configured. This means every new table requires manual grants.

---

## Resolution

### Step 1 - Grant access on the existing tables

Fix the immediate problem first. Grant the needed privileges on the tables that already exist.

```sql
GRANT SELECT, INSERT, UPDATE ON inventory TO app_user;
```

Expected output:

```
GRANT
```

```sql
GRANT SELECT, INSERT, UPDATE ON shipments TO app_user;
```

Expected output:

```
GRANT
```

### Step 2 - Grant usage on sequences too

Serial columns use sequences. The application needs usage on them to insert rows.

```sql
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;
```

Expected output:

```
GRANT
```

### Step 3 - Set up ALTER DEFAULT PRIVILEGES for future tables

This prevents the problem from happening again.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;
```

Expected output:

```
ALTER DEFAULT PRIVILEGES
```

This means any table created in the `public` schema from now on automatically grants SELECT, INSERT, UPDATE to `app_user`.

### Step 4 - Set up default privileges for sequences too

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT USAGE ON SEQUENCES TO app_user;
```

Expected output:

```
ALTER DEFAULT PRIVILEGES
```

### Step 5 - Verify default privileges are in place

```sql
SELECT defaclrole::regrole AS role,
       defaclnamespace::regnamespace AS schema,
       defaclobjtype AS object_type,
       defaclacl AS acl
FROM pg_default_acl;
```

Expected output (yours will differ):

```
   role   | schema | object_type |                  acl
----------+--------+-------------+---------------------------------------
 postgres | public | r           | {app_user=arw/postgres}
 postgres | public | S           | {app_user=U/postgres}
(2 rows)
```

The `r` object type means tables (relations). The `S` means sequences.

### Step 6 - Test as app_user

```sql
SET ROLE app_user;
```

```sql
SELECT * FROM inventory LIMIT 2;
```

Expected output (yours will differ):

```
 id | product_name | quantity |  warehouse
----+--------------+----------+--------------
  1 | Laptop       |       50 | Warehouse-A
  2 | Keyboard     |      200 | Warehouse-B
(2 rows)
```

```sql
SELECT * FROM shipments LIMIT 2;
```

Expected output (yours will differ):

```
 id | inventory_id | destination |       shipped_at
----+--------------+-------------+------------------------
  1 |            1 | New York    | 2026-04-19 10:00:00+00
  2 |            2 | Chicago     | 2026-04-19 10:00:00+00
(2 rows)
```

### Step 7 - Test that future tables auto-grant (optional)

```sql
RESET ROLE;
```

```sql
CREATE TABLE test_auto_grant (id serial, name text);
```

```sql
SET ROLE app_user;
```

```sql
SELECT * FROM test_auto_grant;
```

Expected output:

```
 id | name
----+------
(0 rows)
```

The query succeeds (returns 0 rows, not permission denied). Default privileges are working.

```sql
RESET ROLE;
```

```sql
DROP TABLE test_auto_grant;
```

### Step 8 - Exit

```sql
\q
```

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user can SELECT from inventory
- app_user can SELECT from shipments
- ALTER DEFAULT PRIVILEGES are configured for tables
- New tables automatically get grants

---

## Interview Discussion Points

1. **Why does PostgreSQL not automatically grant access to new tables?** - PostgreSQL follows the principle of least privilege. New objects are only accessible to the owner by default. This is safer than auto-granting - it forces DBAs to make explicit access decisions. The tradeoff is operational overhead, which ALTER DEFAULT PRIVILEGES was designed to solve.

2. **What is the difference between GRANT and ALTER DEFAULT PRIVILEGES?** - `GRANT` applies to existing objects immediately. `ALTER DEFAULT PRIVILEGES` only affects objects created in the future. To fully cover a schema, you need both: GRANT for existing objects and ALTER DEFAULT PRIVILEGES for future ones.

3. **What does "FOR ROLE" mean in ALTER DEFAULT PRIVILEGES?** - `ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public` means "when postgres creates objects in public schema, auto-grant." If you omit `FOR ROLE`, it defaults to the current user. If a different role (like a deploy role) creates tables, you need a separate `ALTER DEFAULT PRIVILEGES FOR ROLE deploy_role` statement.

4. **How would you audit which tables are missing grants?** - Query: `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT EXISTS (SELECT 1 FROM information_schema.role_table_grants g WHERE g.table_name = c.relname AND g.grantee = 'app_user');`. This finds all tables in public schema where app_user has no grants.

5. **Should you use ALTER DEFAULT PRIVILEGES or role inheritance for managing access?** - Both have their place. ALTER DEFAULT PRIVILEGES automates table-level grants. Role inheritance (group roles) simplifies user management. The best practice is to combine them: create a group role like `app_readonly`, set default privileges to grant to `app_readonly`, then add users to the group. This gives you both automatic grants and easy user management.

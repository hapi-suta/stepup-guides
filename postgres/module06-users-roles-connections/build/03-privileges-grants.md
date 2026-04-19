# Build 03 - Privileges and Grants

**Module:** 06 - Users, Roles & Connections
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- The privilege hierarchy: cluster - database - schema - table - column
- How to use GRANT and REVOKE for databases, schemas, tables, and columns
- How default privileges work with ALTER DEFAULT PRIVILEGES
- How to set up app_user with minimum required access for the Pulse app

---

> **Concept: Privilege hierarchy**
> PostgreSQL privileges cascade through four levels. A role needs CONNECT on the database, USAGE on the schema, and then the specific object privilege (SELECT, INSERT, etc.) before it can touch any data. Having SELECT on a table does not help if the role cannot CONNECT to the database first. Each level must be explicitly granted - there is no automatic inheritance from higher levels. This is why the "minimal privilege" setup has multiple GRANT steps.

---

> **Concept: Object ownership**
> When a role creates an object (table, sequence, function), it becomes the owner. The owner has all privileges on that object by default and can grant or revoke privileges from others. Changing ownership requires SUPERUSER or being the current owner with CREATEROLE. Use ALTER TABLE ... OWNER TO to reassign ownership.

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

---

## Step 3 - Connect to PostgreSQL

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 4 - View the current privilege hierarchy

First, check what tables exist in stepup_store:

```sql
\dt
```

Expected output (yours will differ):

```
          List of relations
 Schema |    Name    | Type  |  Owner
--------+------------+-------+----------
 public | customers  | table | postgres
 public | orders     | table | postgres
 public | products   | table | postgres
```

---

## Step 5 - Test that app_user currently cannot connect

Open a second terminal and try to connect as app_user via TCP:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT 1;"
```

After Build 02, you should be prompted for a password. Enter `apppass123`. Even if the connection is accepted (CONNECT privilege), querying tables will fail.

Try:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

```sql
SELECT * FROM orders LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table orders
```

Return to the postgres psql session for the grant steps.

---

## Step 6 - Grant CONNECT on the database

```sql
GRANT CONNECT ON DATABASE stepup_store TO app_user;
```

This allows app_user to open a connection to the stepup_store database. Without this, the connection attempt fails at the database level.

Expected output:

```
GRANT
```

---

## Step 7 - Grant USAGE on the schema

```sql
GRANT USAGE ON SCHEMA public TO app_user;
```

USAGE on a schema allows the role to see objects within the schema and access them if they have the appropriate object-level privilege. Without USAGE on the schema, even if the role has SELECT on a table, they cannot reach it.

Expected output:

```
GRANT
```

---

## Step 8 - Grant SELECT, INSERT, UPDATE on specific tables

```sql
GRANT SELECT, INSERT, UPDATE ON TABLE orders TO app_user;
```

```sql
GRANT SELECT ON TABLE products TO app_user;
```

```sql
GRANT SELECT ON TABLE customers TO app_user;
```

The Pulse app needs to read products and customers, and needs full read-write on orders. It does NOT need DELETE or TRUNCATE.

Expected output for each:

```
GRANT
```

---

## Step 9 - Grant usage on sequences

If the orders table has a sequence for its primary key, the app needs USAGE on that sequence to insert new rows.

```sql
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_user;
```

This grants USAGE (needed to call nextval) and SELECT (needed to call currval) on all existing sequences in the schema.

Expected output:

```
GRANT
```

---

## Step 10 - Set up default privileges for future objects

The grants above only apply to objects that exist right now. If someone creates a new table tomorrow, app_user will not have access to it. Use ALTER DEFAULT PRIVILEGES to automatically grant privileges to future objects.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO readonly_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO app_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT USAGE, SELECT ON SEQUENCES TO app_user;
```

Expected output for each:

```
ALTER DEFAULT PRIVILEGES
```

---

> **Concept: ALTER DEFAULT PRIVILEGES scope**
> ALTER DEFAULT PRIVILEGES applies to objects created BY THE CURRENT ROLE going forward. If another superuser creates a table, the default privileges set by postgres do not apply. This is a common source of confusion. You can also set default privileges FOR another role: `ALTER DEFAULT PRIVILEGES FOR ROLE some_creator IN SCHEMA public GRANT SELECT ON TABLES TO app_user;`.

---

## Step 11 - Set up readonly_user with SELECT only

```sql
GRANT CONNECT ON DATABASE stepup_store TO readonly_user;
```

```sql
GRANT USAGE ON SCHEMA public TO readonly_user;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;
```

Expected output for each:

```
GRANT
```

---

## Step 12 - Verify privileges with \dp

```sql
\dp orders
```

This shows the Access Privileges for the orders table.

Expected output (yours will differ):

```
                                Access privileges
 Schema |  Name  | Type  |      Access privileges       | ...
--------+--------+-------+------------------------------+-----
 public | orders | table | postgres=arwdDxt/postgres    +|
        |        |       | app_user=arw/postgres        +|
        |        |       | readonly_user=r/postgres      |
```

The privilege letters mean: `r`=SELECT, `a`=INSERT, `w`=UPDATE, `d`=DELETE, `D`=TRUNCATE, `x`=REFERENCES, `t`=TRIGGER.

---

## Step 13 - Grant column-level privilege

Sometimes you want a role to see only specific columns. For example, restrict readonly_user from seeing the price column in products:

First revoke the table-level SELECT on products:

```sql
REVOKE SELECT ON TABLE products FROM readonly_user;
```

Then grant column-level SELECT for only specific columns:

```sql
GRANT SELECT (id, name, description, category) ON TABLE products TO readonly_user;
```

Expected output for each:

```
REVOKE
GRANT
```

---

## Step 14 - View column privileges

```sql
SELECT grantee, table_name, column_name, privilege_type
FROM information_schema.column_privileges
WHERE table_schema = 'public'
ORDER BY grantee, table_name, column_name;
```

Expected output (yours will differ):

```
   grantee    | table_name | column_name |  privilege_type
--------------+------------+-------------+------------------
 readonly_user| products   | category    | SELECT
 readonly_user| products   | description | SELECT
 readonly_user| products   | id          | SELECT
 readonly_user| products   | name        | SELECT
```

---

## Step 15 - Grant EXECUTE on functions

If the Pulse app calls any stored functions, grant execute permission:

```sql
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_user;
```

Expected output:

```
GRANT
```

---

## Step 16 - Test app_user access from a new terminal

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter password `apppass123`.

```sql
SELECT * FROM orders LIMIT 3;
```

This should now work.

```sql
DELETE FROM orders WHERE id = 1;
```

Expected output:

```
ERROR:  permission denied for table orders
```

app_user has INSERT and UPDATE but not DELETE. The privilege model is working.

```bash
\q
```

---

## Step 17 - Revoke a privilege

```sql
REVOKE INSERT ON TABLE orders FROM app_user;
```

Expected output:

```
REVOKE
```

Restore it:

```sql
GRANT INSERT ON TABLE orders TO app_user;
```

Expected output:

```
GRANT
```

---

## Step 18 - Exit

```bash
\q
```

```bash
exit
```

---

## Summary

Privilege setup for the Pulse app:

| Role | CONNECT | SCHEMA USAGE | Tables | Sequences |
|------|---------|--------------|--------|-----------|
| app_user | stepup_store | public | SELECT/INSERT/UPDATE on orders, customers, products | USAGE/SELECT |
| readonly_user | stepup_store | public | SELECT on all tables (limited columns on products) | none |
| admin_user | stepup_store | public | all (via CREATEDB/CREATEROLE) | all |

---

## Interview Discussion Points

1. **What is the minimum set of grants for a read-only app user?** - GRANT CONNECT ON DATABASE, GRANT USAGE ON SCHEMA, GRANT SELECT ON tables. Three separate grants at three different levels. Many beginners forget USAGE on the schema and wonder why SELECT still fails.

2. **What does GRANT ALL PRIVILEGES ON DATABASE do?** - It grants CREATE, CONNECT, and TEMPORARY on the database. It does NOT grant SELECT on tables. Database-level and table-level privileges are separate namespaces. This surprises many people.

3. **How do you audit which roles have which privileges?** - Use `information_schema.role_table_grants` for table privileges, `information_schema.role_column_grants` for column privileges, and `\dp tablename` in psql for a quick view. For database-level privileges, query `pg_database` and `has_database_privilege()`.

4. **What is the difference between GRANT ... TO role and GRANT role TO role?** - The first form grants an object privilege (SELECT, INSERT, etc.) to a role. The second form makes one role a member of another role (role inheritance). Role membership is how you implement group-based access: grant privileges to the group role, then add members.

5. **How do you remove all privileges from a role?** - Use `REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM rolename;` for table privileges. For database-level, `REVOKE ALL ON DATABASE dbname FROM rolename;`. You can also use `DROP OWNED BY rolename` which removes all privileges AND owned objects (use with caution).

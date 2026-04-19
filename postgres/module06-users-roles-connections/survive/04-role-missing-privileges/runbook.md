# Scenario 04 - Role Missing Privileges

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: The Pulse dashboard is showing database errors.
Orders cannot be loaded or saved. Customer data is unavailable.
Application logs show: ERROR: permission denied for table orders
```

---

## Key Concepts for Revision

- **REVOKE removes privileges** - A single REVOKE statement can strip critical privileges from an application role instantly. PostgreSQL does not confirm or warn - it just removes the privilege. This is why privilege changes should go through a change management process.

- **\dp shows current privileges** - The psql `\dp tablename` command shows the Access Control List (ACL) for a table. Use it to see exactly which roles have which privileges. The format shows `role=privileges/grantor`. An empty ACL for a role means no privileges.

- **Privilege audit query** - `information_schema.role_table_grants` shows all table privileges by role. This is better for scripting than `\dp`. Filter by `grantee` to see what a specific role has.

- **Minimum privileges for an app** - Most CRUD applications need SELECT, INSERT, UPDATE on their main tables, and USAGE + SELECT on sequences for auto-increment. DELETE is rarely needed if soft-delete patterns are used.

---

## Diagnostic Steps

### Step 1 - Confirm the error

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter `apppass123`.

```sql
SELECT * FROM orders LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table orders
```

The error is clear. app_user lost SELECT on orders.

### Step 2 - Connect as postgres to investigate

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Check privileges on the orders table

```sql
\dp orders
```

Expected output (yours will differ):

```
                                  Access privileges
 Schema |  Name  | Type  |    Access privileges    | ...
--------+--------+-------+-------------------------+----
 public | orders | table | postgres=arwdDxt/postgres|
        |        |       |                         |
```

app_user does not appear in the ACL - its privileges were revoked.

### Step 4 - Query information_schema for a full view

```sql
SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
AND grantee IN ('app_user', 'readonly_user')
ORDER BY grantee, table_name, privilege_type;
```

This shows which tables each role has access to. Missing entries for app_user on orders and customers confirm the problem.

---

## Resolution

### Step 1 - Re-grant SELECT, INSERT, UPDATE on orders to app_user

```sql
GRANT SELECT, INSERT, UPDATE ON TABLE orders TO app_user;
```

Expected output:

```
GRANT
```

### Step 2 - Re-grant SELECT on customers to app_user

```sql
GRANT SELECT ON TABLE customers TO app_user;
```

Expected output:

```
GRANT
```

### Step 3 - Verify the grants

```sql
\dp orders
```

Expected output (yours will differ):

```
                                    Access privileges
 Schema |  Name  | Type  |         Access privileges          | ...
--------+--------+-------+------------------------------------+----
 public | orders | table | postgres=arwdDxt/postgres          +|
        |        |       | app_user=arw/postgres              |
```

`arw` = SELECT (r), INSERT (a), UPDATE (w). Correct.

### Step 4 - Test as app_user

```bash
\q
```

```bash
exit
```

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Enter `apppass123`.

```sql
SELECT count(*) FROM orders;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

### Step 5 - Verify the Pulse dashboard recovers

Open your browser and go to `http://NODE1:8080`. Confirm the dashboard returns to normal.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user has SELECT on orders
- app_user has INSERT on orders
- app_user has UPDATE on orders
- app_user has SELECT on customers

---

## Interview Discussion Points

1. **How do you audit what privileges a role has across all tables in a schema?** - Query `information_schema.role_table_grants WHERE grantee = 'rolename' AND table_schema = 'public'`. For column-level grants, use `information_schema.role_column_grants`. For schema and database level, query `pg_namespace.nspacl` and `pg_database.datacl`.

2. **What is the difference between revoking a privilege from a role vs. using DROP OWNED BY?** - REVOKE removes a specific privilege from a specific role. DROP OWNED BY rolename removes ALL privileges granted to the role AND drops all objects owned by the role. DROP OWNED BY is destructive and irreversible without backups. Use it only when decommissioning a role.

3. **If you revoke a privilege from a group role, do members lose it automatically?** - Yes. Privileges inherited through group membership are revoked immediately when the group role loses the privilege. Members that had the privilege only through inheritance will see permission denied errors on the next query.

4. **What is WITH GRANT OPTION and why is it dangerous?** - `GRANT SELECT ON TABLE orders TO app_user WITH GRANT OPTION` allows app_user to grant SELECT on orders to other roles. If app_user is compromised, the attacker can spread access. Avoid WITH GRANT OPTION for application roles.

5. **How do you prevent a developer from accidentally revoking application privileges?** - Use a change management process for all GRANT/REVOKE statements in production. Also consider: only the DBA role should have the GRANT OPTION on critical tables, developers should not have superuser or the ability to GRANT in production, and use pg_audit or pgaudit extension to log all DDL changes including GRANT/REVOKE.

# Scenario 02 - Privilege Escalation

**Severity:** CRITICAL
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Security scan detected an unexpected SUPERUSER role
'rogue_admin' in the stepup_store database.
This role was not in last week's access review.
Investigate and revoke all unauthorized privileges.
```

---

## Key Concepts for Revision

- **Superuser bypass** - A role with SUPERUSER bypasses every access check: RLS, table privileges, schema privileges, and function SECURITY DEFINER boundaries. There is no privilege a superuser cannot exercise. A rogue superuser account is the most severe security breach possible in a PostgreSQL cluster.

- **Privilege audit procedure** - After detecting an unauthorized role, the audit process is: (1) identify the role and its privileges, (2) check what the role accessed using pg_stat_statements or audit logs, (3) revoke all privileges and memberships, (4) drop the role, (5) identify how the role was created (who ran CREATE ROLE with SUPERUSER?), (6) determine the root cause (stolen credentials, misconfigured pg_hba.conf, application vulnerability).

- **Revoking cascaded privileges** - If the rogue role was granted to other roles (`GRANT rogue_admin TO someuser`), those grants must also be revoked. `DROP OWNED BY rogue_admin` removes objects the role owns but does not remove memberships in other roles. Memberships must be revoked explicitly.

- **Audit trail for privilege changes** - If pgAudit or log_statement = 'ddl' was active, the CREATE ROLE statement will appear in the log with the timestamp and client IP. This tells you when it happened and from where. If audit logging was not active, you cannot determine retrospectively when the role was created.

---

## Diagnostic Steps

### Step 1 - List all superuser roles

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT rolname, rolsuper, rolcanlogin, rolcreaterole
FROM pg_roles
WHERE rolsuper = true
ORDER BY rolname;
```

Expected output (yours will differ):

```
  rolname    | rolsuper | rolcanlogin | rolcreaterole
-------------+----------+-------------+---------------
 postgres    | t        | t           | t
 rogue_admin | t        | t           | f
(2 rows)
```

Only `postgres` should be a superuser. `rogue_admin` is unauthorized.

### Step 2 - Check all privileges held by the rogue role

```sql
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee = 'rogue_admin'
ORDER BY table_schema, table_name;
```

Expected output (yours will differ):

```
   grantee   | table_schema | table_name | privilege_type
-------------+--------------+------------+----------------
 rogue_admin | public       | audit_log  | SELECT
 rogue_admin | public       | customers  | SELECT
 rogue_admin | public       | orders     | SELECT
(3 rows)
```

### Step 3 - Check role memberships involving the rogue role

```sql
SELECT r.rolname AS group_role, m.rolname AS member
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
WHERE r.rolname = 'rogue_admin' OR m.rolname = 'rogue_admin';
```

Expected output (yours will differ):

```
 group_role  |    member
-------------+--------------
 app_user    | rogue_admin
(1 row)
```

`rogue_admin` is a member of `app_user` - it inherits all app_user privileges in addition to its own superuser status.

---

## Resolution

### Step 1 - Revoke all memberships from the rogue role

```sql
REVOKE app_user FROM rogue_admin;
```

Expected output:

```
REVOKE ROLE
```

### Step 2 - Revoke all object-level privileges

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA public FROM rogue_admin;
```

Expected output:

```
REVOKE
```

### Step 3 - Drop any objects owned by the rogue role

```sql
DROP OWNED BY rogue_admin;
```

This removes any objects the role owns (tables, sequences, functions) and also removes any grants where `rogue_admin` is the grantee. It is safe to run even if the role owns nothing.

Expected output:

```
DROP OWNED
```

### Step 4 - Drop the rogue role

```sql
DROP ROLE rogue_admin;
```

Expected output:

```
DROP ROLE
```

### Step 5 - Confirm only expected superusers remain

```sql
SELECT rolname FROM pg_roles WHERE rolsuper = true;
```

Expected output:

```
 rolname
----------
 postgres
(1 row)
```

### Step 6 - Check the log file to identify when and how the role was created

```sql
\q
```

```bash
exit
```

```bash
grep -i 'rogue_admin' /opt/pgsql/log/postgresql-*.log
```

Expected output (yours will differ):

```
... LOG:  statement: CREATE ROLE rogue_admin WITH LOGIN SUPERUSER PASSWORD '...';
```

The log entry shows the timestamp and client connection details. Use this to trace the source.

### Step 7 - Return to postgres user and verify the fix

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT rolname FROM pg_roles WHERE rolsuper = true;
```

Expected output:

```
 rolname
----------
 postgres
(1 row)
```

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
- rogue_admin role does not exist
- Only postgres has SUPERUSER
- PostgreSQL accepts normal connections
- app_user role still exists

---

## Interview Discussion Points

1. **How would you detect a privilege escalation attack in real time rather than after the fact?** - Enable pgAudit with `pgaudit.log = 'role'` to capture all role-management statements. Set up alerting on log lines matching `CREATE ROLE.*SUPERUSER`. Many organizations also run scheduled queries against `pg_roles WHERE rolsuper = true` and alert on any new entries not in an approved list. PostgreSQL does not have built-in real-time alerting, so this requires external tooling (Datadog, pgBadger, custom scripts).

2. **What is the difference between DROP ROLE and DROP OWNED BY?** - `DROP ROLE` removes the role itself but fails if the role owns any objects or has any privileges. You must clean up dependencies first. `DROP OWNED BY` removes all objects owned by the role and revokes all privileges where the role is the grantee. Running `DROP OWNED BY rogue_admin` followed by `DROP ROLE rogue_admin` is the correct cleanup sequence for any unwanted role.

3. **If a rogue superuser created tables or functions, do those objects get removed by DROP OWNED BY?** - Yes. `DROP OWNED BY rolename` removes every object owned by that role in the current database (tables, views, sequences, functions, types, schemas). It does not affect objects in other databases. If the rogue role created objects in multiple databases, you must run `DROP OWNED BY` in each database separately.

4. **How should you handle this if the rogue role is currently connected to the database?** - First, terminate the active session: `SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'rogue_admin';`. Then proceed with the privilege revocation and role drop. If you drop the role without terminating the session, the session continues until the client disconnects. The terminated session will get a "server closed the connection unexpectedly" error.

5. **What controls prevent a CREATEROLE user from creating a SUPERUSER role?** - A role with CREATEROLE cannot create a role with more privileges than itself. Specifically, CREATEROLE cannot create SUPERUSER roles, REPLICATION roles, or roles with BYPASSRLS. Only an existing superuser can create another superuser. However, a CREATEROLE user can still create roles with CREATEDB, CREATEROLE, and other dangerous attributes. The best practice is to never grant CREATEROLE to application roles and to restrict it to dedicated DBA accounts.

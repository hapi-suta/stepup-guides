# Scenario 09 - Public Schema Exposure

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Security audit found that the public schema
allows any authenticated user to create objects.
Suspicious objects were found: connection_log, temp_staging,
and a shadowing version() function.
The public schema must be locked down immediately.
```

---

## Key Concepts for Revision

- **PUBLIC is a pseudo-role for all users** - In PostgreSQL, `PUBLIC` represents every authenticated role. Granting to PUBLIC grants to everyone, including future roles. This is different from granting to a specific role.

- **The public schema was writable by default before PostgreSQL 15** - In versions before 15, `CREATE` on the `public` schema was granted to `PUBLIC` by default. Any authenticated user could create tables, functions, and other objects. PostgreSQL 15 changed this default, but upgraded clusters may retain the old permissions.

- **CREATE privilege on a schema is dangerous** - If a user can create objects in a schema that other users search, they can plant trap tables that shadow real ones or functions that intercept system function calls. This is the foundation of search_path injection attacks.

- **Audit before revoking** - Before revoking CREATE, audit what exists in the public schema. Remove any unauthorized objects first, then lock down permissions.

---

## Diagnostic Steps

### Step 1 - Check public schema permissions

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT nspacl FROM pg_namespace WHERE nspname = 'public';
```

Expected output (yours will differ):

```
                nspacl
--------------------------------------
 {postgres=UC/postgres,=UC/postgres}
(1 row)
```

The `=UC/postgres` entry means PUBLIC (the empty string before `=`) has both USAGE (U) and CREATE (C) privileges. The `C` is the problem.

### Step 2 - List all objects in the public schema

```sql
SELECT c.relname, c.relkind,
       CASE c.relkind
         WHEN 'r' THEN 'table'
         WHEN 'S' THEN 'sequence'
         WHEN 'v' THEN 'view'
         WHEN 'i' THEN 'index'
       END AS type,
       r.rolname AS owner
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r ON r.oid = c.relowner
WHERE n.nspname = 'public'
  AND c.relkind IN ('r', 'S', 'v')
ORDER BY c.relkind, c.relname;
```

Look for suspicious objects that you did not create, such as `connection_log`, `temp_staging`, or functions with names that match system functions.

### Step 3 - Check for suspicious functions in public schema

```sql
SELECT p.proname, r.rolname AS owner, p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r ON r.oid = p.proowner
WHERE n.nspname = 'public'
ORDER BY p.proname;
```

Expected output (yours will differ):

```
 proname | owner    | security_definer
---------+----------+------------------
 version | postgres | f
(1 row)
```

A `version()` function exists in the public schema. This shadows `pg_catalog.version()` and could be used to intercept calls.

### Step 4 - Check the trap table contents

```sql
SELECT * FROM public.connection_log;
```

Expected output (yours will differ):

```
 id | captured_user |       captured_at        | client_addr
----+---------------+--------------------------+-------------
  1 | postgres      | 2026-04-19 10:00:00+00   |
(1 row)
```

The trap table has been capturing connection info.

---

## Resolution

### Step 1 - Drop the trap objects

Remove the unauthorized objects first.

```sql
DROP FUNCTION IF EXISTS public.version();
```

Expected output:

```
DROP FUNCTION
```

```sql
DROP TABLE IF EXISTS public.connection_log CASCADE;
```

Expected output:

```
DROP TABLE
```

```sql
DROP TABLE IF EXISTS public.temp_staging CASCADE;
```

Expected output:

```
DROP TABLE
```

### Step 2 - Revoke CREATE on public schema from PUBLIC

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Expected output:

```
REVOKE
```

This prevents any authenticated user from creating objects in the public schema.

### Step 3 - Verify the permissions

```sql
SELECT nspacl FROM pg_namespace WHERE nspname = 'public';
```

Expected output (yours will differ):

```
              nspacl
----------------------------------
 {postgres=UC/postgres,=U/postgres}
(1 row)
```

Now PUBLIC only has USAGE (U), not CREATE (C). Users can use objects in the public schema but cannot create new ones.

### Step 4 - Verify no trap objects remain

```sql
SELECT p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('version', 'current_user', 'session_user');
```

Expected output:

```
 proname
---------
(0 rows)
```

No shadowing functions remain.

```sql
SELECT relname FROM pg_class
WHERE relnamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public')
  AND relname IN ('connection_log', 'temp_staging');
```

Expected output:

```
 relname
---------
(0 rows)
```

No trap tables remain.

### Step 5 - Test that unprivileged users cannot create objects

```sql
SET ROLE app_user;
```

```sql
CREATE TABLE test_lockdown (id int);
```

Expected output:

```
ERROR:  permission denied for schema public
```

The lockdown is working.

```sql
RESET ROLE;
```

### Step 6 - Exit

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
- PUBLIC does not have CREATE on public schema
- No trap tables (connection_log, temp_staging) exist
- No shadowing functions (version) in public schema
- Unprivileged users cannot create objects in public schema

---

## Interview Discussion Points

1. **Why was the public schema writable by default in older PostgreSQL versions?** - Historical convenience. PostgreSQL was designed when multi-user security was less of a concern. Having a shared writable schema made it easy for users to create tables without schema management overhead. PostgreSQL 15 finally changed this default because the security risk outweighed the convenience.

2. **What is the attack surface when PUBLIC has CREATE on the public schema?** - Any authenticated user can: (a) create tables that shadow real tables in other schemas via search_path, (b) create functions that shadow system functions, (c) create trigger functions or event triggers if they have the privilege, (d) create tables to stage exfiltrated data. The public schema becomes an attack staging area.

3. **Should you drop the public schema entirely?** - Some teams do this. `DROP SCHEMA public;` removes the attack surface entirely. All application tables go into named schemas. This is clean but requires all queries to be schema-qualified or search_path to be configured. Most teams keep the public schema but revoke CREATE from PUBLIC.

4. **How do you audit what changes were made in the public schema?** - Use `pgaudit` extension to log DDL operations per schema. Without pgaudit, check `pg_class` for recently created objects: `SELECT relname, relowner::regrole FROM pg_class WHERE relnamespace = 'public'::regnamespace ORDER BY oid DESC LIMIT 20;`. Objects with higher OIDs were created more recently.

5. **What is the difference between USAGE and CREATE privileges on a schema?** - `USAGE` allows a role to access objects within the schema (look up tables, call functions). `CREATE` allows a role to create new objects in the schema. You need USAGE to use existing objects and CREATE to make new ones. Revoking CREATE while keeping USAGE means users can still read/write existing tables but cannot add new ones.

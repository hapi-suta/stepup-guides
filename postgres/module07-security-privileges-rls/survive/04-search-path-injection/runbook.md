# Scenario 04 - search_path Injection

**Severity:** CRITICAL
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application returning unexpected username values.
SELECT current_user is returning 'hacked_postgres'
instead of the actual user. Queries using current_user()
in RLS policies may be returning wrong results.
```

---

## Key Concepts for Revision

- **search_path injection exploits name resolution** - When PostgreSQL resolves an unqualified function call like `current_user()`, it searches schemas in the order defined by `search_path`. If the `public` schema appears before `pg_catalog`, an attacker who can create functions in `public` can shadow built-in functions. The malicious function runs instead of the real one.

- **SECURITY DEFINER amplifies the attack** - A function marked `SECURITY DEFINER` runs with the privileges of the function owner, not the caller. If the malicious function is owned by a superuser (or created by one unknowingly), it executes with superuser privileges regardless of who calls it.

- **pg_catalog should always resolve first** - The `pg_catalog` schema contains all built-in functions. If `pg_catalog` is not explicitly listed in `search_path`, PostgreSQL implicitly searches it first. But if `public` is explicitly listed before `pg_catalog`, the public schema wins. Always ensure `pg_catalog` comes first or is not displaced.

- **The public schema is writable by default** - In PostgreSQL versions before 15, any authenticated user can create objects in the `public` schema by default. This is the root cause of search_path injection attacks. PostgreSQL 15+ changed this default, but upgraded clusters may still have the old permissive setting.

---

## Diagnostic Steps

### Step 1 - Reproduce the issue

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT current_user;
```

Expected output:

```
   current_user
-----------------
 hacked_postgres
(1 row)
```

The result has a `hacked_` prefix. This is not the real `current_user` - a shadowing function is intercepting the call.

### Step 2 - Check what functions exist in the public schema

```sql
SELECT n.nspname, p.proname, p.prosecdef, pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('current_user', 'session_user', 'current_role');
```

Expected output (yours will differ):

```
 nspname |   proname    | prosecdef |            pg_get_functiondef
---------+--------------+-----------+---------------------------------------------
 public  | current_user | t         | CREATE OR REPLACE FUNCTION public...
(1 row)
```

A function named `current_user` exists in the `public` schema with `prosecdef = t` (SECURITY DEFINER). This is the malicious function.

### Step 3 - Call the real function explicitly

```sql
SELECT pg_catalog.current_user();
```

Expected output:

```
 current_user
--------------
 postgres
(1 row)
```

Using the fully-qualified `pg_catalog.current_user()` bypasses the shadow and returns the real value. This confirms the issue is a search_path problem, not a system compromise.

### Step 4 - Check the current search_path

```sql
SHOW search_path;
```

Expected output (yours will differ):

```
   search_path
-----------------
 "$user", public
(1 row)
```

The `public` schema is in the search_path. Since there is no schema named `postgres`, PostgreSQL skips `"$user"` and searches `public` next - before `pg_catalog` can be explicitly checked.

---

## Resolution

### Step 1 - Drop the malicious function

```sql
DROP FUNCTION IF EXISTS public.current_user();
```

Expected output:

```
DROP FUNCTION
```

### Step 2 - Verify the real function works again

```sql
SELECT current_user;
```

Expected output:

```
 current_user
--------------
 postgres
(1 row)
```

No more `hacked_` prefix.

### Step 3 - Check for other suspicious functions in public schema

```sql
SELECT p.proname, p.prosecdef, r.rolname AS owner
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
JOIN pg_roles r ON r.oid = p.proowner
WHERE n.nspname = 'public'
ORDER BY p.proname;
```

Review the results carefully. Any function with `prosecdef = t` (SECURITY DEFINER) in the public schema is suspicious unless you created it intentionally.

### Step 4 - Lock down the search_path for the database

Set the search_path to exclude `public` or ensure `pg_catalog` is listed explicitly first.

```sql
ALTER DATABASE stepup_store SET search_path = 'public', 'pg_catalog';
```

Expected output:

```
ALTER DATABASE
```

This ensures `pg_catalog` is always searched. Since `pg_catalog` is implicitly searched first when not explicitly listed, this is a belt-and-suspenders approach that makes the order explicit.

### Step 5 - Revoke CREATE on public schema from PUBLIC

This prevents unprivileged users from creating objects in the public schema.

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
```

Expected output:

```
REVOKE
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
- Malicious public.current_user() function is removed
- current_user returns correct value without hacked_ prefix
- pg_catalog.current_user() works correctly
- PostgreSQL accepts normal connections

---

## Interview Discussion Points

1. **How does search_path injection work in practice?** - An attacker needs CREATE privileges on a schema that appears in the victim's search_path (typically `public`). They create a function with the same name as a built-in (like `current_user`). When the victim calls the unqualified function name, PostgreSQL resolves it to the attacker's function first. If the function is SECURITY DEFINER and owned by a superuser, the attacker's code runs with superuser privileges.

2. **Why is SECURITY DEFINER dangerous in this context?** - A SECURITY DEFINER function runs as its owner, not its caller. If a superuser creates a function in the public schema with SECURITY DEFINER, any user who calls that function executes code with superuser privileges. In a search_path injection, the malicious function in `public` replaces a system function, so every query that calls the system function now runs attacker-controlled code as the function's owner.

3. **What changed in PostgreSQL 15 regarding the public schema?** - PostgreSQL 15 removed the default `CREATE` privilege on the `public` schema for the `PUBLIC` pseudo-role. In older versions, any authenticated user could create objects in `public`. This change significantly reduces the attack surface for search_path injection. However, databases upgraded from older versions retain the old permissions unless explicitly revoked.

4. **What is the best practice for setting search_path in production?** - Set explicit search_path per role or per database. Never rely on the default. Either exclude `public` entirely or ensure `pg_catalog` is explicitly first. For application roles, set search_path to only the schemas they need: `ALTER ROLE app_user SET search_path = 'app_schema', 'pg_catalog';`. Revoke CREATE on public from PUBLIC.

5. **How would you detect search_path injection in a running system?** - Monitor for functions in the `public` schema that share names with `pg_catalog` functions: `SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND EXISTS (SELECT 1 FROM pg_proc p2 JOIN pg_namespace n2 ON n2.oid = p2.pronamespace WHERE n2.nspname = 'pg_catalog' AND p2.proname = p.proname);`. Any results are suspicious. Run this check periodically.

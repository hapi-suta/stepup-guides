# Scenario 07 - Schema search_path Misconfigured

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application queries are returning wrong data.
SELECT * FROM orders shows a single row with product
'FAKE_PRODUCT' instead of real order data.
The application has not been redeployed.
```

---

## Key Concepts for Revision

- **search_path controls name resolution** - When you write `SELECT * FROM orders`, PostgreSQL looks through the schemas listed in `search_path` in order and uses the first match. If a decoy or wrong schema appears first, your queries silently hit the wrong table. This is one of the most common causes of "the data looks wrong but the query hasn't changed."

- **search_path can be set at multiple levels** - It can be set globally in `postgresql.conf`, per-database with `ALTER DATABASE ... SET`, per-role with `ALTER ROLE ... SET`, per-role-in-database with `ALTER ROLE ... IN DATABASE ... SET`, or per-session with `SET search_path`. The most specific wins. Always check per-role-in-database first when a single role is affected.

- **pg_db_role_setting stores per-role/per-database settings** - The `pg_db_role_setting` catalog stores settings that were configured with `ALTER ROLE ... IN DATABASE ... SET`. This is the first place to check when one role behaves differently from others.

- **Schema-qualify critical queries** - Using `public.orders` instead of just `orders` prevents search_path attacks. In high-security environments, explicitly set search_path and never include untrusted schemas.

---

## Diagnostic Steps

### Step 1 - Reproduce the problem as app_user

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
SHOW search_path;
```

Expected output (yours will differ):

```
 search_path
--------------
 decoy, pg_catalog
(1 row)
```

The search_path points to `decoy` instead of `public`. That is why the wrong table is being read.

### Step 2 - Confirm the wrong table is being hit

```sql
SELECT * FROM orders LIMIT 3;
```

Expected output (yours will differ):

```
  id  | tenant_id |   product    | amount
------+-----------+--------------+--------
 9999 | DECOY     | FAKE_PRODUCT |   0.00
(1 row)
```

This is the decoy table, not the real orders table.

### Step 3 - Check where the search_path was set

```sql
RESET ROLE;
```

```sql
SELECT r.rolname, d.datname, rs.setconfig
FROM pg_db_role_setting rs
JOIN pg_roles r ON r.oid = rs.setrole
JOIN pg_database d ON d.oid = rs.setdatabase
WHERE r.rolname = 'app_user';
```

Expected output (yours will differ):

```
 rolname  |   datname    |           setconfig
----------+--------------+-------------------------------
 app_user | stepup_store | {search_path=decoy,pg_catalog}
(1 row)
```

The `search_path` was overridden at the role-in-database level. This setting takes priority over the global or database-level default.

---

## Resolution

### Step 1 - Fix the search_path for app_user

Reset the search_path to include the correct schema. The `public` schema is where the real tables live.

```sql
ALTER ROLE app_user IN DATABASE stepup_store SET search_path = 'public', 'pg_catalog';
```

Expected output:

```
ALTER ROLE
```

The `public` flag means PostgreSQL searches the public schema first.
The `pg_catalog` flag ensures built-in functions like `now()` and `current_user` are always found.

### Step 2 - Verify the setting was applied

```sql
SELECT r.rolname, d.datname, rs.setconfig
FROM pg_db_role_setting rs
JOIN pg_roles r ON r.oid = rs.setrole
JOIN pg_database d ON d.oid = rs.setdatabase
WHERE r.rolname = 'app_user';
```

Expected output (yours will differ):

```
 rolname  |   datname    |             setconfig
----------+--------------+-----------------------------------
 app_user | stepup_store | {search_path=public,pg_catalog}
(1 row)
```

### Step 3 - Test as app_user in a new session

The search_path change applies to new sessions, not the current one. Reconnect to test.

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SET ROLE app_user;
```

```sql
SHOW search_path;
```

Expected output:

```
   search_path
-----------------
 public, pg_catalog
(1 row)
```

```sql
SELECT id, tenant_id, product FROM orders LIMIT 3;
```

You should now see real order data, not the decoy rows.

### Step 4 - Clean up the decoy schema (optional)

```sql
RESET ROLE;
```

```sql
DROP SCHEMA decoy CASCADE;
```

Expected output:

```
NOTICE:  drop cascades to table decoy.orders
DROP SCHEMA
```

### Step 5 - Exit

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
- app_user search_path includes public
- app_user can query the real orders table
- Queries do not return decoy data

---

## Interview Discussion Points

1. **How does PostgreSQL resolve unqualified table names?** - PostgreSQL walks through the schemas listed in `search_path` left to right. The first schema that contains a table with the matching name wins. If no match is found in any listed schema, the query fails with "relation does not exist." This is why the order of schemas in search_path matters - putting the wrong schema first can silently redirect queries.

2. **What are the different levels where search_path can be set, and which takes priority?** - From highest to lowest priority: (1) session-level `SET search_path`, (2) `ALTER ROLE ... IN DATABASE ... SET`, (3) `ALTER ROLE ... SET`, (4) `ALTER DATABASE ... SET`, (5) `postgresql.conf`. The most specific setting wins. A per-role-in-database setting will override a global one. This layering means you must check all levels during diagnosis.

3. **Why is it dangerous to include untrusted schemas in search_path?** - If an attacker can create objects in a schema that appears in search_path before the legitimate schema, they can shadow real tables or functions. For example, a malicious `current_user()` function in the `public` schema can intercept calls meant for `pg_catalog.current_user()`. This is called a search_path injection attack.

4. **What is the `"$user"` special value in search_path?** - By default, PostgreSQL's search_path includes `"$user", public`. The `"$user"` token expands to the current role name. If role `alice` runs a query, PostgreSQL looks for tables in schema `alice` first, then `public`. This allows per-user private schemas without changing search_path per role.

5. **How would you prevent this issue in production?** - Set explicit search_path per role or per database, never rely on the default. Remove `CREATE` privilege on the `public` schema from PUBLIC (done by default in PostgreSQL 15+). Use schema-qualified names in application queries for critical tables. Monitor `pg_db_role_setting` for unexpected changes.

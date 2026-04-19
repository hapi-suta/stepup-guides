# Use 03 - Build a Multi-Tenant System with RLS

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 30 minutes

---

## Objective

Apply RLS to the stepup_store tables to create a working multi-tenant isolation system. You will use the session variable pattern (app.tenant_id) so a single application role can serve multiple tenants with row-level data isolation.

---

## Prerequisites

Build 04 (Row-Level Security) must be complete. The `orders` table should have RLS enabled and a `tenant_id` column.

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

## Step 4 - Add tenant_id to additional tables

The customers table also needs tenant isolation. First check the current structure:

```sql
\d customers
```

Add tenant_id if it does not exist:

```sql
ALTER TABLE customers ADD COLUMN IF NOT EXISTS tenant_id TEXT NOT NULL DEFAULT 'default';
```

---

## Step 5 - Seed tenant data in customers

```sql
UPDATE customers SET tenant_id = 'tenant_alpha' WHERE id % 2 = 0;
```

```sql
UPDATE customers SET tenant_id = 'tenant_beta' WHERE id % 2 = 1;
```

---

## Step 6 - Enable RLS on customers

```sql
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
```

---

## Step 7 - Create the multi-tenant RLS policy using session variables

This policy works for the `app_user` role (the shared application role):

```sql
CREATE POLICY multi_tenant_customers_select
ON customers
FOR SELECT
TO app_user
USING (tenant_id = current_setting('app.tenant_id', true));
```

```sql
CREATE POLICY multi_tenant_customers_insert
ON customers
FOR INSERT
TO app_user
WITH CHECK (tenant_id = current_setting('app.tenant_id', true));
```

```sql
CREATE POLICY multi_tenant_customers_update
ON customers
FOR UPDATE
TO app_user
USING (tenant_id = current_setting('app.tenant_id', true))
WITH CHECK (tenant_id = current_setting('app.tenant_id', true));
```

```sql
CREATE POLICY multi_tenant_customers_delete
ON customers
FOR DELETE
TO app_user
USING (tenant_id = current_setting('app.tenant_id', true));
```

---

## Step 8 - Grant table access to app_user

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE customers TO app_user;
```

---

## Step 9 - Create a helper function to set tenant context

In a real application, the connection pool calls this function on every new connection:

```sql
CREATE OR REPLACE FUNCTION public.set_tenant(p_tenant_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    IF p_tenant_id IS NULL OR p_tenant_id = '' THEN
        RAISE EXCEPTION 'tenant_id cannot be empty';
    END IF;
    PERFORM set_config('app.tenant_id', p_tenant_id, true);
END;
$$;
```

`set_config('app.tenant_id', value, true)` sets the variable for the current transaction only (the third parameter `true` means transaction-local). This is safer than `SET` which persists for the whole session.

Grant execute to app_user:

```sql
GRANT EXECUTE ON FUNCTION public.set_tenant(TEXT) TO app_user;
```

---

## Step 10 - Test the multi-tenant isolation as app_user

Exit psql and connect as app_user:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U app_user
```

Start a transaction and set the tenant context:

```sql
BEGIN;
```

```sql
SELECT public.set_tenant('tenant_alpha');
```

Query customers - you should only see tenant_alpha rows:

```sql
SELECT id, tenant_id FROM customers LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id
----+--------------
  2 | tenant_alpha
  4 | tenant_alpha
  6 | tenant_alpha
(3 rows)
```

---

## Step 11 - Try to insert a row with the wrong tenant_id

```sql
INSERT INTO customers (name, email, tenant_id)
VALUES ('Hacker', 'hack@evil.com', 'tenant_beta');
```

Expected output:

```
ERROR:  new row violates row-level security policy for table "customers"
```

The WITH CHECK clause prevents inserting cross-tenant data.

---

## Step 12 - Commit and start a new transaction for tenant_beta

```sql
COMMIT;
```

```sql
BEGIN;
```

```sql
SELECT public.set_tenant('tenant_beta');
```

```sql
SELECT id, tenant_id FROM customers LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id
----+-------------
  1 | tenant_beta
  3 | tenant_beta
(2 rows)
```

```sql
COMMIT;
```

---

## Step 13 - Test without setting tenant context

```sql
SELECT id, tenant_id FROM customers LIMIT 5;
```

Expected output:

```
 id | tenant_id
----+-----------
(0 rows)
```

Without a tenant context, `current_setting('app.tenant_id', true)` returns NULL. No rows match `tenant_id = NULL`, so the query returns empty. This is the fail-closed behavior.

---

## Step 14 - Exit app_user session

```sql
\q
```

---

## Step 15 - Connect back as postgres and audit the policies

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

List all RLS policies across all tables:

```sql
SELECT schemaname, tablename, policyname, cmd, roles
FROM pg_policies
ORDER BY tablename, policyname;
```

Expected output (yours will differ):

```
 schemaname | tablename |           policyname           | cmd | roles
------------+-----------+--------------------------------+-----+-----------
 public     | customers | multi_tenant_customers_delete  | DELETE | {app_user}
 public     | customers | multi_tenant_customers_insert  | INSERT | {app_user}
 public     | customers | multi_tenant_customers_select  | SELECT | {app_user}
 public     | customers | multi_tenant_customers_update  | UPDATE | {app_user}
 public     | orders    | tenant_insert_policy           | INSERT | {=}
 ...
```

---

## Step 16 - Check which tables have RLS enabled

```sql
SELECT schemaname, tablename, rowsecurity, forcerowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;
```

Expected output (yours will differ):

```
 schemaname | tablename  | rowsecurity | forcerowsecurity
------------+------------+-------------+-----------------
 public     | audit_log  | f           | f
 public     | customers  | t           | f
 public     | orders     | t           | f
 public     | products   | f           | f
(4 rows)
```

`rowsecurity = t` means RLS is enabled. `forcerowsecurity = f` means the table owner can still bypass RLS.

---

## Step 17 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Validation Questions

Answer these before moving to the next exercise:

1. Why use `set_config(name, value, true)` with `true` instead of `SET app.tenant_id = ...`?
2. What happens if two tenants have the same tenant_id value in the database - is there any additional safeguard?
3. How would you implement a "super-tenant" admin that can see all rows across all tenants?
4. If the application crashes mid-transaction after calling `set_tenant`, what happens to the tenant context?

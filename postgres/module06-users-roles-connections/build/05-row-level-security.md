# Build 05 - Row Level Security

**Module:** 06 - Users, Roles & Connections
**Node:** NODE1 only
**Time:** 30 minutes

---

## What You Will Learn

- What Row Level Security (RLS) is and when to use it
- How to enable RLS on a table
- How to write policies for SELECT, INSERT, UPDATE, and DELETE
- How to create a multi-tenant setup where app_user sees only their own rows
- How to test and debug RLS policies

---

> **Concept: What RLS does**
> Row Level Security adds a per-row filter to every query. When RLS is enabled on a table, PostgreSQL evaluates the policy expression for each row and returns (or allows modification of) only the rows where the expression is true. This happens AFTER column-level privileges but BEFORE results are returned to the client. The application does not need to add WHERE clauses - the filtering is enforced at the database level.

---

> **Concept: Policy types**
> Each policy has a command type: SELECT, INSERT, UPDATE, DELETE, or ALL. A SELECT policy filters which rows the role can read. An INSERT policy filters which rows the role can add. You can have multiple policies on the same table - PostgreSQL combines them with OR (permissive policies) or AND (restrictive policies). If no policy matches and RLS is enabled, the row is invisible (deny by default).

---

> **Concept: Superusers and BYPASSRLS bypass all policies**
> A role with SUPERUSER or BYPASSRLS attribute ignores all RLS policies. This is intentional for administrative access. The postgres role has BYPASSRLS by default. If you want to test your policies as a regular user, you must connect as a non-superuser role.

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

## Step 4 - Create a multi-tenant orders table for this exercise

The stepup_store already has an orders table. We will add a tenant_id column to simulate multi-tenancy.

First, check the current structure:

```sql
\d orders
```

Expected output (yours will differ):

```
                         Table "public.orders"
   Column   |            Type             | Nullable |      Default
------------+-----------------------------+----------+--------------------
 id         | integer                     | not null | nextval(...)
 customer_id| integer                     |          |
 product_id | integer                     |          |
 quantity   | integer                     |          |
 total      | numeric(10,2)               |          |
 created_at | timestamp without time zone |          | now()
```

Add a tenant_id column:

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tenant_id text DEFAULT current_user;
```

This adds `tenant_id` with a default of the current database role. In a real multi-tenant app, the application would set this explicitly.

Expected output:

```
ALTER TABLE
```

---

## Step 5 - Insert test data for two tenants

```sql
INSERT INTO orders (customer_id, product_id, quantity, total, tenant_id)
VALUES (1, 1, 2, 49.98, 'tenant_alpha');
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total, tenant_id)
VALUES (2, 2, 1, 29.99, 'tenant_beta');
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total, tenant_id)
VALUES (3, 3, 5, 124.95, 'tenant_alpha');
```

Expected output for each:

```
INSERT 0 1
```

---

## Step 6 - Enable Row Level Security on the orders table

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
```

At this point, RLS is enabled but there are NO policies. In this state, non-superuser roles see zero rows (default deny). Only roles with BYPASSRLS (like postgres) see everything.

Expected output:

```
ALTER TABLE
```

---

## Step 7 - Verify that app_user now sees nothing

In a second terminal, connect as app_user:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

```sql
SELECT count(*) FROM orders;
```

Expected output:

```
 count
-------
     0
(1 row)
```

app_user has SELECT privilege on orders, but RLS is blocking all rows because there are no policies yet.

Return to the postgres terminal.

---

## Step 8 - Create a tenant isolation policy

This policy allows each user to see only rows where tenant_id matches the current_user:

```sql
CREATE POLICY tenant_isolation ON orders
  FOR ALL
  TO PUBLIC
  USING (tenant_id = current_user);
```

- `FOR ALL` - applies to SELECT, INSERT, UPDATE, and DELETE
- `TO PUBLIC` - applies to all roles (except superusers)
- `USING (tenant_id = current_user)` - the filter expression. Only rows where tenant_id equals the connected role name are visible.

Expected output:

```
CREATE POLICY
```

---

## Step 9 - Test the policy as app_user

In the app_user terminal:

```sql
SELECT id, tenant_id, total FROM orders;
```

Expected output:

```
 id | tenant_id | total
----+-----------+-------
(0 rows)
```

app_user sees nothing because no rows have `tenant_id = 'app_user'`. The policy works, but we need a smarter approach for the Pulse app.

---

## Step 10 - Create a dedicated tenant role for app_user

Drop the current broad policy and create a more practical one for the Pulse app. The app connects as app_user but serves data for multiple tenants using application-level session variables.

```sql
DROP POLICY tenant_isolation ON orders;
```

Create an application-variable based policy:

```sql
CREATE POLICY app_tenant_isolation ON orders
  FOR ALL
  TO app_user
  USING (tenant_id = current_setting('app.tenant_id', true));
```

- `current_setting('app.tenant_id', true)` - reads a session-level variable set by the application
- The second argument `true` means "return NULL if the setting does not exist" (instead of raising an error)

Expected output for each:

```
DROP POLICY
CREATE POLICY
```

---

## Step 11 - Test with a session variable

In the app_user terminal, set the tenant variable and query:

```sql
SET LOCAL app.tenant_id = 'tenant_alpha';
```

```sql
SELECT id, tenant_id, total FROM orders;
```

Expected output (yours will differ):

```
 id | tenant_id    | total
----+--------------+--------
  1 | tenant_alpha |  49.98
  3 | tenant_alpha | 124.95
(2 rows)
```

Now switch tenant:

```sql
SET LOCAL app.tenant_id = 'tenant_beta';
```

```sql
SELECT id, tenant_id, total FROM orders;
```

Expected output:

```
 id | tenant_id   | total
----+-------------+-------
  2 | tenant_beta | 29.99
(1 row)
```

The same role sees different data depending on the session variable. This is the standard multi-tenant RLS pattern.

---

## Step 12 - Create separate INSERT and SELECT policies

Sometimes you need different rules for reading vs. writing. Drop the combined policy and create separate ones:

```sql
DROP POLICY app_tenant_isolation ON orders;
```

```sql
CREATE POLICY orders_select ON orders
  FOR SELECT
  TO app_user
  USING (tenant_id = current_setting('app.tenant_id', true));
```

```sql
CREATE POLICY orders_insert ON orders
  FOR INSERT
  TO app_user
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true));
```

For INSERT policies, `WITH CHECK` is used instead of `USING`. `USING` filters which rows are visible. `WITH CHECK` filters which rows can be written. A row that fails `WITH CHECK` causes the INSERT to fail with an error.

Expected output for each:

```
CREATE POLICY
```

---

## Step 13 - Test the INSERT policy

In the app_user terminal:

```sql
SET LOCAL app.tenant_id = 'tenant_alpha';
```

Try to insert a row for a different tenant (this should fail):

```sql
INSERT INTO orders (customer_id, product_id, quantity, total, tenant_id)
VALUES (1, 1, 1, 9.99, 'tenant_beta');
```

Expected output:

```
ERROR:  new row violates row-level security policy for table "orders"
```

Insert for the correct tenant (this should succeed):

```sql
INSERT INTO orders (customer_id, product_id, quantity, total, tenant_id)
VALUES (1, 1, 1, 9.99, 'tenant_alpha');
```

Expected output:

```
INSERT 0 1
```

---

## Step 14 - View all policies on a table

Back in the postgres terminal:

```sql
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
 schemaname | tablename |   policyname   | permissive | roles     | cmd    | ...
------------+-----------+----------------+------------+-----------+--------+----
 public     | orders    | orders_select  | PERMISSIVE | {app_user}| SELECT |
 public     | orders    | orders_insert  | PERMISSIVE | {app_user}| INSERT |
```

---

## Step 15 - Force RLS even for the table owner

By default, the table owner bypasses RLS. To make policies apply to the owner too:

```sql
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

Now even the postgres role (which owns the table) will be filtered by policies. This is useful for auditing. Reverse it:

```sql
ALTER TABLE orders NO FORCE ROW LEVEL SECURITY;
```

Expected output for each:

```
ALTER TABLE
```

---

## Step 16 - Disable RLS (for cleanup)

To turn off RLS entirely:

```sql
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
```

This leaves the policies defined but disables enforcement. Useful for maintenance or debugging.

Expected output:

```
ALTER TABLE
```

Re-enable it for the module to stay consistent:

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
```

---

## Step 17 - Exit

```bash
\q
```

```bash
exit
```

---

## Summary

RLS flow for the Pulse app:

1. Application connects as `app_user`
2. Before first query, sets `SET LOCAL app.tenant_id = 'tenant_alpha'`
3. All queries automatically filtered by tenant_id
4. No WHERE clause needed in application SQL
5. Inserting for another tenant fails at the database level

---

## Interview Discussion Points

1. **What is the difference between USING and WITH CHECK in a policy?** - `USING` is the visibility filter. It determines which existing rows the role can see or modify. `WITH CHECK` is the write filter. It determines which new rows can be inserted or what updated rows can look like. For INSERT, only WITH CHECK applies. For UPDATE, both apply - USING controls which rows can be updated, WITH CHECK controls what the updated row must look like.

2. **What happens when multiple permissive policies exist?** - PostgreSQL combines permissive policies with OR. A row is visible if it satisfies ANY permissive policy for that role and command. Restrictive policies (created with `AS RESTRICTIVE`) are combined with AND across all restrictive policies. A row must satisfy ALL restrictive policies plus at least one permissive policy to be visible.

3. **How does RLS interact with views?** - A view's security depends on who owns the view. If a view is defined by a superuser, the view bypasses RLS on the underlying tables. If the view is defined by a regular role, RLS on the underlying tables applies based on the current user. Use `SECURITY DEFINER` on functions carefully for the same reason.

4. **Can RLS policies use functions?** - Yes. Policy expressions are regular SQL expressions and can call functions. However, functions called in RLS policies should be `SECURITY INVOKER` (the default) so they run with the rights of the calling role, not the function definer. Calling a `SECURITY DEFINER` function from an RLS policy can bypass the intent of the policy.

5. **How do you test that your RLS policies are correct?** - Connect as the target role and run queries. Use `SET ROLE rolename;` within a superuser session to impersonate a role without disconnecting. Use `EXPLAIN (SECURITY_BARRIER)` on views to see if RLS filters are being pushed down correctly. Check `pg_policies` to see all defined policies.

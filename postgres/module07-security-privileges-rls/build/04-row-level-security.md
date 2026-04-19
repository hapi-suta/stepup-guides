# Build 04 - Row-Level Security

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 35 minutes

---

## What You Will Learn

- How to enable RLS on a table
- How to create SELECT, INSERT, UPDATE, and DELETE policies
- How to use current_user and session variables (SET app.tenant_id) in policies
- How to test that different users see different rows
- What BYPASSRLS means and when to use it

---

> **Concept: How RLS Works**
> Row-Level Security (RLS) adds a filter to every query on a table. When RLS is enabled on a table, every SQL statement that touches that table is silently rewritten to include the policy conditions. For SELECT, the policy acts like an invisible WHERE clause. For INSERT, the policy acts like a check constraint. For UPDATE and DELETE, both a visibility check (USING clause) and a validity check (WITH CHECK clause) apply. If no policy applies to the current role's operation, the default behavior is to deny all rows (fail-closed). The table owner and superusers bypass RLS by default unless you configure FORCE ROW LEVEL SECURITY.

---

> **Concept: Session Variables for Multi-Tenant RLS**
> A common pattern for multi-tenant applications is to store the current tenant's ID in a session-level variable using `SET app.tenant_id = '123'`. Policies then call `current_setting('app.tenant_id')` to read this value and filter rows accordingly. The application sets this variable immediately after connecting and before running any query. This avoids creating a separate database role per tenant (which would not scale) while still isolating each tenant's data at the row level.

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

Expected output (yours will differ):

```
psql (16.3)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - Check the orders table structure

```sql
\d orders
```

Expected output (yours will differ):

```
                              Table "public.orders"
     Column      |            Type             | Collation | Nullable | Default
-----------------+-----------------------------+-----------+----------+--------
 id              | integer                     |           | not null | ...
 customer_id     | integer                     |           |          |
 status          | text                        |           |          |
 total_amount    | numeric(10,2)               |           |          |
 created_at      | timestamptz                 |           |          |
```

---

## Step 5 - Add a tenant_id column for multi-tenant RLS

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tenant_id TEXT DEFAULT 'default';
```

In a real application this column would exist from the start. We add it here to the existing table to demonstrate the RLS pattern.

Expected output:

```
ALTER TABLE
```

---

## Step 6 - Seed some rows with different tenant IDs

```sql
UPDATE orders SET tenant_id = 'tenant_alpha' WHERE id % 2 = 0;
```

```sql
UPDATE orders SET tenant_id = 'tenant_beta' WHERE id % 2 = 1;
```

Expected output for each:

```
UPDATE N
```

---

## Step 7 - Create tenant roles

```sql
CREATE ROLE tenant_alpha WITH LOGIN PASSWORD 'alphapass123';
```

```sql
CREATE ROLE tenant_beta WITH LOGIN PASSWORD 'betapass123';
```

Expected output for each:

```
CREATE ROLE
```

---

## Step 8 - Grant SELECT on orders to both tenant roles

```sql
GRANT SELECT ON TABLE orders TO tenant_alpha;
```

```sql
GRANT SELECT ON TABLE orders TO tenant_beta;
```

Expected output for each:

```
GRANT
```

---

## Step 9 - Enable Row-Level Security on orders

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
```

Enabling RLS does not create any policies yet. At this point, no role except the table owner and superusers can see any rows. Regular roles see zero rows.

Expected output:

```
ALTER TABLE
```

---

## Step 10 - Verify no rows are visible to tenant_alpha before adding a policy

Exit psql and connect as tenant_alpha:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U tenant_alpha
```

```sql
SELECT COUNT(*) FROM orders;
```

Expected output:

```
 count
-------
     0
(1 row)
```

Even though `tenant_alpha` has SELECT on orders, RLS is now blocking all rows because no policy exists yet.

---

## Step 11 - Exit tenant_alpha session

```sql
\q
```

---

## Step 12 - Connect back as postgres

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 13 - Create a SELECT policy for tenant isolation

```sql
CREATE POLICY tenant_select_policy
ON orders
FOR SELECT
TO PUBLIC
USING (tenant_id = current_user);
```

This policy says: for SELECT statements, only show rows where `tenant_id` equals the name of the current role. The `TO PUBLIC` means this policy applies to all roles. The `USING` clause is the filter condition - it acts as an invisible WHERE clause.

Expected output:

```
CREATE POLICY
```

---

## Step 14 - Test that tenant_alpha sees only their rows

Exit and connect as tenant_alpha:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U tenant_alpha
```

```sql
SELECT id, tenant_id, status FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id    | status
----+--------------+--------
  2 | tenant_alpha | paid
  4 | tenant_alpha | pending
  6 | tenant_alpha | shipped
(3 rows)
```

Only rows with `tenant_id = 'tenant_alpha'` are visible. Rows belonging to tenant_beta are invisible.

---

## Step 15 - Test that tenant_beta sees only their rows

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U tenant_beta
```

```sql
SELECT id, tenant_id, status FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id   | status
----+-------------+---------
  1 | tenant_beta | paid
  3 | tenant_beta | pending
(2 rows)
```

---

## Step 16 - Exit tenant_beta and return to postgres

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 17 - Create INSERT and UPDATE policies

Grant INSERT and UPDATE to tenant_alpha:

```sql
GRANT INSERT, UPDATE ON TABLE orders TO tenant_alpha;
```

Create an INSERT policy - tenants can only insert rows for their own tenant_id:

```sql
CREATE POLICY tenant_insert_policy
ON orders
FOR INSERT
TO PUBLIC
WITH CHECK (tenant_id = current_user);
```

The `WITH CHECK` clause validates new rows. If `tenant_alpha` tries to INSERT a row with `tenant_id = 'tenant_beta'`, the insert will fail.

Expected output:

```
CREATE POLICY
```

Create an UPDATE policy - tenants can only update their own rows and cannot change tenant_id to someone else's:

```sql
CREATE POLICY tenant_update_policy
ON orders
FOR UPDATE
TO PUBLIC
USING (tenant_id = current_user)
WITH CHECK (tenant_id = current_user);
```

The `USING` clause determines which rows are visible for update. The `WITH CHECK` clause validates the resulting row after the update.

Expected output:

```
CREATE POLICY
```

---

## Step 18 - Use session variables in RLS policies

A more scalable pattern uses a session variable instead of current_user (useful when your app connects as a shared role):

```sql
CREATE POLICY tenant_session_policy
ON orders
FOR SELECT
TO app_user
USING (tenant_id = current_setting('app.tenant_id', true));
```

The `current_setting('app.tenant_id', true)` reads a session variable. The second argument `true` means return NULL instead of raising an error if the variable is not set. If the variable is NULL, no rows match and the user sees nothing - a safe fail-closed behavior.

Expected output:

```
CREATE POLICY
```

---

## Step 19 - Test the session variable policy

Grant SELECT on orders to app_user (if not already granted):

```sql
GRANT SELECT ON TABLE orders TO app_user;
```

Exit and connect as app_user:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U app_user
```

Set the session variable before querying:

```sql
SET app.tenant_id = 'tenant_alpha';
```

```sql
SELECT id, tenant_id, status FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id    | status
----+--------------+--------
  2 | tenant_alpha | paid
  4 | tenant_alpha | pending
(2 rows)
```

Now switch tenant context in the same session:

```sql
SET app.tenant_id = 'tenant_beta';
```

```sql
SELECT id, tenant_id FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id
----+-----------
  1 | tenant_beta
  3 | tenant_beta
(2 rows)
```

---

## Step 20 - Exit app_user session

```sql
\q
```

---

## Step 21 - Connect back as postgres and demonstrate BYPASSRLS

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

The postgres superuser bypasses RLS by default:

```sql
SELECT COUNT(*) FROM orders;
```

Expected output (yours will differ):

```
 count
-------
    10
(1 row)
```

Postgres sees all rows. To demonstrate BYPASSRLS explicitly:

```sql
CREATE ROLE dba_ops WITH LOGIN BYPASSRLS PASSWORD 'dbapass123';
```

```sql
GRANT SELECT ON TABLE orders TO dba_ops;
```

`BYPASSRLS` is a role attribute that makes the role skip all RLS policies on all tables. Use this only for trusted operational roles that need to see all data for maintenance and auditing.

Expected output:

```
CREATE ROLE
GRANT
```

---

## Step 22 - List all policies on the orders table

```sql
SELECT polname, polcmd, polroles, polqual, polwithcheck
FROM pg_policies
WHERE tablename = 'orders';
```

This system view shows all RLS policies with their commands and conditions.

Expected output (yours will differ):

```
         polname          | polcmd |   polroles    |           polqual            |         polwithcheck
--------------------------+--------+---------------+------------------------------+-----------------------------
 tenant_select_policy     | r      | {=}           | (tenant_id = (current_user)) |
 tenant_insert_policy     | a      | {=}           |                              | (tenant_id = (current_user))
 tenant_update_policy     | w      | {=}           | (tenant_id = (current_user)) | (tenant_id = (current_user))
 tenant_session_policy    | r      | {app_user}    | (tenant_id = current_setting...) |
```

---

## Step 23 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Summary

| RLS Concept | Clause | Purpose |
|-------------|--------|---------|
| ENABLE ROW LEVEL SECURITY | ALTER TABLE | Activates RLS; without policies, all rows are hidden |
| USING | Policy | Filters which existing rows are visible |
| WITH CHECK | Policy | Validates new or updated rows |
| current_user | Policy | Matches role name to column value |
| current_setting() | Policy | Reads session variable set by application |
| BYPASSRLS | Role attribute | Skips all policies; for trusted admin roles only |

---

## Interview Discussion Points

1. **What is the difference between USING and WITH CHECK in an RLS policy?** - `USING` filters rows that are already in the table. For SELECT, it acts as an invisible WHERE clause hiding non-matching rows. For UPDATE and DELETE, it determines which rows the role can operate on. `WITH CHECK` validates the state of a row after modification. For INSERT, it ensures the new row satisfies the policy condition. For UPDATE, it ensures the row's new values still satisfy the condition. You need both for updates - USING to select which rows can be changed, WITH CHECK to ensure the change does not violate the policy.

2. **What happens if no policy matches for a role that has table SELECT privilege?** - By default, RLS is fail-closed: if no policy applies to the current role and operation, zero rows are returned (for SELECT) or the operation fails (for INSERT/UPDATE/DELETE). This is the safe default. You can add a PERMISSIVE policy that always returns TRUE (allowing all rows) for specific roles if you want an explicit bypass rather than using BYPASSRLS.

3. **Can RLS policies slow down queries significantly?** - Yes, if written poorly. Every query against an RLS-enabled table is rewritten to include the policy condition. If the policy condition references a column without an index, every query will do a full table scan. The fix is to index the column used in the USING clause (such as tenant_id) and ensure the policy condition is deterministic and cheap to evaluate. Subqueries and function calls in policies can add overhead; `current_user` and `current_setting()` are very fast.

4. **How do you force RLS to apply even to the table owner?** - Use `ALTER TABLE orders FORCE ROW LEVEL SECURITY`. By default, the table owner bypasses RLS. With FORCE ROW LEVEL SECURITY, the table owner is subject to policies like any other role. Superusers still bypass RLS regardless. This is useful when you want a strict multi-tenant boundary and do not want even the owning application role to accidentally read cross-tenant data.

5. **Explain the security risk of using `current_setting('app.tenant_id')` in an RLS policy.** - The risk is that the session variable can be set to any value by the connecting client. If your application allows users to set `app.tenant_id` themselves, they could set it to another tenant's ID and access that tenant's data. The correct pattern is: the application layer sets `app.tenant_id` immediately after connecting, in a transaction or function that the user cannot influence. Some teams use a security-definer function to set this variable so the user can never change it directly.

# Scenario 08 - RLS Blocking Application

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Products page is empty. The application shows
0 products but the database has data. No errors in
the application log - queries succeed but return 0 rows.
This started after a security team change.
```

---

## Key Concepts for Revision

- **RLS without policies blocks all rows** - When you enable Row Level Security with `ALTER TABLE ... ENABLE ROW LEVEL SECURITY`, all rows become invisible to non-owner roles unless a policy explicitly grants access. This is the "deny by default" model. If you enable RLS and forget to create a policy, every query from non-superuser roles returns 0 rows with no error.

- **Table owners bypass RLS by default** - The table owner (usually `postgres`) can still see all rows even with RLS enabled. This is why the DBA sees data but the application does not. Use `ALTER TABLE ... FORCE ROW LEVEL SECURITY` to make the owner subject to policies too.

- **\d+ shows RLS status** - Running `\d+ tablename` in psql shows "Row Level Security" at the bottom. It says "enabled" or "disabled." If enabled, check for policies.

- **pg_policies catalog** - The `pg_policies` view lists all active policies. If this view returns 0 rows for a table with RLS enabled, no non-owner role can see any data.

---

## Diagnostic Steps

### Step 1 - Confirm the problem as app_user

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
SELECT count(*) FROM products;
```

Expected output:

```
 count
-------
     0
(1 row)
```

Zero rows returned even though data exists.

### Step 2 - Check as the table owner

```sql
RESET ROLE;
```

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):

```
 count
-------
    10
(1 row)
```

The table owner can see the rows. This confirms the issue is permission-related, not data loss.

### Step 3 - Check if RLS is enabled

```sql
SELECT relname, relrowsecurity, relforcerowsecurity
FROM pg_class
WHERE relname = 'products';
```

Expected output:

```
  relname  | relrowsecurity | relforcerowsecurity
-----------+----------------+---------------------
 products  | t              | f
(1 row)
```

`relrowsecurity = t` confirms RLS is enabled.

### Step 4 - Check for policies

```sql
SELECT policyname, cmd, roles, qual
FROM pg_policies
WHERE tablename = 'products';
```

Expected output:

```
 policyname | cmd | roles | qual
------------+-----+-------+------
(0 rows)
```

No policies exist. RLS is enabled but there are no policies granting access, so all non-owner roles see 0 rows.

---

## Resolution

### Step 1 - Create a SELECT policy for app_user

Since products are not tenant-specific, create a simple policy that lets app_user read all rows.

```sql
CREATE POLICY app_user_select_products
ON products
FOR SELECT
TO app_user
USING (true);
```

Expected output:

```
CREATE POLICY
```

The `USING (true)` clause means all rows are visible to `app_user` for SELECT operations.
The `TO app_user` clause limits this policy to the `app_user` role only.

### Step 2 - Create INSERT and UPDATE policies too

The application also needs to insert and update products.

```sql
CREATE POLICY app_user_insert_products
ON products
FOR INSERT
TO app_user
WITH CHECK (true);
```

Expected output:

```
CREATE POLICY
```

```sql
CREATE POLICY app_user_update_products
ON products
FOR UPDATE
TO app_user
USING (true)
WITH CHECK (true);
```

Expected output:

```
CREATE POLICY
```

The `WITH CHECK` clause controls what values can be written. `true` means no restriction.

### Step 3 - Verify policies are in place

```sql
SELECT policyname, cmd, roles
FROM pg_policies
WHERE tablename = 'products'
ORDER BY policyname;
```

Expected output:

```
          policyname          |  cmd   |   roles
-----------------------------+--------+------------
 app_user_insert_products    | INSERT | {app_user}
 app_user_select_products    | SELECT | {app_user}
 app_user_update_products    | UPDATE | {app_user}
(3 rows)
```

### Step 4 - Test as app_user

```sql
SET ROLE app_user;
```

```sql
SELECT count(*) FROM products;
```

Expected output (yours will differ):

```
 count
-------
    10
(1 row)
```

Rows are visible again.

### Step 5 - Exit

```sql
RESET ROLE;
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
- RLS is still enabled on products table
- At least one policy exists for app_user
- app_user can see product rows

---

## Interview Discussion Points

1. **Why does RLS return 0 rows instead of an error when no policy exists?** - This is by design. RLS uses a "deny by default" model. The absence of a policy means "no rows match," not "access denied." The query succeeds with an empty result set. This is a common source of confusion because the application sees no error - just empty data. It looks like the table is empty, not that access is blocked.

2. **What is the difference between ENABLE ROW LEVEL SECURITY and FORCE ROW LEVEL SECURITY?** - `ENABLE` activates RLS for all roles except the table owner and superusers. `FORCE` makes even the table owner subject to policies. Without `FORCE`, the table owner always sees all rows. Use `FORCE` when you want universal enforcement, such as when the application connects as the table owner.

3. **How do USING and WITH CHECK differ in a policy?** - `USING` controls which existing rows are visible (applies to SELECT, UPDATE's WHERE, DELETE's WHERE). `WITH CHECK` controls which new row values are allowed (applies to INSERT and UPDATE's SET values). A policy with `USING (true) WITH CHECK (true)` allows all reads and all writes. A policy with `USING (tenant_id = current_user) WITH CHECK (tenant_id = current_user)` enforces tenant isolation for both reads and writes.

4. **Can you have RLS on some roles but not others for the same table?** - Yes. Policies are targeted to specific roles using the `TO` clause. If you create a policy `TO app_user`, only `app_user` is affected by that policy. Other non-owner roles still see 0 rows unless they have their own policy. You can also use `TO PUBLIC` to apply a policy to all roles.

5. **How would you audit which tables have RLS enabled but no policies?** - Query: `SELECT c.relname FROM pg_class c WHERE c.relrowsecurity = true AND NOT EXISTS (SELECT 1 FROM pg_policies p WHERE p.tablename = c.relname);`. This returns tables with RLS on but zero policies - meaning all non-owner roles see nothing. Run this as a periodic security check.

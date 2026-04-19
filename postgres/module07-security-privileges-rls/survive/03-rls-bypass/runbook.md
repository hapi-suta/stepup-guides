# Scenario 03 - RLS Policy Gap (Data Leakage)

**Severity:** CRITICAL
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Security audit found that tenant_beta can see
tenant_alpha orders in stepup_store. RLS is enabled
on the orders table but data isolation is broken.
Customers are reporting seeing each other's orders.
```

---

## Key Concepts for Revision

- **PERMISSIVE vs RESTRICTIVE policies** - PostgreSQL RLS has two policy types: PERMISSIVE (the default) and RESTRICTIVE. Multiple PERMISSIVE policies are combined with OR logic - a row is visible if ANY permissive policy allows it. Multiple RESTRICTIVE policies are combined with AND logic - a row must pass ALL restrictive policies. This means a single `USING (true)` permissive policy makes all rows visible to the affected roles, even if another permissive policy exists. An attacker who can create a new policy (requires superuser or table owner) can bypass all existing isolation.

- **pg_policies view** - The `pg_policies` view shows all active RLS policies. When isolation breaks, always inspect this view first. Look for policies with `USING (true)` or any condition that is unconditionally true for all roles.

- **Testing RLS as different users** - In psql, you can temporarily act as another user with `SET SESSION AUTHORIZATION rolename`. This switches your role for the session without disconnecting. Superusers can switch to any role this way. Use this to quickly test what a specific role can and cannot see.

- **Policy audit as a routine** - RLS policies should be reviewed whenever someone reports data isolation issues, after any schema or security changes, and as part of regular access reviews. A policy that worked correctly can be broken by adding a new policy without understanding the OR logic.

---

## Diagnostic Steps

### Step 1 - Check what policies exist on the orders table

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE tablename = 'orders'
ORDER BY policyname;
```

Expected output (yours will differ):

```
       policyname        | cmd | roles |            qual            | with_check
-------------------------+-----+-------+----------------------------+------------
 rls_gap_policy          | r   | {=}   | true                       |
 tenant_insert_policy    | a   | {=}   |                            | (tenant_id = current_user)
 tenant_select_policy    | r   | {=}   | (tenant_id = current_user) |
 tenant_update_policy    | w   | {=}   | (tenant_id = current_user) | (tenant_id = current_user)
(4 rows)
```

The `rls_gap_policy` has `qual = true`. This means it passes ALL rows to ALL roles. Because policies merge with OR logic, this single policy overrides the tenant isolation policies.

### Step 2 - Reproduce the leakage

```sql
SET SESSION AUTHORIZATION tenant_beta;
```

```sql
SELECT id, tenant_id FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id
----+--------------
  1 | tenant_beta
  2 | tenant_alpha
  3 | tenant_beta
  4 | tenant_alpha
(4 rows)
```

Both tenant_alpha and tenant_beta rows are visible to tenant_beta. Confirmed leakage.

### Step 3 - Return to postgres

```sql
RESET SESSION AUTHORIZATION;
```

---

## Resolution

### Step 1 - Drop the rogue permissive policy

```sql
DROP POLICY rls_gap_policy ON orders;
```

Expected output:

```
DROP POLICY
```

### Step 2 - Verify the remaining policies are correct

```sql
SELECT policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'orders'
ORDER BY policyname;
```

Expected output (yours will differ):

```
       policyname        | cmd |            qual
-------------------------+-----+----------------------------
 tenant_insert_policy    | a   |
 tenant_select_policy    | r   | (tenant_id = current_user)
 tenant_update_policy    | w   | (tenant_id = current_user)
(3 rows)
```

No more `USING (true)` entries.

### Step 3 - Verify isolation is restored

```sql
SET SESSION AUTHORIZATION tenant_beta;
```

```sql
SELECT id, tenant_id FROM orders LIMIT 5;
```

Expected output (yours will differ):

```
 id | tenant_id
----+------------
  1 | tenant_beta
  3 | tenant_beta
(2 rows)
```

Only tenant_beta rows are visible.

### Step 4 - Return to postgres

```sql
RESET SESSION AUTHORIZATION;
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
- RLS is enabled on orders table
- Permissive gap policy (rls_gap_policy) is removed
- tenant_beta cannot see tenant_alpha rows
- tenant_alpha can still see their own rows

---

## Interview Discussion Points

1. **Explain how PERMISSIVE policy OR logic creates security gaps.** - PostgreSQL evaluates all PERMISSIVE policies for the current role and operation and combines them with OR. If any single policy evaluates to true for a row, the row is visible. A policy with `USING (true)` always evaluates to true for every row, making all rows visible regardless of other policies. This is why adding a "catch-all" policy to test something, then forgetting to remove it, can silently break all tenant isolation in a production system.

2. **What is the difference between PERMISSIVE and RESTRICTIVE policies and when would you use RESTRICTIVE?** - PERMISSIVE policies grant access (combined with OR). RESTRICTIVE policies restrict access (combined with AND). Use RESTRICTIVE when you want to apply an additional constraint that must always hold, even when permissive policies grant access. For example: a RESTRICTIVE policy that prevents reading deleted rows would apply regardless of which PERMISSIVE policy granted row visibility. In most simple tenant isolation scenarios, PERMISSIVE policies are sufficient and RESTRICTIVE is not needed.

3. **If a developer needs to create a temporary debug policy to investigate an issue, what is the safest way to do it?** - Create the policy in a transaction: `BEGIN; CREATE POLICY debug_policy ON orders USING (true); -- run investigation queries here; ROLLBACK;`. The policy is visible to your session but rolled back automatically if you forget to remove it. Never create a temporary policy in production without a plan to remove it immediately. Also use `FOR SELECT TO debug_role` to limit the policy to a specific role rather than PUBLIC.

4. **How would you detect this type of gap in your monitoring?** - Run a periodic query against `pg_policies` that flags any policy with `qual = 'true'` or `qual IS NULL` (meaning no filter). Add this to your security monitoring: `SELECT tablename, policyname, qual FROM pg_policies WHERE qual = 'true' OR with_check = 'true';`. Alert on any results because unconditionally-true policies are almost always misconfiguration.

5. **What is FORCE ROW LEVEL SECURITY and would it have helped here?** - `ALTER TABLE orders FORCE ROW LEVEL SECURITY` makes the table owner subject to RLS policies, not just regular roles. It would NOT have helped here because the problem was a permissive policy that exposed all rows to all roles including tenant_beta. FORCE RLS only affects the table owner and does not change how permissive policies merge. The fix was to remove the overly-permissive policy, not to add FORCE RLS.

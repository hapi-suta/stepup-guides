# Exercise 06 - Write RLS Policies

**Module:** 06 - Users, Roles & Connections
**Time:** 25 minutes

---

## Scenario

The stepup_store has an orders table. You need to write RLS policies that:

1. Allow each customer to see only their own orders (when connecting as `customer_role`)
2. Allow the support team to see all orders but not modify them
3. Allow the app to insert orders only for the currently active tenant (using a session variable)
4. Allow no user to delete orders (hard delete is prohibited)

---

## Setup

```bash
ssh -i your-key.pem ec2-user@NODE1
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Task 1 - Create roles for this exercise

```sql
CREATE ROLE customer_role WITH LOGIN PASSWORD 'cust123';
```

```sql
CREATE ROLE support_role WITH LOGIN PASSWORD 'support123';
```

Grant basic access to customer_role:

```sql
GRANT CONNECT ON DATABASE stepup_store TO customer_role;
```

```sql
GRANT USAGE ON SCHEMA public TO customer_role;
```

```sql
GRANT SELECT ON TABLE orders TO customer_role;
```

Grant basic access to support_role:

```sql
GRANT CONNECT ON DATABASE stepup_store TO support_role;
```

```sql
GRANT USAGE ON SCHEMA public TO support_role;
```

```sql
GRANT SELECT ON TABLE orders TO support_role;
```

---

## Task 2 - Add a customer_id column to orders (if not present)

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS customer_login text DEFAULT current_user;
```

Insert test rows for each "customer":

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount, customer_login)
VALUES (1, 1, 2, 49.98, 'customer_role');
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount, customer_login)
VALUES (2, 2, 1, 29.99, 'other_customer');
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount, customer_login)
VALUES (3, 3, 3, 89.97, 'customer_role');
```

---

## Task 3 - Enable RLS

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
```

---

## Task 4 - Write Policy 1: customer sees only their own orders

```sql
CREATE POLICY customer_own_orders ON orders
  FOR SELECT
  TO customer_role
  USING (customer_login = current_user);
```

Test it in a second terminal:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U customer_role -d stepup_store
```

```sql
SELECT order_id, customer_login, total_amount FROM orders;
```

Expected output (yours will differ):

```
 order_id | customer_login | total_amount
----------+----------------+--------------
  1 | customer_role  | 49.98
  3 | customer_role  | 89.97
(2 rows)
```

---

## Task 5 - Write Policy 2: support sees all orders, read-only

```sql
CREATE POLICY support_read_all ON orders
  FOR SELECT
  TO support_role
  USING (true);
```

`USING (true)` means every row matches the policy - no filtering. Combined with the fact that support_role only has SELECT privilege (no INSERT/UPDATE/DELETE), this gives read-all access.

Test in a third terminal:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U support_role -d stepup_store
```

```sql
SELECT order_id, customer_login, total_amount FROM orders;
```

Expected output - all rows visible:

```
 order_id | customer_login | total_amount
----------+----------------+--------------
  1 | customer_role  | 49.98
  2 | other_customer | 29.99
  3 | customer_role  | 89.97
(3 rows)
```

---

## Task 6 - Write Policy 3: app can INSERT only for the current tenant

Back in the postgres terminal, app_user already has INSERT on orders. Add an RLS policy to restrict inserts to the active tenant:

```sql
CREATE POLICY app_insert_own_tenant ON orders
  FOR INSERT
  TO app_user
  WITH CHECK (tenant_id = current_setting('app.tenant_id', true));
```

Test in a fourth terminal as app_user:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

```sql
SET LOCAL app.tenant_id = 'tenant_alpha';
```

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount, tenant_id)
VALUES (1, 1, 1, 9.99, 'tenant_alpha');
```

This should succeed.

```sql
INSERT INTO orders (customer_id, product_id, quantity, total_amount, tenant_id)
VALUES (1, 1, 1, 9.99, 'tenant_beta');
```

Expected output:

```
ERROR:  new row violates row-level security policy for table "orders"
```

---

## Task 7 - Write Policy 4: prohibit DELETE for all roles

```sql
CREATE POLICY no_delete ON orders
  AS RESTRICTIVE
  FOR DELETE
  TO PUBLIC
  USING (false);
```

`USING (false)` means no row ever satisfies the policy, so DELETE is blocked for everyone. `AS RESTRICTIVE` means this policy is ANDed with other policies - it cannot be overridden by permissive policies.

Test as app_user:

```sql
DELETE FROM orders WHERE order_id = 1;
```

Expected output:

```
ERROR:  new row violates row-level security policy for table "orders"
```

Even postgres (which owns the table) would be blocked IF you ran `ALTER TABLE orders FORCE ROW LEVEL SECURITY`. Without FORCE, the owner bypasses RLS.

---

## Task 8 - List all policies

Back in the postgres terminal:

```sql
SELECT tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies
WHERE tablename = 'orders'
ORDER BY policyname;
```

Expected output (yours will differ):

```
 tablename |       policyname       | permissive |    roles      | cmd    | ...
-----------+------------------------+------------+---------------+--------+----
 orders    | app_insert_own_tenant  | PERMISSIVE | {app_user}    | INSERT |
 orders    | customer_own_orders    | PERMISSIVE | {customer_role}| SELECT|
 orders    | no_delete              | RESTRICTIVE| {=}           | DELETE |
 orders    | support_read_all       | PERMISSIVE | {support_role}| SELECT|
```

---

## Task 9 - Clean up

Disable RLS on the orders table:

```sql
ALTER TABLE orders DISABLE ROW LEVEL SECURITY;
```

Drop the policies:

```sql
DROP POLICY customer_own_orders ON orders;
```

```sql
DROP POLICY support_read_all ON orders;
```

```sql
DROP POLICY app_insert_own_tenant ON orders;
```

```sql
DROP POLICY no_delete ON orders;
```

Drop the exercise roles:

```sql
DROP ROLE customer_role;
```

```sql
DROP ROLE support_role;
```

```bash
\q
```

```bash
exit
```

---

## Review Questions

1. If a role has no matching RLS policy for a SELECT, what does it see? (Zero rows, all rows, or an error?)
2. What is the difference between `AS PERMISSIVE` and `AS RESTRICTIVE` in a CREATE POLICY statement?
3. If you want the postgres role to be filtered by RLS (not bypass it), what command do you run?

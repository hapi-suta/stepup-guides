---
layout: default
title: "Build 03 - Row-Level Security"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 4
locked: "no"
---

# BUILD 03 - Row-Level Security

Table privileges are all-or-nothing: hold `SELECT` and you see every row. **Row-Level
Security (RLS)** adds a per-row filter so one table can show each user only their own
rows - the job you used Oracle VPD (`DBMS_RLS`) or Label Security for. Here you enable
RLS on a table, write a policy, and prove two salespeople reading the same table see
completely different rows. Then you will see the trap that catches everyone: the table
owner and superusers bypass RLS.

Every command was run on a live EPAS 16 box; the outputs are real.

## 1. Connect and build the table

On **epas-single**, as **ec2-user**:

```bash
sudo -iu enterprisedb
```

Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb
```

At the `edb=#` prompt, create a table where each row is owned by a named user:

```sql
CREATE TABLE orders (id int PRIMARY KEY, owner text, amount numeric);
```

```sql
INSERT INTO orders VALUES (1,'sales_a',100),(2,'sales_b',200),(3,'sales_a',300);
```

Rows 1 and 3 belong to `sales_a`; row 2 belongs to `sales_b`.

## 2. Create the two users and grant them table access

```sql
CREATE ROLE sales_a LOGIN PASSWORD 'x';
```

```sql
CREATE ROLE sales_b LOGIN PASSWORD 'x';
```

```sql
GRANT SELECT ON orders TO sales_a, sales_b;
```

At this point both users can `SELECT` the table - and with no RLS yet, both would see
all three rows.

## 3. Enable RLS and write the policy

Turn on row security for the table:

```sql
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
```

```
ALTER TABLE
```

**Important:** the moment RLS is enabled with no policy, the table is default-deny to
non-owners - they see zero rows. So add the policy now. This one says a user may see a
row only when its `owner` column matches their own role name:

```sql
CREATE POLICY own_rows ON orders
    FOR SELECT
    USING (owner = current_user);
```

- `FOR SELECT` - the policy governs reads.
- `USING (owner = current_user)` - the per-row test; `current_user` is whoever is
  running the query.

```
CREATE POLICY
```

## 4. Prove each user sees only their own rows

Use `SET ROLE` to act as each user in turn (it drops superuser powers, so the policy
applies).

Act as `sales_a`:

```sql
SET ROLE sales_a;
```

```sql
SELECT id, owner FROM orders ORDER BY id;
```

Expected output (yours will differ):

```
 id |  owner
----+---------
  1 | sales_a
  3 | sales_a
(2 rows)
```

Now act as `sales_b`:

```sql
SET ROLE sales_b;
```

```sql
SELECT id, owner FROM orders ORDER BY id;
```

Expected output (yours will differ):

```
 id |  owner
----+---------
  2 | sales_b
(1 row)
```

Same table, same query, same `SELECT` privilege - and each user sees only their own
rows. That is RLS.

## 5. The trap: the owner and superusers bypass RLS

Return to the superuser and run the same query:

```sql
RESET ROLE;
```

```sql
SELECT id, owner FROM orders ORDER BY id;
```

Expected output (yours will differ):

```
 id |  owner
----+---------
  1 | sales_a
  2 | sales_b
  3 | sales_a
(3 rows)
```

All three rows. The policy is **not** broken - RLS does not apply to the table owner
or to superusers by default. This is the number-one "RLS isn't working" support
ticket: someone tests as the owner, sees everything, and assumes the policy failed.

## 6. FORCE the owner to obey (and see what superusers still do)

Make the owner obey the policies with `FORCE`:

```sql
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

Now query again as the superuser owner:

```sql
SELECT id, owner FROM orders ORDER BY id;
```

Expected output (yours will differ):

```
 id |  owner
----+---------
  1 | sales_a
  2 | sales_b
  3 | sales_a
(3 rows)
```

Still all three rows - because `enterprisedb` is a **superuser**, and superusers bypass
RLS even under `FORCE`. `FORCE` only bites a **non-superuser** owner. If a non-superuser
owned this table and ran the same query under `FORCE`, they would get **0 rows** (their
role name does not equal any `owner` value). The rule to remember:

- Default: table owner and superusers bypass RLS.
- `FORCE ROW LEVEL SECURITY`: a **non-superuser** owner now obeys policies.
- Superusers (and roles with the `BYPASSRLS` attribute) **always** bypass, `FORCE` or
  not.

Turn `FORCE` back off:

```sql
ALTER TABLE orders NO FORCE ROW LEVEL SECURITY;
```

## 7. Inspect the policy in the catalog

Policies are visible in `pg_policies`:

```sql
SELECT tablename, policyname, cmd, qual
FROM pg_policies WHERE tablename = 'orders';
```

Expected output (yours will differ):

```
 tablename | policyname |  cmd   |          qual
-----------+------------+--------+-------------------------
 orders    | own_rows   | SELECT | (owner = CURRENT_USER)
(1 row)
```

`qual` is the `USING` expression; `cmd` is which command the policy governs. A policy
that also restricted writes would show a `with_check` expression too.

## 8. Clean up

```sql
DROP TABLE orders;
```

Dropping the table drops its policies with it. Then remove the users:

```sql
DROP ROLE sales_a;
```

```sql
DROP ROLE sales_b;
```

Leave the client and shell:

```
edb=# \q
```

```bash
exit
```

## What you did

You enabled RLS on a table, wrote a `USING (owner = current_user)` policy, and watched
two users read the same table and get different rows - each seeing only their own. Then
you hit the trap that defines RLS support tickets: the owner and superusers bypass the
policy, so "test as the owner" is not a valid test. When someone reports "RLS isn't
filtering," your first question is *which role are they connected as* - because the
answer is almost always the owner or a superuser.

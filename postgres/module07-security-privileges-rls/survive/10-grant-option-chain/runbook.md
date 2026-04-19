# Scenario 10 - Grant Option Chain Broken

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: analyst_jr and intern_viewer are reporting
permission denied on customer_data. data_engineer also
lost access. sec_admin revoked data_engineer's access
but did not realize it would break the entire team.
The chain of GRANT OPTION privileges has collapsed.
```

---

## Key Concepts for Revision

- **GRANT OPTION creates dependency chains** - When role A grants to role B `WITH GRANT OPTION`, and B grants to C, and C grants to D, revoking from B automatically revokes from C and D. PostgreSQL tracks the grantor of every privilege and cascades revocations through the chain.

- **CASCADE is the default for REVOKE** - If you run `REVOKE SELECT ON table FROM role`, PostgreSQL defaults to CASCADE behavior. All privileges that were granted downstream through that role are also revoked. Use `REVOKE ... RESTRICT` to check if dependent grants exist before committing.

- **information_schema.role_table_grants shows the chain** - The `grantor` column in `role_table_grants` shows who granted each privilege. By following the grantor chain, you can trace the full dependency tree and understand what will break if you revoke from any point.

- **Direct grants survive cascade** - If role D has a grant from both role B (via chain) and directly from role A, revoking from B only removes the chain grant. The direct grant from A survives. This is why direct grants from the table owner are more resilient than chain grants.

---

## Diagnostic Steps

### Step 1 - Reproduce the error

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SET ROLE intern_viewer;
```

```sql
SELECT * FROM customer_data LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table customer_data
```

```sql
RESET ROLE;
```

### Step 2 - Check all affected roles

```sql
SET ROLE analyst_jr;
```

```sql
SELECT * FROM customer_data LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table customer_data
```

```sql
RESET ROLE;
```

```sql
SET ROLE data_engineer;
```

```sql
SELECT * FROM customer_data LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table customer_data
```

```sql
RESET ROLE;
```

### Step 3 - Check who still has access

```sql
SET ROLE sec_admin;
```

```sql
SELECT count(*) FROM customer_data;
```

Expected output (yours will differ):

```
 count
-------
    20
(1 row)
```

sec_admin still has access because their grant came directly from postgres.

```sql
RESET ROLE;
```

### Step 4 - View the current grant state

```sql
SELECT grantee, grantor, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'customer_data'
  AND grantee NOT IN ('postgres')
ORDER BY grantee, privilege_type;
```

Expected output (yours will differ):

```
  grantee   | grantor  | privilege_type | is_grantable
------------+----------+----------------+--------------
 sec_admin  | postgres | DELETE         | YES
 sec_admin  | postgres | INSERT         | YES
 sec_admin  | postgres | SELECT         | YES
 sec_admin  | postgres | UPDATE         | YES
(4 rows)
```

Only sec_admin has grants. data_engineer, analyst_jr, and intern_viewer have nothing - the entire chain below sec_admin was wiped by CASCADE.

---

## Resolution

### Step 1 - Re-grant to data_engineer from sec_admin

Since sec_admin still has GRANT OPTION, they can rebuild the chain. But a better approach is to grant directly from postgres to avoid future chain breaks.

```sql
GRANT SELECT, INSERT, UPDATE ON customer_data TO data_engineer WITH GRANT OPTION;
```

Expected output:

```
GRANT
```

### Step 2 - Re-grant to analyst_jr

```sql
GRANT SELECT, INSERT ON customer_data TO analyst_jr WITH GRANT OPTION;
```

Expected output:

```
GRANT
```

### Step 3 - Re-grant to intern_viewer

```sql
GRANT SELECT ON customer_data TO intern_viewer;
```

Expected output:

```
GRANT
```

### Step 4 - Verify the grants

```sql
SELECT grantee, grantor, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'customer_data'
  AND grantee NOT IN ('postgres')
ORDER BY grantee, privilege_type;
```

Expected output (yours will differ):

```
    grantee     | grantor  | privilege_type | is_grantable
----------------+----------+----------------+--------------
 analyst_jr     | postgres | INSERT         | YES
 analyst_jr     | postgres | SELECT         | YES
 data_engineer  | postgres | INSERT         | YES
 data_engineer  | postgres | SELECT         | YES
 data_engineer  | postgres | UPDATE         | YES
 intern_viewer  | postgres | SELECT         | NO
 sec_admin      | postgres | DELETE         | YES
 sec_admin      | postgres | INSERT         | YES
 sec_admin      | postgres | SELECT         | YES
 sec_admin      | postgres | UPDATE         | YES
(10 rows)
```

All roles have their privileges. Notice the `grantor` is now `postgres` for all grants - this means a future revoke from sec_admin will not cascade to break the others.

### Step 5 - Test each role

```sql
SET ROLE data_engineer;
```

```sql
SELECT count(*) FROM customer_data;
```

Expected output (yours will differ):

```
 count
-------
    20
(1 row)
```

```sql
RESET ROLE;
```

```sql
SET ROLE analyst_jr;
```

```sql
SELECT count(*) FROM customer_data;
```

Expected output (yours will differ):

```
 count
-------
    20
(1 row)
```

```sql
RESET ROLE;
```

```sql
SET ROLE intern_viewer;
```

```sql
SELECT count(*) FROM customer_data;
```

Expected output (yours will differ):

```
 count
-------
    20
(1 row)
```

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
- data_engineer can SELECT from customer_data
- analyst_jr can SELECT from customer_data
- intern_viewer can SELECT from customer_data
- sec_admin still has full access

---

## Interview Discussion Points

1. **What is the difference between CASCADE and RESTRICT in REVOKE?** - `CASCADE` removes the specified privilege and all privileges that were granted downstream through the revoked role. `RESTRICT` refuses to revoke if any dependent grants exist and returns an error. Always use `RESTRICT` first in production to understand the blast radius before committing to a CASCADE revoke.

2. **Why is granting directly from the table owner more resilient than chain grants?** - When all grants come from the table owner (postgres), they are independent of each other. Revoking from one role does not affect others because there is no dependency chain. Chain grants through intermediate roles create a fragile tree where removing one node breaks all downstream nodes.

3. **What is a better pattern than GRANT OPTION chains for managing team access?** - Use group roles (role inheritance). Create a group role like `customer_data_readers`, grant SELECT to the group, and add users with `GRANT customer_data_readers TO analyst_jr`. When you remove a user from the group, other members are unaffected. This is simpler and more predictable than GRANT OPTION chains.

4. **How would you audit the full grant dependency tree before revoking?** - Query: `SELECT grantor, grantee, privilege_type, is_grantable FROM information_schema.role_table_grants WHERE table_name = 'customer_data' ORDER BY grantor, grantee;`. Trace the chain from the role you plan to revoke and identify all downstream grantees. In complex environments, build a recursive query or use a script to walk the tree.

5. **Can a role have the same privilege from multiple grantors?** - Yes. If postgres grants SELECT to alice, and bob (who has GRANT OPTION) also grants SELECT to alice, alice has two independent grants. Revoking bob's grant to alice only removes bob's grant. Alice still has the grant from postgres. PostgreSQL tracks each grant independently by grantor. This is why direct grants from the owner are safer.

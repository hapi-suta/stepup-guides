# Scenario 10 - Grant Cascade Broken

**Severity:** HIGH
**Expected Recovery Time:** 8-12 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: dev_alice and dev_bob are reporting permission
denied errors on the reports table. team_lead also lost
access. No one on the dev team can read reports.
The DBA recalls revoking team_lead's access but did not
expect it to affect other developers.
```

---

## Key Concepts for Revision

- **GRANT OPTION creates a chain** - When you grant a privilege `WITH GRANT OPTION`, the recipient can grant that same privilege to others. This creates a dependency chain. If the original grant is revoked, all downstream grants that depended on it are also revoked automatically (CASCADE behavior).

- **REVOKE CASCADE is the default** - In PostgreSQL, `REVOKE ... CASCADE` removes the privilege and all dependent grants. `REVOKE ... RESTRICT` refuses to revoke if any dependent grants exist. If you do not specify CASCADE or RESTRICT, PostgreSQL defaults to CASCADE. This catches many DBAs off guard.

- **information_schema.role_table_grants shows the chain** - This view shows who granted what to whom, including the `grantor` column. Use this to trace the full grant chain and understand dependencies.

- **Re-granting restores access** - After a cascade revoke, you must re-grant privileges from a role that still has GRANT OPTION or from the table owner. Grant directly to each role that needs access.

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
SET ROLE dev_bob;
```

```sql
SELECT * FROM reports LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table reports
```

```sql
RESET ROLE;
```

### Step 2 - Check dev_alice too

```sql
SET ROLE dev_alice;
```

```sql
SELECT * FROM reports LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table reports
```

```sql
RESET ROLE;
```

### Step 3 - Check team_lead

```sql
SET ROLE team_lead;
```

```sql
SELECT * FROM reports LIMIT 1;
```

Expected output:

```
ERROR:  permission denied for table reports
```

All three roles lost access.

```sql
RESET ROLE;
```

### Step 4 - Check what grants remain on the reports table

```sql
SELECT grantee, grantor, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'reports'
ORDER BY grantee, privilege_type;
```

Expected output (yours will differ):

```
 grantee  | grantor  | privilege_type | is_grantable
----------+----------+----------------+--------------
 postgres | postgres | DELETE         | YES
 postgres | postgres | INSERT         | YES
 postgres | postgres | SELECT         | YES
 postgres | postgres | UPDATE         | YES
(4 rows)
```

Only `postgres` (the table owner) has grants. The entire chain - team_lead, dev_alice, dev_bob - was wiped out by the CASCADE revoke.

---

## Resolution

### Step 1 - Re-grant to team_lead with GRANT OPTION

As `postgres` (the table owner), re-establish the top of the chain.

```sql
GRANT SELECT, INSERT, UPDATE ON reports TO team_lead WITH GRANT OPTION;
```

Expected output:

```
ALTER ROLE
```

The `WITH GRANT OPTION` flag allows team_lead to pass these privileges to others.

### Step 2 - Re-grant to dev_alice with GRANT OPTION

```sql
GRANT SELECT, INSERT ON reports TO dev_alice WITH GRANT OPTION;
```

Expected output:

```
GRANT
```

### Step 3 - Re-grant to dev_bob

```sql
GRANT SELECT ON reports TO dev_bob;
```

Expected output:

```
GRANT
```

### Step 4 - Verify the full grant chain

```sql
SELECT grantee, grantor, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'reports'
  AND grantee IN ('team_lead', 'dev_alice', 'dev_bob')
ORDER BY grantee, privilege_type;
```

Expected output (yours will differ):

```
  grantee   | grantor  | privilege_type | is_grantable
------------+----------+----------------+--------------
 dev_alice  | postgres | INSERT         | YES
 dev_alice  | postgres | SELECT         | YES
 dev_bob    | postgres | SELECT         | NO
 team_lead  | postgres | INSERT         | YES
 team_lead  | postgres | SELECT         | YES
 team_lead  | postgres | UPDATE         | YES
(6 rows)
```

All roles have their privileges back.

### Step 5 - Test each role

```sql
SET ROLE team_lead;
```

```sql
SELECT count(*) FROM reports;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

```sql
RESET ROLE;
```

```sql
SET ROLE dev_alice;
```

```sql
SELECT count(*) FROM reports;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

```sql
RESET ROLE;
```

```sql
SET ROLE dev_bob;
```

```sql
SELECT count(*) FROM reports;
```

Expected output (yours will differ):

```
 count
-------
     5
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
- team_lead has SELECT, INSERT, UPDATE on reports
- dev_alice has SELECT, INSERT on reports
- dev_bob has SELECT on reports
- All three roles can query the reports table

---

## Interview Discussion Points

1. **Why does REVOKE from one role affect other roles?** - When a privilege is granted WITH GRANT OPTION, the grantee becomes a link in a dependency chain. PostgreSQL tracks who granted what to whom. If the original grant is revoked, all grants that flowed through that role are also revoked. This is CASCADE behavior. It is designed to prevent privilege leaks - if you remove someone's access, they should not be able to maintain access through people they gave it to.

2. **What is the difference between REVOKE CASCADE and REVOKE RESTRICT?** - `CASCADE` removes the privilege and all dependent grants. `RESTRICT` refuses to revoke if any dependent grants exist - it returns an error instead. Use `RESTRICT` when you want to see what would break before committing to the revoke. PostgreSQL defaults to CASCADE when neither is specified, which is the risky default.

3. **How do you safely revoke a privilege without breaking downstream access?** - First, query `information_schema.role_table_grants` to see the full grant chain. Identify all downstream grantees. Then either: (a) re-grant directly from the table owner to each downstream role before revoking, or (b) use `REVOKE ... RESTRICT` to check for dependencies and handle them manually.

4. **What is the best practice for managing privilege chains in production?** - Avoid deep grant chains. Grant directly from the table owner or a designated admin role. Use role inheritance (group roles) instead of GRANT OPTION chains. For example, create a `reports_readers` group role, grant SELECT to the group, and add users to the group with `GRANT reports_readers TO dev_bob`. This way, removing a user from the group does not affect others.

5. **How would you audit the full grant dependency tree for a table?** - Use `SELECT grantor, grantee, privilege_type, is_grantable FROM information_schema.role_table_grants WHERE table_name = 'reports' ORDER BY grantor, grantee`. This shows the full picture. For complex environments, recursive CTEs can trace multi-level chains by following the grantor->grantee relationships.

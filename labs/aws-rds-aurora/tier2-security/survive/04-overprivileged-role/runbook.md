# Runbook - Scenario 04: Overprivileged Role

**Severity:** High
**Category:** Authorization / Least Privilege
**Estimated resolution time:** 20 minutes

---

## Situation

A security audit found that `report_user` - used by the BI reporting tool - has excessive database privileges.

Required access (what the reporting tool actually needs):
- `finance.accounts` - SELECT only
- `finance.transactions` - SELECT only

Excessive access (what was found):
- ALL privileges on all tables (INSERT, UPDATE, DELETE, TRUNCATE)
- Access to `finance.audit_trail` (sensitive - this table should not be visible to reporting)
- Access to `finance.internal_notes` (confidential - executive compensation data)
- CREATE privilege on the `finance` schema

---

## Diagnosis

### Step 1 - Connect to the database

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=financedb user=postgres sslmode=require"
```

### Step 2 - See what report_user can currently do

```sql
SELECT
    grantee,
    table_schema,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'report_user'
  AND table_schema = 'finance'
GROUP BY grantee, table_schema, table_name
ORDER BY table_name;
```

Expected output showing the problem (yours will differ):

```
  grantee   │ table_schema │   table_name   │          privileges
────────────┼──────────────┼────────────────┼──────────────────────────────────
 report_user│ finance      │ accounts       │ DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user│ finance      │ audit_trail    │ DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user│ finance      │ internal_notes │ DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user│ finance      │ transactions   │ DELETE, INSERT, SELECT, TRUNCATE, UPDATE
```

This is significantly more than the role needs.

### Step 3 - Check schema-level privileges

```sql
SELECT
    grantee,
    table_catalog,
    table_schema,
    privilege_type
FROM information_schema.schema_privileges
WHERE grantee = 'report_user';
```

If `CREATE` shows up here, the role can create tables in the schema. That is a serious overprivilege.

### Step 4 - Demonstrate the problem

Verify the role can delete data it should not be able to touch:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=financedb user=report_user sslmode=require"
```

```sql
-- This should NOT work - report_user is supposed to be read-only
DELETE FROM finance.accounts WHERE id = 1;
```

If that succeeds, you have confirmed the problem.

Exit:

```sql
\q
```

---

## Resolution

Connect as master user:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=financedb user=postgres sslmode=require"
```

### Step 1 - Revoke all current privileges

Start clean:

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA finance FROM report_user;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA finance FROM report_user;
REVOKE CREATE ON SCHEMA finance FROM report_user;
```

### Step 2 - Grant only what is needed

```sql
-- Only accounts and transactions, SELECT only
GRANT SELECT ON finance.accounts TO report_user;
GRANT SELECT ON finance.transactions TO report_user;
```

Do NOT grant access to `audit_trail` or `internal_notes`.

### Step 3 - Verify the fix

```sql
SELECT
    grantee,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'report_user'
  AND table_schema = 'finance'
GROUP BY grantee, table_name
ORDER BY table_name;
```

Expected output after fix:

```
  grantee   │  table_name  │ privileges
────────────┼──────────────┼────────────
 report_user│ accounts     │ SELECT
 report_user│ transactions │ SELECT
```

Only two rows, both with only SELECT. `audit_trail` and `internal_notes` do not appear.

### Step 4 - Test the fix as report_user

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=financedb user=report_user sslmode=require"
```

These should SUCCEED:

```sql
SELECT COUNT(*) FROM finance.accounts;
SELECT COUNT(*) FROM finance.transactions;
```

These should FAIL:

```sql
-- Should get: ERROR: permission denied for table audit_trail
SELECT * FROM finance.audit_trail;

-- Should get: ERROR: permission denied for table internal_notes
SELECT * FROM finance.internal_notes;

-- Should get: ERROR: permission denied for table accounts
DELETE FROM finance.accounts WHERE id = 1;

-- Should get: ERROR: permission denied for schema finance
CREATE TABLE finance.test_table (id INT);
```

Exit:

```sql
\q
```

---

## Post-Fix Audit Query

Run this to confirm no tables outside `accounts` and `transactions` are accessible:

```sql
SELECT
    grantee,
    table_name,
    string_agg(privilege_type, ', ') AS privileges
FROM information_schema.role_table_grants
WHERE grantee = 'report_user'
GROUP BY grantee, table_name;
```

Expected: exactly two rows. Any other tables listed are a problem.

---

## Root Cause Analysis

Answer these questions for your incident report:

1. When were the excessive privileges granted?
2. Was this an accident (GRANT ALL instead of GRANT SELECT) or intentional?
3. Could `report_user` have read `internal_notes` or `audit_trail` data before this fix?
4. Is there any evidence the reporting tool actually accessed those tables?
5. What process change would prevent this? (Peer review for GRANT statements? Automated privilege auditing?)

---

## Prevention

1. Use `GRANT SELECT ON specific_table` - never `GRANT ALL PRIVILEGES ON ALL TABLES`
2. Perform quarterly privilege audits using the diagnosis query above
3. Set up automated alerts when `ALL` is granted in any privilege statement
4. Use a script or Terraform to manage role privileges as code - reviewed before applying
5. Separate read-only roles from read-write roles and document which applications use which

# Runbook - Scenario 04: Overprivileged Role

**Severity:** High
**Category:** Authorization / Least Privilege
**Estimated resolution time:** 20 minutes

---

## What Is Being Tested

Your ability to audit a PostgreSQL role's privileges, identify excessive grants, revoke them, and apply the principle of least privilege by granting only the specific access needed.

---

## Why This Matters

An overprivileged role is a ticking time bomb. If the reporting tool using `report_user` gets compromised, the attacker inherits ALL those privileges. They could delete financial data, modify audit records to cover their tracks, or read confidential internal notes. Least privilege limits the blast radius of any compromise.

---

## Symptoms

- Security audit flags a role with ALL PRIVILEGES on sensitive tables
- A reporting tool user can modify or delete data it should only read
- A role has access to tables outside its intended scope (e.g., audit_trail, internal_notes)

---

## Diagnostic Steps

### Step 1 - Connect to the database

```bash
PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=$MASTER_USER sslmode=require"
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

Expected output showing the problem:

```
  grantee   | table_schema |   table_name   |          privileges
------------+--------------+----------------+-----------------------------------
 report_user| finance      | accounts       | DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user| finance      | audit_trail    | DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user| finance      | internal_notes | DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 report_user| finance      | transactions   | DELETE, INSERT, SELECT, TRUNCATE, UPDATE
```

This is significantly more than the role needs.

### Step 3 - Check schema-level privileges

```sql
SELECT nspname, has_schema_privilege('report_user', nspname, 'CREATE') AS can_create
FROM pg_namespace
WHERE nspname = 'finance';
```

If `can_create` is `t`, the role can create tables in the schema. That is a serious overprivilege.

### Step 4 - Demonstrate the problem

Connect as report_user:

```bash
PGPASSWORD="ReportPass1!" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=report_user sslmode=require"
```

```sql
-- This should NOT work - report_user is supposed to be read-only
SELECT * FROM finance.internal_notes;
```

If that succeeds and shows confidential data, you have confirmed the problem.

Exit:

```sql
\q
```

---

## Resolution

Connect as master user:

```bash
PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=$MASTER_USER sslmode=require"
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
  grantee   |  table_name  | privileges
------------+--------------+------------
 report_user| accounts     | SELECT
 report_user| transactions | SELECT
```

Only two rows, both with only SELECT. `audit_trail` and `internal_notes` do not appear.

### Step 4 - Test the fix as report_user

```bash
PGPASSWORD="ReportPass1!" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=financedb user=report_user sslmode=require"
```

These should SUCCEED:

```sql
SELECT COUNT(*) FROM finance.accounts;
SELECT COUNT(*) FROM finance.transactions;
```

These should FAIL:

```sql
SELECT * FROM finance.audit_trail;
SELECT * FROM finance.internal_notes;
DELETE FROM finance.accounts WHERE id = 1;
CREATE TABLE finance.test_table (id INT);
```

Each should return: `ERROR: permission denied`

Exit:

```sql
\q
```

---

## Prevention

1. Use `GRANT SELECT ON specific_table` - never `GRANT ALL PRIVILEGES ON ALL TABLES`
2. Perform quarterly privilege audits using the diagnostic query above
3. Set up automated alerts when `ALL` is granted in any privilege statement
4. Use Terraform or SQL migration scripts to manage role privileges as code
5. Separate read-only roles from read-write roles and document which applications use which

---

## Interview Questions

1. What is the difference between REVOKE ALL and REVOKE specific privileges?
2. How do you check what privileges a role has without connecting as that role?
3. What is the "role as group" pattern and how does it scale?
4. How would you automate quarterly privilege audits?

---

## Key Terminology

| Term | Definition |
|------|-----------|
| Least privilege | Each role gets only the minimum permissions it needs |
| GRANT | SQL command that gives privileges to a role |
| REVOKE | SQL command that removes privileges from a role |
| information_schema.role_table_grants | View showing all table-level privileges |
| NOLOGIN | Role attribute that prevents direct login (used for group roles) |

---

## Red Flags

- Any role with `GRANT ALL PRIVILEGES ON ALL TABLES`
- Application roles with DROP, TRUNCATE, or CREATE privileges
- Roles with access to audit or internal tables they do not need
- No regular privilege audit process
- Roles without password expiration for contractor or temporary accounts

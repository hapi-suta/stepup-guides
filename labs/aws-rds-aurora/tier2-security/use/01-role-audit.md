# Use 01 - Role Audit

**Time:** 20 minutes
**Prerequisite:** Build 01 (Roles and Permissions)

---

## Scenario

You just joined [COMPANY] as the new DBA. The team has been using RDS for 18 months. No one has ever audited the database roles.

Your manager says: "We need to pass a security audit next month. Find any roles with too much access and fix them."

---

## Your Tasks

1. Find all roles that exist in the database
2. Identify roles with excessive privileges
3. Find roles that can log in but should not be able to
4. Find tables that are accessible by roles that should not have access
5. Fix the problems you find

---

## Setup

Connect to your RDS instance as the master user:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres"
```

Run this script to create a messy role setup to audit:

```sql
-- Create a test database and schema
CREATE DATABASE auditdb;
\c auditdb
CREATE SCHEMA myapp;

-- Create some tables
CREATE TABLE myapp.users (id SERIAL PRIMARY KEY, email TEXT, password_hash TEXT);
CREATE TABLE myapp.orders (id SERIAL PRIMARY KEY, amount NUMERIC, user_id INT);
CREATE TABLE myapp.audit_log (id SERIAL PRIMARY KEY, event TEXT, created_at TIMESTAMPTZ);

-- Create roles with problems for you to find
CREATE ROLE developer1 WITH LOGIN PASSWORD 'Dev1Pass!';
CREATE ROLE developer2 WITH LOGIN PASSWORD 'Dev2Pass!';
CREATE ROLE api_service WITH LOGIN PASSWORD 'ApiPass1!';
CREATE ROLE reporting WITH LOGIN PASSWORD 'ReportPass!';
CREATE ROLE temp_contractor WITH LOGIN PASSWORD 'Temp1Pass!';

-- Give developer1 way too much access
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp TO developer1;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA myapp TO developer1;

-- Give api_service access to tables it should not touch
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.users TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.orders TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.audit_log TO api_service;  -- should not have this

-- Give reporting full write access (should be read-only)
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myapp TO reporting;

-- temp_contractor has CONNECT but should have been removed months ago
GRANT CONNECT ON DATABASE auditdb TO temp_contractor;
GRANT USAGE ON SCHEMA myapp TO temp_contractor;
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO temp_contractor;
```

---

## Task 1 - List All Roles

Run the query below. Write down every role you see.

```sql
SELECT
    rolname,
    rolcanlogin,
    rolcreaterole,
    rolcreatedb,
    rolsuper,
    rolreplication
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
  AND rolname NOT IN ('rdsadmin', 'rds_superuser', 'rds_replication',
                       'rds_iam', 'rdsrepladmin', 'rds_monitor',
                       'rds_password')
ORDER BY rolname;
```

Write down which roles can log in (rolcanlogin = t).

---

## Task 2 - Find Roles With Excessive Table Privileges

```sql
SELECT
    grantee,
    table_schema,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'myapp'
  AND grantee NOT IN ('postgres', 'rds_superuser')
GROUP BY grantee, table_schema, table_name
ORDER BY grantee, table_name;
```

Look for:
- Roles with INSERT/UPDATE/DELETE on tables they should only read
- Roles with access to sensitive tables (like `users` or `audit_log`) that should not have it
- Any role with `ALL` or a very long list of privileges when it only needs SELECT

Write down what you find before fixing anything.

---

## Task 3 - Check Who Can Connect to the Database

```sql
SELECT
    rolname,
    rolcanlogin,
    rolvaliduntil
FROM pg_roles
WHERE rolcanlogin = TRUE
  AND rolname NOT IN ('postgres', 'rdsadmin')
ORDER BY rolname;
```

The `rolvaliduntil` column shows when a role's password expires. NULL means it never expires.

Look for:
- Roles that should not be able to log in directly (they should be group roles with NOLOGIN)
- Roles with no expiration that belong to contractors or temporary users

---

## Task 4 - Find the Problems

Based on your audit queries, answer these questions:

1. Which role has `ALL PRIVILEGES` that it should not have?
2. Which role has write access to `audit_log` but should only be able to insert (application services should never be able to update or delete audit records)?
3. Which role is for reporting but has INSERT, UPDATE, DELETE?
4. Which role appears to belong to a temporary user who may no longer need access?

---

## Task 5 - Fix the Problems

Fix each problem you identified. Use the SQL below as a starting point, but fill in the correct role names from your audit.

**Fix 1 - Remove excessive privileges from developer1:**

```sql
-- Remove ALL and replace with specific privileges
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp FROM developer1;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA myapp FROM developer1;

-- Grant only what a developer needs for local debugging (SELECT only, no writes)
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO developer1;
```

**Fix 2 - Remove audit_log write access from api_service:**

```sql
REVOKE INSERT, UPDATE, DELETE ON myapp.audit_log FROM api_service;
-- api_service should only be able to INSERT to audit_log, not update or delete
GRANT INSERT ON myapp.audit_log TO api_service;
```

**Fix 3 - Make reporting role read-only:**

```sql
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myapp FROM reporting;
-- SELECT is still granted
```

**Fix 4 - Revoke temp_contractor access:**

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp FROM temp_contractor;
REVOKE USAGE ON SCHEMA myapp FROM temp_contractor;
REVOKE CONNECT ON DATABASE auditdb FROM temp_contractor;
```

---

## Task 6 - Verify Your Fixes

Re-run the Task 2 query. Compare the output to what you saw before. Confirm:

- `developer1` only has SELECT
- `api_service` can INSERT to audit_log but not UPDATE or DELETE
- `reporting` only has SELECT on all tables
- `temp_contractor` has no privileges

---

## Task 7 - Write a Summary Report

Answer these questions as if writing a report for your manager:

1. How many roles existed before your audit?
2. How many had excessive privileges?
3. What was the most serious finding and why?
4. What did you fix, and what privileges does each role now have?
5. What ongoing process would prevent this from happening again?

---

## Verification Queries

Use these to confirm everything is clean:

```sql
-- Should show no results if temp_contractor is fully revoked
SELECT grantee, privilege_type, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'temp_contractor';

-- Should show only SELECT for developer1
SELECT grantee, privilege_type, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'developer1'
ORDER BY table_name, privilege_type;

-- Should show only INSERT on audit_log for api_service, no UPDATE/DELETE
SELECT grantee, privilege_type, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'api_service'
  AND table_name = 'audit_log';
```

---

## Clean Up

```sql
\c postgres
DROP DATABASE auditdb;
DROP ROLE developer1, developer2, api_service, reporting, temp_contractor;
```

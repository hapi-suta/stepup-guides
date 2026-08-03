# Use 01 - Security Audit Exercise

**Time:** 25 minutes
**Prerequisite:** Build 01 (Security Groups), Build 02 (SSL), Build 05 (Roles)

---

## Scenario

You just joined [COMPANY] as the new DevOps DBA. The Aurora cluster `devops-lab-cluster` has been running for 12 months. No one has ever done a security audit.

Your manager says: "We have a compliance audit in two weeks. I need a security assessment of the Aurora cluster covering network, encryption, authentication, and authorization. Find every problem and fix it."

---

## Your Tasks

1. Audit the network configuration (security groups, public accessibility)
2. Audit SSL/TLS enforcement
3. Audit the database roles and their privileges
4. Find and fix every security problem
5. Write a summary report

---

## Setup

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export AWS_REGION="us-east-1"
```

Connect as master user and create a messy security setup to audit:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

```sql
CREATE DATABASE auditdb;
\c auditdb
CREATE SCHEMA myapp;

CREATE TABLE myapp.users (id SERIAL PRIMARY KEY, email TEXT, password_hash TEXT);
CREATE TABLE myapp.orders (id SERIAL PRIMARY KEY, amount NUMERIC, user_id INT);
CREATE TABLE myapp.audit_log (id SERIAL PRIMARY KEY, event TEXT, created_at TIMESTAMPTZ);
CREATE TABLE myapp.pii_data (id SERIAL PRIMARY KEY, ssn TEXT, full_name TEXT);

CREATE ROLE developer1 WITH LOGIN PASSWORD 'Dev1Pass!';
CREATE ROLE api_service WITH LOGIN PASSWORD 'ApiPass1!';
CREATE ROLE reporting WITH LOGIN PASSWORD 'ReportPass!';
CREATE ROLE temp_contractor WITH LOGIN PASSWORD 'Temp1Pass!';
CREATE ROLE old_intern WITH LOGIN PASSWORD 'Intern123';

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp TO developer1;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA myapp TO developer1;

GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.users TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.orders TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON myapp.audit_log TO api_service;
GRANT SELECT ON myapp.pii_data TO api_service;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myapp TO reporting;

GRANT CONNECT ON DATABASE auditdb TO temp_contractor;
GRANT USAGE ON SCHEMA myapp TO temp_contractor;
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO temp_contractor;

GRANT CONNECT ON DATABASE auditdb TO old_intern;
GRANT USAGE ON SCHEMA myapp TO old_intern;
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO old_intern;
```

---

## Task 1 - Audit Network Configuration

Check the security group rules:

```bash
export CLUSTER_SG=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text \
  --region $AWS_REGION)

aws ec2 describe-security-groups \
  --group-ids $CLUSTER_SG \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json \
  --region $AWS_REGION
```

Look for:
- Is `0.0.0.0/0` listed as a source? (Critical finding)
- Are there more inbound rules than expected?
- Is the port correct (5432)?

Check public accessibility:

```bash
aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
  --query 'DBInstances[*].{Instance:DBInstanceIdentifier,Public:PubliclyAccessible}' \
  --output table \
  --region $AWS_REGION
```

Write down your findings.

<details>
<summary>Hint - What to look for</summary>

1. If `0.0.0.0/0` is a source, the database is reachable from the entire internet - this is critical
2. `PubliclyAccessible: True` gives the instance a public IP - this should be False
3. The security group should reference another security group (app servers), not IP ranges

</details>

---

## Task 2 - Audit SSL/TLS

Check if SSL is enforced:

```sql
SHOW rds.force_ssl;
```

Check the current connection's SSL status:

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Check all active connections for SSL status:

```sql
SELECT
    sa.usename,
    sa.client_addr,
    ss.ssl,
    ss.version
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend'
ORDER BY ss.ssl;
```

Write down: Is SSL enforced? Are there any unencrypted connections?

<details>
<summary>Hint - Expected findings</summary>

1. `rds.force_ssl = off` means non-SSL connections are allowed - fix by setting to 1
2. Any connection with `ssl = f` is unencrypted traffic
3. Production clusters should always have `rds.force_ssl = 1`

</details>

---

## Task 3 - Audit Database Roles

List all roles:

```sql
SELECT
    rolname,
    rolcanlogin,
    rolcreaterole,
    rolcreatedb,
    rolsuper,
    rolvaliduntil
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
  AND rolname NOT IN ('rdsadmin', 'rds_superuser', 'rds_replication',
                       'rds_iam', 'rdsrepladmin', 'rds_monitor',
                       'rds_password')
ORDER BY rolname;
```

Check role privileges on tables:

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

Answer these questions:
1. Which roles have ALL PRIVILEGES that should not?
2. Which roles can access `pii_data` that should not?
3. Which roles appear to be stale (no longer needed)?
4. Does `api_service` have write access to `audit_log`? Should it?
5. Does `reporting` have write access? Should it?

<details>
<summary>Hint - Expected findings</summary>

1. `developer1` has ALL PRIVILEGES on ALL tables - should only need SELECT for debugging
2. `api_service` has SELECT on `pii_data` - should it? Also has UPDATE/DELETE on `audit_log` which is dangerous
3. `temp_contractor` and `old_intern` appear to be stale accounts that should be revoked
4. `reporting` has INSERT, UPDATE, DELETE but should be read-only
5. No roles have password expiration set (`rolvaliduntil` is NULL)

</details>

---

## Task 4 - Fix the Problems

Fix each problem you identified. Here are the fixes:

<details>
<summary>Solution - Fix developer1</summary>

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp FROM developer1;
REVOKE ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA myapp FROM developer1;
GRANT SELECT ON ALL TABLES IN SCHEMA myapp TO developer1;
-- Remove pii_data access
REVOKE SELECT ON myapp.pii_data FROM developer1;
```

</details>

<details>
<summary>Solution - Fix api_service</summary>

```sql
-- Remove write access to audit_log (only INSERT should be kept for logging)
REVOKE UPDATE, DELETE ON myapp.audit_log FROM api_service;
-- Remove pii_data access (api does not need it)
REVOKE SELECT ON myapp.pii_data FROM api_service;
```

</details>

<details>
<summary>Solution - Fix reporting</summary>

```sql
REVOKE INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA myapp FROM reporting;
-- reporting should be SELECT only
```

</details>

<details>
<summary>Solution - Remove stale accounts</summary>

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp FROM temp_contractor;
REVOKE USAGE ON SCHEMA myapp FROM temp_contractor;
REVOKE CONNECT ON DATABASE auditdb FROM temp_contractor;

REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA myapp FROM old_intern;
REVOKE USAGE ON SCHEMA myapp FROM old_intern;
REVOKE CONNECT ON DATABASE auditdb FROM old_intern;
```

</details>

---

## Task 5 - Verify Your Fixes

Re-run the audit query from Task 3. Confirm:

- `developer1` has SELECT only (not on pii_data)
- `api_service` has appropriate access (no UPDATE/DELETE on audit_log, no pii_data)
- `reporting` has SELECT only
- `temp_contractor` and `old_intern` have no privileges

<details>
<summary>Solution - Verification query</summary>

```sql
SELECT
    grantee,
    table_name,
    string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema = 'myapp'
  AND grantee IN ('developer1', 'api_service', 'reporting', 'temp_contractor', 'old_intern')
GROUP BY grantee, table_name
ORDER BY grantee, table_name;
```

</details>

---

## Task 6 - Write the Audit Report

Write a summary covering:

1. How many roles existed before your audit?
2. How many had excessive privileges?
3. What was the most serious finding and why?
4. What did you fix?
5. What ongoing process would prevent this from happening again?

---

## Clean Up

```sql
\c postgres
DROP DATABASE auditdb;
DROP ROLE developer1, api_service, reporting, temp_contractor, old_intern;
```

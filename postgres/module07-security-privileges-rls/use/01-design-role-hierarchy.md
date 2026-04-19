# Use 01 - Design a Role Hierarchy for a SaaS Application

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 25 minutes

---

## Objective

Design and implement a complete role hierarchy for a multi-tenant SaaS application. The application has four access levels. You will create the roles with correct attributes and inheritance, then verify the hierarchy works as expected.

---

## The Business Requirements

You are building access control for a SaaS platform with the following roles:

| Role | Access Level | Can Do |
|------|-------------|--------|
| system_admin | Cluster-wide | Create databases, create roles, manage all tenants |
| tenant_admin | Database-wide | Manage tables and users within their tenant schema |
| tenant_user | Read/write | INSERT, UPDATE, SELECT on tenant tables |
| tenant_readonly | Read-only | SELECT only on tenant tables |

Roles must inherit privileges through group membership. Individual users are members of exactly one role group. No individual user account should have direct privileges on tables - all privileges flow through the group roles.

---

## Step 1 - SSH to your server

```bash
ssh -i your-key.pem ec2-user@NODE1
```

---

## Step 2 - Switch to the postgres OS user

```bash
sudo -iu postgres
```

---

## Step 3 - Connect to PostgreSQL

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 4 - Create the group roles

Create system_admin group (NOLOGIN - nobody logs in as this role directly):

```sql
CREATE ROLE system_admin NOLOGIN CREATEDB CREATEROLE;
```

Create tenant_admin group:

```sql
CREATE ROLE tenant_admin NOLOGIN;
```

Create tenant_user group:

```sql
CREATE ROLE tenant_user NOLOGIN;
```

Create tenant_readonly group:

```sql
CREATE ROLE tenant_readonly NOLOGIN;
```

Expected output for each:

```
CREATE ROLE
```

---

## Step 5 - Create individual user accounts and assign to groups

Create an individual system admin user:

```sql
CREATE ROLE sa_alice WITH LOGIN PASSWORD 'sapass123';
```

```sql
GRANT system_admin TO sa_alice;
```

Create a tenant admin user:

```sql
CREATE ROLE ta_bob WITH LOGIN PASSWORD 'tapass123';
```

```sql
GRANT tenant_admin TO ta_bob;
```

Create two tenant users:

```sql
CREATE ROLE tu_carol WITH LOGIN PASSWORD 'tupass123';
```

```sql
GRANT tenant_user TO tu_carol;
```

```sql
CREATE ROLE tu_dave WITH LOGIN PASSWORD 'tupass123';
```

```sql
GRANT tenant_user TO tu_dave;
```

Create a readonly user:

```sql
CREATE ROLE ro_eve WITH LOGIN PASSWORD 'ropass123';
```

```sql
GRANT tenant_readonly TO ro_eve;
```

---

## Step 6 - Create the tenant schema

```sql
CREATE SCHEMA saas_tenant;
```

---

## Step 7 - Grant schema privileges to groups

Tenant admin needs USAGE and CREATE:

```sql
GRANT USAGE, CREATE ON SCHEMA saas_tenant TO tenant_admin;
```

Tenant user and readonly need USAGE only:

```sql
GRANT USAGE ON SCHEMA saas_tenant TO tenant_user;
```

```sql
GRANT USAGE ON SCHEMA saas_tenant TO tenant_readonly;
```

---

## Step 8 - Create a sample table in the tenant schema

```sql
CREATE TABLE saas_tenant.subscriptions (
    id          SERIAL PRIMARY KEY,
    user_email  TEXT NOT NULL,
    plan_name   TEXT NOT NULL,
    active      BOOLEAN DEFAULT TRUE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

---

## Step 9 - Grant table privileges to each group role

Tenant user gets read/write:

```sql
GRANT SELECT, INSERT, UPDATE ON TABLE saas_tenant.subscriptions TO tenant_user;
```

Tenant readonly gets read only:

```sql
GRANT SELECT ON TABLE saas_tenant.subscriptions TO tenant_readonly;
```

Tenant admin gets full control:

```sql
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLE saas_tenant.subscriptions TO tenant_admin;
```

---

## Step 10 - Set default privileges for future tables

When new tables are created in the schema, grant them automatically:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA saas_tenant
GRANT SELECT, INSERT, UPDATE ON TABLES TO tenant_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA saas_tenant
GRANT SELECT ON TABLES TO tenant_readonly;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA saas_tenant
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE ON TABLES TO tenant_admin;
```

---

## Step 11 - Test ro_eve (tenant_readonly)

Exit and connect as ro_eve:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U ro_eve
```

This should succeed:

```sql
SELECT * FROM saas_tenant.subscriptions;
```

This should fail:

```sql
INSERT INTO saas_tenant.subscriptions (user_email, plan_name) VALUES ('test@example.com', 'basic');
```

Expected error:

```
ERROR:  permission denied for table subscriptions
```

Exit:

```sql
\q
```

---

## Step 12 - Test tu_carol (tenant_user)

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U tu_carol
```

This should succeed:

```sql
INSERT INTO saas_tenant.subscriptions (user_email, plan_name) VALUES ('carol@example.com', 'pro');
```

This should fail (no DELETE privilege for tenant_user):

```sql
DELETE FROM saas_tenant.subscriptions WHERE user_email = 'carol@example.com';
```

Expected error:

```
ERROR:  permission denied for table subscriptions
```

Exit:

```sql
\q
```

---

## Step 13 - Connect back as postgres and verify the hierarchy

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Check role memberships:

```sql
SELECT rolname, member::regrole AS member_of
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
WHERE rolname IN ('system_admin','tenant_admin','tenant_user','tenant_readonly')
ORDER BY rolname;
```

Expected output (yours will differ):

```
     rolname      |  member_of
------------------+------------
 system_admin     | sa_alice
 tenant_admin     | ta_bob
 tenant_readonly  | ro_eve
 tenant_user      | tu_carol
 tenant_user      | tu_dave
(5 rows)
```

---

## Step 14 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Validation Questions

Answer these before moving to the next exercise:

1. Why do the group roles use NOLOGIN?
2. What happens if you add a new user to `tenant_readonly` - do they automatically get SELECT on existing tables?
3. How would you revoke Carol's access completely without affecting Dave?
4. What is the risk if `system_admin` has SUPERUSER instead of just CREATEDB and CREATEROLE?

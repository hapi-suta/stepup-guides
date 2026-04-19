# Use 04 - Privilege Audit

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 20 minutes

---

## Objective

Write SQL queries to answer the question: "Who has access to what?" Using information_schema and pg_catalog system views, you will produce a full privilege map of the database.

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

## Step 4 - List all roles and their attributes

```sql
SELECT rolname,
       rolsuper     AS is_superuser,
       rolinherit   AS inherits,
       rolcreaterole AS can_create_roles,
       rolcreatedb  AS can_create_db,
       rolcanlogin  AS can_login,
       rolbypassrls AS bypasses_rls,
       rolconnlimit AS conn_limit
FROM pg_roles
WHERE rolname NOT LIKE 'pg_%'
ORDER BY rolname;
```

This query shows every non-system role and its cluster-level attributes. Look for any unexpected superusers or roles with BYPASSRLS.

Expected output (yours will differ):

```
     rolname      | is_superuser | inherits | can_create_roles | can_create_db | can_login | bypasses_rls | conn_limit
------------------+--------------+----------+------------------+---------------+-----------+--------------+------------
 admin_user       | f            | t        | t                | t             | t         | f            |         -1
 analytics_team   | f            | t        | f                | f             | f         | f            |         -1
 app_user         | f            | t        | f                | f             | t         | f            |         20
 dba_ops          | f            | t        | f                | f             | t         | t            |         -1
 postgres         | t            | t        | t                | t             | t         | t            |         -1
 ...
```

---

## Step 5 - Find all roles with superuser or BYPASSRLS

```sql
SELECT rolname,
       rolsuper     AS is_superuser,
       rolbypassrls AS bypasses_rls
FROM pg_roles
WHERE rolsuper = true OR rolbypassrls = true
ORDER BY rolname;
```

Expected output (yours will differ):

```
  rolname  | is_superuser | bypasses_rls
-----------+--------------+--------------
 dba_ops   | f            | t
 postgres  | t            | t
(2 rows)
```

Any role in this list bypasses security controls. Keep this list short and review it regularly.

---

## Step 6 - Find all role memberships

```sql
SELECT r.rolname AS group_role,
       m.rolname AS member
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.roleid
JOIN pg_roles m ON m.oid = am.member
ORDER BY group_role, member;
```

Expected output (yours will differ):

```
   group_role    |    member
-----------------+--------------
 analytics_team  | analyst_carol
 dev_team        | dev_alice
 dev_team        | dev_bob
 system_admin    | sa_alice
 tenant_admin    | ta_bob
 tenant_readonly | ro_eve
 tenant_user     | tu_carol
 tenant_user     | tu_dave
(8 rows)
```

---

## Step 7 - List all table-level privileges

```sql
SELECT grantee,
       table_schema,
       table_name,
       string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
FROM information_schema.role_table_grants
WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
GROUP BY grantee, table_schema, table_name
ORDER BY grantee, table_schema, table_name;
```

This aggregates all privileges per role per table into a single readable line.

Expected output (yours will differ):

```
    grantee     | table_schema |      table_name      |          privileges
----------------+--------------+----------------------+-------------------------------
 analytics_team | public       | orders               | SELECT
 app_user       | public       | customers            | DELETE, INSERT, SELECT, UPDATE
 app_user       | public       | orders               | INSERT, SELECT
 tenant_admin   | saas_tenant  | subscriptions        | DELETE, INSERT, SELECT, TRUNCATE, UPDATE
 tenant_readonly| saas_tenant  | subscriptions        | SELECT
 tenant_user    | saas_tenant  | subscriptions        | INSERT, SELECT, UPDATE
 ...
```

---

## Step 8 - Check for column-level privileges

```sql
SELECT grantee, table_schema, table_name, column_name, privilege_type
FROM information_schema.role_column_grants
WHERE table_schema NOT IN ('information_schema', 'pg_catalog')
ORDER BY grantee, table_name, column_name;
```

Column-level grants are often forgotten during privilege audits. This query surfaces them explicitly.

Expected output (yours will differ):

```
    grantee    | table_schema | table_name | column_name  | privilege_type
---------------+--------------+------------+--------------+---------------
 readonly_user | public       | orders     | id           | SELECT
 readonly_user | public       | orders     | status       | SELECT
 readonly_user | public       | orders     | total_amount | SELECT
(3 rows)
```

---

## Step 9 - Audit schema privileges

```sql
SELECT n.nspname AS schema_name,
       r.rolname AS grantor,
       pg_catalog.array_to_string(n.nspacl, E'\n') AS raw_acl
FROM pg_catalog.pg_namespace n
CROSS JOIN pg_roles r
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
ORDER BY n.nspname;
```

Expected output (yours will differ):

```
     schema_name      | grantor  |            raw_acl
----------------------+----------+--------------------------------
 analytics_schema     | postgres | analytics_team=UC/analytics_team
 dev_schema           | postgres | dev_team=UC/dev_team
 public               | postgres | postgres=UC/postgres          +
                      |          | =U/postgres
 restricted_data      | postgres |
 saas_tenant          | postgres | tenant_admin=UC/postgres      +
                      |          | tenant_user=U/postgres        +
                      |          | tenant_readonly=U/postgres
```

---

## Step 10 - Find all objects owned by each role

```sql
SELECT n.nspname AS schema,
       c.relname AS object_name,
       CASE c.relkind
           WHEN 'r' THEN 'table'
           WHEN 'v' THEN 'view'
           WHEN 'S' THEN 'sequence'
           WHEN 'i' THEN 'index'
           ELSE c.relkind::text
       END AS object_type,
       r.rolname AS owner
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_roles r ON r.oid = c.relowner
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast')
  AND c.relkind IN ('r', 'v', 'S')
ORDER BY owner, schema, object_name;
```

Expected output (yours will differ):

```
    schema    |    object_name    | object_type |    owner
--------------+-------------------+-------------+-----------
 public       | audit_log         | table       | postgres
 public       | customers         | table       | postgres
 public       | orders            | table       | postgres
 saas_tenant  | subscriptions     | table       | postgres
(4 rows)
```

---

## Step 11 - Check default privileges

```sql
SELECT pg_get_userbyid(d.defaclrole) AS role,
       n.nspname AS schema,
       CASE d.defaclobjtype
           WHEN 'r' THEN 'table'
           WHEN 'f' THEN 'function'
           WHEN 'S' THEN 'sequence'
           ELSE d.defaclobjtype::text
       END AS object_type,
       array_to_string(d.defaclacl, ', ') AS default_grants
FROM pg_default_acl d
LEFT JOIN pg_namespace n ON n.oid = d.defaclnamespace
ORDER BY role, schema, object_type;
```

Default privileges determine what a new object automatically gets. This is the most commonly missed item in privilege audits.

---

## Step 12 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Validation Questions

Answer these before moving to the next exercise:

1. What does the `=U/postgres` entry in nspacl mean? Who is the grantee?
2. How would you find all roles that have SELECT on the `orders` table, including roles that inherit it through group membership?
3. Why is auditing default privileges important?
4. If a role appears in `role_table_grants` but cannot access the table, what is the most likely cause?

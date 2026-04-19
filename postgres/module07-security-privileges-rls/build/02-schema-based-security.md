# Build 02 - Schema-Based Security

**Module:** 07 - Security, Privileges & Row-Level Security
**Node:** NODE1 only
**Time:** 25 minutes

---

## What You Will Learn

- How to use schemas as security containers for team-based access control
- How to create and configure team-specific schemas
- How to set search_path per role
- How GRANT USAGE ON SCHEMA works and why it matters
- How objects become invisible when USAGE is not granted

---

> **Concept: Schemas as Security Boundaries**
> A schema is a namespace inside a PostgreSQL database. Every object (table, view, function, sequence) lives in exactly one schema. By controlling who has USAGE on a schema, you control who can see the objects inside it. Teams working on separate concerns - for example a developer team and an analytics team - can each have a dedicated schema. Members of one team have USAGE on their own schema but not on the other. The tables are in the same database, but each team only sees their own namespace. This is far simpler to manage than controlling each table individually.

---

> **Concept: search_path**
> When you reference a table without a schema prefix (for example `SELECT * FROM orders` instead of `SELECT * FROM public.orders`), PostgreSQL searches the schemas in your `search_path` in order until it finds the table. The default search_path is `"$user", public`. This means PostgreSQL first looks for a schema with the same name as the current role, then falls back to `public`. You can set search_path per role using ALTER ROLE or per session using SET search_path. Controlling search_path is important for both usability and security - a wrong search_path can cause queries to land on the wrong table.

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

Expected output (yours will differ):

```
psql (16.3)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - Create the dev team role

```sql
CREATE ROLE dev_team NOLOGIN;
```

This creates a group role that cannot log in directly. Individual developer accounts will be made members of this group role and inherit its privileges. `NOLOGIN` makes the intent explicit.

Expected output:

```
CREATE ROLE
```

---

## Step 5 - Create the analytics team role

```sql
CREATE ROLE analytics_team NOLOGIN;
```

Expected output:

```
CREATE ROLE
```

---

## Step 6 - Create individual developer users

```sql
CREATE ROLE dev_alice WITH LOGIN PASSWORD 'devpass123';
```

```sql
CREATE ROLE dev_bob WITH LOGIN PASSWORD 'devpass123';
```

Expected output for each:

```
CREATE ROLE
```

---

## Step 7 - Create an individual analytics user

```sql
CREATE ROLE analyst_carol WITH LOGIN PASSWORD 'analpass123';
```

Expected output:

```
CREATE ROLE
```

---

## Step 8 - Add users to their team groups

```sql
GRANT dev_team TO dev_alice;
```

```sql
GRANT dev_team TO dev_bob;
```

```sql
GRANT analytics_team TO analyst_carol;
```

`GRANT role TO role` adds the second role as a member of the first. Members inherit all non-superuser privileges granted to the group role.

Expected output for each:

```
GRANT ROLE
```

---

## Step 9 - Create the dev team schema

```sql
CREATE SCHEMA dev_schema AUTHORIZATION dev_team;
```

The `AUTHORIZATION` clause sets `dev_team` as the owner of the schema. The owner has full control - they can create objects in it without needing a separate GRANT.

Expected output:

```
CREATE SCHEMA
```

---

## Step 10 - Create the analytics schema

```sql
CREATE SCHEMA analytics_schema AUTHORIZATION analytics_team;
```

Expected output:

```
CREATE SCHEMA
```

---

## Step 11 - Grant USAGE on dev_schema to the dev team

```sql
GRANT USAGE ON SCHEMA dev_schema TO dev_team;
```

`USAGE` allows roles to reference objects inside the schema. Without it, the schema is invisible - even if you know a table exists there, you cannot query it. The owner already has USAGE implicitly, but we grant it explicitly here for group-level inheritance.

Expected output:

```
GRANT
```

---

## Step 12 - Grant CREATE on dev_schema to the dev team

```sql
GRANT CREATE ON SCHEMA dev_schema TO dev_team;
```

`CREATE` on a schema allows the role to create new objects inside it. Granting this to the dev team lets developers create their own tables and views in the dev schema without needing superuser access.

Expected output:

```
GRANT
```

---

## Step 13 - Grant USAGE on analytics_schema to analytics team

```sql
GRANT USAGE ON SCHEMA analytics_schema TO analytics_team;
```

Expected output:

```
GRANT
```

---

## Step 14 - Create a table in dev_schema

```sql
CREATE TABLE dev_schema.feature_flags (
    id          SERIAL PRIMARY KEY,
    flag_name   TEXT NOT NULL UNIQUE,
    enabled     BOOLEAN DEFAULT FALSE,
    updated_at  TIMESTAMPTZ DEFAULT NOW()
);
```

Expected output:

```
CREATE TABLE
```

---

## Step 15 - Create a view in analytics_schema

```sql
CREATE TABLE analytics_schema.daily_revenue (
    report_date DATE NOT NULL,
    total_revenue NUMERIC(12,2),
    order_count INTEGER
);
```

Expected output:

```
CREATE TABLE
```

---

## Step 16 - Set search_path per role

Set dev_alice to look in dev_schema first:

```sql
ALTER ROLE dev_alice SET search_path TO dev_schema, public;
```

Set analyst_carol to look in analytics_schema first:

```sql
ALTER ROLE analyst_carol SET search_path TO analytics_schema, public;
```

This takes effect at the next login. Each developer now automatically lands in their team's schema without needing to prefix every query.

Expected output for each:

```
ALTER ROLE
```

---

## Step 17 - Verify dev_alice can see dev_schema objects

Exit psql and connect as dev_alice:

```sql
\q
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -U dev_alice
```

Check what schemas are visible:

```sql
\dn+
```

Expected output (yours will differ):

```
                          List of schemas
       Name        |    Owner    | Access privileges | Description
-------------------+-------------+-------------------+-------------
 analytics_schema  | analytics_team |                |
 dev_schema        | dev_team    | dev_team=UC/dev_team |
 public            | postgres    | postgres=UC/postgres, =U/postgres |
```

---

## Step 18 - Verify dev_alice can query dev_schema without prefix

```sql
SELECT * FROM feature_flags;
```

Because `search_path` starts with `dev_schema`, the table is found without a schema prefix.

Expected output (yours will differ):

```
 id | flag_name | enabled | updated_at
----+-----------+---------+------------
(0 rows)
```

---

## Step 19 - Verify dev_alice cannot access analytics_schema

```sql
SELECT * FROM analytics_schema.daily_revenue;
```

Expected output:

```
ERROR:  permission denied for schema analytics_schema
```

`dev_alice` is a member of `dev_team` which has no USAGE on `analytics_schema`. The schema boundary enforces the separation.

---

## Step 20 - Exit dev_alice session

```sql
\q
```

---

## Step 21 - Connect back as postgres

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

---

## Step 22 - Grant analytics team read access to public orders table

Sometimes analytics needs to read production data. You grant access at the table level, not the schema level:

```sql
GRANT SELECT ON TABLE public.orders TO analytics_team;
```

Expected output:

```
GRANT
```

---

## Step 23 - Confirm the schema-level check still applies

Even with SELECT on `public.orders`, `analytics_team` must have USAGE on the `public` schema. Check:

```sql
SELECT nspacl FROM pg_namespace WHERE nspname = 'public';
```

Expected output (yours will differ):

```
              nspacl
----------------------------------
 {postgres=UC/postgres,=U/postgres}
```

The `=U/postgres` entry means PUBLIC (all roles) has USAGE on public. So analytics_team can use the public schema and read orders.

---

## Step 24 - List all schema privileges

```sql
SELECT nspname,
       pg_catalog.array_to_string(nspacl, E'\n') AS privileges
FROM pg_catalog.pg_namespace
ORDER BY nspname;
```

This shows the raw ACL for every schema in the database.

Expected output (yours will differ):

```
      nspname       |           privileges
--------------------+---------------------------------
 analytics_schema   | analytics_team=UC/analytics_team
 dev_schema         | dev_team=UC/dev_team
 public             | postgres=UC/postgres           +
                    | =U/postgres
 restricted_data    |
```

The `restricted_data` schema from Build 01 has no grants, so only its owner (postgres) can access it.

---

## Step 25 - Exit psql and return to ec2-user

```sql
\q
```

```bash
exit
```

---

## Summary

| Schema | Owner | USAGE granted to | CREATE granted to |
|--------|-------|-----------------|-------------------|
| dev_schema | dev_team | dev_team | dev_team |
| analytics_schema | analytics_team | analytics_team | (none) |
| public | postgres | PUBLIC | (revoked below in security guides) |
| restricted_data | postgres | (none) | (none) |

---

## Interview Discussion Points

1. **Why create a NOLOGIN group role instead of granting privileges directly to individual users?** - Managing privileges per user does not scale. If you have 10 developers today and hire 5 more next month, you would need to run GRANT statements for every privilege on every object for each new hire. With group roles, you GRANT dev_alice TO dev_team once and Alice inherits all current and future privileges granted to dev_team. Offboarding is equally simple: REVOKE dev_alice FROM dev_team.

2. **What is the difference between USAGE and CREATE on a schema?** - USAGE allows a role to look up objects in the schema - to reference a table, call a function, or use a sequence. Without USAGE, the schema is invisible. CREATE allows a role to add new objects (tables, views, functions) to the schema. A read-only analytics user needs USAGE but not CREATE. A developer building new features needs both.

3. **How does search_path affect security?** - If a malicious function or table with the same name as a system object is placed in a schema that appears earlier in search_path, queries can be hijacked to run against the wrong object. This is called a search_path injection attack. The fix is to set a fully qualified and controlled search_path per role (ALTER ROLE) or to always use schema-qualified names in application code.

4. **Can you grant USAGE on a schema to PUBLIC?** - Yes, and PostgreSQL does this by default for the public schema. It means every role that can connect to the database can see objects in the public schema. This is fine for a single-user or trusted environment but is a security risk in multi-tenant systems. CIS benchmarks recommend revoking CREATE and sometimes USAGE on public from PUBLIC and creating explicit schema grants instead.

5. **What happens if a role has SELECT on a table but no USAGE on its schema?** - The privilege is stored in the catalog but cannot be exercised. Any attempt to access the table results in "permission denied for schema". This is a common source of confusion when migrating tables between schemas - you must re-grant schema USAGE after moving objects.

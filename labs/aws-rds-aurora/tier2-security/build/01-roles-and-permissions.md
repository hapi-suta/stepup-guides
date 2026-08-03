# Build 01 - Roles and Permissions on RDS

**Time:** 35 minutes
**Goal:** Create PostgreSQL roles with least-privilege permissions on your RDS instance.

---

## Before You Start

Read `concepts/security.md` section T2.1 first.

You need:
- A running RDS PostgreSQL instance (from Tier 1)
- psql installed on your local machine or a bastion host
- Your RDS endpoint, master username, and master password

Set these variables now. You will use them throughout the guide.

```bash
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export RDS_PORT="5432"
export RDS_MASTER_USER="postgres"
export RDS_DB="postgres"
```

Replace the values with your actual details.

---

## Step 1 - Connect to Your RDS Instance

Run this command to open a psql session:

```bash
psql \
  --host=$RDS_HOST \
  --port=$RDS_PORT \
  --username=$RDS_MASTER_USER \
  --dbname=$RDS_DB
```

`--host` tells psql which server to connect to.
`--username` is the master user you created when you launched RDS.
`--dbname` is the initial database to connect to.

psql will prompt for a password. Enter your master password.

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, bits: 256, compression: off)
Type "help" for help.

postgres=>
```

Notice the `SSL connection` line. RDS uses SSL by default. Good.

> **Concept:** The `=>` prompt means you are connected as a regular user. If you were a true superuser, you would see `=#`. On RDS, you will always see `=>` because even the master user is not a true superuser.

---

## Step 2 - See What Roles Already Exist

Run this command inside psql:

```sql
\du
```

`\du` is a psql shortcut that lists all database roles.

Expected output (yours will differ):

```
                                   List of roles
 Role name │            Attributes            │           Member of
───────────┼──────────────────────────────────┼──────────────────────────
 postgres  │ Create role, Create DB           │ {rds_superuser}
 rds_superuser │ Cannot login                 │ {}
 rdsadmin  │ Superuser, Create role, ...      │ {}
```

The `rdsadmin` role is used internally by AWS. Do not modify it.
The `postgres` user (your master user) is a member of `rds_superuser`.

---

## Step 3 - Understand rds_superuser

Run this to see exactly what privileges rds_superuser provides:

```sql
SELECT rolname, rolsuper, rolcreaterole, rolcreatedb, rolreplication
FROM pg_roles
WHERE rolname IN ('rds_superuser', 'postgres', 'rdsadmin');
```

Expected output (yours will differ):

```
    rolname    │ rolsuper │ rolcreaterole │ rolcreatedb │ rolreplication
───────────────┼──────────┼───────────────┼─────────────┼────────────────
 rds_superuser │ f        │ f             │ f           │ f
 postgres      │ f        │ t             │ t           │ f
 rdsadmin      │ t        │ t             │ t           │ t
```

Notice `rds_superuser` has `rolsuper = f` (false). It is not a true superuser. AWS restricts it intentionally.

> **Concept:** On a self-managed PostgreSQL server, `rolsuper = t` means "can do anything." On RDS, AWS prevents this and gives you `rds_superuser` instead, which has most DBA capabilities but cannot access OS-level features.

---

## Step 4 - Create an Application Role (Least Privilege)

First, create the application database:

```sql
CREATE DATABASE appdb;
```

Now connect to it:

```sql
\c appdb
```

Create a schema for the application:

```sql
CREATE SCHEMA app;
```

Create a table to test with:

```sql
CREATE TABLE app.orders (
    id SERIAL PRIMARY KEY,
    customer_name TEXT NOT NULL,
    amount NUMERIC(10,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

Now create the application role:

```sql
CREATE ROLE app_user WITH LOGIN PASSWORD 'StrongPass1!';
```

`CREATE ROLE` creates a new role.
`WITH LOGIN` allows this role to log in as a user.
`PASSWORD` sets the initial password.

Grant only what the app needs:

```sql
GRANT CONNECT ON DATABASE appdb TO app_user;
```

This lets the role connect to the database. Without this, nothing else matters.

```sql
GRANT USAGE ON SCHEMA app TO app_user;
```

`USAGE` on a schema lets the role see and access objects inside it. Without this, the role cannot reach any tables.

```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_user;
```

This grants read and write access on all current tables in the `app` schema.

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_user;
```

`ALTER DEFAULT PRIVILEGES` means any new table created in the `app` schema will automatically get these grants. Without this, new tables would be inaccessible.

```sql
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_user;
```

Sequences power SERIAL columns (like the `id` column). The app needs this to insert rows.

---

## Step 5 - Verify the Application Role

Open a second terminal and test the new role:

```bash
psql \
  --host=$RDS_HOST \
  --port=$RDS_PORT \
  --username=app_user \
  --dbname=appdb
```

Enter the password `StrongPass1!` when prompted.

Test that it can insert:

```sql
INSERT INTO app.orders (customer_name, amount) VALUES ('Test Customer', 99.99);
```

Expected output:

```
INSERT 0 1
```

Test that it can select:

```sql
SELECT * FROM app.orders;
```

Expected output (yours will differ):

```
 id │ customer_name  │ amount │          created_at
────┼────────────────┼────────┼──────────────────────────────
  1 │ Test Customer  │  99.99 │ 2024-01-15 14:23:11.456789+00
```

Test that it CANNOT drop tables (it should not be able to):

```sql
DROP TABLE app.orders;
```

Expected output:

```
ERROR:  must be owner of table orders
```

Good. The app user cannot drop tables.

---

## Step 6 - Create a Read-Only Role

Go back to your master user session. Create a read-only role:

```sql
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'ReadOnly1!';
```

```sql
GRANT CONNECT ON DATABASE appdb TO readonly_user;
```

```sql
GRANT USAGE ON SCHEMA app TO readonly_user;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA app TO readonly_user;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
GRANT SELECT ON TABLES TO readonly_user;
```

Verify it cannot insert:

```bash
psql \
  --host=$RDS_HOST \
  --port=$RDS_PORT \
  --username=readonly_user \
  --dbname=appdb \
  --command="INSERT INTO app.orders (customer_name, amount) VALUES ('Hack', 0);"
```

Expected output:

```
ERROR:  permission denied for table orders
```

---

## Step 7 - Create a Group Role (Recommended Pattern)

Instead of granting permissions to individual users, create a group role. Then add users to the group.

```sql
CREATE ROLE app_readwrite NOLOGIN;
```

`NOLOGIN` means this role is a group - it cannot log in directly.

```sql
GRANT USAGE ON SCHEMA app TO app_readwrite;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_readwrite;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA app TO app_readwrite;
```

Create a user and add them to the group:

```sql
CREATE ROLE alice WITH LOGIN PASSWORD 'AlicePass1!';
GRANT app_readwrite TO alice;
```

```sql
CREATE ROLE bob WITH LOGIN PASSWORD 'BobPass1!';
GRANT app_readwrite TO bob;
```

Now if you need to revoke access for Alice:

```sql
REVOKE app_readwrite FROM alice;
```

You do not need to touch any table-level grants. The group handles it.

> **Concept:** This is the "role as group" pattern. It is the standard way to manage permissions in PostgreSQL shops. Think of `app_readwrite` like an Active Directory group.

---

## Step 8 - Audit Permissions

To see what privileges a role has on tables:

```sql
SELECT grantee, table_schema, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE grantee IN ('app_user', 'readonly_user', 'alice', 'bob')
ORDER BY grantee, table_name;
```

Expected output (yours will differ):

```
   grantee    │ table_schema │ table_name │ privilege_type
──────────────┼──────────────┼────────────┼────────────────
 app_user     │ app          │ orders     │ DELETE
 app_user     │ app          │ orders     │ INSERT
 app_user     │ app          │ orders     │ SELECT
 app_user     │ app          │ orders     │ UPDATE
 readonly_user│ app          │ orders     │ SELECT
```

---

## Step 9 - Console Reference

The AWS Console does not manage PostgreSQL roles directly - that is done through psql. However, you can view your instance's master user in the Console.

1. Open the AWS Console in your browser
2. Search for **RDS** in the top search bar
3. Click **Databases** in the left sidebar
4. Click your database instance name
5. Scroll down to **Configuration**
6. Find the **Master username** field

This shows you the master user name. You cannot see the password here. If you forgot it, you must reset it from the Console under **Modify**.

---

## Step 10 - CLI Reference

To reset the master password from the CLI:

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --master-user-password "NewStrongPassword1!" \
  --apply-immediately \
  --region [REGION]
```

`--db-instance-identifier` is the name you gave your RDS instance (not the endpoint).
`--master-user-password` sets the new password.
`--apply-immediately` applies the change now instead of during the next maintenance window.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-db",
        "DBInstanceStatus": "modifying",
        ...
    }
}
```

---

## What You Built

- A dedicated `appdb` database with an `app` schema
- An `app_user` role with INSERT/UPDATE/DELETE/SELECT (not more)
- A `readonly_user` role with SELECT only
- A group role (`app_readwrite`) pattern for scalable permission management
- An audit query to review granted privileges

---

## Clean Up (Optional)

If you want to remove what you created:

```sql
-- Run as master user in the postgres database
REVOKE ALL ON DATABASE appdb FROM app_user, readonly_user;
DROP ROLE alice;
DROP ROLE bob;
DROP ROLE app_user;
DROP ROLE readonly_user;
DROP ROLE app_readwrite;
DROP DATABASE appdb;
```

---

## Key Rules to Remember

1. Never grant more than an application needs
2. Use group roles - not direct table grants to individual users
3. Always set `ALTER DEFAULT PRIVILEGES` or new tables will be inaccessible
4. The master user should not be the application user
5. `GRANT ALL` is almost never the right answer

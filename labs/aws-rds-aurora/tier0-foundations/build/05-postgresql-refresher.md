# Tier 0 - Foundations
## Guide 05: PostgreSQL Refresher

**Objective:** Review the PostgreSQL object hierarchy, roles and privileges, essential psql commands, basic SQL, and how to construct a connection string - so you are ready to connect to and work with RDS and Aurora PostgreSQL in later modules.
**Time:** 25 minutes
**Prerequisites:** PostgreSQL installed locally, OR access to any running PostgreSQL instance. Students who completed prior SUTA PostgreSQL modules can skim this guide as a review.
**Infrastructure:** A local or accessible PostgreSQL instance. No AWS infrastructure needed.

---

## 1. The PostgreSQL Object Hierarchy

PostgreSQL organizes everything into a clear hierarchy. Understanding this hierarchy prevents a lot of confusion when you start working with RDS and Aurora.

```
Cluster
  └── Database
        └── Schema
              └── Table (and other objects: views, functions, sequences, etc.)
```

### Cluster

A PostgreSQL **cluster** is a single running PostgreSQL instance. It is one `postgres` process managing one data directory. On RDS, each RDS instance is one cluster.

When you launch one RDS instance, you get one cluster. When you have three RDS instances (primary + 2 read replicas), you have three clusters - though the replicas are copies of the primary's data.

### Database

Inside a cluster, you can have multiple **databases**. Each database is completely isolated from others in the same cluster. A connection to database `app_db` cannot query tables in database `reporting_db` without explicitly connecting to `reporting_db`.

On a fresh PostgreSQL install, there are three system databases: `postgres`, `template0`, and `template1`. You create your application databases on top.

### Schema

A **schema** is a namespace inside a database. It groups related objects together. The default schema is called `public`.

A table's full name in PostgreSQL is: `schema_name.table_name`. For example, `public.users` or `reporting.monthly_summary`.

Using schemas helps you:
- Organize tables by function or team
- Apply permissions at the schema level
- Avoid naming conflicts (two schemas can have tables with the same name)

### Table

A **table** is where your data lives. Tables belong to a schema, which belongs to a database, which belongs to a cluster.

Other objects - views, functions, sequences, indexes - follow the same hierarchy.

---

## 2. Roles and Privileges

PostgreSQL uses the term **role** for both users and groups. The difference is cosmetic: a role with the `LOGIN` attribute is a user. A role without `LOGIN` is a group role used for organizing permissions.

### Creating a role (user)

```sql
CREATE ROLE app_user WITH LOGIN PASSWORD 'strongpassword123';
```

This creates a role named `app_user` that can log in with a password.
- `WITH LOGIN` - allows this role to connect to the database
- `PASSWORD` - sets the login password

### Creating a read-only role for a team

```sql
CREATE ROLE readonly_role;
```

```sql
GRANT CONNECT ON DATABASE app_db TO readonly_role;
```

```sql
GRANT USAGE ON SCHEMA public TO readonly_role;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_role;
```

```sql
GRANT readonly_role TO analyst_user;
```

This creates a group role `readonly_role`, grants it read access to all tables in the `public` schema, then assigns that role to `analyst_user`. The user inherits the role's privileges.

### Key privilege commands

| Command | What It Does |
|---------|-------------|
| `GRANT SELECT ON table TO role` | Allows `SELECT` on a specific table |
| `GRANT ALL ON table TO role` | Allows all operations on a table |
| `REVOKE INSERT ON table FROM role` | Removes `INSERT` from a role |
| `GRANT USAGE ON SCHEMA s TO role` | Allows access to objects inside schema `s` |
| `GRANT CONNECT ON DATABASE d TO role` | Allows connecting to database `d` |

### The `postgres` superuser

On a fresh PostgreSQL install, `postgres` is the default superuser. On RDS and Aurora, you do not get the true `postgres` superuser - AWS provides an admin user (which you name during instance creation, often called `postgres` or `admin`) with almost all superuser privileges. A small set of OS-level superuser actions are not available on RDS.

---

## 3. Connecting to PostgreSQL with psql

`psql` is the official PostgreSQL command-line client. You will use it constantly when working with RDS and Aurora.

### The basic connection command

```bash
psql -h hostname -p 5432 -U username -d database_name
```

What each flag means:
- `-h` - the host (IP address or hostname of the PostgreSQL server)
- `-p` - the port (PostgreSQL defaults to 5432; specify if different)
- `-U` - the username to connect as
- `-d` - the name of the database to connect to

If you omit `-d`, psql tries to connect to a database with the same name as your username.
If you omit `-p`, psql uses port 5432.
If you omit `-h`, psql connects via a Unix socket to the local instance (only works when running on the same server).

### Example: connect to a local instance

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```

psql will prompt you for a password after you run this command.

Expected output (yours will differ):
```
Password for user postgres:
psql (16.2)
Type "help" for help.

postgres=#
```

The `postgres=#` prompt means you are connected to the `postgres` database as the `postgres` user. The `#` indicates superuser. A regular user sees `=>` instead.

### Using a connection string (URI format)

psql also accepts connection strings in URI format:

```bash
psql "postgresql://username:password@hostname:5432/database_name"
```

This format is common in application configuration and is what you will see in RDS connection examples. The structure:
- `postgresql://` - the protocol
- `username:password` - credentials
- `hostname:5432` - host and port
- `/database_name` - the target database

For RDS, this looks like:

```bash
psql "postgresql://postgres:yourpassword@mydb.c9abcdefgh.us-east-1.rds.amazonaws.com:5432/postgres"
```

---

## 4. Essential psql Meta-Commands

Once inside psql, you use meta-commands (prefixed with `\`) to explore the database. These are not SQL - they are psql-specific shortcuts.

### List databases in the cluster

```
\l
```

Expected output (yours will differ):
```
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
-----------+----------+----------+-------------+-------------+-----------------------
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
           |          |          |             |             | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
...
```

### Switch to a different database

```
\c database_name
```

This changes your connection to `database_name` without leaving psql. You stay in the same psql session.

Expected output (yours will differ):
```
You are now connected to database "app_db" as user "postgres".
```

### List tables in the current schema

```
\dt
```

Expected output (yours will differ):
```
          List of relations
 Schema |  Name   | Type  |  Owner
--------+---------+-------+----------
 public | orders  | table | postgres
 public | users   | table | postgres
...
```

### Describe a table's structure

```
\d tablename
```

Expected output (yours will differ):
```
                        Table "public.users"
   Column    |          Type          | Collation | Nullable |      Default
-------------+------------------------+-----------+----------+-------------------
 id          | integer                |           | not null | nextval('users_id_seq'::regclass)
 email       | character varying(255) |           | not null |
 created_at  | timestamp              |           |          | now()
Indexes:
    "users_pkey" PRIMARY KEY, btree (id)
...
```

### List all roles (users)

```
\du
```

Expected output (yours will differ):
```
                                   List of roles
 Role name  |                         Attributes                         | Member of
------------+-------------------------------------------------------------+-----------
 postgres   | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 app_user   |                                                             | {}
...
```

### List schemas

```
\dn
```

Expected output (yours will differ):
```
  List of schemas
  Name  |  Owner
--------+----------
 public | postgres
...
```

### Show current connection info

```
\conninfo
```

Expected output (yours will differ):
```
You are connected to database "postgres" as user "postgres" on host "127.0.0.1" at port "5432".
```

This is useful when you have multiple psql sessions open and need to confirm which database and server you are connected to.

### Quit psql

```
\q
```

---

## 5. Basic SQL You Need to Know

These are the SQL operations you will use most often when managing and testing your RDS and Aurora databases.

### Create a database

```sql
CREATE DATABASE app_db;
```

On RDS, you can also create databases via the AWS Console or CLI, but creating them with SQL inside psql is the most common method.

### Connect to the new database

```
\c app_db
```

### Create a schema

```sql
CREATE SCHEMA IF NOT EXISTS reporting;
```

The `IF NOT EXISTS` guard prevents an error if the schema already exists. Use this in scripts so they are idempotent (safe to run more than once).

### Create a table

```sql
CREATE TABLE IF NOT EXISTS public.users (
    id          SERIAL PRIMARY KEY,
    email       VARCHAR(255) NOT NULL UNIQUE,
    full_name   VARCHAR(255),
    created_at  TIMESTAMP DEFAULT NOW()
);
```

Breaking down the columns:
- `id SERIAL PRIMARY KEY` - auto-incrementing integer, unique identifier for each row
- `email VARCHAR(255) NOT NULL UNIQUE` - up to 255 characters, must be present, must be unique
- `full_name VARCHAR(255)` - optional text field
- `created_at TIMESTAMP DEFAULT NOW()` - automatically set to current time on insert

### Insert data

```sql
INSERT INTO public.users (email, full_name)
VALUES ('alice@example.com', 'Alice Okoye');
```

```sql
INSERT INTO public.users (email, full_name)
VALUES ('bob@example.com', 'Bob Mensah');
```

### Select data

```sql
SELECT * FROM public.users;
```

Expected output (yours will differ):
```
 id |       email        |   full_name   |         created_at
----+--------------------+---------------+----------------------------
  1 | alice@example.com  | Alice Okoye   | 2026-05-30 10:15:23.123456
  2 | bob@example.com    | Bob Mensah    | 2026-05-30 10:15:25.654321
(2 rows)
```

Filter results with a WHERE clause:

```sql
SELECT id, email FROM public.users WHERE full_name = 'Alice Okoye';
```

### Update data

```sql
UPDATE public.users
SET full_name = 'Alice O. Okoye'
WHERE email = 'alice@example.com';
```

Always include a `WHERE` clause in UPDATE statements. Without one, every row in the table gets updated.

### Delete data

```sql
DELETE FROM public.users
WHERE email = 'bob@example.com';
```

Always include a `WHERE` clause in DELETE statements. Without one, every row in the table is deleted.

### Drop a table

```sql
DROP TABLE IF EXISTS public.users;
```

The `IF EXISTS` guard prevents an error if the table does not exist.

---

## 6. Checking What Is in the Database

These queries use PostgreSQL system catalogs - built-in tables that store metadata about your database objects.

### List all tables in all schemas

```sql
SELECT schemaname, tablename, tableowner
FROM pg_tables
WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
ORDER BY schemaname, tablename;
```

This shows your application tables while filtering out PostgreSQL's internal system tables.

### Check table size

```sql
SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
WHERE relkind = 'r'
  AND relnamespace = 'public'::regnamespace
ORDER BY pg_total_relation_size(oid) DESC;
```

`pg_size_pretty` formats bytes into human-readable units (KB, MB, GB). This is a query you will run regularly on RDS to understand which tables are consuming the most storage.

### Check active connections

```sql
SELECT pid, usename, application_name, client_addr, state, query
FROM pg_stat_activity
WHERE state IS NOT NULL;
```

On RDS, connection limits are set by instance class. This query lets you see who is connected and what they are doing.

---

## 7. Practice Exercise

Run these steps from start to finish to confirm you can navigate PostgreSQL on your local instance.

### Step 1: Connect to your local PostgreSQL

```bash
psql -h 127.0.0.1 -p 5432 -U postgres -d postgres
```

### Step 2: Create a practice database

```sql
CREATE DATABASE suta_practice;
```

### Step 3: Switch to it

```
\c suta_practice
```

### Step 4: Create a table

```sql
CREATE TABLE IF NOT EXISTS public.students (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    module      VARCHAR(50),
    enrolled_at TIMESTAMP DEFAULT NOW()
);
```

### Step 5: Insert some rows

```sql
INSERT INTO public.students (name, module) VALUES ('Amara Diallo', 'aws-rds-aurora');
```

```sql
INSERT INTO public.students (name, module) VALUES ('Kofi Asante', 'aws-rds-aurora');
```

### Step 6: Query the data

```sql
SELECT * FROM public.students;
```

### Step 7: Describe the table

```
\d public.students
```

### Step 8: Update a row

```sql
UPDATE public.students SET module = 'aws-rds-aurora-tier0' WHERE name = 'Amara Diallo';
```

### Step 9: Verify the update

```sql
SELECT name, module FROM public.students;
```

### Step 10: Clean up and exit

```sql
DROP TABLE IF EXISTS public.students;
```

```
\q
```

If all 10 steps worked without errors, you are ready for the next tier.

---

## Summary

- The PostgreSQL object hierarchy is: cluster (instance) > database > schema > table.
- Roles are used for both users (with `LOGIN`) and groups (without `LOGIN`). Privileges are granted to roles.
- `psql` connects with `-h host -p port -U user -d database` or via a URI connection string.
- Key psql meta-commands: `\l` (list databases), `\c` (switch database), `\dt` (list tables), `\d tablename` (describe table), `\du` (list roles), `\conninfo` (show connection), `\q` (quit).
- Core SQL operations: `CREATE`, `INSERT`, `SELECT`, `UPDATE`, `DELETE`, `DROP` - always use `WHERE` clauses on UPDATE and DELETE.
- The `pg_stat_activity` view shows active connections - essential for RDS connection troubleshooting.
- Everything you practiced here applies directly to RDS and Aurora - the SQL and psql commands are identical.

**Next:** Tier 1 - Getting Started with RDS (Guide 01: Launching Your First RDS Instance)

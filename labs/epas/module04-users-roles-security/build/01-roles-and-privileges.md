---
layout: default
title: "Build 01 - Roles and privileges"
parent: "Module 04 - Users, Roles, and Security"
nav_order: 2
locked: "no"
---

# BUILD 01 - Roles and privileges

You will create a login user and a group role, make the user a member of the group,
grant the group read access to a table, and prove that the privilege flows through
membership - then prove the user cannot do what it was not granted. Every command was
run on a live EPAS 16 instance and shows its real output.

Remember the model from Concepts: a **role** is both a user and a group. `CREATE USER`
is `CREATE ROLE ... LOGIN`. Privileges are granted to a group role and inherited by its
members.

## 1. Connect as the superuser

You do this work as the bootstrap superuser, `enterprisedb`.

First switch to the `enterprisedb` OS user.

On **epas-single**, as **ec2-user**:

```bash
sudo -iu enterprisedb
```

- `-iu enterprisedb` starts a login shell as the `enterprisedb` account.

Now open the client. Still as **enterprisedb** on **epas-single**:

```bash
/usr/edb/as16/bin/edb-psql -p 5444 -d edb
```

- `-p 5444` - EPAS's port (not 5432).
- `-d edb` - the default database.

You are at the `edb=#` prompt for the rest of this guide.

## 2. Create a group role and a login user

Create a group role first. It has no password and cannot log in - it exists only to
hold privileges.

At the `edb=#` prompt:

```sql
CREATE ROLE app_read NOLOGIN;
```

- `NOLOGIN` - this role is a group, not a login account.

Expected output (yours will differ):

```
CREATE ROLE
```

Now create a login user with a password:

```sql
CREATE USER app_service WITH LOGIN PASSWORD 'AppPass_2026';
```

- `CREATE USER` is shorthand for `CREATE ROLE ... LOGIN`.
- `PASSWORD '...'` - EPAS stores it hashed (SCRAM by default); it is never kept in
  clear text.

```
CREATE ROLE
```

Note EPAS reports `CREATE ROLE` even for `CREATE USER` - a reminder that they are the
same object underneath.

## 3. List the roles you just made

Use the `\du` meta-command with a pattern to see only your new roles:

```
edb=# \du app_*
```

Expected output (yours will differ):

```
             List of roles
  Role name   |       Attributes
--------------+-------------------------
 app_read     | Cannot login           +
              | Profile default
 app_service  | Profile default
```

`app_read` shows **Cannot login** (it is a group); `app_service` shows no restriction
(it can log in). Both show **Profile default** - you will change that in Build 02.

## 4. Make the user a member of the group

Grant the group role to the login user. This is Oracle's "grant a role to a user."

```sql
GRANT app_read TO app_service;
```

- After this, `app_service` **inherits** every privilege held by `app_read`.

```
GRANT ROLE
```

## 5. Grant the group a privilege on a table

For something to grant, create a small table (any schema you own works; here we use a
schema called `app`).

```sql
CREATE SCHEMA app;
```

```sql
CREATE TABLE app.orders (id int PRIMARY KEY, owner text, amount numeric);
```

```sql
INSERT INTO app.orders VALUES (1,'alice',100),(2,'bob',200),(3,'alice',300);
```

Now grant the group role read access. Remember: `USAGE` on the schema is a
prerequisite for any table access inside it.

```sql
GRANT USAGE ON SCHEMA app TO app_read;
```

```sql
GRANT SELECT ON app.orders TO app_read;
```

Each grant reports:

```
GRANT
```

## 6. Prove the privilege flows through membership

You are connected as the superuser. To test as the app user without logging out, use
`SET ROLE` - it makes the current session act as that role, dropping superuser powers.

```sql
SET ROLE app_service;
```

```sql
SELECT count(*) FROM app.orders;
```

Expected output (yours will differ):

```
 count
-------
     3
(1 row)
```

`app_service` was never granted anything directly - it can read because it is a member
of `app_read`, which holds the `SELECT`. That is inheritance doing its job.

## 7. Prove it cannot do what it was not granted

Still acting as `app_service`, try to write:

```sql
INSERT INTO app.orders VALUES (9,'x',1);
```

Expected output (yours will differ):

```
ERROR:  permission denied for table orders
```

Exactly right - `app_read` holds only `SELECT`, so its members can read and nothing
more. Return to being the superuser:

```sql
RESET ROLE;
```

## 8. Read the resulting ACL

Look at the privileges on the table with `\dp` (display privileges):

```
edb=# \dp app.orders
```

Expected output (yours will differ):

```
                                     Access privileges
 Schema |  Name  | Type  |         Access privileges         | Column privileges | Policies
--------+--------+-------+-----------------------------------+-------------------+----------
 app    | orders | table | enterprisedb=arwdDxt/enterprisedb+|                   |
        |        |       | app_read=r/enterprisedb           |                   |
```

Read the ACL string `app_read=r/enterprisedb` as: role **app_read** has **r**
(SELECT), **granted by** enterprisedb. The owner line
`enterprisedb=arwdDxt/enterprisedb` lists every privilege (a=INSERT, r=SELECT,
w=UPDATE, d=DELETE, and so on).

## 9. Inspect role attributes in the catalog

Attributes (the account's powers) live in `pg_roles`, not in the ACL. Look at your two
roles plus their attributes:

```sql
SELECT rolname, rolcanlogin, rolcreatedb, rolsuper, rolbypassrls
FROM pg_roles WHERE rolname LIKE 'app\_%' ORDER BY 1;
```

Expected output (yours will differ):

```
   rolname   | rolcanlogin | rolcreatedb | rolsuper | rolbypassrls
-------------+-------------+-------------+----------+--------------
 app_read    | f           | f           | f        | f
 app_service | t           | f           | f        | f
(2 rows)
```

`rolcanlogin` is the only difference - `app_service` (t) can log in, `app_read` (f)
cannot. Neither is a superuser, can create databases, or bypasses RLS. Those columns
are the attributes from Concepts.

## 10. Clean up

This guide's objects are throwaway. Remove them so the next guide starts clean.

```sql
DROP TABLE app.orders;
```

```sql
DROP SCHEMA app;
```

```sql
DROP ROLE app_service;
```

```sql
DROP ROLE app_read;
```

Leave the client with `\q`, then return to `ec2-user`:

```
edb=# \q
```

```bash
exit
```

## What you did

You created a group role and a login user, joined them with `GRANT ... TO`, and watched
a `SELECT` granted once to the group become usable by its member - while an `INSERT`
that was never granted stayed denied. You read the ACL with `\dp` and the attributes
with `pg_roles`. This membership-and-inheritance pattern - grant to a group role, add
users as members - is how you keep access manageable when there are fifty users and two
hundred tables, instead of granting object by object.

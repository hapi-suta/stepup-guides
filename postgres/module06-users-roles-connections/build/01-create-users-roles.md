# Build 01 - Create Users and Roles

**Module:** 06 - Users, Roles & Connections
**Node:** NODE1 only
**Time:** 25 minutes

---

## What You Will Learn

- The difference between a role and a user in PostgreSQL
- How to create roles with specific attributes
- How to create the three application roles used throughout this module
- How to modify and remove roles

---

> **Concept: Roles vs Users**
> In PostgreSQL, there is no separate "user" object. A user is just a role that has the LOGIN attribute. The commands CREATE USER and CREATE ROLE both create roles - CREATE USER simply adds LOGIN by default. Everything else is the same. This means all privilege management, including group membership, uses the same role system for both human users and application accounts.

---

> **Concept: Role Attributes vs Privileges**
> Role attributes (SUPERUSER, CREATEDB, CREATEROLE, LOGIN, REPLICATION) control what the role can do at the cluster level - things like creating databases or logging in. Privileges (GRANT SELECT ON TABLE ...) control what the role can do inside databases. These are two separate systems. A role can have no attributes but still have extensive privileges inside a specific database.

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

This switches you to the `postgres` operating system account. The `-i` flag gives you a login shell, which loads the correct environment. The `-u postgres` flag specifies the target user.

---

## Step 3 - Connect to PostgreSQL

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

The full path is required because `/usr/pgsql-16/bin` is not in the default PATH on this server. The `-p 5432` flag specifies the port. The `-d stepup_store` flag selects the database.

Expected output (yours will differ):

```
psql (16.3)
Type "help" for help.

stepup_store=#
```

---

## Step 4 - View existing roles

```bash
\du
```

This psql meta-command lists all roles in the cluster and their attributes.

Expected output (yours will differ):

```
                                   List of roles
 Role name |                         Attributes
-----------+------------------------------------------------------------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS
```

---

## Step 5 - Create the app_user role

```sql
CREATE ROLE app_user WITH LOGIN PASSWORD 'apppass123' CONNECTION LIMIT 20;
```

This creates a role that:
- `LOGIN` - can open a database connection
- `PASSWORD 'apppass123'` - requires password authentication
- `CONNECTION LIMIT 20` - caps concurrent connections from this role at 20

Expected output:

```
CREATE ROLE
```

---

> **Concept: LOGIN attribute**
> Without LOGIN, a role cannot open a connection. Such roles are used as "group roles" - you grant privileges to the group role, then add users as members. This is the recommended pattern for managing privileges at scale. The group role never connects directly; member roles inherit its privileges when they log in.

---

## Step 6 - Create the readonly_user role

```sql
CREATE ROLE readonly_user WITH LOGIN PASSWORD 'readpass123';
```

This role will only be able to read data. The privileges will be set in Build 03. For now this just creates the login-capable role.

Expected output:

```
CREATE ROLE
```

---

## Step 7 - Create the admin_user role

```sql
CREATE ROLE admin_user WITH LOGIN PASSWORD 'adminpass123' CREATEDB CREATEROLE;
```

This creates a role with two additional attributes:
- `CREATEDB` - can create new databases
- `CREATEROLE` - can create, alter, and drop other roles (but not superuser roles)

Expected output:

```
CREATE ROLE
```

---

## Step 8 - View the new roles

```bash
\du
```

Expected output (yours will differ):

```
                                   List of roles
 Role name     |                         Attributes
---------------+------------------------------------------------------------
 admin_user    | Create role, Create DB
 app_user      | 20 connections
 postgres      | Superuser, Create role, Create DB, Replication, Bypass RLS
 readonly_user |
```

---

## Step 9 - Check the REPLICATION attribute

The `REPLICATION` attribute allows a role to connect in replication mode and use streaming replication. This is required for standby servers. You should only grant this to roles that genuinely need it.

```sql
CREATE ROLE replication_user WITH LOGIN REPLICATION PASSWORD 'replpass123';
```

Expected output:

```
CREATE ROLE
```

---

## Step 10 - Modify a role with ALTER ROLE

Change the connection limit on app_user:

```sql
ALTER ROLE app_user CONNECTION LIMIT 10;
```

The `ALTER ROLE` command changes any attribute of an existing role. You can also use it to set passwords, rename roles, or change LOGIN status.

Expected output:

```
ALTER ROLE
```

---

## Step 11 - Rename a role

```sql
ALTER ROLE replication_user RENAME TO repl_user;
```

Expected output:

```
ALTER ROLE
```

---

## Step 12 - Set a role's search_path

```sql
ALTER ROLE app_user SET search_path TO public;
```

This sets a default `search_path` for the role. Every time `app_user` connects, PostgreSQL will use this search path automatically. This is useful for ensuring the application always looks in the right schema.

Expected output:

```
ALTER ROLE
```

---

## Step 13 - Drop the replication role

```sql
DROP ROLE repl_user;
```

You can only drop a role that owns no objects and has no privileges. If you try to drop a role that still owns tables or has been granted privileges, PostgreSQL will return an error listing the dependencies.

Expected output:

```
DROP ROLE
```

---

## Step 14 - Use SUPERUSER attribute (observe, do not leave enabled)

The `SUPERUSER` attribute bypasses all permission checks. It should only be granted for administrative work and only to trusted operators. Never use it as the application role.

```sql
CREATE ROLE dba_temp WITH LOGIN SUPERUSER PASSWORD 'temppass123';
```

```sql
\du dba_temp
```

Expected output (yours will differ):

```
                   List of roles
 Role name |            Attributes
-----------+----------------------------------
 dba_temp  | Superuser
```

Drop it immediately after observing:

```sql
DROP ROLE dba_temp;
```

---

## Step 15 - Exit psql and return to ec2-user

```bash
\q
```

```bash
exit
```

---

## Summary

You created three roles that will be used across this entire module:

| Role | LOGIN | CREATEDB | CREATEROLE | CONNECTION LIMIT |
|------|-------|----------|------------|-----------------|
| app_user | yes | no | no | 10 |
| readonly_user | yes | no | no | unlimited |
| admin_user | yes | yes | yes | unlimited |

The privilege grants (GRANT SELECT, etc.) happen in Build 03.

---

## Interview Discussion Points

1. **What is the difference between CREATE ROLE and CREATE USER?** - CREATE USER is shorthand for CREATE ROLE WITH LOGIN. Both produce a role object in pg_roles. Historically there was a separate user catalog, but PostgreSQL unified users and groups into roles starting in version 8.1.

2. **Can you grant the same privilege to multiple roles at once?** - No, not with a single GRANT statement. You must GRANT to each role individually, or you can use a group role: grant the privilege to the group role, then add members to that group role using GRANT group_role TO member_role.

3. **What happens if you try to DROP a role that owns objects?** - PostgreSQL returns an error: "role cannot be dropped because some objects depend on it." You must either DROP OWNED BY rolename (which removes all owned objects and privileges) or REASSIGN OWNED BY rolename TO another_role before dropping.

4. **What does BYPASSRLS mean?** - BYPASSRLS (Bypass Row Level Security) allows the role to see all rows in tables that have RLS enabled, regardless of any policies. Superusers have this by default. Regular roles see only the rows permitted by active policies. You should only grant BYPASSRLS to trusted administrative roles.

5. **How does CREATEROLE interact with SUPERUSER roles?** - A role with CREATEROLE cannot create or alter superuser roles. It can only create roles with privileges up to its own privilege level. This prevents privilege escalation - a CREATEROLE user cannot bootstrap their way to SUPERUSER.

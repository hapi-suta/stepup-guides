# Security, Privileges, and Row Level Security

## Why This Module Matters

A misconfigured database is an open door. PostgreSQL ships secure by default - it denies
everything until you explicitly allow it. Understanding the authentication and authorization
layers lets you grant exactly the access needed and nothing more.

---

## The Authentication Flow

When a client connects to PostgreSQL, three things happen in order:

```
Client connects
    |
    v
+-------------------+
| 1. pg_hba.conf    |  <-- WHO can connect, FROM WHERE, using WHAT method?
+-------------------+
    |
    v
+-------------------+
| 2. Password check |  <-- Does the credential match? (if method requires it)
+-------------------+
    |
    v
+-------------------+
| 3. Authorization  |  <-- What is this role allowed to do?
+-------------------+
```

### Step 1 - pg_hba.conf (Host-Based Authentication)

This file controls which connections are allowed before any password is checked.
Each line is a rule. PostgreSQL reads top to bottom and uses the first match.

```
# TYPE    DATABASE    USER        ADDRESS           METHOD
local     all         postgres                      peer
host      appdb       appuser     10.0.1.0/24       scram-sha-256
host      all         all         0.0.0.0/0         reject
```

Key fields:
- **TYPE** - `local` (Unix socket) or `host` (TCP/IP)
- **DATABASE** - which database this rule applies to, or `all`
- **USER** - which role this rule applies to, or `all`
- **ADDRESS** - CIDR range for TCP connections (not used for `local`)
- **METHOD** - how to authenticate: `peer`, `scram-sha-256`, `md5`, `cert`, `reject`

Common methods:
- **peer** - OS username must match PostgreSQL role name. Only works for local connections.
- **scram-sha-256** - salted challenge-response. The modern standard. Use this.
- **md5** - legacy hashing. Weaker than scram. Avoid for new setups.
- **cert** - client must present a valid TLS certificate. Strongest option.
- **trust** - no password required. Never use in production.
- **reject** - deny the connection outright.

### Step 2 - Password Verification

If pg_hba.conf specifies a password-based method (scram-sha-256, md5), PostgreSQL
checks the stored credential in `pg_authid`. The password was set with:

```sql
ALTER ROLE appuser PASSWORD 'some_password';
```

With `scram-sha-256`, the password is never sent in cleartext - even over the network.
The client proves it knows the password using a challenge-response protocol.

### Step 3 - Authorization

After authentication succeeds, PostgreSQL checks what the role is allowed to do.
Every SQL statement is checked against the privilege system before execution.

---

## Roles in PostgreSQL

PostgreSQL has one concept for both users and groups: **roles**.

### Login Roles vs Group Roles

```sql
-- Login role: can connect to the database
CREATE ROLE appuser LOGIN PASSWORD 'secret';

-- Group role: cannot connect, used to bundle privileges
CREATE ROLE readonly;

-- Grant group membership
GRANT readonly TO appuser;
```

A login role is just a role with the LOGIN attribute. A group role is a role without it.
There is no separate CREATE USER vs CREATE GROUP under the hood - CREATE USER is an
alias for CREATE ROLE with LOGIN.

### Role Attributes

```sql
CREATE ROLE admin_user
    LOGIN
    SUPERUSER          -- bypasses all permission checks
    CREATEDB           -- can create databases
    CREATEROLE         -- can create other roles
    REPLICATION        -- can initiate streaming replication
    PASSWORD 'secret';
```

Important attributes:
- **SUPERUSER** - bypasses every access check. Equivalent to root. Limit to 1-2 roles.
- **CREATEDB** - can create new databases
- **CREATEROLE** - can create and alter other roles (careful - this is almost as powerful as superuser)
- **INHERIT** - automatically gains privileges of roles it is a member of (default is ON)
- **NOINHERIT** - must explicitly SET ROLE to activate group privileges

### The postgres Superuser

Every PostgreSQL installation has a `postgres` superuser. Treat it like the root account
on Linux - use it for admin tasks only, never for application connections.

---

## The GRANT/REVOKE Hierarchy

Privileges cascade from broad to narrow:

```
DATABASE
  |
  +-- CONNECT, CREATE, TEMP
  |
  SCHEMA
    |
    +-- CREATE, USAGE
    |
    TABLE
      |
      +-- SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER
      |
      COLUMN
        |
        +-- SELECT, INSERT, UPDATE, REFERENCES
```

### Database Level

```sql
-- Allow appuser to connect to appdb
GRANT CONNECT ON DATABASE appdb TO appuser;

-- Revoke public connect (important - by default everyone can connect)
REVOKE CONNECT ON DATABASE appdb FROM PUBLIC;
```

### Schema Level

```sql
-- Allow appuser to see objects in the schema
GRANT USAGE ON SCHEMA app TO appuser;

-- Allow appuser to create objects in the schema
GRANT CREATE ON SCHEMA app TO appuser;
```

**USAGE** is the one people forget. Without it, a role cannot see or reference any
objects in the schema, even if it has table-level grants.

### Table Level

```sql
-- Read-only access
GRANT SELECT ON ALL TABLES IN SCHEMA app TO readonly;

-- Full DML access
GRANT SELECT, INSERT, UPDATE, DELETE ON app.orders TO appuser;
```

### Column Level

```sql
-- Only allow seeing name and email, not salary
GRANT SELECT (name, email) ON hr.employees TO support_team;
```

### Default Privileges

When new tables are created, they don't automatically inherit grants. Fix this with:

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT ON TABLES TO readonly;
```

This ensures future tables created in the `app` schema automatically get the SELECT
grant for `readonly`.

### The PUBLIC Pseudo-Role

`PUBLIC` means "every role." PostgreSQL grants some privileges to PUBLIC by default:
- CONNECT on new databases
- USAGE on the `public` schema
- EXECUTE on new functions

For production, revoke these:

```sql
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE appdb FROM PUBLIC;
```

---

## Row Level Security (RLS)

Regular privileges control access to entire tables. RLS controls access to individual rows.

### The Problem RLS Solves

Imagine a multi-tenant application where all tenants share one `orders` table.
Without RLS, any query can see all tenants' data. The application must always add
`WHERE tenant_id = :current_tenant`. One missed WHERE clause means a data leak.

RLS moves that filter into the database itself.

### Enabling RLS

```sql
-- Step 1: Enable RLS on the table
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;

-- Step 2: Create a policy
CREATE POLICY tenant_isolation ON orders
    USING (tenant_id = current_setting('app.tenant_id')::int);
```

After enabling RLS with no policies, the table returns zero rows for non-superusers.
You must create at least one policy.

### How Policies Work

A policy has two optional filter expressions:

- **USING** - filters rows for SELECT, UPDATE, DELETE (which rows can you see?)
- **WITH CHECK** - filters rows for INSERT, UPDATE (which rows can you write?)

```sql
-- Users can only see their own rows
CREATE POLICY see_own_rows ON orders
    FOR SELECT
    USING (tenant_id = current_setting('app.tenant_id')::int);

-- Users can only insert rows with their own tenant_id
CREATE POLICY insert_own_rows ON orders
    FOR INSERT
    WITH CHECK (tenant_id = current_setting('app.tenant_id')::int);
```

If you omit FOR, the policy applies to all commands.
If you omit WITH CHECK, it defaults to the USING expression.

### USING vs WITH CHECK

```
+------------------+---------------------------------------------------+
| Expression       | Controls                                          |
+------------------+---------------------------------------------------+
| USING            | Which existing rows are visible (reads/updates)   |
| WITH CHECK       | Which new/modified rows are allowed (writes)      |
+------------------+---------------------------------------------------+
```

Example scenario - a policy that lets you see rows WHERE active = true but lets you
insert rows with any value of active. This would use different USING and WITH CHECK.

### Policy Combination

Multiple policies on the same table combine with OR (by default). If any policy
allows the row, it is visible.

To combine with AND, use RESTRICTIVE policies:

```sql
CREATE POLICY base_access ON orders AS PERMISSIVE
    USING (tenant_id = current_setting('app.tenant_id')::int);

CREATE POLICY active_only ON orders AS RESTRICTIVE
    USING (active = true);
```

PERMISSIVE policies OR together. RESTRICTIVE policies AND with the permissive result.

### RLS and Superusers

Superusers and table owners bypass RLS by default. To force the table owner to
respect RLS:

```sql
ALTER TABLE orders FORCE ROW LEVEL SECURITY;
```

---

## SSL/TLS in PostgreSQL

### Why SSL Matters

Without SSL, everything between client and server travels in cleartext - including
passwords (even scram-sha-256 protects the password, but query data is still exposed).
Anyone on the network path can read your queries and results.

### How to Configure SSL

**Server side** (postgresql.conf):

```
ssl = on
ssl_cert_file = '/etc/ssl/certs/server.crt'
ssl_key_file = '/etc/ssl/private/server.key'
ssl_ca_file = '/etc/ssl/certs/ca.crt'       # for client cert verification
```

**Certificate chain:**

```
Root CA
  |
  +-- signs --> Server Certificate (server.crt)
  |
  +-- signs --> Client Certificate (client.crt, for cert auth)
```

The server certificate proves the server's identity.
The CA certificate lets clients verify the server certificate is legitimate.
Client certificates let the server verify the client's identity (used with `cert` auth).

**Enforce SSL in pg_hba.conf:**

```
# Require SSL for all remote connections
hostssl   all   all   0.0.0.0/0   scram-sha-256
```

Use `hostssl` instead of `host` to require encrypted connections.

### Client Connection with SSL

```bash
psql "host=db.example.com dbname=appdb user=appuser sslmode=verify-full sslrootcert=/path/to/ca.crt"
```

SSL modes from weakest to strongest:
- **disable** - no SSL
- **allow** - try without SSL, fall back to SSL
- **prefer** - try SSL, fall back to non-SSL (default)
- **require** - must use SSL, but don't verify the certificate
- **verify-ca** - must use SSL, verify the server cert is signed by a trusted CA
- **verify-full** - must use SSL, verify cert AND that the hostname matches

For production, use `verify-full`.

---

## Common Security Mistakes

### 1. Trust Authentication in pg_hba.conf

```
# NEVER do this for remote connections
host  all  all  0.0.0.0/0  trust
```

This lets anyone connect without a password. It appears in dev setups and sometimes
accidentally makes it to production.

### 2. Superuser for Application Connections

Applications should connect with a role that has only the privileges they need.
A compromised app with superuser access means full database takeover.

### 3. Forgetting to Revoke PUBLIC Privileges

New databases grant CONNECT to PUBLIC. New functions grant EXECUTE to PUBLIC.
If you don't revoke these, every role has more access than intended.

### 4. Granting to Schemas Without USAGE

Granting SELECT on tables without USAGE on the schema means the grants do nothing.
Always pair schema USAGE with table grants.

### 5. Not Using Default Privileges

Without ALTER DEFAULT PRIVILEGES, every new table requires manual GRANT statements.
Tables created in the future will be invisible to non-owners.

### 6. Password in Connection Strings

Storing passwords in application config files or environment variables as plaintext.
Use `.pgpass` files (with 0600 permissions) or certificate authentication instead.

---

## The Principle of Least Privilege

The rule: every role should have the minimum privileges necessary to do its job.

### Practical Implementation

```sql
-- 1. Revoke defaults
REVOKE ALL ON DATABASE appdb FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

-- 2. Create purpose-specific roles
CREATE ROLE app_readonly;
CREATE ROLE app_readwrite;
CREATE ROLE app_admin;

-- 3. Grant incrementally
GRANT CONNECT ON DATABASE appdb TO app_readonly;
GRANT USAGE ON SCHEMA app TO app_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA app TO app_readonly;

GRANT app_readonly TO app_readwrite;
GRANT INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA app TO app_readwrite;

GRANT app_readwrite TO app_admin;
GRANT CREATE ON SCHEMA app TO app_admin;

-- 4. Set defaults for future objects
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT SELECT ON TABLES TO app_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA app
    GRANT INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;

-- 5. Assign login roles to groups
CREATE ROLE webapp LOGIN PASSWORD 'secret';
GRANT app_readwrite TO webapp;

CREATE ROLE analyst LOGIN PASSWORD 'secret';
GRANT app_readonly TO analyst;
```

### Audit Your Privileges

```sql
-- See all grants on a table
\dp app.orders

-- See role memberships
\du

-- See all privileges for a specific role
SELECT * FROM information_schema.role_table_grants
WHERE grantee = 'appuser';
```

---

## Key Takeaways

1. pg_hba.conf is your first line of defense - get the order right, deny by default
2. Use scram-sha-256 for password auth, cert for highest security
3. Roles are both users and groups - use group roles to manage privileges at scale
4. GRANT follows a hierarchy: database -> schema (USAGE!) -> table -> column
5. RLS enforces row-level filtering inside the database, not in application code
6. SSL with verify-full prevents eavesdropping and man-in-the-middle attacks
7. Revoke PUBLIC privileges and use ALTER DEFAULT PRIVILEGES for new objects
8. Principle of least privilege: start with nothing, add only what's needed

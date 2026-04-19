# Concepts - Users, Roles & Connections

**Module:** 06 - Users, Roles & Connections

---

## Role Hierarchy

PostgreSQL has a single object type called a "role" that serves three purposes:

```
ROLE (the only object type)
  |
  +-- Login role  (has LOGIN attribute = "user")
  |     Examples: app_user, postgres, readonly_user
  |
  +-- Group role  (no LOGIN attribute = "group")
  |     Examples: app_read, app_write, app_admin
  |
  +-- Both        (has LOGIN + is a member of a group role)
        Examples: developer_alice MEMBER OF app_write
```

### Role attributes

These control cluster-level capabilities:

| Attribute | Description |
|-----------|-------------|
| LOGIN / NOLOGIN | Whether the role can open a connection |
| SUPERUSER / NOSUPERUSER | Bypasses all permission checks |
| CREATEDB / NOCREATEDB | Can create databases |
| CREATEROLE / NOCREATEROLE | Can create, alter, drop roles (not superuser roles) |
| REPLICATION / NOREPLICATION | Can connect in replication mode |
| BYPASSRLS / NOBYPASSRLS | Bypasses Row Level Security policies |
| CONNECTION LIMIT n | Max simultaneous connections (-1 = unlimited) |
| VALID UNTIL timestamp | Password expiry date |

### Role inheritance

When role A is a member of role B (`GRANT B TO A`), role A inherits the privileges of role B automatically (when INHERIT is set, which is the default). This is how group-based access control works:

```
GRANT SELECT ON TABLE orders TO app_read;   -- privilege on group role
GRANT app_read TO reporter_alice;           -- alice joins the group
-- Now reporter_alice can SELECT from orders (via inheritance)
```

---

## pg_hba.conf Evaluation Order

pg_hba.conf is read top to bottom. The FIRST matching rule is applied. If no rule matches, the connection is rejected.

```
pg_hba.conf (evaluated top to bottom)

TYPE    DATABASE    USER        ADDRESS         METHOD
------  ----------  ----------  --------------  ------------------
local   all         all                         trust          <- Rule 1
host    all         app_user    10.0.0.0/24     scram-sha-256  <- Rule 2
host    all         all         127.0.0.1/32    scram-sha-256  <- Rule 3

Connection attempt: host, stepup_store, app_user, 10.0.1.50
- Rule 1: TYPE=local, but connection is host -> SKIP
- Rule 2: TYPE=host, DB=all, USER=app_user, but 10.0.1.50 not in 10.0.0.0/24 -> SKIP
- Rule 3: TYPE=host, DB=all, USER=all, 10.0.1.50 not in 127.0.0.1/32 -> SKIP
Result: REJECTED (no matching rule)
```

### Connection types

| Type | Description |
|------|-------------|
| local | Unix domain socket connections only |
| host | TCP connections (plain or SSL) |
| hostssl | TCP connections requiring SSL |
| hostnossl | TCP connections prohibiting SSL |

---

## Authentication Method Comparison

| Method | Works On | Password Sent | Strength | Use Case |
|--------|----------|---------------|----------|---------|
| trust | local, host | Never | None | Local dev, OS-managed sockets |
| reject | local, host | N/A | Absolute deny | Blocking specific users/IPs |
| peer | local only | Never | OS username match | postgres OS user on same host |
| md5 | host | Hashed (weak) | Low | Legacy apps that do not support SCRAM |
| scram-sha-256 | host | Challenge-response | High | All modern production TCP connections |
| cert | hostssl | Never | Very High | Certificate-based auth for services |
| ldap | host | LDAP protocol | Varies | Enterprise SSO integration |
| gss / sspi | host | Kerberos | High | Kerberos/Active Directory environments |

---

## Privilege Hierarchy

Access to data requires passing through every level of the privilege hierarchy:

```
Cluster level
  └── CONNECT ON DATABASE stepup_store
        └── USAGE ON SCHEMA public
              └── SELECT ON TABLE orders          (table-level)
                    └── SELECT (col1, col2)       (column-level)
```

Missing any level causes a permission error. Common mistakes:

- GRANT SELECT on table but forget USAGE on schema -> "permission denied for schema"
- GRANT USAGE on schema but forget CONNECT on database -> "permission denied for database"
- GRANT CONNECT and USAGE but forget the table grant -> "permission denied for table"

### Quick reference: system catalog views for privileges

| What to check | View/Command |
|---------------|-------------|
| Role attributes | `pg_roles` |
| Role membership | `pg_auth_members` |
| Table privileges | `information_schema.role_table_grants` or `\dp tablename` |
| Column privileges | `information_schema.role_column_grants` |
| Database privileges | `pg_database.datacl` |
| Schema privileges | `information_schema.schemata` |
| Default privileges | `pg_default_acl` |

### Privilege abbreviations in `\dp` output

```
= anon role (PUBLIC)
r = SELECT
a = INSERT
w = UPDATE
d = DELETE
D = TRUNCATE
x = REFERENCES
t = TRIGGER
X = EXECUTE (functions)
U = USAGE (schemas, sequences, types)
C = CREATE
c = CONNECT (databases)
T = TEMPORARY (databases)
```

---

## Row Level Security Architecture

RLS adds a row-level filter AFTER column-level privilege checks but BEFORE results are returned.

```
Query arrives
    |
    v
Column-level privilege check (GRANT/REVOKE)
    |
    v
RLS policy evaluation (USING clause)
    |
    v
Rows matching policy returned to client
```

### Policy types

- **PERMISSIVE** (default) - rows visible if they satisfy ANY permissive policy (logical OR)
- **RESTRICTIVE** - rows visible only if they satisfy ALL restrictive policies AND at least one permissive policy (logical AND)

### Who bypasses RLS

- Roles with SUPERUSER attribute always bypass RLS
- Roles with BYPASSRLS attribute always bypass RLS
- The table OWNER bypasses RLS unless `ALTER TABLE ... FORCE ROW LEVEL SECURITY` is set
- Members of the table owner role bypass RLS (via inheritance)

### Policy expression timing

`USING` - evaluated against existing rows (for SELECT, UPDATE WHERE clause, DELETE WHERE clause)
`WITH CHECK` - evaluated against new row values (for INSERT, UPDATE SET clause)

---

## Connection Lifecycle

```
Client initiates TCP connection to port 5432
    |
    v
Postmaster accepts, forks a backend process
    |
    v
pg_hba.conf evaluated (type + database + user + address -> method)
    |
    v
Authentication challenge/response (based on method)
    |
    v
Connection limit checks (max_connections, role CONNECTION LIMIT)
    |
    v
Backend enters idle state, waiting for queries
    |
    v
Client sends query
    |
    v
Backend executes query (privilege checks, RLS, execution)
    |
    v
Results returned to client
    |
    v
Client sends COMMIT / ROLLBACK / next query
    |
    v
Client disconnects
    |
    v
Backend process exits, slot freed
```

### Key parameters for connection management

| Parameter | Default | What it controls |
|-----------|---------|-----------------|
| max_connections | 100 | Total connections (requires restart to change) |
| superuser_reserved_connections | 3 | Slots reserved for superusers |
| idle_in_transaction_session_timeout | 0 (off) | Auto-terminate idle-in-transaction sessions |
| statement_timeout | 0 (off) | Auto-cancel queries exceeding time limit |
| lock_timeout | 0 (off) | Fail immediately if lock cannot be acquired within time |
| tcp_keepalives_idle | 0 (OS default) | Seconds before sending TCP keepalive |

---

## pg_stat_activity Quick Reference

Key columns for daily DBA work:

| Column | Description |
|--------|-------------|
| pid | Backend process ID |
| usename | Role name |
| datname | Database name |
| application_name | Set by client (e.g., "PulseApp", "psql") |
| client_addr | Client IP (NULL for Unix socket) |
| backend_start | When the connection was established |
| state | active / idle / idle in transaction / idle in transaction (aborted) |
| wait_event_type | Category of wait (Lock, IO, Client, etc.) |
| wait_event | Specific wait event name |
| query_start | When current/last query started |
| state_change | When state last changed |
| query | Text of current or last query |

Useful derived queries:

```sql
-- Connection count by state
SELECT state, count(*) FROM pg_stat_activity GROUP BY state;

-- Long-running queries (> 1 minute)
SELECT pid, usename, now() - query_start, query
FROM pg_stat_activity
WHERE state = 'active' AND query_start < now() - interval '1 minute';

-- Blocked sessions
SELECT blocked.pid, blocking.pid AS blocking_pid
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- Idle connections older than 10 minutes
SELECT pid, usename, now() - state_change AS idle_for
FROM pg_stat_activity
WHERE state = 'idle' AND state_change < now() - interval '10 minutes';
```

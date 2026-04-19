# Scenario 09 - Connection Limit Reached

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application cannot connect to the database.
Error: FATAL: too many connections for role "app_user"
The total server connections are well under max_connections.
Only app_user is affected - other roles connect fine.
```

---

## Key Concepts for Revision

- **CONNECTION LIMIT is per-role** - Each role can have a connection limit set with `ALTER ROLE rolename CONNECTION LIMIT n`. A value of `-1` means unlimited (the default). When the limit is reached, new connections are rejected with `FATAL: too many connections for role`. This is separate from the server-wide `max_connections` setting.

- **pg_roles shows the limit** - The `rolconnlimit` column in `pg_roles` shows the configured limit. `-1` means no per-role limit.

- **pg_stat_activity shows active connections** - Use `pg_stat_activity` to see how many connections a role currently has and what they are doing. Look at the `state` column: `active` means running a query, `idle` means waiting for a query, `idle in transaction` means a transaction is open but no query is running.

- **pg_terminate_backend kills a connection** - Use `pg_terminate_backend(pid)` to forcibly close a connection. Always prefer `pg_cancel_backend(pid)` first (cancels the query but keeps the connection), then escalate to terminate if needed.

---

## Diagnostic Steps

### Step 1 - Reproduce the error

```bash
PGPASSWORD=apppass123 /usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT 1;"
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  too many connections for role "app_user"
```

### Step 2 - Connect as postgres to investigate

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Check the connection limit for app_user

```sql
SELECT rolname, rolconnlimit
FROM pg_roles
WHERE rolname = 'app_user';
```

Expected output:

```
 rolname  | rolconnlimit
----------+--------------
 app_user |            1
(1 row)
```

The limit is set to 1. That is extremely low for an application role.

### Step 4 - Check current connections for app_user

```sql
SELECT pid, state, query, backend_start, state_change
FROM pg_stat_activity
WHERE usename = 'app_user';
```

Expected output (yours will differ):

```
  pid  | state  |        query         |       backend_start        |       state_change
-------+--------+----------------------+----------------------------+----------------------------
 12345 | active | SELECT pg_sleep(86400) | 2026-04-19 10:00:00+00   | 2026-04-19 10:00:00+00
(1 row)
```

One connection is open and running `pg_sleep(86400)` - a long-running idle query that is holding the only connection slot.

---

## Resolution

### Step 1 - Terminate the blocking session

Use the PID from the previous query. Replace `12345` with the actual PID you saw.

```sql
SELECT pg_terminate_backend(12345);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

The `t` means the backend was successfully terminated.

### Step 2 - Raise the connection limit

A limit of 1 is not suitable for an application role. Set a reasonable limit.

```sql
ALTER ROLE app_user CONNECTION LIMIT 10;
```

Expected output:

```
ALTER ROLE
```

This allows up to 10 simultaneous connections for `app_user`. Adjust this based on your application's connection pool size.

### Step 3 - Verify the new limit

```sql
SELECT rolname, rolconnlimit
FROM pg_roles
WHERE rolname = 'app_user';
```

Expected output:

```
 rolname  | rolconnlimit
----------+--------------
 app_user |           10
(1 row)
```

### Step 4 - Confirm no blocking sessions remain

```sql
SELECT pid, state, query
FROM pg_stat_activity
WHERE usename = 'app_user';
```

Expected output:

```
 pid | state | query
-----+-------+-------
(0 rows)
```

No lingering connections.

### Step 5 - Exit postgres and test

```sql
\q
```

```bash
exit
```

```bash
PGPASSWORD=apppass123 /usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT current_user;"
```

Expected output:

```
 current_user
--------------
 app_user
(1 row)
```

The connection succeeds.

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- app_user CONNECTION LIMIT is greater than 1
- No blocking pg_sleep sessions for app_user
- app_user can establish a new connection

---

## Interview Discussion Points

1. **What is the difference between CONNECTION LIMIT on a role and max_connections on the server?** - `max_connections` is the total number of connections the PostgreSQL server will accept from all clients. `CONNECTION LIMIT` is a per-role cap. A role could hit its limit long before the server hits max_connections. The two are independent - raising max_connections does not fix a per-role limit issue.

2. **When would you set a CONNECTION LIMIT on a role?** - Common use cases: (a) preventing a runaway application from consuming all server connections, (b) enforcing resource isolation in a multi-tenant database where each tenant has their own role, (c) limiting ad-hoc query roles to prevent analysts from accidentally opening too many connections. Application service accounts typically get a limit matching their connection pool size plus a small buffer.

3. **What is the difference between pg_cancel_backend and pg_terminate_backend?** - `pg_cancel_backend(pid)` sends a SIGINT that cancels the currently-running query but keeps the connection alive. The client gets an error for that query but can issue new queries. `pg_terminate_backend(pid)` sends a SIGTERM that closes the entire connection. The client must reconnect. Always try cancel first, then terminate if the session does not cooperate.

4. **How would you set up monitoring to catch connection limit exhaustion before it causes an outage?** - Query `SELECT r.rolname, r.rolconnlimit, count(s.pid) as current FROM pg_roles r LEFT JOIN pg_stat_activity s ON s.usename = r.rolname WHERE r.rolconnlimit > 0 GROUP BY r.rolname, r.rolconnlimit HAVING count(s.pid) >= r.rolconnlimit * 0.8`. This alerts when any role reaches 80% of its limit.

5. **Does CONNECTION LIMIT apply to superusers?** - Superusers are not restricted by CONNECTION LIMIT. They also have `superuser_reserved_connections` (default 3) set aside in max_connections. This means even when the server is at max_connections, superusers can still connect using the reserved slots.

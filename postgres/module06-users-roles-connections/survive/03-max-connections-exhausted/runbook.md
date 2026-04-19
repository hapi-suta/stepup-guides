# Scenario 03 - max_connections Exhausted

**Severity:** HIGH
**Expected Recovery Time:** 5-8 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: PostgreSQL cannot accept new connections.
max_connections is set too low (5). With 3 reserved
for superusers, only 2 slots are available for the app.
The Pulse dashboard shows 'too many connections'.
```

---

## Key Concepts for Revision

- **max_connections requires a restart** - Unlike most PostgreSQL parameters, `max_connections` affects shared memory allocation at startup. It cannot be changed with a reload. You must use `ALTER SYSTEM SET max_connections = N;` and then restart the service.

- **superuser_reserved_connections** - PostgreSQL reserves a number of connection slots (default 3) exclusively for superusers. This ensures you can always connect to diagnose problems even when the app has exhausted all slots. Available slots for regular users = `max_connections - superuser_reserved_connections`.

- **ALTER SYSTEM vs editing postgresql.conf directly** - `ALTER SYSTEM` writes to `postgresql.auto.conf`, which is a separate file that overrides `postgresql.conf`. It is safer than editing `postgresql.conf` directly because the syntax is validated by PostgreSQL before writing, and it is easy to undo with `ALTER SYSTEM RESET parameter_name`.

- **Pending restart indicator** - After running ALTER SYSTEM for a restart-required parameter, `pg_settings.pending_restart` becomes true for that parameter. This tells you a restart is needed.

---

## Diagnostic Steps

### Step 1 - Confirm the error

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store
```

Expected output:

```
psql: error: connection to server at "127.0.0.1", port 5432 failed: FATAL:  sorry, too many clients already
```

### Step 2 - Connect as postgres via socket (uses reserved slots)

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

### Step 3 - Check current max_connections

```sql
SHOW max_connections;
```

Expected output:

```
 max_connections
-----------------
 5
(1 row)
```

### Step 4 - Check how many connections are in use

```sql
SELECT count(*) FROM pg_stat_activity;
```

```sql
SELECT setting FROM pg_settings WHERE name = 'superuser_reserved_connections';
```

With max_connections=5 and 3 reserved, only 2 slots are available for regular users.

---

## Resolution

### Step 1 - Increase max_connections

```sql
ALTER SYSTEM SET max_connections = 100;
```

Expected output:

```
ALTER SYSTEM
```

### Step 2 - Verify the pending restart flag

```sql
SELECT name, setting, pending_restart FROM pg_settings WHERE name = 'max_connections';
```

Expected output:

```
      name       | setting | pending_restart
-----------------+---------+-----------------
 max_connections | 5       | t
(1 row)
```

`pending_restart = t` confirms a restart is required. The current value is still 5 until restart.

### Step 3 - Exit psql

```bash
\q
```

```bash
exit
```

### Step 4 - Restart PostgreSQL

```bash
sudo systemctl restart postgresql-16
```

Wait for it to come back up:

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
  Active: active (running) since ...
```

### Step 5 - Verify the new setting

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW max_connections;"
```

Expected output:

```
 max_connections
-----------------
 100
(1 row)
```

```bash
exit
```

### Step 6 - Verify app_user can connect

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 5432 -U app_user -d stepup_store -c "SELECT current_user;"
```

Enter `apppass123` when prompted.

Expected output:

```
 current_user
--------------
 app_user
(1 row)
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- max_connections is at least 50
- app_user can connect via TCP
- No pending_restart on max_connections

---

## Interview Discussion Points

1. **Why does max_connections require a restart while most other parameters only need a reload?** - max_connections determines how much shared memory PostgreSQL allocates for backend process slots at startup. This is a fixed-size structure in shared memory. Changing it requires the postmaster to tear down and rebuild the shared memory segment, which is only possible during a restart.

2. **What is the risk of setting max_connections very high?** - Each connection requires memory for the backend process stack, work memory allocations, and shared memory overhead. Very high max_connections (e.g., 1000+) can exhaust system memory even with mostly idle connections. It also increases lock table overhead. The general recommendation is to use a connection pooler like PgBouncer and keep max_connections at 200-400.

3. **How does superuser_reserved_connections protect against this exact scenario?** - It reserves slots that only superusers can use. Even when the application has exhausted all non-reserved slots, a DBA can still connect as postgres to diagnose and fix the problem. Without this, you would be completely locked out when connections are exhausted.

4. **If you cannot restart PostgreSQL but need to free up connections, what can you do?** - Use `pg_terminate_backend(pid)` to terminate idle or stuck connections. Query `pg_stat_activity` to find idle connections, idle-in-transaction connections, or connections from old application versions. You can terminate all idle connections from a specific user with a SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE usename = 'app_user' AND state = 'idle'.

5. **What is the relationship between max_connections and shared_buffers memory?** - PostgreSQL documentation suggests shared_buffers at 25% of system RAM. For max_connections, each connection uses roughly 5-10 MB of overhead beyond shared_buffers. A server with 8 GB RAM and shared_buffers at 2 GB has roughly 6 GB available for connection overhead, supporting up to 600-1200 connections in theory. But context switching costs dominate at high connection counts.

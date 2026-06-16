# Runbook 02: PgBouncer Connection Exhaustion

## Alert
> "PgBouncer on pg-primary reporting 'no more connections allowed'. New application connections are
> being rejected."

PgBouncer has hit its `max_client_conn` ceiling. Any new connection attempt from the application
layer is returning: `ERROR: no more connections allowed (max_client_conn)`. Existing sessions may
still be running but no new work can enter the database. Trading pipelines will stall as soon as
their current connection is closed and they try to reconnect.

---

## Layer 1 - Junior DBA: Assess and Contain

**Goal:** Confirm the exhaustion is real, collect baseline numbers, and identify whether idle
connections are piling up - without making any changes yet.

### Step 1: SSH into the primary server

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

### Step 2: Connect to the PgBouncer admin console

PgBouncer exposes a virtual database called `pgbouncer` on port 6432. You can query it with psql.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer
```

If this connection itself is refused with `no more connections allowed`, PgBouncer is completely
saturated. Move to Step 4 and use `pgbouncer` unix socket instead:

```bash
/usr/pgsql-17/bin/psql -h /var/run/pgbouncer -p 6432 -U pgbouncer pgbouncer
```

### Step 3: Check the pools

Inside the PgBouncer console:

```sql
SHOW pools;
```

Expected output (truncated):

```
 database  |   user          | cl_active | cl_waiting | sv_active | sv_idle | sv_used | maxwait
-----------+-----------------+-----------+------------+-----------+---------+---------+---------
 quantdb   | quant_pipeline  |        45 |         87 |        10 |       0 |       2 |      42
(1 row)
```

Key columns to read:
- `cl_active` - clients currently connected and executing
- `cl_waiting` - clients waiting for a free server connection. If this is high, you have a pool bottleneck
- `sv_idle` - idle server-side connections. If this is 0 and cl_waiting is high, you have no room left
- `maxwait` - how long the longest waiting client has been queued (in seconds)

### Step 4: Check overall connection counts

Still inside the PgBouncer console:

```sql
SHOW stats;
```

```sql
SHOW clients;
```

The `SHOW clients` output lists every client connection. Look at the `state` column. States you
will see:

- `active` - executing a query
- `idle` - connected but doing nothing
- `used` - used a server connection recently

Count how many are `idle`. A large number of idle clients is usually a connection leak.

Exit the PgBouncer console:

```sql
\q
```

### Step 5: Check PgBouncer configuration for current limits

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo grep -E "max_client_conn|default_pool_size|pool_mode|reserve_pool_size" /etc/pgbouncer/pgbouncer.ini
```

Expected output:

```
pool_mode = transaction
max_client_conn = 100
default_pool_size = 10
reserve_pool_size = 2
```

Note these numbers. You now know the ceiling and current configuration.

### Step 6: Check the PostgreSQL side for idle-in-transaction sessions

Idle-in-transaction sessions hold a server connection inside PgBouncer's pool and never release it,
starving other clients.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT pid, usename, application_name, state, now() - state_change AS duration FROM pg_stat_activity WHERE state = 'idle in transaction' ORDER BY duration DESC;"
```

Expected output (problem scenario):

```
  pid  |    usename     | application_name | state               | duration
-------+----------------+------------------+---------------------+----------
 18432 | quant_pipeline | voleon-app       | idle in transaction | 00:14:32
 18456 | quant_pipeline | voleon-app       | idle in transaction | 00:09:11
...
```

Any session idle in transaction for more than 2-3 minutes is a leak candidate. Exit:

```bash
exit
```

### Step 7: Notify the team

Document what you found:
- Current `cl_waiting` count
- Number of idle-in-transaction sessions and their duration
- Current `max_client_conn` setting

Post to the incident channel. Do not kill connections or change config yet without authorization.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

**Goal:** Identify which application is leaking connections, terminate idle-in-transaction sessions,
and temporarily raise the connection ceiling to restore service.

### Step 8: Identify the leaking application

Check which application name or IP is holding the most idle-in-transaction sessions.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT application_name, client_addr, count(*) FROM pg_stat_activity WHERE state = 'idle in transaction' GROUP BY application_name, client_addr ORDER BY count DESC;"
```

Expected output:

```
 application_name |  client_addr   | count
------------------+----------------+-------
 voleon-app       | 172.31.21.45   |    34
 ops-reporter     | 172.31.26.19   |     3
(2 rows)
```

The application at `172.31.21.45` (the container server) is holding 34 idle-in-transaction sessions.
That is the source of the leak.

### Step 9: Terminate idle-in-transaction sessions

You can terminate sessions individually by PID, or in bulk by state. Terminate the leaking
application's sessions first.

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE state = 'idle in transaction' AND application_name = 'voleon-app' AND now() - state_change > interval '5 minutes';"
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
 t
 t
...
(34 rows)
```

Each `t` means one session was terminated. The application will reconnect cleanly - PgBouncer will
hand out a fresh connection on the next request.

Exit:

```bash
exit
```

### Step 10: Verify PgBouncer pools cleared

Reconnect to the PgBouncer admin console to confirm `cl_waiting` dropped.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer
```

Inside the PgBouncer console:

```sql
SHOW pools;
```

You should now see `cl_waiting` at or near 0. Exit:

```sql
\q
```

### Step 11: Temporarily raise max_client_conn to restore headroom

While you investigate the leak, give the system breathing room so new connections are not rejected.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Find and change:

```
max_client_conn = 100
```

To:

```
max_client_conn = 200
```

Save and exit vi with `:wq`.

Reload PgBouncer without dropping connections:

```bash
sudo systemctl reload pgbouncer
```

Confirm the new limit took effect:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer -c "SHOW config;" | grep max_client_conn
```

Expected output:

```
 max_client_conn | 200
```

### Step 12: Pause and resume PgBouncer if connections are still stuck

If the pool is in an inconsistent state after mass terminations, a PAUSE/RESUME cycle forces
PgBouncer to drain and re-establish server connections cleanly.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer -c "PAUSE quantdb;"
```

Wait 5 seconds, then resume:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer -c "RESUME quantdb;"
```

Note: PAUSE will block until all active transactions complete. If transactions are stuck, use
`KILL` instead of PAUSE.

### Step 13: Set idle_in_transaction_session_timeout in PostgreSQL

This setting automatically terminates any session that stays idle in transaction beyond the
threshold. It prevents the leak from happening silently in the future.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "ALTER SYSTEM SET idle_in_transaction_session_timeout = '10min';"
```

```bash
/usr/pgsql-17/bin/psql -c "SELECT pg_reload_conf();"
```

Confirm it is active:

```bash
/usr/pgsql-17/bin/psql -c "SHOW idle_in_transaction_session_timeout;"
```

Expected output:

```
 idle_in_transaction_session_timeout
--------------------------------------
 10min
(1 row)
```

Exit:

```bash
exit
```

---

## Layer 3 - Senior DBA: Root Cause and Prevent

**Goal:** Identify the application code path causing the leak, tune PgBouncer for the actual
workload, and set up alerting so this is caught at 80% capacity, not 100%.

### Step 14: Review pg_stat_statements for transaction patterns

Check if a specific query is frequently seen in the `idle in transaction` state. This points to
the code path that opens a transaction and never closes it.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "SELECT query, calls, mean_exec_time FROM pg_stat_statements WHERE query ILIKE '%BEGIN%' OR query ILIKE '%START TRANSACTION%' ORDER BY calls DESC LIMIT 10;"
```

Look for queries that have high `calls` counts without corresponding COMMIT or ROLLBACK patterns.
The application at `172.31.21.45` is opening transactions and not committing them. This is usually
caused by:
- Exception handling that skips the finally/close block
- ORM misconfiguration (autocommit off, connection not returned to pool)
- Long-running background job that holds a connection open

Exit:

```bash
exit
```

### Step 15: Review PgBouncer pool_mode choice

In `transaction` pool mode, PgBouncer holds the server connection only for the duration of a
transaction. This is the most efficient mode but requires that the application not use
session-level features (SET, advisory locks, prepared statements across transactions).

In `session` pool mode, a server connection is held for the entire client session. This is safer
for complex applications but uses more server connections.

Check which mode is in use:

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo grep pool_mode /etc/pgbouncer/pgbouncer.ini
```

If you are in `session` mode and the application leaks connections, each leaked client ties up a
real PostgreSQL backend. Switching to `transaction` mode reduces the blast radius but requires
application testing first.

### Step 16: Tune pool sizes based on observed traffic

Set pool sizes based on actual peak usage rather than defaults.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Recommended settings for this workload (adjust based on your observed peaks):

```ini
; Maximum client-side connections across all pools
max_client_conn = 200

; Server connections per (database, user) pair
default_pool_size = 20

; Extra connections available when pool is saturated (emergency use)
reserve_pool_size = 5

; How long a client can wait for a server connection before getting an error
; Prevents unbounded queue growth
client_login_timeout = 60

; Terminate server connections idle longer than this
server_idle_timeout = 300

; Terminate transactions idle longer than this on the server side
query_timeout = 30
```

Save with `:wq` and reload:

```bash
sudo systemctl reload pgbouncer
```

### Step 17: Set up connection usage alerting

Alert at 80% of `max_client_conn`, not 100%. By the time you hit 100%, it is already an incident.

Check PgBouncer's current client count with:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U pgbouncer pgbouncer -c "SHOW stats_totals;"
```

For production alerting, scrape PgBouncer stats via the pgbouncer_exporter Prometheus exporter and
alert on:

```
pgbouncer_pools_client_active_connections / pgbouncer_config_max_client_conn > 0.8
```

Add this to your alerting rules file and test it fires at 80%.

### Step 18: Coordinate a fix with the application team

Share your findings with the team that owns the `voleon-app` service (container server
172.31.21.45). They need to:

1. Ensure every code path that opens a transaction has a corresponding commit or rollback in the
   exception handler
2. Use connection pooling at the application level (e.g., SQLAlchemy `pool_pre_ping=True`)
3. Explicitly set `autocommit = True` for read-only queries that do not need transactions
4. Add `connect_timeout` in their connection string so stale connections fail fast

Until the application is patched, the `idle_in_transaction_session_timeout` set in Step 13 acts
as a backstop.

---

## Summary

### Root Cause
The application running on the container server (172.31.21.45) opened database transactions and
failed to close them - either due to an unhandled exception path or ORM misconfiguration. Over time
these idle-in-transaction sessions accumulated and consumed all available PgBouncer client slots.

### Resolution
1. Identified the leaking application via `pg_stat_activity`
2. Terminated idle-in-transaction sessions with `pg_terminate_backend()`
3. Temporarily raised `max_client_conn` to 200 to restore headroom
4. Set `idle_in_transaction_session_timeout = 10min` as an automatic cleanup backstop
5. Reloaded PgBouncer config with updated pool sizes

### Prevention
- Alert at 80% of `max_client_conn` using Prometheus/pgbouncer_exporter
- Set `idle_in_transaction_session_timeout` on all databases
- Review application connection handling - ensure all code paths commit or rollback
- Document `pool_mode` choice and validate application compatibility before changing it
- Tune `default_pool_size` and `reserve_pool_size` based on actual peak traffic

# Use Exercise 10 - Connection Pressure

Investigate connection usage, identify idle sessions, and understand how connection limits affect a PostgreSQL server.

**Server:** NODE1 only

---

## Setup

**Step 1.** SSH into NODE1 using your `.pem` key file.

```bash
ssh -i your-key.pem ec2-user@<NODE1_IP>
```

**Step 2.** Switch to the `postgres` OS user.

```bash
sudo su - postgres
```

This switches you to the `postgres` system account, which has permission to connect to PostgreSQL without a password.

**Step 3.** Connect to the `labdb` database.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

You should see a `labdb=#` prompt. You are now inside the PostgreSQL interactive shell.

---

## Task 1 - Connection Census

You will query the `pg_stat_activity` view to count how many connections exist and what state they are in. You will also check the server's maximum connection limit.

**Step 1.** Count connections grouped by state.

```sql
SELECT state, COUNT(*) AS connection_count
FROM pg_stat_activity
GROUP BY state
ORDER BY connection_count DESC;
```

This query reads `pg_stat_activity`, which is a live view showing every connection currently open to PostgreSQL. The `state` column tells you what each connection is doing right now.

Expected output (yours will differ):

```
   state   | connection_count
-----------+------------------
 idle       |                3
 active     |                1
            |                2
(3 rows)
```

A `NULL` state row represents background worker processes (autovacuum, checkpointer, etc.) that are not client connections.

**Step 2.** Check the server's maximum connection limit.

```sql
SHOW max_connections;
```

This shows the hard cap on how many client connections PostgreSQL will accept at one time. It is set in `postgresql.conf` and requires a server restart to change.

Expected output (yours will differ):

```
 max_connections
-----------------
 100
(1 row)
```

**Step 3.** Calculate the current connection count in one query.

```sql
SELECT
  COUNT(*) FILTER (WHERE state = 'active')           AS active,
  COUNT(*) FILTER (WHERE state = 'idle')             AS idle,
  COUNT(*) FILTER (WHERE state = 'idle in transaction') AS idle_in_tx,
  COUNT(*) FILTER (WHERE backend_type = 'client backend') AS total_client,
  current_setting('max_connections')::int            AS max_conn,
  ROUND(
    COUNT(*) FILTER (WHERE backend_type = 'client backend') * 100.0
    / current_setting('max_connections')::int, 1
  )                                                  AS pct_used
FROM pg_stat_activity;
```

This single query gives you a full picture: how many connections are active, idle, or stuck in a transaction, and what percentage of `max_connections` you are consuming.

Expected output (yours will differ):

```
 active | idle | idle_in_tx | total_client | max_conn | pct_used
--------+------+------------+--------------+----------+----------
      1 |    3 |          0 |            4 |      100 |      4.0
(1 row)
```

**Answer these questions before moving on:**

- What percentage of connections are currently in use?
- At what percentage should you start to worry? (See answers at the bottom.)

---

## Task 2 - Connection by Application

You will group connections by `application_name` to see which clients or tools are connected.

**Step 1.** Count connections by application name.

```sql
SELECT
  application_name,
  state,
  COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY application_name, state
ORDER BY connection_count DESC;
```

The `application_name` column is set by the client when it connects. `psql` sets it to `psql`. `pgbench` sets it to `pgbench`. Your application code can set it too using the connection string parameter `application_name=myapp`.

Expected output (yours will differ):

```
 application_name | state | connection_count
------------------+-------+------------------
 psql             | active |               1
(1 row)
```

**Answer this question before moving on:**

- Which application has the most connections right now? (See answers at the bottom.)

---

## Task 3 - Oldest Idle Connection

You will find the connection that has been sitting idle the longest. Long-idle connections hold resources and can block autovacuum on some workloads.

**Step 1.** Find the oldest idle connection.

```sql
SELECT
  pid,
  usename,
  application_name,
  state,
  backend_start,
  state_change,
  NOW() - state_change AS idle_duration
FROM pg_stat_activity
WHERE state = 'idle'
  AND backend_type = 'client backend'
ORDER BY state_change ASC
LIMIT 5;
```

- `backend_start` is when the connection was first opened.
- `state_change` is the last time the connection changed state (for example, from `active` to `idle`). For an idle connection, this is when it finished its last query.
- `idle_duration` tells you how long it has been sitting idle.

Expected output (yours will differ):

```
  pid  | usename  | application_name | state |        backend_start         |         state_change         | idle_duration
-------+----------+------------------+-------+------------------------------+------------------------------+---------------
 12345 | postgres | psql             | idle  | 2026-04-25 10:01:00.123456+00 | 2026-04-25 10:01:05.654321+00 | 00:04:32.1
(1 row)
```

**Answer these questions before moving on:**

- Should this connection be terminated?
- What PostgreSQL setting controls automatic cleanup of idle connections? (See answers at the bottom.)

---

## Task 4 - Simulate Connection Pressure

You will use `pgbench` to open 20 simultaneous connections and watch what happens to `pg_stat_activity` in real time.

You need two terminal windows for this task.

**Terminal 1 - Start the load.**

**Step 1.** Exit psql first.

```sql
\q
```

**Step 2.** Run `pgbench` with 20 clients for 30 seconds.

```bash
/usr/pgsql-16/bin/pgbench -c 20 -T 30 -S labdb
```

- `-c 20` opens 20 simultaneous client connections.
- `-T 30` runs the test for 30 seconds, then stops.
- `-S` runs read-only SELECT queries (lighter on the server, good for observing connection behavior without heavy writes).

The command will hang (run) for 30 seconds. Leave it running and switch to Terminal 2.

**Terminal 2 - Watch connections while pgbench runs.**

**Step 3.** Open a second terminal window and SSH into NODE1 again.

```bash
ssh -i your-key.pem ec2-user@<NODE1_IP>
```

**Step 4.** Switch to the `postgres` user.

```bash
sudo su - postgres
```

**Step 5.** Connect to `labdb`.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

**Step 6.** Count connections by state while pgbench is running.

```sql
SELECT state, COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY connection_count DESC;
```

Run this query a few times during the 30-second window to watch the numbers change.

Expected output while pgbench is running (yours will differ):

```
 state  | connection_count
--------+------------------
 active |               18
 idle   |                3
(2 rows)
```

**Step 7.** Also check the percentage in use.

```sql
SELECT
  COUNT(*) FILTER (WHERE backend_type = 'client backend') AS total_client,
  current_setting('max_connections')::int AS max_conn,
  ROUND(
    COUNT(*) FILTER (WHERE backend_type = 'client backend') * 100.0
    / current_setting('max_connections')::int, 1
  ) AS pct_used
FROM pg_stat_activity;
```

**Step 8.** Wait for pgbench to finish in Terminal 1, then run the count query again to confirm connections dropped back down.

**Answer these questions before moving on:**

- What happened to the number of active connections when pgbench started?
- Did any queries slow down? (See answers at the bottom.)

---

## Task 5 - pg_stat_database Overview

You will query `pg_stat_database` to check overall database health - specifically transaction counts and the buffer cache hit ratio.

**Step 1.** Query `pg_stat_database` for `labdb`.

```sql
SELECT
  datname,
  xact_commit,
  xact_rollback,
  blks_read,
  blks_hit,
  ROUND(
    blks_hit * 100.0 / NULLIF(blks_hit + blks_read, 0), 2
  ) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'labdb';
```

- `xact_commit` - total transactions that completed successfully since the last stats reset.
- `xact_rollback` - total transactions that were rolled back. A high rollback count can indicate application errors or retries.
- `blks_read` - data blocks read from disk (slow).
- `blks_hit` - data blocks found in PostgreSQL's shared buffer cache (fast).
- `cache_hit_ratio` - what percentage of block requests were served from memory instead of disk.

Expected output (yours will differ):

```
 datname | xact_commit | xact_rollback | blks_read | blks_hit | cache_hit_ratio
---------+-------------+---------------+-----------+----------+-----------------
 labdb   |        8421 |            12 |       340 |    97842 |           99.65
(1 row)
```

**Answer these questions before moving on:**

- What is your cache hit ratio?
- Is it good or bad? What is the acceptable threshold? (See answers at the bottom.)

---

## Task 6 - Connection Limit Test

You will temporarily lower the connection limit on `labdb` to 5, then try to exceed it to see exactly what error PostgreSQL returns.

**Step 1.** Set the connection limit to 5 on `labdb`.

```sql
ALTER DATABASE labdb CONNECTION LIMIT 5;
```

This sets a hard cap specific to the `labdb` database. It does not affect other databases. The change takes effect immediately - no restart needed.

**Step 2.** Confirm the limit was applied.

```sql
SELECT datname, datconnlimit
FROM pg_database
WHERE datname = 'labdb';
```

A value of `5` confirms the limit is set. A value of `-1` means unlimited.

Expected output:

```
 datname | datconnlimit
---------+--------------
 labdb   |            5
(1 row)
```

**Step 3.** Open a new terminal window and SSH into NODE1.

```bash
ssh -i your-key.pem ec2-user@<NODE1_IP>
```

**Step 4.** Switch to the `postgres` user.

```bash
sudo su - postgres
```

**Step 5.** Try opening more connections than the limit allows. Run this command 5 or more times rapidly to saturate the limit.

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT pg_sleep(15);" &
/usr/pgsql-16/bin/psql -p 5432 -d labdb
```

Each `&` sends the command to the background so they all open simultaneously. The last line (no `&`) will attempt to connect after the limit is hit.

Expected output on the final connection attempt:

```
psql: error: connection to server on socket "/var/run/postgresql/.s.PGSQL.5432" failed:
FATAL:  too many connections for database "labdb"
```

**Step 6.** Kill the background sleep connections.

```bash
kill %1 %2 %3 %4 %5 %6 2>/dev/null
```

This terminates the background jobs you launched with `&`.

**Step 7.** Go back to your original psql session (Terminal 1 / Terminal 2 where you are still connected) and reset the connection limit.

```sql
ALTER DATABASE labdb CONNECTION LIMIT -1;
```

A limit of `-1` means unlimited. This restores the default behavior.

**Step 8.** Confirm the reset.

```sql
SELECT datname, datconnlimit
FROM pg_database
WHERE datname = 'labdb';
```

Expected output:

```
 datname | datconnlimit
---------+--------------
 labdb   |           -1
(1 row)
```

**Answer this question before moving on:**

- What exact error message did you get when the connection limit was exceeded? (See answers at the bottom.)

---

## Cleanup

Run these steps to make sure nothing is left in a broken state.

**Step 1.** Confirm the connection limit is reset to unlimited.

```sql
SELECT datname, datconnlimit FROM pg_database WHERE datname = 'labdb';
```

The value must be `-1`. If it is not, run:

```sql
ALTER DATABASE labdb CONNECTION LIMIT -1;
```

**Step 2.** Check for any lingering idle-in-transaction sessions.

```sql
SELECT pid, state, NOW() - state_change AS duration, query
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND backend_type = 'client backend';
```

If any rows appear, terminate them.

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND backend_type = 'client backend';
```

**Step 3.** Exit psql.

```sql
\q
```

**Step 4.** Exit the `postgres` user and return to `ec2-user`.

```bash
exit
```

---

## Answers

**Task 1 - Connection Census**

- The percentage of connections in use depends on your exact output. On this lab server with a fresh session you will likely see 3-6% used out of 100 max connections.
- You should start paying attention around 70-75% usage. At 80% you should investigate and consider connection pooling (PgBouncer). At 90%+ you are in danger of hitting the limit and new connections will be rejected entirely. PostgreSQL reserves 3 connections above `max_connections` for superusers, so even at the limit a `postgres` superuser can still connect to investigate.

**Task 2 - Connection by Application**

- On this lab server, `psql` will have the most connections since that is the only client connected. After running pgbench in Task 4, `pgbench` will briefly take the top spot.
- In production, look for application frameworks (Django, Rails, Spring) or connection poolers (PgBouncer). If you see hundreds of connections from a single application name it may mean the app is not using a connection pool.

**Task 3 - Oldest Idle Connection**

- Whether the connection should be terminated depends on the `idle_duration`. An idle connection from a few seconds ago is normal - a query just finished. An idle connection from hours or days ago is a leak. It is holding a slot and may be holding backend memory (the `work_mem` allocation from its last query is not freed until it disconnects). In production, connections idle for more than 10-15 minutes should be investigated and likely terminated.
- The setting is `idle_in_transaction_session_timeout` for connections stuck in an open transaction, and `tcp_keepalives_idle` / `idle_session_timeout` (added in PG 14) for plain idle connections. Set `idle_session_timeout = '10min'` in `postgresql.conf` to automatically terminate connections that have been idle longer than 10 minutes.

**Task 4 - Simulate Connection Pressure**

- The number of active connections jumped from 1-2 (just your psql session) to around 20 as pgbench opened its clients. You should have seen `active` state connections spike during the run, then drop back to near zero after pgbench finished.
- On this 2-vCPU server, 20 SELECT-only connections may not cause visible slowdown since the workload is read-only and likely fits in cache. However, if you ran a write-heavy test (`pgbench -c 20 -T 30 labdb` without `-S`), you would see transaction latency increase due to lock contention, WAL write pressure, and CPU saturation. More connections does not mean more throughput - beyond 2x the CPU core count, throughput plateaus and latency rises.

**Task 5 - pg_stat_database Overview**

- After running pgbench, the cache hit ratio should be very high - typically 98-99%+ for this lab since the pgbench dataset is small enough to fit entirely in PostgreSQL's shared buffers.
- A cache hit ratio above 99% is excellent. 95-99% is acceptable. Below 95% means PostgreSQL is reading too much from disk and you should consider increasing `shared_buffers`, adding indexes, or examining query patterns. The formula is: `blks_hit / (blks_hit + blks_read) * 100`. Note: this is cumulative since the last `pg_stat_reset()` call, so a single large sequential scan can pull the ratio down temporarily.

**Task 6 - Connection Limit Test**

- The exact error message is:
  ```
  FATAL:  too many connections for database "labdb"
  ```
  This is different from the server-wide limit error, which says:
  ```
  FATAL:  sorry, too many clients already
  ```
  The database-level message specifically names the database, which helps you pinpoint the cause immediately. In a production incident, this error in your application logs means either traffic spiked beyond expectations, a connection leak is occurring, or the database-level limit is set too low. Check `pg_stat_activity` and `pg_database.datconnlimit` first.

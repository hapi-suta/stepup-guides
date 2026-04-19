# Build 01: Process Architecture

**Lab 2.1 - Process Architecture Explorer**
**Time:** 45 minutes
**Node:** NODE1 only

In this lab you will explore how PostgreSQL organizes its work across multiple operating system processes. By the end, you will be able to identify every process PostgreSQL runs, understand what each one does, and safely manage client connections.

## Prerequisites

- PostgreSQL 16 installed and running on NODE1 (from the backup-pitr lab)
- Data directory at `/opt/pgsql/data`

---

## 1. The Postmaster Process

**Run on NODE1 (pg-primary):**

The postmaster is the very first PostgreSQL process that starts. It is the parent of every other PostgreSQL process. Its job is to listen for new client connections and spawn a dedicated backend process for each one.

Log in to NODE1 as `ec2-user`, then switch to root.

```bash
sudo su -
```

**You are now root.**

Switch to the postgres user.

```bash
su - postgres
```

**You are now the postgres user.**

List all processes that contain "postgres" in their name. The `aux` flags show all users (`a`), the user who owns each process (`u`), and processes not attached to a terminal (`x`).

```bash
ps aux | grep postgres
```

Expected output (yours will differ - PIDs and timestamps vary):

```
postgres   1234  0.0  0.5 215432 20480 ?  Ss   10:00   0:00 /usr/pgsql-16/bin/postgres -D /opt/pgsql/data
postgres   1236  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: checkpointer
postgres   1237  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: background writer
postgres   1238  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: walwriter
postgres   1239  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: autovacuum launcher
postgres   1240  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: logger
postgres   1241  0.0  0.1 215432  4096 ?  Ss   10:00   0:00 postgres: archiver
```

The very first line - the one that shows the `-D /opt/pgsql/data` flag - is the postmaster. Every other PostgreSQL process is a child of this one.

> **Concept: One postmaster per cluster.**
> A PostgreSQL "cluster" is a single data directory managed by one postmaster. If you run two separate data directories on the same server, each one has its own postmaster on its own port. The postmaster's PID is stored in `postmaster.pid` inside the data directory.

---

## 2. Background Processes

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

PostgreSQL starts several background worker processes automatically. Each one handles a specific housekeeping task so that client queries can focus on reading and writing data.

Run the same `ps` command again and look at the lines after the postmaster.

```bash
ps aux | grep postgres
```

Here is what each background process does:

| Process | Role |
|---|---|
| **checkpointer** | Periodically writes all dirty (modified) buffers from shared memory to disk. This creates a known recovery point. |
| **background writer** (bgwriter) | Gradually writes dirty buffers to disk between checkpoints to reduce the I/O spike when the checkpointer runs. |
| **walwriter** | Flushes WAL (Write-Ahead Log) buffers from shared memory to WAL files on disk. This ensures committed transactions are durable. |
| **autovacuum launcher** | Starts autovacuum worker processes to clean up dead tuples left behind by UPDATE and DELETE operations. |
| **logger** | Writes server log messages to the log file. |
| **archiver** | Copies completed WAL segments to the archive location (if archive_mode is enabled). |
| **logical replication launcher** | Manages logical replication workers if logical replication is configured. You may or may not see this process. |

You can also query PostgreSQL directly to see background processes. Connect to the database using psql. The `-x` flag displays results in expanded (vertical) format, which is easier to read for wide rows.

```bash
psql
```

Run this query to list background processes. The `pg_stat_activity` view shows every process connected to PostgreSQL. Filtering out `client backend` leaves only the internal workers.

```sql
SELECT pid, backend_type FROM pg_stat_activity WHERE backend_type != 'client backend';
```

Expected output (yours will differ - PIDs vary):

```
  pid  |       backend_type
-------+---------------------------
  1236 | checkpointer
  1237 | background writer
  1238 | walwriter
  1239 | autovacuum launcher
  1240 | logical replication launcher
  1241 | archiver
(6 rows)
```

Stay in the psql session for the next section.

> **Concept: Background workers are not optional.**
> You cannot disable the checkpointer or walwriter - PostgreSQL will not start without them. The bgwriter and autovacuum launcher can technically be disabled, but doing so in production causes serious performance problems. Treat all background workers as essential.

---

## 3. Client Backend Processes

**Run on NODE1 (pg-primary):**

**You are still in the psql session as the postgres user.**

Every time a client connects to PostgreSQL (including your psql session right now), the postmaster creates a new backend process just for that connection. That backend handles all queries for that single client.

Run this query to see your own backend process. The `pg_stat_activity` view tracks every connection. Filtering for `client backend` shows only user-facing sessions.

```sql
SELECT pid, usename, application_name, state, query FROM pg_stat_activity WHERE backend_type = 'client backend';
```

Expected output (yours will differ - PID and query text vary):

```
  pid  | usename  | application_name | state  |                              query
-------+----------+------------------+--------+------------------------------------------------------------------
  1301 | postgres | psql             | active | SELECT pid, usename, application_name, state, query FROM pg_...
(1 row)
```

Notice that the `state` column shows `active` because this query is currently running. The `application_name` column shows `psql` because that is the client tool you are using.

Stay in this psql session. You will need it open for the next section.

> **Concept: One process per connection.**
> PostgreSQL uses a process-per-connection model, not a thread-per-connection model. Each client gets its own OS process with its own memory. This is simple and safe (a crash in one backend does not take down others), but it means each connection costs real memory. This is why connection poolers like PgBouncer exist - they reduce the number of backend processes needed.

---

## 4. Watching Connections Grow

**Run on NODE1 (pg-primary):**

Keep your current psql session open. Open a second SSH session to NODE1 in a new terminal window.

In the new terminal, switch to root.

```bash
sudo su -
```

**You are now root.**

Switch to the postgres user.

```bash
su - postgres
```

**You are now the postgres user.**

Open a second psql session.

```bash
psql
```

Now run the same query to see client backends. You should see two rows - one for each psql session.

```sql
SELECT pid, usename, application_name, state, query FROM pg_stat_activity WHERE backend_type = 'client backend';
```

Expected output (yours will differ - PIDs vary):

```
  pid  | usename  | application_name | state  |                              query
-------+----------+------------------+--------+------------------------------------------------------------------
  1301 | postgres | psql             | idle   | SELECT pid, usename, application_name, state, query FROM pg_...
  1425 | postgres | psql             | active | SELECT pid, usename, application_name, state, query FROM pg_...
(2 rows)
```

Notice that the first session now shows `idle` - it is waiting for you to type something. The second session shows `active` because it is running this query right now.

Check the maximum number of connections PostgreSQL will allow. The `SHOW` command displays a server configuration parameter.

```sql
SHOW max_connections;
```

Expected output:

```
 max_connections
-----------------
 100
(1 row)
```

The default is 100. This means PostgreSQL will allow at most 100 simultaneous client connections (plus a few reserved for superusers). If you hit this limit, new connections are refused.

Exit this second psql session.

```sql
\q
```

Exit from the postgres user.

```bash
exit
```

**You are now root.**

Exit from root.

```bash
exit
```

**You are now ec2-user.**

Close this second terminal. Go back to your first terminal where the original psql session is still running.

> **Concept: max_connections is a hard ceiling.**
> Once all connection slots are used, PostgreSQL returns "FATAL: too many connections" and refuses new clients. In production, set `max_connections` based on available memory (each backend uses roughly 5-10 MB), and use a connection pooler for applications that open many short-lived connections.

---

## 5. Process Hierarchy

**Run on NODE1 (pg-primary):**

**You should still be in the psql session from Section 3 (first terminal).** Exit psql first.

```sql
\q
```

**You are now the postgres user.**

Use `pstree` to see the full process tree starting from the postmaster. The `-p` flag shows the PID of each process. The `head -1` command reads the first line of `postmaster.pid`, which contains the postmaster's PID.

```bash
pstree -p $(head -1 /opt/pgsql/data/postmaster.pid)
```

Expected output (yours will differ - PIDs vary):

```
postgres(1234)-+-postgres(1236)
               |-postgres(1237)
               |-postgres(1238)
               |-postgres(1239)
               |-postgres(1240)
               |-postgres(1241)
               |-postgres(1242)
```

This tree shows the postmaster (PID 1234) as the parent of all background workers. If any client backends were connected, they would also appear as children of the postmaster.

If `pstree` is not installed, install it. The `psmisc` package contains `pstree` and other process utilities.

```bash
sudo dnf install -y psmisc
```

Then run the `pstree` command again.

```bash
pstree -p $(head -1 /opt/pgsql/data/postmaster.pid)
```

> **Concept: The postmaster is the supervisor.**
> If a background worker crashes, the postmaster detects it and restarts all processes to recover to a consistent state. If a client backend crashes, the postmaster terminates all other backends, runs crash recovery, and then starts accepting connections again. This is why you should never kill the postmaster directly - it coordinates the safe shutdown of everything else.

---

## 6. Terminating a Backend Safely

**Run on NODE1 (pg-primary):**

**You are still the postgres user.**

Sometimes you need to terminate a stuck or long-running connection. PostgreSQL gives you two functions for this:

| Function | Signal | What it does |
|---|---|---|
| `pg_cancel_backend(pid)` | SIGINT | Cancels the currently running query but keeps the connection open. |
| `pg_terminate_backend(pid)` | SIGTERM | Terminates the entire backend process and closes the connection. |

Open a psql session.

```bash
psql
```

First, find a backend to terminate. Run this query to see all client backends.

```sql
SELECT pid, usename, application_name, state FROM pg_stat_activity WHERE backend_type = 'client backend';
```

Expected output (yours will differ - PIDs vary):

```
  pid  | usename  | application_name | state
-------+----------+------------------+--------
  1501 | postgres | psql             | active
(1 row)
```

You only have one session right now (your own), so do not terminate it. Instead, open a second psql session from another terminal (as you did in Section 4), then come back here and re-run the query.

```sql
SELECT pid, usename, application_name, state FROM pg_stat_activity WHERE backend_type = 'client backend';
```

Expected output (yours will differ - PIDs vary):

```
  pid  | usename  | application_name | state
-------+----------+------------------+--------
  1501 | postgres | psql             | active
  1602 | postgres | psql             | idle
(1 row)
```

Now terminate the idle session. Replace `1602` with the actual PID from your output. The function returns `t` (true) if it successfully sent the termination signal.

```sql
SELECT pg_terminate_backend(1602);
```

Expected output:

```
 pg_terminate_backend
----------------------
 t
(1 row)
```

Verify the backend is gone by re-querying `pg_stat_activity`.

```sql
SELECT pid, usename, application_name, state FROM pg_stat_activity WHERE backend_type = 'client backend';
```

Expected output (yours will differ - PID varies):

```
  pid  | usename  | application_name | state
-------+----------+------------------+--------
  1501 | postgres | psql             | active
(1 row)
```

The terminated session is gone. If you switch to the other terminal, you will see that psql has exited with a message like "server closed the connection unexpectedly."

**WARNING: Never kill the postmaster process with `kill -9` or `pg_terminate_backend`. Killing the postmaster causes an immediate, unclean shutdown of the entire database. Always use `pg_ctl stop` for a clean shutdown.**

Stay in this psql session for the next section.

---

## 7. The postmaster.pid File

**Run on NODE1 (pg-primary):**

Exit psql.

```sql
\q
```

**You are now the postgres user.**

The `postmaster.pid` file is a lock file that PostgreSQL creates when it starts. It prevents two postmasters from running on the same data directory simultaneously.

Display the contents of the file. The `cat` command prints the file to your terminal.

```bash
cat /opt/pgsql/data/postmaster.pid
```

Expected output (yours will differ - PID, timestamps, and paths vary):

```
1234
/opt/pgsql/data
1713400800
5432
/run/postgresql
*
  1234001  65536
ready
```

Here is what each line means:

| Line | Content | Description |
|---|---|---|
| 1 | `1234` | The postmaster's PID |
| 2 | `/opt/pgsql/data` | The data directory path |
| 3 | `1713400800` | The postmaster start time (Unix epoch) |
| 4 | `5432` | The port PostgreSQL is listening on |
| 5 | `/run/postgresql` | The Unix socket directory |
| 6 | `*` | The listen address (`*` means all interfaces) |
| 7 | `1234001  65536` | Shared memory key and segment ID |
| 8 | `ready` | Server startup status (indicates PostgreSQL has completed startup and is accepting connections) |

If PostgreSQL crashes without cleaning up, this file is left behind. On the next startup, PostgreSQL checks whether the PID in the file is still running. If it is not, PostgreSQL removes the stale file and starts normally. If it is, PostgreSQL refuses to start to prevent data corruption.

> **Concept: postmaster.pid prevents split-brain.**
> Two PostgreSQL instances writing to the same data directory would corrupt it immediately. The `postmaster.pid` lock file is one of several safeguards (along with shared memory checks) that prevent this. Never delete this file manually while PostgreSQL is running.

---

## Checkpoint

Before moving on, verify you can do everything in this list:

- [x] Can identify the postmaster process using `ps aux`
- [x] Can name all background worker processes and their roles (checkpointer, bgwriter, walwriter, autovacuum launcher, logical replication launcher)
- [x] Can find client backends in `pg_stat_activity`
- [x] Understand the `max_connections` limit and what happens when it is reached
- [x] Can view the process tree with `pstree`
- [x] Can safely terminate a backend using `pg_terminate_backend(pid)`
- [x] Understand the contents of `postmaster.pid` and why it exists

---

**Next:** [02-memory-architecture.md](./02-memory-architecture.md) - Explore shared_buffers, work_mem, and how PostgreSQL manages memory.

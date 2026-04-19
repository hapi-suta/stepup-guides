# Exercise 01 - Process Investigation

**Time estimate:** 20-25 minutes
**Prerequisites:** BUILD phase complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb (pgbench data), postgres user, PGDATA at `/opt/pgsql/data`, WAL at `/opt/pgsql/wal`, logs at `/opt/pgsql/log`. Extensions installed: pg_buffercache, pageinspect, pgstattuple.

---

## Objective

Identify every PostgreSQL background process, map each one to its role, and prove that the postmaster is the parent of all. By the end of this exercise, you should be able to name every process in a running PostgreSQL cluster from memory and explain when to use `pg_cancel_backend` vs `pg_terminate_backend`.

---

## Step 1 - List All PostgreSQL Processes

On **NODE1** (pg-primary):

```bash
ps aux | grep postgres | grep -v grep
```

(`grep -v grep` removes the grep process itself from the results.)

**Expected:** You will see a list of processes including the postmaster and several background workers. Each line shows the process owner (`postgres`), PID, and a description such as `checkpointer`, `background writer`, `walwriter`, `autovacuum launcher`, `archiver`, `logger`, and `logical replication launcher`.

> **Concept:** The postmaster is the first PostgreSQL process that starts. It listens for new connections and spawns all background workers. Every other PostgreSQL process is a child of the postmaster. If the postmaster dies, all child processes terminate - this is by design for crash safety.

---

## Step 2 - Visualize the Process Tree

Switch to the postgres user to read files inside PGDATA (which has mode 0700 and is owned by postgres):

```bash
sudo -iu postgres
```

Read the first line of the postmaster PID file to get the postmaster PID:

```bash
head -1 /opt/pgsql/data/postmaster.pid
```

**Expected:** A single number - the PID of the postmaster process (e.g., `9593`).

Now use that PID to display the full process tree. Replace `<PID>` with the number from the previous command:

```bash
pstree -pa <PID>
```

(`-p` shows PIDs in parentheses. `-a` shows the command-line arguments so you can identify each process.)

**Expected:** A tree structure with the postmaster at the root and all background workers as children:

```
postgres,9593 -D /opt/pgsql/data
  |-postgres,9594
  |-postgres,9595
  |-postgres,9596
  |-postgres,9598
  |-postgres,9599
  |-postgres,9600
  |-postgres,9601
```

Each child is a direct descendant of the postmaster. You can cross-reference these PIDs with the `ps aux` output from Step 1 to identify which process is the checkpointer, background writer, walwriter, etc.

> **Concept:** The process tree proves the parent-child relationship. The postmaster (PID from `postmaster.pid`) is the root. Every background worker and every client backend is a direct child. This matters operationally because sending `kill -9` to the postmaster kills all children and triggers immediate-mode shutdown - data corruption is possible. Never do this in production.

---

## Step 3 - Read the postmaster.pid File

You should still be the postgres user from Step 2. Examine every line of the PID file:

```bash
cat /opt/pgsql/data/postmaster.pid
```

**Expected:** Eight lines of output:

```
9593                  <- postmaster PID
/opt/pgsql/data       <- PGDATA directory
1776560882            <- postmaster start timestamp (Unix epoch)
5432                  <- port number
/run/postgresql       <- Unix socket directory
*                     <- listen_addresses (* means all interfaces)
  5824    1           <- shared memory key and ID
ready                 <- server status
```

(Your PID, timestamp, and shared memory key will differ.)

> **Concept:** PostgreSQL writes this file at startup and removes it at clean shutdown. If PostgreSQL crashes, the file remains - a new startup checks for it and refuses to start if a process with that PID is still running. This prevents two instances from using the same data directory simultaneously, which would cause corruption. The shared memory key on line 7 identifies the System V shared memory segment. The 8th line (`ready`) indicates the server has completed startup and is accepting connections.

```bash
exit
```

---

## Step 4 - Open Concurrent Sessions and Observe pg_stat_activity

Open 5 background psql sessions. Run each of these commands one at a time:

```bash
psql -U postgres -d labdb -c "SELECT pg_sleep(600);" &
```

```bash
psql -U postgres -d labdb -c "SELECT pg_sleep(600);" &
```

```bash
psql -U postgres -d labdb -c "SELECT pg_sleep(600);" &
```

```bash
psql -U postgres -d labdb -c "SELECT pg_sleep(600);" &
```

```bash
psql -U postgres -d labdb -c "SELECT pg_sleep(600);" &
```

Each `&` sends the psql session to the background. The `-U postgres` flag connects as the postgres user. The `pg_sleep(600)` keeps each session alive for 10 minutes.

Now connect to labdb and check what is happening:

```bash
sudo -iu postgres
```

```bash
psql -d labdb
```

Run this query to see all connections:

```sql
SELECT pid, state, query, backend_type, wait_event_type, wait_event
FROM pg_stat_activity
WHERE datname = 'labdb';
```

**Expected:** You will see your 5 sleeping sessions with `state = 'active'` (they are actively running pg_sleep), plus your current session. The `wait_event_type` for the sleeping sessions will show `Timeout` and the `wait_event` will show `PgSleep`.

> **Concept:** `pg_stat_activity` is the most important view for diagnosing connection issues. The `state` column tells you whether a backend is `active` (running a query), `idle` (connected but not doing anything), `idle in transaction` (in an open transaction but not running a query - dangerous for long periods), or `idle in transaction (aborted)` (in a failed transaction). In production, `idle in transaction` backends are a common source of problems because they hold locks and prevent VACUUM.

---

## Step 5 - Cancel a Running Query

From your psql session connected to labdb, find the PID of one of the sleeping sessions:

```sql
SELECT pid, state, query
FROM pg_stat_activity
WHERE datname = 'labdb' AND query LIKE '%pg_sleep%' AND pid != pg_backend_pid()
LIMIT 1;
```

Note the PID. Now cancel it. Replace `<PID>` with the actual PID number:

```sql
SELECT pg_cancel_backend(<PID>);
```

**Expected:** Returns `t` (true). The target session receives a `QueryCanceled` error, but the connection stays alive. The session returns to `idle` state.

> **Concept:** `pg_cancel_backend` sends a SIGINT to the target backend. It cancels the current query but keeps the connection open. This is the polite way to stop a long-running query. The client can immediately run another query on the same connection. Use this as your first response to a runaway query.

---

## Step 6 - Terminate a Backend

Find another sleeping session PID:

```sql
SELECT pid, state, query
FROM pg_stat_activity
WHERE datname = 'labdb' AND query LIKE '%pg_sleep%' AND pid != pg_backend_pid()
LIMIT 1;
```

Now terminate it. Replace `<PID>` with the actual PID number:

```sql
SELECT pg_terminate_backend(<PID>);
```

**Expected:** Returns `t` (true). The target backend process exits entirely. The client connection is closed - the client will see a "server closed the connection unexpectedly" error.

> **Concept:** `pg_terminate_backend` sends a SIGTERM to the target backend. It kills the connection entirely - the client must reconnect. Use this when `pg_cancel_backend` does not work (some operations cannot be canceled), or when you need to free the connection slot immediately. The escalation path is: cancel first, terminate if cancel fails. Never use `kill -9` on individual backends - let PostgreSQL handle process cleanup.

---

## Step 7 - Clean Up Background Sessions

Exit psql:

```sql
\q
```

```bash
exit
```

Kill the remaining background psql processes:

```bash
kill %1 %2 %3 2>/dev/null
```

The `%1`, `%2`, `%3` refer to background jobs. Some may already be gone from the cancel/terminate steps.

Verify no orphaned sessions remain:

```bash
sudo -iu postgres
```

```bash
psql -d labdb -c "SELECT count(*) FROM pg_stat_activity WHERE datname = 'labdb';"
```

**Expected:** A small number (1 or 2) - just your current connection.

```bash
exit
```

---

## Checkpoint

Before continuing, confirm:
- [ ] You listed all PostgreSQL background processes and can name at least 5 from memory
- [ ] You used `pstree` to prove the postmaster is the parent of all processes
- [ ] You read all 8 lines of `postmaster.pid` and know what each line contains
- [ ] You observed active sessions in `pg_stat_activity`
- [ ] You used `pg_cancel_backend` and understand it cancels the query but keeps the connection
- [ ] You used `pg_terminate_backend` and understand it kills the connection entirely
- [ ] You know the escalation path: cancel first, terminate second, never `kill -9`

---

**Next:** [02 - Memory Pressure Analysis](02-memory-pressure-analysis.md)

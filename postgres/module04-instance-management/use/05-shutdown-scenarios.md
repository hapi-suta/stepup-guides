# Exercise 05: Shutdown Scenarios

**Duration:** 20 minutes
**Objective:** Create a temporary test cluster and experience all three PostgreSQL shutdown modes (smart, fast, immediate) firsthand. Understand when to use each one in production.

**Prerequisites:** PG16 running on port 5432 (`/opt/pgsql/data`). Single node. This exercise uses a throwaway cluster so your main PG16 cluster is never at risk.

---

## Background

PostgreSQL has three shutdown modes:

| Mode | Behavior | Production use |
|------|----------|----------------|
| `smart` | Waits for all clients to disconnect | Rarely - clients may never disconnect |
| `fast` | Disconnects all clients, then shuts down cleanly | **Default for systemctl stop** - use this |
| `immediate` | Kills everything instantly, like pulling the power cord | Last resort only |

You need to experience all three to understand the difference. We will use a temporary cluster so there is zero risk to your main database.

---

## Step 1: Create the test cluster

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create the data directory for the test cluster.

```bash
mkdir -p /opt/pgsql/data-shutdown
```

Initialize a new cluster with data checksums enabled.

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data-shutdown --data-checksums
```

The `-D` flag specifies the data directory. The `--data-checksums` flag enables page-level checksums.

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data-shutdown -l logfile start
```

Now set the port to 5436 so it does not conflict with your other clusters.

```bash
vi /opt/pgsql/data-shutdown/postgresql.conf
```

Press `/` then type `port` and press `Enter` to search. Press `n` until you find the line:

```
#port = 5432
```

Press `i` to enter insert mode. Change it to:

```
port = 5436
```

Remove the `#` at the beginning (that is the comment character). Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Stay as the postgres user for the next step.

---

## Step 2: Start the test cluster

Start the cluster using `pg_ctl`. We use `pg_ctl` instead of `systemctl` because we did not create a systemd service file for this temporary cluster.

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/data-shutdown/server.log
```

The `-l` flag specifies where to write the server log.

Expected output (yours will differ):

```
waiting for server to start.... done
server started
```

Verify it is running.

```bash
/usr/pgsql-16/bin/pg_isready -p 5436
```

Expected output (yours will differ):

```
/run/postgresql:5436 - accepting connections
```

Stay as the postgres user for all remaining steps.

---

## Step 3: Test smart shutdown

Smart shutdown waits for all clients to disconnect voluntarily. If a client is running a long query, the server waits.

Open a psql session to the test cluster and start a long-running query.

```bash
psql -p 5436 -c "SELECT pg_sleep(300);"  &
```

The `&` at the end runs this command in the background so you can continue using the terminal. `pg_sleep(300)` sleeps for 300 seconds (5 minutes).

Wait a moment, then try a smart shutdown.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m smart
```

The `-m smart` flag requests a smart (polite) shutdown.

Expected output (yours will differ):

```
waiting for server to shut down...........
```

The server is waiting for the `pg_sleep` query to finish. It will keep printing dots.

Press `Ctrl+C` to stop watching.

Expected output (yours will differ):

```
^C
```

**This is a common misunderstanding: Ctrl+C does not cancel the shutdown.** It only kills the `pg_ctl` foreground process that was polling and printing dots. The smart-shutdown request was already delivered to the postmaster, and the postmaster does not forget it. The server process is still running, but it is no longer accepting new connections - it is waiting for the `pg_sleep` client to disconnect before it can finish shutting down.

Verify this - the server should now be rejecting connections, not accepting them.

```bash
/usr/pgsql-16/bin/pg_isready -p 5436
```

Expected output (yours will differ):

```
/run/postgresql:5436 - rejecting connections
```

Try to open a new connection to prove it.

```bash
psql -p 5436 -c "SELECT 1;"
```

Expected output (yours will differ):

```
psql: error: connection to server on socket "/run/postgresql/.s.PGSQL.5436" failed: FATAL:  the database system is shutting down
```

There is no PostgreSQL command that un-does a pending shutdown once it has been requested. The only way out of this state is to wait for the blocking client to disconnect on its own, or to escalate to a stronger shutdown mode - which is exactly what fast shutdown does next.

---

## Step 4: Test fast shutdown

Fast shutdown disconnects all clients immediately but performs a clean shutdown. This is the safest way to stop a server that has active connections. It is also how you escalate out of the stuck smart shutdown from Step 3 - the `pg_sleep` session is still connected and the postmaster is still waiting on it.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m fast
```

The `-m fast` flag tells PostgreSQL to terminate all connections and shut down cleanly.

Expected output (yours will differ):

```
waiting for server to shut down.... done
server stopped
```

You will also see the killed `pg_sleep` session print its own connection-lost error to the terminal, followed by the shell's background job notification:

```
FATAL:  terminating connection due to administrator command
server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.
connection to server was lost
[1]+  Exit 2                  psql -p 5436 -c "SELECT pg_sleep(300);"
```

Verify the server is stopped.

```bash
/usr/pgsql-16/bin/pg_isready -p 5436
```

Expected output (yours will differ):

```
/run/postgresql:5436 - no response
```

### Explanation

Fast shutdown sends SIGTERM to all backend processes, which causes them to exit cleanly. All in-progress transactions are rolled back. A checkpoint is performed to flush dirty pages to disk. No recovery is needed on the next start. This is the default mode for `systemctl stop`.

---

## Step 5: Test immediate shutdown

Start the cluster again.

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/data-shutdown/server.log
```

Expected output (yours will differ):

```
waiting for server to start.... done
server started
```

Write some data first, so there is something for crash recovery to replay in Step 6.

```bash
psql -p 5436 -c "CREATE TABLE test_write (id int); INSERT INTO test_write SELECT generate_series(1,1000);"
```

Expected output (yours will differ):

```
CREATE TABLE
INSERT 0 1000
```

Open a psql session in the background.

```bash
psql -p 5436 -c "SELECT pg_sleep(300);" &
```

Now perform an immediate shutdown.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m immediate
```

The `-m immediate` flag kills all processes instantly without a clean shutdown.

Expected output (yours will differ):

```
waiting for server to shut down....WARNING:  terminating connection due to immediate shutdown command
server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.
connection to server was lost
 done
server stopped
```

This completes almost instantly, unlike the smart shutdown.

---

## Step 6: Start again and observe recovery

Start the cluster after the immediate shutdown.

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/data-shutdown/server.log
```

Expected output (yours will differ):

```
waiting for server to start.... done
server started
```

Check the server log for recovery messages. This cluster has `logging_collector = on` (the PGDG package default), so after startup PostgreSQL stops writing to the `-l server.log` file and switches to its own rotating log inside `PGDATA/log/` - `server.log` only ever shows a one-line "redirecting log output to logging collector process" notice. The real messages are in `log/postgresql-<day>.log`.

```bash
tail -20 /opt/pgsql/data-shutdown/log/postgresql-*.log
```

The `tail -20` command shows the last 20 lines of the log file. The `*` wildcard matches today's log regardless of which day of the week it is (the filename pattern is `postgresql-%a.log`, e.g. `postgresql-Wed.log`).

Expected output (yours will differ):

```
LOG:  database system was interrupted; last known up at 2026-08-05 18:57:01 UTC
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/177CF10
LOG:  invalid record length at 0/17A5E00: expected at least 24, got 0
LOG:  redo done at 0/17A5C68 system usage: CPU: user: 0.00 s, system: 0.00 s, elapsed: 0.00 s
LOG:  checkpoint starting: end-of-recovery immediate wait
LOG:  checkpoint complete: wrote 32 buffers (0.2%); 0 WAL file(s) added, 0 removed, 0 recycled; write=0.002 s, sync=0.004 s, total=0.014 s; sync files=23, longest=0.002 s, average=0.001 s; distance=163 kB, estimate=163 kB; lsn=0/17A5E00, redo lsn=0/17A5E00
LOG:  database system is ready to accept connections
```

If you skipped the `CREATE TABLE`/`INSERT` above, you will most likely see `LOG:  redo is not required` instead of the `redo starts at` / `redo done at` pair - that just means there was no WAL activity since the last checkpoint for PostgreSQL to replay.

### Explanation

After an immediate shutdown, PostgreSQL performs **crash recovery** on the next start:

1. `database system was not properly shut down` - PostgreSQL detected the unclean shutdown
2. `automatic recovery in progress` - it is replaying WAL from the last checkpoint
3. `redo starts at` / `redo done at` - the WAL range that needed to be replayed

This recovery process is automatic and safe - it is the same mechanism that protects your data after a power failure. However, recovery takes time proportional to the amount of WAL generated since the last checkpoint. On a busy production server, this could be minutes.

---

## Step 7: Clean up

Stop the test cluster.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m fast
```

Expected output (yours will differ):

```
waiting for server to shut down.... done
server stopped
```

Remove the test data directory.

```bash
rm -rf /opt/pgsql/data-shutdown
```

The `-rf` flags mean recursive (delete directory and all contents) and force (do not prompt for confirmation).

Verify it is gone.

```bash
ls /opt/pgsql/data-shutdown
```

Expected output:

```
ls: cannot access '/opt/pgsql/data-shutdown': No such file or directory
```

Verify your main PG16 cluster is still running and unaffected.

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output (yours will differ):

```
/run/postgresql:5432 - accepting connections
```

Exit back to ec2-user.

```bash
exit
```

---

## Summary

| Mode | Command | Behavior | Recovery needed? | When to use |
|------|---------|----------|-----------------|-------------|
| smart | `pg_ctl stop -m smart` | Waits for all clients to disconnect | No | Almost never in production |
| fast | `pg_ctl stop -m fast` | Disconnects all clients, clean shutdown | No | **Standard production shutdown** |
| immediate | `pg_ctl stop -m immediate` | Kills everything instantly | **Yes** | Last resort when fast hangs |

Key takeaways:

- `systemctl stop` uses fast mode by default - this is correct for production
- Smart shutdown sounds nice but can hang forever if a client never disconnects
- Immediate shutdown is safe (crash recovery handles it) but wastes time on the next startup
- Always check the server log after an immediate shutdown to confirm recovery completed

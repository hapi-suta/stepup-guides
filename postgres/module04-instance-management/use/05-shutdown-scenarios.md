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
/var/run/postgresql:5436 - accepting connections
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

Press `Ctrl+C` to cancel the shutdown attempt.

Expected output (yours will differ):

```
^C
```

The server is still running. The smart shutdown was canceled.

Verify the server is still up.

```bash
/usr/pgsql-16/bin/pg_isready -p 5436
```

Expected output (yours will differ):

```
/var/run/postgresql:5436 - accepting connections
```

---

## Step 4: Test fast shutdown

Fast shutdown disconnects all clients immediately but performs a clean shutdown. This is the safest way to stop a server that has active connections.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m fast
```

The `-m fast` flag tells PostgreSQL to terminate all connections and shut down cleanly.

Expected output (yours will differ):

```
waiting for server to shut down.... done
server stopped
```

You may also see background job output from the killed psql session:

```
[1]+  Exit 2                  psql -p 5436 -c "SELECT pg_sleep(300);"
```

Verify the server is stopped.

```bash
/usr/pgsql-16/bin/pg_isready -p 5436
```

Expected output (yours will differ):

```
/var/run/postgresql:5436 - no response
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
waiting for server to shut down.... done
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

Check the server log for recovery messages.

```bash
tail -20 /opt/pgsql/data-shutdown/server.log
```

The `tail -20` command shows the last 20 lines of the log file.

Expected output (yours will differ):

```
LOG:  database system was interrupted; last known up at ...
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/15A2C28
LOG:  invalid record length at 0/15A2CA0: expected at least 24, got 0
LOG:  redo done at 0/15A2C60 system usage: ...
LOG:  database system is ready to accept connections
```

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
/var/run/postgresql:5432 - accepting connections
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

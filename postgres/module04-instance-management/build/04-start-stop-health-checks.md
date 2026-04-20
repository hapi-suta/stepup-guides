# Module 04 - Creating and Managing Instances
## Guide 04: Server Start, Stop, and Health Checks

**Objective:** Understand the two tools for managing PostgreSQL server lifecycle (`pg_ctl` and `systemctl`), practice the three shutdown modes (smart, fast, immediate), learn health check techniques, and know where to find server logs.

**Time:** 25-30 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432 with PGDATA at `/opt/pgsql/data`

**Important:** This guide uses a temporary test cluster for all shutdown experiments. The main PG16 cluster on port 5432 is never stopped.

---

## 1. pg_ctl Overview

`pg_ctl` is PostgreSQL's own process manager. It can start, stop, restart, and reload a cluster. It talks directly to the `postmaster` process (the main PostgreSQL daemon) using signals and the PID file.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Check the status of the PG16 cluster using `pg_ctl`. The `status` subcommand reads the PID file to determine if the server is running:

```bash
/usr/pgsql-16/bin/pg_ctl status -D /opt/pgsql/data
```

Expected output (yours will differ):

```
pg_ctl: server is running (PID: 1234)
/usr/pgsql-16/bin/postgres "-D" "/opt/pgsql/data"
```

The output shows two things: the process ID of the running postmaster (1234 in this example) and the exact command line that started the server. If the server were stopped, you would see `pg_ctl: no server running`.

Exit the postgres session:

```bash
exit
```

---

## 2. pg_ctl vs systemctl

Both tools can start, stop, and restart PostgreSQL, but they serve different purposes.

| Feature | pg_ctl | systemctl |
|---------|--------|-----------|
| **Who runs it** | `postgres` user | Root or sudo |
| **Start on boot** | No (manual only) | Yes (with `enable`) |
| **Restart on crash** | No | Yes (with `Restart=on-failure`) |
| **Log integration** | Writes to file you specify with `-l` | Integrates with journald |
| **Best for** | Ad-hoc clusters, testing, development | Production services |
| **Knows about PGDATA** | You pass `-D` every time | Reads `PGDATA` from the unit file |

Check the status with systemctl:

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since ...
   Main PID: 1234 (postmaster)
     ...
```

The `enabled` status means it starts automatically on boot. The `active (running)` status means it is running now.

**Rule of thumb:** Use `systemctl` for any cluster that runs in production. Use `pg_ctl` for test clusters and one-off operations.

---

## 3. Shutdown Modes

PostgreSQL has three shutdown modes, each with different behavior toward active connections. You will test all three using a temporary test cluster - never experiment with shutdown modes on a production database.

**Create the test cluster:**

Switch to root:

```bash
sudo su -
```

Create and configure the test directory:

```bash
mkdir /opt/pgsql/data-shutdown
```

```bash
chown postgres:postgres /opt/pgsql/data-shutdown
```

```bash
chmod 700 /opt/pgsql/data-shutdown
```

Exit root:

```bash
exit
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Initialize the test cluster:

```bash
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data-shutdown --data-checksums --locale=en_US.UTF-8 --encoding=UTF8
```

Expected output (yours will differ):

```
...
Data page checksums are enabled.
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data-shutdown -l logfile start
```

Set the port to 5436 so it does not conflict with existing clusters:

```bash
vi /opt/pgsql/data-shutdown/postgresql.conf
```

Find the `#port = 5432` line and change it to:

```
port = 5436
```

Save and exit vi (`:wq`).

Start the test cluster:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/log/pg-shutdown-test.log
```

Expected output:

```
waiting for server to start.... done
server started
```

Create some test data so the cluster has something to work with:

```bash
psql -p 5436 -c "CREATE TABLE shutdown_test (id serial, data text);"
```

Expected output:

```
CREATE TABLE
```

```bash
psql -p 5436 -c "INSERT INTO shutdown_test (data) SELECT 'row ' || g FROM generate_series(1, 1000) g;"
```

Expected output:

```
INSERT 0 1000
```

### 3a. Smart Shutdown (mode: smart)

Smart shutdown refuses new connections and waits for all existing connections to disconnect on their own. It is the gentlest mode but can hang forever if a connection never closes.

First, open a connection that will stay open. Start a psql session on port 5436 and leave it connected:

```bash
psql -p 5436 -c "SELECT pg_backend_pid();"
```

Expected output (yours will differ):

```
 pg_backend_pid
----------------
          54321
(1 row)
```

Now open a second SSH session to your server. In that second session, switch to postgres and try a smart shutdown:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m smart &
```

Expected output:

```
waiting for server to shut down......
```

The server is waiting. It will not shut down until all connections close. Go back to your first SSH session and exit the psql connection:

```bash
psql -p 5436 -c "SELECT 1;"
```

Expected output:

```
FATAL:  the database system is shutting down
```

The cluster is rejecting new connections but waiting for existing ones. Since we already disconnected from the previous `psql -c` command (which exits immediately), the smart shutdown should complete. Check in your second SSH session.

Expected output in the second session:

```
waiting for server to shut down.... done
server stopped
```

Start the cluster again for the next test:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/log/pg-shutdown-test.log
```

Expected output:

```
waiting for server to start.... done
server started
```

### 3b. Fast Shutdown (mode: fast)

Fast shutdown rolls back all active transactions and forcefully disconnects all clients. This is the default mode and the one you will use most often.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Fast shutdown is clean and safe. All data is flushed to disk, a checkpoint is performed, and the cluster records a clean shutdown in `pg_control`. No recovery is needed on the next start.

> **Concept: Smart vs fast shutdown**
> In practice, almost everyone uses fast shutdown (`-m fast`). Smart shutdown sounds polite, but it can hang indefinitely if an application holds a connection open. Fast shutdown is still safe - it rolls back incomplete transactions (just like a normal `ROLLBACK`) and performs a clean checkpoint. It is the default when you run `pg_ctl stop` without specifying a mode.

Start the cluster again:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/log/pg-shutdown-test.log
```

Expected output:

```
waiting for server to start.... done
server started
```

### 3c. Immediate Shutdown (mode: immediate)

Immediate shutdown is like pulling the power cord. The server process exits immediately without flushing data or performing a checkpoint. The cluster will need WAL recovery on the next startup.

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown -m immediate
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

The shutdown happens almost instantly because the server skips checkpoint and cleanup. Check `pg_controldata` to see the cluster state:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-shutdown | grep "cluster state"
```

Expected output:

```
Database cluster state:               in production
```

The state says `in production` even though the server is stopped. This is the sign of an unclean shutdown. The cluster thinks it is still running because no checkpoint was performed.

> **Concept: WAL recovery after immediate shutdown**
> When PostgreSQL starts after an unclean shutdown, it replays the WAL (Write-Ahead Log) to recover any data that was in memory but not yet written to disk. This is the same recovery mechanism used after a power failure or server crash. It is safe and automatic, but it adds time to the startup process. On a busy server with lots of WAL, recovery can take minutes.

Start the cluster and watch for the recovery message:

```bash
/usr/pgsql-16/bin/pg_ctl start -D /opt/pgsql/data-shutdown -l /opt/pgsql/log/pg-shutdown-test.log
```

Expected output:

```
waiting for server to start.... done
server started
```

Check the log for recovery activity. Since `logging_collector` is enabled by default, recovery messages go to the data directory's log subdirectory:

```bash
tail -10 /opt/pgsql/data-shutdown/log/postgresql-*.log
```

Expected output (yours will differ):

```
LOG:  database system was interrupted; last known up at ...
LOG:  database system was not properly shut down; automatic recovery in progress
LOG:  redo starts at 0/...
LOG:  invalid record length at 0/...
LOG:  redo done at 0/...
LOG:  database system is ready to accept connections
```

The `was not properly shut down; automatic recovery in progress` message confirms WAL recovery happened. After recovery, check the cluster state:

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-shutdown | grep "cluster state"
```

Expected output:

```
Database cluster state:               in production
```

Now it says `in production` correctly because the server is running and healthy after recovery.

Here is a summary of the three modes:

| Mode | Flag | Behavior | Recovery Needed? | Use When |
|------|------|----------|-----------------|----------|
| Smart | `-m smart` | Waits for all connections to close | No | Almost never (can hang forever) |
| Fast | `-m fast` | Rolls back transactions, disconnects clients | No | Normal maintenance and restarts |
| Immediate | `-m immediate` | Kills all processes instantly | Yes (WAL replay) | Emergency only (server is unresponsive) |

Exit the postgres session:

```bash
exit
```

---

## 4. Reload Without Restart

Reloading re-reads configuration files without stopping the server. No connections are dropped. This is safe for any setting with `context = 'sighup'` in `pg_settings`.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

There are three equivalent ways to reload. All send the SIGHUP signal to the postmaster process.

**Method 1: pg_ctl reload.** Run from the shell as the `postgres` user:

```bash
/usr/pgsql-16/bin/pg_ctl reload -D /opt/pgsql/data
```

Expected output:

```
server signaled
```

**Method 2: pg_reload_conf() function.** Run from inside psql:

```bash
psql -p 5432 -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Exit the postgres session:

```bash
exit
```

**Method 3: systemctl reload.** Run as ec2-user with sudo:

```bash
sudo systemctl reload postgresql-16
```

This produces no output on success. All three methods do the same thing. Use whichever matches your current context - psql session, postgres shell, or root/sudo shell.

---

## 5. Health Checks

Production PostgreSQL needs monitoring. Here are the tools for checking whether a cluster is alive and healthy.

### pg_isready

The `pg_isready` command is a lightweight connection check. It attempts a connection and reports the result:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

The exit code tells monitoring tools what happened:

| Exit Code | Meaning |
|-----------|---------|
| 0 | Server is accepting connections |
| 1 | Server is rejecting connections (e.g., during startup or smart shutdown) |
| 2 | No response (server is down or port is wrong) |

Check the exit code. The `$?` variable holds the exit code of the last command:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

```bash
echo $?
```

Expected output:

```
0
```

Check a port with no server:

```bash
/usr/pgsql-16/bin/pg_isready -p 9999
```

Expected output:

```
localhost:9999 - no response
```

```bash
echo $?
```

Expected output:

```
2
```

> **Concept: pg_isready exit codes in monitoring**
> Monitoring tools like Nagios, Zabbix, and Prometheus check the exit code of `pg_isready` to determine if PostgreSQL is healthy. Exit code 0 means healthy. Any other code triggers an alert. A simple cron job can use `pg_isready` to send notifications when a cluster goes down.

### postmaster.pid

The `postmaster.pid` file inside PGDATA contains essential process information. It is created when the server starts and removed when it shuts down cleanly.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

View the PID file:

```bash
cat /opt/pgsql/data/postmaster.pid
```

Expected output (yours will differ):

```
1234
/opt/pgsql/data
1713500000
5432
/tmp
localhost
  5432001   131073
```

> **Concept: postmaster.pid anatomy**
> Each line in `postmaster.pid` has a specific meaning: Line 1 is the process ID. Line 2 is the PGDATA path. Line 3 is the start timestamp (Unix epoch). Line 4 is the port number. Line 5 is the Unix socket directory. Line 6 is the listen address. Line 7 is shared memory information. If this file exists but the process is not running, PostgreSQL will refuse to start - you may need to remove the stale PID file manually (after confirming the process is truly gone).

Verify the PID is a real running process. First, read the PID from the file:

```bash
head -1 /opt/pgsql/data/postmaster.pid
```

Note the PID number from the output (for example, `1234`).

Now use `ps` to check if that process is running. Replace `<PID>` with the number from the previous command:

```bash
ps -p <PID> -o pid,user,command
```

Expected output (yours will differ):

```
    PID USER     COMMAND
   1234 postgres /usr/pgsql-16/bin/postgres -D /opt/pgsql/data
```

Exit the postgres session:

```bash
exit
```

---

## 6. Checking Server Logs

When something goes wrong, the server log is your first stop. PostgreSQL writes detailed messages during startup, shutdown, errors, and slow queries.

Check where logs are stored. If the logging collector is enabled (which we configured in Guide 02), logs go to the `log_directory` path:

```bash
sudo -iu postgres
```

```bash
psql -p 5432 -c "SELECT name, setting FROM pg_settings WHERE name IN ('log_directory', 'log_filename', 'logging_collector') ORDER BY name;"
```

Expected output (yours will differ):

```
        name        |          setting
--------------------+----------------------------
 log_directory      | /opt/pgsql/log
 log_filename       | postgresql-%Y-%m-%d.log
 logging_collector  | on
```

Exit psql and list the log files:

```bash
ls -lt /opt/pgsql/log/
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres  12543 Apr 19 11:30 postgresql-2026-04-19.log
-rw------- 1 postgres postgres   8901 Apr 18 23:59 postgresql-2026-04-18.log
-rw------- 1 postgres postgres   2345 Apr 19 10:00 pg-shutdown-test.log
...
```

View the last 10 lines of today's log. The `-10` flag shows the last 10 lines. The `$(date +%Y-%m-%d)` part inserts today's date in YYYY-MM-DD format to match the log filename pattern:

```bash
tail -10 /opt/pgsql/log/postgresql-$(date +%Y-%m-%d).log
```

Expected output (yours will differ):

```
2026-04-19 11:28:15.123 UTC [1234] LOG:  checkpoint starting: time
2026-04-19 11:28:15.456 UTC [1234] LOG:  checkpoint complete: wrote 5 buffers (0.0%); ...
...
```

Key log messages to look for:

| Message | What It Means |
|---------|---------------|
| `database system is ready to accept connections` | Server started successfully |
| `received fast shutdown request` | Fast shutdown was initiated |
| `database system is shut down` | Clean shutdown completed |
| `database system was not properly shut down` | Server crashed or immediate shutdown was used |
| `automatic recovery in progress` | WAL recovery is happening after a crash |
| `FATAL: password authentication failed` | Someone tried to connect with the wrong password |
| `LOG: duration: 5432.123 ms` | A query exceeded `log_min_duration_statement` |

You can also use `journalctl` to see logs for systemd-managed clusters:

```bash
exit
```

```bash
sudo journalctl -u postgresql-16 --no-pager -n 10
```

Expected output (yours will differ):

```
Apr 19 11:28:15 ip-10-0-1-100 postmaster[1234]: LOG:  checkpoint starting: time
Apr 19 11:28:15 ip-10-0-1-100 postmaster[1234]: LOG:  checkpoint complete: ...
...
```

The `-u` flag filters for a specific systemd unit. `--no-pager` prints output directly to the terminal instead of opening a scrollable viewer. The `-n 10` flag shows the last 10 entries.

---

## 7. Tear Down the Test Cluster

Clean up the shutdown test cluster.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Stop the test cluster:

```bash
/usr/pgsql-16/bin/pg_ctl stop -D /opt/pgsql/data-shutdown
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Exit the postgres session:

```bash
exit
```

Remove the data directory as root:

```bash
sudo su -
```

```bash
rm -rf /opt/pgsql/data-shutdown
```

Clean up the test log file:

```bash
rm -f /opt/pgsql/log/pg-shutdown-test.log
```

Exit root:

```bash
exit
```

Verify the main PG16 cluster is still running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output:

```
/run/postgresql:5432 - accepting connections
```

---

## Checkpoint

You have completed Guide 04. Verify you understand the following:

- [ ] You can check cluster status with `pg_ctl status -D <PGDATA>`
- [ ] You know when to use `pg_ctl` (test/dev clusters) vs `systemctl` (production services)
- [ ] You understand the three shutdown modes: smart (waits for connections), fast (rolls back and disconnects), immediate (like pulling the power cord)
- [ ] You know that fast shutdown is the default and the one to use for planned maintenance
- [ ] You know that immediate shutdown requires WAL recovery on next startup
- [ ] You can reload configuration three ways: `pg_ctl reload`, `pg_reload_conf()`, `systemctl reload`
- [ ] You can check server health with `pg_isready` and interpret exit codes (0=up, 1=rejecting, 2=down)
- [ ] You know the `postmaster.pid` file contains the PID, port, PGDATA, and shared memory info
- [ ] You can find and read server logs in `/opt/pgsql/log/` and via `journalctl`

---

You have completed all four guides in Module 04. You can now create clusters, configure them, manage multiple instances, and control their lifecycle.

Proceed to **Module 05 - SQL Fundamentals**

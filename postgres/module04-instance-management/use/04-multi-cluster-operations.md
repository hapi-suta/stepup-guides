# Exercise 04: Multi-Cluster Operations

**Duration:** 25 minutes
**Objective:** Practice managing two independent PostgreSQL clusters on the same server. Prove they are fully isolated, and learn the differences between `pg_ctl` and `systemctl`.

**Prerequisites:** PG16 running on port 5432 (`/opt/pgsql/data`), PG15 running on port 5433 (`/opt/pgsql/data15`). Single node.

---

## Background

Running multiple PostgreSQL versions on the same server is common during major version upgrades. You need to be confident that stopping one cluster does not affect the other, and that data is completely isolated between them.

---

## Step 1: Check status of both clusters

Use `pg_isready` to check if each cluster is accepting connections. This is a lightweight check that does not require authentication.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check PG16 on port 5432.

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

The `-p` flag specifies which port to check.

Expected output (yours will differ):

```
/run/postgresql:5432 - accepting connections
```

Check PG15 on port 5433.

```bash
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output (yours will differ):

```
/run/postgresql:5433 - accepting connections
```

Check the exit code of the last command.

```bash
echo $?
```

Expected output:

```
0
```

Exit back to ec2-user.

```bash
exit
```

### Understanding pg_isready exit codes

| Exit code | Meaning |
|-----------|---------|
| 0 | Server is accepting connections |
| 1 | Server is rejecting connections (e.g., starting up) |
| 2 | Server is not responding (not running or wrong port) |
| 3 | No connection attempt was made (bad parameters) |

These exit codes are useful in health check scripts and monitoring.

---

## Step 2: Stop PG15 only - verify PG16 still running

```bash
sudo systemctl stop postgresql-15
```

The `stop` subcommand sends a shutdown signal to the PG15 process. It does not affect PG16.

Verify PG15 is stopped.

```bash
sudo systemctl status postgresql-15 --no-pager
```

Expected output (yours will differ):

```
● postgresql-15.service - PostgreSQL 15 database server
     Loaded: loaded (...)
     Active: inactive (dead) since ...
     ...
```

Verify PG16 is still running.

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output (yours will differ):

```
/run/postgresql:5432 - accepting connections
```

Verify PG15 is not responding.

```bash
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output (yours will differ):

```
/run/postgresql:5433 - no response
```

Exit back to ec2-user.

```bash
exit
```

PG16 is completely unaffected by stopping PG15. They are independent processes with independent data directories.

---

## Step 3: Start PG15 - verify both running

```bash
sudo systemctl start postgresql-15
```

Verify both clusters are running.

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output (yours will differ):

```
/run/postgresql:5432 - accepting connections
```

```bash
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output (yours will differ):

```
/run/postgresql:5433 - accepting connections
```

Stay as the postgres user for the next step.

---

## Step 4: Prove cluster isolation with data

Create a test table in PG16.

```bash
psql -p 5432 -c "CREATE TABLE cluster_test (id int, cluster_name text);"
```

The `-c` flag runs a single SQL command and exits.

Expected output:

```
CREATE TABLE
```

Insert a row.

```bash
psql -p 5432 -c "INSERT INTO cluster_test VALUES (1, 'PG16 cluster');"
```

Expected output:

```
INSERT 0 1
```

Verify the data exists in PG16.

```bash
psql -p 5432 -c "SELECT * FROM cluster_test;"
```

Expected output:

```
 id | cluster_name
----+--------------
  1 | PG16 cluster
(1 row)
```

Now try to query the same table in PG15.

```bash
psql -p 5433 -c "SELECT * FROM cluster_test;"
```

Expected output (yours will differ):

```
ERROR:  relation "cluster_test" does not exist
LINE 1: SELECT * FROM cluster_test;
                      ^
```

Stay as the postgres user for the next step.

### Explanation

The table does not exist in PG15 because each cluster has its own data directory, its own system catalogs, and its own set of databases. They share nothing except the operating system. This is fundamentally different from schemas within the same cluster - these are completely separate PostgreSQL instances.

---

## Step 5: Check systemd auto-start configuration

When the server reboots, which clusters start automatically?

Exit back to ec2-user first.

```bash
exit
```

Check PG16.

```bash
sudo systemctl is-enabled postgresql-16
```

Expected output (yours will differ):

```
enabled
```

Check PG15.

```bash
sudo systemctl is-enabled postgresql-15
```

Expected output (yours will differ):

```
enabled
```

### Explanation

`enabled` means the service will start automatically at boot. `disabled` means it will not. In production, you typically want your primary database enabled and might disable a test cluster to prevent it from consuming resources after a reboot.

To disable auto-start for a cluster (do NOT run this now):

```
sudo systemctl disable postgresql-15
```

---

## Step 6: Compare system identifiers

Each cluster has a unique 64-bit system identifier. Let's verify they are different.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check PG16's identifier.

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7496032148219837451
```

Check PG15's identifier.

```bash
/usr/pgsql-15/bin/pg_controldata /opt/pgsql/data15 | grep "system identifier"
```

Expected output (yours will differ):

```
Database system identifier:           7496032291405628190
```

Stay as the postgres user for the next step.

### Explanation

These numbers are guaranteed to be different. The system identifier is generated from the timestamp and process ID at `initdb` time. PostgreSQL uses this identifier to prevent mixing WAL files or backups between clusters. If you ever see a replication error about mismatched system identifiers, it means someone pointed a standby at the wrong primary.

---

## Step 7: pg_ctl status vs systemctl status

There are two ways to check cluster status. Let's compare them.

Check PG16 with pg_ctl.

```bash
/usr/pgsql-16/bin/pg_ctl status -D /opt/pgsql/data
```

The `-D` flag specifies the data directory.

Expected output (yours will differ):

```
pg_ctl: server is running (PID: 1234)
/usr/pgsql-16/bin/postgres "-D" "/opt/pgsql/data"
```

Exit back to ec2-user.

```bash
exit
```

Check PG16 with systemctl.

```bash
sudo systemctl status postgresql-16 --no-pager
```

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since Sat 2026-04-19 10:30:00 UTC; 2h ago
   Main PID: 1234 (postgres)
      Tasks: 7 (limit: 4421)
     Memory: 28.5M
        CPU: 1.234s
     CGroup: /system.slice/postgresql-16.service
             ├─1234 /usr/pgsql-16/bin/postgres -D /opt/pgsql/data
             ├─1235 "postgres: logger "
             ├─1236 "postgres: checkpointer "
             ├─1237 "postgres: background writer "
             ...
```

### Explanation

| Feature | pg_ctl status | systemctl status |
|---------|--------------|-----------------|
| Shows PID | Yes | Yes |
| Shows uptime | No | Yes |
| Shows memory usage | No | Yes |
| Shows child processes | No | Yes |
| Works without root | Yes (as postgres) | Needs sudo |
| Reads from | postmaster.pid file | systemd journal |

In production, use `systemctl` for operations and `pg_ctl` for quick checks when you are already logged in as the postgres user. Never mix them - if you start a cluster with `systemctl`, always stop it with `systemctl`.

---

## Step 8: Clean up the test table

Switch to the postgres user.

```bash
sudo -iu postgres
```

Drop the test table from PG16.

```bash
psql -p 5432 -c "DROP TABLE cluster_test;"
```

Expected output:

```
DROP TABLE
```

Verify it is gone.

```bash
psql -p 5432 -c "SELECT * FROM cluster_test;"
```

Expected output (yours will differ):

```
ERROR:  relation "cluster_test" does not exist
LINE 1: SELECT * FROM cluster_test;
                      ^
```

Exit back to ec2-user.

```bash
exit
```

---

## Summary

Key takeaways:

- Multiple PostgreSQL clusters on the same server are completely isolated - separate data, separate processes, separate ports
- `pg_isready` exit codes are useful for scripting health checks (0 = up, 2 = down)
- `systemctl is-enabled` shows whether a service starts at boot
- System identifiers are unique per cluster and prevent cross-cluster accidents
- Use `systemctl` for all start/stop operations when systemd services are configured. Do not mix `pg_ctl` and `systemctl` for the same cluster.

# Exercise 03: Tuning Challenge

**Duration:** 30 minutes
**Objective:** Calculate optimal PostgreSQL settings for the lab server's hardware, apply them via `conf.d/`, and verify each one takes effect. Understand the difference between reload-safe and restart-required settings.

**Prerequisites:** PG16 running on port 5432 (`/opt/pgsql/data`) with `conf.d/` configured (from BUILD Guide 02). Single node. Server is a t3.small (1 CPU, 1 GB RAM, 25 GB SSD).

---

## Background

PostgreSQL ships with conservative defaults designed to run on a Raspberry Pi. On any real server, you need to tune at least a handful of settings. The standard formulas below work for most OLTP workloads.

---

## Step 1: Check the server's actual RAM

Before tuning, verify the hardware. Do not guess.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Check total memory.

```bash
free -m
```

The `-m` flag displays output in megabytes.

Expected output (yours will differ):

```
              total        used        free      shared  buff/cache   available
Mem:            958         312         124          12         521         476
Swap:             0           0           0
```

Exit back to ec2-user.

```bash
exit
```

The `total` column shows roughly 958 MB (a t3.small has 1 GB, but the OS reserves some). We will round to 1 GB for calculations.

---

## Step 2: Calculate optimal settings

Here are the standard formulas for a 1 GB RAM server:

| Setting | Formula | Calculated Value | Why |
|---------|---------|-----------------|-----|
| `shared_buffers` | 25% of RAM, but cap at 128 MB for 1 GB servers | **128MB** | PostgreSQL's own page cache. On a 1 GB server, 256 MB would starve the OS. |
| `effective_cache_size` | 75% of RAM | **768MB** | Tells the query planner how much total cache is available (PG + OS). Not an allocation. |
| `work_mem` | RAM / max_connections / 4 | **2MB** | Per-operation sort/hash memory. Each query can use multiple work_mem allocations. |
| `maintenance_work_mem` | RAM / 16 | **64MB** | Memory for VACUUM, CREATE INDEX, and ALTER TABLE. |
| `max_wal_size` | Default for low-traffic | **1GB** | Maximum WAL size before a checkpoint is forced. |

---

## Step 3: Record the current values

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to psql.

```bash
psql -p 5432
```

Check the current values before changing anything.

```sql
SHOW shared_buffers;
```

Expected output (yours will differ):

```
 shared_buffers
----------------
 128MB
(1 row)
```

```sql
SHOW effective_cache_size;
```

Expected output (yours will differ):

```
 effective_cache_size
----------------------
 4GB
(1 row)
```

```sql
SHOW work_mem;
```

Expected output (yours will differ):

```
 work_mem
----------
 4MB
(1 row)
```

```sql
SHOW maintenance_work_mem;
```

Expected output (yours will differ):

```
 maintenance_work_mem
----------------------
 64MB
(1 row)
```

```sql
SHOW max_wal_size;
```

Expected output (yours will differ):

```
 max_wal_size
--------------
 1GB
(1 row)
```

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

Write down any values that differ from our calculated targets. Those are the ones we need to change.

---

## Step 4: Create the tuning configuration file

We will put all tuning settings into a dedicated `conf.d/tuning.conf` file. This keeps tuning separate from other config like networking and logging.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Open the new tuning config file with vi.

```bash
vi /opt/pgsql/data/conf.d/tuning.conf
```

Press `i` to enter insert mode and type the following content:

```
# Tuning for t3.small (1 CPU, 1 GB RAM, 25 GB SSD)
# Created during Module 04 Exercise 03

# Memory
shared_buffers = 128MB
effective_cache_size = 768MB
work_mem = 2MB
maintenance_work_mem = 64MB

# WAL
max_wal_size = 1GB
```

Press `Esc`, then type `:wq` and press `Enter` to save and exit.

Verify the file was saved correctly.

```bash
cat /opt/pgsql/data/conf.d/tuning.conf
```

Expected output (yours will differ):

```
# Tuning for t3.small (1 CPU, 1 GB RAM, 25 GB SSD)
# Created during Module 04 Exercise 03

# Memory
shared_buffers = 128MB
effective_cache_size = 768MB
work_mem = 2MB
maintenance_work_mem = 64MB

# WAL
max_wal_size = 1GB
```

Exit back to ec2-user.

```bash
exit
```

---

## Step 5: Apply the changes

Some of these settings require different actions to take effect:

| Setting | Context | Action needed |
|---------|---------|---------------|
| `shared_buffers` | postmaster | **Restart** |
| `effective_cache_size` | user | Reload |
| `work_mem` | user | Reload |
| `maintenance_work_mem` | user | Reload |
| `max_wal_size` | sighup | Reload |

Since `shared_buffers` requires a restart and we want all settings active, we need a restart.

First, let's try a reload and see what happens with `shared_buffers`.

Switch to the postgres user.

```bash
sudo -iu postgres
```

```bash
psql -p 5432 -c "SELECT pg_reload_conf();"
```

The `pg_reload_conf()` function tells PostgreSQL to re-read all configuration files without stopping.

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

Now check if shared_buffers changed.

```bash
psql -p 5432 -c "SELECT name, setting, unit, pending_restart FROM pg_settings WHERE name = 'shared_buffers';"
```

Expected output (yours will differ):

```
      name      | setting | unit | pending_restart
----------------+---------+------+-----------------
 shared_buffers | 16384   | 8kB  | t
(1 row)
```

Exit back to ec2-user.

```bash
exit
```

If `pending_restart` shows `t`, the reload was not enough. We need a full restart.

```bash
sudo systemctl restart postgresql-16
```

The `restart` subcommand stops and then starts the service.

Verify the service came back up.

```bash
sudo systemctl status postgresql-16 --no-pager
```

The `--no-pager` flag prints the output directly instead of opening a pager.

Expected output (yours will differ):

```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; preset: disabled)
     Active: active (running) since ...
     ...
```

---

## Step 6: Verify all settings took effect

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to psql.

```bash
psql -p 5432
```

Verify each setting.

```sql
SHOW shared_buffers;
```

Expected output:

```
 shared_buffers
----------------
 128MB
(1 row)
```

```sql
SHOW effective_cache_size;
```

Expected output:

```
 effective_cache_size
----------------------
 768MB
(1 row)
```

```sql
SHOW work_mem;
```

Expected output:

```
 work_mem
----------
 2MB
(1 row)
```

```sql
SHOW maintenance_work_mem;
```

Expected output:

```
 maintenance_work_mem
----------------------
 64MB
(1 row)
```

Confirm that the source is our tuning file.

```sql
SELECT name, setting, unit, sourcefile
FROM pg_settings
WHERE sourcefile LIKE '%tuning%';
```

Expected output (yours will differ):

```
         name         | setting | unit |                sourcefile
----------------------+---------+------+-----------------------------------------
 effective_cache_size | 98304   | 8kB  | /opt/pgsql/data/conf.d/tuning.conf
 maintenance_work_mem | 65536   | kB   | /opt/pgsql/data/conf.d/tuning.conf
 max_wal_size         | 1024    | MB   | /opt/pgsql/data/conf.d/tuning.conf
 shared_buffers       | 16384   | 8kB  | /opt/pgsql/data/conf.d/tuning.conf
 work_mem             | 2048    | kB   | /opt/pgsql/data/conf.d/tuning.conf
```

Confirm nothing is pending restart.

```sql
SELECT name FROM pg_settings WHERE pending_restart = true;
```

Expected output:

```
 name
------
(0 rows)
```

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

---

## Step 7: Discussion - Why not 512 MB shared_buffers on a 1 GB server?

This is a common mistake. Here is what happens:

1. **shared_buffers = 512 MB** reserves half the RAM just for PostgreSQL's page cache.
2. The OS still needs RAM for its own file cache, kernel structures, and other processes.
3. PostgreSQL also allocates memory for connections (`work_mem` per query), autovacuum workers, background processes, etc.
4. Total memory usage exceeds physical RAM.
5. The Linux OOM (Out Of Memory) killer activates and **kills the PostgreSQL postmaster process**.

The result: your database crashes with no warning. In the system log (`/var/log/messages`), you will see something like:

```
Out of memory: Killed process 1234 (postgres) total-vm:1234567kB
```

The rule of thumb: on servers with less than 2 GB RAM, cap `shared_buffers` at 128 MB. On larger servers, 25% of RAM is usually safe but should never exceed 8 GB (beyond that, PostgreSQL sees diminishing returns and the OS file cache does a better job).

---

## Summary

Key takeaways:

- Always check actual RAM with `free -m` before tuning
- Use `conf.d/` files to keep tuning settings organized and auditable
- `pending_restart = true` means a reload was not enough - you need a full restart
- The `sourcefile` column in `pg_settings` confirms which file is controlling each setting
- Over-allocating `shared_buffers` on small servers leads to OOM kills

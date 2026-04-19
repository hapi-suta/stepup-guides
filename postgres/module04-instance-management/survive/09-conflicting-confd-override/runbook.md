# Scenario 09 - Conflicting conf.d Override

**Severity:** HIGH
**Expected Recovery Time:** 3-5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Application connections are failing.
All services connecting to PostgreSQL on port 5432 report
'connection refused'. The database process appears to be
running but something changed the port.
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **conf.d alphabetical loading** - When `postgresql.conf` contains `include_dir = 'conf.d'`, PostgreSQL loads every `.conf` file in that directory in alphabetical (C locale) order. If two files set the same parameter, the file loaded last wins. A file named `zzz-override.conf` loads after `tuning.conf` because `z` sorts after `t`. This is why file naming in `conf.d` matters - it controls precedence.

- **Port parameter** - The `port` setting controls which TCP port PostgreSQL listens on. It has `postmaster` context, meaning it only takes effect on a full restart (not a reload). Changing the port mid-flight does not affect running connections, but after a restart, all new connections must use the new port. Applications hardcoded to port 5432 will get "connection refused."

- **pg_isready for port discovery** - `pg_isready` is a lightweight utility that checks whether PostgreSQL accepts connections on a given host and port. When the standard port fails, try `pg_isready -p <port>` with other ports to find where PostgreSQL is actually listening. You can also use `ss -tlnp | grep postgres` to see all ports the postmaster has bound.

- **pg_settings sourcefile column** - Every active setting in `pg_settings` has a `sourcefile` column showing which file it was loaded from. For conf.d parameters, this tells you the exact file (e.g., `/opt/pgsql/data/conf.d/zzz-override.conf`). This is the fastest way to trace where a mysterious setting came from. You need a running server to query it, so you must connect on whatever port PG is actually using.

- **Configuration file auditing** - In production, `conf.d/` should be managed by version control or configuration management (Ansible, Puppet). Untracked files appearing in `conf.d/` is a red flag. A simple `ls -la conf.d/` during routine checks catches rogue files. Some teams use a naming convention like `00-base.conf`, `10-tuning.conf`, `20-logging.conf` to make the loading order obvious.

---

## Diagnostic Steps

### Step 1 - Check if PostgreSQL is accepting connections on port 5432

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output (yours will differ):

```
localhost:5432 - no response
```

Port 5432 is not responding. But is PostgreSQL actually running?

### Step 2 - Check if the PostgreSQL process is alive

```bash
ps aux | grep postgres | grep -v grep | head -5
```

Expected output (yours will differ):

```
postgres  1234  0.0  1.2 ... /usr/pgsql-16/bin/postgres -D /opt/pgsql/data
postgres  1235  0.0  0.1 ... postgres: checkpointer
postgres  1236  0.0  0.1 ... postgres: background writer
...
```

PostgreSQL IS running. But not on port 5432.

### Step 3 - Find which port PostgreSQL is listening on

```bash
sudo ss -tlnp | grep postgres
```

Expected output (yours will differ):

```
LISTEN  0  244  0.0.0.0:5499  0.0.0.0:*  users:(("postgres",pid=1234,fd=6))
```

PostgreSQL is listening on port 5499, not 5432.

### Step 4 - Connect on the actual port and check where the setting came from

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5499 -d labdb -c "SELECT name, setting, sourcefile FROM pg_settings WHERE name = 'port';"
```

Expected output (yours will differ):

```
 name | setting |                  sourcefile
------+---------+----------------------------------------------
 port | 5499    | /opt/pgsql/data/conf.d/zzz-override.conf
(1 row)
```

The `sourcefile` column points directly to the culprit: `zzz-override.conf` in conf.d.

```bash
exit
```

### Step 5 - Inspect the rogue file

```bash
sudo cat /opt/pgsql/data/conf.d/zzz-override.conf
```

Expected output (yours will differ):

```
# Emergency maintenance override - DO NOT DELETE
# Added by ops team for load balancer testing
port = 5499
```

Someone created this file to test something and forgot to remove it. Because the filename starts with `zzz`, it loads last and overrides every other conf.d file.

### Step 6 - List all conf.d files to understand loading order

```bash
sudo ls -la /opt/pgsql/data/conf.d/
```

Expected output (yours will differ):

```
-rw-------  1 postgres postgres  120 Apr 18 10:00 tuning.conf
-rw-------  1 postgres postgres   95 Apr 18 10:05 zzz-override.conf
```

`zzz-override.conf` loads after `tuning.conf` alphabetically, so its `port` value wins.

---

## Resolution

### Step 1 - Remove the rogue conf.d file

```bash
sudo rm /opt/pgsql/data/conf.d/zzz-override.conf
```

### Step 2 - Verify it is gone

```bash
sudo ls -la /opt/pgsql/data/conf.d/
```

Expected output (yours will differ):

```
-rw-------  1 postgres postgres  120 Apr 18 10:00 tuning.conf
```

Only the legitimate tuning file remains.

### Step 3 - Restart PostgreSQL on the correct port

A restart is required because `port` is a postmaster-context parameter.

```bash
sudo systemctl restart postgresql-16
```

### Step 4 - Verify PostgreSQL is on port 5432

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready -p 5432
```

Expected output (yours will differ):

```
localhost:5432 - accepting connections
```

### Step 5 - Confirm via psql

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SHOW port;"
```

Expected output (yours will differ):

```
 port
------
 5432
(1 row)
```

### Step 6 - Verify sourcefile is correct

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT name, setting, sourcefile FROM pg_settings WHERE name = 'port';"
```

Expected output (yours will differ):

```
 name | setting |             sourcefile
------+---------+------------------------------------
 port | 5432    | /opt/pgsql/data/postgresql.conf
(1 row)
```

The port is now coming from `postgresql.conf`, not from a rogue conf.d file.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running on port 5432
- pg_isready succeeds on port 5432
- No zzz-override.conf in conf.d
- psql connection on port 5432 succeeds
- Port setting comes from postgresql.conf (not conf.d override)

---

## Interview Discussion Points

1. **How does PostgreSQL resolve conflicting settings across multiple configuration files?** - PostgreSQL processes config files sequentially: `postgresql.conf` first, then `include_dir` files in alphabetical order, then `postgresql.auto.conf`. Within each file, if a parameter appears multiple times, the last occurrence wins. Across files, the last file to set the parameter wins. This means naming matters in `conf.d/` - a file named `zzz-anything.conf` will override everything else. The full precedence chain: `postgresql.conf` < `conf.d/aaa.conf` < `conf.d/zzz.conf` < `postgresql.auto.conf`.

2. **How would you prevent unauthorized conf.d files from being created?** - Several approaches: (1) Set directory permissions so only authorized users can write to `conf.d/`. (2) Use configuration management (Ansible) that enforces the exact set of files - any extra file gets removed. (3) Monitor the directory with a cron job or alerting rule that fires when unexpected files appear. (4) Include a `ls conf.d/` check in your deployment runbooks. (5) In PG16+, you can use `include_dir` with a restrictive pattern. The human process matters too: establish a team policy that conf.d files require peer review.

3. **What is the difference between changing the port via conf.d vs ALTER SYSTEM?** - Functionally, they both change the port. The difference is visibility and management. A conf.d file is visible in the filesystem, can be version-controlled, and follows alphabetical precedence rules. ALTER SYSTEM writes to `auto.conf`, which is less visible and always wins over conf.d. If someone used ALTER SYSTEM to set the port, removing the conf.d file would not fix it - auto.conf would still override. Always check both conf.d AND auto.conf when debugging.

4. **You see PostgreSQL is running but applications cannot connect. What is your diagnostic sequence?** - (1) `pg_isready -p 5432` to confirm the expected port is unresponsive. (2) `ps aux | grep postgres` to confirm the process is alive. (3) `ss -tlnp | grep postgres` to find which port it is actually listening on. (4) Connect on the actual port and query `pg_settings` for the `port` setting and its `sourcefile`. (5) Inspect the sourcefile to understand why. This sequence takes under 60 seconds and always gives you the answer. Never guess - always trace the setting to its source.

5. **What other parameters in conf.d can cause similar "silent misconfiguration" issues?** - `max_connections` (too low means new connections rejected), `shared_buffers` (too low means poor performance), `logging_collector = off` (silently stops logging), `archive_mode = off` (silently breaks PITR backups), `wal_level = minimal` (silently breaks replication). The pattern is the same: a rogue conf.d file overrides a critical setting, and nobody notices until something breaks. The defense is the same: `pg_settings.sourcefile` tells you exactly which file is controlling each parameter.

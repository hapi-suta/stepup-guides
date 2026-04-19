# Module 04 - Creating and Managing Instances
## Guide 02: PostgreSQL Configuration Mastery

**Objective:** Master the three configuration files that control PostgreSQL behavior. Learn to query `pg_settings` for live configuration data, organize custom settings using the `conf.d/` pattern, use `ALTER SYSTEM` for runtime changes, and manage client authentication with `pg_hba.conf`.

**Time:** 70-75 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 running on port 5432 with PGDATA at `/opt/pgsql/data`

---

## 1. The Three Configuration Files

PostgreSQL uses three main configuration files, all located inside PGDATA. Each has a distinct purpose.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

List the configuration files in PGDATA:

```bash
ls -la /opt/pgsql/data/*.conf
```

Expected output (yours will differ):

```
-rw------- 1 postgres postgres 29775 Apr 15 10:30 /opt/pgsql/data/postgresql.conf
-rw------- 1 postgres postgres    88 Apr 15 10:30 /opt/pgsql/data/postgresql.auto.conf
-rw------- 1 postgres postgres  4956 Apr 15 10:30 /opt/pgsql/data/pg_hba.conf
-rw------- 1 postgres postgres  1636 Apr 15 10:30 /opt/pgsql/data/pg_ident.conf
```

Here is what each file does:

| File | Purpose | How to Edit |
|------|---------|-------------|
| `postgresql.conf` | Main configuration file. Contains all server settings with commented defaults. | Edit with `vi`, then reload or restart. |
| `postgresql.auto.conf` | Overrides written by `ALTER SYSTEM`. Machine-managed - never edit by hand. | Use `ALTER SYSTEM SET` from psql. |
| `pg_hba.conf` | Client authentication rules. Controls who can connect and how they authenticate. | Edit with `vi`, then reload. |
| `pg_ident.conf` | OS-to-PostgreSQL username mapping. Used with `ident` and `peer` auth methods. | Edit with `vi`, then reload. |

The load order matters: PostgreSQL reads `postgresql.conf` first, then any files included via `include` or `include_dir`, and finally `postgresql.auto.conf`. For any setting that appears in multiple places, the last one wins. This means `postgresql.auto.conf` always overrides everything else.

Exit the postgres session:

```bash
exit
```

---

## 2. Exploring pg_settings

The `pg_settings` view is the single best tool for understanding how your PostgreSQL server is configured right now. It shows every setting, its current value, where it came from, and whether a restart is needed.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Query the key columns in `pg_settings`. The `\x` command turns on expanded display so wide rows are readable:

```bash
psql -p 5432
```

Inside psql, turn on expanded display:

```sql
\x
```

Look at all the columns available for a single setting. This shows you every piece of metadata PostgreSQL tracks:

```sql
SELECT * FROM pg_settings WHERE name = 'shared_buffers';
```

Expected output (yours will differ):

```
-[ RECORD 1 ]---+---------------------------------------------------
name            | shared_buffers
setting         | 16384
unit            | 8kB
category        | Resource Usage / Memory
short_desc      | Sets the number of shared memory buffers used by the server.
extra_desc      | ...
context         | postmaster
vartype         | integer
source          | configuration file
min_val         | 16
max_val         | 1073741823
...
pending_restart | f
```

The most useful columns are:

| Column | What It Tells You |
|--------|-------------------|
| `name` | Setting name (e.g., `shared_buffers`). |
| `setting` | Current value in the internal unit. |
| `unit` | Internal unit (8kB, kB, ms, s, min). Multiply `setting` by `unit` to get the real value. |
| `context` | When the setting takes effect: `postmaster` (restart), `sighup` (reload), `user` (per-session), `superuser` (per-session, superuser only). |
| `source` | Where the current value came from: `default`, `configuration file`, `override`, `environment variable`. |
| `sourcefile` | The exact file path that set this value. |
| `pending_restart` | `t` if the setting was changed but needs a restart to take effect. |

Turn off expanded display:

```sql
\x
```

> **Concept: The context column - reload vs restart**
> The `context` column is the most important column in `pg_settings` for day-to-day operations. Settings with `context = 'postmaster'` require a full server restart. Settings with `context = 'sighup'` take effect after a reload (no downtime). Settings with `context = 'user'` or `context = 'superuser'` can be changed per-session with `SET`. Before changing any setting, always check its context to know whether you will need downtime.

Find all settings that have been modified from their default values. This is the fastest way to audit what has been customized:

```sql
SELECT name, setting, unit, source, sourcefile FROM pg_settings WHERE source != 'default' ORDER BY name;
```

Expected output (yours will differ):

```
         name          | setting |  unit  |       source       |             sourcefile
-----------------------+---------+--------+--------------------+-------------------------------------
 data_checksums        | off     |        | override           |
 lc_messages           | en_US.UTF-8 |    | override           |
 port                  | 5432    |        | configuration file | /opt/pgsql/data/postgresql.conf
 shared_buffers        | 16384   | 8kB    | configuration file | /opt/pgsql/data/postgresql.auto.conf
 ...
```

Find all settings that require a restart. These are the ones you need to plan downtime for:

```sql
SELECT name, setting, unit, context FROM pg_settings WHERE context = 'postmaster' ORDER BY name;
```

Expected output (yours will differ):

```
            name             | setting | unit |  context
-----------------------------+---------+------+------------
 archive_mode                | off     |      | postmaster
 autovacuum_max_workers      | 3       |      | postmaster
 max_connections             | 100     |      | postmaster
 max_wal_senders             | 10      |      | postmaster
 shared_buffers              | 16384   | 8kB  | postmaster
 ...
```

Check if any settings are pending a restart:

```sql
SELECT name, setting, pending_restart FROM pg_settings WHERE pending_restart = true;
```

Expected output:

```
 name | setting | pending_restart
------+---------+-----------------
(0 rows)
```

Zero rows means no restart is pending - everything is in sync.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## 3. Using conf.d/ for Custom Configuration

In production, you should never modify the main `postgresql.conf` file directly (except for the `include_dir` directive). Instead, put all your custom settings in small, purpose-specific files inside a `conf.d/` directory. This approach has major benefits:

- The main `postgresql.conf` stays at package defaults, making upgrades safe
- Each file has a clear purpose (`tuning.conf`, `logging.conf`, `connections.conf`)
- You can see exactly what was changed and why, without diffing against defaults
- Version control tracks each concern separately

> **Concept: The conf.d/ pattern - how production environments work**
> Every serious PostgreSQL deployment uses the `conf.d/` pattern. Cloud-managed services like RDS, Aurora, and Cloud SQL do the same thing with parameter groups - they never touch the base config. When you take over a database from another team, the first thing you check is `conf.d/`. If all changes are dumped into the main `postgresql.conf`, you have no easy way to tell what was intentionally changed versus what is a default.

First, clean up any settings in `postgresql.auto.conf` from previous labs so they don't interfere with our conf.d experiments. Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to psql and reset any persisted settings:

```bash
psql -p 5432
```

```sql
ALTER SYSTEM RESET ALL;
```

Expected output:

```
ALTER SYSTEM
```

```sql
SELECT pg_reload_conf();
```

```sql
\q
```

Now create the `conf.d/` directory inside PGDATA:

```bash
mkdir /opt/pgsql/data/conf.d
```

Now tell PostgreSQL to load files from this directory. Open `postgresql.conf`:

```bash
vi /opt/pgsql/data/postgresql.conf
```

Go to the very end of the file (press `G` in vi). Add this line at the bottom:

```
include_dir = 'conf.d'
```

Save and exit vi (`:wq`).

The `include_dir` directive tells PostgreSQL to read all `.conf` files inside the specified directory, in alphabetical order. Files loaded later override earlier ones. Since `include_dir` is at the end of `postgresql.conf`, the conf.d files override anything in the main file. And `postgresql.auto.conf` is loaded after everything, so `ALTER SYSTEM` always wins.

Now create the first file for memory tuning settings:

```bash
vi /opt/pgsql/data/conf.d/tuning.conf
```

Add these lines:

```
# Memory tuning - Module 04 lab
shared_buffers = '128MB'
work_mem = '4MB'
effective_cache_size = '512MB'
maintenance_work_mem = '64MB'
```

Save and exit vi (`:wq`).

Create a file for logging settings:

```bash
vi /opt/pgsql/data/conf.d/logging.conf
```

Add these lines:

```
# Logging settings - Module 04 lab
log_destination = 'stderr'
logging_collector = on
log_directory = '/opt/pgsql/log'
log_filename = 'postgresql-%Y-%m-%d.log'
log_min_duration_statement = 1000
log_line_prefix = '%m [%p] %u@%d '
```

Save and exit vi (`:wq`).

Create a file for connection settings:

```bash
vi /opt/pgsql/data/conf.d/connections.conf
```

Add these lines:

```
# Connection settings - Module 04 lab
max_connections = 50
superuser_reserved_connections = 3
```

Save and exit vi (`:wq`).

List the conf.d directory to confirm all three files exist:

```bash
ls -la /opt/pgsql/data/conf.d/
```

Expected output:

```
total 12
drwx------ 2 postgres postgres  72 Apr 19 10:15 .
drwx------ 20 postgres postgres 4096 Apr 19 10:10 ..
-rw------- 1 postgres postgres  140 Apr 19 10:12 connections.conf
-rw------- 1 postgres postgres  220 Apr 19 10:13 logging.conf
-rw------- 1 postgres postgres  160 Apr 19 10:11 tuning.conf
```

Some of these settings require a restart (like `shared_buffers`, `max_connections`, and `logging_collector` - they have `context = 'postmaster'`). Others only need a reload. Since we changed restart-required settings, we need to restart:

```bash
/usr/pgsql-16/bin/pg_ctl restart -D /opt/pgsql/data -l /opt/pgsql/log/postgresql.log
```

Expected output:

```
waiting for server to shut down.... done
server stopped
waiting for server to start.... done
server started
```

Now verify the settings took effect. Connect to psql:

```bash
psql -p 5432
```

Check that the settings are loaded and showing the correct source file:

```sql
SELECT name, setting, unit, source, sourcefile FROM pg_settings WHERE sourcefile LIKE '%conf.d%' ORDER BY sourcefile, name;
```

Expected output (yours will differ):

```
             name              | setting |  unit  |       source       |                 sourcefile
-------------------------------+---------+--------+--------------------+---------------------------------------------
 max_connections               | 50      |        | configuration file | /opt/pgsql/data/conf.d/connections.conf
 superuser_reserved_connections| 3       |        | configuration file | /opt/pgsql/data/conf.d/connections.conf
 log_destination               | stderr  |        | configuration file | /opt/pgsql/data/conf.d/logging.conf
 log_directory                 | /opt/pgsql/log |  | configuration file | /opt/pgsql/data/conf.d/logging.conf
 log_min_duration_statement    | 1000    | ms     | configuration file | /opt/pgsql/data/conf.d/logging.conf
 logging_collector             | on      |        | configuration file | /opt/pgsql/data/conf.d/logging.conf
 effective_cache_size          | 65536   | 8kB    | configuration file | /opt/pgsql/data/conf.d/tuning.conf
 maintenance_work_mem          | 65536   | kB     | configuration file | /opt/pgsql/data/conf.d/tuning.conf
 shared_buffers                | 16384   | 8kB    | configuration file | /opt/pgsql/data/conf.d/tuning.conf
 work_mem                      | 4096    | kB     | configuration file | /opt/pgsql/data/conf.d/tuning.conf
```

The `sourcefile` column proves exactly which file set each value. This is the power of the `conf.d/` pattern - full traceability.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## 4. ALTER SYSTEM

`ALTER SYSTEM` is PostgreSQL's built-in way to change settings from a SQL session. It writes the change to `postgresql.auto.conf`, which is loaded last and always wins over everything else.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

First, check the current value of `work_mem`. Connect to psql:

```bash
psql -p 5432
```

```sql
SELECT name, setting, unit, source, sourcefile FROM pg_settings WHERE name = 'work_mem';
```

Expected output:

```
  name   | setting | unit |       source       |              sourcefile
---------+---------+------+--------------------+------------------------------------------
 work_mem | 4096   | kB   | configuration file | /opt/pgsql/data/conf.d/tuning.conf
(1 row)
```

The value is 4096 kB (4 MB), set by `tuning.conf`. Now override it with `ALTER SYSTEM`:

```sql
ALTER SYSTEM SET work_mem = '8MB';
```

Expected output:

```
ALTER SYSTEM
```

The change is written to disk but not yet active. Apply it with a reload:

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Now check `work_mem` again:

```sql
SELECT name, setting, unit, source, sourcefile FROM pg_settings WHERE name = 'work_mem';
```

Expected output:

```
  name   | setting | unit |       source       |                 sourcefile
---------+---------+------+--------------------+-----------------------------------------------
 work_mem | 8192   | kB   | configuration file | /opt/pgsql/data/postgresql.auto.conf
(1 row)
```

Notice two things changed: the value went from 4096 to 8192 (8 MB), and the `sourcefile` changed from `conf.d/tuning.conf` to `postgresql.auto.conf`. The auto.conf override is winning.

> **Concept: ALTER SYSTEM precedence - auto.conf always wins**
> The load order is: `postgresql.conf` -> `include_dir` files (conf.d/) -> `postgresql.auto.conf`. Since `postgresql.auto.conf` loads last, any setting in it overrides the same setting everywhere else. This is by design - `ALTER SYSTEM` is meant for quick runtime changes. But it can cause confusion: if you update `tuning.conf` to set `work_mem = '16MB'` and reload, it will still show 8 MB because `auto.conf` wins. Always check `auto.conf` when a setting change seems to be ignored.

Exit psql to view the auto.conf file directly:

```sql
\q
```

View what `ALTER SYSTEM` wrote:

```bash
cat /opt/pgsql/data/postgresql.auto.conf
```

Expected output (yours will differ):

```
# Do not edit this file manually!
# It will be overwritten by the ALTER SYSTEM command.
work_mem = '8MB'
```

Now remove the override so `tuning.conf` takes control again. Connect to psql:

```bash
psql -p 5432
```

```sql
ALTER SYSTEM RESET work_mem;
```

Expected output:

```
ALTER SYSTEM
```

Reload to apply:

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Verify `work_mem` is back to the `tuning.conf` value:

```sql
SELECT name, setting, unit, source, sourcefile FROM pg_settings WHERE name = 'work_mem';
```

Expected output:

```
  name   | setting | unit |       source       |              sourcefile
---------+---------+------+--------------------+------------------------------------------
 work_mem | 4096   | kB   | configuration file | /opt/pgsql/data/conf.d/tuning.conf
(1 row)
```

It is back to 4 MB from `tuning.conf`. The `ALTER SYSTEM RESET` command removed the line from `auto.conf`.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## 5. pg_hba.conf Basics

The `pg_hba.conf` file (Host-Based Authentication) controls who can connect to your PostgreSQL server and how they must prove their identity. It is the firewall of PostgreSQL.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

View the current `pg_hba.conf`:

```bash
cat /opt/pgsql/data/pg_hba.conf
```

Expected output (yours will differ - comments removed for clarity):

```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
local   all             all                                     trust
host    all             all             127.0.0.1/32            trust
host    all             all             ::1/128                 trust
local   replication     all                                     trust
host    replication     all             127.0.0.1/32            trust
host    replication     all             ::1/128                 trust
```

Your server uses `trust` authentication because `initdb` defaults to it when no auth method is specified. This means no password is required for local connections. In production, you would use `peer` (OS user match) for local and `scram-sha-256` (password hash) for host connections.

Each line is a rule with these fields:

| Field | Meaning |
|-------|---------|
| `TYPE` | Connection type: `local` (Unix socket), `host` (TCP/IP with or without SSL), `hostssl` (SSL only), `hostnossl` (no SSL). |
| `DATABASE` | Which database this rule applies to: a specific name, `all`, or `replication`. |
| `USER` | Which user this rule applies to: a specific name or `all`. |
| `ADDRESS` | Client IP range (not used for `local` connections). CIDR notation: `127.0.0.1/32` = exact IP, `0.0.0.0/0` = any IPv4. |
| `METHOD` | How the user must authenticate: `peer` (OS user must match PG user), `scram-sha-256` (password), `trust` (no password - dangerous), `reject` (deny access). |

> **Concept: pg_hba first-match-wins**
> PostgreSQL reads `pg_hba.conf` from top to bottom and uses the FIRST rule that matches the connection. Once a match is found, no further rules are checked. This means the order of rules matters. A common mistake is putting a `reject` rule after an `all/all` rule - the reject rule will never be reached. Always put more specific rules above more general ones.

Connect to psql to use the `pg_hba_file_rules` view. This view parses `pg_hba.conf` and shows you any syntax errors:

```bash
psql -p 5432
```

```sql
SELECT line_number, type, database, user_name, address, netmask, auth_method, error FROM pg_hba_file_rules;
```

Expected output (yours will differ):

```
 line_number | type  | database |  user_name  |  address  |  netmask  |   auth_method   | error
-------------+-------+----------+-------------+-----------+-----------+-----------------+-------
          85 | local | {all}    | {all}       |           |           | trust           |
          87 | host  | {all}    | {all}       | 127.0.0.1 | 255.255.255.255 | trust     |
          89 | host  | {all}    | {all}       | ::1       | ...       | trust           |
...
```

If the `error` column shows anything other than NULL, you have a syntax error on that line. Fix it before reloading.

Exit psql:

```sql
\q
```

Now add a new rule to allow a specific user to connect from any IP using password authentication. Open `pg_hba.conf`:

```bash
vi /opt/pgsql/data/pg_hba.conf
```

Add this line below the existing `host all all 127.0.0.1/32` line:

```
host    all             labuser         0.0.0.0/0               scram-sha-256
```

Save and exit vi (`:wq`).

This rule says: any TCP/IP connection (`host`) to any database (`all`) as user `labuser` from any IPv4 address (`0.0.0.0/0`) must authenticate with a SCRAM-SHA-256 password.

Reload the configuration to apply the new rule. Use `pg_ctl reload`:

```bash
/usr/pgsql-16/bin/pg_ctl reload -D /opt/pgsql/data
```

Expected output:

```
server signaled
```

Verify the new rule is loaded by checking the view again:

```bash
psql -p 5432
```

```sql
SELECT line_number, type, database, user_name, address, auth_method, error FROM pg_hba_file_rules WHERE user_name = '{labuser}';
```

Expected output:

```
 line_number | type | database | user_name  |  address  |   auth_method   | error
-------------+------+----------+------------+-----------+-----------------+-------
          88 | host | {all}    | {labuser}  | 0.0.0.0   | scram-sha-256   |
(1 row)
```

The rule is active. The `error` column is empty, confirming no syntax errors.

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## 6. Reload vs Restart

Some configuration changes take effect immediately after a reload (no downtime). Others require a full server restart (brief downtime). Knowing which is which prevents unnecessary restarts.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to psql:

```bash
psql -p 5432
```

List all the context types and how many settings belong to each:

```sql
SELECT context, count(*) FROM pg_settings GROUP BY context ORDER BY count DESC;
```

Expected output (yours will differ):

```
      context      | count
-------------------+-------
 user              |   142
 sighup            |    96
 postmaster        |    58
 superuser         |    47
 internal          |    18
 superuser-backend |     4
 backend           |     2
(7 rows)
```

The key distinction:

| Context | When It Takes Effect | Downtime? |
|---------|---------------------|-----------|
| `postmaster` | Server restart only | Yes (brief) |
| `sighup` | Reload (no restart) | No |
| `user` | Can be set per-session with `SET` | No |
| `superuser` | Can be set per-session by superusers | No |
| `internal` | Set at compile time or `initdb` - cannot change | N/A |
| `superuser-backend` | Set at connection start by superusers only | No |
| `backend` | Set only at connection start | No |

> **Concept: Reload vs restart - the practical difference**
> A reload sends a SIGHUP signal to the postmaster process, which re-reads all configuration files. Existing connections keep running. A restart shuts down all connections, stops the server, and starts it fresh. In production, you plan restarts during maintenance windows. Reloads can happen anytime. About 75% of settings are reload-safe (`sighup` + `user` + `superuser`), so you rarely need restarts for day-to-day tuning.

Demonstrate a reload with `log_min_duration_statement` (which has `context = 'superuser'` - meaning it can be changed per-session or via reload, no restart needed). Check its current value:

```sql
SELECT name, setting, unit, context FROM pg_settings WHERE name = 'log_min_duration_statement';
```

Expected output:

```
            name            | setting | unit |  context
----------------------------+---------+------+-----------
 log_min_duration_statement | -1      | ms   | superuser
(1 row)
```

Change it with ALTER SYSTEM:

```sql
ALTER SYSTEM SET log_min_duration_statement = 500;
```

Expected output:

```
ALTER SYSTEM
```

The setting is not active yet. Verify with `pending_restart` (even though this is a sighup setting, the column still indicates a change is pending):

```sql
SELECT name, setting FROM pg_settings WHERE name = 'log_min_duration_statement';
```

Expected output:

```
            name            | setting
----------------------------+---------
 log_min_duration_statement | 1000
(1 row)
```

Still 1000. Now reload using the SQL function:

```sql
SELECT pg_reload_conf();
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Check again:

```sql
SELECT name, setting, unit FROM pg_settings WHERE name = 'log_min_duration_statement';
```

Expected output:

```
            name            | setting | unit
----------------------------+---------+------
 log_min_duration_statement | 500     | ms
(1 row)
```

It changed to 500 without any restart. No connections were dropped. This is the power of `sighup` settings.

There are three equivalent ways to trigger a reload:

| Method | Where to Run | Best For |
|--------|-------------|----------|
| `SELECT pg_reload_conf();` | Inside psql | When you are already in a psql session. |
| `pg_ctl reload -D /opt/pgsql/data` | Shell as `postgres` user | Ad-hoc clusters started with `pg_ctl`. |
| `sudo systemctl reload postgresql-16` | Shell as `ec2-user` or root | Production services managed by systemd. |

All three do the same thing - send SIGHUP to the postmaster process.

Clean up by resetting the value:

```sql
ALTER SYSTEM RESET log_min_duration_statement;
```

```sql
SELECT pg_reload_conf();
```

Exit psql:

```sql
\q
```

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

You have completed Guide 02. Verify you understand the following:

- [ ] You know the three configuration files (`postgresql.conf`, `postgresql.auto.conf`, `pg_hba.conf`) and their purposes
- [ ] You can query `pg_settings` to find current values, their source file, context, and pending restart status
- [ ] You understand the four context types: `postmaster` (restart), `sighup` (reload), `user`/`superuser` (per-session)
- [ ] You can create a `conf.d/` directory and organize settings by purpose (tuning, logging, connections)
- [ ] You understand precedence: `postgresql.conf` -> `conf.d/*.conf` (alphabetical) -> `postgresql.auto.conf` (always wins)
- [ ] You can use `ALTER SYSTEM SET` and `ALTER SYSTEM RESET` to manage `auto.conf` overrides
- [ ] You know `pg_hba.conf` uses first-match-wins and can verify rules with `pg_hba_file_rules`
- [ ] You can reload configuration three ways: `pg_reload_conf()`, `pg_ctl reload`, `systemctl reload`

---

Proceed to **Guide 03 - Managing Multiple Clusters**

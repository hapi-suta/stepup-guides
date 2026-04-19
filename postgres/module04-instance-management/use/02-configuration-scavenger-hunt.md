# Exercise 02: Configuration Scavenger Hunt

**Duration:** 25 minutes
**Objective:** Query the `pg_settings` catalog view to discover how PostgreSQL configuration actually works under the hood. Learn to distinguish between restart-required and reload-safe settings.

**Prerequisites:** PG16 running on port 5432 (`/opt/pgsql/data`) with `conf.d/` configured (from BUILD Guide 02). Single node.

---

## Background

`pg_settings` is a virtual table that shows every configuration parameter, its current value, where it was set, and what you need to do to change it. This is more reliable than reading config files because it shows the **actual running values**, not just what is written in files.

---

## Task 1: Find all settings that need a restart

Settings with `context = 'postmaster'` can only be changed by restarting the entire PostgreSQL server. This is the most disruptive type of configuration change.

### Try it

Switch to the postgres user.

```bash
sudo -iu postgres
```

Connect to the PG16 cluster.

```bash
psql -p 5432
```

Run this query to find all postmaster-context settings. The `count(*)` at the end tells you the total.

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE context = 'postmaster'
ORDER BY name;
```

Expected output (yours will differ):

```
          name           |  setting  | unit
-------------------------+-----------+------
 archive_mode            | off       |
 autovacuum_max_workers  | 3         |
 bonjour                 | off       |
 ...
```

Now count them.

```sql
SELECT count(*) FROM pg_settings WHERE context = 'postmaster';
```

Expected output (yours will differ):

```
 count
-------
    36
(1 row)
```

Stay in psql for the next task.

### Answer

There are roughly 35-40 postmaster-context settings (the exact number varies by PG version and installed extensions). These include critical settings like `shared_buffers`, `max_connections`, `max_worker_processes`, and `wal_level`. In production, changing any of these means a brief outage - plan accordingly.

---

## Task 2: Find all non-default settings

Any setting where `source != 'default'` was changed from its default value. This tells you what was customized and - critically - which file made the change.

### Try it

```sql
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE source != 'default'
ORDER BY source, name;
```

Expected output (yours will differ):

```
          name           |      setting       |       source       |              sourcefile
-------------------------+--------------------+--------------------+--------------------------------------
 archive_mode            | off                | configuration file | /opt/pgsql/data/postgresql.conf
 DateStyle               | ISO, MDY           | configuration file | /opt/pgsql/data/postgresql.conf
 ...
 lc_messages             | en_US.UTF-8        | override           |
 listen_addresses        | *                  | configuration file | /opt/pgsql/data/conf.d/network.conf
 ...
```

Stay in psql for the next task.

### Answer

The `source` column tells you where the value came from:

- `configuration file` - set in postgresql.conf or a conf.d/ file
- `override` - set by initdb or compiled-in
- `environment variable` - set via an OS environment variable
- `command line` - passed as a flag to `pg_ctl start` or `postgres`

The `sourcefile` column shows the exact file path. This is how you track down which conf.d/ file is controlling a specific setting.

---

## Task 3: Find settings with pending restart

When you change a postmaster-context setting in the config file and reload, the new value does not take effect until you restart. The `pending_restart` flag shows you which settings are in this limbo state.

### Try it

```sql
SELECT name, setting, pending_restart
FROM pg_settings
WHERE pending_restart = true;
```

Expected output (yours will differ):

```
 name | setting | pending_restart
------+---------+-----------------
(0 rows)
```

Stay in psql for the next task.

### Answer

If you get 0 rows, that means all config changes have been applied. If you see rows here, those settings were modified in the config file and a `SELECT pg_reload_conf();` was run, but a full restart has not happened yet. The old value is still active. This is a common gotcha - people change `shared_buffers`, reload, and wonder why nothing changed.

---

## Task 4: Find the setting with the largest numeric value

This is a fun exploration task. Some PostgreSQL settings have surprisingly large numbers.

### Try it

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE setting ~ '^\d+$'
ORDER BY setting::bigint DESC
LIMIT 5;
```

The `~ '^\d+$'` filter keeps only settings whose values are purely numeric. The `::bigint` cast lets us sort them numerically instead of alphabetically.

Expected output (yours will differ):

```
           name           |   setting    | unit
---------------------------+--------------+------
 max_function_args         | 100          |
 wal_segment_size          | 16777216     | B
 segment_size              | 131072       | 8kB
 wal_block_size            | 8192         |
 block_size                | 8192         |
```

Stay in psql for the next task.

### Answer

The largest values are typically internal constants like `wal_segment_size` (16 MB in bytes), `segment_size` (1 GB in 8kB pages), and `block_size` (8192 bytes). These are set at compile time and cannot be changed. They show up in `pg_settings` for informational purposes.

---

## Task 5: Find all Write-Ahead Log settings

PostgreSQL groups settings into categories. The WAL category contains all settings that control transaction durability and crash recovery.

### Try it

```sql
SELECT name, setting, unit, context
FROM pg_settings
WHERE category LIKE 'Write-Ahead Log%'
ORDER BY category, name;
```

Expected output (yours will differ):

```
            name             | setting | unit |  context
-----------------------------+---------+------+-----------
 archive_cleanup_command     |         |      | sighup
 archive_command             | (disabled) |   | sighup
 archive_mode               | off     |      | postmaster
 checkpoint_completion_target| 0.9     |      | sighup
 checkpoint_flush_after      | 32      | 8kB  | sighup
 checkpoint_timeout          | 300     | s    | sighup
 checkpoint_warning          | 30      | s    | sighup
 ...
```

Stay in psql for the next task.

### Answer

Notice the `context` column. Most WAL settings are `sighup` (reload-safe), but `archive_mode` and `wal_level` are `postmaster` (restart-required). This matters when you set up archiving or replication - you will need to plan a restart window. The `unit` column is also important: `checkpoint_timeout` shows `300` with unit `s`, meaning 300 seconds (5 minutes).

---

## Task 6: Find settings from conf.d/ files

If you followed BUILD Guide 02, some settings are stored in `/opt/pgsql/data/conf.d/` files. Let's verify.

### Try it

```sql
SELECT name, setting, sourcefile
FROM pg_settings
WHERE sourcefile LIKE '%conf.d%'
ORDER BY sourcefile, name;
```

Expected output (yours will differ):

```
      name       | setting |               sourcefile
-----------------+---------+----------------------------------------
 listen_addresses | *      | /opt/pgsql/data/conf.d/network.conf
 logging_collector| on     | /opt/pgsql/data/conf.d/logging.conf
 log_directory   | /opt/pgsql/log | /opt/pgsql/data/conf.d/logging.conf
 ...
```

Stay in psql for the next task.

### Answer

This query shows exactly which conf.d/ files are actively controlling which settings. If a setting appears here, it means:

1. The file is in the `conf.d/` directory
2. The `include_dir` directive in `postgresql.conf` loaded it
3. The value in this file won the precedence contest (last file loaded wins, and conf.d/ is loaded after postgresql.conf)

---

## Task 7: Find enum-type settings and list allowed values for wal_level

Some settings only accept specific values from a predefined list. The `enumvals` column shows what is allowed.

### Try it

```sql
SELECT name, setting, enumvals
FROM pg_settings
WHERE enumvals IS NOT NULL
ORDER BY name;
```

Expected output (yours will differ):

```
          name          | setting |              enumvals
------------------------+---------+-------------------------------------
 backslash_quote        | safe_encoding | {safe_encoding,on,off}
 bytea_output           | hex     | {escape,hex}
 ...
```

Now look at `wal_level` specifically.

```sql
SELECT name, setting, enumvals, context
FROM pg_settings
WHERE name = 'wal_level';
```

Expected output (yours will differ):

```
   name    | setting | enumvals                    | context
-----------+---------+-----------------------------+-----------
 wal_level | replica | {minimal,replica,logical}   | postmaster
```

Stay in psql for the next task.

### Answer

`wal_level` has three allowed values:

- `minimal` - least WAL generated, but no replication or PITR possible
- `replica` - enough WAL for streaming replication and PITR (the default since PG10)
- `logical` - adds extra information needed for logical replication

Since the context is `postmaster`, changing this requires a full restart. If you try to set it to an invalid value (like `full` from older PG versions), PostgreSQL will refuse to start.

---

## Task 8: List HBA rules using pg_hba_file_rules

`pg_hba_file_rules` is a system view that shows the parsed contents of `pg_hba.conf`. This is safer than reading the file because it shows you what PostgreSQL actually parsed.

### Try it

```sql
SELECT line_number, type, database, user_name, address, auth_method
FROM pg_hba_file_rules
ORDER BY line_number;
```

Expected output (yours will differ):

```
 line_number | type  | database  |  user_name  |  address   | auth_method
-------------+-------+-----------+-------------+------------+-------------
           1 | local | {all}     | {all}       |            | peer
           2 | host  | {all}     | {all}       | 127.0.0.1  | scram-sha-256
           3 | host  | {all}     | {all}       | ::1        | scram-sha-256
           ...
```

Exit psql.

```sql
\q
```

Exit back to ec2-user.

```bash
exit
```

### Answer

The key rule for the postgres user is typically line 1: `local / all / all / peer`. The `peer` authentication method means the OS username must match the PostgreSQL username. This is why `sudo -iu postgres` followed by `psql` works without a password - the OS user `postgres` matches the database user `postgres`.

HBA rules are evaluated top-to-bottom, first match wins. Order matters. If you put a `reject` rule above a `trust` rule, the connection will be rejected even though a more permissive rule exists below.

---

## Summary

`pg_settings` is your single source of truth for configuration. Key columns:

| Column | What it tells you |
|--------|-------------------|
| `source` | Where the current value came from |
| `sourcefile` | The exact file path |
| `context` | What is needed to apply a change (reload vs restart) |
| `pending_restart` | Whether a restart is needed to apply a config change |
| `enumvals` | Allowed values for enum-type settings |
| `unit` | The unit for numeric settings (s, ms, kB, MB, etc.) |

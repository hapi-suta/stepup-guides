# Module 04 Checklist: Creating and Managing Instances

**Scoring:**
- 16-18 correct: Ready for SURVIVE phase
- 12-15 correct: Review weak areas, then proceed
- Below 12: Repeat USE exercises before moving on

---

## Question 1

What does the `--data-checksums` flag do when passed to `initdb`?

<details>
<summary>Answer</summary>

It enables page-level checksums on all data files. PostgreSQL calculates a checksum for every 8 KB data page when writing it to disk and verifies the checksum when reading it back. This detects silent data corruption caused by faulty storage hardware. Once created without checksums, you can only enable them later by stopping the server and running `pg_checksums --enable`.

</details>

---

## Question 2

You change `shared_buffers` in `conf.d/tuning.conf` and run `SELECT pg_reload_conf();`. The value does not change. Why?

<details>
<summary>Answer</summary>

`shared_buffers` has context `postmaster`, which means it can only be changed by restarting the entire PostgreSQL server. A reload (SIGHUP) re-reads the config file but cannot apply postmaster-context changes. After a reload, `pg_settings` will show `pending_restart = true` for this setting. You need to run `sudo systemctl restart postgresql-16` (or the appropriate service name) to apply it.

</details>

---

## Question 3

What are the four `context` types in `pg_settings` and what does each require to apply a change?

<details>
<summary>Answer</summary>

1. **postmaster** - requires a full server restart
2. **sighup** - requires a reload (`SELECT pg_reload_conf()` or `systemctl reload`)
3. **superuser** - takes effect for new sessions of superusers immediately after a SET command (no reload needed)
4. **user** - takes effect for the current session immediately after a SET command (no reload needed)

There is also `internal` (compiled-in constants that cannot be changed) and `backend` (set at connection time only).

</details>

---

## Question 4

What is the configuration file precedence order in PostgreSQL? If the same setting is defined in multiple places, which one wins?

<details>
<summary>Answer</summary>

The last value read wins. The order is:

1. `postgresql.conf` (read first)
2. Files in `conf.d/` (included via `include_dir`, read in alphabetical order)
3. `postgresql.auto.conf` (written by ALTER SYSTEM, read last - always wins)

So `postgresql.auto.conf` has the highest precedence, followed by `conf.d/` files, followed by `postgresql.conf`. Within `conf.d/`, files are loaded in alphabetical order, so `z_override.conf` beats `a_defaults.conf`.

</details>

---

## Question 5

What does `ALTER SYSTEM SET work_mem = '4MB';` do? Where does it write the value?

<details>
<summary>Answer</summary>

`ALTER SYSTEM` writes the setting to `postgresql.auto.conf` (located in the data directory alongside `postgresql.conf`). This file is always read last, so its values override everything in `postgresql.conf` and `conf.d/` files. The change does not take effect until a reload (for sighup-context settings) or restart (for postmaster-context settings). You should never edit `postgresql.auto.conf` by hand - use `ALTER SYSTEM SET` and `ALTER SYSTEM RESET` to manage it.

</details>

---

## Question 6

What are the three `pg_ctl stop` modes and how do they differ?

<details>
<summary>Answer</summary>

1. **smart** (`-m smart`) - waits for all clients to disconnect voluntarily. A checkpoint is performed before shutdown. Can hang indefinitely if clients stay connected.
2. **fast** (`-m fast`) - terminates all client connections immediately, rolls back in-progress transactions, performs a checkpoint, then shuts down. This is the default for `systemctl stop`.
3. **immediate** (`-m immediate`) - kills all server processes instantly without a checkpoint. The next startup requires crash recovery (WAL replay). Use only as a last resort.

</details>

---

## Question 7

What is the difference between using `pg_ctl` and `systemctl` to manage PostgreSQL?

<details>
<summary>Answer</summary>

`pg_ctl` is PostgreSQL's own process management tool. It works directly with the postmaster process and reads from `postmaster.pid`.

`systemctl` is the Linux service manager. It manages PostgreSQL through a systemd service unit file that ultimately calls `pg_ctl` (or the `postgres` binary directly).

Key rules:
- If you started PostgreSQL with `systemctl`, always stop it with `systemctl` (and vice versa)
- `systemctl` handles auto-start at boot, dependency ordering, and resource limits
- `pg_ctl` is useful for temporary test clusters that do not have a systemd service file
- Never mix them for the same cluster or systemd will lose track of the process

</details>

---

## Question 8

What information is stored in the `postmaster.pid` file?

<details>
<summary>Answer</summary>

The `postmaster.pid` file (located in the data directory) contains:

1. The PID of the postmaster process (line 1)
2. The data directory path (line 2)
3. The postmaster start timestamp (line 3)
4. The port number (line 4)
5. The Unix socket directory (line 5)
6. The listen addresses (line 6)
7. The shared memory key (line 7)

PostgreSQL uses this file to prevent two instances from using the same data directory simultaneously. If the server crashes, a stale `postmaster.pid` may need to be manually removed before the server can restart (though PostgreSQL usually handles this automatically).

</details>

---

## Question 9

What are the `pg_isready` exit codes and what does each mean?

<details>
<summary>Answer</summary>

| Exit code | Meaning |
|-----------|---------|
| 0 | Server is accepting connections |
| 1 | Server is rejecting connections (e.g., still starting up or in recovery) |
| 2 | No response from server (server not running or wrong host/port) |
| 3 | No connection attempt was made (invalid parameters) |

These are useful for scripting health checks. For example: `pg_isready -p 5432 && echo "UP" || echo "DOWN"`

</details>

---

## Question 10

What is the difference between `reload` and `restart`? When must you use each?

<details>
<summary>Answer</summary>

**Reload** (`systemctl reload` or `SELECT pg_reload_conf()`) re-reads configuration files without stopping the server. Active connections are not interrupted. Only settings with context `sighup` or lower can be applied via reload.

**Restart** (`systemctl restart`) stops the server and starts it again. All connections are terminated. Required for settings with context `postmaster` (like `shared_buffers`, `max_connections`, `wal_level`).

Always try a reload first. Only restart when the setting requires it (`pending_restart = true` in `pg_settings`).

</details>

---

## Question 11

Why is the `conf.d/` include directory pattern preferred over editing `postgresql.conf` directly?

<details>
<summary>Answer</summary>

Benefits of `conf.d/`:

1. **No merge conflicts on upgrades** - `postgresql.conf` gets replaced during RPM upgrades, losing your edits. Files in `conf.d/` are untouched.
2. **Organized by purpose** - you can have `tuning.conf`, `logging.conf`, `network.conf`, `replication.conf` instead of one giant file.
3. **Auditable** - you can see exactly what was customized vs. defaults. `pg_settings.sourcefile` shows which file controls each setting.
4. **Rollback-friendly** - to undo a change, rename or delete the file and reload.
5. **Automation-friendly** - configuration management tools (Ansible, Chef) can drop files without parsing `postgresql.conf`.

</details>

---

## Question 12

What is the system identifier and why does it matter?

<details>
<summary>Answer</summary>

The system identifier is a unique 64-bit number generated by `initdb` at cluster creation time. It is stored in the control file and embedded in every WAL segment and backup.

It matters because:
- A streaming replica will refuse to connect to a primary with a different system identifier
- `pg_basebackup` embeds the identifier in the backup, preventing restoration to the wrong cluster
- It prevents accidentally mixing WAL files between clusters
- You can view it with `pg_controldata` or `SELECT system_identifier FROM pg_control_system();`

Every cluster - even two on the same server with the same version - has a different system identifier.

</details>

---

## Question 13

You have a `conf.d/` directory with three files: `01-memory.conf`, `02-logging.conf`, and `99-override.conf`. All three set `work_mem` to different values. Which value wins and why?

<details>
<summary>Answer</summary>

`99-override.conf` wins. Files in `conf.d/` are loaded in alphabetical (lexicographic) order. Since PostgreSQL uses "last value wins" precedence, the file that sorts last alphabetically has the highest precedence. Numbering prefixes like `01-`, `02-`, `99-` are a common pattern to explicitly control the load order.

However, if `postgresql.auto.conf` also sets `work_mem` (via `ALTER SYSTEM`), that value would override all `conf.d/` files because `postgresql.auto.conf` is always read after all included files.

</details>

---

## Question 14

What is the `pg_hba.conf` evaluation order? If a connection matches multiple rules, which one applies?

<details>
<summary>Answer</summary>

`pg_hba.conf` is evaluated **top-to-bottom, first match wins**. PostgreSQL scans the rules in order and applies the first rule that matches the connection's type, database, user, and source address.

This means:
- Order matters. A `reject` rule above a `trust` rule will reject the connection.
- More specific rules should go above more general rules.
- If no rule matches, the connection is rejected (implicit deny).
- You can view the parsed rules with `SELECT * FROM pg_hba_file_rules ORDER BY line_number;`

This is the opposite of `postgresql.conf`, where last value wins.

</details>

---

## Question 15

What happens if you set `shared_buffers = 512MB` on a server with only 1 GB of RAM?

<details>
<summary>Answer</summary>

PostgreSQL will start successfully, but the system is at risk of the Linux OOM (Out of Memory) killer. Here is why:

- 512 MB reserved for shared_buffers
- Additional memory needed for: OS kernel, OS file cache, per-connection memory (work_mem per sort/hash operation), autovacuum workers, background processes, other OS services
- Total memory demand exceeds 1 GB of physical RAM
- Linux OOM killer activates and kills the PostgreSQL postmaster process

The result is a database crash with no warning. You will see `Out of memory: Killed process` in `/var/log/messages`. For 1 GB servers, cap `shared_buffers` at 128 MB.

</details>

---

## Question 16

What is `pg_controldata` and when would you use it in production?

<details>
<summary>Answer</summary>

`pg_controldata` reads the `pg_control` file from the data directory and displays cluster metadata. It works even when the server is stopped.

Production use cases:
- **Pre-deployment check**: verify data checksums are enabled before going live
- **Replication setup**: confirm system identifiers match between primary and standby
- **Post-failover audit**: check the timeline ID incremented after promotion
- **Crash investigation**: determine the last checkpoint location and cluster state (in production, shut down, in recovery, etc.)
- **Upgrade planning**: compare catalog versions between old and new clusters

Usage: `/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data`

</details>

---

## Question 17

You run `pg_ctl stop -m fast` but the server does not stop after 60 seconds. What do you do?

<details>
<summary>Answer</summary>

Steps in order:

1. **Check what is blocking** - look at `pg_stat_activity` from another connection (if possible) for long-running queries or blocked sessions
2. **Check the PostgreSQL log** for errors or messages about why shutdown is stalling
3. **Try again with a timeout**: `pg_ctl stop -D /path/to/data -m fast -t 120` (the `-t` flag sets a shutdown timeout in seconds)
4. **As a last resort**, use immediate mode: `pg_ctl stop -m immediate` - this kills everything instantly and requires crash recovery on the next start
5. **Never use `kill -9`** on the postmaster unless even immediate mode fails. `kill -9` bypasses PostgreSQL's shutdown sequence and can leave shared memory in a dirty state.

After an immediate shutdown, always check the log on the next start to confirm crash recovery completed successfully.

</details>

---

## Question 18

What is the difference between the `Data page checksum version` field in `pg_controldata` showing `0` versus `1`?

<details>
<summary>Answer</summary>

- **Version 0**: Data checksums are **disabled**. PostgreSQL does not calculate or verify checksums on data pages. Silent data corruption from faulty disks will go undetected until the corrupted data is read and causes errors or returns wrong results.

- **Version 1**: Data checksums are **enabled**. PostgreSQL calculates a CRC-32C checksum for every 8 KB data page when writing it. On every read, the checksum is verified. If corruption is detected, PostgreSQL raises a `WARNING: page verification failed` error instead of silently returning bad data.

Checksums add a small CPU overhead (typically 1-2%) but are strongly recommended for production. They can only be enabled at `initdb` time (`--data-checksums` or `-k`) or offline with `pg_checksums --enable` (PG12+).

</details>

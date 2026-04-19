# PostgreSQL Instance Management - Comprehensive Concepts Guide

A teaching reference for DBA students learning to create, configure, and manage
PostgreSQL clusters from scratch. This document covers everything from `initdb`
to production-grade configuration patterns, authentication, server lifecycle,
and troubleshooting.

---

## Table of Contents

1. [Why Instance Management Matters](#1-why-instance-management-matters)
2. [Architecture: What is a PostgreSQL Cluster?](#2-architecture-what-is-a-postgresql-cluster)
3. [Core Concepts](#3-core-concepts)
4. [initdb Deep Dive](#4-initdb-deep-dive)
5. [Configuration Architecture](#5-configuration-architecture)
6. [pg_hba.conf Deep Dive](#6-pg_hbaconf-deep-dive)
7. [Server Lifecycle](#7-server-lifecycle)
8. [Production Best Practices](#8-production-best-practices)
9. [Common Commands Quick Reference](#9-common-commands-quick-reference)
10. [Troubleshooting](#10-troubleshooting)
11. [Cross-Platform: CentOS vs Ubuntu/Debian](#11-cross-platform-centos-vs-ubuntudebian)

---

## 1. Why Instance Management Matters

### The real cost of getting it wrong

Instance management is the foundation of every other PostgreSQL skill you will
learn. Replication, backup, high availability, performance tuning - all of them
assume you have a correctly initialized, properly configured cluster running
underneath. When instance management goes wrong, the damage is often permanent
and invisible until it is too late.

Here are the scenarios that play out in production when DBAs skip this
foundation:

- **Wrong locale baked in at init time.** A developer team in Montreal deploys a
  cluster with `en_US.UTF-8` instead of `fr_CA.UTF-8`. Sorting and collation
  rules are wrong for French data. You discover this after 18 months of
  accumulated data. The fix? Dump the entire database, destroy the cluster,
  `initdb` with the correct locale, and reload. On a 2 TB database, that is a
  full weekend of downtime.

- **Checksums not enabled.** You run PostgreSQL for two years without data
  checksums. A failing disk silently corrupts a handful of pages. You restore
  from backup - but the backup also contains the corrupted pages because the
  corruption happened months ago and went undetected. With checksums enabled at
  `initdb` time, PostgreSQL would have raised an alarm on the first read of a
  corrupted page. Without them, you have no way to know which pages are bad.

- **Config drift across environments.** Your development cluster runs with
  `max_connections = 100`, your staging cluster with `max_connections = 200`,
  and production with `max_connections = 500`. Nobody documented why. A
  connection pooler in production masks the real problem. When the pooler
  crashes during a traffic spike, 500 direct connections exhaust shared memory
  and the database goes down. The postmortem reveals that nobody owns the
  configuration - changes were made ad hoc over months.

- **Authentication misconfigured.** A `trust` rule added for debugging sits
  in `pg_hba.conf` for three months. Anyone on the network connects as
  superuser without a password. The security audit is not pleasant.

- **Shutdown mode misunderstood.** An operator runs `pg_ctl stop -m immediate`
  during a maintenance window because it is "faster." Crash recovery takes
  45 minutes on a write-heavy 1 TB database. The 30-minute window is blown.

Every one of these is preventable.

If you have completed Build Guides 01-03, you have already done all of this
hands-on. This document explains the WHY behind every command you ran.

---

## 2. Architecture: What is a PostgreSQL Cluster?

### The term "cluster" in PostgreSQL

The word "cluster" in PostgreSQL does not mean what it means in MySQL, MongoDB,
or distributed systems. In PostgreSQL, a **cluster** (also called a **database
cluster**) is a single instance of a running PostgreSQL server managing a
single data directory. It is not a group of servers working together. That
concept - multiple servers replicating data - is called a **replication
cluster** or a **high-availability cluster** and is covered in later modules.

A single PostgreSQL cluster can contain multiple databases. Each database is a
separate namespace with its own tables, indexes, schemas, and extensions. But
all databases in a cluster share the same:

- Server process (postmaster)
- Port number
- Configuration files
- WAL (write-ahead log) stream
- System catalog for roles and tablespaces

> **Concept:** A PostgreSQL "cluster" is one postmaster process managing one
> PGDATA directory. It can host dozens of databases. When people say "I have
> three PostgreSQL clusters on this server," they mean three separate data
> directories, three separate postmaster processes, three separate ports - all
> on one machine.

### PGDATA - the data directory

Everything PostgreSQL needs to run lives in a single directory tree called
**PGDATA**. When you run `initdb`, it creates this entire structure. When you
start the server, it reads from this directory. When you stop the server, the
data stays here on disk.

Here is what PGDATA looks like after `initdb` creates it:

```
PGDATA (/opt/pgsql/data/)
├── base/                    # All user database files (one subdir per database OID)
│   ├── 1/                   # template1
│   ├── 4/                   # template0 (frozen copy)
│   └── 5/                   # postgres database
│
├── global/                  # Cluster-wide tables (pg_database, pg_authid, pg_control)
│
├── pg_wal/                  # Write-ahead log segments (16 MB each)
│   └── archive_status/     # Tracks which segments have been archived
│
├── pg_xact/                 # Transaction commit status (CLOG)
├── pg_multixact/            # Multi-transaction status (row locks)
├── pg_logical/              # Logical replication state
├── pg_replslot/             # Replication slot data
├── pg_stat/                 # Permanent statistics files
├── pg_tblspc/               # Symbolic links to tablespace directories
│
├── postgresql.conf          # Main configuration file
├── postgresql.auto.conf     # ALTER SYSTEM writes here
├── pg_hba.conf              # Host-based authentication rules
├── pg_ident.conf            # Username mapping for ident/peer auth
├── PG_VERSION               # Major version number (e.g., "16")
│
├── postmaster.pid           # Lock file with PID, port, socket dir, start time
└── postmaster.opts          # Command-line options used to start the server
```

Some of these you will interact with daily (`pg_wal/`, configuration files).
Others you will rarely touch directly (`pg_xact/`, `pg_multixact/`) but need
to understand for troubleshooting and backup.

> **Concept:** Never manually edit, move, or delete files inside `base/`,
> `global/`, `pg_wal/`, or `pg_xact/`. These are binary data files managed by
> PostgreSQL's storage engine. Manually modifying them will corrupt your
> cluster. The only files you should ever edit by hand are the configuration
> files (`postgresql.conf`, `pg_hba.conf`, `pg_ident.conf`) and even those have
> safer alternatives (ALTER SYSTEM, conf.d pattern) covered in Section 5.

### Multiple clusters on one server

A single Linux server can run multiple PostgreSQL clusters simultaneously.
Each cluster needs its own PGDATA directory and its own port. This is common
in development and testing environments. In production, you typically dedicate
a server (or VM) to a single cluster for resource isolation.

```
Server: pg-lab-01
==================================================================

  Cluster A (Development)          Cluster B (Staging)
  ========================         ========================
  PGDATA: /opt/pgsql/dev/data     PGDATA: /opt/pgsql/stg/data
  Port:   5432                     Port:   5433
  PID:    12001                    PID:    12050

  +-----------+                    +-----------+
  | postmaster|                    | postmaster|
  +-----+-----+                   +-----+-----+
        |                               |
   +----+----+----+              +----+----+----+
  wal  chk  bgw  aut            wal  chk  bgw  aut
  snd  pnt  wrt  vac            snd  pnt  wrt  vac

  Both clusters share the OS, CPU, RAM, and disk I/O.
  They are completely independent at the data layer.
==================================================================
```

Each cluster must have a unique combination of listen address and port. Two
clusters cannot both bind to `0.0.0.0:5432`. Using different ports is the
simplest approach.

---

## 3. Core Concepts

Eight terms you must be able to define and explain before managing PostgreSQL
in production.

### 3.1 Cluster vs Instance vs Database

These three terms are constantly confused, even by experienced engineers. Here
is the precise PostgreSQL meaning of each:

| Term | Definition | Analogy |
| ---- | ---------- | ------- |
| **Cluster** | A single PGDATA directory managed by one postmaster process. Contains one or more databases. Created by `initdb`. | A building with apartments |
| **Instance** | A running cluster. The postmaster process and all its children. Often used interchangeably with "cluster," but technically implies the server is running. | The building with the lights on |
| **Database** | A named namespace within a cluster. Has its own tables, schemas, indexes, extensions. Created by `CREATE DATABASE`. | One apartment in the building |

You connect to a specific database within a cluster:

```
psql -h pg-lab-01 -p 5432 -U app_user -d app_production
      ^            ^        ^            ^
      host         port     role         database
      (which       (which   (who you     (which namespace
       server)      cluster)  are)        within the cluster)
```

All databases in a cluster share the same roles. If you create a role `alice`
in one database, she can connect to any database in the same cluster (subject
to `pg_hba.conf` rules and CONNECT privilege). Roles are cluster-wide objects
stored in `global/pg_authid`.

### 3.2 PGDATA

**PGDATA** is both a concept and an environment variable. As a concept, it
refers to the root directory of a PostgreSQL cluster's data files. As an
environment variable, it tells PostgreSQL tools where to find that directory.

```bash
# The environment variable tells pg_ctl, psql, and other tools where the cluster lives
export PGDATA=/opt/pgsql/data

# These two commands are equivalent:
pg_ctl -D /opt/pgsql/data start
pg_ctl start                      # uses $PGDATA
```

Every PostgreSQL binary that touches the data directory supports either the
`-D` flag or the `PGDATA` environment variable. The `-D` flag always takes
precedence.

**Ownership rules:** PGDATA must be owned by the postgres OS user with `0700`
permissions (owner only). PostgreSQL refuses to start if other users can read
the data directory.

> **Concept:** The `PGDATA` environment variable is the single most important
> piece of configuration for any PostgreSQL tool. Set it wrong (or leave it
> unset without using `-D`) and you will get confusing errors about missing
> files or wrong versions. As you saw in Build Guide 01, we set `PGDATA` in
> the postgres user's `.bash_profile` so it is always available.

### 3.3 System Identifier

The **system identifier** is a 64-bit integer assigned at `initdb` time,
derived from the timestamp and PID. It never changes. View it with
`pg_controldata $PGDATA | grep "system identifier"` or
`SELECT system_identifier FROM pg_control_system()`.

Streaming replication uses it to verify primary/standby belong together.
Backup tools record it to prevent cross-cluster WAL mixing. You cannot
change it - a new identifier requires a new cluster.

### 3.4 Data Checksums

**Data checksums** are optional page-level integrity checks that PostgreSQL
writes into every data page (8 KB block) in the cluster. When enabled,
PostgreSQL computes a checksum when writing a page to disk and verifies it
when reading the page back. If the checksum does not match, PostgreSQL raises
a `WARNING` (by default) or an `ERROR` (if `ignore_checksum_failure` is off).

Each 8 KB data page includes a 2-byte checksum computed at write time and
verified at read time. This catches bit rot, firmware bugs, storage controller
errors, and torn writes.

**Critical limitation:** Checksums can only be enabled at `initdb` time or by
running `pg_checksums --enable` on a stopped cluster (PostgreSQL 12+), which
requires reading and rewriting every data page. CPU overhead is 1-3% -
negligible on modern hardware. Every PostgreSQL expert recommends enabling
them.

> **Concept:** Always enable data checksums for any cluster that holds data you
> care about. The `initdb --data-checksums` flag is a one-time decision with
> zero practical downside and enormous diagnostic value. As you saw in Build
> Guide 01, we always pass `--data-checksums` when initializing a cluster.
> Scenario 10 simulates this exact failure - a corrupted data page detected
> by checksums.

### 3.5 Postmaster Process

The **postmaster** is the parent process of a running PostgreSQL instance. It
forks child processes for background tasks and client connections.

```
Postmaster Process Tree
========================

  postmaster (PID 1234)                # Parent process
  ├── checkpointer                     # Writes dirty buffers to disk
  ├── background writer                # Gradually writes dirty buffers
  ├── walwriter                        # Flushes WAL to disk
  ├── autovacuum launcher              # Schedules autovacuum workers
  ├── walsender                        # Streams WAL to standbys
  ├── backend (app_user@app_db)        # Client connection
  └── backend (admin@postgres)         # Client connection
```

Three critical responsibilities: (1) listen for connections, authenticate
against `pg_hba.conf`, and fork a dedicated backend for each; (2) allocate
and manage shared memory (buffer pool, WAL buffers, lock tables); (3)
supervise children - if a backend crashes, the postmaster terminates all
others, runs crash recovery, and restarts. The `postmaster.pid` file in
PGDATA prevents two instances from managing the same data directory.

### 3.6 WAL Segment

A **WAL segment** (also called a WAL file) is a 16 MB file in the `pg_wal/`
directory that contains a sequential record of every change made to the
database. PostgreSQL writes changes to WAL before applying them to the actual
data files. This write-ahead logging is the foundation of crash recovery,
replication, and point-in-time recovery.

| Property | Default Value | Configurable? |
| -------- | ------------- | ------------- |
| Segment size | 16 MB | Only at `initdb` time (`--wal-segsize`) |
| Location | `PGDATA/pg_wal/` | Can symlink to another filesystem |
| Naming | 24 hex characters (timeline + segment number) | No |
| Minimum on disk | 1 segment | `min_wal_size` controls lower bound |
| Maximum on disk | Varies | `max_wal_size` controls upper bound |

WAL segment filenames are 24 hex characters: 8 for the timeline, 16 for the
segment number. Example: `000000010000000000000001` is timeline 1, segment 1.
When a segment fills up, PostgreSQL switches to a new one. You can force a
switch with `SELECT pg_switch_wal()` (useful before backups).

### 3.7 Configuration Context

Every PostgreSQL parameter has a **context** that determines when changes to
that parameter take effect. Understanding context is critical for knowing
whether you need a full server restart (downtime) or just a configuration
reload (no downtime).

| Context | When Change Takes Effect | How to Apply | Examples |
| ------- | ----------------------- | ------------ | -------- |
| `internal` | Compile time only. Cannot change. | Recompile PostgreSQL | `block_size`, `wal_block_size`, `integer_datetimes` |
| `postmaster` | Server startup only. Requires full restart. | `pg_ctl restart` or `systemctl restart` | `max_connections`, `shared_buffers`, `port`, `listen_addresses`, `wal_level` |
| `sighup` | Configuration reload. No restart needed. | `pg_ctl reload`, `SELECT pg_reload_conf()`, or `systemctl reload` | `work_mem`, `log_min_duration_statement`, `archive_command` |
| `superuser` | Next statement by any superuser session. | `SET` in session, or reload for global | `log_temp_files`, `deadlock_timeout` |
| `user` | Next statement by any session. | `SET` in session, or reload for global | `search_path`, `statement_timeout`, `work_mem` |
| `superuser-backend` | Next new superuser connection. | Disconnect and reconnect | `log_connections` (in some builds) |
| `backend` | Next new connection. | Disconnect and reconnect | `ignore_system_indexes` |

You can query the context of any parameter:

```sql
SELECT name, context, setting, unit
FROM pg_settings
WHERE name = 'max_connections';

--  name            | context    | setting | unit
-- -----------------+------------+---------+------
--  max_connections  | postmaster | 100     |
```

This tells you that changing `max_connections` requires a full server restart.
There is no way around it. The postmaster allocates fixed shared memory
structures at startup based on `max_connections`, and those structures cannot
be resized while the server is running.

> **Concept:** Before changing any PostgreSQL parameter in production, always
> check its context in `pg_settings`. If the context is `postmaster`, the
> change requires a restart and therefore a brief outage. Plan accordingly.
> If the context is `sighup` or lower, you can apply the change with a
> reload - zero downtime. As you saw in Build Guide 03, we used
> `SELECT pg_reload_conf()` for sighup parameters and restarted only when
> changing postmaster parameters like `shared_buffers`.

### 3.8 pg_hba.conf Rule Evaluation

**pg_hba.conf** (PostgreSQL host-based authentication) controls which clients
can connect to which databases as which users, and how they must authenticate.
The rules are evaluated in a specific order, and understanding that order is
essential for debugging connection problems.

**Evaluation rules:**

1. PostgreSQL reads `pg_hba.conf` from top to bottom.
2. For each incoming connection, it checks each rule in order.
3. The **first rule that matches** the connection type, client address,
   database, and user is used. No further rules are checked.
4. If the matching rule says `reject`, the connection is denied.
5. If the matching rule says `trust`, the connection is allowed without a
   password.
6. If the matching rule specifies an authentication method (e.g.,
   `scram-sha-256`), the client must satisfy that method.
7. If no rule matches at all, the connection is denied (implicit deny).

This is a **first-match** system, not a best-match system. Order matters
enormously. A broad rule placed too high in the file will shadow more specific
rules below it.

```
pg_hba.conf Rule Evaluation Flow
=================================

  Incoming connection:
  Type=host, User=alice, DB=production, IP=10.0.1.50

  Rule 1: local  all  all  peer                    -> No match (not local)
  Rule 2: host   all  all  127.0.0.1/32  scram...  -> No match (wrong IP)
  Rule 3: host   all  all  10.0.1.0/24   scram...  -> MATCH! Use scram-sha-256.
  Rule 4: host   all  all  0.0.0.0/0     reject    -> Never reached.

  Result: alice must provide a valid scram-sha-256 password.
```

---

## 4. initdb Deep Dive

### What initdb actually does

`initdb` is the command that creates a new PostgreSQL cluster. It is run once,
at the very beginning of a cluster's life. You never run `initdb` on an
existing cluster - that would destroy all data.

`initdb` creates the PGDATA directory (0700 permissions), subdirectories
(`base/`, `global/`, `pg_wal/`, `pg_xact/`, etc.), system catalogs in
`global/`, three databases (template0, template1, postgres), configuration
files (`postgresql.conf`, `pg_hba.conf`, `pg_ident.conf`), the control file
(`global/pg_control` with system identifier, checksums flag, locale, etc.),
and the initial WAL segment.

### Template databases

`initdb` creates three databases. Two of them are templates:

| Database | OID | Purpose | Modifiable? | Used By |
| -------- | --- | ------- | ----------- | ------- |
| `template0` | 4 | Pristine factory template. Never modified. Used when you need a clean database with a different locale. | No. Cannot connect to it. | `CREATE DATABASE ... TEMPLATE template0` |
| `template1` | 1 | Default template for `CREATE DATABASE`. Add shared extensions (pgcrypto, uuid-ossp) here so all new databases get them. | Yes | `CREATE DATABASE dbname` (implicit template1) |
| `postgres` | 5 | Default connection database for maintenance tasks. Just a regular database. | Yes | `psql -d postgres` for admin work |

Install shared extensions in `template1` so they propagate to all new
databases. You cannot modify template0 - it exists as a clean baseline.
When creating a database with a different locale or encoding, you must use
template0: `CREATE DATABASE french_data TEMPLATE template0 LC_COLLATE
'fr_FR.UTF-8'`.

### Decisions that are permanent

Some `initdb` options are baked into the cluster permanently. You cannot
change them later without destroying the cluster and rebuilding from scratch.
These decisions deserve careful thought.

| Option | initdb Flag | Default | Can Change Later? | Impact of Getting It Wrong |
| ------ | ----------- | ------- | ----------------- | ------------------------- |
| **Locale (collation)** | `--locale=xx_XX.UTF-8` | OS default | No | Wrong sort order for your language. Must dump and reload. |
| **Encoding** | `--encoding=UTF8` | Derived from locale | No | Wrong character encoding. Must dump and reload. |
| **Data checksums** | `--data-checksums` | Off | Can enable offline with `pg_checksums` (PG 12+). Requires full downtime. | Silent data corruption goes undetected. |
| **WAL segment size** | `--wal-segsize=N` (in MB) | 16 MB | No | Wrong size for your workload. Too small = excessive WAL switching on busy systems. Too large = wasted disk on quiet systems. 16 MB is correct for 95% of workloads. |
| **Block size** | `--with-blocksize=N` (compile time) | 8 KB | No (compile-time only) | Almost never changed. |

Everything in `postgresql.conf` can be changed later (`max_connections`,
`shared_buffers`, `listen_addresses`, `port`, etc.) - these are just
starting-point defaults.

### pg_controldata - the cluster fingerprint

The `pg_controldata` command reads the `global/pg_control` file and displays
every critical metadata field about the cluster. This is your go-to diagnostic
tool when you need to understand the state of a cluster - especially one you
did not build yourself.

```
$ pg_controldata /opt/pgsql/data

Database system identifier:           7355210286638503921
Database cluster state:               in production
Latest checkpoint location:           0/1A5B3D0
Latest checkpoint's REDO location:    0/1A5B398
Latest checkpoint's TimeLineID:       1
Database block size:                   8192
Bytes per WAL segment:                 16777216
Data page checksum version:            1          # 0 = off, 1 = on
...  (many more fields)
```

The most important fields:

| Field | What It Tells You |
| ----- | ----------------- |
| `Database system identifier` | Unique cluster ID. Must match between primary and standby. |
| `Database cluster state` | Current state: `in production`, `shut down`, `in crash recovery`, `in archive recovery` |
| `Data page checksum version` | 0 = checksums off. 1 = checksums on. |
| `Bytes per WAL segment` | WAL segment size. 16777216 = 16 MB (default). |
| `Latest checkpoint location` | Last successful checkpoint WAL position. Critical for crash recovery. |
| `Latest checkpoint's TimeLineID` | Current timeline. Increments after PITR or promotion. |

> **Concept:** `pg_controldata` works on a stopped cluster. You do not need
> the server running to read it. This makes it invaluable for diagnosing a
> cluster that will not start. If you inherit an unknown cluster, run
> `pg_controldata` first to understand what you are dealing with - version,
> checksums, state, last checkpoint. As you saw in Build Guide 01, we ran
> `pg_controldata` immediately after `initdb` to verify our settings.

---

## 5. Configuration Architecture

### The configuration hierarchy

PostgreSQL has a layered configuration system. Settings can come from multiple
sources, and there is a strict precedence order. Understanding this hierarchy
is essential for debugging "why is this parameter set to that value?" questions.

```
Configuration Precedence (lowest to highest priority)
=====================================================

  1. Compile-time defaults           (built into the binary)
       |  overridden by
  2. postgresql.conf                 (main config file in PGDATA)
       |  overridden by
  3. conf.d/*.conf                   (alphabetical order, last file wins)
       |  overridden by
  4. postgresql.auto.conf            (ALTER SYSTEM writes here)
       |  overridden by
  5. Per-database / per-role SET     (ALTER DATABASE/ROLE ... SET)
       |  overridden by
  6. Session SET commands            (SET work_mem = '512MB')   <-- highest
```

Each level overrides the one above it. A `SET` command in a session always
wins, regardless of what `postgresql.conf` says.

### postgresql.conf - the base file

This is the primary configuration file, located in PGDATA by default. It
contains key-value pairs, one per line:

```ini
listen_addresses = 'localhost'      # which interfaces to bind to
port = 5432                         # TCP port
max_connections = 100               # maximum concurrent connections
shared_buffers = 128MB              # shared memory for data caching
work_mem = 4MB                      # per-operation memory for sorts/hashes
wal_level = replica                 # minimal, replica, or logical
max_wal_size = 1GB                  # trigger checkpoint at this WAL size
logging_collector = on
log_min_duration_statement = 1000   # log queries taking more than 1 second
```

Strings must be quoted (`'localhost'`), numerics are unquoted (`5432`),
memory values take units (`MB`, `GB`), time values take units (`ms`, `s`,
`min`), and booleans accept `on`/`off`, `true`/`false`, `yes`/`no`.

### The conf.d pattern

In production, you rarely edit `postgresql.conf` directly. Instead, you add
a line at the end of `postgresql.conf` that includes a directory of override
files:

```ini
# At the bottom of postgresql.conf:
include_dir = 'conf.d'
```

Then create individual files in the `conf.d/` directory:

```
PGDATA/conf.d/
├── 00-tuning.conf          # Memory, checkpoints, WAL
├── 01-logging.conf         # Log settings
├── 02-replication.conf     # Replication parameters
├── 03-security.conf        # SSL, authentication
└── 99-overrides.conf       # Temporary overrides, testing
```

Files are loaded in alphabetical order. If the same parameter appears in
multiple files, the last one loaded wins. The numeric prefix convention
(`00-`, `01-`, `02-`) gives you explicit control over load order.

**Why this pattern matters:** version control (git diff individual files),
automation (Ansible manages files in conf.d without touching postgresql.conf),
rollback (delete one file instead of editing 700 lines), and multi-tool
management (pgBackRest owns `pgbackrest.conf`, Patroni owns `patroni.conf`).

### postgresql.auto.conf - ALTER SYSTEM

`ALTER SYSTEM SET shared_buffers = '256MB'` writes to `postgresql.auto.conf`,
which is always read after `postgresql.conf` and `conf.d/`. Use
`ALTER SYSTEM RESET param` to remove a setting or `ALTER SYSTEM RESET ALL`
to clear everything.

**Important:** `ALTER SYSTEM` does not apply immediately - you still need to
reload or restart. And the danger: `postgresql.auto.conf` is invisible to
configuration management tools like Ansible. Someone runs `ALTER SYSTEM` on
production, Ansible does not see it, and you get config drift.

> **Concept:** Many production teams disable `ALTER SYSTEM` entirely using
> the `allow_alter_system` parameter (PostgreSQL 17+) or by making
> `postgresql.auto.conf` immutable with `chattr +i`. All configuration changes
> go through the conf.d pattern and version control. As you saw in Build
> Guide 02, we used ALTER SYSTEM for quick lab changes, but the conf.d
> pattern is what you should use in production.

### pg_settings - the single source of truth

The `pg_settings` view answers "what is this parameter set to, and where did
that value come from?" Key columns: `name`, `setting`, `unit`, `source`
(default/configuration file/session), `sourcefile`, `sourceline`, `context`,
`pending_restart`, `boot_val`, `reset_val`.

```sql
SELECT name, setting, unit, source, sourcefile, context, pending_restart
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'max_connections');
```

The `pending_restart` column is particularly useful - after changing a
postmaster-context parameter and reloading, it shows `true` to confirm the
change is recorded but not yet active.

Refer back to the context table in Section 3.7 for the complete reference on
which parameters require restarts, reloads, or reconnections.

---

## 6. pg_hba.conf Deep Dive

### Rule format

Each line in `pg_hba.conf` defines one authentication rule. The format is:

```
TYPE    DATABASE    USER    ADDRESS          METHOD    [OPTIONS]
```

| Field | Description | Examples |
| ----- | ----------- | -------- |
| `TYPE` | Connection type | `local`, `host`, `hostssl`, `hostnossl`, `hostgssenc` |
| `DATABASE` | Database name(s) to match | `all`, `sameuser`, `samerole`, `replication`, `app_db`, `"db1,db2"` |
| `USER` | Role name(s) to match | `all`, `app_user`, `+admin_group`, `"alice,bob"` |
| `ADDRESS` | Client IP address/range (not used for `local`) | `127.0.0.1/32`, `10.0.0.0/8`, `::1/128`, `.example.com` |
| `METHOD` | Authentication method | `trust`, `reject`, `peer`, `scram-sha-256`, `md5`, `cert`, `gss`, `ldap` |
| `OPTIONS` | Method-specific options | `clientcert=verify-full`, `map=mymap`, `ldapserver=ldap.example.com` |

### Connection types

| Type | Description | When to Use |
| ---- | ----------- | ----------- |
| `local` | Unix-domain socket connection. No network involved. | Connections from the same machine using `psql` without `-h`. Used with `peer` auth for OS-user-to-DB-role mapping. |
| `host` | TCP/IP connection, with or without SSL. | General network connections. Combined with `scram-sha-256` or `md5` for password auth. |
| `hostssl` | TCP/IP connection that MUST use SSL. Non-SSL connections are rejected by this rule. | Production connections that require encryption in transit. |
| `hostnossl` | TCP/IP connection that MUST NOT use SSL. | Rare. Sometimes used on internal networks for performance-sensitive connections where SSL overhead is measured and unacceptable. |
| `hostgssenc` | TCP/IP connection with GSSAPI encryption. | Kerberos/Active Directory environments. |

### Authentication methods

| Method | How It Works | Security Level | Use Case |
| ------ | ------------ | -------------- | -------- |
| `trust` | Accept the connection without any authentication. Anyone can connect. | None | Local development only. **Never in production.** |
| `reject` | Deny the connection unconditionally. | N/A (blocks access) | Explicitly block specific users, databases, or IP ranges. |
| `peer` | Match the OS username to the PostgreSQL role name. No password needed. | High (relies on OS auth) | `local` connections where the postgres OS user connects as the postgres role. |
| `ident` | Like peer, but for TCP connections. Requires an ident server. | Medium | Rare in modern deployments. |
| `scram-sha-256` | Challenge-response password authentication. Password is never sent in plaintext. | High | **Recommended for all password-based auth.** Default in PostgreSQL 14+. |
| `md5` | MD5-hashed password authentication. | Medium (vulnerable to replay attacks) | Legacy. Use scram-sha-256 instead. |
| `cert` | Client must present a valid TLS certificate. No password. | Very high | Zero-trust environments, service-to-service connections. |
| `gss` | Kerberos/GSSAPI authentication. | Very high | Enterprise environments with Active Directory/Kerberos. |
| `ldap` | Verify password against an LDAP server. | High | Centralized password management. |
| `radius` | Verify password against a RADIUS server. | High | Network access control environments. |
| `pam` | Use the OS PAM (Pluggable Authentication Modules) stack. | Varies | OS-integrated authentication. |

### A production pg_hba.conf example

```ini
# TYPE    DATABASE        USER            ADDRESS              METHOD
local     all             postgres                              peer
host      replication     replicator      10.0.1.20/32          scram-sha-256
host      replication     replicator      10.0.1.21/32          scram-sha-256
hostssl   app_production  app_user        10.0.2.0/24           scram-sha-256
hostssl   all             dba_admin       10.0.10.0/24          scram-sha-256
host      postgres        pgmonitor       127.0.0.1/32          scram-sha-256
host      all             all             0.0.0.0/0             reject
```

Notice the pattern: local peer for the superuser, specific IP ranges for
replication and application connections, SSL required for sensitive databases,
and an explicit reject-all at the bottom.

### Common pg_hba.conf mistakes

1. **Broad rule shadows specific rules.** A `host all all 0.0.0.0/0` rule
   placed too high matches everything - specific rules below never trigger.
   Always put specific rules first, catch-all reject last.

2. **Forgetting `local` vs `host`.** A `host` rule for `127.0.0.1/32` does
   not match Unix socket connections (`psql` without `-h`). Add a `local`
   rule for socket access.

3. **Leftover `trust` rule.** Added for debugging, forgotten for months.
   Anyone can connect as anyone without a password. Audit regularly.

4. **Typo in database or role name.** PostgreSQL does not validate that the
   database or role exists when reading pg_hba.conf. `app_prodduction` will
   silently fail to match.

### Validating pg_hba.conf

Use `SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL` (PostgreSQL 15+)
to find syntax errors before reloading. A reload with syntax errors keeps the
old rules - you will not lock yourself out from a typo. But a logical error
(misplaced `reject` rule) will lock you out.

> **Concept:** Always keep a `local` peer rule for the postgres OS user as a
> backdoor via Unix socket. If you lock yourself out of TCP connections with
> a bad pg_hba.conf edit, you can still connect locally and fix it. As you
> saw in Build Guide 02, we added rules one at a time and tested each before
> adding the next.

---

## 7. Server Lifecycle

### The postmaster process tree (detailed)

When PostgreSQL starts, it follows a precise initialization sequence. Each
step must succeed before the next one begins. If any step fails, the server
aborts startup and logs the reason.

```
PostgreSQL Startup Sequence
============================

  pg_ctl start -D /opt/pgsql/data
       |
  1. Read postgresql.conf, postgresql.auto.conf
  2. Validate configuration parameters
  3. Check PGDATA permissions (must be 0700, owned by current user)
  4. Check for existing postmaster.pid (abort if already running)
  5. Allocate shared memory (shared_buffers, wal_buffers, lock tables)
  6. Perform crash recovery if needed (replay WAL from last checkpoint)
  7. Start background processes (checkpointer, bgwriter, walwriter, autovacuum)
  8. Open listening sockets (bind to listen_addresses:port)
  9. Write postmaster.pid
  10. Log "database system is ready to accept connections"
       |
  READY - accepting client connections
```

### Shutdown modes

PostgreSQL supports three shutdown modes. Choosing the right one matters for
both data safety and client impact.

```
Shutdown Mode Comparison
=========================

  Smart (-m smart)         Fast (-m fast)          Immediate (-m immediate)
  =====================    =====================   =========================
  Wait for all sessions    Terminate sessions      Abort all processes
  to disconnect            (SIGTERM), roll back    immediately (SIGQUIT)
  voluntarily              in-progress txns
                                                   Next startup REQUIRES
  Then checkpoint +        Then checkpoint +       crash recovery (WAL replay)
  clean shutdown           clean shutdown

  Duration: UNPREDICTABLE  Duration: SECONDS       Duration: INSTANT
  Data safety: CLEAN       Data safety: CLEAN      Data safety: CLEAN (WAL)
```

| Mode | Flag | When to Use | Risk |
| ---- | ---- | ----------- | ---- |
| **Smart** | `-m smart` (default in `pg_ctl`) | Graceful maintenance. You can wait. | May never complete if a session stays connected (e.g., a leaked connection from an app server). |
| **Fast** | `-m fast` (default in `systemctl stop`) | Standard production shutdown. Maintenance windows. | Active transactions are rolled back. Clients get disconnected. |
| **Immediate** | `-m immediate` | Emergency only. The server is hung. Fast shutdown is not working. | Crash recovery on next startup. Duration depends on WAL volume since last checkpoint. |

> **Concept:** In production, `fast` is the standard shutdown mode. `systemctl
> stop postgresql` uses `fast` by default, which is correct. Never use `smart`
> in production - a single leaked connection will prevent the server from
> shutting down. Never use `immediate` unless `fast` has failed, because the
> crash recovery time on restart is unpredictable. As you saw in Build Guide
> 03, we practiced all three modes to see the difference in behavior.

### Restart vs Reload

This distinction is critical for production operations. Getting it wrong means
either unnecessary downtime (restarting when a reload would suffice) or
confusion (reloading when a restart is needed and wondering why the change
did not take effect).

```
Reload vs Restart Decision Tree
================================

  Changed a parameter. What is its context?
  (SELECT context FROM pg_settings WHERE name = 'your_param')

  postmaster?          --> RESTART required (brief outage)
  sighup?              --> RELOAD sufficient (zero downtime)
  superuser / user?    --> RELOAD for global, or SET in session
  backend?             --> New connections only (RELOAD applies globally)
  internal?            --> Cannot change. Period.
```

**Reload:** The postmaster re-reads all config files, validates new values,
applies sighup-context changes immediately, and sends SIGHUP to all child
processes. If invalid, it logs an error and keeps old values.

**Restart:** Stop + start. All connections terminated, checkpoint performed,
new shared memory allocated, all parameter values take effect. Clients must
reconnect.

### pg_ctl vs systemctl

Use `systemctl` for production (init integration, auto-start, journald). Use
`pg_ctl` for manual management (labs, custom installs, multi-cluster). Both
support `start`, `stop`, `restart`, `reload`, and `status`. In our lab we use
`pg_ctl` since we installed from source without a systemd unit file.

### Verifying server readiness

`pg_isready` checks whether PostgreSQL is accepting connections without
authenticating. Exit codes: 0 = accepting, 1 = rejecting (startup), 2 = no
response, 3 = bad parameters. Use it for load balancer health checks, Docker
HEALTHCHECK, and Kubernetes liveness probes.

---

## 8. Production Best Practices

### The conf.d pattern in practice

Production PostgreSQL should never have hand-edited changes in the main
`postgresql.conf`. Instead, use the conf.d pattern described in Section 5.

A typical production layout: `00-base.conf` (shared_buffers, max_connections),
`01-memory.conf`, `02-wal.conf`, `03-checkpoint.conf`, `04-logging.conf`,
`05-replication.conf`, `06-security.conf`, `07-autovacuum.conf`,
`08-pgbackrest.conf`, and `99-emergency.conf` (empty, for incident response).
Each file is version-controlled in Git. Changes go through code review.

### Configuration management and drift detection

Use Ansible (or Puppet/Chef/Salt) to manage conf.d files as templates. The
workflow: DBA edits the Ansible template, opens a pull request, another DBA
reviews, Ansible applies the change and runs `pg_ctl reload`. Rollback is a
simple `git revert` + Ansible run.

Even with automation, drift happens (someone runs `ALTER SYSTEM`, a DBA edits
a file manually). Monitor for it:

```sql
-- Find parameters that differ from the config file value
SELECT name, setting, source, sourcefile
FROM pg_settings
WHERE source NOT IN ('default', 'configuration file', 'override')
ORDER BY name;

-- Find parameters pending restart
SELECT name, setting, pending_restart
FROM pg_settings
WHERE pending_restart = true;
```

Set up a monitoring alert that fires when `pending_restart` is true for any
parameter. This catches forgotten restarts after postmaster-context changes.

### pg_isready in health checks

Use `pg_isready` as the standard health check in Docker (`HEALTHCHECK CMD
pg_isready`), Kubernetes (liveness probes), HAProxy (backend health), and
monitoring systems (Prometheus, Datadog). It returns exit code 0 when the
server is accepting connections, making it ideal for automation.

### Graceful restarts during maintenance windows

When you must restart for a postmaster-context parameter change: (1) schedule
the window with the application team, (2) pre-validate by reloading first to
catch syntax errors, (3) drain connections via PgBouncer `PAUSE`, (4) restart
with `systemctl restart postgresql`, (5) verify with `pg_isready` and
`pg_settings`, (6) resume with PgBouncer `RESUME` and monitor error rates.

### Connection pooling with PgBouncer

PostgreSQL creates a dedicated backend process for every client connection.
Each backend consumes 5-10 MB of RAM. With `max_connections = 1000`, that is
5-10 GB just for connection overhead. **PgBouncer** multiplexes many client
connections onto a smaller pool of server connections:

```
Connection Pooling with PgBouncer
==================================

  App Servers (150 conns) ---> PgBouncer (pool: 25) ---> PostgreSQL (max_connections: 50)

  150 client connections multiplexed onto 25 server connections.
  RAM saved: ~1.2 GB (125 fewer backends x ~10 MB each)
```

| Pooling Mode | How It Works | Best For |
| ------------ | ------------ | -------- |
| **Session** | Dedicated server connection for entire session | Apps using temp tables, prepared statements |
| **Transaction** | Server connection per transaction, returned to pool between | Most web apps (recommended) |
| **Statement** | Server connection per statement | Simple queries only |

> **Concept:** The single biggest mistake in PostgreSQL capacity planning is
> setting `max_connections` too high. Every connection consumes memory, adds
> lock contention, and increases checkpoint overhead. With PgBouncer in
> transaction mode, a 100-backend PostgreSQL server can serve thousands of
> concurrent application connections. Set `max_connections` to the minimum
> required, not the maximum possible.

---

## 9. Common Commands Quick Reference

### Cluster Initialization

| Command | Description | Example |
| ------- | ----------- | ------- |
| `initdb -D $PGDATA --data-checksums` | Create a new cluster with checksums enabled | `initdb -D /opt/pgsql/data --data-checksums --locale=en_US.UTF-8 --encoding=UTF8` |
| `initdb -D $PGDATA --waldir=/path` | Create cluster with WAL on a separate disk | `initdb -D /opt/pgsql/data --waldir=/opt/pgsql/wal --data-checksums` |
| `initdb -D $PGDATA --auth-local=peer --auth-host=scram-sha-256` | Set default pg_hba.conf auth methods | Sets peer for local and scram for host connections |
| `initdb --show` | Display default initdb settings | Shows locale, encoding, text search config |

### Server Control

| Command | Description | Notes |
| ------- | ----------- | ----- |
| `pg_ctl start -D $PGDATA` | Start the server | Add `-l logfile` to direct startup messages to a file |
| `pg_ctl stop -D $PGDATA -m fast` | Stop the server (fast mode) | Terminates active sessions, performs checkpoint |
| `pg_ctl restart -D $PGDATA` | Restart the server | Equivalent to stop + start |
| `pg_ctl reload -D $PGDATA` | Reload configuration files | Zero downtime. Only applies sighup-context changes. |
| `pg_ctl status -D $PGDATA` | Check if server is running | Shows PID and data directory |
| `pg_isready -h host -p port` | Check if server is accepting connections | Lightweight health check. Exit code 0 = ready. |

### Configuration

| Command / Query | Description |
| --------------- | ----------- |
| `SHOW shared_buffers;` | Show current value of a parameter |
| `SHOW ALL;` | Show all parameter values |
| `SELECT * FROM pg_settings WHERE name = 'param';` | Detailed parameter info including source and context |
| `SELECT * FROM pg_settings WHERE pending_restart;` | Parameters changed but awaiting restart |
| `ALTER SYSTEM SET param = 'value';` | Write a setting to postgresql.auto.conf |
| `ALTER SYSTEM RESET param;` | Remove a setting from postgresql.auto.conf |
| `SELECT pg_reload_conf();` | Reload configuration from SQL |

### Authentication

| Command / Query | Description |
| --------------- | ----------- |
| `SELECT * FROM pg_hba_file_rules;` | View parsed pg_hba.conf rules (PG 15+) |
| `SELECT * FROM pg_hba_file_rules WHERE error IS NOT NULL;` | Find syntax errors in pg_hba.conf |
| `ALTER ROLE alice PASSWORD 'newpassword';` | Set a role's password (use scram-sha-256) |
| `SET password_encryption = 'scram-sha-256';` | Ensure passwords are stored as scram hashes |
| `SELECT rolname, rolcanlogin FROM pg_roles;` | List all roles and their login ability |

### Diagnostics

| Command | Description |
| ------- | ----------- |
| `pg_controldata $PGDATA` | Display cluster control file (works on stopped clusters) |
| `pg_checksums --check -D $PGDATA` | Verify data checksums (requires server stopped, PG 12+) |
| `pg_checksums --enable -D $PGDATA` | Enable checksums on existing cluster (requires server stopped, PG 12+) |
| `SELECT pg_postmaster_start_time();` | When was the server last started? |
| `SELECT pg_conf_load_time();` | When was the configuration last loaded? |
| `SELECT pg_is_in_recovery();` | Is this server a standby (in recovery mode)? |

---

## 10. Troubleshooting

### Error 1: "could not access the server configuration file"

```
FATAL: could not access the server configuration file "/opt/pgsql/data/postgresql.conf":
No such file or directory
```

**Cause:** The PGDATA path is wrong, the config file is missing, or the `-D`
flag points to a non-existent directory.

**Fix:** Verify PGDATA with `echo $PGDATA`, confirm the directory exists with
`ls -la /opt/pgsql/data/postgresql.conf`. If using systemd, check the unit
file for `Environment=PGDATA=` or the `-D` flag in `ExecStart`.

---

### Error 2: "data directory has wrong ownership"

```
FATAL: data directory "/opt/pgsql/data" has wrong ownership
HINT: The server must be started by the user that owns the data directory.
```

**Cause:** Starting PostgreSQL as a user other than the one who owns PGDATA.
Usually means you ran the command as root instead of postgres.

**Fix:** Check ownership with `ls -la /opt/pgsql/ | grep data` (should show
`drwx------ postgres postgres`). Fix with `chown -R postgres:postgres
/opt/pgsql/data && chmod 700 /opt/pgsql/data` and start as the postgres user.

---

### Error 3: "lock file postmaster.pid already exists"

```
FATAL: lock file "postmaster.pid" already exists
HINT: Is another postmaster (PID 1234) running in data directory "/opt/pgsql/data"?
```

**Cause:** PostgreSQL is already running, or a previous crash left a stale
PID file.

**Fix:** Check if the PID is running: `head -1 $PGDATA/postmaster.pid` then
`ps -p <PID>`. If running, connect to it. If stale, remove the file and
start. PostgreSQL 9.3+ automatically cleans stale PID files in most cases.

---

### Error 4: "could not bind to address"

```
LOG: could not bind to IPv4 address "0.0.0.0": Address already in use
FATAL: could not create any TCP/IP sockets
```

**Cause:** Another process is already listening on the configured port.

**Fix:** Find what is using it: `ss -tlnp | grep 5432`. Either stop the
conflicting process or change your cluster's port in `postgresql.conf`. If
the port is in TCP TIME_WAIT from a recent exit, wait 30-60 seconds.

---

### Error 5: "invalid value for parameter"

```
FATAL: invalid value for parameter "shared_buffers": "256"
HINT: Valid units are "B", "kB", "MB", "GB", and "TB".
```

**Cause:** Missing units, out-of-range value, or typo. PostgreSQL requires
explicit units for memory and time parameters.

**Fix:** Check the expected format: `SELECT name, vartype, min_val, max_val,
unit FROM pg_settings WHERE name = 'shared_buffers'`. Common mistake: writing
`shared_buffers = 256` instead of `shared_buffers = 256MB`.

---

### Error 6: "no pg_hba.conf entry for host"

```
FATAL: no pg_hba.conf entry for host "10.0.1.50", user "app_user", database "production",
       no encryption
```

**Cause:** No rule matches the connection type, client IP, database, and user.
This is the most common authentication error.

**Fix:** The error message tells you exactly what to match. Add a rule:
`host  production  app_user  10.0.1.50/32  scram-sha-256`, then reload.
Check for broad rules shadowing specific ones, typos in database/role names,
and whether the client needs SSL (`hostssl` vs `host`).

---

### Error 7: "too many connections for role"

```
FATAL: too many connections for role "app_user"
```

**Cause:** The role has a connection limit (`ALTER ROLE app_user CONNECTION
LIMIT 10`) that has been reached. Different from the global `max_connections`.

**Fix:** Check with `SELECT rolname, rolconnlimit FROM pg_roles WHERE rolname
= 'app_user'` and `SELECT count(*) FROM pg_stat_activity WHERE usename =
'app_user'`. Increase with `ALTER ROLE app_user CONNECTION LIMIT 50`. If you
see `FATAL: sorry, too many clients already` instead, that is the global
`max_connections` limit - requires a restart to increase.

---

### Error 8: "database system is starting up"

```
FATAL: the database system is starting up
```

**Cause:** The server is starting, likely performing crash recovery.

**Fix:** Wait. Check progress with `tail -f $PGDATA/log/postgresql-*.log`.
You will see redo progress and eventually "database system is ready to accept
connections." Use `until pg_isready -q; do sleep 1; done` to detect readiness.
If recovery is slow, consider reducing `max_wal_size` to shorten future
recovery times.

---

### Error 9: "the database system is shutting down"

```
FATAL: the database system is shutting down
```

**Cause:** You are connecting while the server is stopping.

**Fix:** Wait for shutdown to complete. If stuck (common with smart shutdown),
escalate: `pg_ctl stop -D $PGDATA -m fast`. If fast also stalls, use
`-m immediate` as a last resort.

---

### Error 10: "invalid page in block" (checksum failure)

```
WARNING: page verification failed, calculated checksum 12345 but expected 54321
ERROR: invalid page in block 42 of relation base/16384/16385
```

**Cause:** A data page is corrupted - disk failure, memory bit flip, or
storage controller bug. The checksum does not match.

**Fix:** Do not restart. Identify the table (`SELECT relname FROM pg_class
WHERE relfilenode = 16385`), check extent with `pg_checksums --check -D
$PGDATA` (requires stopping the server), and restore from backup. As a
data-loss last resort, `SET zero_damaged_pages = on` skips corrupted pages.

> **Concept:** Checksum failures are the reason we enable data checksums at
> `initdb` time. Without checksums, corruption goes undetected and the
> application processes garbage data as valid. With checksums, PostgreSQL
> catches it immediately. Scenario 10 simulates this exact failure.

---

### Error 11: "could not open file pg_xact/0000"

```
ERROR: could not open file "pg_xact/0000": No such file or directory
```

**Cause:** The CLOG (commit log) file is missing - manual deletion, filesystem
failure, or botched restore.

**Fix:** The correct fix is restoring from backup. As a dangerous last resort
on a cleanly shut down cluster, you can create a zeroed file (`dd if=/dev/zero
of=$PGDATA/pg_xact/0000 bs=256k count=1`) which marks all transactions as
committed. This risks data integrity.

---

### Error 12: "could not write to file pg_wal/..."

```
PANIC: could not write to file "pg_wal/...": No space left on device
```

**Cause:** The `pg_wal/` filesystem is full. PANIC-level - PostgreSQL crashes.

**Fix:** Free space by removing archived WAL files (check `archive_status/`
for `.done` files), then start the server for crash recovery. Prevent
recurrence by fixing `archive_command` failures (unarchived WAL accumulates)
and putting `pg_wal/` on its own filesystem.

---

### Error 13: "SSL connection is required"

```
FATAL: no pg_hba.conf entry for host "10.0.1.50", user "app_user", ..., SSL off
```

**Cause:** Only `hostssl` rules exist for this connection, but the client did
not use SSL.

**Fix:** Connect with `sslmode=require`:
`psql "host=pg-primary dbname=production user=app_user sslmode=require"`.
For client certificates, add `sslcert`, `sslkey`, and `sslrootcert` parameters.

---

### Error 14: "checkpoints are occurring too frequently"

```
LOG: checkpoints are occurring too frequently (18 seconds apart)
HINT: Consider increasing the configuration parameter "max_wal_size".
```

**Cause:** WAL generation exceeds `max_wal_size`, forcing frequent checkpoints.

**Fix:** `ALTER SYSTEM SET max_wal_size = '4GB'; SELECT pg_reload_conf();`
This is a sighup parameter (no restart). Monitor with `SELECT checkpoints_timed,
checkpoints_req FROM pg_stat_bgwriter` - `checkpoints_req` should be much
smaller than `checkpoints_timed`.

---

### Troubleshooting summary table

| Error | Severity | Immediate Action | Root Cause |
| ----- | -------- | ---------------- | ---------- |
| Could not access config file | Startup failure | Verify PGDATA path | Wrong -D flag or missing PGDATA env var |
| Wrong ownership | Startup failure | `chown -R postgres:postgres` | Started as wrong OS user |
| postmaster.pid exists | Startup failure | Check if PID is running, remove if stale | Previous crash or double-start |
| Address already in use | Startup failure | `ss -tlnp \| grep PORT` | Port conflict |
| Invalid parameter value | Startup failure or reload failure | Fix the value in the config file | Typo, missing unit, out-of-range |
| No pg_hba.conf entry | Connection refused | Add matching rule to pg_hba.conf | Missing or mismatched rule |
| Too many connections | Connection refused | Increase role limit or check for leaks | Connection limit hit |
| System is starting up | Connection refused | Wait for crash recovery | Server still starting |
| System is shutting down | Connection refused | Wait for shutdown to complete | Server is stopping |
| Invalid page (checksum) | Data corruption | Identify table, restore from backup | Hardware failure |
| Missing pg_xact | Data corruption | Restore from backup | File deletion or disk failure |
| No space left (pg_wal) | PANIC / crash | Free disk space, fix archiving | Full WAL filesystem |
| SSL required | Connection refused | Connect with sslmode=require | pg_hba.conf requires SSL |
| Checkpoints too frequent | Performance warning | Increase max_wal_size | Write load exceeds checkpoint capacity |

---

*This concepts document accompanies Module 04: Creating and Managing Instances.
For hands-on practice, work through the Build Guides in the `build/` directory.
For failure simulation and recovery practice, see the Survive scenarios in
`survive/`.*

## 11. Cross-Platform: CentOS vs Ubuntu/Debian

### Why you must know both

In production, you will manage PostgreSQL on both Red Hat-family (CentOS, RHEL, Rocky, Alma) and Debian-family (Ubuntu, Debian) systems. The core PostgreSQL behavior is identical - same SQL, same WAL, same catalog. But the packaging, directory layout, service management, and tooling differ significantly.

> **Concept:** PostgreSQL itself is cross-platform. The differences are in how the OS packages, installs, and manages it. Think of it as the same engine in two different cars - the engine works the same, but the dashboard, ignition, and controls are arranged differently.

### The two packaging philosophies

**CentOS/RHEL** follows upstream PostgreSQL conventions closely. You get raw tools (`initdb`, `pg_ctl`) and manage clusters manually. Maximum control, more steps.

**Ubuntu/Debian** adds `postgresql-common` on top of upstream tools. Wrapper commands automate multi-cluster management. More convenience, hides some mechanics.

Neither is "better." CentOS teaches you what PostgreSQL actually does. Ubuntu teaches you how to manage multiple clusters efficiently. A senior DBA masters both.

### Directory layout comparison

```
CentOS/RHEL Layout:                        Ubuntu/Debian Layout:
==========================                 ==========================
/usr/pgsql-16/bin/       <-- Binaries      /usr/lib/postgresql/16/bin/
/opt/pgsql/data/         <-- PGDATA        /var/lib/postgresql/16/main/  <-- PGDATA
  postgresql.conf        (config+data        postgresql.auto.conf        (data only)
  postgresql.auto.conf    together)          base/, global/, pg_wal/
  pg_hba.conf
  conf.d/                <-- if created    /etc/postgresql/16/main/      <-- Config
  base/, global/, pg_wal/                    postgresql.conf              (separated!)
/opt/pgsql/log/          <-- Logs            pg_hba.conf, pg_ident.conf
                                             conf.d/                     <-- default!
                                           /var/log/postgresql/          <-- Logs
```

> **Concept:** Ubuntu separates config from data so sysadmins can back up `/etc/` (config) and `/var/lib/` (data) independently. `apt upgrade postgresql-16` will not overwrite config files since they live in `/etc/`, not in the package-managed directory.

### The Ubuntu cluster management tools

| Command | Purpose | CentOS Equivalent |
|---------|---------|-------------------|
| `pg_lsclusters` | List all clusters (version, name, port, status) | `systemctl list-units 'postgresql*'` + manual checks |
| `pg_createcluster 16 test` | Create cluster (initdb + systemd + config) | Manual: mkdir + chown + initdb + systemd unit + config |
| `pg_dropcluster 16 test --stop` | Remove cluster (stop + delete data + systemd) | Manual: stop + disable + rm unit + rm data |
| `pg_ctlcluster 16 main start` | Start/stop/restart a cluster | `systemctl start postgresql-16` |

**pg_lsclusters** output:

```
Ver Cluster Port Status Owner    Data directory                  Log file
16  main    5432 online postgres /var/lib/postgresql/16/main      /var/log/postgresql/postgresql-16-main.log
15  main    5433 online postgres /var/lib/postgresql/15/main      /var/log/postgresql/postgresql-15-main.log
```

**pg_createcluster** does in one command what takes 5-6 steps on CentOS: creates data directory, runs `initdb`, sets port, creates systemd unit, configures log rotation.

### Package naming differences

| Purpose | CentOS/RHEL | Ubuntu/Debian |
|---------|-------------|---------------|
| Server | `postgresql16-server` | `postgresql-16` |
| Client | `postgresql16` | `postgresql-client-16` |
| Contrib | `postgresql16-contrib` | `postgresql-16-contrib` |
| Dev headers | `postgresql16-devel` | `postgresql-server-dev-16` |
| Cluster tools | (none) | `postgresql-common` |

### Service management comparison

| Task | CentOS/RHEL | Ubuntu/Debian |
|------|-------------|---------------|
| Start | `systemctl start postgresql-16` | `pg_ctlcluster 16 main start` |
| Stop | `systemctl stop postgresql-16` | `pg_ctlcluster 16 main stop` |
| Reload | `systemctl reload postgresql-16` | `pg_ctlcluster 16 main reload` |
| Status | `systemctl status postgresql-16` | `pg_lsclusters` |
| Service name | `postgresql-16` | `postgresql@16-main` (template unit) |
| Auto-init? | No (manual `initdb`) | Yes (automatic) |

> **Concept:** Ubuntu uses systemd template units (`postgresql@.service`) where the instance name encodes both version and cluster name (e.g., `16-main`). This lets you run multiple clusters of the same version with separate services.

### The universal commands

No matter which OS you are on, these always work:

```sql
SHOW config_file;
SHOW data_directory;
SHOW hba_file;
```

When you SSH into an unfamiliar server, connect to PostgreSQL and run `SHOW config_file;` first.

### When you will encounter each platform

| Scenario | Likely Platform |
|----------|----------------|
| AWS EC2, enterprise, legacy | CentOS/RHEL |
| Cloud providers (DigitalOcean, Linode) | Ubuntu |
| Docker containers | Debian (official postgres image) |
| Managed services (RDS, Cloud SQL) | Managed by provider |
| Kubernetes operators | Debian-based images |

> **Concept:** The official PostgreSQL Docker image is Debian-based, so the config separation pattern (`/etc/postgresql/` vs `/var/lib/postgresql/`) is what you will see inside containers.

For hands-on practice with Ubuntu commands, see USE Exercise 06: Cross-Platform Cluster Management.

# How an EPAS Instance Is Put Together

Before you manage something, you should be able to picture it. This document is the
mental model of a running EDB Postgres Advanced Server instance - the processes, the
memory, the files, and the two doors you connect through. Everything you do in the
BUILD guides is one of these pieces.

If you come from Oracle, keep your Oracle picture handy - the parts map over almost
one to one, with different names. We call those out as we go.

---

## 1. One instance is a family of processes, not one big program

When you start `edb-as-16`, you are not starting a single program. You are starting a
**postmaster** - a supervisor process - which then launches a family of helper
processes that each own one job. You saw this in Module 01 with `ps -ef | grep edb`.

The postmaster (its program is `edb-postgres`) is the parent. It:

- owns the shared memory,
- listens on the network port for new connections,
- and starts a dedicated **backend** process for each client that connects.

Under it run the background workers, always present:

- **checkpointer** - periodically writes ("checkpoints") dirty data from memory out to
  the data files, so recovery after a crash is fast and bounded.
- **background writer** - trickles dirty pages to disk between checkpoints so the
  checkpoint itself is not a giant stall.
- **walwriter** - flushes the Write-Ahead Log (WAL) to disk. WAL is how EPAS makes your
  committed transactions durable: the change is written to WAL *before* it is
  considered committed.
- **autovacuum launcher** - watches your tables and starts cleanup workers when dead
  rows (from updates and deletes) build up.
- **logger** - collects the server's log output into files (when logging is on).

> **Oracle bridge:** the postmaster is your listener + `pmon`-style supervisor rolled
> together. checkpointer is `CKPT`, background writer + walwriter together do the work
> of `DBWn` and `LGWR`, autovacuum is a bit like the automatic segment/space and stats
> maintenance jobs. The big difference: **one postmaster owns one cluster**, and one
> server usually runs exactly one postmaster.

Why this matters: when something is wrong, "the database" is really "one of these
processes." Knowing the cast tells you where to look - a stuck checkpoint, WAL not
flushing, a backend hung on a lock.

---

## 2. Shared memory: the part they all cooperate through

All those processes cooperate through a single block of **shared memory** the
postmaster allocates at startup. The biggest piece is **`shared_buffers`** - the cache
of table and index pages. When a query needs a page, EPAS looks in `shared_buffers`
first; a hit avoids a disk read.

Because this block is sized and mapped **once, at startup**, you cannot resize it while
the server runs. That is why `shared_buffers` is a *restart-only* parameter - a fact
you will meet head-on in BUILD 03. It is the single most common "why won't my change
take effect?" surprise for new EPAS DBAs.

> **Oracle bridge:** `shared_buffers` is your buffer cache (the `db_cache_size` part of
> the SGA). And just like resizing certain SGA components, some changes need a bounce.

---

## 3. The data directory (PGDATA) is the instance on disk

Everything an instance owns lives under one directory - the **data directory**, or
**PGDATA**. On this server it is `/var/lib/edb/as16/data`. Inside it:

- `base/` - the actual table and index data, one subdirectory per database.
- `global/` - cluster-wide catalog (roles, tablespaces).
- `pg_wal/` - the Write-Ahead Log files.
- `log/` - the server's log files (where you go first when something breaks).
- `postgresql.conf`, `postgresql.auto.conf`, `pg_hba.conf`, `pg_ident.conf` - the
  configuration (next section).
- `postmaster.pid` - present only while the server runs; how systemd and other tools
  know it is up.

> **Oracle bridge:** PGDATA is the closest thing to `ORACLE_BASE/oradata` *for one
> instance* - except EPAS keeps data files, WAL (redo), control information, and config
> all under this one tree, rather than spread across `oradata`, `fast_recovery_area`,
> and `dbs`.

---

## 4. Configuration: three files, two ways to change them

An instance reads its settings from files in PGDATA:

- **`postgresql.conf`** - the main settings file. Human-edited.
- **`postgresql.auto.conf`** - the same kind of settings, but written *for* you by the
  `ALTER SYSTEM` SQL command. Its first two lines warn you not to edit it by hand,
  because `ALTER SYSTEM` will overwrite it.
- **`pg_hba.conf`** - **h**ost-**b**ased **a**uthentication: who may connect, from
  where, to which database, and how they must prove it (peer, scram-sha-256, etc.).

There are two honest ways to change a parameter: edit `postgresql.conf` in an editor,
or run `ALTER SYSTEM SET ...` in SQL (which lands in `postgresql.auto.conf`). Most
teams prefer `ALTER SYSTEM` for run-time settings because it is auditable and less
error-prone than hand-editing.

### Reload vs restart - the distinction that runs production

Not every setting can change the same way. Each parameter has a **context** (visible in
the `pg_settings` view) that tells you how it takes effect:

- **`postmaster`** - can only be set at startup. Changing it needs a **restart**
  (`shared_buffers`, `port`, `max_connections`).
- **`sighup`** - the running server re-reads it on a **reload** (a SIGHUP signal). No
  downtime.
- **`superuser`** / **`user`** - can change on a reload and even per session
  (`work_mem`, `log_min_duration_statement`).

A **reload** (`systemctl reload edb-as-16`) tells the running postmaster to re-read its
config without dropping a single connection. A **restart**
(`systemctl restart edb-as-16`) stops and starts the instance - every client is
disconnected. The professional habit: check a parameter's `context` *before* you change
it, so you know whether you need a maintenance window or can do it live.

> **Oracle bridge:** a reload is `ALTER SYSTEM ... SCOPE=BOTH` for a dynamic parameter -
> live. A `postmaster` parameter is a static one you set `SCOPE=SPFILE` and then bounce
> the instance to pick up. EPAS's `pg_settings.pending_restart = true` is your signal,
> the way `V$PARAMETER.ISSYS_MODIFIABLE`/`ISMODIFIED` hints at it in Oracle.

---

## 5. The two doors: edb-psql and edbplus

You reach the database through one of two command-line clients:

- **`edb-psql`** - the PostgreSQL-style client. Terse, scriptable, full of `\`
  meta-commands (`\l`, `\d`, `\conninfo`). This is where a Postgres DBA lives.
- **`edbplus`** - EDB's re-implementation of Oracle's **SQL\*Plus**. Same `SET`
  commands, same `@script.sql`, same `EXIT`, same `dual` table. It exists so an Oracle
  team can be productive on day one with muscle memory intact.

A subtlety you will hit in BUILD 02: `edb-psql` run locally as the `enterprisedb` OS
user connects over a Unix socket and is trusted automatically (peer authentication).
`edbplus` is a Java tool that connects over **TCP**, so peer auth does not apply - it
needs a real password and a `pg_hba.conf` rule that accepts one (`scram-sha-256`). Same
database, different door, different lock.

Remember the three EPAS constants that differ from community PostgreSQL: the port is
**5444** (not 5432), the bootstrap superuser is **`enterprisedb`** (not `postgres`),
and the default database is **`edb`**.

---

## Where this leaves you

You can now picture a running instance: a postmaster and its background family, sharing
one block of memory, backed by one data directory, configured by three files with a
reload-or-restart rule, reachable through two clients. Every task in the BUILD guides -
and every failure in the SURVIVE scenarios - is one of these pieces behaving, or
misbehaving. Keep this map in mind as you go.

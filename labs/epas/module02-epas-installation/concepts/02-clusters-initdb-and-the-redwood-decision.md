---
layout: default
title: "Concepts 02 - Clusters, initdb, and the Redwood Decision"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 2
locked: "no"
---

# Concepts 02: Clusters, initdb, and the Redwood Decision

## What You Are Doing

You are learning what actually gets created when an EPAS server comes to life: the "cluster," the data directory, the four default databases, and the systemd service. Most importantly, you are learning about the one decision that gets made at creation time and can never be changed afterward - Redwood mode, the thing that makes EPAS speak Oracle.

**Mode:** Theory only - read on your laptop.

**Time:** 60 min.

**Prerequisite:** Concepts 01 (EDB Repos and Packaging).

---

## "Cluster" Does Not Mean What You Think It Means

First terminology landmine. In Postgres/EPAS, a **database cluster** has nothing to do with RAC, nothing to do with multiple servers, nothing to do with high availability. A cluster is simply:

> One postmaster process + one data directory (PGDATA) + the collection of databases living inside it.

One server can even run several independent clusters (each with its own port and PGDATA), though in production you almost never do.

Map it to the Oracle mental model carefully, because it is close to CDB thinking but not identical:

| Oracle concept | EPAS equivalent | Caution |
|:---------------|:----------------|:--------|
| Instance (SGA + background processes) | The running postmaster and its children | One postmaster per cluster, always |
| Database (datafiles on disk) | The cluster's PGDATA directory | Instance and storage are 1:1 - no RAC-style many instances, one database |
| CDB (container database) | The cluster | Both are "one set of processes hosting many databases" |
| PDB (pluggable database) | A database inside the cluster (`edb`, `cardauth`, ...) | The big difference: you cannot unplug/plug a Postgres database, and clients connect *directly* to a named database, there is no CDB root to log into |
| SID / service name | The database name in the connection string | Connecting without naming a database is the #1 rookie error - more below |

The CDB analogy carries you 80% of the way: shared memory, shared WAL, shared background processes, many logical databases inside. The 20% that differs: databases in a cluster share one transaction log and one set of physical processes but are logically walled off from each other - a session connected to database `edb` cannot query tables in database `cardauth` without something like a foreign data wrapper (think database link). There is no `ALTER SESSION SET CONTAINER`. You disconnect and reconnect.

So when a Postgres person says "I restarted the cluster," they mean "I restarted the instance." When they say "I created a database," that is a lightweight in-cluster operation closer to creating a PDB than running DBCA.

---

## initdb: DBCA in One Second

In Oracle, creating a database is an event: DBCA, template selection, character sets, redo sizing, twenty minutes of progress bars. In EPAS, the equivalent is `initdb`, and EDB wraps it in a helper script. The whole thing runs in about one second.

For reference (you will run this in Build 01), on **epas-lab**, as **ec2-user**:

```bash
sudo /usr/edb/as16/bin/edb-as-16-setup initdb
```

What this does: `edb-as-16-setup` is EDB's wrapper around the raw `initdb` binary. It creates the data directory at the default location, sets ownership to `enterprisedb`, and initializes a brand-new cluster with EDB's defaults - including Redwood mode (the entire next section).

Expected output (yours will differ):

```
Initializing database ... OK
```

That single OK line is your entire DBCA run. Also note: `initdb` refuses to run against a directory that already has a cluster in it - a second run fails with `Data directory is not empty!`. It will never silently destroy an existing cluster, which is exactly the behavior you want from a tool this powerful.

### Walking the data directory

Here is the real PGDATA listing from our validated server, `/var/lib/edb/as16/data` right after initdb:

Expected output (yours will differ):

```
base
global
log
pg_hba.conf
pg_wal
pg_xact
postgresql.auto.conf
postgresql.conf
PG_VERSION
...
```

(The full listing has about 22 entries - `pg_commit_ts`, `pg_multixact`, `pg_replslot`, `pg_tblspc`, and friends. The table below covers the ones that matter daily.)

Map each to what you already know:

| PGDATA entry | What it is | Oracle mapping |
|:-------------|:-----------|:---------------|
| `base/` | The actual data files - one subdirectory per database, files named by OID | Datafiles for all your tablespaces, USERS/SYSTEM alike |
| `global/` | Cluster-wide catalogs (roles, tablespaces) + `pg_control`, the tiny binary file recording cluster state and checkpoint info | Data dictionary shared across PDBs; `pg_control` is your controlfile |
| `pg_wal/` | Write-ahead log segments, 16 MB each | Redo logs + (before archiving) archive logs |
| `pg_xact/` | Transaction commit status (committed/aborted per XID) | Roughly the transaction table in UNDO - the "did it commit?" record |
| `postgresql.conf` | The main config file, plain text, ~800 lines of commented defaults | init.ora / SPFILE (human-readable, editable with vi) |
| `postgresql.auto.conf` | Settings applied via `ALTER SYSTEM`, overrides postgresql.conf | The SPFILE half of the story - persisted dynamic changes |
| `pg_hba.conf` | Host-based authentication: who may connect, from where, to which database, with which auth method | sqlnet.ora + listener.ora access control, roughly - the network admission layer |
| `pg_ident.conf` | OS-user to DB-user mapping for certain auth methods | OS authentication mapping |
| `log/` | Server log files (EDB's packaging points logs here) | alert log + trace directory |
| `PG_VERSION` | Text file containing `16` | Marks the on-disk format's major version - checked at startup |

Two observations a senior Oracle DBA should make immediately:

1. **Everything lives under one directory.** Controlfile-equivalent, redo-equivalent, datafiles, configs, logs - all under PGDATA. Backup that directory (correctly - Module 05) and you have the whole cluster. There is no scattered `+DATA`/`+FRA`/`$ORACLE_HOME/dbs` sprawl.
2. **Everything important is plain text.** postgresql.conf and pg_hba.conf are files you read and edit with vi. No `ALTER SYSTEM ... SCOPE=SPFILE` binary indirection required (though `ALTER SYSTEM` exists and writes to postgresql.auto.conf).

Also notice what is *missing*: there is no listener. The postmaster itself listens on the TCP port. No listener.ora, no `lsnrctl`, no TNS. `pg_hba.conf` plus the `listen_addresses` parameter cover everything the listener stack did.

---

## The Redwood Decision: The One-Shot Choice

Now the most important concept in this module.

EPAS can initialize a cluster in one of two personality modes:

- **Redwood mode** (Oracle-compatible): the cluster behaves like Oracle wherever the two disagree
- **PostgreSQL mode**: the cluster behaves like stock community PostgreSQL

"Redwood" is EDB's internal codename for Oracle compatibility - Oracle's headquarters was at Redwood Shores, California. The joke stuck and became a config surface: `edb_redwood_date`, `edb_redwood_strings`, and friends.

Here is what makes this a *decision* and not a setting: **the mode is chosen at initdb time and baked into the cluster.** The EDB wrapper `edb-as-16-setup initdb` defaults to Redwood mode ON. If you wanted PostgreSQL mode, you would pass `--no-redwood-compat` at initdb time. There is no ALTER, no parameter flip, no restart that converts an existing cluster from one mode to the other. To change your mind, you re-run initdb on an empty directory and reload every byte of data. On a production CardAuth cluster, that is a full migration project.

Why can't it be flipped? Because Redwood mode changes what initdb *creates*: system catalogs get Oracle dictionary views (USER_TABLES, ALL_OBJECTS, DBA_ views), the DBMS_ and UTL_ built-in packages are installed, `DUAL` exists, and default behaviors (date output format, string semantics) are wired in. That is structural, not a runtime knob.

This should feel familiar: it is the same class of decision as Oracle's database character set, or PostgreSQL data checksums from Module 01. Get it right at creation, because "later" means "rebuild."

### What Redwood mode actually gives you

All of the following are real outputs from our validated 16.14 cluster, fresh from a default initdb. First, the Oracle DBA's oldest friend:

```sql
SELECT * FROM dual;
```

Expected output (yours will differ):

```
 dummy 
-------
 X
(1 row)
```

`DUAL` exists, with its one row and its `X`. Community PostgreSQL has no DUAL (you just write `SELECT 1;` with no FROM clause). Next, sysdate and the date format:

```sql
SELECT sysdate FROM dual;
```

Expected output (yours will differ):

```
      sysdate       
--------------------
 07-JUL-26 01:48:18
```

Two Oracle-isms in one: `sysdate` works at all, and the output is `DD-MON-YY` format because the cluster ships with `edb_redwood_date = on`. A stock PostgreSQL server would have neither - dates print ISO style (`2026-07-07`). The DBMS_ packages are there too:

```sql
EXEC dbms_output.put_line('Hello from EPAS, Linuel');
```

Expected output (yours will differ):

```
Hello from EPAS, Linuel

EDB-SPL Procedure successfully completed
```

Note the tell: `EDB-SPL Procedure successfully completed` instead of `PL/SQL procedure successfully completed`. EDB-SPL is EPAS's PL/SQL-compatible language from Module 01. `NVL` and `DECODE` work as native functions, and the Oracle dictionary views are populated - `SELECT count(*) FROM user_tables;` runs and returns a count, exactly as it would in SQL*Plus.

The operational takeaway for Mastercard: any cluster that will host code migrated from Oracle **must** be initialized in Redwood mode. If someone hands you an EPAS cluster and the CardAuth PL/SQL fails on DUAL or sysdate, your very first check is whether the cluster was initialized in the right mode - and if it was not, the fix is a rebuild, not a parameter change.

---

## The Four Databases, and Why edb Is Your Home

Right after initdb, the cluster contains four databases:

| Database | Purpose | Oracle analogy |
|:---------|:--------|:---------------|
| `edb` | The Oracle-flavored default database. Redwood objects (DUAL, DBMS_ packages, dictionary views) live here. **This is where you work.** | The PDB your applications actually use |
| `postgres` | Conventional default/maintenance database, present in every Postgres cluster. Tools and scripts often connect here "just to have somewhere to land." | A utility PDB - somewhere to log in when you do not care which database |
| `template1` | The template cloned by `CREATE DATABASE`. Objects you add here appear in every future database. | A PDB seed you are allowed to customize |
| `template0` | The pristine, never-modified template. Used to create databases with non-default encodings, and as the known-clean fallback. | The read-only seed - the untouched reference copy |

Why does `edb` matter so much? Because of a psql behavior that produced the most instructive failure in our entire validation run. psql, when you do not tell it a database name, assumes the database is named after your OS user. Log in as `enterprisedb` and run a bare psql command:

Expected output (yours will differ):

```
psql: error: connection to server on socket "/tmp/.s.PGSQL.5444" failed: FATAL:  database "enterprisedb" does not exist
```

The server is running fine. The connection reached it. But psql asked for a database named `enterprisedb`, and no such database exists. On community PostgreSQL this trap is invisible, because the OS user is `postgres` and a database named `postgres` exists - the defaults happen to line up. On EPAS the OS user is `enterprisedb` and the defaults do NOT line up, so every EPAS DBA hits this error in week one. The fix is simply to name your database: `-d edb`.

Burn it in: **on EPAS, `edb` is your SID.** It is the database in your connection strings, your monitoring checks, and your muscle memory.

---

## Service and Directory Anatomy

### The systemd unit: edb-as-16

The cluster runs as a systemd service named **edb-as-16**. This replaces the whole Oracle startup stack - no `dbstart`, no oratab, no srvctl:

On **epas-lab**, as **ec2-user** (systemctl is always run with sudo as ec2-user - never switch to enterprisedb for this):

```bash
sudo systemctl status edb-as-16
```

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Loaded: loaded (/usr/lib/systemd/system/edb-as-16.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-07-07 01:48:17 UTC; 48ms ago
    Process: 10898 ExecStartPre=/usr/edb/as16/bin/edb-as-16-check-db-dir ${PGDATA} (code=exited, status=0/SUCCESS)
   Main PID: 10903 (edb-postgres)
...
```

Read the details: the unit runs a pre-check (`edb-as-16-check-db-dir`) validating PGDATA before start, and the main PID is `edb-postgres` - the postmaster from Module 01, started with `-D /var/lib/edb/as16/data`.

Now the gotcha that cost us real time during validation. The service name is `edb-as-16` with a hyphen between "as" and "16". The *package* name is `edb-as16` with no hyphen there. Type the package spelling at systemctl and you get:

```
Unit edb-as16.service could not be found.
```

Package: `edb-as16-server`. Binaries: `/usr/edb/as16/`. Service: `edb-as-16`. Three spellings, one hyphen of difference. You will hit this in SURVIVE.

### ORACLE_HOME vs ORACLE_BASE, EPAS edition

Two directory trees, cleanly separated, and the separation maps directly onto instincts you already have:

| Path | Contains | Oracle mapping | Owned by |
|:-----|:---------|:---------------|:---------|
| `/usr/edb/as16/` | Binaries (`bin/`), libraries, share files. Read-only at runtime, replaced by `dnf update`. | ORACLE_HOME | root (installed by RPM) |
| `/var/lib/edb/as16/data/` | PGDATA - all your data, WAL, configs, logs. The precious part. | ORACLE_BASE datafile area (plus controlfile, redo, and pfile all in one) | enterprisedb |

Everything under `/usr/edb` is disposable - reinstalling packages recreates it exactly. Everything under `/var/lib/edb/as16/data` is irreplaceable - that is what backups protect. Same discipline as never confusing $ORACLE_HOME with your datafile mounts, and it drives real decisions: PGDATA goes on your fast, monitored, backed-up volume; the binaries can live on the root disk.

Log files, note, live at `/var/lib/edb/as16/data/log/` - *inside* PGDATA. First log from our validated server: `enterprisedb-2026-07-07_014817.log`. That is your alert log equivalent, and it is the first file you open when anything misbehaves.

### Port 5444: the non-default listener port story

Community PostgreSQL listens on **5432**. EPAS deliberately compiled its default to **5444**. In postgresql.conf you will find:

```
#port = 5444				# (change requires restart)
```

The line is commented out - and this is a postgresql.conf idiom worth learning now: a commented parameter shows the *compiled-in default*, which is active. Nothing needs uncommenting for the server to listen on 5444; the real server proves it, listening on `0.0.0.0:5444`.

Why did EDB pick a different port? So EPAS and community PostgreSQL can coexist on one host without a port fight, and so it is always unambiguous which engine you are talking to. Think of it exactly like a shop that runs its listener on 1522 instead of 1521: nothing is wrong, but every connection string, firewall rule, monitoring probe, and colleague's assumption must know about it.

The subtle part: EPAS's own client tools (`edb-psql`, and the `psql` in `/usr/edb/as16/bin`) also default to 5444, so on the server itself everything just works. But any *stock* PostgreSQL client - a developer's laptop psql, a JDBC driver with defaults, a random monitoring agent - will try 5432, get connection refused, and someone will file a ticket saying "the database is down." It is not down. It is on 5444. This exact confusion is a SURVIVE scenario in this module.

---

## Reading Checkpoint

Answer these from memory before starting Build 01. If any answer is shaky, re-read that section.

1. A colleague says "we run a three-node Postgres cluster." A Postgres purist says "this server runs one cluster." Explain both usages, and state precisely what a cluster is in EPAS terms (processes + directory + databases).

2. You inherit an EPAS server and CardAuth's migrated PL/SQL fails with errors on `DUAL` and `sysdate`. What single initdb-time decision do you suspect, how do you confirm it, and why can't you fix it with `ALTER SYSTEM`?

3. Map these PGDATA entries to their closest Oracle concepts: `global/pg_control`, `pg_wal/`, `base/`, `pg_hba.conf`, `postgresql.auto.conf`.

4. As `enterprisedb`, you run `psql -p 5444 -c "SELECT 1;"` and get `FATAL: database "enterprisedb" does not exist`. Is the server down? What is psql actually doing, and what is the fix? Why does this never happen on community PostgreSQL?

5. Spell, exactly: the package you dnf-install, the directory holding the binaries, and the systemd service name. Which one has the extra hyphen?

6. A developer's laptop psql cannot connect to your new EPAS server, but `edb-psql` on the server connects fine. Both the security group and pg_hba.conf are correct. What is the most likely cause, and what is the Oracle analogy you would use to explain it to the team?

Next: Build 01, where you run every one of these commands yourself on your own server - repo setup, install, initdb, first login, and the Redwood proofs.

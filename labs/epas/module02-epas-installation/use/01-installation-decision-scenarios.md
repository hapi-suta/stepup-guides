---
layout: default
title: "Use 01 - Installation Decision Scenarios"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 6
locked: "no"
---

# Use 01: Installation Decision Scenarios

## What You Are Doing

You are working through five installation decision scenarios pulled from real situations on the CardAuth platform at Mastercard. Each scenario gives you evidence - command output, architect proposals, emails - and asks you to make the call a senior DBA would make. You write your answers first, then check your reasoning against the Answer Discussion.

**Mode:** Written analysis - no server changes needed.

**Time:** 60 minutes.

**Prerequisite:** Build 01 and Build 02 complete.

---

## Scenario 1: One Cluster or Two?

The CardAuth team is building a new reporting service. The developers wrote and tested it against **community PostgreSQL 16** - standard date formats, standard empty-string behavior, no Oracle anything. The architect wants to deploy it onto your existing EPAS server, which already hosts Oracle-migrated CardAuth schemas.

Here is what your existing cluster looks like. This is real output from an EPAS 16 server initialized with the default `edb-as-16-setup initdb`:

```
edb=# SELECT sysdate FROM dual;
      sysdate
--------------------
 07-JUL-26 01:48:18
(1 row)

edb=# SHOW edb_redwood_date;
 edb_redwood_date
------------------
 on
(1 row)
```

The architect's position: "It is all PostgreSQL under the hood. Just create a new database in the existing cluster and point the reporting service at it."

### Questions

1. What does the `sysdate` output and `edb_redwood_date = on` tell you about how this cluster was initialized, and at what point in the cluster's life was that decided?
2. Name at least two concrete ways a Redwood-mode cluster could break an application written and tested against community PostgreSQL.
3. Can you "turn off" Redwood mode for just the new database inside the existing cluster? What is safe to toggle and what is not?
4. What is the deployment you would actually propose, and what changes on the server to make it work?

<details markdown="block">
<summary>Answer Discussion</summary>

**1. Redwood mode is an initdb-time decision.**

`edb-as-16-setup initdb` creates the cluster in Redwood (Oracle-compatible) mode by default. That is why `dual` exists, why `sysdate` returns `07-JUL-26 01:48:18` in Oracle date format, and why `edb_redwood_date` is on. The Oracle compatibility catalog objects (dual, user_tables and the other dictionary views, the DBMS_ packages) are installed **when the cluster is initialized**. In Oracle terms: this is a CREATE DATABASE-time decision, like choosing your character set. You do not casually change it later.

**2. How Redwood mode breaks a community-PG application.**

- **Date formats.** `edb_redwood_date = on` makes DATE behave like Oracle DATE (includes time, displays as `07-JUL-26`). An app parsing `2026-07-07` ISO dates gets a surprise.
- **Empty strings.** With Redwood string behavior, `''` is treated as NULL, Oracle-style. Community PG treats `''` and NULL as different values. An app that stores empty strings and later tests `WHERE col = ''` silently changes behavior.
- **Name collisions.** The cluster ships Oracle dictionary views and packages. If the reporting app creates its own table or view named `dual` or `user_tables`, or uses identifiers that collide with EDB-SPL keywords, it fails in ways it never did in dev.

**3. Per-database toggling gets you partway, not all the way.**

Some Redwood behaviors are GUCs you can set per database (`ALTER DATABASE reporting SET edb_redwood_date = off;` and similar). But the compatibility objects and the Oracle-flavored catalog were baked in at initdb. You cannot initdb a single database - initdb operates on the whole cluster. Running a "mostly community" database inside a Redwood cluster means every future incident starts with "wait, which behaviors are Oracle here?" That ambiguity is exactly what you do not want at 3am.

**4. The right call: a second cluster in no-Redwood mode on another port.**

The EPAS binaries in `/usr/edb/as16/bin` can serve multiple clusters. Initialize a second cluster with `initdb --no-redwood-compat` pointed at its own data directory, give it its own port (for example 5445, since the Redwood cluster owns 5444), and its own systemd unit. Now:

- The Oracle-migrated schemas keep their Redwood cluster untouched.
- The reporting service gets genuine community-PostgreSQL semantics.
- Each cluster restarts, tunes, and fails independently.

Cost: a second set of shared_buffers and background processes on the same host. That is a memory-budget conversation (Module 01, Step 2), not a blocker. Tell the architect: same binaries, same server, two clusters - because Redwood is decided at initdb, not at CREATE DATABASE.

</details>

---

## Scenario 2: The Patching Cadence Question

Email from the Mastercard security team:

> Subject: EPAS patch compliance - CardAuth
>
> For Oracle we receive quarterly Release Updates (RUs) and apply them within 30 days. We need the equivalent commitment for the new EPAS 16 servers. Please document: what the vendor ships, how you apply it, and what downtime each patch type requires.

Here is what is installed today, real output from the CardAuth EPAS server:

```
$ rpm -qa | grep edb-as16 | sort

edb-as16-server-16.14.0-1.el9.x86_64
edb-as16-server-client-16.14.0-1.el9.x86_64
edb-as16-server-contrib-16.14.0-1.el9.x86_64
edb-as16-server-core-16.14.0-1.el9.x86_64
edb-as16-server-libs-16.14.0-1.el9.x86_64
...
```

### Questions

1. In the version string `16.14.0`, what do the `16` and the `14` each mean? What is the community/EDB equivalent of an Oracle RU?
2. When 16.15 ships, what is the actual apply procedure on this server, and what downtime does it require? Does it touch the data directory format?
3. How is going from 16 to 17 fundamentally different from going from 16.14 to 16.15?
4. Write the two-line patching policy you would send back to the security team.

<details markdown="block">
<summary>Answer Discussion</summary>

**1. Major version 16, minor release 14.**

`16` is the major version - the on-disk format, the feature set, the catalog. `14` is the minor release number: a cumulative roll-up of bug fixes and security fixes for major version 16. PostgreSQL ships minor releases on a quarterly schedule (plus out-of-band releases for critical security issues), and EDB packages them for EPAS shortly after. So the honest answer to security: **the minor release IS the RU equivalent** - quarterly cadence, cumulative, fixes-only, no behavior changes.

Oracle bridge: minor release ~ RU applied with OPatch. The difference is the delivery mechanism - there is no OPatch. The fix arrives as updated rpms in the EDB dnf repository you configured in Build 01.

**2. Applying 16.14 to 16.15: dnf update plus one restart.**

On **epas-lab**, as **ec2-user**:

```bash
sudo dnf update -y edb-as16-\*
```

This updates every installed `edb-as16-*` package (server, client, contrib, libs and the rest) to the newest build in the EDB repo. The `-y` answers yes to the transaction prompt. The new binaries land in `/usr/edb/as16/bin`, but the **running** postmaster is still executing the old code, so:

```bash
sudo systemctl restart edb-as-16
```

Downtime is the restart: seconds to a couple of minutes depending on checkpoint activity. Minor releases **never change the data directory format** - no initdb, no migration, no dump and restore. Stop, swap binaries (dnf already did), start.

**3. 16 to 17 is a major upgrade, not a patch.**

Major versions change the on-disk catalog and sometimes the data format. You cannot point the version 17 binaries at a version 16 data directory - the equivalent of trying to open an Oracle 19c database with 12c binaries. A major upgrade is a project: install the 17 packages alongside 16, run `pg_upgrade` (or dump and restore), re-test the application, plan a rollback. Budget it like an Oracle major release upgrade, not like an RU.

**4. The policy statement.**

"EPAS 16 minor releases (16.14 to 16.15, etc.) ship quarterly and are applied via `dnf update edb-as16-\*` plus a service restart within 30 days of release; downtime per patch is under 5 minutes. Major version upgrades (16 to 17) are separate planned projects using pg_upgrade and are scheduled independently."

</details>

---

## Scenario 3: The Port 5444 Incident

Ticket from the CardAuth application team, priority high:

> Our new fraud-scoring service cannot reach the database. JDBC URL is `jdbc:postgresql://epas-lab:5432/edb`. Error: `Connection refused`. The DBA team said the database is up. Please advise - we go to integration testing tomorrow.

You check the server yourself. On **epas-lab**, as **ec2-user**:

```bash
sudo ss -tlnp | grep 544
```

`ss` lists sockets; `-t` TCP only, `-l` listening only, `-n` numeric ports, `-p` show the owning process. Real output:

```
Expected output (yours will differ):
LISTEN 0      200          0.0.0.0:5444      0.0.0.0:*
LISTEN 0      200             [::]:5444         [::]:*
```

And in `postgresql.conf`:

```
#port = 5444				# (change requires restart)
```

### Questions

1. The database is healthy and listening. Why does the app get `Connection refused` rather than an authentication or database error?
2. The `port` line in postgresql.conf is commented out, yet the server listens on 5444. Explain exactly why.
3. You have two fix options: change the JDBC URL to 5444, or change the server's port to 5432. Walk the cost of each - including what the comment `(change requires restart)` means for the second option.
4. Which do you choose for CardAuth, and what one-line standard do you add to the team wiki so this never happens again?

<details markdown="block">
<summary>Answer Discussion</summary>

**1. Nothing is listening on 5432.**

`Connection refused` is the OS-level TCP answer: the SYN arrived at port 5432 and no process owns that port, so the kernel rejected it. The request never reached EPAS at all - which is why there is no PostgreSQL error message, no pg_hba.conf rejection, no "database does not exist." When you see `Connection refused`, stop thinking about database configuration and start thinking about port, host, and firewall.

**2. Commented lines show the compiled-in default.**

In postgresql.conf, a `#`-commented parameter line documents the default that the parameter takes when you do not set it. Community PostgreSQL is compiled with a default port of 5432; **EPAS is compiled with a default of 5444**. So `#port = 5444` means: "you have not set the port, and the built-in default this server will use is 5444." Uncommenting it and leaving 5444 would change nothing. Oracle bridge: 5444 is your 1521 - the listener port everything must agree on.

**3. Cost of each fix.**

- **Change the app URL to 5444.** One line in the app config, no database downtime, and the server stays on the EPAS default that every EPAS tool already assumes (EPAS's own psql defaults to 5444 too). Cost: the app team redeploys config.
- **Change the server to 5432.** Edit postgresql.conf (`port = 5432`, uncommented), then restart - the inline comment `(change requires restart)` is literal, `port` cannot be reloaded live, so you take an outage for every connected session. You also now run a non-standard EPAS server: every EPAS client tool on the box starts defaulting to the wrong port, every runbook that says 5444 is now wrong for this one server, and if community PostgreSQL is ever installed alongside, you collide on 5432.

**4. Fix the app, standardize the documentation.**

Change the JDBC URL to 5444. It is the zero-downtime fix and it keeps the server on the platform default. Wiki line: "EPAS listens on **5444**, not 5432 - every connection string, firewall rule, and monitoring check for CardAuth EPAS servers uses 5444." The root cause here was not a typo; it was an assumption imported from community PostgreSQL. Kill the assumption, not the default.

</details>

---

## Scenario 4: The Disk Layout Review

An infrastructure architect sends you the build sheet for the production CardAuth EPAS servers:

> Single 100 GB root volume. PGDATA stays at the package default `/var/lib/edb/as16/data` on `/`. Keeps the build simple - one volume to size, one volume to snapshot.

Before you respond, you look at what actually lives inside a freshly initialized PGDATA. Real listing from the lab server:

```
$ ls /var/lib/edb/as16/data

base
global
log
pg_commit_ts
pg_hba.conf
pg_ident.conf
pg_logical
pg_multixact
pg_notify
pg_replslot
pg_tblspc
pg_wal
pg_xact
postgresql.auto.conf
postgresql.conf
...
```

### Questions

1. Which three things under (or logically belonging to) PGDATA grow without a fixed bound in production, and what drives each one's growth?
2. What happens to the database - and to the whole server - when the root filesystem hits 100%? Why is "database and OS on the same volume" the specific problem?
3. As an Oracle DBA, how would you have laid out an Oracle server, and what is the equivalent layout here? Use the SUTA `/opt/pgsql` pattern (data, wal, log, backup) as your reference.
4. Write your reply to the architect: what you accept, what you reject, and the layout you require.

<details markdown="block">
<summary>Answer Discussion</summary>

**1. The three growers.**

- **`base/`** - the heap and index files, one subdirectory per database. Grows with data volume and with bloat (dead tuples that VACUUM has not reclaimed). This is your steady, expected growth.
- **`pg_wal/`** - WAL segments, 16 MB each. Normally cycles within a few GB, but a stuck replication slot or a failing archive_command makes it grow **unbounded and fast**. You saw a 127 GB pg_wal in Module 01, Step 3 - that failure mode is common, not exotic.
- **`log/`** - server logs (the lab server was already writing `enterprisedb-2026-07-07_014817.log` minutes after initdb). Growth depends on logging settings; `log_statement = all` on a high-TPS system generates gigabytes per day.

Backups are the fourth grower if they land on the same volume - which is exactly what a "one volume" design invites.

**2. Root at 100% is a double outage.**

When PostgreSQL cannot write WAL, it does not degrade politely - it PANICs and shuts down, because continuing without durable WAL would risk corruption. That alone is a database outage. But because PGDATA is on `/`, the same event takes out the OS: sshd cannot write, systemd journals cannot write, you may not even be able to log in to fix it. Separate volumes turn "runaway WAL" into a database incident. A shared root volume turns it into a server incident where your recovery tools are also broken.

**3. The Oracle instinct is correct here.**

No Oracle DBA at Mastercard would put datafiles, redo, archive logs, and RMAN backups on the OS volume - they get separate mounts precisely because redo and archive destinations filling up is a known failure mode. Same instinct, new names. The SUTA layout:

| Mount | Holds | Oracle equivalent thinking |
|:------|:------|:---------------------------|
| `/opt/pgsql/data` | PGDATA (base/, global/, config) | Datafile diskgroup/mount |
| `/opt/pgsql/wal` | pg_wal (symlinked or initdb --waldir) | Online redo mount |
| `/opt/pgsql/log` | Server logs | Diag/adump destinations |
| `/opt/pgsql/backup` | Base backups + archived WAL | FRA / RMAN destination |

Each mount gets its own size, its own alert threshold, and its own blast radius.

**4. The reply.**

Accept: keeping the layout simple and snapshot-friendly is a fair goal. Reject: PGDATA on the root volume - a WAL archiving failure would take down both the database and the OS in one event, and we cannot size "everything" as one number. Require: dedicated volumes for data, WAL, logs, and backups (the `/opt/pgsql` pattern), with root reserved for the OS. This costs three extra volumes on the build sheet and removes the single most common self-inflicted outage in PostgreSQL operations.

</details>

---

## Scenario 5: The Default-Database Trap

The monitoring team onboards the CardAuth EPAS server into their tooling. The agent runs as the `enterprisedb` OS user and executes a health probe. It fails instantly. Real output:

```
$ psql -p 5444 -c "SELECT 1;"
psql: error: connection to server on socket "/tmp/.s.PGSQL.5444" failed: FATAL:  database "enterprisedb" does not exist
```

The monitoring engineer's proposed fix, from the ticket:

> Easiest solution: just run `CREATE DATABASE enterprisedb;` and the probe works. Can you do that today?

For reference, a default EPAS 16 initdb creates exactly these databases: `edb`, `postgres`, `template0`, `template1`.

### Questions

1. The probe never specified a database name. Where did `database "enterprisedb"` come from?
2. The connection clearly reached the server (this is a FATAL from PostgreSQL, not a refused TCP connection). What does that tell you compared to Scenario 3?
3. What is the correct probe command, and why is `edb` the right target on this server?
4. Is `CREATE DATABASE enterprisedb;` a good idea? Give at least two reasons for your answer.

<details markdown="block">
<summary>Answer Discussion</summary>

**1. libpq defaults dbname to the username.**

psql (and every libpq-based client) resolves the database name in order: `-d` flag, then the `PGDATABASE` environment variable, then **the connecting username**. No `-d`, no `PGDATABASE`, OS user `enterprisedb` - so the client asked for a database literally named `enterprisedb`. On community PostgreSQL this trap is invisible, because the default user is `postgres` and initdb creates a `postgres` database, so username and database line up by accident. EPAS breaks that accident: the user is `enterprisedb` but no such database exists.

**2. This is a server-side error - authentication and routing all worked.**

Compare with Scenario 3: `Connection refused` meant nothing was listening and EPAS never saw the request. Here, the TCP (well, Unix socket) connection succeeded, pg_hba.conf allowed the connection, and the postmaster got as far as looking up the requested database in its catalog before rejecting it. Reading which layer produced the error - kernel, HBA, or catalog - is how you triage connection issues in one glance.

**3. The correct probe.**

Still as **enterprisedb** on **epas-lab**:

```bash
psql -p 5444 -d edb -c "SELECT 1;"
```

`-p 5444` sets the port, `-d edb` names the database explicitly, `-c` runs one command and exits. `edb` is the right target because it is the database EPAS creates as the Oracle-compatible home - the dual table, the dictionary views, the CardAuth migrated schemas all live there. It is the closest thing to "the SID you connect to" on this server. (`postgres` also exists and is fine for pure health checks, but standardizing on `edb` matches where the actual workload lives.)

**4. Do not create an `enterprisedb` database.**

- **It masks the misconfiguration instead of fixing it.** The probe would "work" while still relying on an implicit default. The day the agent runs as a different user, or the day someone copies the probe to another tool, it breaks again and nobody remembers why.
- **It creates a snowflake.** Every other EPAS server on earth has `edb`, `postgres`, and the templates. Yours now has a mystery database that appears in backups, in `\l` output, in capacity reports - and holds nothing. Future DBAs must ask "what is this for?" forever, and the safe answer to "can we drop it?" is never obvious once monitoring has been pointed at it.
- **Monitoring would probe a dead database.** A health check against an empty, unused database can pass while the real workload database `edb` has problems. Monitor where the workload is.

The fix is one flag in the agent config: set the database name to `edb` explicitly. Explicit beats implicit in every connection string you will ever write.

</details>

---

## How To Know You Are Done

You wrote answers to all five scenarios before opening the discussions, and you can now state from memory:

- **Redwood is an initdb-time decision** - mixed Oracle and community workloads mean two clusters, same binaries, different ports
- **Minor releases are the RU equivalent** - `dnf update edb-as16-\*` plus a restart; 16 to 17 is a project, not a patch
- **`#port = 5444` is the compiled default** - `Connection refused` means wrong port or nothing listening, and changing `port` requires a restart
- **pg_wal, base, and log grow** - PGDATA never belongs on the root volume; use dedicated data, wal, log, backup mounts
- **libpq defaults dbname to username** - always pass `-d edb` on EPAS, and never create a database just to satisfy a lazy default

If any of these took you by surprise, redo that scenario and re-read the matching Build 01/02 section before Prof. Happy unlocks the SURVIVE phase.

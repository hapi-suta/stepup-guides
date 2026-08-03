---
layout: default
title: "Interview 01 - Installation and Setup Discussion Points"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 8
locked: "no"
---

# Interview 01 - Installation and Setup Discussion Points

## What You Are Doing

You are rehearsing the 15 installation and setup questions an interviewer is most likely to throw at an Oracle DBA who now claims EPAS/PostgreSQL on their resume. Every answer below is grounded in what you actually did and saw on your epas-lab server in this module, so you can speak from experience, not from a blog post.

**Mode:** Study and rehearse out loud.

**Time:** 45 min.

**Prerequisite:** All other Module 02 phases complete.

---

## Question 1: Walk me through how you would install EPAS on a fresh Linux server.

**What they are really asking:** Can you actually do this hands-on, or have you only read about it? They want to hear a real sequence with real package names.

**Model answer:** On RHEL-family systems like CentOS Stream 9, EPAS installs from EDB's repos 2.0, which is a token-authenticated Cloudsmith repository. First I run EDB's setup script with my repo token, which imports the GPG keys and adds three repos: enterprisedb-enterprise, the noarch repo, and the source repo. Then I install the server and contrib packages with dnf, which pulls in about 11 edb-as16 packages including the client, core, libs, and the procedural language packages for Perl, Python, and Tcl.

The two commands, run as ec2-user on the target server:

```bash
curl -1sSLf 'https://downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh' | sudo -E bash
sudo dnf install -y edb-as16-server edb-as16-server-contrib
```

At that point I have binaries in /usr/edb/as16/bin and an OS user called enterprisedb, but no database yet. I run the setup wrapper to create the cluster:

```bash
sudo /usr/edb/as16/bin/edb-as-16-setup initdb
```

Then I enable and start the edb-as-16 systemd service. Coming from Oracle, the whole thing feels like runInstaller plus DBCA compressed into three commands: the dnf install is the software-only install, initdb is DBCA, and systemctl replaces the init.d or srvctl wiring. The big mindset shift is that there is no GUI installer and no response file. The package manager owns the software lifecycle, which also means patching later is a dnf operation rather than an OPatch session.

## Question 2: How does patching EPAS compare to patching Oracle with OPatch?

**What they are really asking:** Do you understand that the entire patching model is different, and can you reason about the operational consequences?

**Model answer:** In Oracle I lived in OPatch: download the PSU or RU from My Oracle Support, check conflicts, patch the Oracle home, run datapatch. In EPAS, patching is a package manager operation. A minor version bump, say from 16.14 to a newer 16.x, is a dnf update of the edb-as16 packages followed by a service restart. Minor releases in the Postgres world only change the binaries, never the on-disk data format, so there is no equivalent of datapatch for a minor update. The data directory stays exactly as it is and the new binaries just start against it.

That makes minor patching dramatically simpler and faster than an Oracle RU cycle. The trade-offs I plan around are different: dnf will restart nothing by itself, so I control the restart window, but I also have to make sure a routine OS-wide dnf update does not accidentally pull a database update at 2 AM via automatic updates. I typically version-lock the edb-as16 packages or exclude them from unattended updates so database patching stays a deliberate change.

Major version upgrades, say 16 to 17, are a different animal entirely, requiring pg_upgrade or a dump and reload, which is closer to an Oracle major release upgrade and gets treated as a project, not a patch.

## Question 3: What does initdb actually do, and what about it is irreversible?

**What they are really asking:** Whether you know the DBCA equivalent deeply enough to know which decisions you only get one shot at.

**Model answer:** initdb creates the cluster: it builds the data directory, in EPAS at /var/lib/edb/as16/data, writes the initial system catalogs, creates the template0 and template1 databases plus the postgres database, and in EPAS also creates the edb database and the enterprisedb superuser role. In Oracle terms it is DBCA, but for a whole cluster rather than a single database.

Several choices are baked in at initdb time and cannot be changed afterward without a dump and reload or a full re-init. The big ones are the Redwood versus no-redwood compatibility mode in EPAS, the cluster's default encoding and locale, whether data checksums are enabled, and the WAL segment size if you override it. Redwood mode is the one that catches Oracle folks: it is the default in EPAS, and I verified on my lab box that a Redwood cluster serves DUAL, SYSDATE in Oracle date format, and the Oracle dictionary views. If you initialize without Redwood and later need it, you are re-initializing and reloading, not flipping a parameter.

One more practical detail: initdb refuses to run against a non-empty directory. On my lab server, running it a second time returned this and exited 1:

```
Data directory is not empty!
```

That is a safety rail, not a bug. So before initdb on a production build I confirm the mode, encoding, locale, and checksum decisions in writing, the same way I used to review DBCA character set choices, because NLS_CHARACTERSET was equally unforgiving.

## Question 4: What is Redwood compatibility mode? What does it give you and what does it not give you?

**What they are really asking:** Whether you understand EPAS's core value proposition honestly, including its limits, or whether you will oversell it during a migration project.

**Model answer:** Redwood is EPAS's Oracle compatibility mode, chosen at initdb time and on by default. On my lab cluster I proved what it delivers, all against a stock install. DUAL exists and behaves:

```
 dummy
-------
 X
(1 row)
```

SYSDATE works and returns Oracle-format dates like 07-JUL-26 because edb_redwood_date is on. DBMS_OUTPUT.PUT_LINE runs through EDB's SPL and finishes with "EDB-SPL Procedure successfully completed". NVL and DECODE work as built-ins, and Oracle dictionary views like USER_TABLES are queryable. It also gives you Oracle-style packages, EDB-SPL as a PL/SQL-compatible language, and Oracle-ish data type behavior. That covers a large fraction of typical PL/SQL application code and dramatically reduces migration rewrite effort.

What it does not give you is Oracle itself. There is no RAC equivalent, no Oracle optimizer, no AWR, and Oracle-specific features like flashback query or fine-grained OEM integration have EPAS or Postgres analogues but not drop-in copies. Under the hood it is still PostgreSQL: MVCC with vacuum instead of undo, WAL instead of redo plus archive logs, and Postgres execution plans. My rule in migration assessments is that Redwood handles most of the schema and PL/SQL surface, but anything touching Oracle internals, hints, or RAC-specific behavior gets flagged for redesign rather than assumed compatible.

## Question 5: Explain the difference between a cluster, an instance, and a database in PostgreSQL/EPAS terms. Where do Oracle DBAs get this wrong?

**What they are really asking:** Terminology traps cause real miscommunication in mixed teams. They want to know you can translate cleanly.

**Model answer:** In Postgres, a cluster is one data directory served by one set of processes on one port. It has nothing to do with RAC or multi-node clustering, which is the first trap. Inside that single cluster live multiple databases: after my EPAS initdb I had four, which are edb, postgres, template0, and template1. The running processes plus shared memory are the closest thing to an Oracle instance, and unlike RAC there is always exactly one instance per cluster.

The second trap is the database boundary: in Oracle, schemas are just users inside one database, and cross-schema queries are trivial. In Postgres, databases within a cluster are hard boundaries, so you cannot join across them in a single connection without foreign data wrappers or dblink-style tools. Schemas in Postgres are namespaces inside a database and are decoupled from users, which is looser than Oracle's user-equals-schema model.

So my translation table is: a Postgres cluster is roughly one ORACLE_HOME plus one instance plus its storage, a Postgres database is roughly a PDB or a very isolated schema set, and a Postgres schema is the closest thing to an Oracle schema. Getting this wrong in a design meeting leads to architectures where someone plans cross-database joins that simply will not work.

## Question 6: What are the default port, superuser, and database in EPAS, and how do they differ from community PostgreSQL?

**What they are really asking:** These three defaults cause a disproportionate share of first-week incidents. They want proof you have hit and understood them.

**Model answer:** EPAS compiles its default port as 5444, not the community 5432. On my lab box, postgresql.conf shows the port line commented out:

```
#port = 5444				# (change requires restart)
```

That trips people up because the commented value is the compiled-in default, unlike Oracle where a commented parameter tells you nothing about the effective value. The OS user and superuser role is enterprisedb, not postgres, created by the RPM with uid 996 and home /var/lib/edb. And the default database for Oracle-style work is edb, alongside the standard postgres, template0, and template1. Community PostgreSQL is 5432, user postgres, database postgres.

The interplay bites in a specific way I hit live: psql defaults the database name to your username, so connecting as enterprisedb without specifying a database fails:

```
psql: error: connection to server on socket "/tmp/.s.PGSQL.5444" failed: FATAL:  database "enterprisedb" does not exist
```

The fix is always connecting with `-d edb`. Meanwhile EPAS's bundled psql defaults to port 5444 but any stock PostgreSQL client on the same box defaults to 5432, so two clients on one server can behave differently against the same running instance. The Oracle mapping I use: 5444 is my 1521 listener port, enterprisedb is my oracle OS user, and edb is the database I connect to the way I used to connect to a SID. In a mixed EPAS and community estate I document these three defaults per host, because "connection refused on 5432" against a healthy EPAS server is a classic false alarm.

## Question 7: A monitoring alert says the database on a new EPAS server is unreachable, but the application team swears it was working an hour ago. What defaults would you suspect first?

**What they are really asking:** Can you apply the port/user/database knowledge under incident pressure instead of just reciting it?

**Model answer:** Before I suspect the database, I suspect the client configuration, because on a fresh EPAS server the three most common false alarms are all client-side defaults. First, port: if the monitoring probe or the app's connection string assumes 5432, it will fail against EPAS listening on 5444, so I check what is actually listening with ss. On my lab server that shows:

```
LISTEN 0      200          0.0.0.0:5444      0.0.0.0:*
LISTEN 0      200             [::]:5444         [::]:*
```

Nothing on 5432, and that is correct. Second, database name: a probe connecting as enterprisedb without an explicit database gets FATAL: database "enterprisedb" does not exist, which looks like an outage in a log but is really a missing `-d edb`. Third, service state and name: EPAS's unit is edb-as-16 with hyphens in specific places, and checking the wrong name returns:

```
Unit edb-as16.service could not be found.
```

Someone checking that wrong unit name can conclude the service is down while it is running fine. Only after ruling those out do I look at pg_hba.conf rules, listen_addresses, and the actual server log under the data directory. In Oracle terms this is the same discipline as distinguishing a listener problem from a database problem: TNS-12541 never meant the database was down, and neither does a refused connection on the wrong port here.

## Question 8: Describe the EPAS directory layout. What would you put on separate storage in production and why?

**What they are really asking:** Whether you can translate your Oracle storage discipline of separating datafiles, redo, and archive into the Postgres world.

**Model answer:** EPAS 16 puts binaries under /usr/edb/as16/bin and the data directory, PGDATA, at /var/lib/edb/as16/data. Inside PGDATA the pieces that matter operationally are base for the actual table and index files, pg_wal for write-ahead log segments, log for the text server logs, pg_tblspc for tablespace symlinks, and the config files postgresql.conf, pg_hba.conf, and postgresql.auto.conf sitting at the top. Coming from Oracle, PGDATA is my datafile area, pg_wal is my redo, and the log directory is my alert log and trace area rolled into one.

In production I separate three things. First, pg_wal goes on its own volume, exactly like putting redo on dedicated storage, because WAL is sequential write and fsync-heavy, and because if the data volume fills, a separate WAL volume keeps the failure modes distinct. Second, large or hot application data goes into tablespaces on separate volumes via pg_tblspc, the same reasoning as Oracle tablespace placement. Third, WAL archives and backups never live on the same volume as PGDATA, since a full data disk taking out your recovery artifacts is an unforgivable single point of failure.

I also keep an eye on the log directory since verbose logging can quietly eat the data volume if it shares one. The one thing I do not separate is the config files from PGDATA on RHEL-style packaging, since the service's ExecStartPre check validates the data directory as a unit.

## Question 9: You have just installed EPAS on a new server. Give me your checklist to verify the install is healthy before you hand it over.

**What they are really asking:** Senior DBAs verify, juniors assume. They want a concrete, runnable sequence, not "I would check that it works."

**Model answer:** I run a five-point check, and every step has an expected answer. This is the exact sequence I ran on my lab build.

Point one, service. On the server, as ec2-user:

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

I want active (running), the ExecStartPre data directory check exited 0, and the main edb-postgres process pointing at /var/lib/edb/as16/data.

Point two, network. Still as ec2-user:

```bash
ss -tlnp | grep 5444
```

Expected output (yours will differ):

```
LISTEN 0      200          0.0.0.0:5444      0.0.0.0:*
LISTEN 0      200             [::]:5444         [::]:*
```

If I were grepping for 5432 here I would be verifying the wrong product.

Points three and four, connectivity, version, and compatibility mode, run as the enterprisedb user. Switch once:

```bash
sudo su - enterprisedb
```

Then, as enterprisedb:

```bash
psql -d edb -c "SELECT version();"
psql -d edb -c "SELECT * FROM dual;"
psql -d edb -c "SELECT sysdate FROM dual;"
exit
```

The version query must return, and on this build it reports PostgreSQL 16.14 with EnterpriseDB Advanced Server 16.14.0, confirming both the community base and the EPAS layer. The `-d edb` is deliberate, since omitting it fails on the enterprisedb database not existing. DUAL should return X, and sysdate should return an Oracle-format date:

```
      sysdate
--------------------
 07-JUL-26 01:48:18
(1 row)
```

Together those prove the cluster was initialized in Redwood mode. If they fail on a cluster that is supposed to host migrated Oracle code, I have found a re-init-level problem before the app team did.

Point five, logs. Back as ec2-user, I list the log directory under PGDATA, find the current file such as enterprisedb-2026-07-07_014817.log, and read it end to end looking for FATAL or ERROR lines from startup. This is the same instinct as tailing the alert log after an Oracle build, and it is the step people skip. The whole checklist takes two minutes and turns "I installed it" into "I verified it."

## Question 10: What happens when someone runs a dnf update on the server and it includes the EPAS packages?

**What they are really asking:** Whether you have thought about the failure mode where OS patching and database patching collide.

**Model answer:** dnf will replace the edb-as16 binaries in place with the newer minor version, and critically, the running instance keeps executing the old code from memory until something restarts it. That gap is the danger zone: the on-disk binaries and the running process no longer match, so an unplanned crash or an innocent reboot later effectively becomes an uncontrolled database patch. The data directory itself is safe, since minor versions never change the on-disk format, but extensions and the server binary should move together, and I want the restart to happen in a window I chose.

My controls are, first, excluding or version-locking edb-as16 packages from routine OS patching so database updates are a separate, deliberate change; second, when I do intend to patch, doing the dnf update and the systemctl restart of edb-as-16 as one planned operation with a health check after, which is my Question 9 checklist compressed; third, reading the release notes because occasionally a minor release requires a follow-up action like reindexing a specific index type.

Compared to Oracle this is both better and worse: better because there is no hours-long OPatch session and no datapatch, worse because the barrier to accidentally patching is one yum-style command that a well-meaning sysadmin can run. The organizational fix is making it explicit in the patching runbook who owns the edb-as16 packages, the same way the oracle home was never touched by the Linux team.

## Question 11: Can you run multiple EPAS clusters on one host? How would you set that up and when would you want to?

**What they are really asking:** Whether your mental model is one-database-per-server or whether you understand the cluster-per-port architecture well enough to consolidate.

**Model answer:** Yes, and it is a first-class pattern. Each cluster is just a data directory plus a port, so a second cluster means a second initdb into a different PGDATA, a distinct port since 5444 is taken by the first, and a second systemd unit pointing its PGDATA environment at the new directory. The packaged edb-as-16 unit already works this way, with an ExecStartPre that validates the data directory before starting edb-postgres against it, so a second unit is a copy with a different PGDATA and port. Each cluster gets its own shared memory, its own WAL, its own set of databases, and its own superuser, with complete isolation at the storage and crash-recovery level.

The Oracle analogy is running multiple instances from one home on one box, which we all did in dev, except Postgres makes it cleaner because there is no shared SGA sizing negotiation and no listener multiplexing, just distinct ports. I would use it for consolidating small dev and test environments, for running Redwood and non-Redwood clusters side by side during a migration, or for keeping an old minor version alive briefly during validation.

I would not use it for two production workloads that both matter, because they still share CPU, RAM, and the OS page cache, and Postgres has no resource manager as strong as Oracle's. And with the default shared_buffers at 128MB per cluster, multi-cluster hosts need deliberate memory budgeting per cluster rather than the defaults.

## Question 12: EPAS reported version 16.14 on your server. Decode that version number for me and explain how you track when to patch.

**What they are really asking:** Version literacy. Oracle DBAs think in RU quarters, and they want to know you can map that habit onto the Postgres release train.

**Model answer:** In 16.14, the 16 is the major version and the 14 is the minor. Majors ship yearly and change features and potentially the on-disk format, while minors are cumulative bug and security fix rollups released roughly quarterly, aligned with the community PostgreSQL point releases. So EPAS 16.14 corresponds to community PostgreSQL 16.14 plus EDB's Advanced Server layer, which the version string makes explicit: it reports PostgreSQL 16.14 and EnterpriseDB Advanced Server 16.14.0 together, and the installed RPMs on my lab box all carry 16.14.0-1.el9.

The mapping to my Oracle habits is direct: a minor release is like a quarterly RU, cumulative and low-drama, and a major upgrade is like going 12c to 19c, planned and tested as a project. My tracking process is to watch the community release schedule and EDB's advisories, then patch minors within a defined SLA, faster when a CVE lands in the fix list. Because minors do not touch the data format, my patch cycle is dnf update, restart, run the verification checklist, and I can rehearse it on a lower environment in minutes.

One nuance I carry from Oracle: never let a cluster drift so many minors behind that the fix list becomes unreadable, because cumulative or not, the risk review for a 10-minor jump is real work. And end-of-life matters: each major gets about five years of minors, so part of version tracking is knowing when major 16 stops receiving them and planning the major upgrade well before that.

## Question 13: How does EDB's repository access work, and how do you handle the credentials operationally?

**What they are really asking:** Whether you treat repo tokens as production credentials, and whether you can debug access failures.

**Model answer:** EPAS is commercial software, so unlike community PostgreSQL's public yum repos, EDB's repos 2.0 requires a subscription token. The token is embedded in the repo setup URL, `downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh`, and the resulting repo definitions on the server carry it for every subsequent dnf operation. That means the token is a credential sitting in /etc/yum.repos.d, and I treat it that way: it does not go in wikis, tickets, or version control, it gets distributed through a secrets channel, and if it leaks it gets rotated with EDB and re-deployed to every server. The Oracle parallel is your My Oracle Support credentials plus the license entitlement rolled into one string.

The failure mode is distinctive and I have seen it live: a bad or expired token makes the setup script fail with an HTTP 404:

```
curl: (22) The requested URL returned error: 404
```

Exit code 22, and on an existing server dnf starts throwing metadata fetch errors against the enterprisedb repos. So when EPAS patching suddenly breaks fleet-wide, my first suspicion is token expiry or a subscription lapse, not a network problem. Operationally I verify repo health as part of build validation with dnf repolist, which should show enterprisedb-enterprise, enterprisedb-enterprise-noarch, and enterprisedb-enterprise-source alongside the OS repos.

On air-gapped estates, the same token gates access for building an internal mirror, which is how I would handle environments where servers cannot reach the internet, similar to staging Oracle patches on an internal share.

## Question 14: Out of the box, is a fresh EPAS install production-ready? What would you tune first?

**What they are really asking:** Whether you know the defaults are deliberately conservative, and whether you have a principled first-pass tuning list rather than cargo-cult settings.

**Model answer:** No, and the clearest proof is shared_buffers: a fresh cluster ships with 128MB, which is a compatibility-safe floor so the instance starts on any machine, not a recommendation. On a dedicated database server I start shared_buffers at roughly a quarter of RAM, which is philosophically similar to sizing an SGA except Postgres deliberately leans on the OS page cache for the rest, so I do not chase Oracle-style 80 percent memory allocations.

My first-pass list after that: effective_cache_size set to what the OS cache can realistically hold so the planner costs index scans correctly, work_mem sized against expected concurrency since it is per-sort-node rather than a shared pool, maintenance_work_mem for vacuum and index builds, and max_wal_size so checkpoints are not firing constantly under write load. I also fix operational hygiene in the same pass: logging configuration since the defaults are quiet, listen_addresses and pg_hba.conf for real client access instead of local-only trust, and archive settings before the first backup, not after the first incident.

Two process points matter as much as the values. First, in EPAS the compiled defaults hide behind comments, the port 5444 line being the canonical example, so I read effective settings from pg_settings rather than trusting the conf file visually. Second, most of these require a restart or at least a reload, so I batch them into the build window rather than trickling restarts into the first production week. The theme for an Oracle audience: Postgres defaults assume a laptop, Oracle defaults assume a server, so the first hour of tuning is not optional here.

## Question 15: When would you recommend community PostgreSQL over EPAS, and vice versa?

**What they are really asking:** Judgment and honesty. Anyone can install both; they want to know you can make a defensible architecture and licensing recommendation.

**Model answer:** I frame it around three questions: what code are you running, what operational features do you need, and what are you willing to pay. EPAS earns its subscription when you are migrating Oracle applications, because Redwood mode, EDB-SPL, the Oracle packages like DBMS_OUTPUT, the dictionary views, and built-ins like NVL and DECODE turn a rewrite project into a port, and I have verified all of those working on a stock EPAS cluster. It also brings enterprise extras community lacks, like EDB Loader as an SQL*Loader analogue and sqlprotect, plus vendor support with an SLA, which for a Mastercard-class shop is often mandatory regardless of technology.

Community PostgreSQL wins for greenfield applications with no Oracle heritage, where the compatibility layer buys nothing and you avoid subscription cost and any vendor coupling, and its ecosystem, cloud availability, and talent pool are broader. The differences a candidate should name concretely: EPAS defaults to port 5444, user enterprisedb, and database edb versus 5432, postgres, and postgres, and EPAS's Redwood choice is baked in at initdb while community has no such mode at all.

The mistake I steer teams away from is choosing EPAS "to keep our options open" on a greenfield build, because writing new code against Oracle compatibility features quietly creates the very lock-in you left Oracle to escape. My honest default: EPAS for Oracle migrations and shops that need EDB's support and tooling, community for everything else, and never both dialects in one codebase. Being able to defend that line, rather than advocating one vendor reflexively, is what separates a migration lead from an installer.

---

## How to Use This Before an Interview

- Rehearse out loud, one question per pass. Reading silently does not build recall under pressure.
- For Questions 6, 7, and 9, be ready to type the actual commands on a whiteboard: the port check, the psql connect with -d edb, and the dual/sysdate proof.
- Every answer references something you did on epas-lab in this module. If a claim in your answer does not match what you saw, go back and re-run that step until it does.

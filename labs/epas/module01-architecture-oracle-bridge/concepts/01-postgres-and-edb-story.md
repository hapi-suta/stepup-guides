---
layout: default
title: "01 - Postgres and the EDB Story"
parent: "Module 01 - Architecture and Oracle Bridge"
nav_order: 1
---

# Postgres and the EDB Story

## Why This Module Matters

You are about to become responsible for an EDB Postgres Advanced Server
(EPAS) production environment at Mastercard. EPAS is not vanilla PostgreSQL.
It is a commercial distribution built by a company called EnterpriseDB
specifically to give Oracle DBAs a soft landing into the Postgres world.

If you understand where EPAS came from and why it exists, every decision
EDB made about features, tools, licensing, and support contracts will make
sense. If you skip the story, you will spend the next eight weeks confused
about why some commands look exactly like Oracle and others look nothing
like it.

This document is the story.

---

## Part 1: PostgreSQL - The 50-Year-Old Open Source Database

PostgreSQL is older than Oracle. It started as an academic research project
at UC Berkeley in 1973 under Michael Stonebraker, who built a system called
INGRES. Stonebraker won the Turing Award in 2014 for this work - the
computing equivalent of a Nobel Prize.

The lineage:

```
1973 - INGRES (Berkeley research project, used QUEL not SQL)
        |
1986 - POSTGRES (Stonebraker's redesign - "post-INGRES")
        |
1994 - Postgres95 (grad students add SQL parser, drop POSTQUEL)
        |
1996 - PostgreSQL (renamed, community takes over from Berkeley)
        |
1997 - PostgreSQL 6.0 (first community release)
        |
        ... 28 years of community-led development ...
        |
2024 - PostgreSQL 17 (current major version)
```

Three things about PostgreSQL matter for you as an Oracle DBA:

**1. It is not owned by a single company.** Oracle Corporation owns Oracle
Database. Microsoft owns SQL Server. PostgreSQL is owned by the PostgreSQL
Global Development Group, which has no employees, no offices, and no CEO.
Development happens through volunteer committers across many companies (EDB,
Crunchy Data, AWS, Microsoft, Google, NTT, and dozens of others).

This is why no single vendor can hold the PostgreSQL roadmap hostage. It is
also why Mastercard can deploy PostgreSQL at scale without negotiating
per-CPU license terms.

**2. It is licensed under the PostgreSQL License** - a permissive open
source license similar to BSD and MIT. You can use it commercially, modify
it, embed it in your own products, and never pay anyone. Many companies
have built commercial products on top of PostgreSQL exactly because of this
license.

**3. It has a release cadence of one major version per year**, with five
years of community support per major version. PostgreSQL 16 (your target
version) was released in September 2023 and is supported by the community
until November 2028.

---

## Part 2: Why Companies Built Distributions on Top of PostgreSQL

PostgreSQL out of the box is powerful but minimal. The community ships:

- The database engine
- A small set of CLI tools (psql, pg_dump, pg_basebackup)
- Source code

It does NOT ship:

- A graphical admin console
- An enterprise monitoring stack
- Commercial 24/7 support
- An Oracle-compatible PL/SQL parser
- A failover automation system
- A backup management server with web UI

If you want any of those, you either build them yourself or buy a
commercial distribution. Multiple companies sell commercial PostgreSQL
distributions:

| Vendor | Distribution | Key differentiator |
|:-------|:-------------|:-------------------|
| **EnterpriseDB (EDB)** | EPAS, EDB Postgres Distributed (PGD) | Oracle compatibility, enterprise tooling |
| Crunchy Data | Crunchy PostgreSQL | Kubernetes-first, FedRAMP/STIG hardened |
| Percona | Percona Distribution for PostgreSQL | Free, includes pgBackRest + Patroni |
| Cybertec | Cybertec Postgres Enterprise | European/German market focus |
| Fujitsu | Fujitsu Enterprise Postgres | Japan/APAC enterprise market |
| Amazon | RDS for PostgreSQL, Aurora PostgreSQL | Cloud-managed PostgreSQL |
| Google | Cloud SQL for PostgreSQL, AlloyDB | Cloud-managed PostgreSQL |
| Microsoft | Azure Database for PostgreSQL | Cloud-managed PostgreSQL |

Mastercard chose EDB. That is the only one you need to deeply understand.

---

## Part 3: Who is EnterpriseDB?

EnterpriseDB (EDB) is a Massachusetts-based company founded in 2004 by Andy
Astor and Denis Lussier. From day one, their business thesis was simple:

> "Oracle is expensive and locks customers in. PostgreSQL is free and open.
> If we add Oracle compatibility on top of PostgreSQL and sell enterprise
> support, large companies will migrate off Oracle and save millions."

That thesis turned out to be correct. EDB now has:

- 1,500+ enterprise customers
- 1,000+ employees worldwide
- Annual revenue in the hundreds of millions
- Backed by Bain Capital (majority owner since 2019) and IBM (minority
  stake since 2020)

EDB's strategy has been to:

1. Take community PostgreSQL
2. Add Oracle compatibility features (the "Advanced Server" piece)
3. Build enterprise tools around it (PEM, EFM, Barman partnership, BART,
   PGD, Migration Toolkit)
4. Sell commercial support subscriptions
5. Hire many of the top PostgreSQL committers (about 30% of PostgreSQL core
   committers work at EDB)

The last point matters: when you call EDB support, you may literally be
talking to the person who wrote the PostgreSQL feature you have a problem
with.

---

## Part 4: The EDB Product Line

EDB sells multiple products. You need to know what each one is, even if
you only directly use a few.

### Database Engines

**EDB Postgres Standard (PG Standard)**

Vanilla community PostgreSQL, packaged and supported by EDB. Same features
as `apt install postgresql-16` would give you, but you get EDB support
contracts.

**EDB Postgres Advanced Server (EPAS) - THIS IS WHAT YOU WILL USE**

PostgreSQL plus a layer of Oracle compatibility features baked into the
engine itself. Not a plugin - compiled into the binary. Features include:

- PL/SQL parser (called edb-spl, accepts most Oracle PL/SQL syntax)
- DBMS_ packages (DBMS_OUTPUT, DBMS_LOCK, DBMS_SCHEDULER, DBMS_SQL,
  DBMS_PIPE, UTL_FILE, UTL_SMTP, UTL_HTTP, UTL_ENCODE)
- Oracle data types (NUMBER, VARCHAR2, RAW, ROWID, LONG, INTERVAL DAY TO
  SECOND, etc.)
- Oracle SQL features (ROWNUM, hierarchical queries with CONNECT BY,
  hints in /*+ */ comments, sequences with NEXTVAL/CURRVAL, synonyms)
- Profiles with password policies (CREATE PROFILE, FAILED_LOGIN_ATTEMPTS,
  PASSWORD_LIFE_TIME, PASSWORD_REUSE_TIME)
- The `edb-psql` CLI (psql with Oracle-style prompt and SQL*Plus
  compatibility)
- The `edbplus` CLI (full SQL*Plus replacement with SET, COL, DEFINE)

When EDB says "Oracle compatible," they mean it. Most Oracle PL/SQL
packages move to EPAS with minor or zero changes. This is the entire
reason Mastercard chose EPAS instead of vanilla PostgreSQL.

**EDB Postgres Distributed (PGD)**

EDB's multi-master replication product. Formerly called BDR
(Bi-Directional Replication) - the name changed to PGD in late 2022. You
will work with PGD in Module 11.

If you hear someone at Mastercard say "BDR," they probably mean PGD - the
products are the same lineage. Legacy BDR3 still exists but is being
replaced.

### Enterprise Tools

**EDB Postgres Enterprise Manager (PEM)**

The OEM equivalent. Web-based monitoring and management console. Agent
runs on each database server, collects metrics, ships them to a central
PEM server with a PostgreSQL database backend. You will use PEM in Module
09.

**EDB Failover Manager (EFM)**

Manages PostgreSQL primary/standby clusters with automatic failover.
Roughly equivalent to Data Guard with Fast-Start Failover. Requires 3
nodes minimum (primary, standby, witness). You will use EFM in Module 07.

**Barman (Backup and Recovery Manager)**

Open-source PostgreSQL backup server, originally developed by 2ndQuadrant
(acquired by EDB in 2020). Roughly equivalent to RMAN with a backup
catalog. Manages full backups, incrementals, WAL archiving, retention
policies, and PITR. You will use Barman in Module 06.

Note: EDB also has a proprietary backup tool called BART (Backup and
Recovery Tool). Barman is the open source one, more widely used. Confirm
with Mastercard which one they actually run.

**EDB Migration Toolkit (MTK)**

Java-based tool that connects to your source Oracle database via JDBC,
reads the schema and data, and writes it to a target EPAS database. Used
for migrating Oracle workloads to EPAS. You will use MTK in Module 10.

**EDB BigAnimal**

EDB's managed cloud service - runs EPAS or community PostgreSQL on AWS,
Azure, or GCP. The EDB-managed equivalent of RDS. Mastercard likely runs
self-managed EDB on AWS Marketplace AMIs, not BigAnimal. Confirm.

---

## Part 5: Why Mastercard Chose EPAS (Probably)

You will not know the actual decision process unless someone tells you,
but the standard EPAS adoption pattern looks like this:

**Year 0:** Mastercard has thousands of Oracle databases. Annual Oracle
licensing costs run into millions per year. Renewal negotiations get
worse every year. CTO mandate: reduce Oracle footprint by X% over Y
years.

**Year 1:** Engineering teams evaluate PostgreSQL distributions. Vanilla
PG is the cheapest but requires rewriting every PL/SQL package, every
stored procedure, every Oracle-specific query. Cost: enormous engineering
effort, multi-year project, high risk.

**Year 2:** EDB pitches EPAS. The pitch: most Oracle PL/SQL runs on EPAS
unchanged. Most Oracle SQL runs unchanged. Most Oracle tools have direct
equivalents. Migration cost drops from "rewrite everything" to "test
everything." 5x to 10x cheaper than vanilla PG migration.

**Year 3:** Mastercard signs an enterprise EDB contract. Pilot
applications start moving to EPAS. EDB consultants help with migrations.
Mastercard DBA teams (you) need to learn EPAS to support the production
workload.

This is where you come in. You are not migrating Oracle workloads
yourself. You are running the EPAS infrastructure that the migrated
workloads land on. The migration teams hand you a running database, and
you keep it running.

---

## Part 6: What You Need to Internalize Before Module 02

Five facts to lock in before moving on:

1. **EPAS is PostgreSQL plus Oracle compatibility.** Not a fork. Not a
   different database. Everything you learn about PostgreSQL applies to
   EPAS. EPAS adds extra features on top.

2. **EPAS is commercial.** You cannot download it for free without an EDB
   account. The AMI you will use in Module 02 requires an active EDB
   Marketplace subscription. The license is per-CPU.

3. **You will deal with three EDB-specific operational tools** in this
   track: Barman (backup), EFM (HA failover), PEM (monitoring), plus PGD
   for multi-master and MTK for migration. Each replaces an Oracle tool
   you already know.

4. **The community PostgreSQL knowledge applies, with adjustments.** When
   you Google "how do I VACUUM in PostgreSQL," the community answer is
   correct for EPAS too. When you Google "how do I use DBMS_SCHEDULER in
   PostgreSQL," you will get a wrong answer because community PG does not
   have that package. You need to know when to search EDB docs versus
   community docs.

5. **EDB owns or contributes to most of the tools you will touch.** This
   means support contracts cover the full stack, not just the database.
   When something breaks in Barman or EFM, you call EDB support.

---

## Reading Checkpoint

Before moving to the next concepts doc, you should be able to answer
these without looking back:

1. What year was PostgreSQL renamed from Postgres95?
2. What company makes EPAS?
3. What is the difference between EPAS and vanilla PostgreSQL?
4. What was BDR renamed to?
5. Which EDB tool replaces Oracle Data Guard?
6. Which EDB tool replaces Oracle OEM?
7. Why did Mastercard choose EPAS instead of vanilla PostgreSQL?
8. What language does the EPAS PL/SQL parser accept?
9. What is the EPAS equivalent of SQL*Plus?
10. Who currently owns a majority stake in EDB?

If any of these are fuzzy, re-read the relevant section before moving on.

---

## Further Reading

- [EDB official docs](https://www.enterprisedb.com/docs/)
- [EPAS 16 release notes](https://www.enterprisedb.com/docs/epas/16/release_notes/)
- [PostgreSQL community](https://www.postgresql.org/)
- [EDB blog](https://www.enterprisedb.com/blog)
- [Stonebraker Turing Award lecture](https://amturing.acm.org/award_winners/stonebraker_1172121.cfm)

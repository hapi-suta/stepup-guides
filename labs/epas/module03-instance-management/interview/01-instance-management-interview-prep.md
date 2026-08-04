---
layout: default
title: "Interview 01 - Instance Management Discussion Points"
parent: "Module 03 - Instance Management"
nav_order: 7
locked: "no"
---

# Interview 01 - Instance Management Discussion Points

## What You Are Doing

You are rehearsing the 12 instance-management questions an interviewer is most likely
to put to an Oracle DBA now claiming EPAS/PostgreSQL. Every answer is grounded in what
you actually did on your `epas-single` server in this module, so you speak from
experience, not from a blog post.

**Mode:** Study and rehearse out loud.

**Time:** 45 min.

**Prerequisite:** All other Module 03 phases complete.

---

## Question 1: How do you start, stop, and restart EPAS on Linux?

**What they are really asking:** Do you know it is a systemd service, and its name?

Through the `edb-as-16` systemd service: `sudo systemctl start|stop|restart|status
edb-as-16`. The name carries the major version, so on a 15 server it is `edb-as-15`. I
verify state with `systemctl is-active edb-as-16`, which prints one word, and I know a
clean stop is a "fast" shutdown that disconnects clients and flushes to disk.

## Question 2: What is the difference between a reload and a restart, and when do you use each?

**What they are really asking:** This is the single most important operational
distinction. Get it wrong and you cause an outage or a failed change.

A **reload** (`systemctl reload edb-as-16`) makes the running server re-read its config
without dropping a single connection - it sends the postmaster a SIGHUP. A **restart**
stops and starts the instance and disconnects everyone. I use a reload whenever the
parameter allows it (production stays up), and a restart only for parameters that can
only change at startup.

## Question 3: How do you know, in advance, whether a parameter needs a restart?

**What they are really asking:** Do you check, or do you find out the hard way?

I check the parameter's **context** in `pg_settings`:
`SELECT name, context FROM pg_settings WHERE name = 'max_connections';`. A context of
`postmaster` means restart-only (`shared_buffers`, `port`, `max_connections`). `sighup`,
`superuser`, and `user` take effect on a reload. If I have already changed a
restart-only parameter, `pg_settings.pending_restart` reads `true` until I bounce.

## Question 4: What are the EPAS configuration files and which do you edit?

**What they are really asking:** Do you know `ALTER SYSTEM` versus hand-editing?

Three files in the data directory (`/var/lib/edb/as16/data`): `postgresql.conf`
(hand-edited), `postgresql.auto.conf` (written by `ALTER SYSTEM` - I never hand-edit it),
and `pg_hba.conf` (authentication rules). For run-time settings I prefer
`ALTER SYSTEM SET ...` because it is auditable and lands in `auto.conf` for me.

## Question 5: A colleague changed a setting in postgresql.conf but says it "isn't working." What happened?

**What they are really asking:** Do you understand file-on-disk versus running server?

Editing the file changes the file; the running server does not re-read it until told
to. They almost certainly did not reload. I would confirm with `SHOW <param>;` (live
value) versus the file, check the parameter's context, and reload (or restart if it is
a `postmaster` parameter).

## Question 6: EPAS is running but nobody can connect. Where do you look?

**What they are really asking:** Can you separate "service up" from "clients can
connect"?

Those are two different facts. If `systemctl is-active` says `active` but connections
fail, it is not the service. I check: is it listening on the right port
(`sudo ss -tlnp | grep 5444`)? Does the client error mention `pg_hba.conf`
(authentication) - in which case I read the rules top to bottom, first match wins. And
I check the server's own log in `/var/lib/edb/as16/data/log/`.

## Question 7: What is special about the EPAS port and superuser?

**What they are really asking:** Do you know the constants that differ from community
PostgreSQL?

EPAS defaults to port **5444**, not 5432; the bootstrap superuser is **enterprisedb**,
not `postgres`; and the default database is **edb**. Forgetting the port is the number
one reason a new EPAS DBA's connection "refuses" for no obvious reason.

## Question 8: What is edbplus and when would you use it over psql?

**What they are really asking:** Do you know the Oracle-compatibility tooling?

`edbplus` is EDB's re-implementation of Oracle's SQL\*Plus - same `SET` commands, same
`@script.sql`, same `EXIT`, same `dual` table. I reach for it when I am running existing
SQL\*Plus scripts or when an Oracle team wants a familiar prompt. For day-to-day Postgres
work I use `edb-psql` with its `\` meta-commands.

## Question 9: Why does edbplus need a password when local edb-psql does not?

**What they are really asking:** Do you understand local socket versus TCP
authentication?

`edb-psql` run locally as the `enterprisedb` OS user connects over a Unix socket and is
trusted by **peer** authentication - no password. `edbplus` is a Java client that
connects over **TCP**, where peer does not apply, so it needs a real password and a
`pg_hba.conf` rule that accepts one (I use `scram-sha-256`). Same database, different
door, different lock.

## Question 10: The service failed to start after a change. How do you find the cause?

**What they are really asking:** Do you go to the log, or guess?

I read the database's own log - `/var/lib/edb/as16/data/log/`, newest file, last lines -
not just `journalctl`. It names the offending parameter and why it is unacceptable.
This usually traces to a restart-only parameter that passed a reload but had a bad value
the next start could not accept. I fix the line in `postgresql.conf` and start the
service.

## Question 11: Map the EPAS instance processes to their Oracle equivalents.

**What they are really asking:** Can you bridge your Oracle knowledge?

The postmaster (`edb-postgres`) is the listener plus supervisor; each client gets a
backend process (a bit like a dedicated server process). checkpointer is `CKPT`,
background writer plus walwriter together do the work of `DBWn` and `LGWR`, autovacuum
is the automatic maintenance. The big difference: one postmaster owns one cluster, and
they cooperate through one block of shared memory whose largest piece, `shared_buffers`,
is my buffer cache.

## Question 12: How do you confirm an instance is healthy in under a minute?

**What they are really asking:** Do you have a repeatable check?

Service is `active` (`systemctl is-active edb-as-16`), it is listening on 5444
(`ss -tlnp | grep 5444`), I can connect (`edb-psql -p 5444 -d edb`), the log has no
recent errors, and `pg_settings.pending_restart` shows nothing waiting. Five checks,
under a minute, and I know the instance is genuinely up - not just that the process
exists.

---

## How to Use This

Say each answer out loud before you read the model answer. If you cannot answer from
what you did on your server this week, go back and do that phase again - a real answer
always beats a memorized one.

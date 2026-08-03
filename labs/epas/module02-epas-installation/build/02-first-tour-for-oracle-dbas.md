---
layout: default
title: "Build 02 - First Tour for an Oracle DBA"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 5
locked: "no"
---

# Build 02: First Tour for an Oracle DBA

## What You Are Doing

Build 01 left you with a running EPAS 16 server. Now you tour it the way you would on your first day owning it in production: where everything lives, how to stop and start it safely, the psql survival kit that replaces your SQL*Plus reflexes, and the health checklist you will run after every install, patch, and restart for the rest of your EPAS career.

**Mode:** Hands-on - you need your lab server with Build 01 complete.

**Time:** 60 minutes.

**Prerequisite:** Build 01.

---

## Step 1: Tour the Binaries (Your ORACLE_HOME/bin)

On **epas-single**, as **ec2-user**:

```
ls /usr/edb/as16/bin | head -20
```

This lists the first 20 programs in the EPAS binary directory. Everything you will ever run against this cluster lives here.

Expected output (yours will differ):

```
alteruser
clusterdb
createdb
createuser
dropdb
dropuser
edb-as-16-check-db-dir
edb-as-16-setup
...
```

The ones to recognize on sight:

| Binary | What it is | Oracle reflex |
| ------ | ---------- | ------------- |
| edb-postgres | The server binary itself (the postmaster) | oracle executable |
| psql | Interactive SQL client | sqlplus |
| pg_ctl | Low-level start/stop/reload control | startup/shutdown from SQL*Plus |
| pg_basebackup | Online physical backup tool | RMAN backup (you meet it in Module 06) |
| createdb / dropdb | Shell wrappers to create and drop databases | CREATE DATABASE, but cheap and instant |

---

## Step 2: The Two Config Files That Run Your Life

On **epas-single**, as **ec2-user**, read the port setting without switching users (a one-off read like this is fine with sudo):

```
sudo grep -E "^port|^#port" /var/lib/edb/as16/data/postgresql.conf
```

`grep -E` searches with a regex; this shows the port line whether it is active or commented out.

Expected output (yours will differ):

```
#port = 5444				# (change requires restart)
```

Read that carefully: the line is **commented out**, yet your server listens on 5444. Commented settings show the compiled-in default. EPAS was built with 5444 as its default port, which is why nobody had to set it. The comment also tells you the restart rule - port changes need a full restart, like changing a static Oracle parameter.

The other file, `pg_hba.conf`, controls who can connect from where and how they authenticate - it does the job of sqlnet.ora and listener access control combined. You get a full module on it later; for now, just know where it lives (same directory).

---

## Step 3: Check the Memory Settings (Your SGA Moment)

Switch to the database owner for a block of SQL work. On **epas-single**, as **ec2-user**:

```
sudo su - enterprisedb
```

Still as **enterprisedb** on **epas-single**:

```
psql -p 5444 -d edb
```

At the `edb=#` prompt:

```
SHOW shared_buffers;
```

`SHOW` displays a running parameter value - your `SHOW PARAMETER` equivalent.

Expected output (yours will differ):

```
 shared_buffers
----------------
 128MB
(1 row)
```

128MB. That is the out-of-the-box shared_buffers - the closest thing to your buffer cache - on a server that might have 64GB of RAM. Oracle would never ship a default that small; Postgres-family databases do, on purpose, so they start anywhere. Every production EPAS install gets this tuned (the working rule of thumb is around 25% of RAM). That is Module 08 territory - today you just need to know the default is tiny and finding it takes one command.

Two more you should know on day one:

```
SHOW data_directory;
```

Expected output (yours will differ):

```
     data_directory
------------------------
 /var/lib/edb/as16/data
(1 row)
```

If you ever land on an unfamiliar EPAS server, this is how you find PGDATA without trusting the environment or the docs.

---

## Step 4: Make Something and Find It in the Dictionary

Still as **enterprisedb**, at the `edb=#` prompt. Prove the Oracle data dictionary views work by giving them something to show:

```
SELECT count(*) FROM user_tables;
```

Expected output (yours will differ):

```
 count
-------
    16
(1 row)
```

Sixteen tables - on a cluster where you have created nothing? Look at what they are:

```
SELECT table_name FROM user_tables;
```

Expected output (yours will differ):

```
             table_name
-------------------------------------
 PRODUCT_COMPONENT_VERSION
 DUAL
 CALLBACK_QUEUE_TABLE
 PLSQL_PROFILER_RAWDATA
 EDB$SNAP
 EDB$SESSION_WAITS
...
(16 rows)
```

These are EPAS's own Oracle-compatibility furniture: DUAL itself is a real table here, plus the PL/SQL profiler tables and the EDB$ wait-event snapshot tables (you will meet those in the performance module - they are EPAS's answer to AWR). On a fresh Oracle database, USER_TABLES for SYS is not empty either; same idea. Now add one of yours:

```
CREATE TABLE card_auth_test (
    txn_id      NUMBER PRIMARY KEY,
    merchant    VARCHAR2(50),
    auth_time   DATE DEFAULT sysdate
);
```

Look at what you just wrote: `NUMBER`, `VARCHAR2`, `DATE DEFAULT sysdate`. Pure Oracle DDL, accepted verbatim because this cluster runs in Redwood mode.

```
INSERT INTO card_auth_test (txn_id, merchant) VALUES (1, 'COFFEE-SHOP-4521');
SELECT * FROM card_auth_test;
```

Expected output (yours will differ):

```
 txn_id |     merchant     |     auth_time
--------+------------------+--------------------
      1 | COFFEE-SHOP-4521 | 07-JUL-26 02:15:44
(1 row)
```

The DATE column defaulted from sysdate and prints in Oracle format. Now check the dictionary:

```
SELECT table_name FROM user_tables WHERE table_name = 'CARD_AUTH_TEST';
```

Expected output (yours will differ):

```
   table_name
-----------------
 CARD_AUTH_TEST
(1 row)
```

`user_tables` works, and the name comes back uppercase, exactly as your Oracle eyes expect. Clean up:

```
DROP TABLE card_auth_test;
```

---

## Step 5: The psql Survival Kit

Still as **enterprisedb**, at the `edb=#` prompt. psql meta-commands start with a backslash and replace your most-used SQL*Plus habits:

```
\l
```

Lists all databases in the cluster.

Expected output (yours will differ):

```
   Name    |    Owner     | Encoding | ...
-----------+--------------+----------+----
 edb       | enterprisedb | UTF8     | ...
 postgres  | enterprisedb | UTF8     | ...
 template0 | enterprisedb | UTF8     | ...
 template1 | enterprisedb | UTF8     | ...
(4 rows)
```

Four databases in a fresh cluster: `edb` is your working database, `postgres` is a plain community-style database many tools expect to find, and the two templates are what CREATE DATABASE clones (closest Oracle analogy: seed PDB).

The rest of the kit - run each one now so your fingers learn them:

| psql | What it does | SQL*Plus reflex |
| ---- | ------------ | --------------- |
| \dt | List tables in the current schema path | SELECT ... FROM user_tables |
| \d tablename | Describe a table | DESC tablename |
| \timing | Toggle per-query elapsed time | SET TIMING ON |
| \x | Toggle vertical output for wide rows | (no real equivalent - you will love it) |
| \q | Quit | exit |

When you are done exploring:

```
\q
```

```
exit
```

You are back to **ec2-user**. Always exit explicitly.

---

## Step 6: Stop and Start Like You Own It

Service control happens as **ec2-user** with systemctl - never from the enterprisedb account. On **epas-single**, as **ec2-user**:

```
sudo systemctl stop edb-as-16
```

Verify it is really down - trust the socket, not the message:

```
ss -tlnp | grep 5444
```

Expected output (yours will differ):

```
(no output - nothing is listening)
```

Empty output means port 5444 has no listener: the database is down. Now bring it back:

```
sudo systemctl start edb-as-16
```

```
sudo systemctl status edb-as-16
```

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Loaded: loaded (/usr/lib/systemd/system/edb-as-16.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-07-07 02:18:03 UTC; 5s ago
...
```

That stop/verify/start/verify rhythm is the discipline. `systemctl restart edb-as-16` exists too - one command for a bounce, the same idea as `shutdown immediate` plus `startup`, and like that pair it kills every session connected.

---

## Step 7: Find the Logs Before You Need Them

On **epas-single**, as **ec2-user**:

```
sudo ls /var/lib/edb/as16/data/log
```

Expected output (yours will differ):

```
enterprisedb-2026-07-07_014817.log
enterprisedb-2026-07-07_015440.log
...
```

One file per server start, named after the enterprisedb user and timestamped at startup. This directory is your alert log. Peek at the latest one:

```
sudo tail -5 /var/lib/edb/as16/data/log/$(sudo ls -t /var/lib/edb/as16/data/log | head -1)
```

The `$(...)` picks the newest file by modification time so you do not have to type the timestamp. You should see startup messages like `database system is ready to accept connections` - the EPAS version of a clean alert-log startup sequence.

---

## Step 8: The Post-Install Health Checklist

This is the checklist. Run it after every install, every patch, every restart, every 2am page - in this order, as shown. It takes 90 seconds.

On **epas-single**, as **ec2-user**:

```
sudo systemctl status edb-as-16 | head -3
ss -tlnp | grep 5444
```

Service active, port listening. Then:

```
sudo su - enterprisedb
```

Still as **enterprisedb**:

```
psql -p 5444 -d edb -c "SELECT version();"
psql -p 5444 -d edb -c "SELECT sysdate FROM dual;"
```

Version answers (the server accepts connections and runs SQL), and sysdate-from-dual proves you are on the Redwood cluster you think you are on. Then:

```
exit
```

Back as **ec2-user**, last check - no errors in the newest log:

```
sudo tail -5 /var/lib/edb/as16/data/log/$(sudo ls -t /var/lib/edb/as16/data/log | head -1)
```

Five checks: service, port, version, Redwood, logs. If all five pass, the server is healthy and you can say so with evidence.

---

## Checkpoint

You now know:

1. Where the binaries live (/usr/edb/as16/bin) and which five matter daily
2. The two config files (postgresql.conf, pg_hba.conf) and how commented defaults work
3. That shared_buffers ships at 128MB and will always need tuning
4. That Oracle DDL (NUMBER, VARCHAR2, sysdate defaults) and user_tables work natively in Redwood mode
5. The psql survival kit (\l, \dt, \d, \timing, \x, \q)
6. The stop/verify/start/verify service discipline
7. Where the logs are and the 5-point health checklist

Message Prof. Happy on WhatsApp: *done with build 02*. He will quiz you on Module 02 and unlock the Use phase - six installation incidents from production, and you get to be the DBA who explains them.

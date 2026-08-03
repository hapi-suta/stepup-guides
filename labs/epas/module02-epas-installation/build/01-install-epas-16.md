---
layout: default
title: "Build 01 - Install EPAS 16"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 4
locked: "no"
---

# Build 01: Install EPAS 16

## What You Are Doing

You are installing EDB Postgres Advanced Server 16 on your lab server, from bare CentOS to a running database you can log into. This is the install you would run at Mastercard if the CardAuth migration project handed you a fresh VM tomorrow. Every command below was tested on a real server and the expected output is shown, so you always know whether you are on track.

**Mode:** Hands-on - you need your lab server.

**Time:** 60 minutes.

**Prerequisite:** Concepts 01 (EDB Repos and Packaging) and Concepts 02 (Clusters, initdb, and the Redwood Decision). Do not skip Concepts 02 - Step 6 below makes a decision you cannot undo, and Concepts 02 explains it.

---

## Step 0: Connect to Your Server

Your welcome email from Prof. Happy has your server IP and SSH key. From your laptop:

```
ssh -i epas-lab.pem ec2-user@<YOUR-SERVER-IP>
```

- `-i epas-lab.pem` tells SSH which private key file to use
- `ec2-user` is the Linux login user on CentOS lab servers - think of it as your personal OS account, like logging into a database host with your own ID before touching the oracle account

You should land at a prompt like `[ec2-user@epas-single ~]$`.

---

## Step 1: Verify the OS

On **epas-single**, as **ec2-user**:

```
cat /etc/centos-release
```

This prints the OS release file so you know exactly what you are installing onto. EPAS ships packages per distro version, so this matters.

Expected output (yours will differ):

```
CentOS Stream release 9
```

---

## Step 2: Configure the EDB Repository

Oracle gives you a zip from My Oracle Support. EDB gives you a package repository, and access to it is controlled by a personal token. Prof. Happy sends you your token on WhatsApp - it is a credential, treat it like a password.

On **epas-single**, as **ec2-user**:

```
curl -1sSLf 'https://downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh' | sudo -E bash
```

- `curl` downloads the EDB repo setup script; `-1` forces TLSv1+, `-s` silent, `-S` still show errors, `-L` follow redirects, `-f` fail loudly on HTTP errors instead of piping an error page into bash
- `| sudo -E bash` runs the downloaded script as root; `-E` preserves your environment variables
- The script imports EDB's GPG signing keys and writes the repo definitions into /etc/yum.repos.d/

Expected output (yours will differ):

```
   OK: Importing 'enterprisedb/enterprise' repository GPG keys into rpm ...
   OK: Checking for available package manager (DNF/Microdnf/YUM/Zypper) ...
 ^^^^: ... Detected package manager as 'dnf'
   OK: Fetching 'enterprisedb/enterprise' repository configuration ...
   OK: Installing 'enterprisedb/enterprise' repository via dnf ...
...
   OK: The repository has been installed successfully - You're ready to rock!
```

If you get `curl: (22) The requested URL returned error: 404` your token is wrong - re-copy it from WhatsApp. You will diagnose this exact failure in Survive 01.

---

## Step 3: Confirm the Repos Are Registered

On **epas-single**, as **ec2-user**:

```
sudo dnf repolist
```

This lists every repository dnf can install from. You want to see three new enterprisedb entries next to the stock CentOS ones.

Expected output (yours will differ):

```
repo id                                repo name
appstream                              CentOS Stream 9 - AppStream
baseos                                 CentOS Stream 9 - BaseOS
enterprisedb-enterprise                enterprisedb-enterprise
enterprisedb-enterprise-noarch         enterprisedb-enterprise-noarch
enterprisedb-enterprise-source         enterprisedb-enterprise-source
extras-common                          CentOS Stream 9 - Extras packages
```

---

## Step 4: Install EPAS 16

On **epas-single**, as **ec2-user**:

```
sudo dnf install -y edb-as16-server edb-as16-server-contrib
```

- `edb-as16-server` is the meta package - it pulls in the core server, client tools, and libraries
- `edb-as16-server-contrib` adds the extension modules you will want in every real deployment (pg_stat_statements lives here - you will lean on it hard in the performance module)
- `-y` answers yes to the dependency prompt

This downloads roughly a dozen packages and takes a minute or two.

Expected output (yours will differ):

```
Installed:
  edb-as16-server-16.14.0-1.el9.x86_64
  edb-as16-server-client-16.14.0-1.el9.x86_64
  edb-as16-server-core-16.14.0-1.el9.x86_64
  ...
Complete!
```

Now verify what actually landed:

```
rpm -qa | grep edb-as16 | sort
```

`rpm -qa` lists every installed package; the grep narrows it to the EPAS 16 family. This is your install manifest - the equivalent of checking the OPatch inventory after an Oracle install.

Expected output (yours will differ):

```
edb-as16-server-16.14.0-1.el9.x86_64
edb-as16-server-client-16.14.0-1.el9.x86_64
edb-as16-server-contrib-16.14.0-1.el9.x86_64
edb-as16-server-core-16.14.0-1.el9.x86_64
edb-as16-server-libs-16.14.0-1.el9.x86_64
edb-as16-server-plperl-16.14.0-1.el9.x86_64
...
```

---

## Step 5: Meet the enterprisedb User

The rpm just created the OS account that owns everything, the same way the oracle user owns an Oracle home. On EPAS it is called `enterprisedb`, not postgres.

On **epas-single**, as **ec2-user**:

```
id enterprisedb
```

`id` shows the user's uid, primary group, and group memberships.

Expected output (yours will differ):

```
uid=996(enterprisedb) gid=995(enterprisedb) groups=995(enterprisedb)
```

Burn this into memory now: **the OS user is enterprisedb**. Typing `sudo su - postgres` on an EPAS box, out of PostgreSQL habit or from a blog post, gets you nothing.

---

## Step 6: Initialize the Cluster (The One-Way Door)

This is the step Concepts 02 prepared you for. `initdb` creates the data directory - the Oracle equivalent of DBCA creating your database. And the compatibility mode it picks is permanent for this cluster: the EPAS setup wrapper initializes in **Redwood mode** (Oracle-compatible) by default, which is exactly what you want for this track.

On **epas-single**, as **ec2-user**:

```
sudo /usr/edb/as16/bin/edb-as-16-setup initdb
```

- `/usr/edb/as16/bin` is where every EPAS 16 binary lives - your ORACLE_HOME/bin equivalent
- `edb-as-16-setup initdb` creates the cluster at /var/lib/edb/as16/data, owned by enterprisedb, in Redwood mode

Expected output (yours will differ):

```
Initializing database ... OK
```

One line, but a lot happened. Look at what it built:

```
sudo ls /var/lib/edb/as16/data
```

Expected output (yours will differ):

```
base     pg_hba.conf    pg_wal           postgresql.auto.conf
global   pg_ident.conf  pg_xact          postgresql.conf
log      pg_multixact   PG_VERSION       ...
```

You walked through what each of these means in Concepts 02. The two you will touch most in this track: `postgresql.conf` (your spfile) and `pg_hba.conf` (your sqlnet.ora/listener security, rolled into one).

If you run the initdb command a second time you get `Data directory is not empty!` - the cluster already exists and EPAS refuses to clobber it. Survive 01 covers when that message is routine and when it is a career-saving guardrail.

---

## Step 7: Enable and Start the Service

On **epas-single**, as **ec2-user** (systemctl always runs as ec2-user - never switch to enterprisedb for service commands):

```
sudo systemctl enable --now edb-as-16
```

- `enable` registers the service to start at boot
- `--now` also starts it immediately, saving you a second command

Note the service name carefully: `edb-as-16`, with a hyphen before the 16. `edb-as16` does not exist and systemctl will tell you so at the worst possible moment.

Now check it:

```
sudo systemctl status edb-as-16
```

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Loaded: loaded (/usr/lib/systemd/system/edb-as-16.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-07-07 01:48:17 UTC; 48ms ago
   Main PID: 10903 (edb-postgres)
     CGroup: /system.slice/edb-as-16.service
             ├─10903 /usr/edb/as16/bin/edb-postgres -D /var/lib/edb/as16/data
...
```

`Active: active (running)` is what you are looking for. The Main PID line is your postmaster - the process model you studied in Module 01, now alive on your own server.

---

## Step 8: Confirm the Listener Port

On **epas-single**, as **ec2-user**:

```
ss -tlnp | grep 5444
```

- `ss` shows sockets; `-t` TCP, `-l` listening only, `-n` numeric ports, `-p` owning process
- EPAS listens on **5444** by default, not PostgreSQL's 5432 and not Oracle's 1521

Expected output (yours will differ):

```
LISTEN 0      200          0.0.0.0:5444      0.0.0.0:*
LISTEN 0      200             [::]:5444         [::]:*
```

Every connection string you write for the rest of this track says port 5444. Every app team you ever hand an EPAS server to will forget this once. Use 01 has the incident write-up.

---

## Step 9: First Login

Time to connect. Switch to the enterprisedb OS user first - it authenticates to the database without a password on local connections (peer authentication, the mechanics come in the security module).

On **epas-single**, as **ec2-user**:

```
sudo su - enterprisedb
```

Your prompt changes to something like `[enterprisedb@epas-single ~]$`. You are now the database owner account.

Still as **enterprisedb** on **epas-single**:

```
psql -p 5444 -d edb
```

- `-p 5444` the EPAS port
- `-d edb` the database to connect to. This flag is NOT optional muscle memory: without it, psql assumes the database name matches your username and fails with `FATAL: database "enterprisedb" does not exist`. The database you work in is called `edb`.

You should land at the `edb=#` prompt. Now prove what you built:

```
SELECT version();
```

Expected output (yours will differ):

```
                                    version
--------------------------------------------------------------------------
 PostgreSQL 16.14 (EnterpriseDB Advanced Server 16.14.0) on x86_64-pc-linux-gnu,
 compiled by gcc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-5), 64-bit
(1 row)
```

Read that line the way Concepts 01 taught you: community PostgreSQL 16.14 underneath, EPAS 16.14.0 on top.

---

## Step 10: Prove Redwood Mode Is Alive

Still as **enterprisedb**, at the `edb=#` prompt. Four quick tests that would all fail on community PostgreSQL:

```
SELECT * FROM dual;
```

Expected output (yours will differ):

```
 dummy
-------
 X
(1 row)
```

```
SELECT sysdate FROM dual;
```

Expected output (yours will differ):

```
      sysdate
--------------------
 07-JUL-26 01:48:18
(1 row)
```

Look at that date format: `DD-MON-YY`. That is `edb_redwood_date` doing Oracle date behavior for you.

```
EXEC dbms_output.put_line('Hello from EPAS, Linuel');
```

Expected output (yours will differ):

```
Hello from EPAS, Linuel

EDB-SPL Procedure successfully completed
```

`EXEC` and `DBMS_OUTPUT` - the muscle memory you built over years of Oracle just worked on a Postgres-family database. Note the status line: `EDB-SPL Procedure successfully completed` where Oracle says PL/SQL. EDB-SPL is EPAS's PL/SQL-compatible language - same code, different badge.

```
SELECT nvl(NULL,'fallback') AS nvl_test, decode(1,1,'one','other') AS decode_test FROM dual;
```

Expected output (yours will differ):

```
 nvl_test | decode_test
----------+-------------
 fallback | one
(1 row)
```

---

## Step 11: Exit Cleanly

Still as **enterprisedb**:

```
\q
```

`\q` quits psql (your `exit` from SQL*Plus).

```
exit
```

This drops you from the enterprisedb shell back to **ec2-user**. Always exit explicitly so you know which user you are - half of all lab accidents start with someone running a command as the wrong user.

---

## Checkpoint

You now have:

1. The EDB repository registered with your personal token
2. EPAS 16.14 installed (11 packages, owned by the enterprisedb OS user)
3. A cluster initialized in Redwood mode at /var/lib/edb/as16/data
4. The edb-as-16 service enabled, running, and listening on 5444
5. A verified login path: ec2-user, then sudo su - enterprisedb, then psql -p 5444 -d edb
6. Proof that dual, sysdate, DBMS_OUTPUT, NVL, and DECODE all work

Message Prof. Happy on WhatsApp: *done with build 01*. He will check your work and point you to Build 02, where you tour everything you just installed the way you would on your first day owning it in production.

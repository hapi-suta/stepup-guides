---
layout: default
title: "Survive 01 - Installation Failure Scenarios"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 7
locked: "no"
---

# Survive 01 - Installation Failure Scenarios

## What You Are Doing

You are diagnosing four real installation failures that happen when a Mastercard-scale shop rolls out EPAS for the first time. Every error message in this document was captured on a real CentOS Stream 9 server running the exact install you did in Build 01. Your job is to reason through each one the way you would on an Oracle bridge call: evidence first, hypothesis second, change third.

**Mode:** Paper diagnosis now, live practice when your server arrives.

**Time:** 60 min.

**Prerequisite:** Build 01 complete.

---

## Severity Legend

| Severity | Meaning |
|----------|---------|
| SEV-1 | Production down or data at risk. All hands. |
| SEV-2 | Service degraded or rollout blocked. Fix this shift. |
| SEV-3 | Annoyance or single-user impact. Fix during business hours. |

## Format

Each scenario follows the Module 01 contract: **Alert** (what pages you), **Key Concepts for Revision** (what to re-read first), **Available Evidence** (real output from a live server), **Diagnostic Steps**, **Resolution Steps**, **Prevention**, and **Interview Discussion Points**. Work each one top to bottom. Do not jump to Resolution before working the Diagnostics - the whole point is building the discipline of not guessing.

---

## Scenario 1: The Repo That 404s (SEV-2)

### Alert

A junior DBA pings you: "The EDB repo setup script is failing on the new CardAuth database server. Curl says 404. Is EDB down? The rollout is blocked."

### Key Concepts for Revision

- The EDB repos 2.0 setup URL embeds your company token: `https://downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh`. The token IS the authentication - there is no separate login.
- Oracle bridge: this is bad My Oracle Support credentials when pulling a patch. The media server is fine; your key to it is not.
- curl exit code 22 means "HTTP error returned and --fail was set". The server answered - so the network path works.

### Available Evidence

The junior DBA sends you the failing output:

```
curl: (22) The requested URL returned error: 404
exit=22
```

### Diagnostic Steps

Three plausible causes. Order them by likelihood and cost to check.

**1. Token wrong or expired (most likely).** The token is part of the URL path, and a 404 means the path did not resolve. A mangled paste (truncated token, smart quotes from a Word doc, trailing space) produces exactly this. Ask the junior to show you the command they ran, not a description of it.

**2. Proxy or egress filtering (possible in a locked-down network).** On **epas-lab**, as **ec2-user**, test reachability to the EDB host. The `-I` flag asks for headers only, so nothing downloads:

```bash
curl -I https://downloads.enterprisedb.com
```

Any HTTP response back means the network path is fine and you are back to suspecting the token.

**3. EDB outage (least likely).** A real outage returns connection failures or 5xx errors across the board, not a clean 404 on one URL. Check the EDB status page before blaming the vendor.

Key reasoning: a 404 is the server saying "I answered, and that path does not exist." That is almost never an outage. It is almost always the path - and your token is in the path.

### Resolution Steps

On **epas-lab**, as **ec2-user**:

**1. Get the correct token.** Prof. Happy sends your token on WhatsApp. Never copy it from a document that may have mangled it, and never commit it to a repo or paste it into a ticket.

**2. Re-run the setup script with the verified token.** `-1sSLf` means: TLS 1.x, silent, show errors, follow redirects, fail on HTTP errors. `sudo -E bash` runs the downloaded script as root:

```bash
curl -1sSLf 'https://downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh' | sudo -E bash
```

Expected output (yours will differ):

```
   OK: Importing 'enterprisedb/enterprise' repository GPG keys into rpm ...
   OK: Fetching 'enterprisedb/enterprise' repository configuration ...
   OK: Installing 'enterprisedb/enterprise' repository via dnf ...
...
   OK: The repository has been installed successfully - You're ready to rock!
```

**3. Confirm the three enterprisedb repos are registered.** `dnf repolist` lists every repo dnf will consult:

```bash
dnf repolist
```

Expected output (yours will differ):

```
repo id                                repo name
appstream                              CentOS Stream 9 - AppStream
baseos                                 CentOS Stream 9 - BaseOS
enterprisedb-enterprise                enterprisedb-enterprise
enterprisedb-enterprise-noarch         enterprisedb-enterprise-noarch
enterprisedb-enterprise-source         enterprisedb-enterprise-source
...
```

All three `enterprisedb-*` repos present means the token is valid and the rollout is unblocked.

### Prevention

- Store the token in the team secrets manager, not in wiki pages where copy-paste corrupts it.
- Put repo setup in a tested provisioning script so humans stop hand-pasting tokens under pressure.
- Document the "404 means token, not outage" rule in the team runbook.

### Interview Discussion Points

- "Walk me through diagnosing a package repo failure." Lead with exit-code reasoning: 404 with curl exit 22 proves connectivity and points at the URL path, which contains the credential.
- The Oracle parallel: bad MOS credentials versus Oracle's download site being down - check the cheap, likely thing first. Repo tokens are credentials and belong in a vault.

---

## Scenario 2: initdb Says No (SEV-1)

### Alert

During a planned rebuild of the CardAuth staging database, a teammate runs initdb and it refuses. They message you: "initdb is failing with 'Data directory is not empty'. OK if I just delete the data directory and re-run it?"

Stop. The answer to that question is what this scenario is about.

### Key Concepts for Revision

- `edb-as-16-setup initdb` refuses to run against a non-empty PGDATA (`/var/lib/edb/as16/data`) by design. This is a safety interlock, not a bug.
- Oracle bridge: this is DBCA telling you the target directory already holds datafiles. You would never `rm -rf` an ORACLE_BASE datafile directory to make DBCA happy. Same discipline here.
- The non-empty directory might be a LIVE production cluster someone pointed you at by mistake - wrong server, wrong terminal tab, stale ticket. The error cannot tell you which. Only investigation can.

### Available Evidence

```
Data directory is not empty!

exit=1
```

### Diagnostic Steps

Before ANY deletion, answer three questions with evidence.

**1. Is a cluster currently running out of that directory?** On **epas-lab**, as **ec2-user**, check the service:

```bash
sudo systemctl status edb-as-16
```

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Active: active (running) since Tue 2026-07-07 01:48:17 UTC; 48ms ago
   Main PID: 10903 (edb-postgres)
...
```

If it says `active (running)`, you were one `rm -rf` away from killing a live cluster. Full stop - re-verify which server you are on and which environment this is.

**2. What is actually in the data directory?** Still as **ec2-user** (`sudo` because the directory belongs to enterprisedb, `-la` shows ownership and timestamps):

```bash
sudo ls -la /var/lib/edb/as16/data
```

Expected output (yours will differ):

```
base
global
pg_wal
postgresql.conf
PG_VERSION
...
```

A populated `base/` and a `PG_VERSION` file mean a real initialized cluster, not leftover junk. Files modified minutes ago mean recent activity.

**3. Do backups exist, and is anyone depending on this cluster?** Confirm the last backup for this host, and confirm in writing (ticket or chat) that this specific cluster is approved for destruction. At Mastercard scale, "staging" directories have a way of quietly becoming production.

### Resolution Steps

Only proceed once all three diagnostic questions have clean answers and the rebuild is approved.

On **epas-lab**, as **ec2-user**:

**1. Stop the service.** Never work on a data directory with the server running:

```bash
sudo systemctl stop edb-as-16
```

**2. Move the old directory aside - do not delete it.** `mv` is instant, reversible, and preserves everything if you discover in an hour that someone needed this cluster. The date suffix documents when it was retired:

```bash
sudo mv /var/lib/edb/as16/data /var/lib/edb/as16/data.old-20260707
```

**3. Re-run initdb.** The setup wrapper creates a fresh PGDATA with Redwood (Oracle-compatible) mode on by default:

```bash
sudo /usr/edb/as16/bin/edb-as-16-setup initdb
```

Expected output (yours will differ):

```
Initializing database ... OK
```

**4. Start the service and verify it is healthy:**

```bash
sudo systemctl start edb-as-16
sudo systemctl status edb-as-16
```

Confirm `Active: active (running)`, then run the same connection check you did at the end of Build 01 (switch to enterprisedb, `psql -p 5444 -d edb`, then `exit`).

**5. Only after days of verified healthy operation**, and with sign-off, remove `data.old-20260707` to reclaim disk.

### Prevention

- Team rule: `rm -rf` is never the answer to "Data directory is not empty". Move aside, verify, delete later.
- Rebuild runbooks start with "confirm hostname, confirm service stopped, confirm backup" as checkbox steps.
- Distinct shell prompts or terminal colors for production versus staging make the wrong-tab mistake harder.

### Interview Discussion Points

- A gift of an interview story: "Tell me about a time you prevented data loss." The initdb interlock plus mv-not-rm discipline shows senior judgment.
- Draw the DBCA parallel explicitly - interviewers hiring Oracle-to-Postgres migrators want to hear you transfer safety instincts, not just syntax.
- Be ready to explain WHY mv beats rm: reversibility, forensic value, near-zero cost on the same filesystem.

---

## Scenario 3: systemctl Says the Unit Does Not Exist (SEV-3)

### Alert

2:07 AM. A CardAuth batch job failed its database health check and the on-call engineer escalates: "I tried to check the database service and systemd says the unit doesn't exist. Did the install get wiped?"

### Key Concepts for Revision

- The EPAS 16 systemd unit is `edb-as-16` - hyphens on both sides of the version. `edb-as16` does not exist, even though the RPM packages ARE named `edb-as16-*`. Package name and unit name disagree by one hyphen. Everyone hits this once.
- systemd exit code 4 from `systemctl status` means "no such unit", not "unit failed".
- Oracle bridge: this is typo-ing the service name in `srvctl` and concluding the database is gone. The database was never asked.

### Available Evidence

The on-call engineer ran:

```
$ sudo systemctl status edb-as16
Unit edb-as16.service could not be found.
exit=4
```

### Diagnostic Steps

**1. Read the error precisely.** "Could not be found" is a statement about the unit NAME, not the database. A dead database with a correct unit name says `inactive (dead)` or `failed`. This message means systemd has never heard of the name you typed.

**2. Find the real unit name.** On **epas-lab**, as **ec2-user**, list unit files and filter for anything EDB-related. `list-unit-files` shows every unit systemd knows about; `grep -i edb` filters case-insensitively:

```bash
systemctl list-unit-files | grep -i edb
```

Expected output (yours will differ):

```
edb-as-16.service                          enabled         disabled
```

There it is: `edb-as-16`, with the extra hyphen.

### Resolution Steps

On **epas-lab**, as **ec2-user**:

**1. Check status with the correct name:**

```bash
sudo systemctl status edb-as-16
```

Expected output (yours will differ):

```
● edb-as-16.service - EDB Postgres Advanced Server 16
     Loaded: loaded (/usr/lib/systemd/system/edb-as-16.service; enabled; preset: disabled)
     Active: active (running) since Tue 2026-07-07 01:48:17 UTC; 48ms ago
   Main PID: 10903 (edb-postgres)
...
```

The database was running the whole time. The health-check failure that started this page is a separate investigation - but "install got wiped" is off the table in under a minute.

**2. Close the loop with the on-call engineer** so they learn the one-hyphen rule instead of fearing the server.

### Prevention

- Put the exact unit name in the runbook header for every EPAS host: "Service: edb-as-16 (note the hyphens)".
- Teach the recovery move, not just the name: `systemctl list-unit-files | grep -i edb` works even when memory fails at 2 AM.

### Interview Discussion Points

- Small story, big signal: "read the error message literally" separates calm operators from guessers. Exit code 4 versus a failed unit is a great detail to cite.
- Useful when asked "how do you onboard Oracle DBAs to Postgres?" - naming friction like package `edb-as16` versus unit `edb-as-16` is exactly what checklists exist for.

---

## Scenario 4: Fresh Install, Cannot Connect (SEV-2)

### Alert

The CardAuth platform team finishes a fresh EPAS install on a new node. Monitoring is green: service active, port 5444 listening. But every psql attempt fails, and the platform lead escalates: "The install must be corrupt. Postgres says our database does not exist. We need to reinstall."

### Key Concepts for Revision

- libpq (the client library under psql and most drivers) defaults the database name to your username when you do not pass `-d`. Log in as OS user `enterprisedb`, run bare `psql`, and it tries to connect to a database literally named `enterprisedb`.
- After initdb, EPAS has exactly four databases: `edb`, `postgres`, `template0`, `template1`. There is no `enterprisedb` database. The Oracle-style default for EPAS work is `edb`.
- Oracle bridge: in Oracle you connect to an instance (SID or service name), one database per instance. In Postgres, one cluster serves many databases and every connection MUST name one. `FATAL: database ... does not exist` is the server working correctly - a corrupt install could not send that message.

### Available Evidence

The server side looks perfect. Real captured output:

```
LISTEN 0      200          0.0.0.0:5444      0.0.0.0:*
LISTEN 0      200             [::]:5444         [::]:*
```

But the connection attempt as enterprisedb fails:

```
psql: error: connection to server on socket "/tmp/.s.PGSQL.5444" failed: FATAL:  database "enterprisedb" does not exist
exit=2
```

### Diagnostic Steps

**1. Notice what the error proves.** The client reached the server over the socket, the server authenticated the user, checked its catalog, and returned a well-formed FATAL. Every one of those steps requires a healthy postmaster. This single line rules out "corrupt install".

**2. Notice WHICH database it looked for.** Nobody typed `enterprisedb` as a database name. That is the giveaway: psql defaulted dbname to the OS username because no `-d` was given.

**3. Confirm what databases actually exist.** On **epas-lab**, as **ec2-user**, switch to the enterprisedb user:

```bash
sudo su - enterprisedb
```

Still as **enterprisedb**, list databases. `-l` lists every database in the cluster; `-d edb` gives psql a database that exists to connect through:

```bash
psql -p 5444 -d edb -l
```

Expected output (yours will differ):

```
   Name    |    Owner     | Encoding | ...
-----------+--------------+----------+----
 edb       | enterprisedb | UTF8     | ...
 postgres  | enterprisedb | UTF8     | ...
 template0 | enterprisedb | UTF8     | ...
 template1 | enterprisedb | UTF8     | ...
```

Four databases, none named `enterprisedb`. Diagnosis complete: wrong default dbname, healthy server.

### Resolution Steps

**1. Connect correctly.** Still as **enterprisedb**, name the database explicitly. `-p 5444` is the EPAS port and `-d edb` is the Oracle-compatible default database:

```bash
psql -p 5444 -d edb -c "SELECT version();"
```

Expected output (yours will differ):

```
                                     version
---------------------------------------------------------------------------------
 PostgreSQL 16.14 (EnterpriseDB Advanced Server 16.14.0) on x86_64-pc-linux-gnu...
(1 row)
```

**2. Return to ec2-user:**

```bash
exit
```

**3. Brief the app team, because they are about to hit the same trap.** A JDBC URL like `jdbc:postgresql://cardauth-db:5444/cardauth` fails identically if the database `cardauth` was never created or the URL carries the wrong dbname - and the app team will also call it "a broken database server". Give them the exact database name for their connection strings, and create the application database before they deploy.

### Prevention

- Runbook rule for EPAS hosts: always connect with `psql -p 5444 -d edb` spelled out. Never rely on defaults during incident response.
- Make a connection smoke test the final step of every install runbook: `psql -p 5444 -d edb -c "SELECT 1;"` proves both port and dbname before you hand the box over.
- When handing a server to an app team, put the full connection string (host, port 5444, database name) in the ticket, not just "it's up".

### Interview Discussion Points

- The classic "looks like an outage, is actually a client default" story. Explaining that a FATAL from the server PROVES the server is healthy shows real Postgres understanding.
- The Oracle contrast is interview gold: one-database-per-instance thinking versus multi-database clusters, and why every Postgres connection must name a database.
- Mention port 5444 versus 5432: EPAS's own psql defaults to 5444, but stock PostgreSQL clients default to 5432 - a second client-side default that bites mixed environments.

---

## Wrap-Up

Four failures, zero reinstalls, and only one ever justified touching the data directory. The pattern: the error message told the truth, and the fast path was reading it literally, gathering evidence with cheap read-only commands, and only then changing anything. When your server arrives, re-create each of these on purpose and fix them live - paper diagnosis builds the reasoning, breaking your own lab builds the reflexes.

- Prof. Happy (SUTA Labs)

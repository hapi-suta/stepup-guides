---
layout: default
title: "Concepts 01 - EDB Repos, Packaging, and How EPAS Ships"
parent: "Module 02 - EPAS 16 Installation"
nav_order: 1
locked: "no"
---

# Concepts 01: EDB Repos, Packaging, and How EPAS Ships

## What You Are Doing

You are learning how EDB distributes and patches EPAS before you install it in Build 01. This matters because the entire software lifecycle - getting media, installing, patching, upgrading - works completely differently from the Oracle world you know. You have spent years with My Oracle Support downloads, OPatch, and quarterly RUs. None of that exists here, and what replaces it is simpler than you expect.

**Mode:** Theory only - read on your laptop.

**Time:** 45 min.

**Prerequisite:** Module 01 complete (architecture theory).

---

## The Big Shift: From Downloaded Media to Package Repositories

Think about how you get Oracle software onto a server today at Mastercard:

1. Log in to My Oracle Support (support.oracle.com) with your CSI number
2. Download a multi-gigabyte zip of the base release (say, 19.3)
3. Stage it, unzip it, run the installer (runInstaller or the gold image clone)
4. Download the latest Release Update (RU) - another few gigabytes
5. Run `opatch apply`, then `datapatch` to sync the data dictionary
6. Repeat the RU dance every quarter, forever

Every step is manual, every artifact is a file you personally downloaded, staged, and checksummed. Oracle software distribution is a *pull-files-and-run-installers* model.

EPAS ships the way modern Linux software ships: through a **package repository**. There is no installer to download, no zip to stage, no `runInstaller`. You point the OS package manager (`dnf` on CentOS/RHEL) at EDB's repository once, and from then on:

- **Install** = `dnf install`
- **Patch** = `dnf update`
- **Verify** = `rpm -qa`

The package manager handles download, GPG signature verification, dependency resolution, and file placement. The same tool you use to install `htop` installs your enterprise database.

| Oracle world | EPAS world |
|:-------------|:-----------|
| My Oracle Support download (CSI-gated) | EDB repository (token-gated) |
| Base release zip + runInstaller | `dnf install edb-as16-server` |
| Quarterly RU zip + `opatch apply` | `dnf update` |
| `datapatch` after patching | Not needed (see below) |
| OPatch inventory (`opatch lsinventory`) | RPM database (`rpm -qa 'edb-as16*'`) |
| Manual checksum verification | Automatic GPG signature verification |

---

## EDB Repos 2.0: Token-Based Access

EPAS is commercial software, so the repository is not public. EDB runs its repositories on a hosted packaging platform called **Cloudsmith**, and access is controlled by a **repository token** - a long random string unique to your subscription. Think of the token as your CSI number: it proves you are entitled to the software.

The token is embedded in the repository URL itself. The setup command looks like this (you will run it in Build 01):

On **epas-lab**, as **ec2-user**:

```bash
curl -1sSLf 'https://downloads.enterprisedb.com/<YOUR-EDB-REPO-TOKEN>/enterprise/setup.rpm.sh' | sudo -E bash
```

What this does: `curl` downloads a shell script from EDB's server and pipes it into `bash` running as root. The flags: `-1` forces TLSv1 or newer, `-s` is silent mode, `-S` still shows errors, `-L` follows redirects, and `-f` makes curl fail with an error code on HTTP errors instead of saving an error page. `sudo -E` runs bash as root while preserving your environment variables.

**Never put your real token in a script, a git repo, or a chat message.** Treat it like a database password. Prof. Happy sends your token on WhatsApp.

### What the setup script actually does

Piping a script from the internet into a root shell should make any senior DBA pause, so let us be precise about what it does. The script:

1. **Detects your OS** (distro, version, architecture) so it can serve the right repo definition
2. **Imports EDB's GPG signing keys** into the RPM keyring, so every package you later install is cryptographically verified against EDB's signature
3. **Writes repo definition files** into `/etc/yum.repos.d/` - three of them:
   - `enterprisedb-enterprise` (the main x86_64 packages)
   - `enterprisedb-enterprise-noarch` (architecture-independent packages)
   - `enterprisedb-enterprise-source` (source RPMs)
4. **Refreshes the dnf metadata cache** so the new packages are immediately visible

Here is the real output from our validated install:

Expected output (yours will differ):

```
   OK: Importing 'enterprisedb/enterprise' repository GPG keys into rpm ...
   OK: Checking for available package manager (DNF/Microdnf/YUM/Zypper) ...
 ^^^^: ... Detected package manager as 'dnf'
   OK: Fetching 'enterprisedb/enterprise' repository configuration ...
   OK: Installing 'enterprisedb/enterprise' repository via dnf ...
   OK: Updating the dnf cache to fetch the new repository metadata ...
   OK: The repository has been installed successfully - You're ready to rock!
```

After the script runs, `dnf repolist` shows the three new EDB repos alongside the stock CentOS ones. That is the entire "media acquisition" step. No 3 GB downloads, no staging directory, no unzip.

One production note: if the token is wrong or expired, curl fails immediately with `curl: (22) The requested URL returned error: 404` and exit code 22. A 404 here almost always means bad token, not "EDB is down." You will break and fix this yourself in the SURVIVE phase.

---

## The edb-as16 Package Family

When you run the install in Build 01, you will type one command:

```bash
sudo dnf install -y edb-as16-server edb-as16-server-contrib
```

That pulls in the full EPAS package family. Here is the real list from our validated server - this is what `rpm -qa 'edb-as16*'` shows after install:

Expected output (yours will differ):

```
edb-as16-server-16.14.0-1.el9.x86_64
edb-as16-server-client-16.14.0-1.el9.x86_64
edb-as16-server-contrib-16.14.0-1.el9.x86_64
edb-as16-server-core-16.14.0-1.el9.x86_64
edb-as16-server-docs-16.14.0-1.el9.x86_64
edb-as16-server-ecpg-16.14.0-1.el9.x86_64
edb-as16-server-libs-16.14.0-1.el9.x86_64
edb-as16-server-plperl-16.14.0-1.el9.x86_64
...
```

What each package contains:

| Package | What is inside | Oracle analogy |
|:--------|:---------------|:---------------|
| `edb-as16-server` | Meta-package that ties the family together, systemd unit, setup scripts | The top-level "Database Server" install option |
| `edb-as16-server-core` | The actual database engine binary (`edb-postgres`), `initdb`, `pg_ctl` | `$ORACLE_HOME/bin/oracle` itself |
| `edb-as16-server-client` | Client tools: `edb-psql`, `pg_dump`, `pg_restore`, `createdb` | SQL*Plus + Data Pump client pieces |
| `edb-as16-server-contrib` | Optional extensions: `pg_stat_statements`, `pgcrypto`, `oid2name`, etc. | The "companion" or examples CD, but you actually want it |
| `edb-as16-server-libs` | Shared libraries (`libpq` etc.) that clients link against | Oracle client libraries / instant client |
| `edb-as16-server-plperl` / `-plpython3` / `-pltcl` | Procedural language handlers so you can write functions in Perl, Python, Tcl | Java in the database, roughly - extra in-database languages |
| `edb-as16-server-sqlprotect` | EDB's SQL injection prevention module (EPAS-only security feature) | No direct Oracle equivalent - closest is Database Firewall |
| `edb-as16-server-docs` | Man pages and documentation | Bundled docs |
| `edb-as16-server-ecpg` | Embedded SQL in C preprocessor | Pro*C |

Naming convention worth memorizing: `edb-as16` = EDB Advanced Server, major version 16. When EPAS 17 ships it will be a separate `edb-as17-*` family that installs side by side - major versions never overwrite each other, exactly like having 12c and 19c homes on the same server.

Everything installs under **/usr/edb/as16/** (binaries in `/usr/edb/as16/bin`). Hold that thought - directory anatomy is covered properly in Concepts 02.

---

## Version Semantics: 16.14 and What "Minor Update" Means

Our validated server reports itself as **PostgreSQL 16.14, EnterpriseDB Advanced Server 16.14.0**. Decode that:

- **16** is the major version. New major versions ship yearly with new features and require a real upgrade process (Module 08 territory).
- **.14** is the minor version, and it tracks community PostgreSQL exactly. When the PostgreSQL project releases 16.14 (bug fixes and security fixes only, no feature changes), EDB rebases EPAS on it, adds its Oracle-compatibility layer on top, and publishes EPAS 16.14.
- The trailing **.0** is EDB's own build number for that minor release, used if EDB needs to re-cut a build for an EPAS-specific fix.

This is a genuinely different patching philosophy from Oracle:

| | Oracle RU | EPAS minor release |
|:--|:----------|:-------------------|
| Cadence | Quarterly (Jan/Apr/Jul/Oct) | Quarterly, following community PostgreSQL (Feb/May/Aug/Nov) |
| Content | Bug fixes + security + sometimes features | Bug fixes + security only, never features |
| Delivery | Multi-GB patch zip from MOS | Updated RPMs in the repo |
| Apply | `opatch apply` + `datapatch`, careful conflict analysis | `sudo dnf update 'edb-as16*'` + service restart |
| Rollback | `opatch rollback` | `dnf downgrade` (rarely needed - minors are low-risk) |
| On-disk format | Can change dictionary | Never changes within a major version |

The last row is the important one. Within major version 16, the on-disk data format is frozen. Updating 16.14 to 16.15 swaps binaries and restarts the service - your data directory is untouched and immediately compatible. That is why there is no `datapatch` equivalent: there is no dictionary to patch, because minor releases are forbidden from changing it.

---

## Why There Is No OPatch, and What That Means Operationally

The question every Oracle DBA asks at this point: "OK, but where is the patch tool?" There is none, and here is why that is a feature.

OPatch exists because Oracle patches *files inside an existing ORACLE_HOME* - it surgically replaces individual libraries and binaries, tracks what it changed in an inventory, and handles conflicts between overlapping patches. That model requires a dedicated tool, an inventory, conflict analysis, and `datapatch` to reconcile the data dictionary with the new binaries.

The RPM model replaces whole packages atomically. A minor update is not "patch the home" - it is "install the new version of every package over the old one." The RPM database *is* your inventory. There are no one-off patches, no merge patches, no conflict checking, because there is only ever one build of 16.14 for your platform.

Operationally, patching an EPAS server at Mastercard looks like this (conceptually - do not run this yet):

1. `sudo dnf update 'edb-as16*'` - swaps the binaries
2. `sudo systemctl restart edb-as-16` - the running postmaster restarts on the new binaries
3. Done. Total downtime: one service restart, typically seconds.

Compare with an Oracle RU: stage the patch, check OPatch version, run conflict analysis, stop services, `opatch apply` (20-40 minutes), start the database, run `datapatch`, verify `dba_registry_sqlpatch`. The EPAS equivalent is a two-command change ticket.

What you give up: fine-grained one-off fixes. If you hit a bug in EPAS 16.14, you cannot get "just that fix" as an interim patch on top of 16.14 - you wait for 16.15 (or EDB cuts a new build, e.g. 16.14.1). In practice PostgreSQL minor releases are so low-risk that shops apply them far more promptly than Oracle shops apply RUs, so you are usually *less* exposed, not more.

One real gotcha for the CardAuth fleet mindset: because `dnf update` on a box will happily update EPAS along with everything else, production servers need version pinning discipline (dnf `versionlock` or excluding `edb-as16*` from unattended updates) so a routine OS patching run does not restart your database at 2 PM on a Tuesday. Same instinct as never letting anyone touch ORACLE_HOME outside a change window - just enforced with different tooling.

---

## The enterprisedb OS User

One more thing the RPM install does silently, and it will bite you if you miss it: it creates a dedicated OS user named **enterprisedb**. Not `postgres`. From our validated server:

Expected output (yours will differ):

```
uid=996(enterprisedb) gid=995(enterprisedb) groups=995(enterprisedb)
enterprisedb:x:996:995:EDBAS User:/var/lib/edb:/bin/bash
```

Read that passwd line: system UID 996, home directory `/var/lib/edb`, real bash shell. This user is the EPAS equivalent of the `oracle` OS user:

- The postmaster process runs as `enterprisedb`
- The data directory is owned by `enterprisedb`
- Local admin work is done by switching to this user: `sudo su - enterprisedb`
- It has no password - you reach it only via sudo, which is good security posture

The trap for people coming from community PostgreSQL tutorials (and half the blog posts you will Google): they all say `sudo su - postgres`. On an EPAS server there is no `postgres` OS user at all. Files created as `postgres`, cron jobs under `postgres`, SSH keys for `postgres` - all wrong on EPAS. Retrain the muscle memory now: **enterprisedb is your oracle user**.

---

## Oracle-to-EPAS Mapping: Software Lifecycle

Your reference table for this document. Add it to the Module 01 reference card.

| Concern | Oracle | EPAS |
|:--------|:-------|:-----|
| Software source | My Oracle Support downloads | EDB dnf repos (Cloudsmith, token-gated) |
| Entitlement proof | CSI number / MOS login | Repo token in the URL |
| Install tool | runInstaller / gold image | `dnf install edb-as16-server ...` |
| Patch tool | OPatch + datapatch | `dnf update` + service restart |
| Patch cadence | Quarterly RUs | Quarterly minors tracking community PostgreSQL |
| Patch inventory | `opatch lsinventory` | `rpm -qa 'edb-as16*'` |
| Software integrity | Manual checksums | GPG signatures, verified automatically by dnf |
| OS user | `oracle` | `enterprisedb` (uid 996, home /var/lib/edb) |
| Binaries location | `$ORACLE_HOME/bin` | `/usr/edb/as16/bin` |
| Side-by-side versions | Multiple ORACLE_HOMEs | Separate `edb-asNN` package families |

Next up: Concepts 02, where the packages you just learned about actually become a running database - `initdb`, the data directory, and the one decision you can never take back.

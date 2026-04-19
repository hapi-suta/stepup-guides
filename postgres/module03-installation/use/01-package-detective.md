# Exercise 01 - Package Detective

**Time estimate:** 20-25 minutes
**Prerequisites:** BUILD phase complete - CentOS Stream 9 with PostgreSQL 16 (RPM) running on port 5432, PostgreSQL 15 (RPM) running on port 5433, source-compiled PG at `/opt/pg-src/bin/`. PGDATA at `/opt/pgsql/data`. Database `labdb` exists. Extensions installed: pg_stat_statements, pgcrypto, pg_trgm, pageinspect.

---

## Scenario

Your manager asks you to audit the PostgreSQL installation on a new server you have inherited. You need to document exactly what is installed, how it was installed, where everything lives, and how the service is configured - before making any changes.

---

## Step 1 - Determine the Running PostgreSQL Version

Log in to your server as `ec2-user` and check which version of PostgreSQL is actively running.

Switch to the postgres user:

```bash
sudo -iu postgres
```

Ask the running server for its version:

```bash
psql -c "SELECT version();"
```

**Expected:**

```
                                                version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

This tells you the major version (16), minor version, CPU architecture (x86_64), and compiler used. The "compiled by gcc" line confirms this was built from C source code - either by the RPM packager or by you.

Now check the server version using the command-line flag. This does not require a running server:

```bash
/usr/pgsql-16/bin/postgres --version
```

**Expected:**

```
postgres (PostgreSQL) 16.x
```

Exit the postgres user:

```bash
exit
```

> **Concept: Server Version vs. Client Version**
> The `postgres --version` command checks the server binary's version. The `psql --version` command checks the client binary's version. In most setups they match, but on jump boxes or application servers you might have a PG16 psql client connecting to a PG15 server. The `SELECT version()` query always shows the server's version regardless of which client you use.

---

## Step 2 - Determine How PostgreSQL Was Installed

Check whether the running PostgreSQL was installed from RPM packages or compiled from source. The `rpm -q` command queries the RPM database for a specific package:

```bash
rpm -q postgresql16-server
```

**Expected:**

```
postgresql16-server-16.x-1PGDG.rhel9.x86_64
```

If this returns a version string, PostgreSQL was installed from an RPM package. If it says "package is not installed", it was likely compiled from source.

List all installed PostgreSQL packages. The `grep` command filters the output to show only lines containing "postgres":

```bash
dnf list installed | grep postgres
```

**Expected:**

```
postgresql15.x86_64              15.x-1PGDG.rhel9    @pgdg15
postgresql15-server.x86_64       15.x-1PGDG.rhel9    @pgdg15
postgresql16.x86_64              16.x-1PGDG.rhel9    @pgdg16
postgresql16-contrib.x86_64      16.x-1PGDG.rhel9    @pgdg16
postgresql16-libs.x86_64         16.x-1PGDG.rhel9    @pgdg16
postgresql16-server.x86_64       16.x-1PGDG.rhel9    @pgdg16
```

The `@pgdg16` column tells you which repository each package came from. This confirms PGDG RPMs, not the CentOS AppStream module.

Now check for the source-compiled installation:

```bash
ls /opt/pg-src/bin/postgres
```

**Expected:**

```
/opt/pg-src/bin/postgres
```

This file exists because you compiled PostgreSQL from source in Build Guide 03. The RPM packages do not install anything under `/opt/pg-src/`.

```bash
/opt/pg-src/bin/postgres --version
```

**Expected:**

```
postgres (PostgreSQL) 16.8
```

> **Concept: RPM vs. Source Identification**
> The fastest way to determine how PostgreSQL was installed is `rpm -q postgresql16-server`. If RPM knows about the package, it was installed via RPM. Source-compiled binaries are invisible to the RPM database. In production, you might also find PostgreSQL installed via container images (Docker) or configuration management tools (Ansible) - always check the process arguments with `ps aux | grep postgres` to find the actual binary path.

---

## Step 3 - Map All Binaries, Config Files, and Data Directories

Find where the PG16 RPM placed its binaries. The `rpm -ql` command lists every file that belongs to a package. The `grep bin` filter shows only lines containing "bin":

```bash
rpm -ql postgresql16-server | grep bin
```

**Expected:**

```
/usr/pgsql-16/bin/initdb
/usr/pgsql-16/bin/pg_basebackup
/usr/pgsql-16/bin/pg_controldata
/usr/pgsql-16/bin/pg_ctl
/usr/pgsql-16/bin/pg_resetwal
/usr/pgsql-16/bin/pg_rewind
/usr/pgsql-16/bin/pg_upgrade
/usr/pgsql-16/bin/pg_verifybackup
/usr/pgsql-16/bin/postgres
/usr/pgsql-16/bin/postmaster
```

Now check the client tools package:

```bash
rpm -ql postgresql16 | grep bin
```

**Expected:**

```
/usr/pgsql-16/bin/clusterdb
/usr/pgsql-16/bin/createdb
/usr/pgsql-16/bin/createuser
/usr/pgsql-16/bin/dropdb
/usr/pgsql-16/bin/dropuser
/usr/pgsql-16/bin/pg_dump
/usr/pgsql-16/bin/pg_dumpall
/usr/pgsql-16/bin/pg_isready
/usr/pgsql-16/bin/pg_restore
/usr/pgsql-16/bin/psql
/usr/pgsql-16/bin/reindexdb
/usr/pgsql-16/bin/vacuumdb
```

Find the active configuration files. Switch to the postgres user:

```bash
sudo -iu postgres
```

Query the running server for its configuration file locations:

```bash
psql -c "SHOW config_file;"
```

**Expected:**

```
           config_file
---------------------------------
 /opt/pgsql/data/postgresql.conf
(1 row)
```

```bash
psql -c "SHOW hba_file;"
```

**Expected:**

```
          hba_file
-----------------------------
 /opt/pgsql/data/pg_hba.conf
(1 row)
```

```bash
psql -c "SHOW data_directory;"
```

**Expected:**

```
  data_directory
-----------------
 /opt/pgsql/data
(1 row)
```

Exit the postgres user:

```bash
exit
```

> **Concept: Always Query the Running Server**
> Never assume you know where the config files are by looking at the filesystem. The systemd service might override PGDATA, or someone might have started PostgreSQL with a `-D` flag pointing to a non-default location. `SHOW config_file`, `SHOW hba_file`, and `SHOW data_directory` always tell you the truth because they read from the running server's memory.

---

## Step 4 - Check the PGDG Repository Configuration

Switch to root to inspect system-level files:

```bash
sudo su -
```

Check which PGDG repositories are enabled:

```bash
dnf repolist | grep pgdg
```

**Expected:**

```
pgdg-common         PostgreSQL common RPMs for RHEL / CentOS 9 - x86_64
pgdg15              PostgreSQL 15 for RHEL / CentOS 9 - x86_64
pgdg16              PostgreSQL 16 for RHEL / CentOS 9 - x86_64
```

Check what other PostgreSQL versions are available for installation. This searches the PGDG repository for server packages you have not installed yet:

```bash
dnf list available | grep postgresql | grep server
```

**Expected (partial):**

```
postgresql12-server.x86_64       12.x-xPGDG.rhel9    pgdg12
postgresql13-server.x86_64       13.x-xPGDG.rhel9    pgdg13
postgresql14-server.x86_64       14.x-xPGDG.rhel9    pgdg14
postgresql17-server.x86_64       17.x-xPGDG.rhel9    pgdg17
```

These are additional versions you could install alongside your existing PG15 and PG16 without any conflicts.

Exit the root session:

```bash
exit
```

---

## Step 5 - Verify the Systemd Service Configuration

Check the service status:

```bash
sudo systemctl status postgresql-16
```

**Expected (key lines):**

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; ...)
     Active: active (running) since ...
   Main PID: 1234 (postgres)
```

Confirm the service is enabled for auto-start on boot. The `is-enabled` subcommand returns a single word:

```bash
sudo systemctl is-enabled postgresql-16
```

**Expected:**

```
enabled
```

View the full service unit file to understand how PostgreSQL starts:

```bash
sudo systemctl cat postgresql-16
```

**Expected (key lines):**

```
[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/opt/pgsql/data/
ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}
```

If you see an override file at the top of the output, that means someone (or the Build phase) customized the PGDATA path.

Check whether a systemd drop-in override exists:

```bash
ls /etc/systemd/system/postgresql-16.service.d/ 2>/dev/null
```

**Expected (if an override exists):**

```
override.conf
```

> **Concept: The Audit Trail**
> When inheriting a server, your audit should answer these questions: (1) What version is running? (2) How was it installed? (3) Where are the binaries, configs, and data? (4) What repository provides updates? (5) How does the service start? With this information documented, you can safely plan upgrades, troubleshoot startup failures, and hand off to another DBA.

---

## Step 6 - Compile Your Audit Report

Based on everything you discovered, fill in this table. This is the kind of documentation you would hand to your manager or put in a runbook:

| Item | Value |
|------|-------|
| PostgreSQL version | (from `SELECT version()`) |
| Installation method | RPM (PGDG) |
| Server packages | postgresql16-server, postgresql16, postgresql16-libs, postgresql16-contrib |
| Binary path | `/usr/pgsql-16/bin/` |
| Data directory | `/opt/pgsql/data` |
| Config file | `/opt/pgsql/data/postgresql.conf` |
| HBA file | `/opt/pgsql/data/pg_hba.conf` |
| Port | 5432 |
| Systemd service | postgresql-16 (enabled, active) |
| PGDG repo | pgdg16 (enabled) |
| Other versions installed | PG15 on port 5433 |
| Source build present | Yes, at `/opt/pg-src/bin/` |
| Available for install | PG12, PG13, PG14, PG17 |

---

## Checkpoint

Before moving on, confirm you can:

- [ ] Determine the running PG version using both `postgres --version` and `SELECT version()`
- [ ] Distinguish an RPM install from a source install using `rpm -q`
- [ ] Find all installed PG packages with `dnf list installed | grep postgres`
- [ ] Locate the active config files by querying the running server with `SHOW`
- [ ] Check which PGDG repos are enabled with `dnf repolist`
- [ ] Read the systemd service unit with `systemctl cat`
- [ ] Check for systemd drop-in overrides

---

**Next:** Exercise 02 - Multi-Version Management

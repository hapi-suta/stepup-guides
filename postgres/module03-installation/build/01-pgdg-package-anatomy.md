# Module 03 - PostgreSQL Installation
## Guide 01: PGDG Repository and Package Anatomy

**Objective:** Reverse-engineer how PostgreSQL 16 was installed on your CentOS Stream 9 server. You will explore the PGDG repository, installed packages, file layout, systemd service, and version tools - all without installing anything new.

**Time:** 20-25 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- PostgreSQL 16 is already installed via PGDG RPMs

---

## 1. Explore the PGDG Repository Configuration

The PostgreSQL Global Development Group (PGDG) publishes official RPM packages through their own Yum repository. Your server already has this repository configured. Let's look at it.

Log in to your server as `ec2-user`:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Switch to the root user. You need root to inspect system-level repository files:

```bash
sudo su -
```

List the repo files in the Yum configuration directory. This shows every repository source your system knows about:

```bash
ls /etc/yum.repos.d/
```

Expected output:

```
centos-addons.repo  centos.repo  pgdg-redhat-all.repo
```

The file `pgdg-redhat-all.repo` is the one PGDG added. Display its contents:

```bash
cat /etc/yum.repos.d/pgdg-redhat-all.repo
```

Expected output (abbreviated - yours will be longer):

```
[pgdg-common]
name=PostgreSQL common RPMs for RHEL / CentOS $releasever - $basearch
baseurl=https://download.postgresql.org/pub/repos/yum/common/redhat/rhel-$releasever-$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
...

[pgdg16]
name=PostgreSQL 16 for RHEL / CentOS $releasever - $basearch
baseurl=https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-$releasever-$basearch
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
...
```

> **Concept: What is a Yum repository file?**
> A `.repo` file tells `dnf` (the package manager) where to download software from. Each `[section]` is a separate repository. The `baseurl` is the download URL. The `$releasever` and `$basearch` variables get replaced with your OS version (9) and CPU architecture (x86_64) automatically.

Notice the `gpgcheck=1` line. This tells `dnf` to verify every downloaded package was cryptographically signed by PGDG. This prevents tampered packages from being installed.

Check which PGDG repositories are enabled on your system. The `-v` flag shows verbose output including the repo URL:

```bash
dnf repolist -v | grep -i pgdg
```

Expected output:

```
Repo-id            : pgdg-common
Repo-name          : PostgreSQL common RPMs for RHEL / CentOS 9 - x86_64
...
Repo-id            : pgdg16
Repo-name          : PostgreSQL 16 for RHEL / CentOS 9 - x86_64
```

> **Concept: Why not use the CentOS built-in PostgreSQL packages?**
> CentOS ships an older PostgreSQL version (usually 13 or 15) through the `AppStream` module. PGDG provides the latest versions (12 through 17+) and publishes updates faster. In production, you almost always want the PGDG repo for access to the newest features and security patches.

---

## 2. List Installed PostgreSQL Packages

Now see which PostgreSQL packages are actually installed on this server. The `dnf list installed` command shows all installed packages, and we filter for `postgres`:

```bash
dnf list installed | grep postgres
```

Expected output:

```
postgresql16.x86_64              16.x-1PGDG.rhel9    @pgdg16
postgresql16-contrib.x86_64      16.x-1PGDG.rhel9    @pgdg16
postgresql16-libs.x86_64         16.x-1PGDG.rhel9    @pgdg16
postgresql16-server.x86_64       16.x-1PGDG.rhel9    @pgdg16
```

Here is what each package provides:

| Package | Purpose |
|---------|---------|
| `postgresql16` | Client tools: `psql`, `pg_dump`, `pg_restore`, `createdb`, etc. |
| `postgresql16-server` | The PostgreSQL server daemon (`postgres`), `initdb`, `pg_ctl`, `pg_basebackup` |
| `postgresql16-libs` | Shared libraries (`libpq`) that client applications link against |
| `postgresql16-contrib` | Extra modules: `pg_stat_statements`, `pgcrypto`, `pg_trgm`, and more |

Get more detail on a specific package. The `dnf info` command shows the description, size, and which repository it came from:

```bash
dnf info postgresql16-server
```

Expected output (abbreviated):

```
Name         : postgresql16-server
Version      : 16.x
Release      : 1PGDG.rhel9
Architecture : x86_64
Size         : 22 M
Source        : postgresql16-16.x-1PGDG.rhel9.src.rpm
Repository   : @System
From repo    : pgdg16
Summary      : The programs needed to create and run a PostgreSQL server
```

> **Concept: Server vs. Client packages**
> You can install `postgresql16` (client only) on a jump box or application server without installing `postgresql16-server`. This gives you `psql` and `pg_dump` without running a full database server. In production, only the database servers need the `-server` package.

---

## 3. Understand the RPM File Layout

Each RPM package places files in specific directories. Let's see exactly where `postgresql16-server` put its files. The `rpm -ql` command lists every file a package installed. The `-q` means query, the `-l` means list files:

```bash
rpm -ql postgresql16-server | head -30
```

Expected output (abbreviated):

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
/usr/pgsql-16/lib/...
/usr/pgsql-16/share/...
```

The `head -30` flag limits the output to the first 30 lines so you can see the pattern without flooding your terminal.

Now list just the binary files. The `grep bin` filter shows only lines containing "bin":

```bash
rpm -ql postgresql16-server | grep bin
```

Expected output:

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

Now check where the client package put its binaries:

```bash
rpm -ql postgresql16 | grep bin
```

Expected output:

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

List the binaries in that directory directly to see them all together:

```bash
ls /usr/pgsql-16/bin/
```

> **Concept: The /usr/pgsql-16/ prefix**
> PGDG installs everything under `/usr/pgsql-16/` (a version-specific prefix). This is intentional - it lets you install PostgreSQL 15 and 16 side by side on the same server without file conflicts. Each version gets its own directory tree: `bin/`, `lib/`, `share/`.

Check the library directory. These are shared libraries that PostgreSQL and extensions need at runtime:

```bash
ls /usr/pgsql-16/lib/
```

Check the contrib extensions directory. These are SQL scripts and shared objects for the extra modules:

```bash
ls /usr/pgsql-16/share/extension/ | head -20
```

Expected output (abbreviated):

```
pg_stat_statements--1.10--1.11.sql
pg_stat_statements--1.10.sql
pg_stat_statements.control
pgcrypto--1.3.sql
pgcrypto.control
pg_trgm--1.6.sql
pg_trgm.control
...
```

Count how many extensions are available. The `wc -l` flag counts the number of lines:

```bash
ls /usr/pgsql-16/share/extension/*.control | wc -l
```

---

## 4. Explore the Systemd Service Unit

PostgreSQL 16 runs as a systemd service called `postgresql-16`. Let's look at how it is configured. The `systemctl cat` command shows the full service unit file:

```bash
systemctl cat postgresql-16
```

Expected output:

```
# /usr/lib/systemd/system/postgresql-16.service
[Unit]
Description=PostgreSQL 16 database server
Documentation=https://www.postgresql.org/docs/16/static/
After=syslog.target
After=network-online.target

[Service]
Type=notify
User=postgres
Group=postgres
Environment=PGDATA=/var/lib/pgsql/16/data/
OOMScoreAdjust=-1000
ExecStartPre=/usr/pgsql-16/bin/postgresql-16-check-db-dir ${PGDATA}
ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}
ExecReload=/bin/kill -HUP $MAINPID
KillMode=mixed
KillSignal=SIGINT
TimeoutSec=infinity

[Install]
WantedBy=multi-user.target

# /etc/systemd/system/postgresql-16.service.d/override.conf
[Service]
Environment=PGDATA=/opt/pgsql/data
```

`systemctl cat` prints the shipped unit first, then any drop-in overrides beneath it. The shipped unit's `PGDATA` is the PGDG default `/var/lib/pgsql/16/data/`; the `override.conf` you created in Guide 00 changes it to `/opt/pgsql/data`. The last value wins, so this server runs from `/opt/pgsql/data`.

Key lines explained:

| Line | Meaning |
|------|---------|
| `User=postgres` | The server process runs as the `postgres` OS user, never as root |
| `Environment=PGDATA=...` | Sets the data directory path. This is the default - your lab overrides it |
| `ExecStart=/usr/pgsql-16/bin/postgres -D ${PGDATA}` | The actual command that starts the database server |
| `ExecReload=/bin/kill -HUP $MAINPID` | Sending SIGHUP to the main process reloads configuration without restart |
| `KillSignal=SIGINT` | A graceful shutdown uses SIGINT (smart shutdown), not SIGTERM |
| `OOMScoreAdjust=-1000` | Tells the Linux OOM killer to never kill PostgreSQL, even under memory pressure |
| `TimeoutSec=infinity` | Systemd will wait forever for PostgreSQL to start (large databases can take minutes) |

Check whether your lab overrides the default PGDATA. Service overrides live in a drop-in directory:

```bash
ls /etc/systemd/system/postgresql-16.service.d/ 2>/dev/null
```

If an override file exists, read it:

```bash
cat /etc/systemd/system/postgresql-16.service.d/override.conf 2>/dev/null
```

If your lab uses `/opt/pgsql/data`, you may see something like:

```
[Service]
Environment=PGDATA=/opt/pgsql/data
```

> **Concept: Systemd drop-in overrides**
> Never edit the original service file in `/usr/lib/systemd/system/` directly - a package update will overwrite your changes. Instead, create override files in `/etc/systemd/system/postgresql-16.service.d/`. Systemd merges them on top of the original. Use `systemctl edit postgresql-16` to create overrides safely.

Check the current status of the service:

```bash
systemctl status postgresql-16
```

Expected output (abbreviated):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled; ...)
     Active: active (running) since ...
   Main PID: 1234 (postgres)
     ...
```

The `enabled` means PostgreSQL will start automatically on server boot. The `active (running)` means it is running right now.

---

## 5. Understand the Alternatives System

CentOS uses the `alternatives` system to manage which version of a command `/usr/bin/psql` points to. This matters when you have multiple PostgreSQL versions installed.

Check how `psql` is managed:

```bash
alternatives --display pgsql-psql
```

Expected output:

```
pgsql-psql - status is auto.
 link currently points to /usr/pgsql-16/bin/psql
/usr/pgsql-16/bin/psql - priority 1600
Current `best' version is /usr/pgsql-16/bin/psql.
```

This means when you type `psql` without a full path, the system runs `/usr/pgsql-16/bin/psql`. The priority `1600` is derived from the version number. If you installed PG17, its priority would be `1700` and it would automatically become the default.

Verify the symlink chain. The `which` command shows what path your shell resolves for `psql`:

```bash
which psql
```

Expected output:

```
/usr/bin/psql
```

> On CentOS Stream, `/bin` is itself a symlink to `/usr/bin`, so `which` may print `/bin/psql` instead. That is the same file - do not worry about the `/bin` vs `/usr/bin` difference.

Now check what `/usr/bin/psql` actually points to. The `ls -la` shows the symlink target:

```bash
ls -la /usr/bin/psql
```

Expected output:

```
lrwxrwxrwx. 1 root root 28 ... /usr/bin/psql -> /etc/alternatives/pgsql-psql
```

Follow the chain one more level:

```bash
ls -la /etc/alternatives/pgsql-psql
```

Expected output:

```
lrwxrwxrwx. 1 root root 22 ... /etc/alternatives/pgsql-psql -> /usr/pgsql-16/bin/psql
```

> **Concept: Why alternatives matter for multi-version setups**
> If you install PG15 and PG16 on the same server, both provide a `psql` binary. The alternatives system decides which one `/usr/bin/psql` points to. You can always bypass it by using the full path: `/usr/pgsql-16/bin/psql` or `/usr/pgsql-15/bin/psql`.

---

## 6. Check the PostgreSQL Version and Build Options

Finally, check the installed version and how PostgreSQL was compiled. These commands work as any user, so you can stay as root.

Check the server version:

```bash
/usr/pgsql-16/bin/postgres --version
```

Expected output:

```
postgres (PostgreSQL) 16.x
```

Check the client version:

```bash
/usr/pgsql-16/bin/psql --version
```

Expected output:

```
psql (PostgreSQL) 16.x
```

Now look at the build configuration. The `pg_config` tool shows how PostgreSQL was compiled, including which features were enabled:

```bash
/usr/pgsql-16/bin/pg_config --configure
```

Expected output (one long line, abbreviated):

```
'--enable-rpath' '--prefix=/usr/pgsql-16' '--includedir=/usr/pgsql-16/include'
'--mandir=/usr/pgsql-16/share/man' '--datadir=/usr/pgsql-16/share'
'--with-icu' '--with-llvm' '--with-lz4' '--with-zstd' '--with-openssl'
'--with-pam' '--with-gssapi' '--with-ldap' '--with-systemd' '--with-libxml'
'--with-libxslt' '--with-uuid=e2fs' ...
```

Key build flags explained:

| Flag | Meaning |
|------|---------|
| `--prefix=/usr/pgsql-16` | Install location for all files |
| `--with-openssl` | SSL/TLS support is compiled in (required for encrypted connections) |
| `--with-llvm` | JIT compilation support using LLVM (speeds up complex queries) |
| `--with-lz4` | LZ4 compression support for WAL and TOAST data |
| `--with-zstd` | Zstandard compression support (better ratio than LZ4) |
| `--with-systemd` | Integration with systemd service manager |
| `--with-icu` | International Components for Unicode (proper collation sorting) |

View all `pg_config` output at once:

```bash
/usr/pgsql-16/bin/pg_config
```

This shows every path and setting - useful for troubleshooting when extensions fail to compile because they cannot find headers or libraries.

Exit the root session:

```bash
exit
```

---

## Checkpoint

You have completed Guide 01. Verify you understand the following:

- [ ] You can locate the PGDG repo file at `/etc/yum.repos.d/pgdg-redhat-all.repo`
- [ ] You know the four core packages: `postgresql16`, `postgresql16-server`, `postgresql16-libs`, `postgresql16-contrib`
- [ ] You know that PGDG installs everything under `/usr/pgsql-16/` (bin, lib, share)
- [ ] You can read the systemd service unit with `systemctl cat postgresql-16`
- [ ] You understand that `ExecStart` runs as the `postgres` user with a `PGDATA` environment variable
- [ ] You know the alternatives system links `/usr/bin/psql` to `/usr/pgsql-16/bin/psql`
- [ ] You can check build options with `pg_config --configure` (SSL, LLVM, LZ4 are compiled in)

---

Proceed to **Guide 02 - Multi-Version Installation**

# Module 03 - PostgreSQL Installation
## Guide 00: Installing PostgreSQL 16 on CentOS Stream 9

**Objective:** Install PostgreSQL 16 from scratch on a bare CentOS Stream 9 server using the official PGDG repository. By the end of this guide, you will have a running PostgreSQL 16 database you installed yourself.

**Time:** 30-40 minutes

**Prerequisites:**
- SSH access to your lab server as `ec2-user`
- Your server has NO PostgreSQL installed yet

---

## 1. Connect to Your Server

Open your terminal and connect to your lab server using SSH. Replace `[YOUR_SERVER_IP]` with the IP address from your welcome email:

```bash
ssh -i your-key.pem ec2-user@[YOUR_SERVER_IP]
```

Once connected, you will see a prompt that looks like this:

```
[ec2-user@pg-suta-lab-1 ~]$
```

This means you are logged in as the `ec2-user` on a server named `pg-suta-lab-1`.

---

## 2. Check Your Operating System

On **pg-suta-lab-1**, as **ec2-user**:

Before installing anything, confirm you are on the right operating system. This command shows which Linux distribution and version you are running:

```bash
cat /etc/centos-release
```

Expected output (yours will differ):

```
CentOS Stream release 9
```

Check your CPU architecture. PostgreSQL packages are built for specific architectures:

```bash
uname -m
```

Expected output:

```
x86_64
```

> **Why this matters:** You need to know your OS version and architecture to download the correct packages. PostgreSQL packages for CentOS 9 will not work on CentOS 8, and x86_64 packages will not work on ARM processors.

---

## 3. Check That PostgreSQL Is NOT Installed

On **pg-suta-lab-1**, as **ec2-user**:

Let's confirm there is no PostgreSQL on this server yet. This command searches installed packages for anything with "postgres" in the name:

```bash
sudo dnf list installed | grep -i postgres
```

Expected output:

```
(nothing - no output means no PostgreSQL packages are installed)
```

If you see nothing, that is correct. Your server is clean and ready.

> **What is dnf?** `dnf` is the package manager for CentOS Stream 9. It downloads, installs, updates, and removes software packages. Think of it like an app store for Linux, but you use it from the command line.

---

## 4. Install the PGDG Repository

On **pg-suta-lab-1**, as **ec2-user**:

Before you can install PostgreSQL, you need to tell your server where to download it from. The PostgreSQL Global Development Group (PGDG) maintains an official package repository with the latest versions.

Install the PGDG repository configuration package. This single command downloads and installs a small package that adds the PGDG download URLs to your system:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

Expected output (yours will differ):

```
...
Installed:
  pgdg-redhat-repo-42.0-64.rhel9PGDG.noarch

Complete!
```

The `-y` flag means "answer yes to all prompts automatically." Without it, `dnf` would ask you to confirm before installing.

> **Why not use the built-in CentOS packages?** CentOS ships an older PostgreSQL version through its AppStream module. PGDG provides the latest versions (12 through 17) and publishes security updates faster. In production, DBAs almost always use the PGDG repository.

---

## 5. Disable the Built-in PostgreSQL Module

On **pg-suta-lab-1**, as **ec2-user**:

CentOS has a built-in PostgreSQL module that can conflict with the PGDG packages. You need to disable it so your system uses the PGDG versions instead:

```bash
sudo dnf -qy module disable postgresql
```

Expected output (yours will differ):

```
Importing GPG key 0x08B40D20:
 Userid     : "PostgreSQL RPM Repository <pgsql-pkg-yum@lists.postgresql.org>"
 Fingerprint: D4BF 08AE 67A0 B4C7 A1DB CCD2 40BC A2B4 08B4 0D20
 From       : /etc/pki/rpm-gpg/PGDG-RPM-GPG-KEY-RHEL
...
```

You may see the GPG key import message repeated several times - that is normal. It is importing the signing key for each PGDG repository.

The `-q` flag means "quiet" (less output) and `-y` means "yes to all prompts."

> **What is a dnf module?** Modules are collections of packages that CentOS bundles together at a specific version. The `postgresql` module locks you to whatever version CentOS chose. Disabling it lets PGDG take over.

---

## 6. Install PostgreSQL 16 Packages

On **pg-suta-lab-1**, as **ec2-user**:

Now install the four core PostgreSQL 16 packages. This is the main installation command:

```bash
sudo dnf install -y postgresql16 postgresql16-server postgresql16-contrib postgresql16-libs
```

Expected output (yours will differ):

```
...
Installing:
 postgresql16            x86_64   16.14-2PGDG.rhel9.8   pgdg16   1.6 M
 postgresql16-contrib    x86_64   16.14-2PGDG.rhel9.8   pgdg16   696 k
 postgresql16-libs       x86_64   16.14-2PGDG.rhel9.8   pgdg16   282 k
 postgresql16-server     x86_64   16.14-2PGDG.rhel9.8   pgdg16   5.8 M
...
Complete!
```

Here is what each package gives you:

| Package | What It Provides |
|---------|-----------------|
| `postgresql16` | Client tools - `psql`, `pg_dump`, `pg_restore`, `createdb` |
| `postgresql16-server` | The database server itself - `postgres`, `initdb`, `pg_ctl`, `pg_basebackup` |
| `postgresql16-contrib` | Extra modules - `pg_stat_statements`, `pgcrypto`, `pg_trgm` |
| `postgresql16-libs` | Shared libraries that client applications need |

Verify the packages were installed. This searches your installed packages for anything starting with "postgresql16":

```bash
sudo dnf list installed | grep postgresql16
```

Expected output (yours will differ):

```
postgresql16.x86_64              16.14-2PGDG.rhel9.8    @pgdg16
postgresql16-contrib.x86_64      16.14-2PGDG.rhel9.8    @pgdg16
postgresql16-libs.x86_64         16.14-2PGDG.rhel9.8    @pgdg16
postgresql16-server.x86_64       16.14-2PGDG.rhel9.8    @pgdg16
```

Four packages - all installed from the `@pgdg16` repository. 

---

## 7. Check What the Installation Created

On **pg-suta-lab-1**, as **ec2-user**:

The installation automatically created a `postgres` OS user. This is the user that will own and run the database. Verify it exists:

```bash
id postgres
```

Expected output (yours will differ):

```
uid=26(postgres) gid=26(postgres) groups=26(postgres)
```

> **Your numbers may differ.** On a bare install the PGDG package creates the `postgres` user with uid/gid `26`. On some lab servers the `postgres` user already exists (created during server setup) and will show a different uid/gid - that is fine. What matters is that the `postgres` user exists.

Check where PostgreSQL binaries were installed. The `ls` command lists the contents of the binary directory:

```bash
ls /usr/pgsql-16/bin/ | head -10
```

Expected output (yours will differ):

```
clusterdb
createdb
createuser
dropdb
dropuser
initdb
oid2name
pg_amcheck
pg_archivecleanup
pg_basebackup
```

Verify the server binary is in place:

```bash
/usr/pgsql-16/bin/postgres --version
```

Expected output:

```
postgres (PostgreSQL) 16.14
```

> **Where did everything go?** PGDG installs all PostgreSQL files under `/usr/pgsql-16/`. This version-specific path lets you install multiple PostgreSQL versions (15, 16, 17) side by side without conflicts.

---

## 8. Initialize the Database

On **pg-suta-lab-1**, as **ec2-user**:

Installing the packages gives you the software, but it does NOT create a database yet. You need to run `initdb` to create the initial database cluster (the data directory with system catalogs, configuration files, and the default databases).

Run the official initialization script. This wrapper script runs `initdb` as the `postgres` user with the correct settings:

```bash
sudo -u postgres /usr/pgsql-16/bin/initdb -D /opt/pgsql/data
```

Expected output:

```
Initializing database ... OK
```

If you see `OK`, your database cluster was created successfully.

> **What did initdb do?** It created a directory at `/opt/pgsql/data/` containing:
> - `postgresql.conf` - the main configuration file (memory, connections, logging)
> - `pg_hba.conf` - the client authentication file (who can connect and how)
> - `base/` - the actual database files for `postgres`, `template0`, and `template1`
> - `pg_wal/` - the write-ahead log directory (crash recovery)

Verify the data directory was created:

```bash
sudo ls /opt/pgsql/data/
```

Expected output (yours will differ):

```
base          pg_commit_ts  pg_logical    pg_replslot   pg_stat      pg_tblspc    pg_wal                postgresql.conf
global        pg_dynshmem   pg_multixact  pg_serial     pg_stat_tmp  pg_twophase  pg_xact               postgresql.auto.conf
log           pg_ident.conf pg_notify     pg_snapshots  pg_subtrans  PG_VERSION   postmaster.opts
```

---

## 9. Point the Service at Your Data Directory

On **pg-suta-lab-1**, as **ec2-user**:

You initialized your cluster at `/opt/pgsql/data`, but the PostgreSQL service ships pointing at a different default location, `/var/lib/pgsql/16/data`. If you start it now, systemd would look in that empty default directory and the service would fail. Tell systemd where your data actually lives with a drop-in override.

First, create the override directory. The `-p` flag creates parent directories as needed and does not error if the directory already exists:

```bash
sudo mkdir -p /etc/systemd/system/postgresql-16.service.d
```

Now open a new override file with vi:

```bash
sudo vi /etc/systemd/system/postgresql-16.service.d/override.conf
```

vi opens an empty file. Press `i` to enter insert mode, then type these two lines exactly:

```
[Service]
Environment=PGDATA=/opt/pgsql/data
```

Press `Esc` to leave insert mode, then type `:wq` and press `Enter` to save and quit.

Confirm the file has the right contents:

```bash
cat /etc/systemd/system/postgresql-16.service.d/override.conf
```

Expected output:

```
[Service]
Environment=PGDATA=/opt/pgsql/data
```

Reload systemd so it picks up the override. You must do this whenever you change a unit file or one of its drop-ins:

```bash
sudo systemctl daemon-reload
```

No output means success.

> **Why a drop-in instead of editing the unit file?** The main unit at `/usr/lib/systemd/system/postgresql-16.service` is owned by the package - a future `dnf update` would overwrite your edits. A drop-in under `/etc/systemd/system/postgresql-16.service.d/` is yours: it survives upgrades and cleanly layers on top of the shipped unit.

---

## 10. Start PostgreSQL

On **pg-suta-lab-1**, as **ec2-user**:

Now start the PostgreSQL service. The `systemctl start` command tells systemd to launch the database server:

```bash
sudo systemctl start postgresql-16
```

No output means success. Verify it is running:

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
  postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; disabled; ...)
     Active: active (running) since ...
   Main PID: 1234 (postgres)
     ...
```

Look for two things:
- **Active: active (running)** - the server is up
- **Loaded: ... disabled** - this means it will NOT start automatically on reboot

Fix that. Enable the service so PostgreSQL starts automatically whenever the server reboots:

```bash
sudo systemctl enable postgresql-16
```

Expected output:

```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-16.service → /usr/lib/systemd/system/postgresql-16.service
```

> **start vs enable:** `start` launches the service right now. `enable` makes it launch automatically on every future boot. You almost always want both.

---

## 11. Connect to PostgreSQL

Your database is running. Let's connect to it.

On **pg-suta-lab-1**, as **ec2-user**:

Switch to the `postgres` OS user. This user was created during installation and is the database superuser:

```bash
sudo su - postgres
```

Your prompt changes to:

```
-bash-5.1$
```

Now launch `psql`, the PostgreSQL interactive terminal:

```bash
psql
```

Expected output:

```
psql (16.14)
Type "help" for help.

postgres=#
```

The `postgres=#` prompt means you are connected to the `postgres` database as the `postgres` superuser.

Run your first SQL query. This confirms the database server is responding:

```bash
SELECT version();
```

Expected output (yours will differ):

```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.14 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.5.0 20240719 (Red Hat 11.5.0-14), 64-bit
(1 row)
```

Congratulations - you installed PostgreSQL 16 from scratch and it is running.

Check which databases exist. The `\l` command lists all databases:

```bash
\l
```

Expected output (yours will differ):

```
                                                  List of databases
   Name    |  Owner   | Encoding | Locale Provider |   Collate   |    Ctype    | ...
-----------+----------+----------+-----------------+-------------+-------------+----
 postgres  | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 | ...
 template0 | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 | ...
 template1 | postgres | UTF8     | libc            | en_US.UTF-8 | en_US.UTF-8 | ...
(3 rows)
```

These three databases are created automatically by `initdb`:
- **postgres** - the default database for connections
- **template0** - a pristine template that is never modified
- **template1** - the template used when you create new databases

Exit psql:

```bash
\q
```

Exit the postgres user session and go back to ec2-user:

```bash
exit
```

---

## Checkpoint

You have completed Guide 00. Verify you understand the following:

- [ ] You installed the PGDG repository to get official PostgreSQL packages
- [ ] You disabled the built-in CentOS PostgreSQL module to avoid conflicts
- [ ] You installed four packages: `postgresql16`, `postgresql16-server`, `postgresql16-contrib`, `postgresql16-libs`
- [ ] You know that installing packages does NOT create a database - you must run `initdb`
- [ ] You ran `initdb -D /opt/pgsql/data` to create the data directory at `/opt/pgsql/data/`
- [ ] You started the service with `systemctl start` and enabled it with `systemctl enable`
- [ ] You connected with `psql` as the `postgres` user and ran `SELECT version()`

---

Proceed to **Guide 01 - PGDG Repository and Package Anatomy**

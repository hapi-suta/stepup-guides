# Build 02: PostgreSQL Installation (CentOS Stream 9)

Install PostgreSQL 16 from the official PGDG yum repository.

NODE1 gets the full server installation. NODE2 gets the client package only (the server will be replaced by a clone of NODE1 in the next guide).

---

## Connecting to your servers

Open two terminal windows (or two MobaXterm tabs). Connect to each server:

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE1_IP]
```

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE2_IP]
```

---

## Part A: Run on BOTH servers

### 1. Add the PGDG yum repository

CentOS Stream 9 ships with an older PostgreSQL in its default repos. The PGDG repo gives you the latest version maintained by the PostgreSQL core team.

First, disable the built-in PostgreSQL module. CentOS Stream 9 uses DNF modules that can block installing from external repos. This step removes that conflict:

```bash
sudo dnf -qy module disable postgresql
```

`-q` runs quietly (less output). `-y` answers yes automatically. `module disable postgresql` prevents the OS's bundled PostgreSQL from interfering.

Now install the PGDG repo RPM. This adds the repo configuration to your system:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

`dnf install -y` downloads and installs the RPM at that URL. The `-y` skips the confirmation prompt.

Expected output (yours will differ):

```
Last metadata expiration check: ...
pgdg-redhat-repo-latest.noarch.rpm    22 kB/s |  14 kB     00:00
...
Installed:
  pgdg-redhat-repo-42.0-37.noarch
Complete!
```

> **Concept - Why PGDG, not the OS default**: CentOS ships older PostgreSQL versions that lag behind security patches and new features. The PGDG (PostgreSQL Global Development Group) repo tracks every minor release within days of release. Always use PGDG in production.

---

## Part B: NODE1 only - Install the server

### 2. Install PostgreSQL 16 server

Run on NODE1:

```bash
sudo dnf install -y postgresql16-server postgresql16-contrib
```

- `postgresql16-server` - the database engine and server binaries
- `postgresql16-contrib` - extra modules (pg_stat_statements, pg_rewind, etc.)

Expected output (yours will differ):

```
...
Installed:
  postgresql16-16.x-1PGDG.rhel9.x86_64
  postgresql16-server-16.x-1PGDG.rhel9.x86_64
  postgresql16-contrib-16.x-1PGDG.rhel9.x86_64
Complete!
```

### 3. Initialize the database cluster

On CentOS/RHEL, PostgreSQL does NOT auto-initialize the data directory after install. You must run `initdb` manually. This creates the initial cluster files (system catalogs, default config, pg_hba.conf):

Run on NODE1:

```bash
sudo /usr/pgsql-16/bin/postgresql-16-setup initdb
```

`postgresql-16-setup initdb` is the PGDG helper script that runs `initdb` with the correct settings for the CentOS package layout. It creates the data directory at `/var/lib/pgsql/16/data`.

Expected output:

```
Initializing database ... OK
```

### 4. Enable and start the PostgreSQL service

Enable the service so it starts automatically after a reboot:

```bash
sudo systemctl enable postgresql-16
```

Start the service now:

```bash
sudo systemctl start postgresql-16
```

The service name on PGDG CentOS packages is `postgresql-16` (not `postgresql`).

Check the service is running:

```bash
sudo systemctl status postgresql-16
```

Expected output (yours will differ):

```
* postgresql-16.service - PostgreSQL 16 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled)
     Active: active (running) since ...
```

The `active (running)` line confirms success.

### 5. Verify with psql

Switch to the postgres operating system user:

```bash
sudo -iu postgres
```

Your prompt will change to `[postgres@pg-primary ~]$`. Now connect to the database:

```bash
psql -c "SELECT version();"
```

Expected output:

```
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x ..., 64-bit
(1 row)
```

### 6. Add PG binaries to the postgres user's PATH

By default, the postgres user does not have `/usr/pgsql-16/bin/` in its PATH. Add it permanently to its `.bash_profile` so commands like `psql`, `pg_basebackup`, and `pg_ctl` work without typing the full path.

Still as the postgres user, open the profile file:

```bash
vi ~/.bash_profile
```

Add this line at the end of the file:

```
export PATH=/usr/pgsql-16/bin:$PATH
```

In vi: press `G` to jump to the end of the file, then `o` to open a new line below and enter insert mode. Type the line above. Press `Esc`, then type `:wq` and press Enter to save and quit.

Reload the profile so the change takes effect right now:

```bash
source ~/.bash_profile
```

Verify PATH is updated:

```bash
which psql
```

Expected output:

```
/usr/pgsql-16/bin/psql
```

### 7. Verify the data directory

Still as the postgres user:

```bash
psql -c "SHOW data_directory;"
```

Expected output:

```
       data_directory
-----------------------------
 /var/lib/pgsql/16/data
(1 row)
```

List the data directory contents:

```bash
ls -la /var/lib/pgsql/16/data/
```

Expected output (yours will differ):

```
total 60
drwx------. 19 postgres postgres 4096 May 15 14:00 .
drwx------.  4 postgres postgres   51 May 15 13:58 ..
-rw-------.  1 postgres postgres    3 May 15 13:58 PG_VERSION
drwx------.  5 postgres postgres   41 May 15 13:58 base
drwx------.  2 postgres postgres 4096 May 15 13:58 global
drwx------.  2 postgres postgres    6 May 15 13:58 pg_commit_ts
...
drwx------.  3 postgres postgres   60 May 15 14:00 pg_wal
```

You should see `PG_VERSION`, `base/`, `pg_wal/`, and other standard PostgreSQL directories.

> **Concept - Config files live inside PGDATA on CentOS**: Unlike Debian/Ubuntu which keeps config under `/etc/postgresql/`, on CentOS Stream 9 with PGDG packages the config files (`postgresql.conf`, `pg_hba.conf`) live inside PGDATA at `/var/lib/pgsql/16/data/`. There is no separate config directory to remember.

Exit back to ec2-user:

```bash
exit
```

---

## Part C: NODE2 only - Install the client

NODE2 will eventually be a standby server. Its data directory will be fully replaced by a clone of the primary in guide 04. You only need the client package and binary tools on NODE2 for now.

### 8. Install PostgreSQL 16 client on NODE2

Run on NODE2:

```bash
sudo dnf install -y postgresql16 postgresql16-server
```

- `postgresql16` - the psql client and shared libraries
- `postgresql16-server` - needed for pg_basebackup binary

Do NOT run initdb or start the service on NODE2 yet. The data directory will be populated in guide 04.

Add PG binaries to the postgres user's PATH on NODE2 as well. First switch to postgres:

```bash
sudo -iu postgres
```

```bash
vi ~/.bash_profile
```

Add at the end:

```
export PATH=/usr/pgsql-16/bin:$PATH
```

Save and quit vi: press `Esc`, then `:wq`, then Enter.

Reload the profile:

```bash
source ~/.bash_profile
```

Verify:

```bash
which pg_basebackup
```

Expected output:

```
/usr/pgsql-16/bin/pg_basebackup
```

Exit back to ec2-user:

```bash
exit
```

---

## Checkpoint

NODE1 has:
- [x] PGDG yum repo added
- [x] Built-in postgresql module disabled
- [x] `postgresql16-server` and `postgresql16-contrib` installed
- [x] Database cluster initialized (`initdb` complete)
- [x] `postgresql-16` service enabled and running
- [x] `psql` returns PostgreSQL 16.x version
- [x] PGDATA at `/var/lib/pgsql/16/data`
- [x] `/usr/pgsql-16/bin` in postgres user's PATH

NODE2 has:
- [x] PGDG yum repo added
- [x] Built-in postgresql module disabled
- [x] `postgresql16` and `postgresql16-server` packages installed (no initdb yet)
- [x] `/usr/pgsql-16/bin` in postgres user's PATH

Proceed to `03-configure-primary.md`.

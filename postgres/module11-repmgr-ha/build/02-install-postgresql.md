# Build 02: Install PostgreSQL 16 (CentOS Stream 9)

Install PostgreSQL 16 from the official PGDG repository on all four nodes.

Run every step on **ALL FOUR servers** as **root**. If your prompt does not show `root@`, run `sudo su -` first.

---

## 1. Add the PGDG repository

Install the PGDG RPM for CentOS/RHEL 9:

```bash
dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

This adds the official PostgreSQL repository to your system.

Disable the built-in PostgreSQL module so it does not conflict with PGDG:

```bash
dnf -qy module disable postgresql
```

`-q` suppresses unnecessary output. `-y` auto-confirms.

Expected output (yours will differ):
```
Complete!
```

> **Concept - Why PGDG, not the OS default**: CentOS ships an older PostgreSQL version
> that lags behind features and security patches. The PGDG repo is maintained by the
> PostgreSQL core team and tracks every minor release within days. Always use PGDG
> in production.

## 2. Install PostgreSQL 16

```bash
dnf install -y postgresql16-server postgresql16-contrib
```

`postgresql16-server` installs the database server. `postgresql16-contrib` installs extra modules and extensions (including utilities needed by repmgr).

Expected output (yours will differ):
```
Complete!
```

## 3. Initialize the database cluster

On CentOS, PostgreSQL does not auto-initialize after install. You must run initdb:

```bash
sudo -u postgres /usr/pgsql-16/bin/initdb -D /opt/pgsql/data --waldir=/opt/pgsql/wal --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):
```
Initializing database ... OK
```

> **Concept - initdb creates the data directory**: This creates the cluster at
> `/opt/pgsql/data/` with default settings, the `postgres` superuser,
> and the template databases. On Debian/Ubuntu this happens automatically during
> package install, but on Red Hat systems you must do it explicitly.

## 4. Start and enable the service

Start PostgreSQL:

```bash
systemctl start postgresql-16
```

Enable it to start on boot:

```bash
systemctl enable postgresql-16
```

Expected output (yours will differ):
```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-16.service ...
```

> **Important**: On CentOS, the service name is `postgresql-16`, NOT `postgresql`.
> This is different from Debian/Ubuntu where the service is just `postgresql`.

## 5. Verify PostgreSQL is running

```bash
systemctl status postgresql-16
```

Expected: `active (running)`.

Switch to the postgres user:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -c "SELECT version();"
```

Expected output (yours will differ):
```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.x.x, 64-bit
(1 row)
```

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

## 6. Confirm the data directory

Switch to the postgres user:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -c "SHOW data_directory;"
```

Expected: `/opt/pgsql/data`.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

> **Concept - Red Hat keeps config inside PGDATA**: Unlike Debian where configs live
> under `/etc/postgresql/`, Red Hat-based systems keep `postgresql.conf` and
> `pg_hba.conf` inside the data directory (`/opt/pgsql/data/`). Know where
> your configs live on your OS.

## 7. Enable wal_log_hints

This is required for `pg_rewind` (used by repmgr node rejoin):

Switch to the postgres user:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -c "ALTER SYSTEM SET wal_log_hints = on;"
```

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

Restart to apply:

```bash
systemctl restart postgresql-16
```

Verify:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -c "SHOW wal_log_hints;"
```

Expected: `on`.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

> **Concept - wal_log_hints**: This parameter logs hint-bit changes in WAL,
> which is required by `pg_rewind`. Without it, `pg_rewind` cannot safely
> determine which data pages changed after a timeline divergence. In this lab,
> repmgr uses `pg_rewind` during `repmgr node rejoin` to bring a former primary
> back as a standby without a full base backup.

## 8. Configure essential replication parameters

On ALL FOUR servers:

Switch to the postgres user:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql <<SQL
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET wal_keep_size = '1GB';
ALTER SYSTEM SET shared_preload_libraries = 'repmgr';
SQL
```

Expected output (yours will differ):
```
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
ALTER SYSTEM
```

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

Restart PostgreSQL:

```bash
systemctl restart postgresql-16
```

Verify the settings. Switch to the postgres user:

```bash
su - postgres
```

**You are now the postgres user.** Your prompt shows `postgres@`.

```bash
psql -c "SHOW wal_level;"
```

Expected: `replica`.

```bash
psql -c "SHOW max_wal_senders;"
```

Expected: `10`.

```bash
psql -c "SHOW hot_standby;"
```

Expected: `on`.

```bash
psql -c "SHOW shared_preload_libraries;"
```

Expected: `repmgr`.

```bash
exit
```

**You are back to root.** Your prompt shows `root@`.

> **Concept - shared_preload_libraries = 'repmgr'**: The repmgr extension
> includes a background worker (repmgrd) that monitors cluster health and
> triggers automatic failover. To load background workers, the library must
> be preloaded at server start via shared_preload_libraries. Without this,
> the repmgrd daemon cannot start.

> **Concept - Setting these on all nodes**: Even though NODE2, NODE3, and
> NODE4 start as standbys (or witness), any of them could become primary
> after a failover. By configuring replication parameters on all nodes from
> the start, you avoid a situation where a newly promoted standby cannot
> accept replication connections.

---

## Checkpoint

All four servers have:
- [x] PGDG repo added and OS module disabled
- [x] PostgreSQL 16 installed (`postgresql16-server postgresql16-contrib`)
- [x] Database cluster initialized (initdb)
- [x] Service running and enabled (`postgresql-16`)
- [x] Data directory at `/opt/pgsql/data`
- [x] `wal_log_hints = on`
- [x] `wal_level = replica`, `max_wal_senders = 10`
- [x] `shared_preload_libraries = 'repmgr'`
- [x] `hot_standby = on`

Proceed to `03-install-repmgr.md`.

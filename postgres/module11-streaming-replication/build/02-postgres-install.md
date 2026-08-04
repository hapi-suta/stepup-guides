# Build 02: PostgreSQL Installation (CentOS Stream 9)

Install PostgreSQL 16 from the official PGDG repository on BOTH servers.

---

## 1. Add the PGDG repository

Install the PGDG RPM for CentOS/RHEL 9:

```bash
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
```

This adds the official PostgreSQL repository to your system.

Disable the built-in PostgreSQL module so it does not conflict with PGDG:

```bash
sudo dnf -qy module disable postgresql
```

> **Concept - Why PGDG, not the OS default**: CentOS ships an older PostgreSQL version
> that lags behind features and security patches. The PGDG repo is maintained by the
> PostgreSQL core team and tracks every minor release within days. Always use PGDG
> in production.

## 2. Install PostgreSQL 16

```bash
sudo dnf install -y postgresql16-server postgresql16
```

`postgresql16-server` installs the server. `postgresql16` installs the client tools (psql, pg_dump, etc).

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
sudo systemctl start postgresql-16
```

Enable it to start on boot:

```bash
sudo systemctl enable postgresql-16
```

Expected output (yours will differ):
```
Created symlink /etc/systemd/system/multi-user.target.wants/postgresql-16.service ...
```

> **Important**: On CentOS, the service name is `postgresql-16`, NOT `postgresql`.
> This is different from Debian/Ubuntu where the service is just `postgresql`.

## 5. Verify the service is running

```bash
sudo systemctl status postgresql-16
```

Expected: `active (running)`.

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT version();"
```

Expected: `PostgreSQL 16.x on ...`.

When you are done, type `exit` to return to your previous user:

```bash
exit
```

## 6. Verify the data directory

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SHOW data_directory;"
```

Expected: `/opt/pgsql/data`.

```bash
exit
```

```bash
ls -la /opt/pgsql/data/
```

Expected: PG_VERSION, base/, global/, pg_wal/, postgresql.conf, pg_hba.conf, etc.

## 7. Verify key config files

On CentOS, config files live inside the data directory:

```bash
ls -la /opt/pgsql/data/postgresql.conf
```

```bash
ls -la /opt/pgsql/data/pg_hba.conf
```

Expected: both files exist.

> **Concept - Red Hat keeps config inside PGDATA**: Unlike Debian where configs live
> under `/etc/postgresql/`, Red Hat-based systems keep `postgresql.conf` and
> `pg_hba.conf` inside the data directory (`/opt/pgsql/data/`). Know where
> your configs live on your OS.

## 8. Check the postgres user

```bash
id postgres
```

Expected: user `postgres` exists with a UID and GID.

Switch to the postgres user and verify:

```bash
sudo -iu postgres
```

```bash
whoami
```

Expected: `postgres`.

```bash
exit
```

---

## Checkpoint

Both servers have:
- [x] PGDG repo added and OS module disabled
- [x] PostgreSQL 16 installed
- [x] Database cluster initialized (initdb)
- [x] Service running and enabled (`postgresql-16`)
- [x] Data directory at `/opt/pgsql/data`
- [x] Config files at `/opt/pgsql/data/`
- [x] `postgres` OS user exists

Proceed to `03-configure-primary.md`.

# Build 02: PostgreSQL Installation

Install PostgreSQL 16 from the official PGDG repository on BOTH servers.

---

## 1. Add the PGDG repository

Add the PGDG apt source list:

```bash
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
```

Download and install the PGDG signing key. The pipe here streams the key directly into `gpg` for conversion:

```bash
curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
```

`-f` fails silently on HTTP errors. `-s` is silent mode. `-S` shows errors even in silent mode. `-L` follows redirects.

Update the package list so apt sees the new PGDG repo:

```bash
apt update
```

Verify:
```bash
apt-cache policy postgresql-16
```

Expected: shows the PGDG version (16.x) as the candidate.

> **Concept - Why PGDG, not the OS default**: Debian/Ubuntu ship older PG versions
> that lag behind features and security patches. The PGDG repo is maintained by the
> PostgreSQL core team and tracks every minor release within days. Always use PGDG
> in production.

## 2. Install PostgreSQL 16

```bash
apt install -y postgresql-16 postgresql-client-16
```

## 3. Verify the service is running

```bash
systemctl status postgresql
```

Expected: `active (exited)` or `active (running)`.

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT version();"
```

Expected: `PostgreSQL 16.x on ...`.

When you are done, type `exit` to return to the root user:

```bash
exit
```

## 4. Verify the data directory

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SHOW data_directory;"
```

Expected: `/var/lib/postgresql/16/main`.

```bash
exit
```

```bash
ls -la /var/lib/postgresql/16/main/
```

Expected: PG_VERSION, base/, global/, pg_wal/, etc.

## 5. Verify key config files

```bash
ls -la /etc/postgresql/16/main/
```

Expected: `postgresql.conf`, `pg_hba.conf`, `pg_ident.conf`.

> **Concept - Debian splits config from data**: Unlike Red Hat where config lives
> inside PGDATA, Debian keeps configs under `/etc/postgresql/`. The `data_directory`
> parameter in `postgresql.conf` points to the actual data. Know where both live.

## 6. Check the postgres user

```bash
id postgres
```

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

Expected: user `postgres` exists, UID typically 26 or similar.

## 7. Verify pg_lsclusters

```bash
pg_lsclusters
```

Expected: one row showing `16 main 5432 online`.

---

## Checkpoint

Both servers have:
- [x] PGDG repo added and updated
- [x] PostgreSQL 16 installed
- [x] Service running
- [x] Data directory at `/var/lib/postgresql/16/main`
- [x] Config files at `/etc/postgresql/16/main/`
- [x] `postgres` OS user exists
- [x] Cluster visible in `pg_lsclusters`

Proceed to `03-configure-primary.md`.

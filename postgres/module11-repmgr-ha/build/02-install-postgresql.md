# Build 02: Install PostgreSQL 16

Install PostgreSQL 16 from the PGDG repository on all four nodes.

Run every step on ALL FOUR servers.

---

## 1. Add the PGDG repository

```bash
sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" \
  > /etc/apt/sources.list.d/pgdg.list'

curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/pgdg.gpg

apt update
```

Expected: repository added, key imported, package list updated.

## 2. Install PostgreSQL 16

```bash
apt install -y postgresql-16
```

Expected: PostgreSQL 16 installed and started automatically.

## 3. Verify PostgreSQL is running

```bash
sudo systemctl status postgresql
sudo -iu postgres psql -c "SELECT version();"
```

Expected: service active, version string shows `PostgreSQL 16.x`.

## 4. Confirm the data directory

```bash
sudo -iu postgres psql -c "SHOW data_directory;"
```

Expected: `/var/lib/postgresql/16/main`.

## 5. Enable wal_log_hints

This is required for `pg_rewind` (used by repmgr node rejoin):

```bash
sudo -iu postgres psql -c "ALTER SYSTEM SET wal_log_hints = on;"
```

Restart to apply:
```bash
sudo systemctl restart postgresql
```

Verify:
```bash
sudo -iu postgres psql -c "SHOW wal_log_hints;"
```

Expected: `on`.

> **Concept - wal_log_hints**: This parameter logs hint-bit changes in WAL,
> which is required by `pg_rewind`. Without it, `pg_rewind` cannot safely
> determine which data pages changed after a timeline divergence. In this lab,
> repmgr uses `pg_rewind` during `repmgr node rejoin` to bring a former primary
> back as a standby without a full base backup.

## 6. Configure essential replication parameters

On ALL FOUR servers:

```bash
sudo -iu postgres psql <<SQL
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET wal_keep_size = '1GB';
ALTER SYSTEM SET shared_preload_libraries = 'repmgr';
SQL
```

Restart PostgreSQL:
```bash
sudo systemctl restart postgresql
```

Verify:
```bash
sudo -iu postgres psql -c "SHOW wal_level;"
sudo -iu postgres psql -c "SHOW max_wal_senders;"
sudo -iu postgres psql -c "SHOW hot_standby;"
sudo -iu postgres psql -c "SHOW shared_preload_libraries;"
```

Expected: `replica`, `10`, `on`, `repmgr`.

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
- [x] PostgreSQL 16 installed from PGDG
- [x] PostgreSQL running and accessible
- [x] `wal_log_hints = on`
- [x] `wal_level = replica`, `max_wal_senders = 10`
- [x] `shared_preload_libraries = 'repmgr'`
- [x] `hot_standby = on`

Proceed to `03-install-repmgr.md`.

# Build 03: Configure the Primary

Configure NODE1 as the streaming replication primary.

All steps run on NODE1 only.

---

## 1. Edit postgresql.conf

```bash
sudo -iu postgres vim /etc/postgresql/16/main/postgresql.conf
```

Set or uncomment these parameters:

```
listen_addresses = '*'
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
hot_standby = on
wal_log_hints = on
wal_keep_size = 1GB
archive_mode = on
archive_command = 'test ! -f /var/lib/postgresql/16/archive/%f && cp %p /var/lib/postgresql/16/archive/%f'
archive_timeout = 60
```

> **Concept - wal_level = replica**: This is the minimum WAL level that supports
> streaming replication. It adds enough information to the WAL for a standby to
> replay it. The default in PG 16 is already `replica`, but always set it
> explicitly so your config is self-documenting.

> **Concept - max_wal_senders**: Each streaming standby uses one WAL sender
> process. Set this to at least the number of standbys you plan to run, plus a
> few spare for pg_basebackup and monitoring tools.

> **Concept - wal_log_hints = on**: This logs full-page images of hint-bit-only
> changes to WAL. Without it, `pg_rewind` cannot safely rewind a diverged node
> because some page modifications would be invisible in the WAL. Always enable this
> if you plan to use `pg_rewind` after a failover (and you should).

> **Concept - wal_keep_size**: Keeps this much WAL on the primary even if no
> standby has consumed it yet. A safety net for slow standbys. In production,
> use replication slots instead (which we set up in step 3).

## 2. Create the archive directory

```bash
sudo -iu postgres mkdir -p /var/lib/postgresql/16/archive
```

## 3. Create a replication role

```bash
sudo -iu postgres psql <<SQL
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD 'replicator_pass_2026';
SQL
```

Verify:
```bash
sudo -iu postgres psql -c "SELECT rolname, rolreplication FROM pg_roles WHERE rolname = 'replicator';"
```

Expected: `replicator | t`.

> **Concept - Least privilege for replication**: The `replicator` role has only
> REPLICATION and LOGIN. It cannot read tables, modify data, or create objects.
> Never use a superuser for replication.

## 4. Create a replication slot

```bash
sudo -iu postgres psql -c "SELECT pg_create_physical_replication_slot('standby_slot');"
```

Verify:
```bash
sudo -iu postgres psql -c "SELECT slot_name, active FROM pg_replication_slots;"
```

Expected: `standby_slot | f` (not active yet - standby hasn't connected).

> **Concept - Replication slots prevent WAL recycling**: Without a slot, the
> primary can delete WAL that a lagging standby still needs. With a slot, the
> primary retains WAL until the standby confirms it has consumed it. The tradeoff:
> if a standby goes down for days, the slot prevents WAL cleanup and the primary's
> disk fills. Monitor `pg_replication_slots.active` and drop abandoned slots.

## 5. Configure pg_hba.conf for replication

```bash
sudo -iu postgres vim /etc/postgresql/16/main/pg_hba.conf
```

Add at the end:

```
# Replication connections from standby
host    replication     replicator      [NODE2_IP]/32       scram-sha-256
```

> **Concept - pg_hba.conf for replication**: The `replication` keyword in the
> database column is special. It allows the role to connect via the replication
> protocol (used by pg_basebackup and WAL streaming). Without this line, the
> standby cannot connect even if the role has REPLICATION privilege.

## 6. Restart PostgreSQL to apply changes

```bash
sudo systemctl restart postgresql
```

Verify it came back:
```bash
sudo -iu postgres psql -c "SHOW wal_level;"
sudo -iu postgres psql -c "SHOW max_wal_senders;"
sudo -iu postgres psql -c "SHOW archive_mode;"
sudo -iu postgres psql -c "SHOW wal_log_hints;"
```

Expected: `replica`, `10`, `on`, `on`.

## 7. Create a test database with sample data

```bash
sudo -iu postgres psql <<SQL
CREATE DATABASE labdb;
\c labdb
CREATE TABLE employees (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    department TEXT NOT NULL,
    hired_at TIMESTAMPTZ DEFAULT now()
);
INSERT INTO employees (name, department)
SELECT 'employee_' || g,
       (ARRAY['engineering','sales','support','ops'])[1 + (g % 4)]
FROM generate_series(1, 10000) g;
SQL
```

Verify:
```bash
sudo -iu postgres psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000`.

## 8. Test that the standby can reach the primary

From NODE2:
```bash
psql -h pg-primary -U replicator -d postgres -c "SELECT 1;"
```

If prompted for password, enter `replicator_pass_2026`.

Expected: returns `1`. If it fails, check pg_hba.conf and firewall.

---

## Checkpoint

NODE1 (primary) has:
- [x] `wal_level = replica`, `max_wal_senders = 10`, `archive_mode = on`
- [x] Archive directory created
- [x] `replicator` role with REPLICATION privilege
- [x] Physical replication slot `standby_slot` created
- [x] pg_hba.conf allows replication from NODE2
- [x] PostgreSQL restarted and running
- [x] `labdb` database with 10,000 test rows
- [x] Standby can connect to primary on 5432

Proceed to `04-configure-standby.md`.

# Build 04: Configure the Standby

Clone NODE1 to NODE2 using pg_basebackup and start streaming replication.

All steps run on NODE2 unless noted.

---

## 1. Stop PostgreSQL on the standby

```bash
sudo systemctl stop postgresql
```

## 2. Remove the existing data directory

The standby needs to start from a copy of the primary, not its own initdb.

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
rm -rf /var/lib/postgresql/16/main/*
```

Verify it is empty:

```bash
ls -la /var/lib/postgresql/16/main/
```

```bash
exit
```

Expected: empty directory.

> **Concept - Why we wipe the standby's data**: `pg_basebackup` needs an empty
> target directory. The standby's original data (from its own `initdb` during
> install) is not related to the primary's data. Wiping it is safe because the
> standby has no data of its own yet.

## 3. Run pg_basebackup from the primary

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pg_basebackup \
  -h pg-primary \
  -U replicator \
  -D /var/lib/postgresql/16/main \
  -Fp -Xs -P -R \
  -S standby_slot
```

Enter password when prompted: `replicator_pass_2026`

Expected: progress bar reaching 100%, ending with a basebackup completion message.

> **Concept - pg_basebackup flags**:
> - `-Fp`: plain format (not tar). Files are written directly to the data directory.
> - `-Xs`: stream WAL during backup. Without this, WAL generated during the backup
>   might not be included, causing a gap.
> - `-P`: show progress.
> - `-R`: write `standby.signal` and `primary_conninfo` to `postgresql.auto.conf`.
>   This is what tells PostgreSQL to start in standby mode.
> - `-S standby_slot`: use the replication slot we created on the primary.

```bash
exit
```

## 4. Verify the standby.signal file exists

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
ls -la /var/lib/postgresql/16/main/standby.signal
```

Expected: file exists (can be empty, its presence is what matters).

## 5. Check postgresql.auto.conf for primary_conninfo

Still as the postgres user (if you exited, run `sudo -iu postgres` again):

```bash
cat /var/lib/postgresql/16/main/postgresql.auto.conf
```

Expected: a `primary_conninfo` line pointing to the primary, with the replication
slot reference.

> **Concept - standby.signal + primary_conninfo = standby mode**: In PG 12+, the
> presence of `standby.signal` tells PostgreSQL to enter recovery mode on startup.
> `primary_conninfo` tells it where to stream WAL from. Together they replace the
> old `recovery.conf` file from PG 11 and earlier.

## 6. Configure postgresql.conf on the standby

Still as the postgres user:

```bash
vim /etc/postgresql/16/main/postgresql.conf
```

Set:

```
listen_addresses = '*'
hot_standby = on
```

> **Concept - hot_standby = on**: This allows read queries on the standby while
> it is replaying WAL. Without it, the standby accepts no connections during
> recovery. In production, hot standby is almost always enabled so the standby
> can serve read traffic.

Save and exit vim, then exit back to root:

```bash
exit
```

## 7. Start PostgreSQL on the standby

```bash
sudo systemctl start postgresql
```

Check the log for successful startup. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
tail -20 /var/log/postgresql/postgresql-16-main.log
```

Expected: messages about entering standby mode, connecting to primary, starting
WAL streaming.

## 8. Verify the standby is in recovery mode

Still as the postgres user:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t`.

## 9. Verify data replicated

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: `10000` (same as primary).

## 10. Verify the standby rejects writes

```bash
psql -d labdb -c "INSERT INTO employees (name, department) VALUES ('test', 'test');"
```

Expected: `ERROR: cannot execute INSERT in a read-only transaction`.

```bash
exit
```

---

## Checkpoint

NODE2 (standby) has:
- [x] Data directory cloned from primary via pg_basebackup
- [x] `standby.signal` file present
- [x] `primary_conninfo` configured in `postgresql.auto.conf`
- [x] `hot_standby = on`
- [x] PostgreSQL started and in recovery mode (`pg_is_in_recovery() = t`)
- [x] Data matches primary (10,000 rows in labdb.employees)
- [x] Writes correctly rejected

Proceed to `05-verify-replication.md`.

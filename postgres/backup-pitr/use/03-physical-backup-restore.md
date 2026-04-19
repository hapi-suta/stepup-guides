# Exercise 03 - Physical Backup and Restore

**Time estimate:** 30-40 minutes
**Prerequisites:** Exercise 02 complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with labdb, appdb, blobdb intact

---

## Objective

Take a full physical backup with pg_basebackup, simulate a disaster, and restore from the backup. By the end of this exercise, you should be able to recover a PostgreSQL cluster from a base backup under pressure.

---

## Step 1 - Verify Prerequisites for pg_basebackup

On **NODE1** (pg-primary), confirm the required settings:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SHOW wal_level;"
sudo -u postgres /usr/pgsql-16/bin/psql -c "SHOW max_wal_senders;"
```

**Expected:**
- `wal_level` = `replica` (or `logical`)
- `max_wal_senders` >= 2

> **Concept:** `pg_basebackup` connects as a replication client to stream a copy of the entire data directory. It requires `wal_level` >= `replica` (so WAL contains enough information) and at least one available WAL sender slot. These are the same prerequisites as streaming replication - a base backup is essentially a one-time replication snapshot.

---

## Step 2 - Take a Base Backup in Plain Format

On **NODE2** (pg-backup):

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_basebackup \
  -h [NODE1_IP] \
  -U replicator \
  -D /opt/pgsql/backup/pg_basebackup_plain \
  -Fp \
  -Xs \
  -P \
  -R
```

Flag breakdown:
- `-Fp` - plain format (files copied as-is)
- `-Xs` - stream WAL during backup (ensures consistency)
- `-P` - show progress
- `-R` - write standby.signal and connection info (useful but optional for restore)

**Expected:**

```
5765321/5765321 kB (100%), 1/1 tablespace
```

Verify the backup:

```bash
ls -la /opt/pgsql/backup/pg_basebackup_plain/
```

**Expected:** A full PostgreSQL data directory - `base/`, `global/`, `pg_wal/` (symlink to `/opt/pgsql/wal`), `PG_VERSION`, `postgresql.conf`, etc.

```bash
cat /opt/pgsql/backup/pg_basebackup_plain/PG_VERSION
```

**Expected:** `16`

> **Concept:** Plain format creates an exact copy of the data directory. You can start a PostgreSQL instance directly from this directory. The `-Xs` flag (stream WAL) is critical - it ensures that WAL generated during the backup is captured, making the backup self-contained. Without it, you would need to keep WAL archives from the backup period separately. With the 5GB labdb dataset, this backup will be approximately 5.5GB.

---

## Step 3 - Verify the Backup Contents

```bash
# Check that all databases exist in the backup
ls /opt/pgsql/backup/pg_basebackup_plain/base/
```

**Expected:** Multiple OID directories, one for each database (template0, template1, postgres, labdb, appdb, blobdb).

Confirm the OID-to-database mapping:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -h [NODE1_IP] -c "SELECT oid, datname FROM pg_database ORDER BY oid;"
```

Match the OIDs from the query to the directories in `base/`.

> **Concept:** Physical backups capture everything - all databases, all roles, all configuration. Unlike pg_dump (which targets one database), pg_basebackup copies the entire cluster. This is both its strength (complete backup in one step) and its limitation (you cannot selectively restore a single database from a physical backup).

---

## Step 4 - Record the Current State Before Disaster

On **NODE1** (pg-primary), record row counts for verification after restore:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) AS pgbench_accounts_count FROM pgbench_accounts;"
sudo -u postgres /usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) AS employee_count FROM employees;"
```

Write these numbers down - you will verify them after restore.

**Expected:**
- pgbench_accounts: ~33,000,000 (scale 330)
- employees: 100,000

---

## Step 5 - Simulate Disaster: Stop and Wipe NODE1

**WARNING:** This step destroys the data directory. Only proceed because you have a backup.

On **NODE1** (pg-primary):

```bash
sudo systemctl stop postgresql-16
```

Verify it is stopped:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready
```

**Expected:** `no response` or connection refused.

Now wipe the data directory and WAL directory:

```bash
sudo rm -rf /opt/pgsql/data/*
sudo rm -rf /opt/pgsql/wal/*
```

Verify they are empty:

```bash
ls -la /opt/pgsql/data/
ls -la /opt/pgsql/wal/
```

**Expected:** Empty directories.

> **Concept:** This simulates total data loss - disk failure, accidental deletion, or corruption beyond repair. In production, you would never wipe the data directory manually. But practicing this in a lab builds the muscle memory for the real thing. When disaster strikes, you do not have time to read documentation.

---

## Step 6 - Restore From the Plain Format Backup

Copy the backup into the data directory:

```bash
sudo cp -a /opt/pgsql/backup/pg_basebackup_plain/* /opt/pgsql/data/
```

Recreate the pg_wal symlink pointing to the WAL mount:

```bash
sudo rm -rf /opt/pgsql/data/pg_wal
sudo ln -s /opt/pgsql/wal /opt/pgsql/data/pg_wal
```

Copy WAL files from the backup into the WAL directory:

```bash
sudo cp -a /opt/pgsql/backup/pg_basebackup_plain/pg_wal/* /opt/pgsql/wal/
```

Remove the standby.signal file (we want this to come up as a primary, not a standby):

```bash
sudo rm -f /opt/pgsql/data/standby.signal
```

Fix ownership:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data/
sudo chown -R postgres:postgres /opt/pgsql/wal/
```

Verify permissions on the data directory:

```bash
sudo chmod 700 /opt/pgsql/data
```

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_isready
```

**Expected:** `accepting connections`

> **Concept:** Restoring from a plain format base backup is conceptually simple - copy the files back and start PostgreSQL. The critical details on CentOS with custom mount points are: (1) recreate the pg_wal symlink to `/opt/pgsql/wal`, (2) remove `standby.signal` unless you want a standby, (3) ensure correct ownership (`postgres:postgres`), and (4) ensure correct permissions (mode 0700 on the data directory). Getting ownership or permissions wrong is the most common restore failure.

---

## Step 7 - Verify All Databases Are Intact

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "\l"
```

**Expected:** labdb, appdb, blobdb all listed.

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
sudo -u postgres /usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM employees;"
```

**Expected:** Row counts match the numbers you recorded in Step 4 (~33M pgbench_accounts, 100K employees).

---

## Step 8 - Take a Compressed Tar Format Backup

On **NODE2** (pg-backup):

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_basebackup \
  -h [NODE1_IP] \
  -U replicator \
  -D /opt/pgsql/backup/pg_basebackup_tar \
  -Ft \
  -z \
  -Xs \
  -P
```

Flag changes:
- `-Ft` - tar format (single archive file)
- `-z` - gzip compression

**Expected:** Two files in the target directory:

```bash
ls -lh /opt/pgsql/backup/pg_basebackup_tar/
```

```
-rw-------  1 postgres postgres  1.1G Apr 17 10:30 base.tar.gz
-rw-------  1 postgres postgres   17M Apr 17 10:30 pg_wal.tar.gz
```

> **Concept:** Tar format produces portable archive files instead of a raw directory. Combined with `-z` for compression, this is ideal for shipping backups to remote storage (S3, NFS, tape). With the 5GB dataset, the compressed tar is roughly 1-1.2GB versus ~5.5GB for the plain backup. The tradeoff - you must extract the tar before you can start PostgreSQL from it, adding time to the restore process.

---

## Step 9 - Restore From Tar Format Backup

Simulate another disaster on **NODE1**:

```bash
sudo systemctl stop postgresql-16
sudo rm -rf /opt/pgsql/data/*
sudo rm -rf /opt/pgsql/wal/*
```

Extract the tar backup:

```bash
sudo tar xzf /opt/pgsql/backup/pg_basebackup_tar/base.tar.gz \
  -C /opt/pgsql/data/

sudo tar xzf /opt/pgsql/backup/pg_basebackup_tar/pg_wal.tar.gz \
  -C /opt/pgsql/wal/
```

Recreate the pg_wal symlink:

```bash
sudo rm -rf /opt/pgsql/data/pg_wal
sudo ln -s /opt/pgsql/wal /opt/pgsql/data/pg_wal
```

Fix ownership and start:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data/
sudo chown -R postgres:postgres /opt/pgsql/wal/
sudo chmod 700 /opt/pgsql/data
sudo systemctl start postgresql-16
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM pgbench_accounts;"
sudo -u postgres /usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM employees;"
```

**Expected:** Same row counts as before (~33M pgbench_accounts, 100K employees).

---

## Step 10 - Compare Backup Approaches

Compare the sizes:

```bash
du -sh /opt/pgsql/backup/pg_basebackup_plain
du -sh /opt/pgsql/backup/pg_basebackup_tar
```

**Expected:** With the 5GB dataset:
- Plain backup: ~5.5GB
- Tar+gzip backup: ~1.1GB

Summary comparison:

| Aspect | Plain (-Fp) | Tar + gzip (-Ft -z) |
|---|---|---|
| Backup size | ~5.5GB (uncompressed) | ~1.1GB (compressed) |
| Backup speed | Faster (no compression overhead) | Slightly slower |
| Restore speed | Fastest (just copy files) | Slower (must extract first) |
| Portability | Harder to move (many files) | Easier (two files) |
| Direct start | Yes (copy and start) | No (must extract first) |

> **Concept:** In production, choose based on your priorities. If RTO (recovery time) is critical, use plain format on fast local storage - you can start PostgreSQL immediately after copying. If storage cost or transfer speed matters (cloud backups, offsite copies), use tar with compression. Many teams use plain for local fast-recovery and tar for offsite archival.

---

## Checkpoint

Before continuing, confirm:
- [ ] You took a base backup in plain format and verified its structure
- [ ] You simulated a disaster by wiping the data directory
- [ ] You restored from the plain backup and verified all databases
- [ ] You recreated the pg_wal symlink to `/opt/pgsql/wal` during restore
- [ ] You took a compressed tar format backup
- [ ] You restored from the tar backup and verified data integrity
- [ ] You understand the tradeoffs between plain and tar format
- [ ] You know the critical restore details: remove standby.signal, recreate pg_wal symlink, fix ownership, fix permissions

---

**Next:** [04 - PITR Exercise](04-pitr-exercise.md)

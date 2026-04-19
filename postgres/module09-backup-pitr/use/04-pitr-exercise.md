# Exercise 04 - Point-in-Time Recovery (PITR)

**Time estimate:** 30-40 minutes
**Prerequisites:** Exercise 03 complete - NODE1 (pg-primary) running PostgreSQL 16 on CentOS Stream 9 with all databases intact, WAL archiving configured to `/opt/pgsql/backup/archive`

---

## Objective

Perform point-in-time recovery to a named restore point, a specific timestamp, and a specific LSN. Master the side-restore pattern for extracting lost data without disrupting production. By the end of this exercise, you should be able to recover data to any moment in time.

---

## Step 1 - Verify Continuous Archiving Is Active

On **NODE1** (pg-primary):

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SHOW archive_mode;"
sudo -u postgres /usr/pgsql-16/bin/psql -c "SHOW archive_command;"
sudo -u postgres /usr/pgsql-16/bin/psql -c "SHOW wal_level;"
```

**Expected:**
- `archive_mode` = `on`
- `archive_command` = a command that copies WAL files to the archive directory (e.g., `cp %p /opt/pgsql/backup/archive/%f`)
- `wal_level` = `replica` or `logical`

Verify the archive directory exists and has WAL files:

```bash
ls -la /opt/pgsql/backup/archive/ | head -10
```

> **Concept:** PITR requires two ingredients: (1) a base backup taken with pg_basebackup, and (2) a continuous stream of archived WAL files from that base backup forward. The base backup gives you the starting state. The WAL files let you replay transactions forward to any point in time. Without WAL archiving, you can only restore to the moment the base backup was taken - you lose everything after that.

---

## Step 2 - Take a Base Backup for PITR

On **NODE2** (pg-backup):

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_basebackup \
  -h [NODE1_IP] \
  -U replicator \
  -D /opt/pgsql/backup/pitr_base \
  -Fp \
  -Xs \
  -P
```

**Expected:** Backup completes successfully. With the 5GB labdb dataset, expect ~5.5GB transferred.

```bash
ls /opt/pgsql/backup/pitr_base/PG_VERSION
```

**Expected:** File exists, contains `16`.

---

## Step 3 - Create a Named Restore Point

On **NODE1** (pg-primary), connect to labdb:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT pg_create_restore_point('before_delete');"
```

**Expected:**

```
 pg_create_restore_point
-------------------------
 0/6000100
```

Note this LSN - you will use it later.

> **Concept:** `pg_create_restore_point()` writes a named marker into the WAL stream. During PITR, you can target this name with `recovery_target_name` instead of guessing at timestamps. This is the most reliable PITR target because it is exact - no clock skew, no timezone confusion. In production, create restore points before risky operations: `SELECT pg_create_restore_point('before_schema_migration_v42');`

---

## Step 4 - Insert Batch A (1000 Rows)

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "
INSERT INTO employees (name, department, hired_at)
SELECT
    'batch_a_' || generate_series(1, 1000),
    CASE (random() * 3)::int
        WHEN 0 THEN 'Engineering'
        WHEN 1 THEN 'Marketing'
        WHEN 2 THEN 'Sales'
        ELSE 'Operations'
    END,
    NOW() - (random() * interval '365 days');
"
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'batch_a_%';"
```

**Expected:** `1000`

---

## Step 5 - Record the Exact Timestamp

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT now() AS pitr_target_time;"
```

**Write this timestamp down exactly.** Example: `2026-04-17 10:45:23.456789+00`

Force a WAL switch to ensure the timestamp is archived:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT pg_switch_wal();"
```

---

## Step 6 - Simulate Disaster: Delete All Employees

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "DELETE FROM employees;"
```

Verify the damage:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees;"
```

**Expected:** `0` - all data is gone.

---

## Step 7 - Insert Batch B (500 Rows Post-Disaster)

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "
INSERT INTO employees (name, department, hired_at)
SELECT
    'batch_b_' || generate_series(1, 500),
    'PostDisaster',
    NOW();
"
```

Force another WAL switch:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT pg_switch_wal();"
```

> **Concept:** This creates a realistic scenario. After the disaster (DELETE), new legitimate data was written (batch B). A naive restore would lose batch B. This is why PITR must target the exact moment before the DELETE - not "the latest backup." Understanding this timeline is critical for production incidents.

---

## Step 8 - Recover the Current WAL Position

Note the current LSN for the LSN-based PITR exercise later:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT pg_current_wal_lsn() AS current_lsn;"
```

---

## Step 9 - PITR to the Named Restore Point

Stop NODE1:

```bash
sudo systemctl stop postgresql-16
```

Wipe the data directory and WAL directory:

```bash
sudo rm -rf /opt/pgsql/data/*
sudo rm -rf /opt/pgsql/wal/*
```

Copy the base backup:

```bash
sudo cp -a /opt/pgsql/backup/pitr_base/* /opt/pgsql/data/
```

Recreate the pg_wal symlink and copy WAL files:

```bash
sudo cp -a /opt/pgsql/data/pg_wal/* /opt/pgsql/wal/ 2>/dev/null || true
sudo rm -rf /opt/pgsql/data/pg_wal
sudo ln -s /opt/pgsql/wal /opt/pgsql/data/pg_wal
```

Configure recovery in `postgresql.auto.conf`:

```bash
sudo tee -a /opt/pgsql/data/postgresql.auto.conf << 'EOF'
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_name = 'before_delete'
recovery_target_action = 'pause'
EOF
```

Create the recovery signal:

```bash
sudo touch /opt/pgsql/data/recovery.signal
```

Fix ownership and start:

```bash
sudo chown -R postgres:postgres /opt/pgsql/data/
sudo chown -R postgres:postgres /opt/pgsql/wal/
sudo chmod 700 /opt/pgsql/data
sudo systemctl start postgresql-16
```

Check recovery status:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

**Expected:** `t` - the server is paused at the restore point.

Verify the data:

```bash
# Batch A should NOT exist yet (it was inserted AFTER the restore point)
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'batch_a_%';"

# The DELETE should NOT have happened
# Original employees should be present
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees;"
```

**Expected:**
- batch_a count: `0` (inserted after the restore point)
- Total employee count: the original count before any of this exercise's changes

> **Concept:** `recovery_target_name` tells PostgreSQL to replay WAL until it reaches the named restore point and then stop. `recovery_target_action = 'pause'` keeps the server in recovery mode so you can inspect the data before committing to the recovery. Other options are `'promote'` (immediately become a primary) and `'shutdown'` (stop the server after reaching the target).

---

## Step 10 - Promote After Verification

Once you confirm the data looks correct:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_wal_replay_resume();"
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_promote();"
```

Verify:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

**Expected:** `f` - the server is now a primary.

---

## Step 11 - PITR to a Specific Timestamp

Repeat the restore process but target the timestamp you recorded in Step 5.

Stop, wipe, and copy the base backup again:

```bash
sudo systemctl stop postgresql-16
sudo rm -rf /opt/pgsql/data/*
sudo rm -rf /opt/pgsql/wal/*
sudo cp -a /opt/pgsql/backup/pitr_base/* /opt/pgsql/data/
```

Recreate the pg_wal symlink:

```bash
sudo cp -a /opt/pgsql/data/pg_wal/* /opt/pgsql/wal/ 2>/dev/null || true
sudo rm -rf /opt/pgsql/data/pg_wal
sudo ln -s /opt/pgsql/wal /opt/pgsql/data/pg_wal
```

Configure for timestamp-based recovery:

```bash
sudo tee -a /opt/pgsql/data/postgresql.auto.conf << 'EOF'
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_time = '2026-04-17 10:45:23.456789+00'
recovery_target_action = 'pause'
EOF
```

Replace the timestamp with the exact value from Step 5.

```bash
sudo touch /opt/pgsql/data/recovery.signal
sudo chown -R postgres:postgres /opt/pgsql/data/
sudo chown -R postgres:postgres /opt/pgsql/wal/
sudo chmod 700 /opt/pgsql/data
sudo systemctl start postgresql-16
```

Verify:

```bash
# Batch A should exist (inserted before the timestamp)
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'batch_a_%';"

# Batch B should NOT exist (inserted after the DELETE, which is after the timestamp)
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees WHERE name LIKE 'batch_b_%';"

# The DELETE should NOT have happened
sudo -u postgres /usr/pgsql-16/bin/psql -d labdb -c "SELECT count(*) FROM employees;"
```

**Expected:**
- batch_a count: `1000`
- batch_b count: `0`
- Total: original count + 1000

Promote:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_wal_replay_resume();"
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_promote();"
```

> **Concept:** Timestamp-based PITR is the most common in practice because operators usually know "the bad thing happened around 10:45 AM." The risk is timezone confusion - always use timestamps with explicit timezone offsets. If your `recovery_target_time` is in the wrong timezone, you might recover to the wrong moment.

---

## Step 12 - PITR to a Specific LSN

For completeness, perform one more recovery targeting a specific LSN.

Stop, wipe, and copy the base backup:

```bash
sudo systemctl stop postgresql-16
sudo rm -rf /opt/pgsql/data/*
sudo rm -rf /opt/pgsql/wal/*
sudo cp -a /opt/pgsql/backup/pitr_base/* /opt/pgsql/data/
```

Recreate the pg_wal symlink:

```bash
sudo cp -a /opt/pgsql/data/pg_wal/* /opt/pgsql/wal/ 2>/dev/null || true
sudo rm -rf /opt/pgsql/data/pg_wal
sudo ln -s /opt/pgsql/wal /opt/pgsql/data/pg_wal
```

Configure for LSN-based recovery (use the LSN from the restore point in Step 3):

```bash
sudo tee -a /opt/pgsql/data/postgresql.auto.conf << 'EOF'
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_lsn = '0/6000100'
recovery_target_action = 'promote'
EOF
```

```bash
sudo touch /opt/pgsql/data/recovery.signal
sudo chown -R postgres:postgres /opt/pgsql/data/
sudo chown -R postgres:postgres /opt/pgsql/wal/
sudo chmod 700 /opt/pgsql/data
sudo systemctl start postgresql-16
```

Verify the server promoted automatically (because `recovery_target_action = 'promote'`):

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

**Expected:** `f`

> **Concept:** LSN-based PITR is the most precise - it targets an exact byte position in the WAL stream. It is useful when you know the exact LSN from `pg_create_restore_point()` or from log analysis. In practice, named restore points are easier to work with because you do not need to track raw LSN values.

---

## Step 13 - The Side-Restore Pattern

This is the production-safe approach: instead of restoring over your live database, restore to a separate directory, extract the lost data, and re-insert it into production.

On **NODE2** (pg-backup), set up a scratch PostgreSQL instance:

```bash
# Create a scratch data directory
sudo mkdir -p /opt/pgsql/backup/pitr_scratch
sudo cp -a /opt/pgsql/backup/pitr_base/* /opt/pgsql/backup/pitr_scratch/
```

Configure recovery on the scratch instance:

```bash
sudo tee -a /opt/pgsql/backup/pitr_scratch/postgresql.auto.conf << 'EOF'
restore_command = 'cp /opt/pgsql/backup/archive/%f %p'
recovery_target_time = '2026-04-17 10:45:23.456789+00'
recovery_target_action = 'promote'
port = 5433
EOF
```

```bash
sudo touch /opt/pgsql/backup/pitr_scratch/recovery.signal
sudo chown -R postgres:postgres /opt/pgsql/backup/pitr_scratch/
```

Start the scratch instance on a different port:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/backup/pitr_scratch start
```

Verify it is running:

```bash
/usr/pgsql-16/bin/pg_isready -p 5433
```

**Expected:** `accepting connections`

Extract the lost data from the scratch instance and insert into production:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_dump -p 5433 -d labdb -t employees --data-only | \
  sudo -u postgres /usr/pgsql-16/bin/psql -h [NODE1_IP] -d labdb
```

Or for more surgical extraction:

```bash
sudo -u postgres /usr/pgsql-16/bin/psql -p 5433 -d labdb -c \
  "COPY (SELECT * FROM employees WHERE name LIKE 'batch_a_%') TO STDOUT WITH CSV" | \
  sudo -u postgres /usr/pgsql-16/bin/psql -h [NODE1_IP] -d labdb -c \
  "COPY employees (id, name, department, hired_at) FROM STDIN WITH CSV"
```

Stop and clean up the scratch instance:

```bash
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/backup/pitr_scratch stop
sudo rm -rf /opt/pgsql/backup/pitr_scratch
```

> **Concept:** The side-restore pattern is the safest way to recover lost data in production. It does not touch your live database. You spin up a temporary instance from a backup, recover to the point before the data loss, extract what you need, and pipe it back into production. This avoids downtime and preserves any new data written after the incident. Every DBA should have this pattern in their toolkit.

---

## Step 14 - Think: When Is PITR Better Than Logical Restore?

| Scenario | Better Approach |
|---|---|
| Single table accidentally dropped | Side-restore with PITR |
| Need to restore to 5 minutes ago | PITR |
| Migrating to a new PG version | Logical (pg_dump/pg_restore) |
| Total server loss, need full recovery | PITR from base backup + WAL |
| Need to restore one table into a different database | Logical |
| Corruption discovered hours after it happened | PITR to before corruption |

---

## Checkpoint

Before continuing, confirm:
- [ ] You set up continuous WAL archiving to `/opt/pgsql/backup/archive`
- [ ] You created a named restore point
- [ ] You performed PITR to the named restore point and verified data state
- [ ] You performed PITR to a specific timestamp
- [ ] You performed PITR to a specific LSN
- [ ] You understand `recovery_target_action` options (pause, promote, shutdown)
- [ ] You executed the side-restore pattern on a scratch instance
- [ ] You can explain when PITR is better than logical restore
- [ ] You correctly recreated the pg_wal symlink during every restore

---

**Next:** [05 - pgBackRest Operations](05-pgbackrest-operations.md)

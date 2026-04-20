# Runbook 06 - Full Disk Emergency

**Severity:** Critical - PostgreSQL may stop accepting writes or crash
**Time to resolve:** 10-20 minutes
**Skills tested:** Disk management, WAL management (Module 09), replication slots (Module 11), monitoring (Module 10)

---

## Fix Path

### Step 1: Assess disk usage

```bash
df -h
```

Expected output (yours will differ):
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       50G   47G  3.0G  94% /
...
```

Identify which filesystems are near full.

```bash
du -sh /opt/pgsql/data
```

```bash
du -sh /opt/pgsql/wal
```

```bash
du -sh /opt/pgsql/log
```

```bash
du -sh /opt/pgsql/backup
```

```bash
du -sh /tmp
```

### Step 2: Emergency space recovery - remove filler files

These are the safest items to remove (not real data):

```bash
rm -f /tmp/filler_disk.dat
```

```bash
rm -f /opt/pgsql/log/filler_1.dat
```

```bash
rm -f /opt/pgsql/log/filler_2.dat
```

```bash
rm -f /opt/pgsql/backup/filler_1.dat
```

Verify space recovered:

```bash
df -h
```

### Step 3: Remove the inactive replication slot

An inactive replication slot prevents WAL cleanup. This is the most dangerous disk-filling issue because it grows without bound.

```bash
su - postgres
```

Check for inactive slots:

```bash
/usr/pgsql-16/bin/psql -c "SELECT slot_name, active, pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS retained_bytes FROM pg_replication_slots ORDER BY retained_bytes DESC;"
```

Drop the inactive slot:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_drop_replication_slot('leak_slot_capstone');"
```

Expected output (yours will differ):
```
 pg_drop_replication_slot
--------------------------

(1 row)
```

Verify the WAL can now be cleaned:

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) FROM pg_ls_waldir();"
```

Force a checkpoint to trigger WAL cleanup:

```bash
/usr/pgsql-16/bin/psql -c "CHECKPOINT;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT count(*) FROM pg_ls_waldir();"
```

The WAL file count should decrease after the checkpoint.

### Step 4: Remove the filler table

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DROP TABLE IF EXISTS app.disk_filler;"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "VACUUM FULL app.customers;"
```

The VACUUM FULL reclaims the disk space from the filler inserts. Note that VACUUM FULL locks the table - only use it in emergencies.

### Step 5: Clean up filler customer data

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DELETE FROM app.customers WHERE email LIKE 'diskfill%@capstone.lab';"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "VACUUM ANALYZE app.customers;"
```

### Step 6: Verify PostgreSQL is healthy

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('disk-test@capstone.lab', 'Disk Test');"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "DELETE FROM app.customers WHERE email = 'disk-test@capstone.lab';"
```

```bash
exit
```

### Step 7: Verify disk headroom

```bash
df -h
```

Expected output (yours will differ):
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvda1       50G   30G   20G  60% /
...
```

All partitions should have at least 15% free space.

---

## Revision Concepts

**Q: What is the most dangerous disk-filling issue?**
A: Inactive replication slots. They retain WAL indefinitely. A single forgotten slot can fill a 500GB disk in hours during a busy workload. Always monitor slot activity and set `max_slot_wal_keep_size` (PG 13+) to limit how much WAL a single slot can retain.

**Q: What happens when PostgreSQL runs out of disk?**
A: It depends on which filesystem fills up: (1) Data directory full: inserts and updates fail with "could not extend file", (2) WAL directory full: PostgreSQL panics and crashes (cannot write WAL = potential data loss), (3) Log directory full: logging stops but PostgreSQL continues running (blind spot), (4) /tmp full: sorts and large queries fail.

**Q: Why not just increase the disk?**
A: Increasing the disk treats the symptom, not the cause. If an inactive replication slot is filling the disk at 10GB/hour, a bigger disk just buys time. Find and fix the root cause first, then resize if needed.

**Q: What is the order of priority for freeing space?**
A: (1) Drop inactive replication slots (stops the bleeding), (2) Remove old log files (safe, high reward), (3) Expire old backups, (4) Remove temp files, (5) VACUUM FULL bloated tables (last resort - locks tables), (6) Resize the volume.

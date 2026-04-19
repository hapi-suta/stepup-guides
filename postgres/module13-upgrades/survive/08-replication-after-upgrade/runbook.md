# Scenario 08 - Replication After Upgrade

**Severity:** HIGH
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only (simulated primary/replica mismatch)

---

## Alert

```
ALERT: After upgrading the primary from PG15 to PG16,
the replica is down and streaming replication is broken.
The replica status file shows it is still on PG15.
The replication slot on the primary is accumulating WAL.
You need to plan and execute the replica rebuild.
```

---

## Key Concepts for Revision

- **Streaming replication requires matching major versions** - A PG15 replica cannot replicate from a PG16 primary. WAL format changes between major versions. After upgrading the primary, all replicas must be rebuilt on the same major version. This is the most common replication-related upgrade mistake.

- **The correct upgrade sequence** - (1) Upgrade the primary with `pg_upgrade`. (2) Stop the old replica. (3) Rebuild the replica using `pg_basebackup` from the upgraded primary. (4) Start the new replica. You cannot upgrade replicas in-place with `pg_upgrade` because they are read-only and cannot run the upgrade process.

- **Replication slots accumulate WAL** - While the replica is down, the replication slot on the primary prevents WAL from being recycled. This protects the replica's catch-up point but consumes disk space. If the replica will be rebuilt (not caught up), the old slot should be dropped to free WAL space.

- **pg_basebackup is the standard rebuild tool** - `pg_basebackup -h primary_host -D /opt/pgsql/data -R -P` creates a full copy of the primary and configures replication automatically (the `-R` flag creates `standby.signal` and sets `primary_conninfo`).

- **Version mismatch detection** - On the replica, check `PG_VERSION` file in the data directory. On the primary, check `SELECT version();`. Compare the major version numbers. Also check that the binary paths match (`/usr/pgsql-16/bin/` on both nodes).

---

## Diagnostic Steps

### Step 1 - Check the replica status file

```bash
sudo -iu postgres
```

```bash
cat /opt/pgsql/replica_status/replica_info.conf
```

Expected output:

```
# Replica Status File
# This file tracks the replica cluster state after primary upgrade.

replica_pg_version=15
primary_pg_version=16
replica_data_directory=/opt/pgsql/data15
replica_status=STOPPED
replica_last_lsn=0/5000000
upgrade_started=2026-04-18T10:00:00Z
upgrade_completed=
notes=Primary upgraded to PG16. Replica still on PG15. Streaming replication broken.
```

The version mismatch is clear: primary is PG16, replica is still PG15.

### Step 2 - Check the primary version

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT version();"
```

Expected output (yours will differ):

```
                                  version
---------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

### Step 3 - Check the replication slot status

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS wal_retained
FROM pg_replication_slots;
```

Expected output (yours will differ):

```
      slot_name       | slot_type | active | restart_lsn | wal_retained
----------------------+-----------+--------+-------------+--------------
 chaos8_replica_slot  | physical  | f      | 0/5000000   | 48 MB
(1 row)
```

The slot is inactive (replica is down) and retaining WAL. If left unattended, this will fill the disk.

### Step 4 - Check replication configuration on primary

```sql
SHOW wal_level;
```

Expected output:

```
 wal_level
-----------
 replica
(1 row)
```

```sql
SHOW max_wal_senders;
```

Expected output:

```
 max_wal_senders
-----------------
 5
(1 row)
```

The primary is correctly configured for replication. The issue is the replica side.

---

## Resolution

Since this is a single-node lab, we simulate the rebuild by cleaning up the stale state and documenting the correct procedure.

### Step 1 - Drop the stale replication slot

The old slot is no longer needed since we will rebuild the replica from scratch:

```sql
SELECT pg_drop_replication_slot('chaos8_replica_slot');
```

Expected output:

```
 pg_drop_replication_slot
--------------------------

(1 row)
```

### Step 2 - Verify the slot is gone

```sql
SELECT slot_name FROM pg_replication_slots;
```

Expected output:

```
 slot_name
-----------
(0 rows)
```

WAL retention for the old slot is released.

```sql
\q
```

### Step 3 - Update the replica status file

```bash
vi /opt/pgsql/replica_status/replica_info.conf
```

Update the file to reflect the completed rebuild plan:

```
# Replica Status File
# Updated after primary upgrade to PG16.

replica_pg_version=16
primary_pg_version=16
replica_data_directory=/opt/pgsql/data
replica_status=REBUILD_PLANNED
replica_last_lsn=
upgrade_started=2026-04-18T10:00:00Z
upgrade_completed=2026-04-19T12:00:00Z
notes=Old PG15 replica decommissioned. Rebuild with pg_basebackup from PG16 primary.
```

Save and exit (`:wq`).

### Step 4 - Document the rebuild procedure

The correct steps to rebuild the replica (on the actual replica server) are:

1. Stop the old PG15 replica service
2. Remove or rename the old PG15 data directory
3. Install PostgreSQL 16 packages on the replica
4. Run pg_basebackup from the primary:

```
pg_basebackup -h <primary_ip> -p 5432 -U replicator -D /opt/pgsql/data -R -P -Xs
```

5. The `-R` flag creates `standby.signal` and `primary_conninfo` automatically
6. Start the PG16 service on the replica
7. Verify replication with `SELECT * FROM pg_stat_replication;` on the primary

### Step 5 - Create a new replication slot for the rebuilt replica

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT pg_create_physical_replication_slot('replica_slot');
```

Expected output:

```
 pg_create_physical_replication_slot
--------------------------------------
 (replica_slot,)
(1 row)
```

```sql
\q
```

### Step 6 - Verify the configuration is consistent

```bash
cat /opt/pgsql/replica_status/replica_info.conf
```

Both versions should show 16. Status should indicate rebuild planned or completed.

```bash
exit
```

---

## Validation

Run the validation script from the instructor machine.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- Old stale replication slot (chaos8_replica_slot) is removed
- replica_info.conf shows matching versions (both PG16)
- wal_level is set to replica
- A new replication slot exists for future use

---

## Interview Discussion Points

1. **Why can't you upgrade replicas in-place with pg_upgrade?** - `pg_upgrade` modifies system catalogs and data file formats. This requires exclusive write access to the data directory. Replicas are read-only - they replay WAL from the primary but cannot run arbitrary DDL or data modifications. The upgrade process is fundamentally a write operation that replicas cannot perform. The only option is to rebuild the replica from the upgraded primary.

2. **What is the downtime impact of upgrading a primary with replicas?** - The primary upgrade itself requires downtime (typically 5-30 minutes with `pg_upgrade --link`). During this time and until replicas are rebuilt, you have no replica for failover. The total exposure window includes: primary upgrade time + replica rebuild time (which depends on database size and network speed). For a 1TB database over a gigabit network, `pg_basebackup` takes roughly 2-3 hours.

3. **How do you minimize replication rebuild time?** - Use `pg_basebackup` with `--checkpoint=fast` to start immediately. Use `-Xs` (stream WAL) to avoid WAL accumulation. On the network side, ensure dedicated replication bandwidth. Consider using `rsync` with `--existing` to only transfer changed files if you used `pg_upgrade --link` (which creates hard links, meaning most files are identical). Some teams pre-stage the new binary on the replica to reduce setup time.

4. **What happens if you forget to drop the old replication slot?** - WAL files accumulate on the primary because the slot prevents recycling. Eventually, the `pg_wal` directory fills the disk, causing the primary to shut down with a "no space left on device" error. This is one of the most common causes of primary outages during upgrade maintenance windows. Always monitor `pg_replication_slots` for inactive slots.

5. **Can logical replication help with zero-downtime upgrades?** - Yes. With logical replication, you can set up a PG16 subscriber replicating from a PG15 publisher. Once the subscriber is caught up, promote it to primary and redirect application connections. This avoids the pg_upgrade downtime but adds complexity: DDL is not replicated, sequences need manual sync, and large tables take time for initial copy. Tools like `pglogical` and native logical replication (PG 10+) support this pattern.

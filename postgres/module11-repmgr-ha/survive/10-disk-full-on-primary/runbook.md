# Runbook 10 - Disk Full on Primary

**Severity:** Critical - WAL writes failing, transactions blocked, replication stalling
**Time to resolve:** 5-15 minutes

---

## Fix Path

### Step 1: Confirm disk usage on the primary

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

```bash
df -h /var/lib/postgresql/16/main/pg_wal
```

Expected: usage near 100% or partition full.

Also check the overall data directory:

```bash
df -h /var/lib/postgresql/16/main
```

### Step 2: Identify the space hog

```bash
ls -lhS /var/lib/postgresql/16/main/pg_wal/ | head -20
```

Look for files that do not follow the standard WAL segment naming pattern
(24-hex-character filenames like `000000010000000000000001`). A file named
`FILL_DISK_CHAOS` or any non-WAL file is the culprit.

> **Concept - WAL segment naming**: Valid WAL files have names like
> `00000001000000000000002A` (24 hex chars). Any file in pg_wal that does
> not match this pattern is suspicious. The `archive_status` subdirectory
> is normal.

### Step 3: Remove the offending file

```bash
rm -f /var/lib/postgresql/16/main/pg_wal/FILL_DISK_CHAOS
```

Verify space is freed:

```bash
df -h /var/lib/postgresql/16/main/pg_wal
```

Usage should drop significantly.

### Step 4: Check if PostgreSQL is still running

```bash
pg_isready -p 5432
```

```bash
sudo systemctl status postgresql
```

If PostgreSQL crashed due to disk full, restart it:

```bash
sudo systemctl start postgresql
```

If PostgreSQL is running but in a PANIC state, you may need a full restart:

```bash
sudo systemctl restart postgresql
```

### Step 5: Check PostgreSQL logs for errors

```bash
tail -50 /var/log/postgresql/postgresql-16-main.log
```

Look for messages like:
```
PANIC: could not write to file "pg_wal/...": No space left on device
ERROR: could not extend file "...": No space left on device
```

After removing the fill file, these errors should stop. If PostgreSQL
restarted cleanly, look for:
```
LOG: database system is ready to accept connections
```

### Step 6: Verify WAL writes resume

Test a write on the primary:

```sql
INSERT INTO employees(name, department) VALUES ('disk_fix_test', 'SRE');
SELECT count(*) FROM employees;
```

If the write succeeds, WAL is working again.

Check WAL position is advancing:

```sql
SELECT pg_current_wal_lsn();
-- Wait a few seconds
SELECT pg_current_wal_lsn();
```

The LSN should advance between queries.

### Step 7: Verify replication catches up

On the primary:

```bash
psql -c "
SELECT client_addr,
       state,
       sent_lsn,
       replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;"
```

All standbys should show `state = streaming` and `lag_bytes` decreasing to
near zero. If a standby is disconnected, check its logs:

```bash
tail -20 /var/log/postgresql/postgresql-16-main.log
```

If a standby cannot reconnect, restart it:

```bash
sudo systemctl restart postgresql
```

### Step 8: Check for any other large files

Ensure no other space issues remain:

Check for other large non-WAL files:

```bash
find /var/lib/postgresql/16/main/pg_wal -type f ! -name '????????????????????????' \
  ! -path '*/archive_status/*' -ls
```

This finds files in pg_wal whose names do not match the 24-character WAL naming pattern.

Check overall disk usage:

```bash
du -sh /var/lib/postgresql/16/main/pg_wal/
```

```bash
df -h /var/lib/postgresql/16/main
```

> **Concept - WAL retention and disk space**: PostgreSQL keeps WAL segments
> until they are no longer needed by standbys, archiving, or replication slots.
> The `wal_keep_size` parameter sets a minimum WAL to retain. Unused replication
> slots can cause unbounded WAL growth - always monitor slot lag.

### Step 9: Verify full cluster health

```bash
repmgr -f /etc/repmgr.conf cluster show
```

Expected output (yours will differ):
```
 ID | Name         | Role    | Status    | Upstream    | ...
----+--------------+---------+-----------+-------------+----
 1  | pg-repmgr-1  | primary | * running |             | ...
 2  | pg-repmgr-2  | standby |   running | pg-repmgr-1 | ...
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-1 | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-1 | ...
```

All 4 nodes running, replication streaming, no errors.

---

## Key Concepts for Revision

- **WAL and disk space**: PostgreSQL writes all changes to the Write-Ahead Log
  (WAL) before modifying data files. If the WAL partition fills up, PostgreSQL
  cannot write new WAL segments and all transactions fail. This is a complete
  write outage.

- **PANIC on disk full**: When PostgreSQL cannot write WAL, it may enter PANIC
  mode and crash. This is a safety mechanism - it is better to crash than to
  write partial or corrupt WAL, which could make recovery impossible.

- **pg_wal directory contents**: pg_wal contains WAL segment files (16MB each
  by default), an archive_status subdirectory, and potentially temporary files.
  Any non-WAL file in this directory is suspicious and should be investigated.

- **Replication slot WAL retention**: Inactive replication slots prevent WAL
  from being recycled, potentially filling the disk. Always monitor
  pg_replication_slots for slots with large lag. Drop unused slots.

- **Monitoring disk space**: Set alerts at 70%, 80%, and 90% disk usage on
  the WAL and data partitions. By the time you hit 100%, transactions are
  already failing. Proactive monitoring is essential.

- **Recovery from disk full**: The recovery sequence is: free space first (rm
  the offending file), then check if PG needs restart, then verify WAL writes
  resume, then verify replication catches up. Do not restart PG before freeing
  space - it will crash again immediately.

---

## Interview Discussion Points

1. **Disk full prevention**: What monitoring and alerting do you set up to
   prevent disk-full incidents? Discuss threshold-based alerts, trend-based
   prediction, and automatic WAL cleanup. What disk usage percentage triggers
   your pager?

2. **WAL partition sizing**: How do you size the WAL partition? What factors
   influence WAL generation rate (write volume, full_page_writes, checkpoint
   interval)? Should pg_wal be on a separate partition from the data directory?

3. **Replication slot dangers**: How can an inactive replication slot fill
   your disk? Discuss max_slot_wal_keep_size (PG 13+), monitoring slot lag,
   and automatic slot cleanup policies.

4. **Emergency disk space recovery**: Beyond removing obvious fill files, what
   else can you do to free space in an emergency? Discuss pg_wal archival,
   dropping old WAL with pg_archivecleanup, removing temp files, and the
   reserved_space trick (pre-allocating a dummy file you can delete in
   emergencies).

5. **Checkpoint tuning**: How does checkpoint_completion_target and
   checkpoint_timeout affect WAL generation and disk usage? Discuss the
   tradeoff between checkpoint frequency, recovery time, and WAL volume.

6. **Disk full vs network partition**: Compare the blast radius of a disk-full
   event vs a network partition. Which is easier to detect? Which is easier
   to resolve? Which has a higher risk of data loss?

7. **Cloud vs on-prem disk management**: How does disk management differ in
   cloud environments (EBS, Persistent Disk) vs on-prem? Discuss auto-scaling
   volumes, IOPS provisioning, and the risk of io1/gp3 credit exhaustion
   mimicking a disk-full scenario.

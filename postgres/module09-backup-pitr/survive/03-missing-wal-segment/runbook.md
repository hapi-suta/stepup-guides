# Runbook 03 - Missing WAL Segment

**Severity:** High - PITR capability is broken, recovery to certain points is impossible
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Identify the missing segment

Attempt a PITR dry run or check pgBackRest verify. First, switch to the postgres user:

```bash
sudo -iu postgres
```

Run pgBackRest's verify command. The `--stanza` flag tells pgBackRest which backup configuration to check:

```bash
pgbackrest --stanza=main verify
```

Expected output (yours will differ):
```
ERROR: [044]: WAL segment 000000010000000000000006 is missing
       HINT: this is a gap in the WAL archive
```

Or look at the archive directory for gaps. List WAL files in order:

```bash
ls -1 /opt/pgsql/backup/archive/ | sort | head -20
```

```bash
exit
```

Look for a gap in the sequence (e.g., 000000010000000000000005 exists, 000000010000000000000006 is missing, 000000010000000000000007 exists).

> **Concept - WAL Continuity**: WAL segments must be continuous for PITR to work. Each segment picks up exactly where the previous one left off. A gap means the database cannot replay past that point - recovery stops at the last segment before the gap.

### Step 2: Check the primary's pg_wal directory

The missing segment might still exist on the primary if it has not been recycled. SSH to [NODE1] and switch to the postgres user:

```bash
sudo -iu postgres
```

List the WAL directory contents to look for the missing segment:

```bash
ls /opt/pgsql/data/pg_wal/ | sort
```

Look for the missing segment name. PostgreSQL keeps WAL segments in pg_wal until they are archived and no longer needed for replication or crash recovery.

```bash
exit
```

### Step 3: Copy the segment to the archive

If found on the primary, switch to the postgres user on NODE1:

```bash
sudo -iu postgres
```

Copy the missing segment from the primary's pg_wal directory to NODE2's archive. The `scp` command securely copies files between servers:

```bash
scp /opt/pgsql/data/pg_wal/[SEGMENT_NAME] \
  [SSH_USER]@[NODE2]:/opt/pgsql/backup/archive/
```

```bash
exit
```

If the archive uses compression, compress the copied file on NODE2 to match. Use the same compression format as the other archive files (gzip, lz4, or zstd):

```bash
gzip /opt/pgsql/backup/archive/[SEGMENT_NAME]
```

Ensure ownership and permissions match the other archive files:

```bash
# On NODE2
sudo chown postgres:postgres /opt/pgsql/backup/archive/[SEGMENT_NAME]*
sudo chmod 640 /opt/pgsql/backup/archive/[SEGMENT_NAME]*
```

> **Concept - WAL Lifecycle**: A WAL segment is created on the primary, written to, then archived via archive_command. After archiving, the primary may recycle the file. If archiving failed before the file was recycled, the segment is lost forever. This is why monitoring archive_command failures is critical.

### Step 4: Verify archive continuity

List the archive and confirm no more gaps:

```bash
ls -1 /opt/pgsql/backup/archive/ | sort
```

Or run pgBackRest verify again as the postgres user:

```bash
sudo -iu postgres
```

```bash
pgbackrest --stanza=main verify
```

Expected: No errors about missing WAL segments.

```bash
exit
```

### Step 5: Test PITR capability

Do a quick PITR to a scratch location to confirm recovery works. Switch to the postgres user:

```bash
sudo -iu postgres
```

Restore a backup to a temporary directory. The `--pg1-path` flag sets the restore destination, `--type=immediate` stops recovery as soon as consistency is reached, and `--target-action=promote` makes the instance writable after recovery:

```bash
pgbackrest --stanza=main \
  --pg1-path=/tmp/pg-pitr-test \
  --type=immediate \
  --target-action=promote \
  restore
```

Start the restored instance on port 5433 so it does not conflict with the production server. The `-D` flag points to the data directory, and `-o` passes options (here, the port) to the postgres process:

```bash
/usr/pgsql-16/bin/pg_ctl -D /tmp/pg-pitr-test -o "-p 5433" start
```

Verify the instance promoted successfully. A result of `f` (false) means it is no longer in recovery - it promoted and is writable:

```bash
/usr/pgsql-16/bin/psql -p 5433 -c "SELECT pg_is_in_recovery();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

Stop the test instance now that verification is complete:

```bash
/usr/pgsql-16/bin/pg_ctl -D /tmp/pg-pitr-test stop
```

```bash
exit
```

Remove the temporary data directory to free disk space:

```bash
sudo rm -rf /tmp/pg-pitr-test
```

### Step 6: Force a WAL switch to confirm archiving is current

On NODE1, switch to the postgres user:

```bash
sudo -iu postgres
```

Force a WAL segment switch. This creates a new segment and triggers archiving so you can confirm the archive pipeline is working:

```bash
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
```

```bash
exit
```

Wait a few seconds, then verify the new segment appears in the archive on [NODE2].

---

## Key Concepts for Revision

- **WAL segments are numbered sequentially** in the format [timeline][log][segment]. A gap anywhere in the sequence breaks PITR for all target times after the gap.
- **pg_wal on the primary** retains segments until they are archived (confirmed by archive_command returning success) and no longer needed for replication. This is your best chance to recover a missing segment.
- **wal_keep_size** (PG 13+) or wal_keep_segments (older) forces the primary to retain extra WAL beyond what replication needs. This provides a buffer but is not a substitute for monitoring archive failures.
- **pgBackRest verify** checks the entire archive chain for continuity. Run it regularly as a monitoring check, not just during incidents.
- **archive_command** should be monitored via pg_stat_archiver. If failed_count is increasing, segments are being lost.
- **Compression format consistency** matters - if your archive uses .gz files, a restored segment must also be compressed to match, or your restore_command must handle both.
- **WAL segment size** is 16 MB by default. Each segment represents a window of database changes. Losing one segment loses all transactions within that window.

---

## Interview Discussion Points

1. **Monitoring WAL archiving**: What metrics from pg_stat_archiver do you monitor? How quickly would you detect a failed archive_command in production?

2. **WAL retention strategies**: How do you balance disk usage on the primary (wal_keep_size) against the risk of losing segments? When would you increase retention?

3. **Archive storage reliability**: What happens if your archive storage (NFS, S3, local disk) has an outage? How do you prevent WAL segments from being recycled before they are archived?

4. **Partial archive recovery**: You have a gap at segment 0000000100000000000000A0. Segments before and after exist. Can you still do PITR? What are your options?

5. **pgBackRest vs archive_command**: How does pgBackRest's archive-push differ from a raw archive_command? What advantages does it provide for reliability and verification?

6. **Cross-region archiving**: In a multi-datacenter setup, how do you ensure WAL archives are replicated to a remote site? What is the RPO impact of async archive replication?

7. **Timeline and WAL interaction**: After a failover, the new primary starts a new timeline. How does this affect WAL archiving and PITR? Can you restore across timeline boundaries?

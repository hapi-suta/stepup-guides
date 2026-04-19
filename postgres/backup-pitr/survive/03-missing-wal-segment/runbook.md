# Runbook 03 - Missing WAL Segment

**Severity:** High - PITR capability is broken, recovery to certain points is impossible
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Identify the missing segment

Attempt a PITR dry run or check pgBackRest verify:

```bash
sudo -u postgres pgbackrest --stanza=main verify
```

Or look at the archive directory for gaps. List WAL files in order:

```bash
ls -1 /opt/pgsql/backup/archive/ | sort | head -20
```

Look for a gap in the sequence (e.g., 000000010000000000000005 exists, 000000010000000000000006 is missing, 000000010000000000000007 exists).

> **Concept - WAL Continuity**: WAL segments must be continuous for PITR to work. Each segment picks up exactly where the previous one left off. A gap means the database cannot replay past that point - recovery stops at the last segment before the gap.

### Step 2: Check the primary's pg_wal directory

The missing segment might still exist on the primary if it has not been recycled:

```bash
# SSH to [NODE1]
sudo -u postgres ls /opt/pgsql/data/pg_wal/ | sort
```

Look for the missing segment name. PostgreSQL keeps WAL segments in pg_wal until they are archived and no longer needed for replication or crash recovery.

### Step 3: Copy the segment to the archive

If found on the primary:

```bash
# From NODE1, copy to NODE2's archive
sudo -u postgres scp /opt/pgsql/data/pg_wal/[SEGMENT_NAME] \
  [SSH_USER]@[NODE2]:/opt/pgsql/backup/archive/

# If the archive uses compression, compress it
gzip /opt/pgsql/backup/archive/[SEGMENT_NAME]
# or use the same compression the other files use (lz4, zstd)
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

Or run pgBackRest verify again:

```bash
sudo -u postgres pgbackrest --stanza=main verify
```

Expected: No errors about missing WAL segments.

### Step 5: Test PITR capability

Do a quick PITR to a scratch location to confirm recovery works:

```bash
sudo -u postgres pgbackrest --stanza=main \
  --pg1-path=/tmp/pg-pitr-test \
  --type=immediate \
  --target-action=promote \
  restore

sudo -u postgres /usr/pgsql-16/bin/pg_ctl \
  -D /tmp/pg-pitr-test -o "-p 5433" start

sudo -u postgres /usr/pgsql-16/bin/psql -p 5433 -c "SELECT pg_is_in_recovery();"
# Expected: f (promoted successfully)

# Clean up
sudo -u postgres /usr/pgsql-16/bin/pg_ctl -D /tmp/pg-pitr-test stop
rm -rf /tmp/pg-pitr-test
```

### Step 6: Force a WAL switch to confirm archiving is current

```bash
# On NODE1
sudo -u postgres /usr/pgsql-16/bin/psql -p 5432 -c "SELECT pg_switch_wal();"
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

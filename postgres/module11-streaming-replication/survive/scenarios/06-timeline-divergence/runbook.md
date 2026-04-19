# Runbook 06 - Timeline Divergence

**Severity:** Critical - Both nodes are down, data has diverged
**Time to resolve:** 10-20 minutes

---

## Fix Path

### Step 1: Understand the situation

Both PostgreSQL nodes are stopped. They are on different timelines because the standby was promoted while the original primary still had uncommitted WAL.

SSH to each node and check their timeline:

```bash
# On [NODE1]
sudo -u postgres /usr/lib/postgresql/16/bin/pg_controldata /var/lib/postgresql/16/main | grep 'Latest checkpoint.*TimeLineID'

# On [NODE2]
sudo -u postgres /usr/lib/postgresql/16/bin/pg_controldata /var/lib/postgresql/16/main | grep 'Latest checkpoint.*TimeLineID'
```

### Step 2: Decide which node becomes the primary

Choose the node with the most up-to-date data. Typically this is the node that was promoted (the one on the higher timeline). For this scenario, [NODE2] was promoted and received additional writes, so it should be the primary.

### Step 3: Start the chosen primary

On [NODE2]:

```bash
sudo systemctl start postgresql
```

Verify it is running as a primary:

```bash
sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (false).

> **Concept - Timeline IDs**: Every promotion increments the timeline. Timeline history files (e.g., 00000002.history) record where the fork happened. A standby can only follow a primary on a compatible timeline.

### Step 4: Rebuild the other node as a standby

You have two options:

**Option A - pg_rewind (fast, if wal_log_hints or checksums enabled):**

On [NODE1], with [NODE2] running:

```bash
sudo systemctl stop postgresql  # ensure it is stopped
sudo -u postgres /usr/lib/postgresql/16/bin/pg_rewind \
  --target-pgdata=/var/lib/postgresql/16/main \
  --source-server="host=[NODE2] port=5432 user=replicator dbname=postgres" \
  --progress
```

After pg_rewind completes, configure [NODE1] as a standby:

```bash
sudo -u postgres touch /var/lib/postgresql/16/main/standby.signal
sudo -u postgres psql -c "ALTER SYSTEM SET primary_conninfo = 'host=[NODE2] port=5432 user=replicator application_name=standby1';"
```

> **Concept - pg_rewind**: pg_rewind synchronizes a diverged data directory by copying only the changed blocks from the source (the new primary). It requires wal_log_hints=on or data checksums. It is much faster than a full pg_basebackup.

**Option B - pg_basebackup (full rebuild, always works):**

On [NODE1]:

```bash
sudo systemctl stop postgresql
sudo -u postgres rm -rf /var/lib/postgresql/16/main/*
sudo -u postgres pg_basebackup \
  -h [NODE2] -p 5432 -U replicator \
  -D /var/lib/postgresql/16/main \
  -R -P -X stream -C -S standby_slot
```

The `-R` flag automatically creates standby.signal and sets primary_conninfo.

### Step 5: Start the rebuilt standby

On [NODE1]:

```bash
sudo systemctl start postgresql
```

Check the log for successful startup:

```bash
sudo tail -20 /var/log/postgresql/postgresql-16-main.log
```

Look for: "started streaming WAL from primary".

### Step 6: Verify replication is working

On [NODE2] (the primary):

```bash
sudo -u postgres psql -c "
  SELECT client_addr, state,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected: `state` is `streaming`.

### Step 7: Verify data consistency

On both nodes:

```sql
SELECT count(*) FROM employees;
```

Counts should match. The standby should have all data from the primary.

---

## Key Concepts for Revision

- **Timeline divergence** occurs when two nodes accept writes independently. This is the PostgreSQL equivalent of a "split-brain" - both nodes believe they are authoritative.
- **pg_rewind** works by reading the WAL of both nodes to find the divergence point, then copying only the blocks that differ. Requirements: wal_log_hints=on or data checksums enabled, and the source WAL must still be available.
- **pg_basebackup** is the brute-force approach - it copies the entire data directory. It is slower but always works regardless of how far the nodes have diverged.
- **Timeline history files** (e.g., 00000002.history in pg_wal) record when and where each timeline forked. The standby uses these to verify it can follow the primary's timeline.
- **wal_log_hints** must be enabled for pg_rewind to work. It causes PostgreSQL to write full-page images of hint-bit updates to WAL, which pg_rewind needs to detect changed pages.
- **Data loss risk**: When nodes diverge, any writes on the "losing" node are discarded during pg_rewind or pg_basebackup. You must decide which node's data to keep before proceeding.
- **Prevention**: Use synchronous replication or a consensus-based HA tool (Patroni) to prevent both nodes from accepting writes simultaneously.

---

## Interview Discussion Points

1. **Timeline fork detection**: How do you detect that two nodes are on different timelines? What monitoring would catch this before it becomes a crisis?

2. **pg_rewind prerequisites**: What must be configured before pg_rewind can work? Explain wal_log_hints, data checksums, and the requirement for available WAL on the source.

3. **Choosing the winner**: In a split-brain situation with writes on both nodes, how do you decide which node's data to keep? What tools can you use to compare the data on each node?

4. **pg_rewind vs pg_basebackup**: When would you choose one over the other? Discuss the tradeoffs in terms of speed, data requirements, and failure modes.

5. **Preventing timeline divergence**: How do tools like Patroni, repmgr, and pg_auto_failover prevent split-brain? Explain the role of DCS (etcd/ZooKeeper/Consul) in fencing.

6. **Synchronous replication**: How does synchronous_commit = remote_apply prevent data loss during failover? What is the performance cost? When is it worth it?

7. **Recovery from divergence in production**: Walk through a real-world scenario where you discovered timeline divergence in production. What was your recovery plan? How long did it take?

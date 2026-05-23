# Runbook 06 - repmgr Metadata Desync

**Severity:** High - repmgr shows incorrect topology, risking wrong failover decisions
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Observe the inconsistency with repmgr cluster show

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

From any node:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Note which node repmgr claims is the primary. This may be WRONG.

### Step 2: Verify actual roles with pg_is_in_recovery()

Check each data node directly, one at a time:

```bash
psql -h pg-repmgr-1 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-2 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-3 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

Expected: exactly ONE node returns `f` (the real primary). Compare this
with what repmgr cluster show reported. The mismatch is the bug.

> **Concept - pg_is_in_recovery()**: This function is the ground truth for
> whether a node is a primary (`f`) or standby (`t`). repmgr metadata can
> lie, but pg_is_in_recovery() always reflects actual PostgreSQL state.

### Step 3: Check replication is still streaming

On the real primary:

```bash
psql -c "
SELECT client_addr, state, sent_lsn, replay_lsn
FROM pg_stat_replication;"
```

Replication should still be streaming even though metadata is wrong. The data
plane is independent of repmgr metadata.

### Step 4: Fix the metadata by re-registering the primary

On the actual primary node:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf primary register --force
```

This overwrites the incorrect type in repmgr.nodes for this node.

### Step 5: Re-register each standby

On each actual standby node:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

This corrects the standby entries in repmgr.nodes.

### Step 6: Verify repmgr cluster show matches reality

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected: the real primary shows `primary | * running`, standbys show
`standby | running`, witness shows `witness | * running`.

Cross-check with pg_is_in_recovery() again to confirm they agree.

### Step 7: Restart repmgrd on all nodes

```bash
exit
```

Run this on each node one at a time:

```bash
ssh root@pg-repmgr-1 "systemctl start repmgr-16"
```

```bash
ssh root@pg-repmgr-2 "systemctl start repmgr-16"
```

```bash
ssh root@pg-repmgr-3 "systemctl start repmgr-16"
```

```bash
ssh root@pg-repmgr-w "systemctl start repmgr-16"
```

### Step 8: Verify full cluster health

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
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

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster crosscheck
```

All 4 nodes running, all roles correct, replication streaming.

```bash
exit
```

---

## Key Concepts for Revision

- **repmgr.nodes is metadata, not truth**: The repmgr.nodes table stores what
  repmgr *believes* about the cluster topology. It can become stale or
  corrupted. The actual PostgreSQL state (pg_is_in_recovery, pg_stat_replication)
  is always the source of truth. Never blindly trust repmgr cluster show.

- **Metadata vs data plane**: repmgr metadata corruption does not affect
  PostgreSQL replication. Standbys continue streaming from the primary regardless
  of what repmgr.nodes says. The danger is that the NEXT failover decision will
  be based on wrong metadata.

- **Re-registration fixes metadata**: `repmgr primary register --force` and
  `repmgr standby register --force` overwrite the node's entry in repmgr.nodes
  with the correct type based on actual PostgreSQL state. This is the safest
  way to fix metadata - it reads reality and writes it to the metadata table.

- **repmgrd self-healing**: Under normal operation, repmgrd periodically checks
  the cluster state and can detect inconsistencies. Stopping repmgrd (as the
  inject script did) prevents this self-healing behavior.

- **Danger of wrong metadata during failover**: If repmgr thinks a standby is
  the primary, a failover election may skip the actual best candidate or try
  to promote a node that is already primary. This can lead to split-brain or
  failed promotions.

- **Manual UPDATE vs re-register**: You can fix metadata with a direct SQL
  UPDATE to repmgr.nodes, but re-register is safer because it also updates
  conninfo, upstream_node_id, and other fields that might be stale.

---

## Interview Discussion Points

1. **Metadata trust boundaries**: When troubleshooting a repmgr cluster, how
   do you decide which information sources to trust? Rank these in order of
   reliability: repmgr cluster show, pg_is_in_recovery(), pg_stat_replication,
   pg_controldata. Why does this ordering matter?

2. **Detection strategies**: How would you proactively detect metadata desync
   before it causes a bad failover? Discuss monitoring queries that compare
   repmgr.nodes types against pg_is_in_recovery() on each node.

3. **Root cause analysis**: What could cause repmgr metadata to desync in
   production (not just malicious UPDATEs)? Discuss interrupted registrations,
   failed switchovers, network partitions during promotion, and manual pg_ctl
   promote without repmgr.

4. **Patroni comparison**: How does Patroni (with etcd/Consul) handle the
   equivalent problem? Discuss the DCS as a single source of truth vs repmgr's
   distributed metadata table. What are the tradeoffs?

5. **Automation safety**: Should your automated failover tools validate metadata
   against reality before acting? What pre-flight checks would you add to a
   promote_command script?

6. **Auditing changes**: repmgr.events logs registration changes. How would
   you use this table to detect unauthorized metadata modifications? Should
   you set up alerts on repmgr.events for unexpected type changes?

7. **Recovery without repmgr**: If repmgr metadata is completely destroyed
   (the repmgr schema dropped), can you rebuild it from scratch without
   downtime? Walk through the steps: create extension, register primary,
   register each standby, register witness.

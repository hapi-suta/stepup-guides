# Runbook 07 - Failed Switchover Rollback

**Severity:** Critical - No primary available, all writes blocked
**Time to resolve:** 10-20 minutes

---

## Fix Path

### Step 1: Assess actual state of every node

Check which nodes have PostgreSQL running and their role:

```bash
for host in pg-repmgr-1 pg-repmgr-2 pg-repmgr-3; do
  echo -n "$host PG: "
  pg_isready -h $host -p 5432 2>/dev/null && echo "UP" || echo "DOWN"
done
```

For each running node, check if it is primary or standby:

```bash
for host in pg-repmgr-1 pg-repmgr-2 pg-repmgr-3; do
  echo -n "$host role: "
  sudo -iu postgres psql -h $host -U repmgr -d repmgr -tAc \
    "SELECT pg_is_in_recovery();" 2>/dev/null || echo "unreachable"
done
```

Expected: the old primary is DOWN, all running nodes return `t` (standby).
There is no primary - that is the problem.

> **Concept - Switchover vs Failover**: A switchover is a planned role swap
> where the primary is demoted before the standby is promoted. If the process
> is interrupted between demotion and promotion, you end up with zero primaries.

### Step 2: Check WAL positions to pick the best promotion candidate

On each running standby:

```bash
sudo -iu postgres psql -c "
SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn();"
```

The standby with the highest receive_lsn has the most data. Promote that one
(typically the intended switchover target).

### Step 3: Promote the target standby

On the intended target:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf standby promote
```

Verify it is now primary:

```bash
sudo -iu postgres psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f`.

Test a write:

```sql
INSERT INTO employees(name, department) VALUES ('switchover_fix', 'SRE');
SELECT count(*) FROM employees;
```

### Step 4: Redirect other standbys to follow the new primary

On each standby that was NOT promoted:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf standby follow \
  --upstream-node-id=<NEW_PRIMARY_NODE_ID>
```

Verify replication is streaming:

```bash
sudo -iu postgres psql -h <NEW_PRIMARY> -U repmgr -d repmgr -c \
  "SELECT client_addr, state FROM pg_stat_replication;"
```

### Step 5: Rejoin the old primary as a standby

Start PostgreSQL on the old primary first, then rejoin:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails, do a full reclone:

```bash
sudo systemctl stop postgresql
sudo -iu postgres repmgr -f /etc/repmgr.conf \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr \
  standby clone --force
sudo systemctl start postgresql
sudo -iu postgres repmgr -f /etc/repmgr.conf standby register --force
```

### Step 6: Re-register the primary to fix metadata

On the new primary:

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf primary register --force
```

This ensures the metadata reflects the actual promotion.

### Step 7: Restart repmgrd on all nodes

```bash
for host in pg-repmgr-1 pg-repmgr-2 pg-repmgr-3 pg-repmgr-w; do
  ssh root@$host "sudo systemctl start repmgrd"
done
```

### Step 8: Verify full cluster health

```bash
sudo -iu postgres repmgr -f /etc/repmgr.conf cluster show
sudo -iu postgres repmgr -f /etc/repmgr.conf cluster crosscheck
```

All 4 nodes running: 1 primary, 2 standbys, 1 witness. repmgrd active on all.

---

## Key Concepts for Revision

- **Switchover atomicity**: A switchover is a two-phase operation - demote the
  old primary, then promote the new one. Unlike a database transaction, this is
  NOT atomic. If the process is interrupted between phases, you get the worst
  outcome: zero primaries, total write outage.

- **Demotion before promotion**: repmgr's switchover sequence intentionally
  demotes first to prevent split-brain (two primaries). The tradeoff is that an
  interrupted switchover results in no primaries rather than two primaries.
  This is safer from a data integrity perspective.

- **WAL position comparison**: When choosing which standby to promote, always
  check pg_last_wal_receive_lsn(). The standby with the highest LSN has
  received the most WAL from the old primary and will lose the least data
  upon promotion.

- **standby follow**: After promoting a new primary, remaining standbys are
  still configured to follow the old primary. `repmgr standby follow` updates
  their recovery configuration (primary_conninfo) to point to the new primary
  and restarts replication.

- **Metadata cleanup after manual intervention**: When you manually promote and
  follow, the repmgr.nodes metadata may not reflect reality. Always re-register
  nodes (`primary register --force`, `standby register --force`) to sync
  metadata with the actual cluster state.

- **repmgrd dependency on clean state**: repmgrd reads repmgr.nodes at startup.
  If the metadata is wrong when repmgrd starts, it may make incorrect decisions.
  Always fix metadata before restarting repmgrd.

---

## Interview Discussion Points

1. **Switchover safety**: What pre-checks should a switchover perform before
   starting? Discuss replication lag thresholds, standby health verification,
   lock conflicts on the primary, and connection draining.

2. **Rollback strategy**: If a switchover fails mid-way, is it safer to roll
   forward (promote the target) or roll back (restart the old primary)?
   What factors influence this decision? What if the old primary's data
   directory was already modified?

3. **Planned maintenance windows**: How do you communicate and coordinate a
   switchover with application teams? Discuss maintenance windows, connection
   draining, PgBouncer PAUSE, and graceful client disconnection.

4. **Automation guardrails**: What safety checks would you build into a
   switchover automation script? Discuss pre-flight checks, progress
   monitoring, automatic rollback on timeout, and post-switchover validation.

5. **Zero-downtime switchover**: Is it possible to achieve zero-downtime
   during a planned switchover? Discuss PgBouncer with PAUSE/RESUME, multi-host
   connection strings, and the brief window where no primary is available.

6. **Switchover vs failover in practice**: When do you use switchover (planned)
   vs failover (unplanned)? How does your DR plan account for both? Should your
   team practice switchovers regularly?

7. **Post-switchover validation checklist**: After a successful switchover,
   what do you verify? Discuss replication streaming, application connectivity,
   backup schedule updates, monitoring reconfiguration, and DNS/VIP updates.

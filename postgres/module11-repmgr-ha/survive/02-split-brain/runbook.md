# Runbook 02 - Split-Brain (Network Partition)

**Severity:** Critical - Risk of two primaries accepting conflicting writes
**Time to resolve:** 5-15 minutes

---

## Fix Path

### Step 1: Identify the partition

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

Check repmgr logs on the standbys for connection failures:

```bash
tail -50 /var/lib/pgsql/16/data/log/repmgrd.log
```

Look for messages like:
```
[WARNING] unable to ping "host=pg-repmgr-1 user=repmgr dbname=repmgr"
[INFO] checking state of node "pg-repmgr-1" (ID: 1) ...
[WARNING] node "pg-repmgr-1" (ID: 1) is not reachable
```

### Step 2: Check if repmgrd auto-promoted

If repmgrd had enough quorum (standbys + witness agree the primary is unreachable),
it will have promoted a standby. Check from any standby:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Look for a new primary. If a standby was promoted, verify the old primary is
marked as `- failed`.

### Step 3: Verify only ONE primary exists

This is the critical split-brain check. Test every data node:

Run this on each data node one at a time:

```bash
psql -h pg-repmgr-1 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-2 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-3 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

The `-t` flag removes headers, `-A` removes alignment padding, `-c` runs a single command.

Expected: exactly ONE node returns `f` (primary). If TWO nodes return `f`, you
have split-brain - proceed to emergency fencing (Step 3b).

### Step 3b: Emergency fencing (if split-brain occurred)

If the old primary is still accepting writes while isolated:

On the old primary - stop PostgreSQL immediately:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

```bash
sudo systemctl stop repmgr-16
```

The old primary must be stopped before the partition is lifted. Otherwise,
clients might write to both primaries.

### Step 4: Resolve the network partition

On the partitioned primary, flush iptables rules:

```bash
ssh root@<OLD_PRIMARY> 'iptables -F'
```

Verify connectivity is restored:

```bash
ssh root@<OLD_PRIMARY> 'pg_isready -h pg-repmgr-2 -p 5432'
```

### Step 5: Rejoin the old primary as a standby

Switch to the postgres user on the old primary:

```bash
sudo -iu postgres
```

If PostgreSQL is still running, stop it first:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

```bash
sudo systemctl stop repmgr-16
```

```bash
sudo -iu postgres
```

Rejoin using pg_rewind:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails, do a full reclone:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr \
  standby clone --force
```

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

### Step 6: Restart repmgrd on the rejoined node

```bash
exit
```

```bash
sudo systemctl start repmgr-16
```

### Step 7: Verify full cluster health

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
 1  | pg-repmgr-1  | standby |   running | pg-repmgr-2 | ...
 2  | pg-repmgr-2  | primary | * running |             | ...
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-2 | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-2 | ...
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster crosscheck
```

Expected output (yours will differ):
```
 Name         | ID | 1 | 2 | 3 | 4
--------------+----+---+---+---+---
 pg-repmgr-1  |  1 | * | * | * | *
 pg-repmgr-2  |  2 | * | * | * | *
 pg-repmgr-3  |  3 | * | * | * | *
 pg-repmgr-w  |  4 | * | * | * | *
```

All 4 nodes should be running with full connectivity.

```bash
exit
```

---

## Key Concepts for Revision

- **Split-brain** means two nodes both think they are the primary and accept
  conflicting writes. This is the worst possible HA failure because reconciling
  divergent data is extremely difficult and sometimes impossible.

- **Witness role in partition detection**: The witness acts as a tiebreaker. If
  a standby cannot reach the primary but CAN reach the witness, and the witness
  also cannot reach the primary, then the primary is likely down (not just a
  local network issue). If the standby cannot reach the witness either, repmgrd
  should NOT promote - the standby might be the isolated node.

- **Fencing**: Preventing the old primary from accepting writes during a partition.
  repmgr does not provide physical fencing (like STONITH). In production, you
  need external mechanisms: VIP withdrawal, firewall rules, or storage fencing.

- **iptables for simulation**: We used iptables to simulate a network partition.
  In production, partitions happen due to switch failures, cable pulls, or
  misconfigured firewall rules. The behavior is similar - some nodes can see
  each other while others cannot.

- **Quorum**: repmgr requires a majority of registered nodes to agree that the
  primary is down before promoting. In a 4-node cluster (3 data + 1 witness),
  a majority is 3. If only 1 standby detects the failure, it will not promote.

- **recovery after partition**: Once the partition is lifted, the old primary
  must be stopped and rejoined as a standby. It cannot simply resume as primary
  because the new primary may have accepted writes during the partition.

---

## Interview Discussion Points

1. **Preventing split-brain**: What mechanisms does repmgr use to prevent
   split-brain? How does the witness node contribute? What are the limitations
   compared to a consensus-based system like Patroni+etcd?

2. **Asymmetric partitions**: What happens if NODE2 can see the primary but
   NODE3 cannot? Will repmgrd still trigger a failover? How does partial
   connectivity affect the election?

3. **Fencing strategies**: repmgr does not have built-in STONITH. What external
   fencing mechanisms would you deploy in production? Discuss VIP-based fencing,
   watchdog timers, and cloud provider APIs for stopping instances.

4. **Client behavior during partition**: How should applications handle a network
   partition? Discuss connection timeouts, retry logic, multi-host connection
   strings, and read-only vs read-write routing.

5. **Detecting silent split-brain**: How would you detect if split-brain occurred
   and both primaries accepted writes? Discuss comparing WAL positions, table
   row counts, and checksums across nodes after the partition resolves.

6. **Recovery from actual split-brain**: If both nodes accepted conflicting writes,
   how do you reconcile the data? Discuss logical replication for selective replay,
   pg_dump/restore, and application-level conflict resolution.

7. **Witness node availability**: What happens if the witness is also down during
   a primary failure? How does repmgr behave without quorum? Should you run
   multiple witness nodes?

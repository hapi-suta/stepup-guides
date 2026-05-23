# Runbook 04 - Witness Failure During Primary Crash

**Severity:** Critical - Primary down, witness unavailable for quorum
**Time to resolve:** 10-15 minutes

---

## Fix Path

### Step 1: Check if auto-failover occurred

On either standby, switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

```bash
tail -50 /var/lib/pgsql/16/data/log/repmgrd.log
```

Look for promotion messages. Without the witness, repmgrd may not have reached
quorum, and the standbys may still be in recovery mode waiting.

### Step 2: Check standby status

```bash
psql -c "SELECT pg_is_in_recovery();"
```

If `t` on both standbys, auto-failover did NOT occur. Proceed with manual
promotion.

### Step 3: Manually promote the best standby

Choose the standby with the lowest replication lag. Check from each standby:

```bash
psql -c "
SELECT pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();"
```

Promote the standby that received the most WAL (highest `pg_last_wal_receive_lsn`):

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby promote
```

Verify:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f`.

### Step 4: Redirect the other standby

On the standby that was NOT promoted:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby follow \
  --upstream-node-id=<NEW_PRIMARY_NODE_ID>
```

### Step 5: Verify writes

On the new primary:

```sql
INSERT INTO employees(name, department) VALUES ('witness_fail_test', 'ops');
SELECT count(*) FROM employees;
```

### Step 6: Bring the witness back

On NODE4:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

```bash
sudo systemctl start repmgr-16
```

Re-register the witness to point at the new primary:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf witness register --force \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr
```

### Step 7: Rejoin the old primary as a standby

On the old primary:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails:

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

```bash
sudo -iu postgres
```

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

### Step 8: Restart repmgrd on the old primary

```bash
exit
```

```bash
sudo systemctl start repmgr-16
```

### Step 9: Verify full cluster health

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

All 4 nodes should be running with correct roles.

```bash
exit
```

---

## Key Concepts for Revision

- **Witness as quorum voter**: The witness exists to provide a tiebreaker vote
  in failover elections. When the witness is down, the remaining nodes may not
  have enough votes for quorum, blocking automatic failover.

- **Quorum calculation**: In a 4-node cluster (3 data + 1 witness), quorum
  requires a majority (3 out of 4). With the witness and primary both down,
  only 2 nodes remain - below quorum. repmgrd correctly refuses to auto-promote
  because it cannot distinguish between "primary is down" and "I am partitioned."

- **Manual override**: When you KNOW the primary is down (not just a network
  issue), manual promotion is the right call. The quorum requirement is a safety
  net, not an absolute rule. A skilled DBA makes the judgment call.

- **Choosing which standby to promote**: When multiple standbys are available,
  promote the one with the highest `pg_last_wal_receive_lsn`. This minimizes
  potential data loss because that standby received the most WAL before the
  primary went down.

- **Witness recovery**: The witness does not hold data, so bringing it back is
  trivial - just start PostgreSQL and re-register. There is no data recovery
  or WAL replay needed.

- **Dependency chain**: The witness's purpose is to prevent false failovers.
  When the witness fails first, you lose that protection. This is why production
  deployments should monitor witness health and alert when it goes down - even
  though nothing breaks immediately.

---

## Interview Discussion Points

1. **Witness redundancy**: Should you run multiple witness nodes? What are the
   tradeoffs of adding a second witness vs adding a third data standby?

2. **Quorum design**: How does the number of nodes affect quorum requirements?
   Compare 3-node (no witness needed), 4-node (witness needed), and 5-node
   configurations. What is the maximum number of simultaneous failures each
   can tolerate?

3. **Manual vs automatic failover**: In this scenario, repmgrd correctly
   blocked auto-failover due to insufficient quorum. But the primary was
   genuinely down. How do you build operational procedures that allow manual
   override while still maintaining safety? Discuss break-glass procedures.

4. **Witness monitoring**: What alerting would you set up for the witness node?
   Why is "witness is down" a warning-level alert even though nothing breaks
   immediately? How does it relate to the concept of "defense in depth"?

5. **Cloud witness placement**: If your data nodes are in us-east-1, should the
   witness be in us-east-1 (same region, different AZ) or us-west-2 (different
   region)? Discuss latency vs independence tradeoffs.

6. **Comparison with Patroni**: How does Patroni handle the equivalent scenario
   (etcd down + primary down)? What is the role of the DCS (Distributed
   Configuration Store) vs repmgr's witness approach? Which provides stronger
   consistency guarantees?

7. **Recovery order**: In this scenario, should you bring the witness back before
   or after promoting a standby? Does it matter? Why?

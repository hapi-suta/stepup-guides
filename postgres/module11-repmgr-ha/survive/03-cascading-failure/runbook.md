# Runbook 03 - Cascading Failure (Primary + Standby Down)

**Severity:** Critical - Only one data node remains, zero redundancy
**Time to resolve:** 15-25 minutes

---

## Fix Path

### Step 1: Assess the damage

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

Check which nodes are still reachable:

Check each node one at a time:

```bash
pg_isready -h pg-repmgr-1 -p 5432
```

```bash
pg_isready -h pg-repmgr-2 -p 5432
```

```bash
pg_isready -h pg-repmgr-3 -p 5432
```

```bash
pg_isready -h pg-repmgr-w -p 5432
```

The `-h` flag specifies the hostname, `-p` specifies the port. Nodes that are down will show a connection error.

### Step 2: Check if repmgrd auto-promoted the surviving standby

On the surviving standby:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

```bash
tail -50 /var/lib/pgsql/16/data/log/repmgrd.log
```

Look for promotion messages. repmgrd may or may not have promoted depending on
whether quorum was met. With 2 of 4 nodes down, quorum might not be achievable
(depends on which nodes are up and repmgr's quorum calculation).

### Step 3: Manually promote if auto-failover did not occur

If the surviving standby is still in recovery:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

If it returns `t`, promote manually:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby promote
```

Verify:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f`.

> **Concept - Manual promotion during cascading failure**: When repmgrd cannot
> reach enough nodes for quorum, it will NOT auto-promote. This is a safety
> feature - it prevents promotion when the surviving node might be the isolated
> one. In a cascading failure where you KNOW the other nodes are down, manual
> promotion is the correct action.

### Step 4: Verify writes on the new primary

```sql
INSERT INTO employees(name, department) VALUES ('cascade_test', 'ops');
SELECT count(*) FROM employees;
```

### Step 5: Rejoin the first failed node (victim standby)

This is easier because the victim standby was already a standby - it was just
stopped.

On the victim standby:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

It may auto-reconnect if it was just stopped. Check:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_is_in_recovery();"
```

If it does not reconnect, rejoin. Stop PostgreSQL first:

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
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

Or reclone:

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

### Step 6: Rejoin the old primary

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

### Step 7: Restart repmgrd on rejoined nodes

```bash
exit
```

Run on each rejoined node:

```bash
sudo systemctl start repmgr-16
```

### Step 8: Update the witness

Re-register the witness to point at the new primary:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf witness register --force \
  -h <NEW_PRIMARY_HOSTNAME> -U repmgr -d repmgr
```

### Step 9: Verify full cluster health

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output (yours will differ):
```
 ID | Name         | Role    | Status    | Upstream    | ...
----+--------------+---------+-----------+-------------+----
 1  | pg-repmgr-1  | standby |   running | pg-repmgr-3 | ...
 2  | pg-repmgr-2  | standby |   running | pg-repmgr-3 | ...
 3  | pg-repmgr-3  | primary | * running |             | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-3 | ...
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster crosscheck
```

All 4 nodes should be running: 1 primary, 2 standbys, 1 witness.

```bash
exit
```

---

## Key Concepts for Revision

- **Cascading failure** means multiple components fail in quick succession. The
  cluster goes from healthy (N+2 redundancy) to single-point-of-failure in
  seconds. This is the scenario that tests your composure.

- **Quorum with reduced nodes**: In a 4-node cluster, quorum requires 3 nodes.
  With 2 nodes down, the surviving standby + witness = only 2 nodes. repmgrd
  may not auto-promote because it lacks quorum. Manual intervention is required.

- **Order of recovery matters**: Rejoin the victim standby first (simpler, no
  timeline divergence), then the old primary (requires pg_rewind). This
  restores redundancy faster.

- **Single copy danger**: After the cascading failure, you have exactly ONE copy
  of your data on the surviving standby. If that node also fails before you
  rejoin others, data is lost. This is the most dangerous moment - prioritize
  restoring at least one standby immediately.

- **Witness does not store data**: The witness cannot be promoted to primary.
  It only votes in elections. During a cascading failure, the witness is
  irrelevant for data recovery.

- **Reclone as last resort**: If both failed nodes have diverged WAL that
  pg_rewind cannot reconcile, a full reclone with `standby clone --force` is
  always safe. It is slower but guaranteed to work.

---

## Interview Discussion Points

1. **Cascading failure root causes**: What causes two nodes to fail
   simultaneously? Discuss shared infrastructure (same rack, same power supply,
   same network switch), correlated failures (OS update reboots), and blast
   radius of cloud availability zones.

2. **Quorum vs availability**: In this scenario, repmgrd's quorum requirement
   prevented auto-promotion. Is this the right behavior? When is it better to
   err on the side of safety (no promotion) vs availability (promote anyway)?

3. **Recovery prioritization**: With the primary and one standby down, what do
   you restore first? Why? Discuss the tradeoff between speed (manual promote
   immediately) and safety (assess the situation first).

4. **Multi-AZ deployment**: How would you deploy these 4 nodes across
   availability zones to minimize the risk of cascading failure? What is the
   maximum number of AZs a single outage can take out?

5. **Backup as last resort**: If all data nodes failed (unlikely but possible),
   what is your recovery path? Discuss PITR from backups, recovery time
   estimates, and the importance of tested backup restoration procedures.

6. **Monitoring for cascading risk**: What monitoring would alert you to
   conditions that increase cascading failure risk? Discuss disk space
   convergence, network latency spikes, and correlated hardware failures.

7. **Runbook automation**: At what point do you automate cascading failure
   recovery vs keep it manual? Discuss the risks of automated recovery making
   wrong decisions vs the speed advantage.

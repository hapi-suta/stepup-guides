# Exercise 02 - Manual Switchover (CentOS Stream 9)

**Time estimate:** 20-30 minutes
**Prerequisites:** Exercise 01 complete - all 4 nodes healthy, replication lag at zero

---

## Objective

Perform a planned switchover using `repmgr standby switchover`. Understand how switchover differs from promotion and verify the new topology after the operation.

---

## Step 1 - Understand Switchover vs Promote

> **Concept - Switchover is planned, promote is unplanned**: A switchover
> gracefully swaps the primary and a standby. The current primary is demoted
> to standby, and the target standby is promoted to primary. Both nodes
> remain in the cluster. A promote, by contrast, is for emergencies - the
> old primary is already down and cannot be demoted gracefully.

> **Concept - Zero data loss**: Because a switchover stops the primary first
> (ensuring all WAL is flushed to the standby), there is zero data loss.
> Promotion can lose data if async replication has unflushed WAL.

---

## Step 2 - Confirm Starting State

Switch to the postgres user. All commands in this exercise run as the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for all steps in this exercise.**

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Note which node is primary (should be pg-repmgr-1, node_id=1).

---

## Step 3 - Dry-run the Switchover

Run from the TARGET standby (the node you want to become the new primary). For this exercise, switch to NODE2.

On NODE2:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby switchover --dry-run
```

**Expected output (yours will differ):**
```
NOTICE: checking switchover on node "pg-repmgr-2" (ID: 2) in --dry-run mode
INFO: SSH connection to host "pg-repmgr-1" succeeded
INFO: all prerequisites for "standby switchover" are met
INFO: would switch current primary node "pg-repmgr-1" (ID: 1) to standby
INFO: would promote standby node "pg-repmgr-2" (ID: 2) to primary
```

> **Concept - Always dry-run first**: The dry-run checks SSH connectivity,
> replication lag, pg_hba.conf rules, and disk space. If any prerequisite
> fails, the dry-run tells you exactly what to fix before you attempt the
> actual switchover.

---

## Step 4 - Execute the Switchover

On NODE2:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby switchover \
  --siblings-follow
```

**Expected output (yours will differ):**
```
NOTICE: executing switchover on node "pg-repmgr-2" (ID: 2)
NOTICE: attempting to pause repmgrd on 4 nodes
NOTICE: local node "pg-repmgr-2" (ID: 2) will be promoted to primary; current primary "pg-repmgr-1" (ID: 1) will be demoted to standby
NOTICE: stopping current primary node "pg-repmgr-1" (ID: 1)
NOTICE: issuing CHECKPOINT on node "pg-repmgr-1" (ID: 1)
NOTICE: current primary has been cleanly shut down at location 0/XXXXXXXX
NOTICE: promoting standby to primary
DETAIL: promoting server "pg-repmgr-2" (ID: 2) using pg_promote()
NOTICE: waiting up to 60 seconds (parameter "promote_check_timeout") for promotion to complete
NOTICE: STANDBY PROMOTE successful
NOTICE: node "pg-repmgr-1" (ID: 1) is now attached as standby to node "pg-repmgr-2" (ID: 2)
NOTICE: node "pg-repmgr-3" (ID: 3) is now following new upstream node "pg-repmgr-2" (ID: 2)
NOTICE: switchover was successful
```

> **Concept - --siblings-follow**: This flag tells repmgr to also reconfigure
> other standbys (NODE3 in this case) to follow the new primary. Without it,
> NODE3 would remain connected to the old primary (which is now a standby
> itself, creating a cascade). In most cases, you want `--siblings-follow`.

> **Concept - What happens during a switchover**:
> 1. repmgrd is paused on all nodes (to prevent interference)
> 2. A CHECKPOINT is issued on the current primary
> 3. The current primary is stopped
> 4. The target standby is promoted using pg_promote()
> 5. The old primary is converted to a standby (using pg_rewind if needed)
> 6. Other standbys are pointed at the new primary
> 7. repmgrd is resumed on all nodes

---

## Step 5 - Verify the New Topology

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected output (yours will differ):**
```
 ID | Name         | Role    | Status    | Upstream    | Location | Priority | Timeline | Connection string
----+--------------+---------+-----------+-------------+----------+----------+----------+-------------------------------------------
 1  | pg-repmgr-1  | standby |   running | pg-repmgr-2 | default  | 100      | 2        | host=pg-repmgr-1 user=repmgr dbname=repmgr
 2  | pg-repmgr-2  | primary | * running |             | default  | 100      | 2        | host=pg-repmgr-2 user=repmgr dbname=repmgr
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-2 | default  | 100      | 2        | host=pg-repmgr-3 user=repmgr dbname=repmgr
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-2 | default  | 0        | 1        | host=pg-repmgr-w user=repmgr dbname=repmgr
```

Key changes:
- NODE2 is now primary (timeline 2)
- NODE1 is now a standby, upstream = pg-repmgr-2
- NODE3 is following the new primary
- Witness upstream changed to the new primary

---

## Step 6 - Verify Writes on the New Primary

On NODE2:

```bash
psql -d labdb -c "
INSERT INTO employees (name, department) VALUES ('switchover_test', 'ops');
SELECT count(*) FROM employees;"
```

**Expected:** INSERT succeeds, count = 10001 (or more).

---

## Step 7 - Verify Data Replicated to Standbys

On NODE1 and NODE3:

```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

**Expected:** Same count as the new primary.

---

## Step 8 - Verify Replication Streaming

On NODE2 (new primary):

```sql
SELECT client_addr, state, sync_state FROM pg_stat_replication;
```

**Expected:** Two rows (NODE1 and NODE3), both `streaming`.

---

## Step 9 - Check the Timeline

On NODE2:

```sql
SELECT timeline_id FROM pg_control_checkpoint();
```

**Expected:** `2` (incremented from the switchover).

> **Concept - Switchover advances the timeline**: Just like a manual promote,
> a switchover creates a new timeline. The old primary is rewound (or rebuilt)
> to follow the new timeline. This is why `wal_log_hints = on` or data
> checksums are required - pg_rewind needs them to identify diverged pages.

---

## Step 10 - Switch Back (Optional)

To switch back to NODE1 as primary, run from NODE1:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby switchover \
  --siblings-follow --dry-run
```

If the dry-run passes:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby switchover \
  --siblings-follow
```

This restores the original topology. Notice the timeline increments again.

When done, exit the postgres user:

```bash
exit
```

**You are now back to ec2-user.**

---

## Checkpoint

Before continuing, confirm:
- [ ] You performed a successful switchover from NODE1 to NODE2
- [ ] You understand the difference between switchover and promote
- [ ] `repmgr cluster show` reflects the new topology
- [ ] Writes work on the new primary
- [ ] Both standbys are streaming from the new primary
- [ ] The timeline advanced
- [ ] You understand why `--siblings-follow` is important

---

**Next:** [03 - Manual Promote](03-manual-promote.md)

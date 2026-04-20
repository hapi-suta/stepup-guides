# Exercise 03 - Manual Promote

**Time estimate:** 15-20 minutes
**Prerequisites:** Exercise 02 complete - cluster in any topology, all nodes healthy

---

## Objective

Simulate an unplanned primary failure and manually promote a standby using
`repmgr standby promote`. Understand when manual promotion is appropriate
and how it differs from switchover.

---

## Step 1 - Confirm Starting State

Switch to the postgres user on the node you are working from:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user unless instructed to exit.**

```bash
repmgr -f /etc/repmgr.conf cluster show
```

Note the current primary. For this exercise, ensure NODE1 is primary. If
NODE2 is still primary from Exercise 02, switch back first.

---

## Step 2 - Stop repmgrd on ALL Nodes

For this exercise, stop repmgrd so it does not auto-promote before you do it
manually:

On ALL FOUR servers:
```bash
sudo systemctl stop repmgrd
```

> **Concept - Disabling repmgrd for manual practice**: In production, repmgrd
> handles failover automatically. Here we disable it so you can practice the
> manual workflow. Understanding the manual process is critical because repmgrd
> might not always be running (maintenance windows, upgrades, etc.).

---

## Step 3 - Simulate Primary Crash

On NODE1 (primary), kill PostgreSQL ungracefully:

```bash
sudo systemctl stop postgresql
```

Verify it is down:
```bash
pg_isready -p 5432
```

Expected: `pg_isready: could not connect to server`.

---

## Step 4 - Observe the Cluster State

From NODE2:
```bash
repmgr -f /etc/repmgr.conf cluster show
```

**Expected:**
```
 ID | Name         | Role    | Status        | Upstream    | ...
----+--------------+---------+---------------+-------------+----
 1  | pg-repmgr-1  | primary | - failed      |             | ...
 2  | pg-repmgr-2  | standby |   running     | pg-repmgr-1 | ...
 3  | pg-repmgr-3  | standby |   running     | pg-repmgr-1 | ...
 4  | pg-repmgr-w  | witness | * running     | pg-repmgr-1 | ...
```

NODE1 shows `- failed`. The standbys are still running but their upstream
is the failed primary.

> **Concept - Standby behavior when primary dies**: The standbys do not crash
> when the primary goes down. They notice the WAL stream has stopped and enter
> a waiting state. They will replay any WAL they already received but cannot
> get new WAL. They remain read-only and functional for SELECT queries.

---

## Step 5 - Promote NODE2

On NODE2:
```bash
repmgr -f /etc/repmgr.conf standby promote
```

**Expected:**
```
NOTICE: promoting standby to primary
DETAIL: promoting server "pg-repmgr-2" (ID: 2) using pg_promote()
NOTICE: waiting up to 60 seconds (parameter "promote_check_timeout") for promotion to complete
NOTICE: STANDBY PROMOTE successful
DETAIL: server "pg-repmgr-2" (ID: 2) was successfully promoted to primary
```

Verify:
```bash
repmgr -f /etc/repmgr.conf cluster show
```

**Expected:** NODE2 is now `primary | * running`.

---

## Step 6 - Attach NODE3 to the New Primary

NODE3 is still pointing at the old primary. Redirect it:

On NODE3:
```bash
repmgr -f /etc/repmgr.conf standby follow \
  --upstream-node-id=2
```

**Expected:**
```
NOTICE: setting node 3's upstream to node 2
NOTICE: restarting server using "sudo systemctl restart postgresql"
NOTICE: STANDBY FOLLOW successful
DETAIL: node 3 is now attached to node 2
```

Verify from NODE2:
```sql
SELECT client_addr, state FROM pg_stat_replication;
```

Expected: NODE3 is streaming from NODE2.

> **Concept - standby follow**: After a manual promotion, other standbys must
> be explicitly redirected to the new primary. In automatic failover, repmgrd
> handles this via the `follow_command`. In manual failover, you must run
> `standby follow` on each remaining standby.

---

## Step 7 - Verify Writes on the New Primary

On NODE2:
```bash
psql -d labdb -c "
INSERT INTO employees (name, department) VALUES ('promote_test', 'engineering');
SELECT count(*) FROM employees;"
```

Expected: INSERT succeeds.

---

## Step 8 - Verify Data on NODE3

On NODE3:
```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: matches NODE2's count.

---

## Step 9 - Understand the Cleanup Required

After a manual promote, the old primary (NODE1) is still down and registered
as a primary in repmgr metadata. Before bringing it back, you must:

1. Rejoin it as a standby (Exercise 04 covers this)
2. Re-register the witness to follow the new primary

Update the witness:
On NODE4:
```bash
repmgr -f /etc/repmgr.conf witness register --force \
  -h pg-repmgr-2 -U repmgr -d repmgr
```

> **Concept - Promote vs switchover tradeoffs**:
>
> | Aspect       | Switchover             | Promote                      |
> | ------------ | ---------------------- | ---------------------------- |
> | When to use  | Planned maintenance    | Primary is down/unreachable  |
> | Data loss    | None (clean shutdown)  | Possible (async lag)         |
> | Old primary  | Automatically demoted  | Must be manually rejoined    |
> | Other nodes  | Automatically follow   | Must manually `standby follow` |
> | Downtime     | Seconds                | Seconds (plus manual steps)  |

---

## Step 10 - Restart repmgrd

On all running nodes (NODE2, NODE3, NODE4):
```bash
sudo systemctl start repmgrd
```

Leave NODE1 stopped for now - we will rejoin it in Exercise 04.

---

## Checkpoint

Before continuing, confirm:
- [ ] You stopped NODE1 (simulated crash)
- [ ] You promoted NODE2 using `repmgr standby promote`
- [ ] You redirected NODE3 to follow NODE2 using `standby follow`
- [ ] Writes work on the new primary
- [ ] Data replicated to NODE3
- [ ] You understand when to use promote vs switchover
- [ ] NODE1 is still stopped (ready for Exercise 04)

---

**Next:** [04 - Rejoin Node](04-rejoin-node.md)

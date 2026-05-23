# Exercise 05 - Add and Remove Nodes (CentOS Stream 9)

**Time estimate:** 20-30 minutes
**Prerequisites:** Exercise 04 complete - all 4 nodes healthy, repmgrd running

---

## Objective

Practice adding and removing nodes from a running repmgr cluster. Understand how to deregister nodes cleanly and what happens to replication slots.

---

## Part A - Remove a Standby

### Step 1 - Identify the node to remove

We will temporarily remove NODE3 from the cluster.

Switch to the postgres user. All repmgr/psql commands in this exercise run as the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user unless instructed to exit.**

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Note NODE3's current upstream and status.

### Step 2 - Stop repmgrd on NODE3

Exit the postgres user first:

```bash
exit
```

**You are now back to ec2-user.**

On NODE3:

```bash
sudo systemctl stop repmgr-16
```

Verify:

```bash
sudo systemctl status repmgr-16
```

**Expected output (yours will differ):**
```
... Active: inactive (dead) ...
```

### Step 3 - Stop PostgreSQL on NODE3

On NODE3:

```bash
sudo systemctl stop postgresql-16
```

### Step 4 - Unregister NODE3 from the cluster

From the primary (whichever node is primary), switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby unregister --node-id=3
```

**Expected output (yours will differ):**
```
NOTICE: standby node 3 successfully unregistered
```

### Step 5 - Drop the orphaned replication slot

On the primary (still as postgres user):

```sql
SELECT slot_name, active FROM pg_replication_slots;
```

The slot `repmgr_slot_3` should show `active = f`. Drop it:

```sql
SELECT pg_drop_replication_slot('repmgr_slot_3');
```

> **Concept - Clean up replication slots**: When you remove a standby, its
> replication slot remains on the primary. An inactive slot prevents WAL
> recycling, which will eventually fill the primary's disk. Always drop
> replication slots for deregistered nodes.

### Step 6 - Verify the cluster

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected:** 3 nodes (NODE1, NODE2/primary, NODE4/witness). NODE3 is gone.

---

## Part B - Add a Standby Back

### Step 7 - Clone NODE3 from the current primary

On NODE3, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf \
  -h pg-repmgr-2 -U repmgr -d repmgr \
  standby clone --dry-run
```

**Expected output (yours will differ):**
```
NOTICE: destination directory "/var/lib/pgsql/16/data" provided
INFO: connecting to source node
...
INFO: all prerequisites for "standby clone" are met
```

If dry-run passes:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf \
  -h pg-repmgr-2 -U repmgr -d repmgr \
  standby clone --force
```

The `--force` flag is needed because the data directory is not empty.

```bash
exit
```

**You are now back to ec2-user.**

### Step 8 - Start PostgreSQL on NODE3

```bash
sudo systemctl start postgresql-16
```

### Step 9 - Register NODE3 as a standby

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

**Expected output (yours will differ):**
```
NOTICE: standby node "pg-repmgr-3" (ID: 3) successfully registered
```

The `--force` flag overwrites any stale registration.

### Step 10 - Start repmgrd on NODE3

```bash
exit
```

**You are now back to ec2-user.**

```bash
sudo systemctl start repmgr-16
```

### Step 11 - Verify the cluster

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected:** 4 nodes, all running. NODE3 is back as a standby.

Verify replication:

```sql
-- On the primary
SELECT client_addr, state FROM pg_stat_replication;
```

**Expected:** NODE3 is streaming.

```bash
exit
```

---

## Part C - Deregister and Re-register the Witness

### Step 12 - Unregister the witness

On the primary, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf witness unregister --node-id=4
```

### Step 13 - Verify it is gone

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected:** 3 nodes (witness is gone).

```bash
exit
```

### Step 14 - Re-register the witness

On NODE4, switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf \
  -h pg-repmgr-2 -U repmgr -d repmgr \
  witness register --force
```

```bash
exit
```

### Step 15 - Verify the full cluster

Switch to the postgres user on any node:

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

**Expected:** 4 nodes, all running, all in correct roles.

```bash
exit
```

> **Concept - Node lifecycle in repmgr**:
>
> | Operation          | Command                        | When to use                    |
> | ------------------ | ------------------------------ | ------------------------------ |
> | Add a standby      | standby clone + standby register | New node joining the cluster  |
> | Remove a standby   | standby unregister + drop slot | Decommissioning a node        |
> | Add a witness      | witness register               | Adding quorum voter           |
> | Remove a witness   | witness unregister             | Decommissioning witness       |
> | Rejoin after fail  | node rejoin --force-rewind     | Failed node coming back       |
> | Full rebuild       | standby clone --force          | Data too diverged for rejoin  |

---

## Checkpoint

Before continuing, confirm:
- [ ] You removed NODE3 from the cluster (unregister + drop slot)
- [ ] You added NODE3 back (clone + register)
- [ ] You deregistered and re-registered the witness
- [ ] All 4 nodes are healthy in `repmgr cluster show`
- [ ] You understand why orphaned replication slots must be dropped
- [ ] You know the difference between `--force` on clone vs register

---

**Next:** [Checklist - Self-Assessment](checklist.md)

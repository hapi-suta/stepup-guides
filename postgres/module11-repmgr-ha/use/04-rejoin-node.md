# Exercise 04 - Rejoin a Failed Node

**Time estimate:** 20-30 minutes
**Prerequisites:** Exercise 03 complete - NODE1 stopped, NODE2 is primary, NODE3 streaming from NODE2

---

## Objective

Rejoin NODE1 as a standby using `repmgr node rejoin --force-rewind`. Understand
how repmgr uses pg_rewind under the hood and when a full reclone is needed instead.

---

## Step 1 - Confirm Current State

From NODE2 (primary), switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user unless instructed to exit.**

```bash
repmgr -f /etc/repmgr.conf cluster show
```

**Expected:**
- NODE1: `- failed` (stopped)
- NODE2: `* running` (primary)
- NODE3: `running` (standby)
- NODE4: `* running` (witness)

---

## Step 2 - Understand Why NODE1 Cannot Just Start

> **Concept - Timeline divergence**: NODE1 was the primary on timeline 1.
> NODE2 promoted and started timeline 2. NODE1's data directory may contain
> WAL from timeline 1 that does not exist on timeline 2 (for example, a
> checkpoint that ran just before NODE1 stopped). Simply adding
> `standby.signal` and pointing NODE1 at NODE2 would fail because PostgreSQL
> detects the timeline mismatch. `pg_rewind` solves this by identifying the
> divergence point and copying only the changed pages from the new primary.

---

## Step 3 - Dry-run the Rejoin

On NODE1:
```bash
repmgr -f /etc/repmgr.conf node rejoin \
  -d 'host=pg-repmgr-2 user=repmgr dbname=repmgr' \
  --force-rewind --dry-run
```

**Expected:**
```
NOTICE: using provided configuration file "/etc/repmgr.conf"
INFO: prerequisites for executing NODE REJOIN are met
INFO: 2 files would need to be copied
```

If the dry-run fails with a message about `wal_log_hints`, verify that
`wal_log_hints = on` was set in Build 02.

---

## Step 4 - Execute the Rejoin

On NODE1:
```bash
repmgr -f /etc/repmgr.conf node rejoin \
  -d 'host=pg-repmgr-2 user=repmgr dbname=repmgr' \
  --force-rewind
```

**Expected:**
```
NOTICE: using provided configuration file "/etc/repmgr.conf"
NOTICE: pg_rewind execution required for this node to attach to rejoin target node 2
DETAIL: pg_rewind: servers diverged at WAL location 0/XXXXXXXX on timeline 1
INFO: 2 files copied to /var/lib/postgresql/16/main
NOTICE: setting node 1's upstream to node 2
NOTICE: starting server using "sudo systemctl start postgresql"
NOTICE: NODE REJOIN successful
DETAIL: node 1 is now attached to node 2
```

> **Concept - What repmgr node rejoin does**:
> 1. Validates pg_rewind prerequisites (wal_log_hints or checksums)
> 2. Runs pg_rewind against the new primary to sync diverged pages
> 3. Creates standby.signal and configures primary_conninfo
> 4. Starts PostgreSQL in standby mode
> 5. Updates the repmgr metadata to reflect the new role
>
> This is equivalent to the manual pg_rewind + standby.signal + start
> process from the streaming-replication lab, but automated by repmgr.

---

## Step 5 - Verify NODE1 is Now a Standby

```bash
repmgr -f /etc/repmgr.conf cluster show
```

**Expected:**
```
 ID | Name         | Role    | Status    | Upstream    | ...
----+--------------+---------+-----------+-------------+----
 1  | pg-repmgr-1  | standby |   running | pg-repmgr-2 | ...
 2  | pg-repmgr-2  | primary | * running |             | ...
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-2 | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-2 | ...
```

NODE1 is now a standby, upstream = pg-repmgr-2.

---

## Step 6 - Verify Replication

On NODE2 (primary):
```sql
SELECT client_addr, state FROM pg_stat_replication;
```

Expected: two rows (NODE1 and NODE3), both `streaming`.

On NODE1:
```sql
SELECT pg_is_in_recovery();
```

Expected: `t`.

---

## Step 7 - Verify Data Consistency

On NODE1:
```bash
psql -d labdb -c "SELECT count(*) FROM employees;"
```

Expected: matches the count on NODE2 and NODE3.

---

## Step 8 - Restart repmgrd on NODE1

```bash
sudo systemctl start repmgrd
```

Verify:

```bash
sudo systemctl status repmgrd
```

```bash
tail -5 /var/log/postgresql/repmgr.log
```

Expected: repmgrd is running and monitoring the primary.

---

## Step 9 - When Rejoin Fails - Full Reclone

Sometimes `node rejoin --force-rewind` fails because:
- WAL required by pg_rewind is no longer available
- The data directory is too diverged
- wal_log_hints was not set

In these cases, do a full reclone:

Stop PostgreSQL on the failed node:

```bash
sudo systemctl stop postgresql
```

Reclone from the current primary (run as postgres user):

```bash
repmgr -f /etc/repmgr.conf \
  -h pg-repmgr-2 -U repmgr -d repmgr \
  standby clone --force
```

The `--force` flag allows overwriting the existing data directory.

Start PostgreSQL:

```bash
sudo systemctl start postgresql
```

Re-register as standby. The `--force` flag overwrites the old registration:

```bash
repmgr -f /etc/repmgr.conf standby register --force
```

> **Concept - Reclone vs rejoin tradeoffs**:
>
> | Aspect     | node rejoin (pg_rewind)         | standby clone (pg_basebackup) |
> | ---------- | ------------------------------ | ----------------------------- |
> | Speed      | Fast (copies only diverged pages) | Slow (copies entire data dir) |
> | Prerequisite | wal_log_hints or checksums    | None                          |
> | WAL needed | Divergence WAL must exist       | No WAL dependency             |
> | Data safety | Higher risk if WAL gap exists  | Always safe (fresh copy)      |
> | Use when   | Small divergence, WAL available | Large divergence or rebuild   |

---

## Checkpoint

Before continuing, confirm:
- [ ] NODE1 successfully rejoined as a standby
- [ ] `repmgr cluster show` shows all 4 nodes healthy
- [ ] Both standbys streaming from NODE2
- [ ] Data counts match across all nodes
- [ ] repmgrd running on all nodes
- [ ] You understand when to use `node rejoin` vs `standby clone --force`

---

**Next:** [05 - Add/Remove Nodes](05-add-remove-nodes.md)

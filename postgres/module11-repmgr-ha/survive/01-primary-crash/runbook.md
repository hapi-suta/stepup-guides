# Runbook 01 - Primary Crash (repmgr Auto-Failover)

**Severity:** Critical - All writes are blocked until repmgrd promotes a standby
**Time to resolve:** 2-5 minutes (auto-failover) + 10 minutes (rejoin old primary)

---

## Fix Path

### Step 1: Wait for repmgrd auto-failover

repmgrd on the standbys should detect the primary failure and auto-promote within
60-90 seconds (based on `reconnect_attempts * reconnect_interval`).

Monitor the repmgr log on any standby. Switch to the postgres user first:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

```bash
tail -f /opt/pgsql/data/log/repmgrd.log
```

Press `Ctrl+C` to stop tailing once you see the promotion messages.

Look for messages like:
```
[WARNING] unable to ping "host=pg-repmgr-1 user=repmgr dbname=repmgr"
[WARNING] connection to node "pg-repmgr-1" (ID: 1) lost
[NOTICE] this node is the winner, promoting self
[NOTICE] STANDBY PROMOTE successful
```

### Step 2: Verify the new topology

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Expected output (yours will differ):
```
 ID | Name         | Role    | Status    | Upstream    | ...
----+--------------+---------+-----------+-------------+----
 1  | pg-repmgr-1  | primary | - failed  |             | ...
 2  | pg-repmgr-2  | primary | * running |             | ...
 3  | pg-repmgr-3  | standby |   running | pg-repmgr-2 | ...
 4  | pg-repmgr-w  | witness | * running | pg-repmgr-2 | ...
```

One node shows `primary | * running`, the old primary shows `- failed`,
and at least one standby is following the new primary.

### Step 3: Verify writes on the new primary

Identify the new primary and test writes:

```sql
INSERT INTO employees(name, department) VALUES ('failover_test', 'SRE');
SELECT count(*) FROM employees;
```

Should succeed without error. Count should be >= 10,000.

### Step 4: Check that the other standby followed

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

The standby that was NOT promoted should show the new primary as its upstream.
If it does not, manually redirect it:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby follow \
  --upstream-node-id=<NEW_PRIMARY_ID>
```

### Step 5: Rejoin the old primary as a standby

On the failed node, rejoin using pg_rewind:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin \
  -d 'host=<NEW_PRIMARY_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

If rejoin fails, do a full reclone. Stop PostgreSQL first:

```bash
exit
```

You are now back as the ec2-user. Stop PostgreSQL:

```bash
sudo systemctl stop postgresql-16
```

Switch back to postgres and clone from the new primary:

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

Start PostgreSQL:

```bash
sudo systemctl start postgresql-16
```

Re-register as standby:

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

All 4 nodes should be running: 1 primary, 2 standbys, 1 witness.

```bash
exit
```

---

## Key Concepts for Revision

- **repmgrd automatic failover** follows a detect-wait-elect-promote cycle. It waits
  `reconnect_attempts * reconnect_interval` seconds before declaring the primary dead.
  This delay prevents false failovers caused by brief network glitches.

- **Election mechanism**: When multiple standbys detect the primary is down, they
  hold an election. The standby with the lowest replication lag and highest priority
  wins. The witness node votes but cannot win (it has no data).

- **follow_command**: After the winner promotes itself, all other standbys execute
  `follow_command` from their repmgr.conf. The `%n` placeholder is replaced with
  the new primary's node_id. This is how the cluster automatically reconfigures.

- **Fencing the old primary**: The crashed node must NOT come back as a primary.
  repmgr handles this by tracking the active primary in `repmgr.nodes`. When the
  old primary restarts, repmgrd detects the role mismatch and refuses to start
  in primary mode.

- **pg_rewind during rejoin**: `repmgr node rejoin --force-rewind` uses pg_rewind
  to sync the old primary's data directory with the new primary. This is fast
  because it only copies diverged pages, not the entire data directory.

- **Timeline advancement**: The new primary starts a new timeline (timeline + 1).
  All standbys following it are on the new timeline. The old primary is on the
  old timeline until it is rewound and rejoined.

---

## Interview Discussion Points

1. **Failover detection tuning**: How do you balance `reconnect_attempts` and
   `reconnect_interval`? Short values mean faster failover but higher risk of
   false positives. Long values mean slower failover but fewer unnecessary
   promotions. What would you set for a financial trading platform vs a content
   management system?

2. **Witness placement**: Where should the witness node be located? Why does it
   matter that the witness is on a separate network segment from the data nodes?
   What happens if the witness is in the same rack as the primary?

3. **Split-brain prevention**: How does repmgr prevent split-brain during
   auto-failover? What role does the witness play? What happens if the network
   partitions such that one standby can see the witness but the other cannot?

4. **Data loss quantification**: In async replication, the promoted standby may
   be slightly behind. How do you quantify potential data loss? Where do you
   check the gap between the primary's last WAL position and the standby's
   replay position?

5. **Post-failover automation**: Beyond promotion, what else should be automated?
   Discuss DNS/VIP updates, PgBouncer reconfiguration, monitoring updates,
   backup schedule updates, and notification to the on-call team.

6. **Rejoin vs reclone decision**: After a failover, when do you use
   `node rejoin --force-rewind` vs `standby clone --force`? What factors
   influence this decision (time since divergence, WAL availability, data
   directory size)?

7. **Testing failover in production**: How do you validate your auto-failover
   setup before a real incident? Discuss controlled failure drills, chaos
   engineering, and the importance of testing the entire chain (detection,
   promotion, follow, application reconnection).

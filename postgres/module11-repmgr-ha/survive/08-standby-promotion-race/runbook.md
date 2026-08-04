# Runbook 08 - Standby Promotion Race (Dual Promote)

**Severity:** Critical - Split-brain with two primaries accepting divergent writes
**Time to resolve:** 15-30 minutes

---

## Fix Path

### Step 1: Confirm two primaries exist

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user. Stay as this user for the remaining steps.**

Check every data node one at a time:

```bash
psql -h pg-repmgr-1 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-2 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

```bash
psql -h pg-repmgr-3 -U repmgr -d repmgr -tAc "SELECT pg_is_in_recovery();"
```

Expected: TWO nodes return `f`. This confirms split-brain.

> **Concept - Split-brain detection**: Always verify roles with
> pg_is_in_recovery() rather than repmgr metadata. In a dual-promote scenario,
> repmgr metadata is stale because both promotions used pg_ctl promote, not
> repmgr standby promote.

### Step 2: Compare WAL positions to choose the winner

On each primary, check how much data it has:

On node A:

```bash
psql -c "SELECT pg_current_wal_lsn(), pg_current_wal_insert_lsn();"
```

On node B:

```bash
psql -c "SELECT pg_current_wal_lsn(), pg_current_wal_insert_lsn();"
```

Also check row counts to understand divergence:

```sql
SELECT count(*) FROM employees;
SELECT * FROM employees ORDER BY id DESC LIMIT 5;
```

Choose the node with the most complete dataset as the winner.

### Step 3: Export divergent data from the loser (optional but recommended)

Before destroying the loser's divergent state, export any unique data:

On the loser node:

```bash
pg_dump -t employees --data-only \
  --column-inserts stepup > /tmp/loser_divergent_data.sql
```

The `-t` flag selects a single table, `--data-only` skips schema, `--column-inserts` generates INSERT statements.

### Step 4: Shut down PostgreSQL on the loser

```bash
exit
```

```bash
sudo systemctl stop postgresql-16
```

### Step 5: Rewind the loser back to the winner's timeline

```bash
sudo -iu postgres
```

On the loser node:

```bash
/usr/pgsql-16/bin/pg_rewind \
  --target-pgdata=/opt/pgsql/data \
  --source-server="host=<WINNER_HOSTNAME> port=5432 user=repmgr dbname=repmgr"
```

If pg_rewind fails (common when timelines diverged significantly):

Full reclone:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf \
  -h <WINNER_HOSTNAME> -U repmgr -d repmgr \
  standby clone --force
```

### Step 6: Start PostgreSQL on the demoted node

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

Verify it is now a standby:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t`.

### Step 7: Re-register nodes with repmgr

On the winner (the surviving primary):

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf primary register --force
```

On the demoted node (now standby):

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby register --force
```

On the old crashed primary (if rejoined):

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin \
  -d 'host=<WINNER_HOSTNAME> user=repmgr dbname=repmgr' \
  --force-rewind
```

Or reclone and register:

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
  -h <WINNER_HOSTNAME> -U repmgr -d repmgr \
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

### Step 8: Verify single primary and streaming replication

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

Confirm exactly ONE primary, all others standby/witness, all running.

Check replication:

```sql
SELECT client_addr, state, sent_lsn, replay_lsn
FROM pg_stat_replication;
```

### Step 9: Restart repmgrd on all nodes

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

### Step 10: Verify data consistency

```bash
sudo -iu postgres
```

```sql
-- On the primary
SELECT count(*) FROM employees;

-- On each standby
SELECT count(*) FROM employees;
```

Counts should match. Note that the loser's divergent writes are gone (unless
you exported them in Step 3).

```bash
exit
```

---

## Key Concepts for Revision

- **pg_ctl promote vs repmgr standby promote**: pg_ctl promote is a low-level
  PostgreSQL command that promotes immediately with no coordination. repmgr
  standby promote wraps this with election logic and metadata updates. Using
  pg_ctl promote on multiple nodes bypasses all safety mechanisms.

- **pg_rewind**: Rewinds a diverged data directory to match another server's
  timeline. It works by finding the point where timelines diverged, then copying
  only the changed blocks from the source. Much faster than a full reclone for
  small divergence windows.

- **Timeline divergence**: Each promotion creates a new timeline. When two
  nodes promote independently, they create two different timelines from the
  same fork point. pg_rewind can only handle this if WAL for both timelines
  is still available.

- **Data loss in split-brain resolution**: When you choose a winner, the
  loser's divergent writes are lost. This is unavoidable - you cannot merge two
  independent write streams automatically. The best you can do is export the
  loser's data before rewinding.

- **Prevention is better than cure**: Split-brain from dual promotion should
  never happen if repmgrd is running correctly. It uses election and quorum
  to ensure only one standby promotes. This scenario happens when operators
  bypass repmgr and use pg_ctl promote directly.

- **Fencing importance**: In production, fencing mechanisms (STONITH, VIP
  withdrawal) prevent the second promotion from happening. Without fencing,
  any operator with SSH access can accidentally create split-brain.

---

## Interview Discussion Points

1. **Winner selection criteria**: When two primaries have diverged, how do you
   decide which one to keep? Discuss WAL position, number of transactions,
   business criticality of the data, and whether either node serves production
   traffic.

2. **Data reconciliation**: The loser's divergent writes are lost after
   pg_rewind. How would you recover them? Discuss pg_dump before rewind,
   logical replication slots, and application-level idempotency.

3. **pg_rewind prerequisites**: What must be true for pg_rewind to work?
   Discuss wal_log_hints or data checksums, WAL retention on the source,
   and the full_page_writes setting.

4. **Preventing dual promotion**: What operational controls prevent two
   operators from promoting different standbys? Discuss runbook coordination,
   promotion locking mechanisms, and communication protocols during incidents.

5. **Consensus-based alternatives**: How do Patroni (with etcd), Stolon, and
   pg_auto_failover prevent this class of failure? Compare the distributed
   consensus approach to repmgr's election-based approach.

6. **Post-mortem questions**: After resolving a dual-promotion incident, what
   should the post-mortem focus on? Discuss root cause (why was repmgrd not
   running?), gap analysis, and process improvements.

7. **Application impact**: During the split-brain window, both primaries
   accepted writes. How do applications typically behave? Discuss connection
   caching, DNS TTL, load balancer health checks, and the risk of
   auto-increment ID conflicts.

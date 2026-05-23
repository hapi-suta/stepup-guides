# Runbook 01 - Primary Crash

**Severity:** Critical - All writes are blocked
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Verify the primary is down

SSH to [NODE1] and confirm PostgreSQL is not running:

```bash
sudo systemctl status postgresql-16
```

Now check if PostgreSQL is accepting connections:

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

```bash
exit
```

You should see the service as inactive/dead and pg_isready failing.

### Step 2: Check standby status

SSH to [NODE2] and confirm it is still in recovery:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected result: `t` (true) - it has not been promoted yet.

```bash
exit
```

### Step 3: Promote the standby

On [NODE2], switch to the postgres user:

```bash
sudo -iu postgres
```

Promote it to primary:

```bash
pg_ctl promote -D /var/lib/pgsql/16/data
```

Or using the SQL function (PG 12+):

```bash
psql -c "SELECT pg_promote();"
```

Wait a few seconds, then verify:

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected result: `f` (false) - it is now the primary.

Expected output (yours will differ):
```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

```bash
exit
```

### Step 4: Verify writes work on the new primary

On [NODE2], insert a test row:

```sql
INSERT INTO employees(name, department)
VALUES ('failover_test', 'SRE');
```

If this succeeds without error, the promotion worked.

### Step 5: Verify data integrity

Confirm the employees table is intact:

```sql
SELECT count(*) FROM employees;
```

Should return >= 10,000 rows (all pre-existing data preserved).

Expected output (yours will differ):
```
 count
-------
 10001
(1 row)
```

### Step 6: Confirm timeline advanced

```sql
SELECT timeline_id FROM pg_control_checkpoint();
```

Should return 2 or higher - this proves the standby created a new timeline branch during promotion.

---

## Key Concepts for Revision

- **pg_promote()** is the clean way to promote a standby since PG 12. It writes a promote trigger file and signals the recovery process to stop.
- **Timeline IDs** increment on every promotion. Timeline 1 is the original primary. After promotion the standby starts timeline 2, forking the WAL history.
- **Replication slots** survive promotion. The slot `standby_slot` will still exist on the new primary but will be inactive until a new standby connects.
- **pg_is_in_recovery()** is the single source of truth for whether a node is primary (false) or standby (true).
- **Data consistency**: because streaming replication is physical (byte-level), all committed transactions on the primary that were shipped to the standby before the crash are preserved after promotion.
- **Fencing the old primary**: the crashed [NODE1] must NOT be restarted as a primary. If it comes back, you must either wipe its data directory or convert it to a standby using pg_rewind or pg_basebackup.

---

## Interview Discussion Points

1. **Promotion decision**: What criteria do you use to decide when to promote a standby? How do you balance speed-of-recovery against the risk of data loss from async replication lag?

2. **RTO vs RPO tradeoffs**: In async replication, the standby may be slightly behind. How do you quantify acceptable data loss (RPO) before promotion? How does synchronous replication change this?

3. **Timeline divergence**: After promoting [NODE2], [NODE1] is on timeline 1 and [NODE2] is on timeline 2. What happens if [NODE1] comes back online without being reconfigured? Why is this dangerous?

4. **Split-brain prevention**: How do you prevent both nodes from accepting writes simultaneously? Discuss fencing strategies - STONITH, VIP withdrawal, iptables rules, or connection pooler reconfiguration.

5. **pg_rewind vs pg_basebackup**: After a failover, what are the tradeoffs between using pg_rewind (fast, incremental) vs pg_basebackup (slow, full copy) to rejoin the old primary as a standby?

6. **Automated failover**: Should promotion be automatic or manual? Discuss tools like Patroni, repmgr, and pg_auto_failover. What quorum/consensus mechanisms prevent false failovers?

7. **Client reconnection**: After promoting the standby, how do clients discover the new primary? Discuss DNS updates, VIP failover, connection string with multiple hosts, and PgBouncer reconfiguration.

8. **Post-failover checklist**: Beyond promotion, what else needs to happen? (Update monitoring, verify backups point to the new primary, reconfigure replication slots, notify the team, rebuild the old primary as a standby.)

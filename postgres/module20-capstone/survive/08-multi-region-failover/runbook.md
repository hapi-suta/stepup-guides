# Runbook 08 - Multi-Region Failover

**Severity:** Critical - Entire region unavailable, all services impacted
**Time to resolve:** 10-20 minutes
**Skills tested:** Failover (Module 11), DNS management, disaster recovery planning, standby promotion

---

## Fix Path

All work is done from the **standby (region-b)** server. The primary is unreachable.

### Step 1: Confirm the primary is unreachable

```bash
ping -c 3 -W 2 [PRIMARY_IP]
```

Expected: 100% packet loss or timeout.

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -h [PRIMARY_IP] -U replicator -d postgres -c "SELECT 1;" 2>&1
```

Expected: Connection refused or timeout. The primary is down.

### Step 2: Check standby status

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t` (still a standby).

Check what data the standby has:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT email FROM app.customers WHERE email = 'region-a-marker@capstone.lab';"
```

If the marker row is present, the standby received all data before the failure (RPO = 0).

Check the last replay time:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_last_xact_replay_timestamp(), now() - pg_last_xact_replay_timestamp() AS lag;"
```

This tells you how stale the standby data is.

### Step 3: Promote the standby

```bash
/usr/pgsql-16/bin/pg_ctl promote -D /opt/pgsql/data
```

Or using SQL:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_promote();"
```

Wait a few seconds, then verify:

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (now a primary).

### Step 4: Update DNS / connection strings

In a real multi-region setup, you would update Route 53, an internal DNS, or a load balancer. For this lab, update `/etc/hosts`:

```bash
exit
```

```bash
vi /etc/hosts
```

Find the line with `db-primary.internal` and change it to point to the local (region-b) IP:

```
[STANDBY_IP] db-primary.internal
```

Remove or comment out the line pointing to the old primary.

Save and exit (`:wq`).

Verify DNS resolution:

```bash
ping -c 1 db-primary.internal
```

Should resolve to the local IP.

### Step 5: Verify application connectivity

```bash
su - postgres
```

Test writes:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('region-b-active@capstone.lab', 'Region B Active');"
```

Test reads:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) FROM app.orders;"
```

Both should succeed.

### Step 6: Document the RPO

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_last_xact_replay_timestamp() AS last_replayed;"
```

Compare this with the injection time from the state file. If they are close (within seconds), RPO is effectively zero.

Record:
- Last replayed transaction time: ____
- Region failure time: ____
- RPO: ____ seconds

### Step 7: Configure the new primary for standalone operation

Since the old primary is gone, remove the replication configuration:

```bash
/usr/pgsql-16/bin/psql -c "ALTER SYSTEM RESET synchronous_standby_names;"
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_reload_conf();"
```

This prevents commits from hanging while waiting for a standby that no longer exists.

### Step 8: Take a backup on the new primary

```bash
pgbackrest --stanza=prod --type=full backup
```

This is critical - you now have only one copy of your data.

```bash
exit
```

### Step 9: When region-a recovers

When the old primary comes back online (after the region recovers):

1. Do NOT start PostgreSQL on it - it has stale data
2. Clean the data directory
3. Take a base backup from the new primary (now region-b)
4. Start it as a standby of the new primary
5. This gives you HA again, but with region-b as the primary

---

## Revision Concepts

**Q: In a real multi-region failover, what updates DNS?**
A: Options include: (1) AWS Route 53 health checks with automatic failover, (2) Manual DNS update via API (`aws route53 change-resource-record-sets`), (3) A proxy layer like HAProxy or PgBouncer that reroutes connections, (4) Application-level connection string updates via config management.

**Q: Why reset synchronous_standby_names after promotion?**
A: With synchronous replication configured, every commit waits for standby acknowledgment. If there is no standby (it was in the failed region), all commits will hang indefinitely. Resetting to asynchronous mode lets the new primary operate independently.

**Q: How is multi-region DR different from same-region HA?**
A: Same-region HA (repmgr, Patroni) assumes network connectivity between nodes. Multi-region DR assumes the entire region can become unreachable. This means: (1) Higher latency for synchronous replication, (2) DNS-level routing instead of direct IP, (3) Longer detection time (must distinguish region failure from transient network issue), (4) Cannot use pg_rewind across regions (WAL may not be accessible).

**Q: What is the typical RTO for multi-region failover?**
A: Manual: 5-15 minutes (detect + decide + promote + DNS). Automated (Route 53 + health checks): 60-120 seconds. The DNS TTL is often the bottleneck - clients cache the old IP.

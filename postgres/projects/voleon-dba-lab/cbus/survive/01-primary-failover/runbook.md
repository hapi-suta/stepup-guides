# Runbook 01: Primary Failover

## Alert
> "PostgreSQL primary pg-primary is DOWN. All writes are failing. Trading signals cannot be persisted."

The monitoring system has lost connectivity to PostgreSQL on pg-primary (3.90.199.62). Applications
connecting through PgBouncer on port 6432 are receiving connection errors. The replica (3.91.32.84)
is running but read-only. Every second of downtime means trading signals are not being written.

---

## Layer 1 - Junior DBA: Assess and Contain

**Goal:** Confirm the primary is actually down, document what you see, and notify the on-call team
before touching anything.

### Step 1: SSH into the primary server

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.90.199.62
```

If the SSH connection hangs or times out after 15-20 seconds, the server is unreachable. Move to
Step 3 immediately.

### Step 2: Check the PostgreSQL service status

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo systemctl status postgresql-17
```

Expected output (yours will differ):

```
* postgresql-17.service - PostgreSQL 17 Database Server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-17.service; enabled)
     Active: failed (Result: exit-code) since ...
```

If it shows `failed` or `inactive`, the service is down. Do not restart yet.

### Step 3: Check if PostgreSQL is accepting connections

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5432
```

Expected output when down:

```
127.0.0.1:5432 - no response
```

Expected output when running:

```
127.0.0.1:5432 - accepting connections
```

### Step 4: Check the PostgreSQL log for the last known error

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
sudo tail -50 /var/lib/pgsql/17/data/log/postgresql-$(date +%a).log
```

Look for lines containing `FATAL`, `PANIC`, `OOM`, or `out of memory`. Copy what you see - the
senior DBA will need this.

### Step 5: Check if the replica is reachable and healthy

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@3.91.32.84
```

Once connected, on **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/pg_isready -h 127.0.0.1 -p 5432
```

Expected output:

```
127.0.0.1:5432 - accepting connections
```

### Step 6: Confirm the replica is still in standby mode

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

Then, as **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output:

```
 pg_is_in_recovery
-------------------
 t
(1 row)
```

`t` means true - the replica has not been promoted yet. Good. Exit the postgres user:

```bash
exit
```

### Step 7: Notify the team

Write down the following before paging anyone:
- Time you noticed the alert
- Whether primary SSH was reachable (yes/no)
- Last few lines from the PostgreSQL log
- Whether the replica is healthy and still in standby

Post this information to the incident channel. Do not promote the replica yet. Wait for a mid-level
or senior DBA to authorize failover.

---

## Layer 2 - Mid-Level DBA: Investigate and Remediate

**Goal:** Promote the replica to primary, redirect traffic through PgBouncer, and verify that
trading signals can be written again.

### Step 8: Confirm replication lag before promotion

Before promoting, check how far behind the replica was at the time of failure. A large lag means
some transactions may be lost.

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

Expected output (healthy):

```
 replication_lag
-----------------
 00:00:02.14
(1 row)
```

If lag is over 60 seconds, discuss with the senior DBA before proceeding. Exit postgres user:

```bash
exit
```

### Step 9: Promote the replica to primary

There are two ways to promote. Use the SQL method if you can connect. Use pg_ctl if you cannot.

**Method A - SQL promotion** (preferred):

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT pg_promote();"
```

Expected output:

```
 pg_promote
------------
 t
(1 row)
```

Exit the postgres user:

```bash
exit
```

**Method B - pg_ctl promotion** (use if Method A fails):

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/pg_ctl promote -D /var/lib/pgsql/17/data
```

Expected output:

```
waiting for server to promote.... done
server promoted
```

Exit the postgres user:

```bash
exit
```

### Step 10: Confirm the replica is no longer in recovery

On **pg-replica (3.91.32.84)**, as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output:

```
 pg_is_in_recovery
-------------------
 f
(1 row)
```

`f` means false - promotion succeeded. This server is now the primary and accepts writes. Exit:

```bash
exit
```

### Step 11: Test that writes work on the new primary

On **pg-replica (3.91.32.84)** (now the primary), as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "INSERT INTO quant.signals (symbol, signal_type, value, generated_at) VALUES ('TEST_FAILOVER', 'test', 0.0, now()) RETURNING id;"
```

Expected output:

```
  id
------
 9001
(1 row)
```

Clean up the test row:

```bash
/usr/pgsql-17/bin/psql -d quantdb -c "DELETE FROM quant.signals WHERE symbol = 'TEST_FAILOVER';"
```

Exit:

```bash
exit
```

### Step 12: Update PgBouncer to point to the new primary

PgBouncer is installed on the old primary (3.90.199.62). Since that server may be down, check
whether PgBouncer is running on the ops server (54.209.143.137) or if you need to install it on
the new primary.

Connect to the ops server to check:

On your local machine, as yourself:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@54.209.143.137
```

On **pg-ops (54.209.143.137)**, as **ec2-user**, check the pgbouncer config:

```bash
sudo grep -r "host=" /etc/pgbouncer/pgbouncer.ini
```

Update the `host=` line to point to the new primary's private IP (172.31.22.69):

```bash
sudo vi /etc/pgbouncer/pgbouncer.ini
```

Find the line that looks like:

```
quantdb = host=172.31.19.86 port=5432 dbname=quantdb
```

Change `172.31.19.86` to `172.31.22.69` (the new primary's private IP). Save and exit vi with
`:wq`.

Reload PgBouncer without dropping existing connections:

```bash
sudo systemctl reload pgbouncer
```

### Step 13: Verify application connectivity through PgBouncer

On **pg-ops (54.209.143.137)**, as **ec2-user**:

```bash
/usr/pgsql-17/bin/psql -h 127.0.0.1 -p 6432 -U quant_pipeline -d quantdb -c "SELECT count(*) FROM quant.signals;"
```

If this returns a row count, PgBouncer is correctly routing to the new primary.

---

## Layer 3 - Senior DBA: Root Cause and Prevent

**Goal:** Understand why the primary failed, rebuild it as a new replica, restore pgBackRest
configuration for the new topology, and prevent recurrence.

### Step 14: Investigate the cause of the primary failure

If you can SSH into the old primary (3.90.199.62), do so. On **pg-primary (3.90.199.62)**, as
**ec2-user**:

```bash
sudo journalctl -u postgresql-17 --since "1 hour ago" | tail -100
```

Also check the OS-level logs:

```bash
sudo journalctl -k --since "1 hour ago" | grep -iE "oom|kill|panic|error"
```

Look for:
- `Out of memory: Kill process` - OOM killer took down PostgreSQL
- `kernel panic` - OS-level crash
- `disk full` - no space on the data volume
- `PANIC: could not write to file` - I/O failure

### Step 15: Check disk and memory state on the old primary

On **pg-primary (3.90.199.62)**, as **ec2-user**:

```bash
df -h /var/lib/pgsql
```

```bash
free -h
```

```bash
sudo dmesg | tail -30
```

Document findings for the post-mortem.

### Step 16: Rebuild the old primary as a new replica using pgBackRest

Once the old primary is stable enough to receive data, rebuild it as a standby of the new primary.

On **pg-primary (3.90.199.62)**, as **ec2-user**:

Stop PostgreSQL if it is still partially running:

```bash
sudo systemctl stop postgresql-17
```

Clear the old data directory:

```bash
sudo su - postgres
```

As **postgres** on **pg-primary**:

```bash
rm -rf /var/lib/pgsql/17/data/*
```

Run a pgBackRest delta restore from the new primary's backup stanza:

```bash
/usr/bin/pgbackrest --stanza=voleon-lab --delta restore
```

After the restore completes, create a `standby.signal` file so PostgreSQL starts in standby mode:

```bash
touch /var/lib/pgsql/17/data/standby.signal
```

Edit `postgresql.auto.conf` to set `primary_conninfo` to the new primary:

```bash
vi /var/lib/pgsql/17/data/postgresql.auto.conf
```

Add or update:

```
primary_conninfo = 'host=172.31.22.69 port=5432 user=replicator application_name=pg-primary'
```

Exit the postgres user:

```bash
exit
```

Start PostgreSQL on the old primary (now a replica):

```bash
sudo systemctl start postgresql-17
```

### Step 17: Confirm replication is flowing from the new primary to the new replica

On **pg-replica (3.91.32.84)** (now the primary), as **ec2-user**:

```bash
sudo su - postgres
```

As **postgres** on **pg-replica**:

```bash
/usr/pgsql-17/bin/psql -c "SELECT client_addr, state, write_lag, replay_lag FROM pg_stat_replication;"
```

Expected output:

```
   client_addr   |   state   | write_lag | replay_lag
-----------------+-----------+-----------+------------
 172.31.19.86    | streaming | 00:00:00  | 00:00:01
(1 row)
```

Exit:

```bash
exit
```

### Step 18: Update pgBackRest configuration for the new topology

The pgBackRest stanza config needs to know which host is the primary. On whichever host runs
pgBackRest backups, update `/etc/pgbackrest/pgbackrest.conf`:

```bash
sudo vi /etc/pgbackrest/pgbackrest.conf
```

Update the `pg1-host` and `pg1-path` entries to reflect the new primary (172.31.22.69). Run a
check after saving:

```bash
sudo -u postgres /usr/bin/pgbackrest --stanza=voleon-lab check
```

Expected output:

```
INFO: check command end: completed successfully
```

### Step 19: Post-mortem - add early warning monitoring

Review what monitoring gaps allowed this to escalate to a full outage. Recommended additions:

- Alert when PostgreSQL memory usage exceeds 80% of available RAM
- Alert when disk usage on `/var/lib/pgsql` exceeds 75%
- Alert when replication lag exceeds 30 seconds
- Page on-call when primary becomes unreachable, not just when connections fail

### Step 20: Patroni discussion for automated failover

Document for the next architecture review: manual failover in this runbook took at minimum 5-10
minutes. Patroni with etcd can automate promotion in under 30 seconds. Queue this for the next
sprint with the platform team.

---

## Summary

### Root Cause
The PostgreSQL primary (3.90.199.62) crashed due to [OOM / disk full / kernel panic - fill in
after investigation]. No automated failover was in place, requiring manual promotion of the replica.

### Resolution
1. Replica at 3.91.32.84 was promoted to primary using `pg_promote()`
2. PgBouncer config updated to route to new primary (172.31.22.69)
3. Old primary rebuilt as a replica via pgBackRest restore
4. Replication confirmed flowing in new topology

### Prevention
- Add OOM / disk / replication lag alerts before thresholds are breached
- Evaluate Patroni for automated failover
- Ensure pgBackRest runs against the correct primary after any topology change
- Run quarterly failover drills so the team stays practiced

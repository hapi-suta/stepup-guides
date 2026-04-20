# Use 06: Disaster Recovery Test

Simulate a complete primary failure, perform failover, verify application connectivity, perform PITR, and document your actual RTO and RPO.

---

## Instructions

1. Complete this exercise on your running cluster (primary + standby)
2. Record timestamps for every step - you are measuring RTO and RPO
3. This is a hands-on exercise - you will actually perform the failover
4. Have Build guides 02 and 03 open for reference

---

## 1. Preparation

### 1.1 Record the starting state

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT now() AS test_start;"
```

Record: Test start time = ____

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

Record: Replication state = ____

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) AS total_orders FROM app.orders;"
```

Record: Total orders before disaster = ____

### 1.2 Take a fresh backup

```bash
pgbackrest --stanza=prod --type=diff backup
```

Record: Backup completed at = ____

### 1.3 Insert a marker row

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('dr-test-marker@example.com', 'DR Test Marker');"
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT now() AS marker_time;"
```

Record: Marker insert time = ____

This row must exist after failover to prove zero data loss.

### 1.4 Force a WAL switch

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_switch_wal();"
```

Wait 5 seconds for the standby to receive the WAL.

```bash
exit
```

---

## 2. Simulate Primary Failure

### 2.1 Record the failure time

```bash
date -u +%Y-%m-%dT%H:%M:%SZ
```

Record: Failure time = ____

### 2.2 Stop the primary

```bash
systemctl stop postgresql-16
```

This simulates a sudden primary failure. The stopwatch starts now.

**START YOUR TIMER**

---

## 3. Perform Failover

### 3.1 Check repmgrd detects the failure

On the **standby**:

```bash
su - postgres
```

```bash
tail -f /var/log/repmgr/repmgr.log
```

Watch for promotion messages. Record when you see:

- Failure detected at: ____
- Promotion started at: ____
- Promotion completed at: ____

Press Ctrl+C after promotion.

### 3.2 If automatic failover did not trigger

Manually promote:

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf standby promote
```

Record: Manual promotion at = ____

### 3.3 Verify the new primary

```bash
/usr/pgsql-16/bin/psql -c "SELECT pg_is_in_recovery();"
```

Expected output:
```
 pg_is_in_recovery
--------------------
 f
```

`f` (false) means this server is now a primary. Record the time.

Record: New primary confirmed at = ____

```bash
exit
```

---

## 4. Verify Application Connectivity

### 4.1 Test writes

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -d appdb -c "INSERT INTO app.customers (email, full_name) VALUES ('post-failover@example.com', 'Post Failover Test');"
```

Record: First write after failover at = ____

**STOP YOUR TIMER - This is your RTO**

### 4.2 Verify data integrity

Check the marker row is present:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT email, created_at FROM app.customers WHERE email = 'dr-test-marker@example.com';"
```

Expected: The row exists. If it does, RPO = 0 (zero data loss).

Record: Marker row present? ____

Check total orders match:

```bash
/usr/pgsql-16/bin/psql -d appdb -c "SELECT count(*) AS total_orders FROM app.orders;"
```

Record: Total orders after failover = ____

Compare with the count from section 1.1. They should match.

### 4.3 Test pgBouncer connectivity (if configured)

If pgBouncer is running on the new primary:

```bash
/usr/pgsql-16/bin/psql -h 127.0.0.1 -p 6432 -U app_readwrite -d appdb -c "SELECT count(*) FROM app.customers;"
```

Record: pgBouncer working? ____

```bash
exit
```

---

## 5. Perform PITR to 5 Minutes Before Failure

This tests your ability to recover to an arbitrary point in time.

### 5.1 Calculate the PITR target

Take your failure time from section 2.1 and subtract 5 minutes.

Record: PITR target time = ____

### 5.2 Restore to a temporary instance

We will do this non-destructively by restoring to a separate directory.

```bash
su - postgres
```

```bash
mkdir -p /tmp/pitr-dr-test
```

```bash
pgbackrest --stanza=prod --pg1-path=/tmp/pitr-dr-test --type=time "--target=[YOUR_PITR_TARGET_TIME]" --target-action=promote restore
```

Replace `[YOUR_PITR_TARGET_TIME]` with your calculated time in the format `2026-04-19 12:00:00+00`.

Record: PITR restore started at = ____

### 5.3 Start the PITR instance on a different port

```bash
/usr/pgsql-16/bin/pg_ctl -D /tmp/pitr-dr-test -o "-p 5433" start
```

Wait for it to complete recovery:

```bash
/usr/pgsql-16/bin/psql -p 5433 -c "SELECT pg_is_in_recovery();"
```

Expected: `f` (recovery complete, promoted).

Record: PITR instance ready at = ____

### 5.4 Verify the PITR data

```bash
/usr/pgsql-16/bin/psql -p 5433 -d appdb -c "SELECT count(*) FROM app.orders;"
```

```bash
/usr/pgsql-16/bin/psql -p 5433 -d appdb -c "SELECT email FROM app.customers WHERE email LIKE '%dr-test%' OR email LIKE '%post-failover%';"
```

The marker row should exist (inserted before PITR target). The post-failover row should NOT exist (inserted after failure, which is after PITR target).

Record: PITR data correct? ____

### 5.5 Clean up

```bash
/usr/pgsql-16/bin/pg_ctl -D /tmp/pitr-dr-test stop
```

```bash
rm -rf /tmp/pitr-dr-test
```

```bash
exit
```

---

## 6. Rebuild the Old Primary as Standby

### 6.1 Start PostgreSQL on the old primary

On the **old primary** as root:

```bash
systemctl start postgresql-16
```

### 6.2 Rejoin as standby

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf node rejoin -d 'host=pg-prod-standby user=repmgr dbname=repmgr' --force-rewind=/usr/pgsql-16/bin/pg_rewind
```

Record: Rejoin completed at = ____

```bash
exit
```

### 6.3 Verify replication is healthy

On the **new primary**:

```bash
su - postgres
```

```bash
/usr/pgsql-16/bin/psql -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
```

Expected: One standby streaming.

```bash
/usr/pgsql-16/bin/repmgr -f /etc/repmgr/16/repmgr.conf cluster show
```

Record: Both nodes healthy? ____

```bash
exit
```

---

## 7. Document Results

### 7.1 Recovery Metrics

Fill in:

```
# Disaster Recovery Test Results

## Test Date: [DATE]
## Tester: [YOUR NAME]

## Timeline
- Test started: ____
- Backup taken: ____
- Marker data inserted: ____
- Primary stopped (failure): ____
- Failure detected by repmgrd: ____
- Failover promoted: ____
- New primary confirmed: ____
- First write after failover: ____
- PITR restore started: ____
- PITR instance available: ____
- Old primary rejoined: ____
- Full cluster healthy: ____

## Key Metrics
- RTO (time from failure to first write): ____ seconds
- RPO (data loss): ____ (expected: 0 with sync replication)
- PITR Recovery Time: ____ seconds
- Total exercise duration: ____ minutes

## Data Integrity
- Marker row present after failover: ____
- Order count matches: ____
- PITR data at correct point in time: ____
- Post-failover data absent from PITR: ____

## Findings
- What went well: ____
- What could be improved: ____
- Action items: ____

## Pass/Fail
- Failover: ____
- Data integrity: ____
- PITR: ____
- Rejoin: ____
- Overall: ____
```

### 7.2 Compare against SLA

| Metric | SLA Target | Actual | Status |
|--------|-----------|--------|--------|
| RTO | 5 minutes | | |
| RPO | 0 (sync replication) | | |
| PITR available | 15 minutes | | |
| Full cluster recovery | 30 minutes | | |

If any metric exceeds the SLA target, document what changes would improve it.

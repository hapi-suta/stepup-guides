# SURVIVE 03 - Aurora Writer Failover Runbook
## Incident: Aurora Writer Instance Crash - Automatic Promotion

---

## What Is Being Tested

The Aurora writer instance has crashed unexpectedly. Aurora must automatically promote a reader to writer. You must verify recovery, confirm the new writer, and validate application connectivity.

---

## Why This Matters

Unlike planned failovers (which you trigger), this simulates an unexpected writer crash. In production, this happens due to hardware failures, out-of-memory conditions, or AWS infrastructure issues. Your response time and verification steps directly affect how long users experience errors.

---

## Symptoms

- Application errors flood logging:
```
[ERROR] db connection failed: could not connect to server
[ERROR] FATAL: the database system is starting up
[ERROR] SSL connection has been closed unexpectedly
```
- CloudWatch cluster status shows `failing-over`
- No recent deployments or configuration changes (rules out human error)

---

## Diagnostics

### Step 1 - Confirm It Is a Failover

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-east-1
```

`failing-over` = failover in progress. `available` = may have already completed.

### Step 2 - Check Events

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 15 \
  --region us-east-1
```

Look for "A failover for the DB cluster has started" and "DB cluster failover completed."

### Step 3 - Wait (Do Not Panic)

Aurora failover is automatic. The process:
1. Old writer stops accepting connections
2. Aurora promotes highest-priority reader (tier 0)
3. Shared storage - no data sync needed
4. DNS updated (TTL = 5 seconds)
5. New writer accepts connections

Total time: 20-35 seconds. Do not try to intervene.

---

## Resolution

### Step 4 - Verify New Writer

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

A different instance should now show `Writer: True`.

### Step 5 - Test Write Operation

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "INSERT INTO failover_test (message) VALUES ('survive-03-recovery') RETURNING id;"
```

If the INSERT succeeds, the new writer is operational.

### Step 6 - Test Reader Endpoint

```bash
psql -h devops-lab-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT pg_is_in_recovery(), inet_server_addr();"
```

Reader endpoint should serve a replica (`pg_is_in_recovery = t`).

### Step 7 - Check Application Recovery

Verify application logs show reconnection. If the app is not reconnecting:
- Restart connection pool or application process
- Check if app caches DNS longer than 5 seconds
- Confirm connection string uses cluster endpoint (not instance endpoint)

---

## Prevention

- [ ] Set failover tiers correctly (tier 0 on preferred target)
- [ ] Application connection retry with exponential backoff
- [ ] CloudWatch alarm on failover events
- [ ] Use RDS Proxy for faster failover detection
- [ ] Test failover quarterly
- [ ] Never use instance endpoints in application connection strings

---

## Interview Questions From This Scenario

1. What is the difference between a planned failover and an unplanned writer crash?
2. How does Aurora select which reader to promote?
3. What happens to in-flight transactions during failover?
4. How can you reduce perceived downtime during Aurora failover?
5. After failover, what happens to the old writer instance?

---

## Terminology

| Term | Definition |
|------|-----------|
| Writer crash | Unexpected failure of the Aurora writer instance |
| Automatic promotion | Aurora promotes a reader to writer without human intervention |
| In-flight transactions | Transactions that were active when the writer failed - these are rolled back |
| Connection retry | Application logic that automatically reconnects after a connection drop |
| Exponential backoff | Retry strategy that waits longer between each retry (1s, 2s, 4s, 8s) |

---

## Red Flags

- No reader available to promote - cluster has only a writer (no HA). Add at least one reader immediately.
- Failover taking more than 60 seconds - check if the target reader is severely undersized or overloaded
- Application still sending writes to old IP after failover - DNS caching issue; add `-Dnetworkaddress.cache.ttl=1` to JVM
- Multiple failovers in succession - investigate underlying hardware or configuration issues

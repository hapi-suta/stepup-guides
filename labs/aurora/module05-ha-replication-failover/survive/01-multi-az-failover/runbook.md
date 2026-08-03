# SURVIVE 01 - Multi-AZ Failover Runbook
## Incident: Aurora Writer Failed - Application Connection Drops

---

## What Is Being Tested

An Aurora writer instance has failed. The cluster must automatically promote a reader to writer. The application must reconnect through the same cluster endpoint.

---

## Why This Matters

Every Aurora cluster will experience a failover at some point - planned maintenance, hardware failure, or AZ outage. If your application cannot handle a 20-35 second connection drop and reconnect automatically, your users experience an outage every time AWS performs routine maintenance.

---

## Symptoms

- Application logs show connection errors:
```
FATAL: could not connect to server: Connection refused
SSL connection has been closed unexpectedly
FATAL: the database system is starting up
```
- CloudWatch alarm fires for database connectivity
- Users report "page not loading" or "error saving data"
- Aurora Events show "A failover for the DB cluster has started"

---

## Diagnostics

### Step 1 - Check the Cluster Status

**In your terminal:**

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].{Status:Status,Members:DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}}' \
  --output json \
  --region us-east-1
```

If `Status` is `failing-over`, the failover is in progress. If `available`, the failover may have already completed.

### Step 2 - Check Aurora Events

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 15 \
  --region us-east-1
```

Look for:
- "A failover for the DB cluster has started."
- "DB cluster failover completed."

### Step 3 - Wait for Recovery

Aurora failover is automatic. Do not try to force anything. Wait 20-35 seconds.

```bash
watch -n 5 "aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-east-1"
```

Wait until status returns to `available`.

---

## Resolution

### Step 4 - Verify the New Writer

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

Confirm a different instance is now the writer.

### Step 5 - Verify DNS Updated

```bash
dig +short devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

The IP should be different from before the failover.

### Step 6 - Test Connectivity

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT now(), inet_server_addr(), pg_is_in_recovery();"
```

Confirm `pg_is_in_recovery = f` (you are on the writer).

### Step 7 - Test a Write Operation

```bash
psql -h devops-lab-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "INSERT INTO failover_test (message) VALUES ('survive-01-recovery') RETURNING id;"
```

If the INSERT succeeds, the writer is fully operational.

---

## Prevention

- [ ] Set failover priority tiers on all readers (tier 0 for preferred, tier 15 for analytics)
- [ ] Configure application connection retry (at least 3 retries with 1-second backoff)
- [ ] Set connection pool max lifetime to under 5 minutes (prevents stale connections)
- [ ] Test failover quarterly to verify RTO meets requirements
- [ ] Set CloudWatch alarm on failover events
- [ ] Use RDS Proxy for faster failover recovery

---

## Interview Questions From This Scenario

1. What is the expected downtime during an Aurora failover?
2. Why is Aurora failover faster than RDS Multi-AZ Instance failover?
3. What DNS TTL does Aurora use, and why does it matter?
4. What happens to the old writer after failover?
5. How do you force a failover to a specific reader instance?

---

## Terminology

| Term | Definition |
|------|-----------|
| Failover | Automatic promotion of a reader to writer when the writer fails |
| DNS flip | Updating the cluster endpoint DNS to point to the new writer |
| Promotion tier | Priority number (0-15) controlling which reader becomes writer |
| RTO | Recovery Time Objective - maximum acceptable downtime |
| Cluster endpoint | DNS name that always resolves to the current writer |

---

## Red Flags

- Failover taking longer than 60 seconds - check if the promoted reader was under heavy load
- Application not reconnecting - check DNS caching settings and connection pool configuration
- Same instance still showing as writer after failover - the failover may not have triggered; check Events
- Data missing after failover - should not happen with Aurora (shared storage); investigate application-level issues

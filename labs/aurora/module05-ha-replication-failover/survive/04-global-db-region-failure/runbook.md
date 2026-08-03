# SURVIVE 04 - Global Database Region Failure Runbook
## Incident: Primary Region Unreachable - Manual Cross-Region Failover Required

---

## What Is Being Tested

The primary Aurora cluster in us-east-1 is unreachable due to a regional outage. Aurora Global Database does NOT automatically fail over to another region. You must manually detach the secondary cluster in us-west-2 and promote it to a standalone read-write cluster. This tests your ability to execute a disaster recovery procedure under pressure.

---

## Why This Matters

Regional AWS outages are rare but real. When they happen, your entire primary database is gone. If you have not practiced this procedure, you will spend 30-60 minutes reading documentation while your application is down. Companies that practice DR failover recover in 5-10 minutes. Companies that do not practice take hours - or lose data permanently because they make mistakes under pressure.

---

## Symptoms

- Application errors flood logging:
```
[ERROR] psql: connection to server at "devops-global-primary.cluster-xxxx.us-east-1.rds.amazonaws.com"
        failed: Connection timed out
[ERROR] FATAL: could not connect to server: Network is unreachable
```
- AWS Health Dashboard shows us-east-1 service disruption
- CloudWatch alarms are firing but the us-east-1 console may be unreachable
- Secondary cluster in us-west-2 is healthy but serving read-only traffic
- Replication lag in the secondary is growing (no new data arriving from primary)

---

## Diagnostics

### Step 1 - Confirm the Secondary Is Healthy

Check the secondary cluster status from us-west-2:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-global-secondary \
  --query 'DBClusters[0].{Status:Status,Endpoint:Endpoint}' \
  --output table \
  --region us-west-2
```

`--query` - extracts just the status and endpoint from the full response.
`--region us-west-2` - targets the secondary region directly.

Expected output (yours will differ):
```
-------------------------------------------------------------
|                    DescribeDBClusters                     |
+----------+------------------------------------------------+
| Endpoint | devops-global-secondary.cluster-xxxx.us-west-2...|
| Status   | available                                      |
+----------+------------------------------------------------+
```

If status is `available`, the secondary is healthy.

### Step 2 - Verify the Secondary Is Still a Replica

Connect to the secondary cluster:

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT pg_is_in_recovery(), now();"
```

Expected output (yours will differ):
```
 pg_is_in_recovery |              now
-------------------+-------------------------------
 t                 | 2026-06-09 15:40:00.000000+00
```

`pg_is_in_recovery = t` - this is still a replica. It is healthy but read-only.

### Step 3 - Check the Last Replication Point

This tells you how much data might be lost:

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT pg_last_xact_replay_timestamp() AS last_data_received, now() AS current_time, now() - pg_last_xact_replay_timestamp() AS time_since_last_data;"
```

Expected output (yours will differ):
```
    last_data_received     |       current_time        | time_since_last_data
---------------------------+---------------------------+---------------------
 2026-06-09 15:35:00.000   | 2026-06-09 15:40:00.000   | 00:05:00
```

The `time_since_last_data` value is your potential data loss window. Any writes to the primary after that timestamp were lost. Record this value - it is your actual RPO.

---

## Resolution

### Step 4 - Detach the Secondary From the Global Database

Get the secondary cluster ARN. Since us-east-1 may be unreachable, query from us-west-2:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-global-secondary \
  --query 'DBClusters[0].DBClusterArn' \
  --output text \
  --region us-west-2
```

Expected output (yours will differ):
```
arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary
```

Now detach the secondary from the Global Database:

```bash
aws rds remove-from-global-cluster \
  --global-cluster-identifier devops-aurora-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:devops-global-secondary \
  --region us-west-2
```

`remove-from-global-cluster` - detaches this cluster from the global database. The secondary automatically becomes a standalone read-write cluster.
`--db-cluster-identifier` - must be the full ARN, not just the cluster name.

**WARNING:** This is a one-way operation. After detaching, the secondary becomes independent. The Global Database relationship is broken. Data written to the old primary after the last replication point will NOT be in this cluster.

### Step 5 - Wait for the Secondary to Become Read-Write

After detachment, the secondary exits recovery mode automatically. This takes 1-3 minutes.

Check the status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-global-secondary \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-west-2
```

Expected progression: `modifying` then `available`.

Also verify with psql:

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT pg_is_in_recovery();"
```

Wait until you see `f` (false = no longer in recovery = now read-write).

### Step 6 - Confirm Writes Work on the New Primary

```bash
psql -h devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "CREATE TABLE IF NOT EXISTS dr_failover_test (id SERIAL PRIMARY KEY, region TEXT, message TEXT, created_at TIMESTAMPTZ DEFAULT now()); INSERT INTO dr_failover_test (region, message) VALUES ('us-west-2', 'survive-04-dr-failover') RETURNING id;"
```

If the INSERT returns an id, the new primary (us-west-2) is operational and accepting writes.

### Step 7 - Update Application Connection Strings

Your application must point to the new primary in us-west-2. Options:

1. Update environment variables or Secrets Manager with the new endpoint
2. Update Route 53 if you use a CNAME in front of the RDS endpoint
3. Update connection pool configuration and restart application servers

New endpoint:
```
devops-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com
```

### Step 8 - Recovery Plan for When us-east-1 Returns

When the original primary region recovers:

1. Do NOT try to make it the primary again immediately
2. Assess whether any data was written to us-east-1 between the last replication and the outage
3. If data was lost: the us-west-2 cluster now has the authoritative data
4. Create a new Global Database with us-west-2 as primary
5. Add us-east-1 as a new secondary to the Global Database

---

## Prevention

- [ ] Script the entire DR failover procedure so it runs in under 5 minutes
- [ ] Test DR failover quarterly - do not wait for a real outage to discover problems
- [ ] Use Route 53 health checks with failover routing to reduce application update time
- [ ] Set CloudWatch alarm on GlobalDB replication lag exceeding 5 seconds
- [ ] Document the RPO commitment and verify replication lag meets it
- [ ] Keep the secondary cluster sized to handle write load after promotion
- [ ] Store the DR runbook somewhere accessible even if us-east-1 is down

---

## Interview Questions From This Scenario

1. What is the difference between `switchover-global-cluster` and `remove-from-global-cluster`?
2. Why does Aurora Global Database NOT automatically fail over to another region?
3. After detaching a secondary, how do you re-establish the Global Database relationship?
4. What is your RPO when the primary region fails unexpectedly?
5. How would you automate the DR failover to reduce RTO below 5 minutes?

---

## Terminology

| Term | Definition |
|------|-----------|
| Regional outage | Complete failure of all AWS services in one geographic region |
| Detach-and-promote | Process of removing a secondary from a Global Database so it becomes a standalone read-write cluster |
| RPO (Recovery Point Objective) | Maximum acceptable data loss, measured in time. For Global DB, this equals the replication lag at time of failure |
| RTO (Recovery Time Objective) | Maximum acceptable downtime. For manual Global DB failover, typically 5-15 minutes |
| Split-brain | Scenario where two clusters both think they are the primary, leading to conflicting writes. Aurora avoids this by requiring manual failover |
| Switchover | Planned, non-destructive role swap between primary and secondary regions. Zero data loss |

---

## Red Flags

- No secondary region exists - you have no cross-region DR. Add a secondary immediately.
- Secondary cluster is undersized - after promotion, it cannot handle the write load. Size it to match the primary.
- DR procedure has never been tested - the first real test should not be during a production outage. Test quarterly.
- Application connection strings are hardcoded to us-east-1 - changing them requires a code deployment. Use environment variables or DNS.
- The runbook is stored in us-east-1 - if the region is down, you cannot access it. Store runbooks in multiple locations.
- Replication lag was already high before the outage - you may lose more data than expected. Monitor lag continuously.

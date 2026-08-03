# SURVIVE 03 - Aurora Writer Failover Runbook
## Incident: Aurora Writer Failed - Automatic Promotion in Progress

---

## What You Are Seeing

Application errors are flooding your logging system:

```
[ERROR] db connection failed: could not connect to server
[ERROR] FATAL: the database system is starting up
[ERROR] SSL connection has been closed unexpectedly
```

CloudWatch shows the Aurora cluster status as `failing-over`.

---

## Step 1 - Confirm It Is a Failover (Not Something Worse)

Check the cluster status immediately:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].{Status:Status,Members:DBClusterMembers}' \
  --output json \
  --region us-east-1
```

Expected output during failover (yours will differ):
```json
{
    "Status": "failing-over",
    "Members": [
        {"DBInstanceIdentifier": "my-aurora-writer", "IsClusterWriter": false},
        {"DBInstanceIdentifier": "my-aurora-reader-1", "IsClusterWriter": false},
        {"DBInstanceIdentifier": "my-aurora-reader-2", "IsClusterWriter": false}
    ]
}
```

`Status: failing-over` - Aurora is actively promoting a new writer. This is controlled and recoverable.

If status is `available` but you still cannot connect, something else may be wrong.

---

## Step 2 - Check Aurora Events

```bash
aws rds describe-events \
  --source-identifier my-aurora-cluster \
  --source-type db-cluster \
  --duration 15 \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "Events": [
        {
            "Message": "A failover for the DB cluster has started.",
            "Date": "2024-01-15T15:30:02.000Z"
        }
    ]
}
```

---

## Step 3 - Do Not Panic. Wait.

Aurora failover is automatic. You do not need to do anything during the failover.

The process:
1. Old writer stops accepting connections (this is what causes the errors)
2. Aurora promotes the highest-priority reader to writer (tier 0 first)
3. Storage is already shared - no data sync needed
4. DNS record for the cluster endpoint is updated (TTL = 5 seconds)
5. New writer starts accepting connections

This takes 20-35 seconds.

Time yourself from when you noticed the error to when you see the next step working.

---

## Step 4 - Verify Recovery

Wait until the cluster status returns to "available":

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-east-1
```

Expected output:
```
available
```

Now check which instance is the new writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
------------------------------------------------------
|           DescribeDBClusters                       |
+--------------------+-------------------------------+
| Instance           | Writer                        |
+--------------------+-------------------------------+
| my-aurora-writer   | False                         |
| my-aurora-reader-1 | True                          |
| my-aurora-reader-2 | False                         |
+--------------------+-------------------------------+
```

`my-aurora-reader-1` is now the writer (it had failover tier 0).

---

## Step 5 - Confirm Writer Endpoint DNS Updated

```bash
dig +short my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

The IP should be different from what it was before the failover. The DNS points to the new writer's IP.

---

## Step 6 - Test a Write Operation

```bash
psql -h my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
INSERT INTO replication_test (message) VALUES ('post-failover write test');
SELECT * FROM replication_test ORDER BY id DESC LIMIT 3;
```

If the INSERT succeeds, the new writer is fully operational.

---

## Step 7 - Test the Reader Endpoint

```bash
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT pg_is_in_recovery(), inet_server_addr();"
```

Expected output:
```
 pg_is_in_recovery | inet_server_addr
-------------------+-----------------
 t                 | 10.0.3.67
```

The reader endpoint should serve one of the non-writer instances.

---

## Step 8 - Check Application Recovery

Most modern applications with connection retry will reconnect automatically once DNS updates. Check your application logs for reconnection messages.

If the application is not reconnecting automatically:
- Restart the connection pool (or the app process) to flush old connections
- Check if your app caches DNS for longer than 5 seconds
- Confirm the connection string uses the cluster endpoint (not a hardcoded instance endpoint)

---

## Step 9 - Restore Failover Priority if Needed

After failover, the original writer is now a reader. If you want to fail back to the original writer:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --target-db-instance-identifier my-aurora-writer \
  --region us-east-1
```

This is optional. Aurora clusters work fine with any instance as the writer.

---

## Step 10 - Write the Incident Summary

```
Incident: Aurora Writer Failover
Date/Time: [DATE TIME UTC]
Duration: [N seconds] from first error to recovery
Old writer: [INSTANCE ID]
New writer: [INSTANCE ID]
Cause: [Planned test / AWS event / Instance failure]
Detection: [CloudWatch alarm / Application error / Manual]
Recovery: Automatic (Aurora promoted tier-0 reader)
Application: [Auto-reconnected / Required restart]
Action items:
  - [ ] Check if all failover tiers are set correctly on readers
  - [ ] Confirm application retry settings are adequate
  - [ ] Set CloudWatch alarm on 'failover' event category
  - [ ] Test failover quarterly
```

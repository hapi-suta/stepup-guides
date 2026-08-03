# SURVIVE 04 - Global Database Region Failure Runbook
## Incident: Primary Region Unreachable - Manual Cross-Region Failover Required

---

## What You Are Seeing

All connections to your primary Aurora cluster (us-east-1) are failing:

```
psql: error: connection to server at "my-global-primary.cluster-xxxx.us-east-1.rds.amazonaws.com"
failed: Connection timed out
```

AWS Status page shows us-east-1 is experiencing a major outage. Your secondary cluster in us-west-2 is healthy and currently serving reads.

---

## IMPORTANT: This Failover Is Manual

Unlike a single-cluster Aurora failover (which is automatic), Aurora Global Database does NOT automatically failover to another region. You must trigger it manually.

This is by design - AWS does not want to automatically split your Global Database in a "split-brain" scenario.

---

## Step 1 - Confirm the Secondary Is Healthy

Connect to the secondary cluster (us-west-2):

```bash
psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT pg_is_in_recovery(), now();"
```

Expected output:
```
 pg_is_in_recovery |           now
-------------------+------------------------------
 t                 | 2024-01-15 15:40:00.000000+00
```

`pg_is_in_recovery = t` - this is still a replica. Good. It is healthy.

Check secondary cluster status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-global-secondary \
  --query 'DBClusters[0].{Status:Status,Endpoint:Endpoint}' \
  --output table \
  --region us-west-2
```

Expected output:
```
-------------------------------------------------------------
|                    DescribeDBClusters                     |
+----------+------------------------------------------------+
| Endpoint | my-global-secondary.cluster-xxxx.us-west-2... |
| Status   | available                                      |
+----------+------------------------------------------------+
```

---

## Step 2 - Check the Last Replication Point

Because replication stopped when us-east-1 went down, check how much data the secondary received before the failure:

```bash
psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

```sql
SELECT
    pg_last_xact_replay_timestamp() AS last_data_received,
    now() AS current_time,
    now() - pg_last_xact_replay_timestamp() AS time_since_last_data;
```

Expected output (yours will differ):
```
    last_data_received    |       current_time        | time_since_last_data
--------------------------+---------------------------+---------------------
 2024-01-15 15:35:00.000  | 2024-01-15 15:40:00.000   | 00:05:00
```

5 minutes of data may be lost (written to primary after 15:35 that never reached the secondary). This is your RPO. Record it.

---

## Step 3 - Detach the Secondary and Promote It

> **WARNING:** This is a one-way operation. After detaching, the secondary becomes a standalone cluster. The Global Database relationship is broken. Data written to the old primary after the last replication point will NOT be in this cluster.

Get the secondary cluster ARN:

```bash
aws rds describe-global-clusters \
  --global-cluster-identifier my-aurora-global \
  --query 'GlobalClusters[0].GlobalClusterMembers[?IsWriter==`false`].DBClusterArn' \
  --output text \
  --region us-east-1
```

If us-east-1 is truly down, run from us-west-2:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-global-secondary \
  --query 'DBClusters[0].DBClusterArn' \
  --output text \
  --region us-west-2
```

Expected output:
```
arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary
```

Detach the secondary from the Global Database:

```bash
aws rds remove-from-global-cluster \
  --global-cluster-identifier my-aurora-global \
  --db-cluster-identifier arn:aws:rds:us-west-2:123456789012:cluster:my-global-secondary \
  --region us-west-2
```

`remove-from-global-cluster` - detaches this cluster from the global database. It automatically becomes a standalone read-write cluster.

Expected output (yours will differ):
```json
{
    "GlobalCluster": {
        "GlobalClusterIdentifier": "my-aurora-global",
        "Status": "available",
        "GlobalClusterMembers": [
            {
                "DBClusterArn": "arn:aws:rds:us-west-2:...",
                "IsWriter": false
            }
        ]
    }
}
```

---

## Step 4 - Wait for the Secondary to Become Read-Write

After detachment, the secondary cluster exits recovery mode automatically. This takes 1-3 minutes.

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-global-secondary \
  --query 'DBClusters[0].Status' \
  --output text \
  --region us-west-2
```

Expected progression: `modifying` -> `available`

Also check with psql:

```bash
watch -n 5 "psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres -d postgres \
     -t -c 'SELECT pg_is_in_recovery();'"
```

Wait until you see `f` (false = no longer in recovery = now read-write).

---

## Step 5 - Confirm the New Primary Can Accept Writes

```bash
psql -h my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com \
     -U postgres -d postgres
```

```sql
INSERT INTO global_test (region, message)
VALUES ('us-west-2', 'DR failover - now primary');
SELECT * FROM global_test ORDER BY id DESC LIMIT 3;
```

Expected output:
```
 id | region    | message                        |
----+-----------+--------------------------------+
  3 | us-west-2 | DR failover - now primary      |
  2 | us-east-1 | Written in primary region      |
  1 | us-east-1 | First row                      |
```

Writes work. The new primary (us-west-2) is operational.

---

## Step 6 - Update Application Connection Strings

Your application must point to the new primary in us-west-2. This is a manual step that your team must do. Options:

- Update environment variables / secrets manager with the new endpoint
- Update Route 53 if you use a CNAME in front of the RDS endpoint
- Update connection pool configuration and restart app servers

New endpoint:
```
my-global-secondary.cluster-xxxx.us-west-2.rds.amazonaws.com
```

---

## Step 7 - Estimate Data Loss

Calculate what data was potentially lost:

```sql
-- The timestamp from Step 2 is the last data the secondary received
-- Any writes to the primary AFTER that time were lost
SELECT
    count(*) AS rows_in_secondary,
    max(created_at) AS most_recent_row
FROM global_test;
```

Compare this to what you expect from the primary. The gap is your actual data loss.

---

## Step 8 - Recovery Plan for When us-east-1 Returns

When the original primary region recovers:
1. Do NOT try to make it the primary again immediately
2. Assess whether any data was written to us-east-1 between the last replication and the outage
3. If data was lost: restore from the us-west-2 cluster (which now has the authoritative data) or restore from a backup
4. Re-attach us-east-1 as a secondary to the now-primary us-west-2 cluster

> This re-attachment process is the same as BUILD 06 - create the global database again with the current primary (us-west-2) and add us-east-1 as a secondary.

---

## Step 9 - Write the Incident Summary

```
Incident: Global Database Region Failure (us-east-1)
Date/Time of incident: [DATE TIME UTC]
Date/Time of detection: [DATE TIME UTC]
Date/Time of recovery: [DATE TIME UTC]
Total downtime: [N minutes]
New primary region: us-west-2
Last replication timestamp: [TIMESTAMP from Step 2]
Estimated data loss: [N minutes] of transactions
Recovery method: manual detach-and-promote on secondary

Action items:
  - [ ] Automate the failover runbook into a script for faster execution
  - [ ] Implement Route 53 health check + failover routing to reduce app update time
  - [ ] Investigate root cause of us-east-1 failure
  - [ ] Plan re-attachment of us-east-1 when region recovers
  - [ ] Review RPO to see if cross-region replication lag was acceptable
```

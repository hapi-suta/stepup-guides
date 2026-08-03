# BUILD 01 - RDS Multi-AZ: Enable and Test Failover
## Estimated Time: 40 minutes

---

## What You Will Do

1. Enable Multi-AZ on an existing RDS PostgreSQL instance
2. Compare Multi-AZ Instance vs Multi-AZ DB Cluster
3. Trigger a manual failover
4. Observe the failover event in the Events tab

---

## Before You Start

You need:
- An existing RDS PostgreSQL instance (db.t3.micro is fine)
- AWS CLI v2 configured: `aws configure`
- Your instance identifier (you gave it a name when you created it)

If you do not have an instance yet, create one first:

```bash
aws rds create-db-instance \
  --db-instance-identifier my-postgres \
  --db-instance-class db.t3.micro \
  --engine postgres \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --allocated-storage 20 \
  --no-multi-az \
  --region us-east-1
```

Wait for it to become available before continuing (about 5-10 minutes).

---

## Step 1 - Confirm Your Instance Is Single-AZ

### Console

1. Open the AWS Console
2. Go to RDS -> Databases
3. Click your instance name
4. Look at "Availability and durability" - it should say "Single-AZ"
5. Note the "Endpoint" DNS name (you will use this later)

### CLI

Run this command to see your instance details:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].{MultiAZ:MultiAZ,AZ:AvailabilityZone,Endpoint:Endpoint.Address}' \
  --output table \
  --region us-east-1
```

`--db-instance-identifier` - the name you gave your instance.
`--query` - filters the output to just the fields we care about.
`--output table` - formats the output as a readable table.

Expected output (yours will differ):
```
-------------------------------------------------------------
|                   DescribeDBInstances                     |
+------+------------------------------+--------------------+
| AZ   | Endpoint                     | MultiAZ            |
+------+------------------------------+--------------------+
| us-east-1a | my-postgres.xxxx.us-east-1.rds.amazonaws.com | False |
+------+------------------------------+--------------------+
```

Note the AZ value (e.g. us-east-1a). After failover, this will change.

---

## Step 2 - Enable Multi-AZ

### Console

1. In RDS -> Databases, click your instance
2. Click the orange "Modify" button (top right)
3. Scroll down to "Availability and durability"
4. Select "Multi-AZ deployment - Create a standby instance"
5. Scroll to the bottom
6. Under "Scheduling of modifications", select "Apply immediately"
7. Click "Continue"
8. Review the summary - it should show "Multi-AZ: No -> Yes"
9. Click "Modify DB instance"

> **Concept:** "Apply immediately" means AWS starts the change now. "Apply during the next scheduled maintenance window" means AWS waits for the low-traffic window you configured. For this lab, use "Apply immediately."

The instance status changes to "modifying." This takes 5-20 minutes because AWS is creating the standby and synchronizing data.

### CLI

Run this command:

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-postgres \
  --multi-az \
  --apply-immediately \
  --region us-east-1
```

`--multi-az` - enables Multi-AZ (no value needed, it is a flag).
`--apply-immediately` - start the change now instead of waiting for maintenance window.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres",
        "DBInstanceStatus": "modifying",
        "MultiAZ": true,
        ...
    }
}
```

---

## Step 3 - Wait and Verify Multi-AZ Is Active

Wait for the status to return to "available."

### Console

Watch the "Status" column in RDS -> Databases. Refresh every 2 minutes. When it shows "Available," click the instance and confirm:
- "Availability and durability" shows "Multi-AZ"
- You can see the "Secondary Zone" listed

### CLI

Poll the status:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ,SecondaryAZ:SecondaryAvailabilityZone}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
-------------------------------------------------------------------
|                      DescribeDBInstances                        |
+-------------------+----------+----------------------------------+
| MultiAZ           | SecondaryAZ | Status                       |
+-------------------+----------+----------------------------------+
| True              | us-east-1b  | available                    |
+-------------------+----------+----------------------------------+
```

Note that the SecondaryAZ is different from your primary AZ.

---

## Step 4 - Connect to the Database Before Failover

This step records your connection details so you can observe the impact of failover.

Get your endpoint:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text \
  --region us-east-1
```

`--output text` - outputs just the raw value, no JSON formatting.

Expected output (yours will differ):
```
my-postgres.cxyz1234abcd.us-east-1.rds.amazonaws.com
```

Connect from your EC2 instance or Cloud Shell:

```bash
psql -h my-postgres.cxyz1234abcd.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Once connected, run this query and keep it running in a loop:

```sql
SELECT now(), inet_server_addr(), pg_postmaster_start_time();
```

`inet_server_addr()` - returns the IP address of the server you are connected to.
`pg_postmaster_start_time()` - returns when this PostgreSQL process started.

Note the IP address and start time. After failover, both will change.

Open a second terminal. You will trigger the failover from there.

---

## Step 5 - Trigger a Manual Failover

> **Concept:** A manual failover in RDS is called a "reboot with failover." It forces the standby to become primary. AWS uses this to test your setup and to perform maintenance that requires switching AZs.

### Console

1. In RDS -> Databases, select your instance (checkbox)
2. Click "Actions" -> "Reboot"
3. In the dialog, check "Reboot with failover?"
4. Click "Confirm"

### CLI

```bash
aws rds reboot-db-instance \
  --db-instance-identifier my-postgres \
  --force-failover \
  --region us-east-1
```

`--force-failover` - triggers failover to the standby AZ instead of a normal reboot.

Expected output (yours will differ):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres",
        "DBInstanceStatus": "rebooting",
        "MultiAZ": true,
        ...
    }
}
```

---

## Step 6 - Observe the Failover

In your first terminal (the one with the psql connection), you will see:

```
          now          | inet_server_addr | pg_postmaster_start_time
------------------------+------------------+--------------------------
 2024-01-15 14:22:01   | 10.0.1.45        | 2024-01-15 10:00:00

ERROR:  SSL connection has been closed unexpectedly
```

The connection drops. This is the failover happening.

Wait about 60-90 seconds, then reconnect:

```bash
psql -h my-postgres.cxyz1234abcd.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

Run the query again:

```sql
SELECT now(), inet_server_addr(), pg_postmaster_start_time();
```

Expected output (yours will differ):
```
          now          | inet_server_addr | pg_postmaster_start_time
------------------------+------------------+--------------------------
 2024-01-15 14:23:45   | 10.0.2.87        | 2024-01-15 14:23:30
```

Notice:
- The IP address changed (you are now on the old standby, in a different subnet)
- `pg_postmaster_start_time` is recent (the new primary just started)
- The endpoint DNS name is the same (AWS updated DNS behind the scenes)

---

## Step 7 - Check the Failover Event

### Console

1. In RDS -> Databases, click your instance
2. Click the "Logs and events" tab
3. Scroll down to "Recent events"
4. You should see events like:
   - "Multi-AZ instance failover started"
   - "DB instance restarted"
   - "Multi-AZ instance failover completed"

Note the timestamps and calculate the downtime.

### CLI

```bash
aws rds describe-events \
  --source-identifier my-postgres \
  --source-type db-instance \
  --duration 60 \
  --region us-east-1
```

`--source-identifier` - the name of your instance.
`--source-type db-instance` - we want events for the instance (not a cluster or parameter group).
`--duration 60` - show events from the past 60 minutes.

Expected output (yours will differ):
```json
{
    "Events": [
        {
            "Message": "Multi-AZ instance failover started.",
            "EventCategories": ["failover"],
            "Date": "2024-01-15T14:22:05.000Z"
        },
        {
            "Message": "DB instance restarted.",
            "EventCategories": ["availability"],
            "Date": "2024-01-15T14:23:28.000Z"
        },
        {
            "Message": "Multi-AZ instance failover completed.",
            "EventCategories": ["failover"],
            "Date": "2024-01-15T14:23:35.000Z"
        }
    ]
}
```

---

## Step 8 - Confirm the AZ Has Changed

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].{AZ:AvailabilityZone,SecondaryAZ:SecondaryAvailabilityZone}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
----------------------------------------
|        DescribeDBInstances           |
+------------------+-------------------+
| AZ               | SecondaryAZ       |
+------------------+-------------------+
| us-east-1b       | us-east-1a        |
+------------------+-------------------+
```

The AZ values have swapped. What was the primary AZ (us-east-1a) is now the secondary.

---

## Multi-AZ Instance vs Multi-AZ DB Cluster - Side by Side

RDS offers two distinct Multi-AZ architectures. The lab above used **Multi-AZ Instance** (2-node). Here is the complete comparison with the newer **Multi-AZ DB Cluster** (3-node).

### Architecture Comparison

```
Multi-AZ Instance (2-node)          Multi-AZ DB Cluster (3-node)
==============================      ==============================

  AZ-a           AZ-b                AZ-a        AZ-b        AZ-c
+--------+    +--------+          +--------+  +--------+  +--------+
| Writer |    | Standby|          | Writer |  | Reader |  | Reader |
| (EBS)  |--->| (EBS)  |          | (EBS)  |->| (EBS)  |->| (EBS)  |
+--------+    +--------+          +--------+  +--------+  +--------+
   |              |                   |            |           |
   v              v                   v            v           v
 Synchronous block-level           Transaction log replication
 replication (no reads)            (readers serve read traffic)
```

**Multi-AZ Instance** (what you used above):
- 2 nodes: 1 writer + 1 standby
- Standby is invisible - cannot serve reads
- Synchronous block-level replication (EBS mirroring)
- Failover time: 60-120 seconds
- Supports all instance types including db.t3.micro

**Multi-AZ DB Cluster** (3-node):
- 3 nodes: 1 writer + 2 readable standbys
- Standbys can serve read traffic (reader endpoint provided)
- Transaction log-based replication (similar to Aurora)
- Failover time: under 35 seconds (typically 10-25 seconds)
- Requires r-series or m-series instances (db.r6gd.large minimum)
- Requires io1 or io2 storage

### When to Use Which

| Scenario | Recommendation |
|----------|---------------|
| Dev/test on a budget | Multi-AZ Instance (supports db.t3.micro) |
| Production, read-heavy, fast failover needed | Multi-AZ DB Cluster |
| Production, write-heavy, simple HA | Multi-AZ Instance |
| Need readable standbys without Aurora | Multi-AZ DB Cluster |
| Want Aurora-like HA without Aurora pricing | Multi-AZ DB Cluster |

### Creating a Multi-AZ DB Cluster (CLI)

```bash
aws rds create-db-cluster \
  --db-cluster-identifier my-multiaz-cluster \
  --engine postgres \
  --engine-version 16.6 \
  --master-username postgres \
  --master-user-password YourPassword123 \
  --db-cluster-instance-class db.r6gd.large \
  --allocated-storage 100 \
  --storage-type io1 \
  --iops 3000 \
  --availability-zones us-east-1a us-east-1b us-east-1c \
  --region us-east-1
```

`--db-cluster-identifier` - Multi-AZ DB Cluster uses the cluster API (like Aurora), not the instance API.
`--db-cluster-instance-class` - Multi-AZ DB Clusters require specific instance classes (r-series or m-series, not t-series).
`--storage-type io1` - Multi-AZ DB Clusters require io1 or io2 storage (not gp2/gp3).
`--iops 3000` - Required with io1 storage.
`--availability-zones` - Specify the 3 AZs for the 3 nodes. AWS creates one node per AZ automatically.

> Note: Multi-AZ DB Clusters require `db.r6gd.large` or larger. They do not support `db.t3.micro`. This makes them more expensive for learning. Use the regular Multi-AZ Instance for this lab.

### Verify the 3-Node Cluster

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier my-multiaz-cluster \
  --query 'DBClusters[0].{Status:Status,Writer:Endpoint,Reader:ReaderEndpoint,Members:DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}}' \
  --output json \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "Status": "available",
    "Writer": "my-multiaz-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com",
    "Reader": "my-multiaz-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com",
    "Members": [
        {"Instance": "my-multiaz-cluster-instance-1", "Writer": true},
        {"Instance": "my-multiaz-cluster-instance-2", "Writer": false},
        {"Instance": "my-multiaz-cluster-instance-3", "Writer": false}
    ]
}
```

Notice you get both a **writer endpoint** and a **reader endpoint** - just like Aurora. The reader endpoint load-balances reads across the two standby instances.

### Failover on a Multi-AZ DB Cluster

Failover is faster than Multi-AZ Instance because the standbys are already running and serving reads:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-multiaz-cluster \
  --region us-east-1
```

`--db-cluster-identifier` - uses the cluster failover command (not instance reboot with failover).

Expected failover time: under 35 seconds. In practice, most failovers complete in 10-25 seconds.

### Cost Comparison

```
Multi-AZ Instance (db.t3.micro):
  2 * $0.018/hr = $0.036/hr = ~$26/month

Multi-AZ DB Cluster (db.r6gd.large + io1):
  3 * $0.260/hr = $0.780/hr = ~$569/month
  + io1 storage: $0.125/GB/month + $0.065/IOPS/month
```

Multi-AZ DB Cluster costs roughly 20x more than the cheapest Multi-AZ Instance. The tradeoff is readable standbys, faster failover, and transaction-log replication.

### Cleanup (Multi-AZ DB Cluster)

If you created the Multi-AZ DB Cluster for testing:

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier my-multiaz-cluster \
  --skip-final-snapshot \
  --region us-east-1
```

---

## Key Takeaways

1. Multi-AZ adds a standby that is invisible to your application until failover
2. The DNS endpoint stays the same during failover - your app just needs to reconnect
3. Expect 60-120 seconds of downtime during failover for Multi-AZ Instance
4. Multi-AZ DB Cluster (3-node) fails over in under 35 seconds and provides readable standbys
5. Failover events are logged - always check Events after an unexpected failover
6. Your AZ will change after failover - this is expected
7. Multi-AZ DB Cluster uses the cluster API (like Aurora) and requires io1/io2 storage
8. Choose Multi-AZ Instance for budget, Multi-AZ DB Cluster for fast failover + read scaling

---

## Clean Up

If you want to disable Multi-AZ to save money (costs roughly double with Multi-AZ):

```bash
aws rds modify-db-instance \
  --db-instance-identifier my-postgres \
  --no-multi-az \
  --apply-immediately \
  --region us-east-1
```

`--no-multi-az` - disables Multi-AZ and deletes the standby.

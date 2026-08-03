# BUILD 02: Aurora PostgreSQL - Cloud-Native Architecture

**Module 03 - Cloud Database Services**
**Time Estimate:** 75 minutes
**Prerequisites:** Completed BUILD 01 (RDS fundamentals), AWS CLI configured, psql installed

---

## Step 1: Understand Aurora's Architecture

Aurora PostgreSQL is wire-compatible with PostgreSQL - your psql, pgAdmin, and application drivers work without changes. The difference is under the hood: Aurora separates compute from storage in a way that regular PostgreSQL cannot.

**The DBA analogy:** Imagine if all your PostgreSQL replicas shared a single `$PGDATA` directory. No streaming replication. No WAL shipping. When the primary writes, all replicas can read that data within milliseconds because they all point to the same storage. That is Aurora's core idea.

**How Aurora storage works:**

1. Your data is automatically replicated 6 ways across 3 Availability Zones
2. Aurora can tolerate losing 2 copies without affecting writes, and 3 copies without affecting reads
3. Storage auto-grows in 10 GB increments up to 128 TB - no more `ALTER SYSTEM SET` or resizing EBS volumes
4. Only the redo log (similar to WAL) is written to the storage layer - not full data pages

**Architecture comparison:**

```
Standard RDS PostgreSQL:
  [Primary Instance] --EBS Volume (single AZ)--
       |
  streaming replication (WAL)
       |
  [Standby Instance] --EBS Volume (different AZ)--

Aurora PostgreSQL:
  [Writer Instance]---+
                      |
              [Shared Distributed Storage]
              (6 copies across 3 AZs)
                      |
  [Reader Instance]---+
```

---

## Step 2: Writer and Reader Instances

Aurora uses a cluster model, not individual instances.

| Concept | RDS Equivalent | Self-Managed Equivalent |
|---|---|---|
| Writer instance | Primary | Your primary server |
| Reader instance | Read replica | Your streaming replica |
| Cluster | No equivalent | Your entire replication set |

**Key differences from RDS read replicas:**

- Aurora readers share storage with the writer - replication lag is typically under 20 milliseconds
- RDS read replicas use asynchronous streaming replication - lag can be seconds or minutes
- Aurora supports up to 15 readers. RDS supports up to 5 read replicas.
- Aurora readers can be promoted to writer automatically. RDS read replicas require manual promotion.

---

## Step 3: Aurora Serverless v2

**Analogy:** Think of PgBouncer auto-adjusting its pool size based on load. Aurora Serverless v2 does the same thing but for compute (CPU and RAM). When traffic is low, it scales down. When traffic spikes, it scales up - in seconds.

**How it works:**

- You set a minimum and maximum ACU (Aurora Capacity Unit). 1 ACU = approximately 2 GB RAM.
- Minimum: 0.5 ACU (1 GB RAM) - good for dev/test
- Maximum: up to 256 ACU (512 GB RAM)
- Scaling happens in increments of 0.5 ACU
- You pay per ACU-hour consumed, not for provisioned capacity

**When to use Serverless v2:**

- Development and test environments (scales to near-zero when idle)
- Unpredictable workloads (marketing events, seasonal traffic)
- New applications where you do not know the traffic pattern yet

**When NOT to use it:**

- Steady, predictable production workloads (provisioned is cheaper)
- Workloads that need consistent low latency (scaling takes a few seconds)

---

## Step 4: Create an Aurora PostgreSQL Cluster via AWS CLI

**On your Mac, in your terminal:**

First, reuse or create the security group and subnet group from BUILD 01. If you still have them:

```bash
# Verify security group exists
SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=rds-postgres-lab" \
  --query "SecurityGroups[0].GroupId" \
  --output text)
echo "Security Group: $SG_ID"
```

If you deleted them, re-create them following BUILD 01, Step 4.

Create the Aurora cluster (this is the logical container):

```bash
aws rds create-db-cluster \
  --db-cluster-identifier lab-aurora-cluster \
  --engine aurora-postgresql \
  --engine-version 16.4 \
  --master-username labadmin \
  --master-user-password 'ChangeMe2024!Secure' \
  --db-subnet-group-name lab-subnet-group \
  --vpc-security-group-ids "$SG_ID" \
  --backup-retention-period 7 \
  --storage-encrypted \
  --tags Key=Environment,Value=lab Key=Module,Value=03
```

Now create the writer instance inside the cluster:

```bash
aws rds create-db-instance \
  --db-instance-identifier lab-aurora-writer \
  --db-cluster-identifier lab-aurora-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql
```

**Note:** Aurora requires at least `db.t3.medium` - `db.t3.micro` is not supported.

Create a reader instance:

```bash
aws rds create-db-instance \
  --db-instance-identifier lab-aurora-reader \
  --db-cluster-identifier lab-aurora-cluster \
  --db-instance-class db.t3.medium \
  --engine aurora-postgresql
```

Wait for both instances:

```bash
aws rds wait db-instance-available --db-instance-identifier lab-aurora-writer
aws rds wait db-instance-available --db-instance-identifier lab-aurora-reader
echo "Aurora cluster is ready"
```

This takes 10-15 minutes total.

---

## Step 5: Understand Aurora Endpoints

**Analogy:** Aurora endpoints are like DNS CNAMEs that always point to the right server. In self-managed PostgreSQL, you might use a VIP (virtual IP) or HAProxy to route traffic. Aurora gives you managed endpoints that handle routing automatically.

Get your cluster endpoints:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier lab-aurora-cluster \
  --query "DBClusters[0].{Writer:Endpoint,Reader:ReaderEndpoint,Port:Port}"
```

Expected output (yours will differ):
```json
{
    "Writer": "lab-aurora-cluster.cluster-c9abcdefghij.us-east-1.rds.amazonaws.com",
    "Reader": "lab-aurora-cluster.cluster-ro-c9abcdefghij.us-east-1.rds.amazonaws.com",
    "Port": 5432
}
```

**Three endpoint types:**

| Endpoint | Routes To | Use For | DBA Analogy |
|---|---|---|---|
| **Cluster (writer)** | Current writer instance | All writes, DDL | Primary server VIP |
| **Reader** | Load-balances across readers | Read-only queries | HAProxy for standbys |
| **Instance** | Specific instance | Debugging, maintenance | Direct IP connection |

Connect to the writer:

```bash
AURORA_WRITER=$(aws rds describe-db-clusters \
  --db-cluster-identifier lab-aurora-cluster \
  --query "DBClusters[0].Endpoint" \
  --output text)

psql -h "$AURORA_WRITER" -U labadmin -d postgres
```

Run a quick test:

```sql
CREATE DATABASE aurorlab;
\c aurorlab

CREATE TABLE test_data (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO test_data (payload)
SELECT md5(random()::text)
FROM generate_series(1, 100000);

SELECT count(*) FROM test_data;
\q
```

Now connect to the reader and verify the data is there:

```bash
AURORA_READER=$(aws rds describe-db-clusters \
  --db-cluster-identifier lab-aurora-cluster \
  --query "DBClusters[0].ReaderEndpoint" \
  --output text)

psql -h "$AURORA_READER" -U labadmin -d aurorlab -c "SELECT count(*) FROM test_data;"
```

Expected output:
```
 count
--------
 100000
(1 row)
```

The data appeared on the reader almost instantly because the writer and reader share the same storage layer. No streaming replication delay.

---

## Step 6: Failover Behavior

**Aurora failover is significantly faster than RDS Multi-AZ.** Here is why:

| Metric | RDS Multi-AZ | Aurora |
|---|---|---|
| Failover time | 60-120 seconds | ~30 seconds |
| DNS propagation | Can add 30+ seconds | Managed - faster |
| Data loss risk | None (synchronous) | None (shared storage) |
| Reader availability during failover | N/A | Readers stay up |

Trigger a manual failover to test:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier lab-aurora-cluster \
  --target-db-instance-identifier lab-aurora-reader
```

This promotes the reader to become the writer. The old writer becomes a reader. Watch the status:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier lab-aurora-cluster \
  --query "DBClusters[0].{Status:Status,Writer:Endpoint}"
```

**Important:** The cluster endpoint (writer endpoint) automatically updates to point to the new writer. Your application does not need to change its connection string. This is why you should always connect via the cluster endpoint, never via instance endpoints.

---

## Step 7: Aurora Global Database

**Analogy:** Imagine having a streaming replica in a completely different AWS region - US East to EU West - for disaster recovery. That is Aurora Global Database. The primary region handles writes, and secondary regions have read-only copies with typical replication lag under 1 second.

**When to use it:**

- Cross-region disaster recovery (RPO < 1 second, RTO < 1 minute)
- Serving read traffic closer to users in other regions
- Regulatory requirements for data residency

**How it works:**

1. You designate one region as the primary (handles all writes)
2. You add secondary regions (read-only, up to 5 regions)
3. Aurora replicates at the storage level, not at the PostgreSQL level
4. If the primary region fails, you can promote a secondary region in under 1 minute

We will not create a Global Database in this lab (it requires multi-region setup and costs more), but you should understand when to recommend it.

---

## Step 8: Performance Insights

**Analogy:** Performance Insights is like `pg_stat_statements` combined with a visual timeline. It shows you which queries are consuming the most resources and what wait events they are hitting - all in a web UI.

Enable Performance Insights:

```bash
aws rds modify-db-instance \
  --db-instance-identifier lab-aurora-writer \
  --enable-performance-insights \
  --performance-insights-retention-period 7 \
  --apply-immediately
```

**What Performance Insights shows you:**

| Feature | DBA Equivalent |
|---|---|
| Top SQL | `pg_stat_statements` sorted by total_exec_time |
| Database load | Active sessions over time - like counting rows in `pg_stat_activity` every second |
| Wait events | `pg_stat_activity.wait_event_type` and `wait_event` |
| Instance load vs max vCPU | Like comparing active backends to `max_connections` |

Access it in the AWS Console:

1. Go to RDS in the console
2. Click on your writer instance
3. Click the **Monitoring** tab
4. Click **Performance Insights**

The counter-intuitive part: if your database load line is BELOW the max vCPU line, you have headroom. If it is ABOVE, queries are waiting for CPU.

---

## Step 9: Enhanced Monitoring

Performance Insights shows you database-level metrics. Enhanced Monitoring shows you OS-level metrics - CPU, memory, disk, and network per process. This is like running `htop` on your database server, but you do not have SSH access to RDS.

Enable it:

```bash
# First, create an IAM role for Enhanced Monitoring (if it does not exist)
# RDS needs permission to publish OS metrics to CloudWatch

aws rds modify-db-instance \
  --db-instance-identifier lab-aurora-writer \
  --monitoring-interval 60 \
  --monitoring-role-arn "arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):role/rds-monitoring-role" \
  --apply-immediately
```

**Note:** If you get an error about the IAM role, you may need to create it first. Check the AWS docs for "rds-monitoring-role". This is one of those IAM setup tasks that your cloud team may have already done.

---

## Step 10: Aurora vs RDS Cost Comparison

| Component | RDS db.r6g.xlarge | Aurora db.r6g.xlarge |
|---|---|---|
| Instance (on-demand) | ~$0.48/hr | ~$0.58/hr |
| Storage (500 GB) | $57.50/mo (gp3) | $50.00/mo ($0.10/GB) |
| I/O | Free (gp3) | $0.20/million I/O |
| Multi-AZ | 2x instance cost | Included in storage (6-way replication) |
| Read replica | Full instance cost | Full instance cost |
| Backup | Free up to DB size | Free up to DB size |

**Key insight:** Aurora storage is more expensive per GB, but includes 6-way replication. RDS Multi-AZ doubles your instance cost. For HA workloads, Aurora can be cheaper overall despite the higher per-hour instance price.

---

## Step 11: When to Choose Aurora vs RDS

Use this decision framework:

**Choose RDS when:**
- Budget is tight and you do not need fast failover
- Workload is simple with few replicas needed
- You want the lowest possible cost for dev/test
- You need a specific PostgreSQL version not yet supported by Aurora

**Choose Aurora when:**
- You need fast failover (< 30 seconds)
- You need more than 5 read replicas
- Your storage needs are unpredictable (auto-grows)
- You need cross-region replication (Global Database)
- You want Performance Insights and Enhanced Monitoring without extra setup
- You want automatic storage scaling and pay-per-use I/O (Aurora I/O-Optimized)

---

## Step 12: Clean Up Aurora Resources

```bash
# Delete reader instance
aws rds delete-db-instance \
  --db-instance-identifier lab-aurora-reader \
  --skip-final-snapshot

aws rds wait db-instance-deleted --db-instance-identifier lab-aurora-reader

# Delete writer instance
aws rds delete-db-instance \
  --db-instance-identifier lab-aurora-writer \
  --skip-final-snapshot

aws rds wait db-instance-deleted --db-instance-identifier lab-aurora-writer

# Delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier lab-aurora-cluster \
  --skip-final-snapshot

echo "Aurora cluster deleted"
```

---

## What You Learned

| Topic | Key Takeaway |
|---|---|
| Aurora architecture | Shared distributed storage - 6 copies across 3 AZs |
| Writer/reader model | One writer, up to 15 readers sharing the same storage |
| Serverless v2 | Auto-scaling compute - pay for what you use |
| Endpoints | Cluster (writer), reader (load-balanced), instance (direct) |
| Failover | ~30 seconds - much faster than RDS Multi-AZ |
| Global Database | Cross-region replication at the storage level for DR |
| Performance Insights | Visual `pg_stat_statements` with wait event analysis |
| Enhanced Monitoring | OS-level metrics without SSH access |
| Cost model | Higher per-hour but HA is cheaper overall due to shared storage |
| Decision framework | Aurora for fast failover, many replicas, unpredictable growth |

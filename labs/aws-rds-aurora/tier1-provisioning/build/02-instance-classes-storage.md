# Build 02 - Instance Classes and Storage Types
## Tier 1: Provisioning and Connectivity

**Estimated time:** 30 minutes
**Difficulty:** Beginner
**Prerequisite:** Build 01 complete (you have a running RDS instance)

---

## What You Will Do

You will explore the different instance class families and storage types available for RDS PostgreSQL. By the end you will know:

- The difference between T, M, and R instance families
- When to use Graviton vs Intel instances
- How gp3, io1, and io2 storage differ
- How to check your current instance class and storage using Console and CLI
- How to estimate cost for a given configuration

---

## Part A - Instance Class Families

### Understanding the Naming Convention

Every RDS instance class name follows a pattern:

```
db.t3.micro
   |  |   |
   |  |   +-- Size: nano, micro, small, medium, large, xlarge, 2xlarge, ...
   |  +------ Generation: 3, 4, 5, 6, 7
   +--------- Family: t (burstable), m (general), r (memory)
```

And for Graviton instances:

```
db.t4g.medium
      ^
      g = Graviton (ARM64)
```

### The T Family - Burstable

T instances are the cheapest option. They work well for workloads that are idle most of the time with occasional short bursts of activity.

#### How CPU credits work

When a T instance is idle, it earns CPU credits. When it is busy, it spends credits. If it runs out of credits, AWS throttles the CPU back to the baseline level.

```
db.t3.micro baseline CPU: 10%
db.t3.small baseline CPU: 20%
db.t3.medium baseline CPU: 40%
db.t3.large baseline CPU: 30%
```

A `db.t3.micro` earning credits at idle:
```
Credit balance
1000 |......................
 800 |..........
 600 |..
 400 |   (burst used credits)
 200 |              ..........
   0 +-----------------------------------> time
              ^ heavy load here
              Credits being spent
```

If you see your T instance CPU throttled and queries are slow, it means you ran out of credits. Switch to an M instance for sustained workloads.

#### When to use T instances
- Development and test environments
- Low-traffic applications (< 100 queries per second)
- Applications that are idle overnight
- When cost is the primary concern

### The M Family - General Purpose

M instances give you consistent CPU without bursting. No credit system. You pay for full CPU availability at all times.

Current generation options: `db.m6g`, `db.m7g` (Graviton), `db.m6i`, `db.m7i` (Intel)

#### When to use M instances
- Production OLTP workloads
- Applications with consistent CPU usage
- When you cannot afford the variability of T instances
- Most common choice for production PostgreSQL

### The R Family - Memory Optimized

R instances have roughly 2x the RAM per vCPU compared to M instances. PostgreSQL performance is heavily tied to RAM because:

1. `shared_buffers` - holds hot data pages in RAM. Larger = fewer disk reads.
2. OS page cache - the OS also caches database files. More RAM = bigger cache.
3. `work_mem` - each sort operation or hash join can use this much RAM. With many connections, this adds up.

#### When to use R instances
- Large databases where you want the working set to fit in RAM
- High connection counts (many concurrent queries)
- Analytical queries with large sorts and joins
- When disk I/O is your bottleneck and you need more caching

### Graviton vs Intel

Graviton is AWS's custom ARM chip. It consistently delivers better price-performance than Intel for PostgreSQL workloads.

| | Intel (m6i, r6i, t3) | Graviton (m6g, r6g, t4g) |
|---|---|---|
| Architecture | x86_64 | ARM64 |
| Relative cost | 100% | ~20% cheaper |
| Relative performance | Baseline | Equal or better |
| PostgreSQL compatibility | Full | Full |
| Available since | Long history | 2020 |
| Recommendation | Legacy only | Use by default |

> **Concept:** Your application code runs on your laptop or EC2, not on the RDS instance. The architecture of the RDS instance (ARM vs x86) does not affect your application. PostgreSQL handles the difference internally.

#### Quick comparison: db.m6i.xlarge vs db.m6g.xlarge

| Spec | db.m6i.xlarge | db.m6g.xlarge |
|------|--------------|--------------|
| vCPU | 4 | 4 |
| RAM | 16 GB | 16 GB |
| On-Demand price (us-east-1) | ~$0.38/hr | ~$0.306/hr |
| Monthly savings with Graviton | - | ~$55/month |

For a workload running a year, that is ~$660 saved per instance.

---

## Part B - Storage Types

### gp3 - The Default Choice

gp3 stands for "General Purpose SSD version 3". It is the recommended storage type for most RDS use cases.

The key feature of gp3: you can set IOPS and throughput independently from storage size.

```
gp3 storage:
  - Size: 20 GB to 64 TB
  - Baseline IOPS: 3,000 (always included, no extra charge)
  - Max IOPS: 64,000 (extra charge for anything above 3,000)
  - Baseline throughput: 125 MB/s (always included)
  - Max throughput: 1,000 MB/s (extra charge above 125 MB/s)
```

**Example:** You have a 100 GB database that needs 6,000 IOPS. With gp3, you provision 100 GB of storage and separately add 3,000 extra IOPS (above the 3,000 included). You do not need to buy more storage to get more IOPS.

### io1 - Provisioned IOPS SSD (Legacy)

io1 was the high-performance option before io2 and gp3 improvements. The IOPS-to-storage ratio is limited: max 50 IOPS per GB.

```
io1:
  - Min IOPS: 100
  - Max IOPS: 64,000
  - Ratio: max 50 IOPS per GB of storage
  - Durability: 99.8% (most io1 volumes will not fail in a given year)
```

If you need 32,000 IOPS on io1, you must provision at least 640 GB of storage (32000 / 50 = 640). Even if your actual data only uses 50 GB.

### io2 - Provisioned IOPS SSD (Current)

io2 is the improved version of io1. It has a much better IOPS-to-storage ratio and higher durability.

```
io2:
  - Min IOPS: 100
  - Max IOPS: 256,000 (with io2 Block Express)
  - Ratio: max 500 IOPS per GB
  - Durability: 99.999%
```

Use io2 instead of io1 for all new high-performance deployments.

### Comparison Table

| Feature | gp3 | io1 | io2 |
|---------|-----|-----|-----|
| Min size | 20 GB | 100 GB | 100 GB |
| Max IOPS | 64,000 | 64,000 | 256,000 |
| IOPS included in base price | 3,000 | 0 | 0 |
| Max IOPS:GB ratio | N/A | 50:1 | 500:1 |
| Durability | 99.8-99.9% | 99.8% | 99.999% |
| Best for | Most workloads | Legacy high-perf | Mission-critical |

### How to Choose Storage Type

```
Start here: What is your peak IOPS requirement?

Under 3,000 IOPS:
  -> gp3 with default settings (3,000 IOPS included)

3,000 to 64,000 IOPS:
  -> gp3 with additional provisioned IOPS
  -> (check if gp3 max throughput of 1,000 MB/s is enough)

Over 64,000 IOPS:
  -> io2 Block Express

Need 99.999% storage durability:
  -> io2 regardless of IOPS

High IOPS but limited storage budget:
  -> io2 (500:1 ratio means less storage needed)
```

---

## Part C - Checking Current Instance Class and Storage

### Using the Console

1. Go to RDS > Databases.
2. Click on your instance name.
3. Click the **Configuration** tab.
4. You will see:
   - DB instance class: `db.t3.micro`
   - Storage type: `gp3`
   - Allocated storage: `20 GiB`
   - Provisioned IOPS: `3000`

### Using the CLI

Replace `YOUR_INSTANCE_ID` with your instance identifier (e.g. `suta-rds-lab`).

```bash
aws rds describe-db-instances \
  --db-instance-identifier YOUR_INSTANCE_ID \
  --query "DBInstances[0].{Class:DBInstanceClass,StorageType:StorageType,Storage:AllocatedStorage,IOPS:Iops}" \
  --output table
```

Expected output (yours will differ):
```
-------------------------------------------------------
|              DescribeDBInstances                    |
+---------+-------+-----------+----------------------+
|  Class  | IOPS  |  Storage  |     StorageType      |
+---------+-------+-----------+----------------------+
|  db.t3.micro  |  3000 |  20       |  gp3                 |
+---------+-------+-----------+----------------------+
```

To see full instance details:

```bash
aws rds describe-db-instances \
  --db-instance-identifier YOUR_INSTANCE_ID \
  --output json
```

### Listing Available Instance Classes for PostgreSQL

To see all instance classes available in your region for PostgreSQL:

```bash
aws rds describe-orderable-db-instance-options \
  --engine postgres \
  --query "OrderableDBInstanceOptions[*].DBInstanceClass" \
  --output text | tr '\t' '\n' | sort -u | head -30
```

Expected output (yours will differ):
```
db.m5.xlarge
db.m5.2xlarge
db.m6g.large
db.m6g.xlarge
db.m6i.large
db.r5.large
db.r6g.large
db.t3.micro
db.t3.small
db.t4g.medium
...
```

---

## Part D - Cost Estimation

### Using the AWS Pricing Calculator

Go to: https://calculator.aws/pricing/2/home

1. Click **Create estimate**.
2. Click **Add service**.
3. Search for **RDS for PostgreSQL** and click **Configure**.
4. Set your region, instance class, storage type, and hours.
5. Click **Add to my estimate**.

### Manual Estimation with the CLI

Get the on-demand price for a specific instance class:

```bash
aws rds describe-db-instances \
  --db-instance-identifier YOUR_INSTANCE_ID \
  --query "DBInstances[0].DBInstanceClass" \
  --output text
```

Then look up the price at: https://aws.amazon.com/rds/postgresql/pricing/

### Cost Comparison Example

Monthly cost for a 500 GB PostgreSQL database in us-east-1 (approximate, check current pricing):

| Instance | vCPU | RAM | Storage | Est. Monthly |
|----------|------|-----|---------|-------------|
| db.t3.micro + gp3 | 2 | 1 GB | 500 GB gp3 | ~$65 |
| db.m6g.large + gp3 | 2 | 8 GB | 500 GB gp3 | ~$150 |
| db.m6g.xlarge + gp3 | 4 | 16 GB | 500 GB gp3 | ~$240 |
| db.r6g.large + gp3 | 2 | 16 GB | 500 GB gp3 | ~$190 |
| db.r6g.large + io2 6000 IOPS | 2 | 16 GB | 500 GB io2 | ~$400 |

Note: These are rough estimates. Always check current AWS pricing.

---

## Part E - Modifying an Instance Class (No Downtime with Multi-AZ)

You can change the instance class of a running RDS instance. For a Single-AZ instance, this causes a brief outage (typically 2 to 5 minutes). For Multi-AZ, AWS applies the change to the standby first, then fails over.

### Console steps

1. Go to RDS > Databases.
2. Click on your instance.
3. Click **Modify**.
4. Under "DB instance class", select a different size.
5. Scroll to the bottom and click **Continue**.
6. Under "Scheduling of modifications", choose **Apply immediately** (for the lab).
7. Click **Modify DB instance**.

### CLI steps

```bash
aws rds modify-db-instance \
  --db-instance-identifier suta-rds-lab \
  --db-instance-class db.t3.small \
  --apply-immediately
```

What the flags do:
- `--db-instance-class` - the new instance class to change to
- `--apply-immediately` - do not wait for the next maintenance window; apply now

Wait for the modification to complete:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier suta-rds-lab
```

Verify the change:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].DBInstanceClass" \
  --output text
```

Expected output:
```
db.t3.small
```

---

## Summary

| Concept | Key Point |
|---------|-----------|
| T family | Burstable CPU. Good for dev/test. Throttles if credits run out. |
| M family | Consistent CPU. Best general-purpose production choice. |
| R family | Extra RAM. Use when your working set needs to fit in memory. |
| Graviton | ARM64, ~20% cheaper, equal or better performance. Use by default. |
| gp3 | 3,000 IOPS included. Tune IOPS independently from storage. Default choice. |
| io1 | Legacy high-IOPS. 50:1 IOPS:GB ratio. Being replaced by io2. |
| io2 | High-IOPS, high durability. 500:1 ratio. Use for mission-critical. |

**Next:** Build 03 covers creating an Aurora PostgreSQL cluster.

# USE 02 - Instance Right-Sizing
## Tier 1: Provisioning and Connectivity

**Estimated time:** 30 minutes
**Type:** Analysis exercise (no infrastructure to create)
**Prerequisite:** Build 02 complete

---

## Overview

Right-sizing means choosing the smallest instance that can handle the workload without performance problems. Too small causes slowdowns. Too big wastes money.

In this exercise you will analyze three real-world workloads and recommend the correct instance class and storage type. You will also calculate the cost difference between choices.

---

## How to Use CloudWatch Metrics for Sizing

Before looking at the workloads, understand what metrics matter:

| CloudWatch Metric | What It Tells You | Concerning Value |
|------------------|------------------|-----------------|
| CPUUtilization | Percent of CPU used | > 80% sustained |
| FreeableMemory | RAM available in bytes | < 100 MB |
| DatabaseConnections | Number of open connections | > 80% of max_connections |
| ReadIOPS | Read operations per second | Near provisioned IOPS |
| WriteIOPS | Write operations per second | Near provisioned IOPS |
| ReadLatency | Average read response time | > 20ms |
| WriteLatency | Average write response time | > 5ms |
| FreeStorageSpace | Remaining disk space | < 20% of total |
| BurstBalance | CPU credit balance (T instances only) | < 10% = throttling soon |

---

## Workload 1 - Company Blog with Admin Dashboard

**Current setup:** db.t3.micro, 20 GB gp3 storage, us-east-1

**CloudWatch data (last 30 days):**

```
CPUUtilization:
  - Peak: 85% (occurs during nightly report job, 2am, lasts 8 minutes)
  - Average: 4%
  - During business hours: 8-15%

FreeableMemory:
  - Minimum: 650 MB
  - Average: 720 MB (instance has 1 GB total)

DatabaseConnections:
  - Peak: 12
  - Average: 3

BurstBalance:
  - Drops to 25% during the nightly report job
  - Recovers to 100% by 6am every day

ReadIOPS: average 45, peak 120
WriteIOPS: average 8, peak 30

FreeStorageSpace: 14.5 GB remaining (out of 20 GB)

Alarms triggered last month: 0
User complaints: None
```

**Questions to answer:**

1. Is the current instance class (`db.t3.micro`) appropriate? Why or why not?

2. The nightly report causes CPU to spike to 85%. Is this a problem? What specifically tells you whether to worry?

3. The FreeableMemory minimum is 650 MB on a 1 GB instance. Is this concerning?

4. Storage is 72.5% full (14.5 GB of 20 GB used). What should you do?

5. Write your final recommendation. Fill in this form:

```
Workload 1 Recommendation:
  Instance class: db.____.__________
  Reason for choice:
  Storage type: ___
  Allocated storage: ___ GB
  Additional IOPS: Yes / No (if yes, how many?)
  Estimated monthly cost (us-east-1): $___
  Action timeline: Urgent / Next maintenance window / No action needed
```

---

## Workload 2 - E-commerce Order Processing

**Current setup:** db.m5.xlarge, 500 GB io1 (8000 IOPS), us-east-1, Multi-AZ

**CloudWatch data (last 30 days):**

```
CPUUtilization:
  - Peak: 45% (occurs during flash sales, 3-4 times per month)
  - Average: 22%
  - During business hours: 25-35%

FreeableMemory:
  - Minimum: 2.8 GB (instance has 16 GB total)
  - Average: 9 GB

DatabaseConnections:
  - Peak: 380
  - Average: 180
  - max_connections setting: 500

ReadIOPS: average 1200, peak 3800
WriteIOPS: average 900, peak 2600

ReadLatency: average 2.1ms, peak 8ms
WriteLatency: average 1.3ms, peak 4ms

FreeStorageSpace: 285 GB remaining (57% free)

io1 provisioned IOPS: 8000
IOPS actually used at peak: 6400 (80% of provisioned)

Monthly io1 cost: ~$580 (storage + IOPS)
```

**Questions to answer:**

1. The instance has 16 GB RAM but FreeableMemory minimum is 2.8 GB. Is memory a concern? What is using the RAM?

2. The peak connection count is 380 out of 500 max. How close to the limit is this? What happens when max_connections is reached?

3. The io1 IOPS peak is 6400 out of 8000 provisioned. Should you increase IOPS, decrease them, or switch storage types?

4. This workload has both read and write latency under 5ms at average, and under 10ms at peak. Is this acceptable?

5. Could you save money by switching from io1 to gp3? Calculate:
   - io1: 500 GB at $0.125/GB + 8000 IOPS at $0.10/IOPS = $___/month
   - gp3: 500 GB at $0.115/GB + (8000 - 3000) additional IOPS at $0.006/IOPS = $___/month
   - Monthly savings: $___

6. Could you switch to a Graviton instance? The current instance is `db.m5.xlarge` (Intel). The equivalent Graviton is `db.m6g.xlarge`. The Intel costs ~$0.38/hr and the Graviton costs ~$0.306/hr. What is the monthly savings?

7. Write your final recommendation:

```
Workload 2 Recommendation:
  Instance class: db.____.__________
  Reason for any change (or why you kept it the same):
  Storage type: ___
  Allocated storage: ___ GB
  Additional IOPS: Yes / No (if yes, how many?)
  Estimated monthly savings from your changes: $___/month
  Action timeline: Urgent / Next maintenance window / No action needed
  Risk of your changes: Low / Medium / High. Explain:
```

---

## Workload 3 - Analytics Data Warehouse (Read-Heavy)

**Current setup:** db.m5.2xlarge, 2 TB gp2 storage, us-east-1, Single-AZ

**CloudWatch data (last 30 days):**

```
CPUUtilization:
  - Peak: 95% (during analyst queries, 9am-5pm weekdays)
  - Average: 72%
  - After business hours: 5-10%

FreeableMemory:
  - Minimum: 800 MB (instance has 32 GB total)
  - Average: 1.2 GB
  - Memory is almost entirely consumed during business hours

DatabaseConnections:
  - Peak: 15 (small analyst team)
  - Average: 8

ReadIOPS: average 4500, peak 12000
WriteIOPS: average 200, peak 500 (mostly ETL jobs at night)

ReadLatency: average 35ms, peak 180ms (bad)
WriteLatency: average 5ms, peak 12ms

FreeStorageSpace: 800 GB remaining (out of 2 TB)

BurstBalance: N/A (not a T instance)

User complaints: "Queries are too slow during the day"
Alarms triggered: CPUUtilization > 90% fired 18 times last month
```

**Questions to answer:**

1. The instance has 32 GB RAM but only 800 MB to 1.2 GB is free. What does this tell you about the workload? Which instance family is the right choice here?

2. ReadLatency averaging 35ms and peaking at 180ms is very high for a database. List two possible causes.

3. CPU is at 95% during business hours. This is `db.m5.2xlarge` with 8 vCPUs. Can you solve this by increasing storage IOPS? Why or why not?

4. This is a read-heavy workload with 8 concurrent analyst connections. Would adding a read replica (or Aurora reader) help? Explain.

5. The team needs the database during business hours but not at night. Is this a good candidate for Aurora Serverless? Why or why not? (Research hint: Aurora Serverless v2 scales compute up and down automatically.)

6. Write your final recommendation. This time be specific about your reasoning:

```
Workload 3 Recommendation:
  Current problem in one sentence:
  Instance class: db.____.__________
  Why this family (T/M/R):
  Why this size:
  Storage type: ___
  Allocated storage: ___ GB
  Additional IOPS: Yes / No (if yes, how many? Why?)
  Single-AZ or Multi-AZ: Why?
  Other architectural changes (read replicas, Aurora, etc.):
  Estimated monthly cost of your configuration (rough estimate OK):
  Expected improvement after your changes:
```

---

## Answer Key Discussion

After completing your recommendations, discuss these points with a colleague or instructor:

1. **Workload 1** - The T instance is fine. The BurstBalance recovering every night means the instance is not credit-constrained long-term. The main action item is storage: at 72.5% usage and growing, enable storage autoscaling or expand manually before hitting 95%.

2. **Workload 2** - A good candidate for migrating from io1 to gp3. Peak IOPS of 6400 is well under the gp3 limit of 64,000. The Graviton migration saves ~$55/month per instance. Combined savings could exceed $100/month. Low risk change.

3. **Workload 3** - This is the most interesting case. High CPU and high memory usage together, plus bad read latency, usually means the working set is too large for available RAM. Moving to an R-family instance (more RAM per vCPU) is the right first step. More RAM means more hot data fits in shared_buffers and OS cache, reducing disk reads, which reduces both I/O wait and latency. The gp2 storage should also be migrated to gp3 for free IOPS headroom.

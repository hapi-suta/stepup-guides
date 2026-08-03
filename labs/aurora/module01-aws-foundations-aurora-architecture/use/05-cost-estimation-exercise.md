# Exercise 05: Aurora Cost Estimation

**Duration:** 30 minutes
**Objective:** Estimate monthly Aurora PostgreSQL costs for three different workload scenarios, compare Aurora vs RDS pricing, and understand the cost components that make up your database bill.
**Prerequisites:** Module 01 BUILD guides complete

---

## Background

You are the DBA at [COMPANY]. Your finance team wants a cost forecast for three environments: development, staging, and production. They also want to understand why Aurora costs more than RDS and whether the premium is justified.

Before you start, understand the key cost components for Aurora PostgreSQL:

| Component | What It Is | How It Is Charged |
|-----------|-----------|-------------------|
| **Compute** | The database instance (CPU/RAM) | Per instance-hour |
| **Storage** | Data stored on disk | Per GB-month of consumed storage |
| **I/O** | Read and write operations to storage | Per million I/O requests (Standard) or included (I/O-Optimized) |
| **Backup** | Automated backup storage | Free up to cluster storage size; excess per GB-month |
| **Data Transfer** | Data leaving the AWS region | Per GB transferred out |

For RDS PostgreSQL, the components are:

| Component | What It Is | How It Is Charged |
|-----------|-----------|-------------------|
| **Compute** | The database instance (CPU/RAM) | Per instance-hour |
| **Storage** | Provisioned EBS volume | Per GB-month of provisioned (not consumed) storage |
| **IOPS** | I/O operations (gp3 includes 3,000 baseline) | Included in gp3 baseline; provisioned IOPS cost extra |
| **Backup** | Automated backup storage | Free up to provisioned storage size; excess per GB-month |
| **Data Transfer** | Data leaving the AWS region | Per GB transferred out |

---

## Pricing Reference (us-east-1, On-Demand, June 2026)

Use these approximate prices for your estimates. Real prices vary - check the AWS pricing page for current rates.

### Aurora PostgreSQL

| Instance Type | vCPUs | RAM (GB) | Price/Hour |
|--------------|-------|----------|------------|
| db.t3.medium | 2 | 4 | $0.082 |
| db.t3.large | 2 | 8 | $0.164 |
| db.r6g.large | 2 | 16 | $0.260 |
| db.r6g.xlarge | 4 | 32 | $0.520 |
| db.r6g.2xlarge | 8 | 64 | $1.040 |

| Storage Component | Price |
|-------------------|-------|
| Storage | $0.10 per GB-month |
| I/O (Standard) | $0.20 per million requests |
| I/O-Optimized | 30% higher compute cost, no I/O charges |

### RDS PostgreSQL

| Instance Type | vCPUs | RAM (GB) | Price/Hour |
|--------------|-------|----------|------------|
| db.t3.micro | 2 | 1 | $0.018 |
| db.t3.medium | 2 | 4 | $0.068 |
| db.t3.large | 2 | 8 | $0.136 |
| db.r6g.large | 2 | 16 | $0.218 |
| db.r6g.xlarge | 4 | 32 | $0.436 |
| db.r6g.2xlarge | 8 | 64 | $0.872 |

| Storage Component | Price |
|-------------------|-------|
| gp3 storage | $0.115 per GB-month (provisioned) |
| gp3 baseline IOPS | 3,000 IOPS included |
| Additional provisioned IOPS | $0.08 per IOPS-month |

---

## Scenario 1: Development Environment

**Workload profile:**
- 1 developer instance, used 8 hours/day on weekdays only (about 176 hours/month)
- Database size: 10 GB of actual data
- Traffic: Very light - approximately 5 million I/O requests per month
- No read replicas needed
- No Multi-AZ (single-AZ is acceptable for dev)
- RDS: Provision 50 GB gp3 storage (room to grow)
- Instance size: smallest practical option for each service

### Your Task

Estimate the monthly cost for:
1. Aurora PostgreSQL (db.t3.medium, single instance)
2. RDS PostgreSQL (db.t3.micro, single instance)

<details>
<summary>Show Solution</summary>

### Aurora PostgreSQL - Development

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Compute | $0.082/hr x 730 hrs (runs 24/7 even if idle) | $59.86 |
| Storage | 10 GB x $0.10/GB | $1.00 |
| I/O | 5 million x $0.20/million | $1.00 |
| **Total** | | **$61.86** |

**Important note:** Aurora instances cannot be stopped for more than 7 days. AWS automatically restarts them after 7 days. So even though the developer only uses it 8 hours/day, the instance runs 24/7 unless you use Aurora Serverless v2 (which can scale to near-zero ACUs during inactivity).

### RDS PostgreSQL - Development

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Compute | $0.018/hr x 730 hrs | $13.14 |
| Storage | 50 GB x $0.115/GB (provisioned, not consumed) | $5.75 |
| IOPS | 3,000 baseline included in gp3 | $0.00 |
| **Total** | | **$18.89** |

**RDS advantage:** RDS instances can be stopped for up to 7 days at a time (and you can automate restarting and re-stopping). While stopped, you pay only for storage. If you stop the instance every night and on weekends, compute cost drops to approximately $0.018 x 176 hrs = $3.17.

### Cost Difference

| Service | Monthly Cost |
|---------|-------------|
| Aurora | $61.86 |
| RDS | $18.89 (or ~$8.92 if stopped off-hours) |
| **Difference** | **$42.97 (3.3x more expensive)** |

**Verdict for dev:** RDS wins by a wide margin. Aurora's cost floor is too high for a development database with minimal traffic. The db.t3.micro option on RDS is not available on Aurora.

</details>

---

## Scenario 2: Staging Environment

**Workload profile:**
- 1 primary instance, 1 read replica (for testing read-write split)
- Database size: 100 GB of actual data
- Traffic: Moderate - approximately 50 million I/O requests per month
- Multi-AZ: Yes (testing failover behavior)
- RDS: Provision 200 GB gp3 storage
- Instance size: db.t3.large for both services

### Your Task

Estimate the monthly cost for:
1. Aurora PostgreSQL (db.t3.large writer + db.t3.large reader)
2. RDS PostgreSQL Multi-AZ (db.t3.large primary + standby + db.t3.large read replica)

<details>
<summary>Show Solution</summary>

### Aurora PostgreSQL - Staging

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Writer compute | $0.164/hr x 730 hrs | $119.72 |
| Reader compute | $0.164/hr x 730 hrs | $119.72 |
| Storage | 100 GB x $0.10/GB | $10.00 |
| I/O | 50 million x $0.20/million | $10.00 |
| **Total** | | **$259.44** |

**Note:** Aurora Multi-AZ is built into the architecture when you have reader instances in different AZs. There is no separate "Multi-AZ" toggle like RDS - you achieve HA by adding reader instances.

### RDS PostgreSQL - Staging

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Primary compute (Multi-AZ) | $0.136/hr x 730 hrs x 2 (Multi-AZ doubles cost) | $198.56 |
| Read replica compute | $0.136/hr x 730 hrs | $99.28 |
| Primary storage (Multi-AZ) | 200 GB x $0.115/GB x 2 (Multi-AZ doubles storage) | $46.00 |
| Replica storage | 200 GB x $0.115/GB | $23.00 |
| IOPS | 3,000 baseline included | $0.00 |
| **Total** | | **$366.84** |

### Cost Difference

| Service | Monthly Cost |
|---------|-------------|
| Aurora | $259.44 |
| RDS | $366.84 |
| **Difference** | **RDS is $107.40 more (1.4x)** |

**Why Aurora is cheaper here:** RDS Multi-AZ doubles the compute AND storage cost because it runs a full standby instance with its own EBS volume. Aurora's reader instance shares the same storage layer, so you do not pay for storage twice. Aurora's storage also costs less per GB ($0.10 vs $0.115) and you pay for consumed storage (100 GB) vs provisioned storage (200 GB).

**Verdict for staging:** Aurora is the better value when you need both HA and read replicas. The shared storage model avoids the double-billing that RDS Multi-AZ requires.

</details>

---

## Scenario 3: Production Environment

**Workload profile:**
- 1 primary (writer), 2 read replicas
- Database size: 500 GB of actual data, growing 20 GB/month
- Traffic: Heavy - approximately 500 million I/O requests per month
- Multi-AZ: Required
- RDS: Provision 1,000 GB gp3 storage with 10,000 provisioned IOPS
- Instance size: db.r6g.xlarge for both services

### Your Task

Estimate the monthly cost for:
1. Aurora PostgreSQL Standard (db.r6g.xlarge writer + 2x db.r6g.xlarge readers)
2. Aurora PostgreSQL I/O-Optimized (same config, 30% higher compute, no I/O charges)
3. RDS PostgreSQL Multi-AZ (db.r6g.xlarge primary + standby + 2x db.r6g.xlarge read replicas)

<details>
<summary>Show Solution</summary>

### Aurora PostgreSQL Standard - Production

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Writer compute | $0.520/hr x 730 hrs | $379.60 |
| Reader 1 compute | $0.520/hr x 730 hrs | $379.60 |
| Reader 2 compute | $0.520/hr x 730 hrs | $379.60 |
| Storage | 500 GB x $0.10/GB | $50.00 |
| I/O | 500 million x $0.20/million | $100.00 |
| **Total** | | **$1,288.80** |

### Aurora PostgreSQL I/O-Optimized - Production

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Writer compute | $0.520 x 1.30 = $0.676/hr x 730 hrs | $493.48 |
| Reader 1 compute | $0.676/hr x 730 hrs | $493.48 |
| Reader 2 compute | $0.676/hr x 730 hrs | $493.48 |
| Storage | 500 GB x $0.225/GB (I/O-Optimized rate) | $112.50 |
| I/O | Included | $0.00 |
| **Total** | | **$1,592.94** |

### RDS PostgreSQL - Production

| Component | Calculation | Monthly Cost |
|-----------|------------|-------------|
| Primary compute (Multi-AZ) | $0.436/hr x 730 hrs x 2 | $636.56 |
| Reader 1 compute | $0.436/hr x 730 hrs | $318.28 |
| Reader 2 compute | $0.436/hr x 730 hrs | $318.28 |
| Primary storage (Multi-AZ) | 1,000 GB x $0.115/GB x 2 | $230.00 |
| Reader 1 storage | 1,000 GB x $0.115/GB | $115.00 |
| Reader 2 storage | 1,000 GB x $0.115/GB | $115.00 |
| Provisioned IOPS | (10,000 - 3,000 baseline) x $0.08 x 3 instances | $1,680.00 |
| **Total** | | **$3,413.12** |

### Cost Comparison

| Configuration | Monthly Cost |
|--------------|-------------|
| Aurora Standard | $1,288.80 |
| Aurora I/O-Optimized | $1,592.94 |
| RDS PostgreSQL | $3,413.12 |

**Why is RDS so much more expensive here?**

Three factors compound:
1. **Multi-AZ doubles primary cost** - compute AND 1,000 GB provisioned storage are billed twice
2. **Provisioned storage vs consumed storage** - RDS pays for 1,000 GB provisioned on each instance (3,000 GB total). Aurora pays for 500 GB consumed once (shared across all instances).
3. **Provisioned IOPS** - RDS charges $0.08/IOPS/month for each IOPS above the 3,000 gp3 baseline, on each instance separately. At 10,000 IOPS across 3 instances, this adds $1,680/month. Aurora's I/O cost at 500 million requests is only $100/month on Standard pricing.

**When is Aurora I/O-Optimized worth it?** When your I/O costs exceed 25% of your total Aurora bill. In this example, I/O is $100 out of $1,288.80 (7.8%), so Standard pricing is cheaper. At 2+ billion monthly I/O requests, I/O-Optimized becomes the better choice.

**Verdict for production:** Aurora is dramatically cheaper at this scale, primarily because RDS provisioned IOPS and duplicated storage create significant costs that Aurora's architecture avoids entirely.

</details>

---

## Task 2: Use the AWS Pricing Calculator

Visit the AWS Pricing Calculator at [https://calculator.aws](https://calculator.aws) and build an estimate for Scenario 3 (production) using Aurora PostgreSQL.

Steps:
1. Go to calculator.aws and click "Create estimate"
2. Search for "Amazon Aurora" and click "Configure"
3. Select PostgreSQL compatibility
4. Enter the instance type, number of instances, storage, and I/O details from Scenario 3
5. Compare the calculator output to your manual calculation

This teaches you to use the official tool that you will reference in real cost proposals.

---

## Task 3: Cost Optimization Questions

Answer these questions based on what you learned. Check the answers after thinking through each one.

### Question 1

Your Aurora production cluster runs 24/7 and will run for at least 1 year. How can you reduce compute costs?

<details>
<summary>Show Answer</summary>

**Use Reserved Instances or Compute Savings Plans.**

- Reserved Instances for Aurora offer up to 40-60% discount in exchange for a 1-year or 3-year commitment.
- Compute Savings Plans apply across all AWS compute services and offer similar discounts with more flexibility.
- For a db.r6g.xlarge running 24/7, the on-demand cost is about $379.60/month. A 1-year reserved instance might reduce that to approximately $230/month - saving roughly $150/month per instance.
- With 3 instances (writer + 2 readers), that is $450/month in savings, or $5,400/year.

</details>

### Question 2

Your development Aurora instance runs 24/7 but is only used during business hours. What Aurora feature can reduce this waste?

<details>
<summary>Show Answer</summary>

**Aurora Serverless v2.**

Aurora Serverless v2 scales compute capacity based on demand, measured in Aurora Capacity Units (ACUs). During off-hours when no one is using the database, it scales down to the minimum ACU setting (as low as 0.5 ACU). During business hours, it scales up to meet demand.

At 0.5 ACU, the cost is approximately $0.06/hr instead of $0.082/hr for a db.t3.medium. Over 16 idle hours per day (nights and weekends), the savings add up significantly.

The key advantage over RDS stop/start: Aurora Serverless v2 scales smoothly without connection interruptions. RDS stop/start requires reconnection and has a 7-day auto-restart limit.

</details>

### Question 3

Your RDS production bill shows $1,680/month in provisioned IOPS charges. What is the most impactful way to reduce this?

<details>
<summary>Show Answer</summary>

**Migrate to Aurora PostgreSQL or optimize your I/O patterns.**

Three options, in order of impact:

1. **Migrate to Aurora** - Aurora's I/O pricing ($0.20/million requests) is fundamentally cheaper than RDS provisioned IOPS ($0.08/IOPS/month) for most workloads. This is the single largest cost difference between the two services at scale.

2. **Reduce provisioned IOPS** - Audit whether you actually need 10,000 IOPS. Check CloudWatch ReadIOPS and WriteIOPS metrics. If your average IOPS usage is 4,000, you are over-provisioning by 6,000 IOPS and paying $480/month for unused capacity.

3. **Switch to gp3 with baseline IOPS** - If your workload fits within 3,000 IOPS (the gp3 baseline), you pay $0 for IOPS. Only provision above the baseline if CloudWatch shows you consistently exceeding 3,000 IOPS.

</details>

---

## Summary of Key Takeaways

- Aurora costs more per compute hour than RDS, but its shared storage model eliminates the double-billing that RDS Multi-AZ and read replicas create for storage and IOPS.
- For small, low-traffic workloads (dev/test), RDS is significantly cheaper. The db.t3.micro option does not exist on Aurora.
- For production workloads with HA, read replicas, and high I/O, Aurora is often cheaper overall despite the higher per-hour compute cost.
- RDS provisioned IOPS is the most expensive cost component at scale. Aurora's per-request I/O pricing or I/O-Optimized tier is usually a better model.
- Always compare consumed storage (Aurora) vs provisioned storage (RDS). If you provision 1 TB on RDS but only use 500 GB, you are paying for 500 GB of empty space.
- Use Reserved Instances or Savings Plans for any workload running 24/7. The savings are 40-60% compared to on-demand.
- Use the AWS Pricing Calculator for formal cost proposals - do not rely on mental math alone.

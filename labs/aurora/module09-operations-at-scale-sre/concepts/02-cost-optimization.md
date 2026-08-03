# Concepts 02: Cost Optimization

**Module 09: Operations at Scale and SRE**
**Reading Time:** 25-30 minutes

---

## The Problem with "Set It and Forget It" Pricing

AWS RDS and Aurora pricing is multidimensional. Most teams optimize instance type at launch and never revisit the decision. At scale, this leaves money on the table across four other levers. A fleet of 20 Aurora instances with unoptimized storage, no Reserved Instances, Intel processors where Graviton would work, and over-provisioned instance classes can easily waste $50,000-$100,000 per year.

Cost optimization is not a one-time project. It is a quarterly discipline. Workloads change, pricing changes, new instance families launch, and business priorities shift. The DBA who reviews cost quarterly is the DBA whose leadership trusts their budget numbers.

---

## The Five Cost Levers

### Lever 1: Storage Pricing Model (I/O-Optimized vs Standard)

Aurora offers two storage billing modes. Choosing the wrong one is one of the most common sources of unnecessary cost.

**Aurora Standard:**
- Storage: ~$0.10 per GB-month
- I/O: $0.20 per 1 million requests

**Aurora I/O-Optimized:**
- Storage: ~$0.225 per GB-month (roughly 2.25x Standard)
- I/O: $0.00 - zero per-I/O charge

The break-even point is when I/O charges in Standard mode equal the additional storage cost in I/O-Optimized mode. AWS estimates this occurs when I/O costs exceed approximately 25% of total Aurora spend.

**How to determine your current I/O cost:**
1. Open Cost Explorer in the AWS console.
2. Filter by Service: Relational Database Service.
3. Group by Usage Type.
4. Find `Aurora:StorageIOUsage` - this is your per-I/O charge.
5. Compare this to your total Aurora line item.

If I/O charges exceed 25% of total Aurora spend, I/O-Optimized is likely cheaper. For write-heavy OLTP workloads, this threshold is often crossed quickly.

**Break-even example:**
- 500 GB cluster on Standard: Storage = $50/month
- Same cluster with 10 billion I/Os: I/O cost = $2,000/month
- Total Standard cost: $2,050/month
- Same cluster on I/O-Optimized: Storage = $112.50/month, I/O = $0
- Total I/O-Optimized cost: $112.50/month
- Savings: $1,937.50/month

The switch from Standard to I/O-Optimized is online - no downtime. It applies immediately.

### Lever 2: Reserved Instances

Reserved Instances (RIs) reduce On-Demand costs by 30-60% for a 1 or 3-year commitment.

**Key concepts:**

| RI Type | Flexibility | Discount |
|---------|-------------|----------|
| Standard Reserved | Fixed instance type, AZ, region | Highest (up to 60%) |
| Convertible Reserved | Can exchange for different instance types | Lower (up to 40%) |

**Payment options:**
- **All Upfront:** Best discount. You pay the full amount at purchase.
- **Partial Upfront:** Some upfront, reduced hourly rate.
- **No Upfront:** No upfront payment, reduced hourly rate. Lowest discount.

**RI savings example for db.r6g.2xlarge:**
- On-Demand: ~$0.996/hour = ~$8,725/year
- 1-year All Upfront RI: ~$5,534 = saving ~$3,191/year (37%)
- 3-year All Upfront RI: ~$3,888/year = saving ~$4,837/year (55%)

Break-even on a 1-year RI occurs at approximately month 7. After 7 months, the prepaid cost is recovered compared to On-Demand pricing.

**RI coverage analysis:**

Compare your RI coverage against your running instances quarterly. Track:
- Which On-Demand instances have no RI coverage
- Which RIs are expiring within 90 days (renew or adjust)
- Whether your instance mix has changed since the last RI purchase (different instance classes may be needed)

**The risk of RIs:** Committing to capacity you stop using. RI management requires quarterly review aligned with engineering roadmaps. If a team plans to decommission a service in 6 months, buying a 3-year RI for its database is waste.

### Lever 3: Graviton vs Intel

AWS Graviton (ARM-based) instances offer 10-20% better price/performance than equivalent Intel instances for PostgreSQL workloads.

| Aspect | Intel (r6i, m6i) | Graviton (r6g, m7g) |
|--------|-----------------|---------------------|
| Cost | Baseline | ~10% cheaper |
| Performance | Baseline | Neutral to positive for PostgreSQL |
| Extension compatibility | All | All standard extensions; custom compiled extensions need ARM build |
| Migration method | N/A | Blue/Green deployment or snapshot/restore |

Graviton migration is not an in-place operation. You create a new instance with the Graviton class and either restore a snapshot to it or use Blue/Green deployment for minimal downtime.

**Migration checklist before switching:**
1. Verify all extensions used are available on Graviton (standard extensions are fine)
2. Test the workload on a Graviton staging instance
3. Use Blue/Green deployment for production to minimize downtime
4. Update RI purchases to Graviton instance classes going forward

### Lever 4: Aurora Serverless v2

Serverless v2 charges by Aurora Capacity Unit (ACU) per second. 1 ACU provides approximately 2 GB RAM and proportional CPU.

**Pricing (us-east-1):** ~$0.12 per ACU-hour

**When Serverless v2 makes sense:**
- High workload variability (dev/test, batch jobs, multi-tenant SaaS)
- Workloads that idle for significant periods
- Predictable peaks with long valleys between them

**When Serverless v2 does NOT make sense:**
- Steady, high-throughput OLTP (provisioned is cheaper at sustained high utilization)
- Workloads requiring guaranteed minimum performance without cold start

**Cost modeling example:**
- `db.r6g.2xlarge` has 64 GB RAM, which is approximately 32 ACUs
- Average workload uses 8 ACUs (25% utilization), peaks at 32 ACUs
- Serverless v2 average cost: 8 ACUs x $0.12/ACU-hour x 730 hours/month = $700/month
- Provisioned On-Demand: ~$730/month
- At 25% average utilization, costs are roughly equivalent but Serverless scales automatically

If average utilization drops to 15% (4-5 ACUs), Serverless saves approximately 50%. If average utilization is 80%+, provisioned is significantly cheaper.

### Lever 5: Right-Sizing

AWS Cost Explorer generates right-sizing recommendations from the last 14 days of CPU, memory, and connection metrics.

**How to access recommendations:**
1. Open Billing and Cost Management.
2. Select Cost Explorer.
3. Click Rightsizing recommendations.
4. Filter to Amazon RDS.

**Interpreting recommendations:**

Cost Explorer recommendations are a starting point, not a final answer. Before downsizing:

1. Check the utilization data against your knowledge of peak traffic. 14 days may miss monthly or quarterly peaks.
2. Verify there is headroom for memory-intensive operations like VACUUM on large tables.
3. Test the smaller instance class in staging under realistic load.
4. Confirm the smaller instance's `max_connections` default is sufficient for your connection count.

**Right-sizing decision matrix:**

| Current avg CPU | Current avg connections | Recommendation |
|----------------|------------------------|----------------|
| < 20% | < 30% of max | Downsize - over-provisioned |
| 20-60% | 30-60% of max | Correct - monitor quarterly |
| 60-80% | 60-80% of max | Plan upgrade within 6 months |
| > 80% | > 80% of max | Upgrade now - insufficient headroom |

---

## RI Coverage and Planning

### The RI Coverage Report

RI coverage is the percentage of your running instance-hours that are covered by Reserved Instances. Track this metric monthly.

```
RI Coverage = (RI-covered instance-hours) / (total instance-hours) x 100
```

An RI coverage target of 70-80% for stable production workloads is typical. You keep 20-30% on On-Demand for instances that may change (dev/test, short-lived workloads, workloads being migrated).

### RI Planning Process

1. **Inventory:** List all running instances, their classes, and whether they have RI coverage.
2. **Stability assessment:** Which instances will still exist in 1 year? In 3 years?
3. **Engineering roadmap alignment:** Are any teams planning to decommission services, migrate to different instance classes, or adopt Serverless?
4. **Purchase recommendation:** For stable instances expected to run for 1+ years, recommend 1-year All Upfront RIs. For highly stable infrastructure (core platform databases), consider 3-year terms.
5. **Expiration tracking:** Flag RIs expiring within 90 days for renewal review.

### Savings Plans as an Alternative

AWS Savings Plans offer similar discounts to RIs but with more flexibility. A Compute Savings Plan applies to any instance family in any region. For organizations that frequently change instance types, Savings Plans may offer better flexibility at a slightly lower discount than Standard RIs.

---

## Cost Governance at Scale

### Tagging for Cost Allocation

Every RDS instance must be tagged with a `CostCenter` tag that maps to a team or business unit. Without this tag, cost allocation reports are meaningless.

```
CostCenter:     CC-1042
Environment:    production
Application:    payments-api
Team:           platform
```

Enable Cost Allocation Tags in the Billing console to make these tags appear in Cost Explorer.

### AWS Budgets

Create budget alerts to catch cost spikes before the monthly bill arrives:

- **RDS service budget:** Alert at 120% of previous month's RDS spend
- **Per-cluster budget:** Alert when any single cluster exceeds its historical baseline by 50%
- **CloudWatch Logs budget:** Alert when log ingestion costs spike (a common surprise from verbose query logging)

### Quarterly Cost Review

Schedule a quarterly review that covers:

1. RI coverage and expiration
2. Storage mode optimization (Standard vs I/O-Optimized)
3. Right-sizing recommendations
4. Graviton migration candidates
5. CloudWatch Logs cost (are logging parameters still appropriate?)
6. Unused or orphaned resources (snapshots, parameter groups, option groups)

---

## Common Cost Traps

### Trap 1: Verbose Query Logging

Setting `log_min_duration_statement = 0` logs every query. On a busy instance doing 10,000 queries per second, this generates enormous CloudWatch Logs volume. At $0.50/GB ingested, a single misconfigured parameter can add $500-$2,000/month to your bill.

Fix: Set `log_min_duration_statement` to 1000 (1 second) or higher for production. Only set to 0 temporarily during debugging sessions.

### Trap 2: Unbounded Log Retention

CloudWatch Logs default retention is "never expire." If you export PostgreSQL logs and never set a retention policy, log storage grows forever. A busy cluster can accumulate terabytes of logs over years.

Fix: Set a retention policy on every RDS log group. 90 days is reasonable for operational logs. For compliance (HIPAA), export to S3 with lifecycle policies for long-term storage at lower cost.

### Trap 3: Orphaned Snapshots

Manual snapshots are not automatically cleaned up. Teams that take pre-migration snapshots and forget to delete them accumulate storage charges.

Fix: Audit manual snapshots quarterly. Delete snapshots older than 90 days unless they are explicitly tagged for long-term retention.

### Trap 4: Over-Provisioned Dev/Test

Development and staging databases are often cloned from production and never downsized. A production `db.r6g.4xlarge` cloned for development runs 24/7 at 5% CPU utilization.

Fix: Use smaller instance classes for non-production. Consider Aurora Serverless v2 for dev/test to scale to near-zero when idle.

### Trap 5: Inactive Replication Slots

Logical replication slots that are no longer in use retain WAL indefinitely. This consumes storage (which costs money) and can eventually cause storage exhaustion.

Fix: Monitor `pg_replication_slots` monthly. Drop any slot where `active = false` and the consumer application has been decommissioned.

---

## Summary

| Optimization Lever | When to Use | Estimated Savings |
|-------------------|-------------|-------------------|
| I/O-Optimized storage | Aurora I/O > 25% of total Aurora spend | 20-40% on I/O-heavy workloads |
| Reserved Instances | Stable workloads running 24/7 for 1+ years | 30-60% vs On-Demand |
| Graviton migration | Intel-based instances with compatible workloads | 10-20% on compute |
| Serverless v2 | High-variability workloads, dev/test | 30-50% on variable load |
| Right-sizing | Instances running below 40% average CPU | 20-50% on over-provisioned |
| Log management | Verbose logging or no retention policy | Variable - can be $500+/month |

Cost optimization is a continuous practice, not a one-time project. The DBA who reviews costs quarterly and presents findings to leadership builds trust, protects the budget, and demonstrates the strategic value of the database team.

**Next:** [Concepts 03 - Incident Management](./03-incident-management.md)

# USE 02: Cost Optimization Exercise

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 30-40 minutes

---

## Context

You manage a fleet of 8 Aurora PostgreSQL clusters across three AWS accounts (dev, staging, production). The CFO has asked you to reduce the annual database spend by 30% without impacting reliability. Current annual spend is $180,000 across all clusters. You need to present a savings plan with specific actions and timelines.

---

## Part 1: Cost Analysis

<details>
<summary>Task 1.1: Given the following fleet inventory, identify which cost levers apply to each cluster.</summary>

**Fleet Inventory:**

| Cluster | Account | Instance Class | Instances | Storage Mode | RI Coverage | Avg CPU | Avg I/O Cost (% of total) |
|---------|---------|---------------|-----------|-------------|------------|---------|--------------------------|
| app-primary | prod | db.r6i.2xlarge | 3 | Standard | None | 45% | 35% |
| app-reporting | prod | db.r6i.xlarge | 2 | Standard | None | 15% | 10% |
| api-gateway | prod | db.r6g.large | 2 | I/O-Optimized | 1yr RI | 60% | N/A |
| batch-processor | prod | db.r6i.4xlarge | 1 | Standard | None | 8% | 45% |
| app-staging | staging | db.r6i.2xlarge | 2 | Standard | None | 12% | 5% |
| app-dev | dev | db.r6i.xlarge | 2 | Standard | None | 5% | 3% |
| analytics | prod | db.r6g.2xlarge | 2 | Standard | None | 70% | 28% |
| sandbox | dev | db.r6i.large | 1 | Standard | None | 2% | 1% |

For each cluster, mark which levers apply:
- S = Switch to I/O-Optimized storage
- R = Purchase Reserved Instances
- G = Migrate to Graviton
- D = Downsize (right-size)
- V = Convert to Serverless v2

**Example answer:**

| Cluster | S | R | G | D | V | Notes |
|---------|---|---|---|---|---|-------|
| app-primary | Yes | Yes | Yes (r6i to r7g) | No | No | I/O at 35% - well above 25% threshold. Intel to Graviton. Stable = RI candidate. |
| app-reporting | No | Yes | Yes | Yes | No | CPU at 15% - over-provisioned. Downsize to db.r6g.large. |
| api-gateway | N/A | Already | Already | No | No | Already optimized. Good reference. |
| batch-processor | Yes | No | Yes | Yes | Maybe | I/O at 45%. CPU at 8% - massively over-provisioned. Consider Serverless v2 if batch is periodic. |
| app-staging | No | No | Yes | Yes | Yes | CPU at 12%. Staging does not need r6i.2xlarge. Serverless v2 ideal for variable staging use. |
| app-dev | No | No | Yes | Yes | Yes | CPU at 5%. Serverless v2 perfect for dev. |
| analytics | Yes | Yes | Already | No | No | I/O at 28%. CPU at 70% - correctly sized. RI candidate. |
| sandbox | No | No | Yes | Yes | Yes | CPU at 2%. Convert to Serverless v2 or shut down when not in use. |

</details>

<details>
<summary>Task 1.2: Calculate the estimated annual cost for each cluster and the total fleet cost. Use the following pricing (us-east-1).</summary>

**Pricing Reference:**

| Instance Class | On-Demand ($/hr) | 1yr All Upfront ($/yr) |
|---------------|-------------------|----------------------|
| db.r6i.4xlarge | $3.264 | $20,400 |
| db.r6i.2xlarge | $1.632 | $10,200 |
| db.r6i.xlarge | $0.816 | $5,100 |
| db.r6i.large | $0.408 | $2,550 |
| db.r6g.2xlarge | $1.464 | $9,150 |
| db.r6g.xlarge | $0.732 | $4,575 |
| db.r6g.large | $0.366 | $2,285 |
| db.r6g.medium | $0.183 | $1,143 |
| db.r7g.2xlarge | $1.536 | $9,600 |
| db.r7g.xlarge | $0.768 | $4,800 |
| db.r7g.large | $0.384 | $2,400 |

**Example answer:**

| Cluster | Instances | Rate | Annual Cost |
|---------|-----------|------|------------|
| app-primary | 3 x db.r6i.2xlarge | $1.632/hr x 3 | $42,889 |
| app-reporting | 2 x db.r6i.xlarge | $0.816/hr x 2 | $14,296 |
| api-gateway | 2 x db.r6g.large | RI: $2,285 x 2 | $4,570 |
| batch-processor | 1 x db.r6i.4xlarge | $3.264/hr | $28,593 |
| app-staging | 2 x db.r6i.2xlarge | $1.632/hr x 2 | $28,593 |
| app-dev | 2 x db.r6i.xlarge | $0.816/hr x 2 | $14,296 |
| analytics | 2 x db.r6g.2xlarge | $1.464/hr x 2 | $25,650 |
| sandbox | 1 x db.r6i.large | $0.408/hr | $3,574 |
| **Total** | | | **$162,461** |
| + Storage/I/O (~10%) | | | **~$178,700** |

</details>

---

## Part 2: Optimization Plan

<details>
<summary>Task 2.1: Build a prioritized optimization plan. Group actions by timeline (immediate, 30 days, 90 days) and calculate expected savings for each action.</summary>

Your plan should include:
- The specific action
- Which cluster it applies to
- Risk level (low/medium/high)
- Estimated annual savings
- Prerequisites before executing

**Example answer:**

### Immediate Actions (This Week) - Low Risk

| Action | Cluster | Savings/yr | Risk |
|--------|---------|-----------|------|
| Switch to I/O-Optimized | app-primary | ~$8,000 | Low (online, no downtime) |
| Switch to I/O-Optimized | batch-processor | ~$6,000 | Low |
| Switch to I/O-Optimized | analytics | ~$3,000 | Low |
| **Subtotal** | | **~$17,000** | |

### 30-Day Actions - Medium Risk

| Action | Cluster | Savings/yr | Risk |
|--------|---------|-----------|------|
| Convert app-dev to Serverless v2 | app-dev | ~$10,000 | Medium (test app compatibility) |
| Convert sandbox to Serverless v2 | sandbox | ~$2,500 | Medium |
| Downsize app-reporting (r6i.xl to r6g.large) | app-reporting | ~$8,000 | Medium (test under load) |
| Downsize app-staging (r6i.2xl to r6g.large) | app-staging | ~$22,000 | Medium (test staging workflows) |
| **Subtotal** | | **~$42,500** | |

### 90-Day Actions - Requires Planning

| Action | Cluster | Savings/yr | Risk |
|--------|---------|-----------|------|
| Purchase RIs for app-primary (3x r7g.2xl) | app-primary | ~$12,000 | Low (financial commitment) |
| Migrate app-primary Intel to Graviton | app-primary | ~$3,000 | Medium (Blue/Green deployment) |
| Purchase RI for analytics (2x r6g.2xl) | analytics | ~$8,000 | Low |
| Right-size batch-processor + Serverless v2 | batch-processor | ~$20,000 | High (test batch job timing) |
| **Subtotal** | | **~$43,000** | |

### Total Projected Savings: ~$102,500/year (57% reduction)

</details>

---

## Part 3: Risk Assessment

<details>
<summary>Task 3.1: For each medium and high-risk action, describe the testing process you would follow before executing in production.</summary>

For each action, specify:
- How you would test in staging first
- What metrics you would monitor during and after the change
- Your rollback plan if something goes wrong
- The maintenance window requirements

**Example answer:**

**Downsize app-reporting (r6i.xlarge to r6g.large):**

1. Testing:
   - Clone production data to staging on db.r6g.large
   - Run representative reporting queries and measure latency
   - Verify max_connections default is sufficient (IMPORTANT: smaller instances have lower defaults)
   - Run during peak load simulation

2. Metrics to monitor:
   - CPU utilization (must stay below 70% at peak)
   - FreeableMemory (must stay above 2 GB minimum)
   - ReadLatency and WriteLatency
   - DatabaseConnections (must not approach max)

3. Rollback plan:
   - Use Blue/Green deployment to switch back to original class
   - Rollback time: ~5 minutes
   - Or: modify-db-instance back to original class (causes brief outage)

4. Maintenance window:
   - Schedule during lowest traffic period (Sunday 2-4 AM)
   - Notify stakeholders 48 hours in advance
   - DBA on standby for 2 hours post-change

</details>

---

## Part 4: CFO Presentation

<details>
<summary>Task 4.1: Create a one-page summary for the CFO. Include current spend, projected savings, timeline, and any risks to reliability.</summary>

Your summary should be non-technical and focused on business impact:

**Example answer:**

```
DATABASE COST OPTIMIZATION SUMMARY
===================================

Current Annual Spend:  $178,700
Projected Annual Spend: $76,200
Annual Savings:        $102,500 (57%)
Target (30% reduction): $53,610 - EXCEEDED

TIMELINE:
- Week 1:   $17,000/yr savings (storage optimization, zero risk)
- Month 1:  $42,500/yr savings (right-sizing dev/staging/reporting)
- Quarter 1: $43,000/yr savings (Reserved Instances, Graviton migration)

RELIABILITY IMPACT:
- No degradation to production SLOs
- All changes tested in staging before production
- Dev/staging changes reduce cost without impacting development workflow
- Reserved Instances lock in pricing but require 1-year commitment

RISKS:
- Serverless v2 conversion for batch-processor needs careful testing
  (batch job duration may increase on smaller capacity)
- Graviton migration requires Blue/Green deployment (15-minute window)

APPROVAL NEEDED:
- Reserved Instance purchases: $23,550 upfront (1-year terms)
- Engineering time: ~40 hours over 90 days for testing and migration
```

</details>

---

## Deliverables

By the end of this exercise, you should have:

1. Cost lever analysis for each cluster in the fleet
2. Calculated baseline annual cost
3. Prioritized optimization plan with timeline
4. Risk assessment with testing procedures
5. CFO-ready summary

---

## Reflection Questions

1. Why should you avoid purchasing Reserved Instances for dev/test environments?
2. What is the risk of right-sizing based on only 14 days of CPU data?
3. When would you choose Convertible RIs over Standard RIs?
4. How would you handle a situation where the batch-processor needs db.r6i.4xlarge for 2 hours per day but is idle the other 22 hours?

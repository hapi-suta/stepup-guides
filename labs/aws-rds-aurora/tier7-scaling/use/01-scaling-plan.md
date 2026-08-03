# Tier 7 - USE Exercise 01: Scaling Plan

**Exercise type:** Analysis and planning (no infrastructure required)
**Time:** 30 minutes
**Goal:** Given a real-world scenario, produce a complete scaling plan with justification, timeline, and rollback steps.

---

## Scenario

You are the lead DBA at a SaaS company. Your production Aurora PostgreSQL cluster has the following profile:

- **Current instance class:** db.r6g.2xlarge (8 vCPU, 64 GiB RAM)
- **Storage:** 800 GiB allocated, 120 GiB free, storage autoscaling enabled with 2 TiB maximum
- **CloudWatch:** CPUUtilization averaging 78% during business hours (9 AM - 6 PM weekdays)
- **DatabaseConnections:** Peaking at 380 connections, average 210
- **FreeableMemory:** Averaging 4.2 GiB during peak hours
- **ReadIOPS / WriteIOPS:** Both well under provisioned limits
- **Pattern:** CPU spike every morning 9-10 AM (batch processing job), sustained high CPU 11 AM - 3 PM

Business context:
- Traffic is expected to grow 30% over the next 3 months due to a product launch.
- The quarterly earnings report is in 6 weeks. No maintenance windows allowed during that period (starts in 2 weeks).
- The company is evaluating Aurora Serverless v2 as a cost optimization measure.

---

## Tasks

### Task 1: Root Cause Analysis

Before recommending a scaling action, determine what is actually causing the CPU pressure.

Answer these questions in writing:

1. The CPU is averaging 78% during business hours. Is this a compute problem, a query problem, or both? What additional data would you collect to distinguish between them?

2. FreeableMemory at 4.2 GiB on a 64 GiB instance is roughly 6.5% free. Is this concerning for PostgreSQL? What does low freeable memory typically indicate in RDS?

3. The morning spike (9-10 AM) is correlated with a batch job. Should you address the spike differently than the sustained midday load? Why?

4. What two CloudWatch metrics would you examine to determine whether adding a read replica would reduce CPU pressure?

---

### Task 2: Vertical Scaling Recommendation

You have decided to scale up the instance class.

1. What instance class do you recommend? Justify your choice (consider the memory:CPU ratio for PostgreSQL workloads).

2. Write the exact AWS CLI command to submit the modification request. Include all required flags. Do not apply immediately - schedule for the next maintenance window.

3. With Multi-AZ enabled, what is the expected downtime? Describe the sequence of events during the resize.

4. Write the CLI command to verify the modification is pending (not yet applied).

5. The on-call engineer asks: "How will we know the resize completed successfully?" What specific metric or event would you monitor?

---

### Task 3: Storage Autoscaling Review

Current storage: 800 GiB allocated, 120 GiB free. Autoscaling is enabled with a 2 TiB maximum.

1. At the current free space level, will autoscaling trigger? What is the threshold condition?

2. If writes grow 30% due to the product launch, estimate when autoscaling will trigger. Show your work.

3. The current maximum is 2 TiB. Is this appropriate? What would happen if the database grew beyond 2 TiB?

4. What is the 6-hour cooldown limitation and why does it matter for this scenario?

5. Write the CloudWatch alarm CLI command to alert when free storage drops below 200 GiB.

---

### Task 4: Serverless v2 Evaluation

The business wants to know if Aurora Serverless v2 could replace this provisioned cluster.

1. Based on the workload profile described (high and consistent business-hours CPU, specific batch spike pattern), is this a good or poor fit for Serverless v2? Explain.

2. If you were to migrate to Serverless v2, what ACU range would you set? Show your reasoning.

3. Calculate the break-even: at what average ACU level would Serverless v2 cost more than the current db.r6g.2xlarge? (Use $0.52/hr for db.r6g.2xlarge, $0.12/ACU-hr for ASv2.)

4. What are two operational advantages of Serverless v2 for this specific company, and two risks?

---

### Task 5: Timeline and Rollback Plan

Produce a migration timeline and rollback plan for the instance class upgrade.

1. You have a 2-week window before the earnings period begins. Build a day-by-day timeline including: testing in staging, maintenance window scheduling, monitoring period, and rollback decision point.

2. What is your rollback procedure if performance degrades after the resize? Be specific about what you would observe and how long you would wait before rolling back.

3. Who needs to be notified before executing the resize? What information do they need?

---

## Deliverable

Write up your answers as if you are presenting to the engineering leadership team. Use headings. Be specific - avoid vague answers like "monitor CloudWatch." Name the specific metrics, thresholds, and commands.

---

## Reference Answers (Check After Completing)

### Task 1 Guidance

- CPU pressure without I/O pressure suggests query efficiency issues or connection overhead, not raw compute shortage. You would collect `pg_stat_statements` top queries by total execution time and `DatabaseConnections` time series to see if connection count correlates with CPU spikes.
- 4.2 GiB free on 64 GiB (6.5%) is a yellow flag but not critical for PostgreSQL. PostgreSQL uses shared_buffers plus OS page cache. Low freeable memory can mean the OS cache is being evicted, causing more disk reads. Check `ReadIOPS` - if it is rising alongside low memory, that is the pattern.
- The batch spike should be addressed separately: move the batch job to off-hours, reduce its parallelism, or add it to a read replica. The sustained midday load is the scaling target.
- `CPUUtilization` on read replicas and `ReadIOPS` on the primary. If replicas have spare CPU while the primary is saturated, the workload is read-heavy and more replicas would help.

### Task 3 Guidance

- Autoscaling triggers when free space < 10% of allocated. 10% of 800 GiB = 80 GiB. Current free is 120 GiB - NOT triggering yet. But approaching.
- With 30% growth in writes, free space decreases faster. If the database currently uses 680 GiB and grows 30%, it needs 884 GiB. Autoscaling would trigger and expand to roughly 970 GiB (10% overage rounding). Timeline depends on write rate, but plan for autoscaling to trigger within weeks of launch.

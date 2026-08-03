# USE 05 - Serverless v2 Sizing: Right-Size ACU Ranges
## Apply What You Learned | Tier 4

---

## What You Will Practice

- Reading CloudWatch ACU metrics to find the right range
- Matching ACU ranges to workload patterns
- Calculating cost tradeoffs between Serverless v2 and provisioned
- Identifying when Serverless v2 is and is not the right choice

---

## Background

Setting ACU ranges incorrectly causes two problems:
1. Minimum too high - you pay for capacity you do not use at idle
2. Maximum too low - queries queue up or get throttled during spikes

The goal is: minimum covers baseline load, maximum handles peak spikes.

---

## Reading the CloudWatch Data

Before each exercise, understand how to pull the data you need.

Get ACU usage over the past 24 hours in 5-minute intervals:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average Maximum \
  --region us-east-1
```

`--statistics Average Maximum` - you want both the average and peak.
`--period 300` - 5-minute data points give you a good view of patterns.

Also check CPU, memory, and connections:

```bash
# CPU
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average Maximum \
  --region us-east-1
```

```bash
# Connections
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 300 \
  --statistics Average Maximum \
  --region us-east-1
```

---

## Exercise 1 - Dev/Test Environment

**Observed ACU pattern over 1 week:**

```
Mon-Fri 9am-6pm:  2-4 ACU (developers actively testing)
Mon-Fri nights:   0.5 ACU (idle)
Weekends:         0.5 ACU (idle)
Occasional spikes: 6 ACU (during load tests, 30-min duration)
```

**Question 1:** What minimum and maximum ACU would you set?

**Question 2:** Could you use a provisioned db.t3.medium instead? How would the cost compare?

**Question 3:** If a developer complains that their first query each Monday morning is slow, what is the likely cause and how would you fix it?

---

## Exercise 2 - E-Commerce Application (Business Hours)

**Observed ACU pattern over 1 week:**

```
Mon-Fri 10am-8pm:  8-12 ACU (peak shopping)
Mon-Fri 8pm-10pm:  4-6 ACU (winding down)
Mon-Fri nights:    1-2 ACU (cron jobs, background processing)
Weekends:          10-16 ACU (highest traffic days)
Peak event (sale): 20+ ACU for 2-3 hours
```

**Question 4:** What minimum and maximum ACU would you set?

**Question 5:** The team wants to run a flash sale that could double traffic. Should you raise the ACU maximum before the sale? How would you do that without downtime?

**Question 6:** At sustained 12 ACU, is Serverless v2 cheaper or more expensive than a provisioned db.r6g.2xlarge? (Assume us-east-1 pricing: $0.12/ACU-hour, db.r6g.2xlarge = $0.96/hr)

---

## Exercise 3 - API Backend (Spiky Traffic)

**Observed ACU pattern over 1 week:**

```
Random spikes: 0.5 -> 8 ACU in under 30 seconds
Quiet periods: 0.5 ACU for hours
No predictable pattern
P99 API latency SLA: under 200ms
Current situation: API timeouts during the 30-second ramp-up from 0.5 to 8 ACU
```

**Question 7:** The problem is the ramp-up time (30 seconds at 0.5 ACU causes cold-start latency). What minimum ACU would you set to eliminate this?

**Question 8:** The engineering team says "just switch to provisioned db.r6g.2xlarge and be done with it." At average 2 ACU usage, what would the monthly cost be for Serverless v2 vs db.r6g.2xlarge? Which is cheaper?

---

## Exercise 4 - Interpret CloudWatch Output

Here is sample CloudWatch output from a real cluster over 4 hours. Interpret it.

```
Time       | Average ACU | Maximum ACU
-----------+-------------+-------------
14:00      | 0.5         | 0.5
14:05      | 0.5         | 0.5
14:10      | 2.1         | 3.5
14:15      | 4.8         | 6.0
14:20      | 6.2         | 8.0
14:25      | 7.9         | 9.5
14:30      | 8.0         | 8.0    <-- notice max = average
14:35      | 8.0         | 8.0    <-- same
14:40      | 7.8         | 8.0    <-- same
14:45      | 3.1         | 5.0
14:50      | 0.8         | 1.5
14:55      | 0.5         | 0.5
```

**Question 9:** What happened between 14:10 and 14:45?

**Question 10:** At 14:30-14:40, the average and maximum are both 8.0. What does this mean? Is 8.0 the configured maximum?

**Question 11:** If the cluster is configured with MaxCapacity=8, what is happening at 14:30? Is this a problem?

**Question 12:** What would you change to handle the load at 14:25-14:40 without hitting the ceiling?

---

## Exercise 5 - Hands-On: Find Your Cluster's Actual Baseline and Peak

Run these queries on your Serverless v2 cluster from BUILD 07.

Step 1 - Generate a realistic load pattern (run this over 10 minutes):

```bash
# Phase 1: Light load (2 minutes)
pgbench -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres -d pgbenchdb \
        --client 5 --jobs 1 --time 120 --progress 30

# Phase 2: Heavy load (3 minutes)
pgbench -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres -d pgbenchdb \
        --client 40 --jobs 4 --time 180 --progress 30

# Phase 3: Light load again (2 minutes)
pgbench -h my-serverless-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com \
        -U postgres -d pgbenchdb \
        --client 5 --jobs 1 --time 120 --progress 30
```

Step 2 - After the test, pull the ACU data:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=my-serverless-cluster \
  --start-time $(date -u -v-15M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 30 \
  --statistics Average Maximum \
  --region us-east-1
```

Step 3 - Answer these questions from your own data:

**Question 13:** What was your peak ACU during the heavy load phase?

**Question 14:** How quickly did the cluster scale from the light load baseline to the heavy load peak?

**Question 15:** Based on your test data, what min/max ACU would you set for a production cluster that has this traffic pattern?

---

## ACU Sizing Reference

Use these formulas as starting points. Adjust based on actual CloudWatch data.

**Minimum ACU:**
- Set to the average ACU during your slowest period
- Round up to nearest 0.5
- Add 0.5-1 ACU buffer for warm-up headroom

**Maximum ACU:**
- Set to 1.5-2x your observed peak ACU
- Never set lower than your observed peak (queries will queue)
- Consider future growth (set 20-30% higher than current peak)

**Memory-Based Sizing:**
```
If your queries use lots of memory (large sorts, hash joins):
  ACU needed = (expected working set in GB) / 2

Example: 8 GB of tables being scanned = 4 ACU minimum for cache
```

---

## Answer Guide

**Q1:** Min=0.5, Max=8. The idle is 0.5 so minimum matches. The load test spikes to 6, so max=8 gives a comfortable buffer.

**Q2:** db.t3.medium = $0.068/hr x 720 hrs = ~$49/month. Serverless v2 at 0.5 ACU idle most of the time = ~$0.06/hr x ~600 idle hours + $0.24/hr x ~120 business hours = $36+$29 = ~$65/month. Serverless v2 is slightly more expensive but scales for load tests. For a pure dev/test with no spikes, t3.medium wins on cost.

**Q3:** The cluster is at 0.5 ACU (minimum) over the weekend. The first Monday morning queries cause a scale-up. This takes 30-60 seconds which feels like a "slow first query." Fix: increase the minimum to 1-2 ACUs, or use a warm-up query in the application startup.

**Q4:** Min=2 (covers night background jobs), Max=24 (covers weekend peak plus buffer above 16). The flash sale risk makes you want extra headroom.

**Q5:** Run this before the sale (no downtime):
```bash
aws rds modify-db-cluster \
  --db-cluster-identifier my-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=2,MaxCapacity=32 \
  --apply-immediately \
  --region us-east-1
```
After the sale, lower the max back down.

**Q6:** 12 ACU x $0.12 = $1.44/hr. db.r6g.2xlarge = $0.96/hr. Provisioned is 33% cheaper at sustained 12 ACU. This workload should probably use a provisioned writer and Serverless readers (mixed cluster) or a provisioned instance outright.

**Q7:** Set minimum to 4 ACU. The spikes go to 8 ACU, so a minimum of 4 means only a 2x scale-up is needed, which happens in seconds. Starting from 0.5 to 8 is a 16x scale-up which takes longer.

**Q8:** 2 ACU average x $0.12 x 720 hrs = ~$173/month. db.r6g.2xlarge = $0.96 x 720 = $691/month. Serverless v2 wins by a large margin at average 2 ACU. The engineering team's suggestion would cost 4x more.

**Q9:** A load spike started around 14:10 and ended around 14:45. The cluster scaled up from 0.5 to ~8 ACU and then back down.

**Q10:** When average = maximum in a CloudWatch period, it means the ACU was at that level the entire 5-minute window. The cluster was pinned at 8 ACU with no variation.

**Q11:** If MaxCapacity=8, the cluster hit its ceiling at 14:30. Queries that need more capacity will experience increased latency or connection queuing. This is a problem if latency SLAs are being breached.

**Q12:** Increase MaxCapacity to 12 or 16 to allow the cluster to scale past 8 during the load spike. Then monitor actual peak to set the right ceiling.

**Q13-Q15:** Answers depend on your actual test results. Use the ACU sizing reference formulas to calculate your recommended range.

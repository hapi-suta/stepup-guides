# USE 03 - Scaling Decisions: Auto-Scaling and Serverless v2
## Apply What You Learned | Module 05

---

## Instructions

Read each scenario. Make your scaling recommendation. Then reveal the solution to compare.

---

## Exercise 1 - Serverless v2 ACU Sizing

Your cluster shows this ACU pattern over one week:

```
Mon-Fri 9am-6pm:  3-6 ACU (business hours)
Mon-Fri nights:   0.5 ACU (idle)
Weekends:         0.5 ACU (idle)
Occasional spike: 10 ACU (during monthly report, 1 hour)
```

**Question 1:** What min/max ACU would you set?

**Question 2:** A developer complains that Monday morning queries are slow for the first 30 seconds. What is the likely cause and how do you fix it?

<details>
<summary>Click to reveal solution</summary>

**Q1:** Min=0.5, Max=12. The idle periods are at 0.5 so minimum matches. The monthly spike hits 10 ACU, so max=12 gives a comfortable 20% buffer.

Alternative: if the Monday morning slowness is a problem, set Min=1 to keep the cluster warmer.

**Q2:** The cluster scaled down to 0.5 ACU over the weekend. Monday morning, the first queries trigger a scale-up from 0.5 to 3+ ACU. This scale-up takes a few seconds, during which queries experience higher latency. Fix: increase the minimum to 1-2 ACU, or add a "warm-up" query that runs before the application starts Monday morning (e.g., a cron job at 8:55 AM that runs a simple SELECT).

</details>

---

## Exercise 2 - Serverless v2 vs Provisioned Cost

Your workload runs at a sustained 8 ACU during business hours (12 hours/day, 5 days/week) and 0.5 ACU the rest of the time.

Pricing (us-east-1):
- Serverless v2: $0.12 per ACU-hour
- db.r6g.xlarge (comparable to 8 ACU): $0.48/hr

**Question:** Calculate the weekly cost for Serverless v2 vs db.r6g.xlarge.

<details>
<summary>Click to reveal solution</summary>

**Serverless v2 weekly cost:**
- Business hours: 12 hrs/day x 5 days x 8 ACU x $0.12 = $57.60
- Off-hours: (24-12) hrs x 5 days x 0.5 ACU x $0.12 = $3.60
- Weekends: 48 hrs x 0.5 ACU x $0.12 = $2.88
- **Total: $64.08/week**

**Provisioned db.r6g.xlarge weekly cost:**
- Runs 24/7: 168 hrs x $0.48 = $80.64
- **Total: $80.64/week**

Serverless v2 saves about 20% ($16.56/week) because it scales down during idle periods. The savings increase as the ratio of idle-to-active time grows.

If the workload were sustained 24/7 at 8 ACU:
- Serverless: 168 hrs x 8 ACU x $0.12 = $161.28
- Provisioned: 168 hrs x $0.48 = $80.64
- Provisioned wins by 50% at sustained load.

</details>

---

## Exercise 3 - Auto-Scaling Policy Design

Your Aurora cluster serves a SaaS application. Read traffic is 5x higher during business hours (9 AM - 6 PM EST). You currently have 2 readers.

**Question 1:** Should you use auto-scaling or fixed readers? Why?

**Question 2:** If using auto-scaling with target CPU = 50%, what min and max replica count would you set?

**Question 3:** What cooldown period would you recommend? Why?

<details>
<summary>Click to reveal solution</summary>

**Q1:** Auto-scaling. The 5x traffic difference between business hours and off-hours means fixed readers would either be overprovisioned at night (wasting money) or underprovisioned during the day (poor performance). Auto-scaling adjusts to the actual demand.

**Q2:** Min=1, Max=5. You need at least 1 reader for HA (failover target). Maximum of 5 covers the 5x traffic multiplier. If 2 readers handle off-hours comfortably, 5 readers should handle peak (2 x 2.5 = 5).

**Q3:** Cooldown: 300-600 seconds (5-10 minutes). Reasons:
- Adding a reader takes 8-15 minutes, so a short cooldown would trigger multiple additions before the first one is ready
- A 5-minute cooldown prevents flapping when traffic hovers near the threshold
- Scale-in cooldown can be longer (600 seconds) since removing a reader is less urgent than adding one

</details>

---

## Exercise 4 - Interpret CloudWatch ACU Data

Here is CloudWatch output from a Serverless v2 cluster:

```
Time       | Average ACU | Maximum ACU
-----------+-------------+-------------
14:00      | 0.5         | 0.5
14:05      | 0.5         | 0.5
14:10      | 2.1         | 3.5
14:15      | 4.8         | 6.0
14:20      | 6.2         | 8.0
14:25      | 8.0         | 8.0     <-- avg = max
14:30      | 8.0         | 8.0     <-- same
14:35      | 8.0         | 8.0     <-- same
14:40      | 3.1         | 5.0
14:45      | 0.8         | 1.5
14:50      | 0.5         | 0.5
```

The cluster's MaxCapacity is set to 8 ACU.

**Question 1:** What happened between 14:10 and 14:40?

**Question 2:** At 14:25-14:35, the average equals the maximum (both 8.0). What does this mean?

**Question 3:** Is the MaxCapacity of 8 sufficient? What would you change?

<details>
<summary>Click to reveal solution</summary>

**Q1:** A load spike occurred. Traffic ramped up starting at 14:10, peaked at 14:25-14:35, and returned to baseline by 14:50. Total duration: about 30 minutes.

**Q2:** When average = maximum in a 5-minute window, the cluster was pinned at exactly 8.0 ACU the entire period with no variation. The cluster hit its configured ceiling (MaxCapacity=8) and could not scale further. Any additional demand during this window would result in queued queries, higher latency, or connection errors.

**Q3:** MaxCapacity of 8 is NOT sufficient - the cluster is hitting the ceiling. Increase to 12-16 to give headroom:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier devops-serverless-cluster \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=16 \
  --apply-immediately \
  --region us-east-1
```

Also set a CloudWatch alarm at 80% of MaxCapacity (6.4 ACU) to get early warning before hitting the ceiling again.

</details>

---

## Exercise 5 - Mixed Cluster Design

Design a mixed cluster for an e-commerce platform with these requirements:
- Predictable write load (steady 4000 TPS)
- Variable read load (1x at night, 10x during flash sales)
- Budget-conscious
- Failover under 30 seconds

**Question:** What combination of provisioned and Serverless v2 instances would you recommend? Include instance classes, ACU ranges, and failover tiers.

<details>
<summary>Click to reveal solution</summary>

Recommended mixed cluster:

```
Writer:  db.r6g.xlarge (provisioned)
  - 4 vCPU, 32 GB RAM
  - Handles steady 4000 TPS write load
  - Fixed cost: $0.48/hr
  - No scaling delay for writes

Reader-1: db.serverless (Serverless v2)
  - Min: 2 ACU, Max: 32 ACU
  - Failover tier: 0 (promoted first if writer fails)
  - Scales from 2 ACU at night to 32 ACU during flash sales

Reader-2: db.serverless (Serverless v2)
  - Min: 2 ACU, Max: 32 ACU
  - Failover tier: 1 (backup failover target)
  - Provides additional read capacity during sales
```

Why this works:
- Writer is provisioned: predictable cost, no scaling delay for writes, handles steady TPS
- Readers are Serverless v2: auto-scale for variable read traffic during sales
- Minimum 2 ACU on readers prevents cold-start latency
- Two readers with different failover tiers ensure HA
- During flash sales, both readers scale up independently based on their individual load

</details>

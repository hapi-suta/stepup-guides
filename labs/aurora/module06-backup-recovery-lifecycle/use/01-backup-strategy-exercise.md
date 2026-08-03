# USE 01 - Backup Strategy Design
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 30 minutes
**Format:** Scenario-based design exercise. No AWS console or CLI required.
**Goal:** Given a set of business requirements (RTO and RPO), design a complete backup strategy using Aurora PostgreSQL tools.

---

## Review: Key Terms

**RTO (Recovery Time Objective):** The maximum acceptable time to restore service after an outage. "We can be down for at most 2 hours."

**RPO (Recovery Point Objective):** The maximum acceptable amount of data loss, measured in time. "We can lose at most 15 minutes of transactions."

```
RTO and RPO on a Timeline
===========================

    Failure occurs
         |
         v
[Data Loss Window] <---  RPO controls this  --->  [Service Restored]
         |                                               |
         |<-----------  RTO controls this  ----------->|
         |                                               |
    (last backup)                               (application online)
```

---

## Scenario 1 - E-Commerce Order System

**Business context:**
- Handles 800 orders per hour during peak (9am-9pm)
- Revenue impact of downtime: $12,000/hour
- Aurora PostgreSQL cluster size: 150 GB
- Two regions: primary in us-east-1, DR target is us-west-2

**Requirements:**
- RTO: 30 minutes
- RPO: 5 minutes
- Budget: moderate - willing to pay for reliability

**Your task:** Design the backup strategy. Answer these questions:

1. Can you meet a 5-minute RPO with Aurora automated backups alone? Why or why not?
2. What backup retention period would you recommend?
3. Would you recommend adding a reader instance for this workload? Justify using the revenue impact number.
4. How often would you copy snapshots to us-west-2?
5. How often would you take manual snapshots, and when?
6. What is your PITR procedure if a developer accidentally deletes the `orders` table at 2pm on a Tuesday?

Write your answers before reading the discussion below.

---

<details>
<summary>Click to reveal discussion - Scenario 1</summary>

**Q1 - Can PITR meet 5-minute RPO?**

Yes. Aurora PITR can recover to any second within the retention window. The "Latest Restorable Time" lags real-time by only 2-5 minutes because backup data is continuously uploaded to S3. A 5-minute RPO is achievable with PITR.

The 30-minute RTO is achievable for a 150 GB Aurora cluster. PITR restore typically takes 10-20 minutes for clusters of this size.

**Q2 - Retention period recommendation**

14 days minimum. This gives you:
- 2 weeks of PITR capability
- Ability to catch slow corruption that was not noticed for days
- Margin for weekends and holidays when issues may go unnoticed

**Q3 - Reader instance recommendation**

At $12,000/hour revenue loss, a reader instance is strongly justified. A reader instance:
- Reduces maintenance downtime from 3-5 minutes to ~30 seconds (failover during patching)
- Provides a read endpoint for reporting queries
- Can be promoted to writer if the writer fails

The monthly cost of a db.t3.medium reader (~$50/month) is trivial compared to one hour of downtime ($12,000).

**Q4 - Cross-region copy frequency**

Weekly cross-region copies to us-west-2 at minimum. For an e-commerce system with $12K/hour revenue impact, consider daily copies. The cost is low compared to the risk.

**Q5 - Manual snapshot frequency**

Before every significant event:
- Before major version upgrades
- Before large data migrations or schema changes
- Before holiday peak seasons (keep for 60+ days)
- Weekly at minimum for a 150 GB production cluster

**Q6 - PITR procedure for accidental table drop at 2pm Tuesday**

1. Check PostgreSQL logs in CloudWatch for the exact DROP TABLE timestamp
2. Subtract 2-3 minutes from that timestamp - this is your target restore time
3. Check LatestRestorableTime - confirm it covers the pre-drop period
4. Initiate PITR to a new cluster (target time = 2 minutes before the drop)
5. Wait 10-20 minutes for the restore to complete
6. Add an instance to the restored cluster
7. Connect and verify the orders table exists with correct data
8. Export the orders table with `pg_dump -t orders`
9. Import into the production cluster
10. Delete the restored cluster

</details>

---

## Scenario 2 - Internal Analytics Database

**Business context:**
- Used by 50 data analysts, 8am-6pm weekdays only
- Revenue impact of downtime: minimal (analysts use cached dashboards)
- Aurora PostgreSQL cluster size: 500 GB
- Compliance requires 90-day data retention for audit purposes

**Requirements:**
- RTO: 4 hours
- RPO: 24 hours
- Budget: minimize cost

**Your task:** Answer these questions:

1. Do you need PITR? Or is daily snapshot restore enough for a 24-hour RPO?
2. What is the minimum backup strategy that satisfies the 90-day compliance requirement?
3. Do you recommend a reader instance for this workload?
4. What instance class would you use for a 500 GB analytics database?

Write your answers before reading the discussion.

---

<details>
<summary>Click to reveal discussion - Scenario 2</summary>

**Q1 - PITR vs daily snapshots**

A 24-hour RPO means you can lose up to 24 hours of data. A daily snapshot restore satisfies this requirement. PITR is not required - though it is automatically available with Aurora (backups cannot be disabled), so it costs nothing extra.

**Q2 - 90-day compliance strategy**

Automated backups max out at 35 days. They do NOT satisfy a 90-day requirement.

Solution: take a monthly manual snapshot. Keep 3-4 monthly snapshots to cover 90 days. Manual snapshots are retained indefinitely until you delete them.

Total cost for 500 GB: ~$10.50/month per snapshot x 3 snapshots = ~$31.50/month for compliance retention.

**Q3 - Reader instance**

No. With a 4-hour RTO and weekday-only usage, a reader instance is overkill. If the cluster restarts during patching, analysts wait 3-5 minutes. Acceptable for this workload.

However, for a 500 GB analytics database, a reader instance for offloading reporting queries is worth considering for performance reasons (not DR).

**Q4 - Instance class**

For 500 GB and 50 concurrent analysts running complex queries, `db.r6g.large` or `db.r6g.xlarge` is appropriate. Analytics workloads benefit from memory-optimized instances because large query result sets need RAM.

</details>

---

## Scenario 3 - Multi-Region SaaS Platform

**Business context:**
- Customer-facing platform, 24/7 operation
- 200 enterprise customers, each with SLA guarantees of 99.95% uptime
- Aurora PostgreSQL cluster size: 2 TB
- US customers on us-east-1, EU customers on eu-west-1

**Requirements:**
- RTO: 15 minutes
- RPO: 1 minute
- Compliance: EU data must not leave EU region

**Your task:** Design the full backup and recovery architecture.

Consider:
- What backup tools cover US customers?
- What backup tools cover EU customers?
- Can PITR alone meet a 1-minute RPO and 15-minute RTO for 2 TB?
- How does the EU data residency requirement change your snapshot strategy?
- What role would Aurora Global Database play?

This is an open design exercise. There is no single correct answer.

---

<details>
<summary>Click to reveal discussion - Scenario 3</summary>

**Key challenges:**
- 2 TB PITR restore may take 30-60 minutes, exceeding 15-minute RTO
- 1-minute RPO is achievable with Aurora's continuous backup, but RTO is the bottleneck
- EU data residency means snapshots from the EU cluster cannot be copied to US regions

**Recommended architecture:**
- US: Aurora cluster in us-east-1 + Aurora Global Database secondary in us-west-2
- EU: Separate Aurora cluster in eu-west-1 + Aurora Global Database secondary in eu-west-2
- Global Database provides ~1 second RPO and ~1 minute RTO for regional failover
- Standard automated backups (35-day retention) on all clusters
- Monthly manual snapshots for long-term compliance
- EU snapshots ONLY copied within EU regions (eu-west-1 to eu-west-2) for GDPR compliance
- US snapshots can be copied to any US region

</details>

---

## Key Decision Framework

Use this framework when designing backup strategies for real clients:

```
BACKUP STRATEGY DECISION TREE
================================

Step 1: What is the RPO?
  < 5 minutes   -> PITR required, verify latest restorable time
  5-60 minutes  -> PITR sufficient, standard retention
  > 60 minutes  -> Daily snapshot may be sufficient

Step 2: What is the RTO?
  < 5 minutes   -> Aurora Global Database needed
  5-30 minutes  -> PITR for small-medium clusters (< 500 GB)
  30-60 minutes -> PITR or snapshot restore for any size
  > 60 minutes  -> Snapshot restore for any size

Step 3: Compliance retention requirement?
  <= 35 days    -> Automated backups cover it
  > 35 days     -> Monthly manual snapshots (indefinite retention)
  Cross-border  -> Snapshots must stay in specific regions

Step 4: Cost tolerance?
  Low    -> 7-day retention, no manual snapshots, no cross-region
  Medium -> 14-day retention, weekly manual snapshots
  High   -> 35-day retention, daily snapshots, cross-region copies
```

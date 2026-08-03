# USE 01 - Backup Strategy Design
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 30 minutes
**Format:** Scenario-based design exercise. No AWS console or CLI required.
**Goal:** Given a set of business requirements (RTO and RPO), design a complete backup strategy using AWS RDS and Aurora tools.

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

## Scenario 1 - E-Commerce Checkout System

**Business context:**
- Handles 500 orders per hour during peak (9am-9pm)
- Revenue impact of downtime: $8,000/hour
- Database size: 120 GB

**Requirements:**
- RTO: 30 minutes
- RPO: 5 minutes
- Budget: cost-sensitive, prefer to avoid Multi-AZ if possible

**Your task:** Design the backup strategy. Answer these questions:

1. Can you meet a 5-minute RPO with automated backups alone? Why or why not?
2. What backup retention period would you recommend?
3. Would you recommend Multi-AZ for this workload? Justify your answer using the revenue impact number.
4. Would you set up cross-region snapshot copies? Why or why not?
5. How often would you take manual snapshots, and when?
6. What is your PITR procedure if a developer accidentally deletes the `orders` table at 2pm on a Tuesday?

Write your answers before reading the discussion below.

---

### Discussion - Scenario 1

**Q1 - Can PITR meet 5-minute RPO?**

Yes. PITR can recover to any second within the retention window. The "Latest Restorable Time" lags real-time by only 2-5 minutes because WAL is continuously uploaded to S3. A 5-minute RPO is achievable with PITR.

However, PITR recovery TIME (RTO) is 15-30 minutes for a 120 GB database. The 30-minute RTO is tight but achievable with PITR. You would NOT meet 30-minute RTO if you had to restore from a daily snapshot without WAL replay.

**Q2 - Retention period recommendation**

14 days minimum. This gives you:
- 2 weeks of PITR capability
- Ability to catch slow corruption that was not noticed for days
- Margin for weekends and holidays when issues may go unnoticed

**Q3 - Multi-AZ recommendation**

At $8,000/hour revenue loss, Multi-AZ is strongly justified. Multi-AZ eliminates most unplanned downtime from hardware failure and reduces OS patching downtime from 3-5 minutes to 30-60 seconds. Multi-AZ pricing approximately doubles the instance cost, but a single hour of downtime costs far more than a month of Multi-AZ premium.

**Q4 - Cross-region copies**

For an e-commerce system: yes, recommended. A region-level failure (rare but possible) would make your primary snapshot inaccessible. Weekly cross-region copies to a secondary region protect against this. The cost is low (one snapshot copy per week).

**Q5 - Manual snapshot frequency**

Before every significant event:
- Before major version upgrades
- Before large data migrations or schema changes
- Before the holiday peak season (keep this one 60+ days)
- Weekly at minimum for a 120 GB production database

**Q6 - PITR procedure for accidental table drop at 2pm Tuesday**

1. Identify the exact timestamp of the DROP TABLE (check application logs, PostgreSQL logs in CloudWatch)
2. Subtract 1-2 minutes from that timestamp - this is your target restore time
3. Check Latest Restorable Time - confirm it is after the drop happened
4. Initiate PITR to a new instance (target time = 1 minute before the drop)
5. Wait 15-25 minutes for the restore to complete
6. Connect to the restored instance and verify the orders table exists
7. Export the orders table with `pg_dump -t orders`
8. Import into the production database
9. Delete the restored instance
10. Confirm with the application team that orders are back

---

## Scenario 2 - Internal HR Database

**Business context:**
- Used by 200 employees, 8am-6pm weekdays only
- Revenue impact of downtime: minimal (operations continue manually)
- Database size: 8 GB
- Compliance requires 90-day data retention for audit purposes

**Requirements:**
- RTO: 4 hours
- RPO: 24 hours
- Budget: minimize cost

**Your task:** Answer these questions:

1. Do you need PITR? Or is daily snapshot restore enough for a 24-hour RPO?
2. What is the minimum backup retention period that satisfies the 90-day compliance requirement?
3. Do you recommend Multi-AZ for this workload?
4. What instance class would you use?

Write your answers before reading the discussion.

---

### Discussion - Scenario 2

**Q1 - PITR vs daily snapshots**

A 24-hour RPO means you can lose up to 24 hours of data. A daily snapshot restore satisfies this requirement. PITR is not required (though it is included with any retention period > 0, so it is available for free if you want it).

Keep automated backups enabled. Even if the RPO is 24 hours, having PITR available costs nothing extra and gives you more recovery flexibility.

**Q2 - Retention period for 90-day compliance**

Automated backups max out at 35 days. They do NOT satisfy a 90-day requirement.

Solution: take a monthly manual snapshot. Manual snapshots are retained indefinitely. Keep 3-4 monthly snapshots to cover 90 days of audit history.

**Q3 - Multi-AZ**

No. With a 4-hour RTO and weekday-only usage, Multi-AZ is overkill. If the instance goes down during business hours, a snapshot restore within 4 hours is acceptable. Single-AZ with a good backup strategy is sufficient.

**Q4 - Instance class**

For 8 GB and 200 concurrent users on a weekday-only schedule, `db.t3.small` or `db.t3.medium` is appropriate. Start small and scale up if needed. Cost optimization is the stated priority.

---

## Scenario 3 - SaaS Product Database

**Business context:**
- Customer-facing product, 24/7 operation
- Serves 50 enterprise customers, each with SLA guarantees of 99.9% uptime
- Database size: 2 TB Aurora PostgreSQL cluster
- Multiple regions: US customers on us-east-1, EU customers on eu-west-1

**Requirements:**
- RTO: 15 minutes
- RPO: 1 minute
- Compliance: EU data must not leave EU region

**Your task:** Design the full backup and recovery architecture.

Consider:
- What backup tools cover US customers?
- What backup tools cover EU customers?
- Can one restore approach meet a 1-minute RPO and 15-minute RTO for 2 TB?
- How does the EU data residency requirement change your snapshot strategy?
- What role would Aurora Global Database play (not covered in this tier, but think about it)?

This is an open design exercise. There is no single correct answer. Be prepared to discuss your design choices.

---

## Reflection Questions

After completing the three scenarios, answer these for yourself:

1. At what RPO threshold does PITR become necessary vs. daily snapshot restore being sufficient?

2. At what database size does your restore time exceed a typical RTO requirement, and what tools exist to help?

3. Why would a company use both automated backups AND manual snapshots rather than just one?

4. What is the difference between "backup strategy" and "disaster recovery strategy"? How does DR extend beyond just backups?

---

## Key Decision Framework

Use this framework when designing backup strategies for real clients:

```
BACKUP STRATEGY DECISION TREE
================================

Step 1: What is the RPO?
  < 5 minutes   -> PITR required, continuous WAL upload critical
  5-60 minutes  -> PITR sufficient, check latest restorable time
  > 60 minutes  -> Daily snapshot may be sufficient

Step 2: What is the RTO?
  < 15 minutes  -> Consider Multi-AZ + read replica for failover
                   Snapshot restore unlikely to meet this for large DBs
  15-60 minutes -> PITR or snapshot restore for small-medium DBs
  > 60 minutes  -> Snapshot restore for any size DB

Step 3: What is the database size?
  < 100 GB      -> PITR restore typically takes 10-20 minutes
  100 GB - 1 TB -> PITR restore typically takes 20-60 minutes
  > 1 TB        -> Consider Aurora Global Database for near-instant DR failover

Step 4: Is there a compliance retention requirement?
  <= 35 days    -> Automated backups cover it
  > 35 days     -> Manual snapshots required (indefinite retention)
  Cross-border  -> Snapshots must stay in specific regions

Step 5: What is the cost tolerance?
  Low           -> Single-AZ, 7-day retention, minimal manual snapshots
  Medium        -> Multi-AZ, 14-day retention, weekly manual snapshots
  High          -> Multi-AZ, 35-day retention, daily manual snapshots, cross-region copies
```

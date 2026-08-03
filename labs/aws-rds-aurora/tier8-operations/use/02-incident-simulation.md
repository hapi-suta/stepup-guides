# USE Exercise 02: Incident Response Simulation

**Objective:** Work through three realistic incident response scenarios using the runbooks from Build Guide 04. Practice diagnosis under time pressure and evaluate whether your runbooks would work in a real incident.
**Time:** 45-60 minutes
**Level:** Expert
**infra_required:** Partial - Scenarios 1 and 3 require a running RDS instance. Scenario 2 can be completed with console access only.
**Prerequisites:** Build Guide 04 completed. Runbooks written and available.

---

## Instructions

Each scenario is a simulated incident. You receive the information an on-call engineer would see at 2 AM. Work through it as if it is real.

- Set a timer for each scenario.
- Use your runbook from Build Guide 04 as your only reference. Do not google freely.
- Document every command you run and what the output told you.
- After each scenario, complete the debrief questions.

---

## Scenario 1: The Connection Storm

**Time limit:** 15 minutes

**What you receive at 2:47 AM:**

PagerDuty fires:
```
CRITICAL: RDS DatabaseConnections > 450
Instance: prod-payments-db
Region: [REGION]
Current connections: 463
max_connections (from parameter group): 500
Duration: Firing for 4 minutes
```

Simultaneously, the on-call application engineer messages you: "Payments API is returning 500s. About 40% of requests are failing. Error in logs: FATAL: sorry, too many clients already"

**Your starting information:**
- This instance handles payment processing. Every minute of downtime is approximately $8,000 in failed transactions.
- A deployment was made 23 minutes ago (at 2:24 AM).
- The previous deployment was 3 days ago with no issues.
- The application uses a custom connection pool, not PgBouncer.

**What you need to do:**

Step 1 (5 minutes): Using the runbook for "Connection Storm," execute the diagnostic phase. Document what you find. Specifically:

```sql
-- Run these (or equivalents from your runbook):
-- 1. Connection count by state
-- 2. Connection count by application_name
-- 3. Long-running idle-in-transaction sessions
```

Step 2 (5 minutes): Based on your diagnosis, execute the appropriate remediation. Document each command.

Step 3 (5 minutes): Verify the system has recovered. Write one sentence each on:
- What caused the incident (your hypothesis based on evidence)
- What immediate action resolved it
- What systemic change would prevent recurrence

**Debrief Questions:**

1. Your runbook says "Terminate idle-in-transaction connections older than 5 minutes." You found 280 connections in `idle in transaction`, but some are only 45 seconds old and may be legitimate long-running transactions. How do you decide which to terminate?

2. Increasing `max_connections` requires a reboot. You are on call for a payment processing system. How do you communicate the downtime decision to the business?

3. After the incident, the engineering team says "just set max_connections to 5000 and we'll never have this problem again." What is your response?

---

## Scenario 2: Storage Exhaustion - The Slow Creep

**Time limit:** 15 minutes

**What you receive at 4:15 AM:**

```
WARNING: RDS FreeStorageSpace = 18% (threshold: 20%)
Instance: prod-analytics-db
Current allocation: 2000 GB
Free: 360 GB
Rate of change: -15 GB/day (last 7 days average)
```

This alert is not PagerDuty - it fired to your on-call Slack channel. No user impact yet.

**Your starting information:**
- This instance stores analytics data. ETL jobs run every 4 hours.
- The ETL job schedule: 00:00, 04:00, 08:00, 12:00, 16:00, 20:00 UTC.
- The next ETL job runs in 45 minutes (04:00 UTC).
- Storage autoscaling is not enabled (you did not configure this environment).
- You have 45 minutes before the situation could become critical if the ETL job runs normally.

**What you need to do:**

Step 1 (3 minutes): Determine the urgency. At -15 GB/day and 360 GB free, how many days until the database runs out of storage? Does this require immediate action tonight, or can it wait until business hours?

Step 2 (5 minutes): Identify the root cause using diagnostic queries from your runbook. Check:
- Which tables are largest
- Whether any replication slots are accumulating WAL
- Whether there are long-running transactions holding XIDs

Step 3 (5 minutes): Decide on and execute remediation. Options:
- Increase allocated storage now (online, no downtime)
- Enable storage autoscaling
- Drop or archive data
- Drop any inactive replication slots

Step 4 (2 minutes): Write the incident update you would post to your Slack incident channel.

**Debrief Questions:**

1. You can increase RDS storage immediately with no downtime. Why would you still want to understand the root cause before increasing storage?

2. The ETL job that runs at 04:00 does a large INSERT followed by a DELETE of old data. Explain how this could lead to storage growing even though the net data change is small.

3. You decide to enable storage autoscaling as a permanent fix. What maximum storage limit do you set, and why does the maximum matter?

---

## Scenario 3: The Wraparound Near-Miss

**Time limit:** 20 minutes

**What you receive:**

Your custom wraparound monitoring Lambda fires to PagerDuty at 11:30 AM:

```
CRITICAL: Transaction ID Wraparound Risk
Database: app_production
Instance: prod-app-db
age(datfrozenxid): 1,623,000,000
Transactions remaining: 377,000,000
Estimated days until shutdown (at current TX rate): 8 days
```

This is not an emergency - it is a warning. But 8 days is not a comfortable margin, and autovacuum has clearly not been keeping up.

**Your starting information:**
- This is a production OLTP database processing approximately 2,000 transactions per minute.
- At that rate, 377 million transactions = approximately 130 days of transactions (not 8). The discrepancy means the Lambda's rate estimate is wrong. Recalculate.
- The instance is a `db.r6g.2xlarge`. It currently runs autovacuum with default settings.
- There is a 5,000 GB table (`events`) that has not been vacuumed in 6 months.
- The next available maintenance window is Saturday night (4 days away).

**What you need to do:**

Step 1 (5 minutes): Recalculate the actual risk. At 2,000 TPS (transactions per second), how long until wraparound? Show the math.

Step 2 (5 minutes): Identify which tables need VACUUM FREEZE most urgently:

```sql
SELECT schemaname, relname,
       greatest(age(relfrozenxid), age(relminmxid)) AS table_xid_age,
       pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
WHERE relkind = 'r'
AND greatest(age(relfrozenxid), age(relminmxid)) > 500000000
ORDER BY table_xid_age DESC
LIMIT 10;
```

Step 3 (5 minutes): Design your remediation plan. Address:
- Should you run VACUUM FREEZE manually now or wait for the maintenance window?
- How do you run VACUUM FREEZE on the 5,000 GB `events` table without taking down the database?
- What autovacuum parameter changes do you make to prevent recurrence?

Step 4 (5 minutes): Write a 5-bullet executive summary of this incident for your manager.

**Debrief Questions:**

1. VACUUM FREEZE on a 5,000 GB table will take hours and generate significant I/O. The application team says "this will destroy our query performance during business hours." How do you balance the risk of wraparound shutdown against I/O impact?

2. Your autovacuum parameter change (boosting `autovacuum_vacuum_cost_delay` from 20ms to 2ms) will be applied immediately without a restart. Explain what that parameter controls and what the trade-off is of setting it very low.

3. After this incident, you want to build monitoring that catches wraparound risk earlier. What threshold would you set for:
   - A WARNING alert
   - A CRITICAL/page alert

   Explain your reasoning.

4. You discover the `events` table had autovacuum disabled (`autovacuum_enabled = false`) at the table level. Who would have set this and why might they have done it? What do you do now?

---

## Overall Debrief

After completing all three scenarios, answer:

1. Which scenario was hardest to diagnose? What made it harder?

2. For each scenario, was your runbook (from Build Guide 04) complete enough to guide you through the incident? What gaps did you find?

3. What monitoring would have caught each of these incidents earlier? For each, specify the metric, threshold, and how much earlier you would have received an alert.

4. Write a one-paragraph "post-mortem action item" for each scenario - the systemic change you would make to prevent recurrence.

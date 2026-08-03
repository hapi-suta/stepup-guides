# USE 03: Incident Response Exercise

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 30-40 minutes

---

## Context

You are the on-call DBA for a fintech company. It is 2:15 AM on a Tuesday. Your phone just woke you up with a PagerDuty alert. The Aurora PostgreSQL cluster `payments-cluster` is showing critical errors. You need to follow the incident management process from detection through resolution and post-incident review.

---

## Part 1: Incident Detection and Triage

<details>
<summary>Task 1.1: You receive the following alert. Determine the incident severity and your first three actions.</summary>

**Alert Details:**

```
ALARM: payments-cluster-write-latency
State: ALARM
Metric: WriteLatency
Threshold: > 500ms for 3 consecutive periods (5-minute periods)
Current Value: 2,450ms (average over last 5 minutes)
Time: 2026-06-10 02:15:00 UTC
Cluster: payments-cluster (Aurora PostgreSQL 16.4)
Region: us-east-1
```

Additional context from the monitoring dashboard:
- DatabaseConnections: 450 (normal baseline: 200)
- CPUUtilization: 92% (normal baseline: 35%)
- AuroraReplicaLag: 45,000ms (normal: < 100ms)
- Active transactions: 380 (normal: 50-80)

Questions to answer:
1. What severity level is this incident? Justify your choice.
2. What are your first three actions in the first 5 minutes?
3. Who do you notify and how?

**Example answer:**

1. **Severity: SEV1 (Critical)**
   - Write latency is 5x the threshold (2,450ms vs 500ms)
   - CPU is at 92% - near saturation
   - Connection count has more than doubled (450 vs 200 baseline)
   - Replication lag at 45 seconds - readers are severely behind
   - This is a payments system - transaction failures mean lost revenue
   - Customer-visible impact is likely (slow or failing transactions)

2. **First three actions:**
   - Acknowledge the alert in PagerDuty (SLA: < 5 minutes)
   - Open the CloudWatch dashboard and confirm the metrics match the alert
   - Connect to the database and run initial diagnostics:
     ```sql
     -- What is causing the CPU spike?
     SELECT pid, usename, state, wait_event_type, wait_event,
            left(query, 100), extract(epoch FROM now() - query_start) AS age_s
     FROM pg_stat_activity
     WHERE state = 'active'
     ORDER BY query_start ASC
     LIMIT 20;
     ```

3. **Notifications:**
   - Declare SEV1: "This is a SEV1. I am the Incident Commander."
   - Notify: engineering lead, secondary on-call DBA
   - Post to #incidents Slack channel with initial status update
   - Communication template:
     ```
     INCIDENT: payments-cluster write latency critical
     SEVERITY: SEV1
     STATUS: Investigating
     IMPACT: Payment processing likely degraded - high latency
     CURRENT ACTIONS: Diagnosing root cause - CPU and connections elevated
     NEXT UPDATE: 02:30 UTC
     IC: [Your name]
     ```

</details>

<details>
<summary>Task 1.2: Your initial diagnosis reveals the following. What is the root cause, and what is your immediate mitigation action?</summary>

**Diagnosis results:**

```sql
-- pg_stat_activity shows:
 pid  | usename     | state                | wait_event | query                                    | age_s
------+-------------+----------------------+------------+------------------------------------------+-------
 1234 | batch_user  | active               | LWLock     | UPDATE accounts SET balance = balance ... | 1845
 1235 | batch_user  | active               | LWLock     | UPDATE accounts SET balance = balance ... | 1844
 1236 | batch_user  | active               | LWLock     | UPDATE accounts SET balance = balance ... | 1843
 ... (350 more rows from batch_user, all UPDATE statements)
 5678 | app_user    | idle in transaction  | Client     | COMMIT                                   | 892
 5679 | app_user    | active               | Lock       | INSERT INTO payments ...                 | 45
```

```sql
-- Lock tree shows:
 blocked_pid | blocking_pid | blocked_query              | blocking_query
-------------+--------------+----------------------------+------------------------------------------
 5679        | 1234         | INSERT INTO payments ...   | UPDATE accounts SET balance = balance ...
 5680        | 1234         | INSERT INTO payments ...   | UPDATE accounts SET balance = balance ...
```

```sql
-- pg_locks shows 350+ ExclusiveLock on the accounts table
```

Questions:
1. What is the root cause?
2. What is your immediate mitigation action?
3. What is the permanent fix to prevent recurrence?

**Example answer:**

1. **Root cause:** An unscheduled batch job (`batch_user`) is running 350+ concurrent UPDATE statements against the `accounts` table. These updates hold ExclusiveLocks that block the application's payment INSERT statements. The batch job has been running for 30+ minutes (1845 seconds), causing lock contention, CPU saturation, and replication lag.

2. **Immediate mitigation:**
   - Terminate the batch job sessions to release the locks:
     ```sql
     SELECT pg_terminate_backend(pid)
     FROM pg_stat_activity
     WHERE usename = 'batch_user'
       AND state = 'active'
       AND query LIKE 'UPDATE accounts%';
     ```
   - Monitor latency and connections for recovery (should drop within 1-2 minutes)
   - Post status update: "Root cause identified - runaway batch job terminated. Monitoring recovery."

3. **Permanent fix:**
   - Add `statement_timeout` for the `batch_user` role: `ALTER ROLE batch_user SET statement_timeout = '300000';` (5 minutes)
   - Implement a job scheduler that limits batch concurrency to 10 parallel sessions
   - Schedule batch jobs during off-peak hours (not during payment processing)
   - Add a CloudWatch alarm for `batch_user` connection count exceeding 20

</details>

---

## Part 2: Incident Timeline

<details>
<summary>Task 2.1: Construct a complete incident timeline from the information provided. Include MTTD and MTTR calculations.</summary>

**Additional timeline information:**

- 01:45 UTC: Batch job started (scheduled by cron on batch server)
- 01:50 UTC: Connections begin climbing
- 02:00 UTC: CPU crosses 80%
- 02:10 UTC: Write latency crosses 500ms threshold
- 02:15 UTC: CloudWatch alarm fires, PagerDuty pages on-call
- 02:17 UTC: On-call DBA acknowledges
- 02:20 UTC: Initial diagnosis begins
- 02:25 UTC: Root cause identified (batch job lock contention)
- 02:27 UTC: Batch sessions terminated
- 02:29 UTC: Write latency returns below 100ms
- 02:30 UTC: Connections return to baseline
- 02:32 UTC: Replication lag returns to normal
- 02:35 UTC: Incident declared resolved

**Example answer:**

| Time (UTC) | Event |
|-----------|-------|
| 01:45 | Batch job starts - 350 concurrent UPDATE sessions |
| 01:50 | Connections begin climbing (200 to 450 over 20 minutes) |
| 02:00 | CPU crosses 80% |
| 02:10 | Write latency crosses 500ms alarm threshold |
| 02:15 | CloudWatch alarm fires - PagerDuty alert sent |
| 02:17 | On-call DBA acknowledges (2 minutes response time) |
| 02:20 | Diagnosis begins - query pg_stat_activity |
| 02:25 | Root cause identified: batch_user lock contention |
| 02:27 | Batch sessions terminated via pg_terminate_backend |
| 02:29 | Write latency returns to normal |
| 02:32 | Replication lag returns to normal |
| 02:35 | Incident declared resolved |

**MTTD (Mean Time to Detect):**
- Incident started: 01:45 (batch job began causing issues)
- First alert: 02:15
- MTTD = 30 minutes

**MTTR (Mean Time to Recover):**
- Detection: 02:15
- Resolution: 02:35
- MTTR = 20 minutes

**Total incident duration:** 50 minutes (01:45 to 02:35)
**User-visible impact duration:** ~25 minutes (02:10 to 02:35, when latency exceeded SLO)

</details>

---

## Part 3: Post-Incident Review

<details>
<summary>Task 3.1: Write a blameless post-incident review (PIR) for this incident. Follow the PIR template from the concepts material.</summary>

Your PIR must include:
- Summary (2-3 sentences)
- Timeline
- Impact assessment (users affected, error budget consumed)
- Root cause (systemic, not individual blame)
- Contributing factors
- What went well
- What went wrong
- Action items with owners and deadlines

**Example answer:**

```markdown
# Post-Incident Review: Payments Cluster Write Latency Spike

Date: 2026-06-10
Duration: 01:45 to 02:35 UTC (50 minutes total, 25 minutes user-visible)
Severity: SEV1
IC: [DBA Name]

## Summary
An unscheduled batch job ran 350 concurrent UPDATE sessions against the
accounts table, causing lock contention that blocked payment transactions.
Write latency spiked to 2,450ms (SLO: < 500ms) and CPU reached 92%.
The batch sessions were terminated to restore service.

## Timeline
[See Part 2 timeline above]

## Impact
- Users affected: All payment processing users (~2,000 concurrent)
- Duration of impact: 25 minutes (02:10 to 02:35)
- Transactions delayed: estimated 15,000-20,000
- Transactions failed: estimated 200-500 (timeouts)
- Data loss: None
- Error budget consumed: 25 minutes of 38.88 minute quarterly budget (64%)
- Budget status changed from HEALTHY to WARNING

## Root Cause
The batch job execution system has no concurrency limits. A cron job
on the batch server spawned 350 parallel database sessions, each running
long-duration UPDATE statements with ExclusiveLocks on the accounts
table. The system allowed this because:
1. No connection limit per user role
2. No statement_timeout for batch_user
3. No scheduling policy to prevent batch jobs during peak hours
4. No alerting on batch_user connection count

## Contributing Factors
1. The batch job was added 3 months ago without DBA review
2. No connection pooler limits per-user connections
3. The CloudWatch alarm threshold (500ms for 3 periods) delayed
   detection by 15 minutes after symptoms began
4. No runbook existed for "batch job causing lock contention"

## What Went Well
1. On-call DBA acknowledged within 2 minutes
2. Root cause identified within 8 minutes of starting diagnosis
3. Mitigation (terminate batch sessions) was effective immediately
4. No data loss or corruption

## What Went Wrong
1. MTTD was 30 minutes - the batch job ran for 30 minutes before
   alerting detected the impact
2. No proactive monitoring for unusual connection patterns
3. Batch jobs can run without any database-side guardrails
4. 64% of quarterly error budget consumed in one incident

## Action Items
| ID | Action | Owner | Priority | Due |
|----|--------|-------|----------|-----|
| 1 | Set statement_timeout for batch_user (5 min) | DBA Team | P1 | 2026-06-12 |
| 2 | Set connection limit for batch_user (max 20) | DBA Team | P1 | 2026-06-12 |
| 3 | Add CloudWatch alarm for batch_user connections > 20 | DBA Team | P1 | 2026-06-14 |
| 4 | Implement batch job scheduling policy (off-peak only) | Eng Lead | P2 | 2026-06-20 |
| 5 | Create runbook for lock contention incidents | DBA Team | P2 | 2026-06-20 |
| 6 | Reduce CloudWatch alarm evaluation to 1 period (5 min) | DBA Team | P2 | 2026-06-14 |
| 7 | Require DBA review for any new batch job database access | Eng Mgr | P3 | 2026-06-30 |
```

</details>

---

## Part 4: Improving Detection

<details>
<summary>Task 4.1: The MTTD for this incident was 30 minutes. Propose three specific changes to reduce MTTD to under 5 minutes for similar incidents.</summary>

For each change, specify:
- What you would monitor
- The threshold and evaluation period
- Expected MTTD improvement

**Example answer:**

1. **Connection rate-of-change alarm:**
   - Monitor: DatabaseConnections metric, rate of change
   - Alarm: When connections increase by more than 50% in a 5-minute window
   - Threshold: `(current - baseline) / baseline > 0.5` over 1 evaluation period
   - Expected MTTD: ~5 minutes from connection spike start (vs 30 minutes now)

2. **Per-user connection monitoring Lambda:**
   - Deploy Lambda that runs every 2 minutes
   - Query: `SELECT usename, count(*) FROM pg_stat_activity GROUP BY usename`
   - Alert: When any single user exceeds 50 connections
   - Expected MTTD: ~2 minutes

3. **Lock wait monitoring:**
   - Deploy Lambda that runs every 2 minutes
   - Query: `SELECT count(*) FROM pg_stat_activity WHERE wait_event_type = 'Lock'`
   - Alert: When lock-waiting sessions exceed 10
   - Expected MTTD: ~2 minutes from lock contention start

</details>

---

## Deliverables

By the end of this exercise, you should have:

1. Severity classification with justification
2. First-response actions and notification plan
3. Root cause analysis
4. Complete incident timeline with MTTD/MTTR
5. Blameless post-incident review with action items
6. Detection improvement proposals

---

## Reflection Questions

1. Why is it important to terminate the batch sessions rather than wait for them to complete?
2. How would the response differ if this were a SEV3 instead of SEV1?
3. What is the difference between "root cause" and "contributing factors" in a PIR?
4. How does consuming 64% of the error budget in one incident change the team's behavior for the rest of the quarter?

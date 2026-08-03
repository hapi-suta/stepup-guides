# USE 04: Runbook Automation Exercise

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 30-40 minutes

---

## Context

Your team has been running manual runbooks for 6 months. The on-call DBA averages 8 pages per week, and MTTR for connection-related incidents is 25 minutes. Leadership wants to reduce pages to under 5 per week and MTTR to under 10 minutes. You need to design an automation strategy that converts your most frequently used runbooks into automated responses.

---

## Part 1: Toil Assessment

<details>
<summary>Task 1.1: Given the following on-call log from the past month, calculate the toil metrics and identify the top automation candidates.</summary>

**On-Call Log (Last 30 Days):**

| Incident Type | Count | Avg Response Time | Avg Resolution Time | Manual Steps |
|--------------|-------|-------------------|--------------------|--------------|
| Idle-in-transaction timeout | 12 | 3 min | 15 min | Query pg_stat_activity, identify session, terminate, verify |
| Disk space warning (85%) | 8 | 5 min | 20 min | Check table sizes, check bloat, check replication slots, VACUUM if needed |
| Replication lag spike | 6 | 4 min | 18 min | Check long transactions, check write IOPS, verify reader status |
| Connection count high | 5 | 3 min | 12 min | Check connection sources, identify idle sessions, terminate, verify |
| Slow query alert | 4 | 5 min | 25 min | Identify query, check explain plan, check for missing index |
| Failover event | 2 | 2 min | 5 min | Verify failover complete, check application reconnect |
| Parameter drift detected | 1 | 10 min | 30 min | Compare parameters across environments, fix drift |
| **Total** | **38** | | | |

Calculate:
1. Total pages per week
2. Total manual hours per month on incident response
3. The toil score (time x frequency) for each incident type
4. The top 3 automation candidates

**Example answer:**

1. **Pages per week:** 38 / 4 weeks = 9.5 pages/week (target: < 5)

2. **Total manual hours per month:**

| Incident Type | Count | Avg Time | Total Hours |
|--------------|-------|----------|-------------|
| Idle-in-transaction | 12 | 15 min | 3.0 hrs |
| Disk space warning | 8 | 20 min | 2.7 hrs |
| Replication lag | 6 | 18 min | 1.8 hrs |
| Connection count | 5 | 12 min | 1.0 hrs |
| Slow query | 4 | 25 min | 1.7 hrs |
| Failover event | 2 | 5 min | 0.2 hrs |
| Parameter drift | 1 | 30 min | 0.5 hrs |
| **Total** | **38** | | **10.9 hrs** |

3. **Toil score (monthly hours):**
   - Idle-in-transaction: 3.0 hrs (highest)
   - Disk space warning: 2.7 hrs
   - Replication lag: 1.8 hrs

4. **Top 3 automation candidates:**
   1. Idle-in-transaction (12 incidents/month, simple automation: auto-terminate sessions > 5 minutes)
   2. Disk space warning (8 incidents/month, automated diagnosis + VACUUM recommendation)
   3. Connection count high (5 incidents/month, auto-terminate idle sessions + report)

</details>

---

## Part 2: Automation Design

<details>
<summary>Task 2.1: Design the Lambda function for automating the idle-in-transaction runbook. Describe the inputs, logic, outputs, and safety guardrails.</summary>

Your design should include:
- Trigger mechanism (what fires the automation)
- Input data (what the function receives)
- Decision logic (when to auto-remediate vs. alert only)
- Safety guardrails (what the function should NOT do)
- Output (what the DBA receives)

**Example answer:**

```
RUNBOOK: Auto-Terminate Idle-in-Transaction Sessions

TRIGGER:
- EventBridge rule matching CloudWatch alarm:
  "idle-in-transaction-count > 5 for 2 consecutive 1-minute periods"

INPUT:
- Alarm event (cluster name, current metric value)
- Database credentials from Secrets Manager

DECISION LOGIC:
1. Connect to database via writer endpoint
2. Query pg_stat_activity for idle-in-transaction sessions
3. For each session:
   a. If idle > 5 minutes AND user is NOT in protected list -> TERMINATE
   b. If idle > 5 minutes AND user IS in protected list -> ALERT ONLY
   c. If idle < 5 minutes -> SKIP (may be legitimate transaction)

PROTECTED USERS (never auto-terminate):
- postgres (superuser)
- replication_user
- migration_user (may run long DDL)

SAFETY GUARDRAILS:
- Maximum 20 sessions terminated per invocation
  (if > 20, alert DBA - likely a systemic issue)
- Never terminate sessions on reader instances
- Log every termination with PID, user, database, query, and idle duration
- If termination fails, alert DBA immediately
- Cool-down period: do not run more than once per 5 minutes

OUTPUT (SNS notification):
- Number of sessions found
- Number of sessions terminated
- Number of sessions skipped (protected users)
- Full session details for each terminated session
- Recommendation if pattern is recurring
```

</details>

<details>
<summary>Task 2.2: Design the EventBridge rule and CloudWatch alarm that triggers the idle-in-transaction automation. Write the AWS CLI commands.</summary>

**Example answer:**

```bash
# Step 1: Create a custom CloudWatch metric via Lambda
# (The health check Lambda from BUILD 03 already publishes
#  ConnectionUtilization. Add idle-in-transaction count.)

# Step 2: Create CloudWatch alarm on the custom metric
aws cloudwatch put-metric-alarm \
    --alarm-name "payments-cluster-idle-in-txn" \
    --alarm-description "More than 5 idle-in-transaction sessions detected" \
    --namespace DBA/Aurora \
    --metric-name IdleInTransactionCount \
    --dimensions Name=ClusterIdentifier,Value=payments-cluster \
    --statistic Maximum \
    --period 60 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --evaluation-periods 2 \
    --treat-missing-data notBreaching

# Step 3: Create EventBridge rule
aws events put-rule \
    --name payments-idle-in-txn-remediation \
    --event-pattern '{
        "source": ["aws.cloudwatch"],
        "detail-type": ["CloudWatch Alarm State Change"],
        "detail": {
            "alarmName": ["payments-cluster-idle-in-txn"],
            "state": {"value": ["ALARM"]}
        }
    }' \
    --state ENABLED

# Step 4: Add Lambda as target
aws events put-targets \
    --rule payments-idle-in-txn-remediation \
    --targets "Id=1,Arn=arn:aws:lambda:us-east-1:123456789012:function:payments-idle-in-txn-remediation"
```

</details>

---

## Part 3: Measuring Automation Impact

<details>
<summary>Task 3.1: After deploying the top 3 automations, project the new on-call metrics. Will you meet the targets of < 5 pages/week and < 10 minutes MTTR?</summary>

Assume:
- Idle-in-transaction automation resolves 10 of 12 monthly incidents automatically (2 still need human review due to protected users)
- Connection count automation resolves 4 of 5 monthly incidents automatically
- Disk space automation provides instant diagnosis but still needs human action for VACUUM decisions

**Example answer:**

**Before Automation:**
- Pages per week: 9.5
- Monthly manual hours: 10.9

**After Automation:**

| Incident Type | Before | Auto-Resolved | Remaining Pages | New Avg MTTR |
|--------------|--------|--------------|-----------------|-------------|
| Idle-in-transaction | 12 | 10 | 2 | 3 min (auto) / 15 min (manual) |
| Disk space warning | 8 | 0 (diagnosis only) | 8 | 8 min (auto-diagnosis saves 12 min) |
| Replication lag | 6 | 0 (alert only) | 6 | 18 min (no change yet) |
| Connection count | 5 | 4 | 1 | 2 min (auto) / 12 min (manual) |
| Slow query | 4 | 0 | 4 | 25 min |
| Failover | 2 | 0 | 2 | 5 min |
| Parameter drift | 1 | 0 | 1 | 30 min |
| **Total** | **38** | **14** | **24** | |

**New pages per week:** 24 / 4 = 6.0 pages/week
**Target: < 5 pages/week - NOT YET MET**

To reach the target, Phase 2 automation should address:
- Disk space: Add automated VACUUM for known-safe tables -> eliminate 5 of 8 pages
- Replication lag: Add auto-diagnosis + long transaction alerting -> reduce MTTR
- Slow query: Add automated EXPLAIN analysis -> reduce MTTR

**Phase 2 projected pages/week:** (24 - 5) / 4 = 4.75 pages/week - TARGET MET

</details>

---

## Part 4: Runbook Documentation

<details>
<summary>Task 4.1: Write a runbook for the disk space warning incident. Include both the manual steps and the automated diagnosis that the Lambda provides.</summary>

Follow the runbook template from the concepts material.

**Example answer:**

```markdown
# Runbook: Disk Space Warning (85% Threshold)

Severity: High
Last Updated: 2026-06-09
Owner: DBA Team

## Symptoms
- CloudWatch alarm: FreeStorageSpace < 15% of allocated
- Alert: "devops-lab-cluster-storage-warning" in ALARM state
- Automated diagnosis Lambda has already run and sent report to SNS

## Impact
- If storage reaches 100%, the database becomes read-only
- Write transactions fail with "could not extend file" errors
- Aurora auto-scales storage, but inactive replication slots
  and bloat can consume storage faster than scaling

## Immediate Actions (first 5 minutes)
1. Check the automated diagnosis report (sent to #dba-alerts Slack)
2. The report includes: largest tables, bloat estimates, replication slots
3. If inactive replication slots are identified, proceed to Remediation

## Diagnosis (if automated report is insufficient)
Connect to the writer endpoint:

    SELECT schemaname || '.' || tablename AS table_name,
           pg_size_pretty(pg_total_relation_size(
               schemaname || '.' || tablename)) AS total_size
    FROM pg_tables
    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
    ORDER BY pg_total_relation_size(
        schemaname || '.' || tablename) DESC
    LIMIT 10;

Check for inactive replication slots:

    SELECT slot_name, active,
           pg_size_pretty(pg_wal_lsn_diff(
               pg_current_wal_lsn(), restart_lsn)) AS retained_wal
    FROM pg_replication_slots;

## Remediation

### If inactive replication slots are found:
    SELECT pg_drop_replication_slot('slot_name');

### If table bloat is high:
    VACUUM (VERBOSE) schema.table_name;
    -- For severe bloat (> 50% dead tuples):
    VACUUM FULL schema.table_name;
    -- WARNING: VACUUM FULL locks the table exclusively

### If old data can be archived:
    -- Work with application team to identify purgeable data
    -- DELETE in batches of 10,000 rows to avoid long locks

## Verification
    -- Check storage is recovering:
    SELECT pg_size_pretty(pg_database_size(current_database()));

    -- Check CloudWatch: FreeStorageSpace should be increasing
    -- Alarm should return to OK state within 15-30 minutes

## Prevention
- Monitor replication slots weekly
- Schedule VACUUM analysis monthly
- Implement data retention policies for large tables
- Set CloudWatch alarm at 75% (warning) and 85% (critical)

## Escalation
- If storage exceeds 95%: escalate to senior DBA immediately
- If VACUUM FULL is needed on a large table: schedule during
  maintenance window with engineering lead approval
```

</details>

---

## Deliverables

By the end of this exercise, you should have:

1. Toil assessment with metrics and automation candidates
2. Lambda automation design with safety guardrails
3. EventBridge and CloudWatch alarm CLI commands
4. Projected impact analysis (before vs after automation)
5. Hybrid runbook (manual + automated diagnosis)

---

## Reflection Questions

1. Why should automated remediation have a "protected users" list?
2. What is the risk of setting the auto-terminate threshold too aggressively (e.g., 1 minute instead of 5)?
3. How do you measure whether automation is working correctly over time?
4. When should a runbook remain manual rather than being automated?

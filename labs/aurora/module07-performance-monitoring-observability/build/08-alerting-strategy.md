# Build 08 - Alerting Strategy

**Time:** 35 minutes
**Goal:** Design and implement a tiered alerting strategy that pages for real problems and avoids alert fatigue.
**Prerequisites:** Build 01 complete (CloudWatch alarms set). Build 07 optional (Prometheus + Grafana). `$CLUSTER_ID`, `$WRITER_INSTANCE`, `$REGION`, `$SNS_TOPIC_ARN` set.

---

## Step 1 - Understand Alert Tiers

Not every alert deserves the same response. A well-designed alerting strategy has three tiers:

```
Tier 1: PAGE (wake someone up)
    - Data at risk
    - Complete service outage
    - Approaching catastrophic failure
    Response time: < 15 minutes

Tier 2: NOTIFY (Slack/email during business hours)
    - Performance degraded
    - Approaching capacity limits
    - Unusual behavior detected
    Response time: < 4 hours

Tier 3: LOG (dashboard only, review weekly)
    - Informational events
    - Trend changes
    - Completed maintenance
    Response time: next business day
```

---

## Step 2 - Create Separate SNS Topics for Each Tier

**Tier 1 - Critical (PagerDuty/phone):**

```bash
aws sns create-topic \
  --name "aurora-critical-${CLUSTER_ID}" \
  --region "$REGION"
```

Save the ARN:

```bash
export SNS_CRITICAL="arn:aws:sns:${REGION}:$(aws sts get-caller-identity --query Account --output text):aurora-critical-${CLUSTER_ID}"
```

**Tier 2 - Warning (Slack/email):**

```bash
aws sns create-topic \
  --name "aurora-warning-${CLUSTER_ID}" \
  --region "$REGION"
```

```bash
export SNS_WARNING="arn:aws:sns:${REGION}:$(aws sts get-caller-identity --query Account --output text):aurora-warning-${CLUSTER_ID}"
```

Subscribe your email to both (in production, route critical to PagerDuty and warning to Slack):

```bash
aws sns subscribe \
  --topic-arn "$SNS_CRITICAL" \
  --protocol email \
  --notification-endpoint "your@email.com" \
  --region "$REGION"
```

```bash
aws sns subscribe \
  --topic-arn "$SNS_WARNING" \
  --protocol email \
  --notification-endpoint "your@email.com" \
  --region "$REGION"
```

---

## Step 3 - Define the Complete Alert Set

### Tier 1 - PAGE Immediately

These indicate data at risk or complete outage:

| Alert | Metric | Threshold | Period | Eval Periods | Why Page |
|-------|--------|-----------|--------|-------------|----------|
| TXID Wraparound | MaximumUsedTransactionIDs | > 1,500,000,000 | 300s | 1 | Database will shut down if not addressed |
| Storage Critical | FreeStorageSpace / VolumeBytesUsed | < 5 GB | 300s | 1 | Database becomes read-only when storage is full |
| Connection Exhaustion | DatabaseConnections | > 95% of max | 60s | 3 | No new connections - complete outage |
| Replica Down | AuroraReplicaLag | absent for > 5 min | 60s | 5 | Replication broken - data not protected |
| CPU Critical | CPUUtilization | > 95% | 60s | 5 | Database effectively unresponsive |

### Tier 2 - NOTIFY During Business Hours

These indicate degrading performance:

| Alert | Metric | Threshold | Period | Eval Periods | Why Notify |
|-------|--------|-----------|--------|-------------|-----------|
| CPU Warning | CPUUtilization | > 80% | 300s | 2 | Performance degrading - investigate |
| Memory Warning | FreeableMemory | < 10% of RAM | 300s | 2 | Approaching OOM - may start swapping |
| Connections Warning | DatabaseConnections | > 80% of max | 60s | 3 | Approaching exhaustion |
| Commit Latency | CommitLatency | > 20ms | 300s | 2 | Write performance degraded |
| Read Latency | ReadLatency | > 20ms | 300s | 2 | Storage I/O degraded |
| Cache Hit Low | BufferCacheHitRatio | < 95% | 300s | 3 | Working set exceeds cache |
| Deadlocks | Deadlocks | > 0 per 5 min | 300s | 1 | Application contention |
| Replica Lag Warning | AuroraReplicaLag | > 100ms | 60s | 5 | Reads may return stale data |

### Tier 3 - LOG Only

These go to the dashboard for weekly review:

| Alert | Metric | Threshold | Why Track |
|-------|--------|-----------|-----------|
| TXID Age Rising | MaximumUsedTransactionIDs | > 500,000,000 | Early warning before critical |
| Storage Growth | VolumeBytesUsed delta | > 10% per week | Capacity planning |
| Connection Baseline | DatabaseConnections | > 2x baseline | Unusual application behavior |

---

## Step 4 - Implement Tier 1 Alarms

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "CRITICAL-TXIDWraparound-${WRITER_INSTANCE}" \
  --alarm-description "TXID wraparound approaching - database may shut down" \
  --metric-name MaximumUsedTransactionIDs \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Maximum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1500000000 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_CRITICAL" \
  --ok-actions "$SNS_CRITICAL" \
  --region "$REGION"
```

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "CRITICAL-ConnectionExhaustion-${WRITER_INSTANCE}" \
  --alarm-description "Connections above 95% of max - new connections failing" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 3 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_CRITICAL" \
  --ok-actions "$SNS_CRITICAL" \
  --region "$REGION"
```

Note: Adjust the connection threshold to 95% of your actual max_connections value.

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "CRITICAL-CPUSaturation-${WRITER_INSTANCE}" \
  --alarm-description "CPU sustained above 95% - database effectively unresponsive" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 95 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_CRITICAL" \
  --ok-actions "$SNS_CRITICAL" \
  --region "$REGION"
```

---

## Step 5 - Implement Tier 2 Alarms

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WARNING-CPUHigh-${WRITER_INSTANCE}" \
  --alarm-description "CPU above 80% for 10 minutes - investigate" \
  --metric-name CPUUtilization \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_WARNING" \
  --ok-actions "$SNS_WARNING" \
  --region "$REGION"
```

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WARNING-CommitLatency-${WRITER_INSTANCE}" \
  --alarm-description "Commit latency above 20ms - write performance degraded" \
  --metric-name CommitLatency \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average \
  --period 300 \
  --evaluation-periods 2 \
  --threshold 20 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_WARNING" \
  --region "$REGION"
```

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WARNING-ReplicaLag-${CLUSTER_ID}" \
  --alarm-description "Replica lag above 100ms - reads may return stale data" \
  --metric-name AuroraReplicaLag \
  --namespace AWS/RDS \
  --dimensions Name=DBClusterIdentifier,Value="$CLUSTER_ID" \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 100 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_WARNING" \
  --region "$REGION"
```

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WARNING-Deadlocks-${WRITER_INSTANCE}" \
  --alarm-description "Deadlocks detected - application contention" \
  --metric-name Deadlocks \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Sum \
  --period 300 \
  --evaluation-periods 1 \
  --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions "$SNS_WARNING" \
  --region "$REGION"
```

---

## Step 6 - Verify the Complete Alarm Set

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "CRITICAL-" \
  --region "$REGION" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue}" \
  --output table
```

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "WARNING-" \
  --region "$REGION" \
  --query "MetricAlarms[].{Name:AlarmName,State:StateValue}" \
  --output table
```

All alarms should show `OK`.

---

## Step 7 - Alert Fatigue Prevention Rules

Write these rules down and follow them:

1. **Every alert must be actionable.** If you cannot do anything about it at 3 AM, it should not page. Move it to Tier 2.

2. **Every page must have a runbook.** The on-call DBA should be able to look up the alarm name and find a step-by-step resolution. The SURVIVE section of this module provides runbooks for the most common scenarios.

3. **Use evaluation periods.** Never alarm on a single data point. Brief CPU spikes during VACUUM or ANALYZE are normal. Require 2-5 consecutive breaches.

4. **Use OK actions.** Always send a notification when the alarm clears. This saves the on-call DBA from investigating a problem that already resolved.

5. **Review monthly.** If an alarm fired but required no action, adjust the threshold or remove the alarm. If an incident occurred without an alarm, add one.

6. **Separate critical from warning.** Never send warnings to PagerDuty. Never send criticals to Slack only. Mixing them causes both to be ignored.

---

## Step 8 - Document Your Alert Inventory

Keep this filled out and current:

```
ALERT INVENTORY - devops-lab-cluster
Last updated: [DATE]

TIER 1 (CRITICAL - PAGE):
[ ] TXID Wraparound        > 1.5B     SNS: aurora-critical-*
[ ] Connection Exhaustion   > 95%      SNS: aurora-critical-*
[ ] CPU Saturation          > 95%/5min SNS: aurora-critical-*

TIER 2 (WARNING - NOTIFY):
[ ] CPU High                > 80%/10min SNS: aurora-warning-*
[ ] Commit Latency          > 20ms/10min SNS: aurora-warning-*
[ ] Replica Lag             > 100ms/5min SNS: aurora-warning-*
[ ] Deadlocks               > 0/5min   SNS: aurora-warning-*

ON-CALL ROTATION: [NAMES]
ESCALATION PATH: [NAMES]
RUNBOOK LOCATION: Module 07 SURVIVE section
```

---

## Summary

You have:
- Created separate SNS topics for critical and warning alerts
- Implemented a tiered alerting strategy with clear escalation paths
- Created critical alarms that page immediately for data-at-risk scenarios
- Created warning alarms that notify during business hours for degraded performance
- Documented alert fatigue prevention rules

A well-designed alerting strategy is the difference between a team that trusts their alerts and responds quickly, and a team that ignores alerts because they cry wolf.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Tier 1 / PAGE | Alert that requires immediate response - data at risk or outage |
| Tier 2 / NOTIFY | Alert that requires investigation within business hours |
| Tier 3 / LOG | Informational event for weekly review |
| Alert fatigue | When too many false or low-priority alerts cause real alerts to be ignored |
| OK action | Notification sent when an alarm clears - tells on-call the problem resolved |
| Evaluation periods | Number of consecutive breaches required before alarm fires |
| Runbook | Step-by-step procedure for responding to a specific alert |

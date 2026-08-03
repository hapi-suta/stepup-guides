# USE 04 - Alerting Validation Exercise

**Time:** 40 minutes
**Difficulty:** Intermediate
**Prerequisites:** Build 01, 08 complete. CloudWatch alarms set. `$CLUSTER_ID`, `$WRITER_INSTANCE`, `$REGION`, `$SNS_TOPIC_ARN` set.

---

## Objective

Validate that your alerting pipeline works end-to-end by triggering a test alarm, verifying the notification arrives, and confirming the alarm clears when the condition resolves.

---

## Exercise Tasks

### Task 1 - Inventory Your Alarms

List all alarms and their current state:

```bash
aws cloudwatch describe-alarms \
  --region "$REGION" \
  --query "MetricAlarms[?starts_with(AlarmName,'Aurora-') || starts_with(AlarmName,'CRITICAL-') || starts_with(AlarmName,'WARNING-')].{Name:AlarmName,State:StateValue,Metric:MetricName,Threshold:Threshold}" \
  --output table
```

Confirm all alarms show `OK`. If any show `INSUFFICIENT_DATA`, wait 5 minutes and recheck.

<details>
<summary>What if an alarm is stuck in INSUFFICIENT_DATA?</summary>

This usually means:
1. The metric is not being published (instance stopped, wrong dimension)
2. The alarm was just created and not enough data points exist yet
3. The namespace or metric name has a typo

Check the alarm configuration:
```bash
aws cloudwatch describe-alarms \
  --alarm-names "ALARM_NAME_HERE" \
  --region "$REGION"
```
</details>

### Task 2 - Test Alarm Notification (Manual)

CloudWatch lets you temporarily set an alarm state for testing:

```bash
aws cloudwatch set-alarm-state \
  --alarm-name "WARNING-CPUHigh-${WRITER_INSTANCE}" \
  --state-value ALARM \
  --state-reason "Testing alarm notification pipeline" \
  --region "$REGION"
```

This forces the alarm into ALARM state. Check your email (or Slack, PagerDuty) for the notification.

<details>
<summary>Expected notification content</summary>

You should receive an email from AWS Notifications with:
- Subject: "ALARM: WARNING-CPUHigh-devops-lab-cluster-instance-1 in US East (N. Virginia)"
- Body including: alarm name, state change, reason, metric details
</details>

Wait for the alarm to auto-recover (the real metric is below threshold):

```bash
aws cloudwatch describe-alarms \
  --alarm-names "WARNING-CPUHigh-${WRITER_INSTANCE}" \
  --query "MetricAlarms[0].StateValue" \
  --output text \
  --region "$REGION"
```

The alarm should return to `OK` within 5-10 minutes. If you set up OK actions, you should receive a recovery notification.

### Task 3 - Trigger a Real Connection Alarm

Generate a connection spike to trigger the connections alarm:

```bash
for i in $(seq 1 50); do
    psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
        -c "SELECT pg_sleep(120);" &
    if (( i % 10 == 0 )); then
        echo "Opened $i connections..."
    fi
done
```

This opens 50 connections that sleep for 2 minutes each. If your threshold is low enough, this should trigger the warning alarm.

Check the alarm state:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "WARNING-ConnectionsHigh-${WRITER_INSTANCE}" \
  --query "MetricAlarms[0].StateValue" \
  --output text \
  --region "$REGION"
```

<details>
<summary>If the alarm does not trigger</summary>

Your connection threshold may be set higher than 50. Check:
```bash
aws cloudwatch describe-alarms \
  --alarm-names "Aurora-HighConnections-${WRITER_INSTANCE}" \
  --query "MetricAlarms[0].Threshold" \
  --output text \
  --region "$REGION"
```

If the threshold is 640 (80% of 800), you would need 640 connections to trigger it. For testing purposes, temporarily lower the threshold:
```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "WARNING-ConnectionsHigh-${WRITER_INSTANCE}" \
  --metric-name DatabaseConnections \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value="$WRITER_INSTANCE" \
  --statistic Average --period 60 --evaluation-periods 1 \
  --threshold 30 --comparison-operator GreaterThanThreshold \
  --alarm-actions "$SNS_TOPIC_ARN" --region "$REGION"
```

Remember to restore the original threshold after testing.
</details>

Clean up the test connections:

```bash
pkill -f "psql.*pg_sleep"
```

### Task 4 - Verify OK Notification

After cleaning up the connections, wait 5 minutes and verify:

1. The alarm returns to `OK` state
2. You receive an OK notification (if OK actions are configured)

```bash
aws cloudwatch describe-alarms \
  --alarm-names "WARNING-ConnectionsHigh-${WRITER_INSTANCE}" \
  --query "MetricAlarms[0].{State:StateValue,LastUpdated:StateUpdatedTimestamp}" \
  --output table \
  --region "$REGION"
```

### Task 5 - Document Alert Response Times

Fill out this table based on your testing:

| Test | Alarm Name | Time to Trigger | Notification Received | Time to Clear |
|------|-----------|----------------|----------------------|--------------|
| Manual state change | WARNING-CPUHigh | Immediate | Yes/No | ___ min |
| Connection spike | WARNING-Connections | ___ min | Yes/No | ___ min |

---

## Validation Checklist

```
[ ] All alarms show OK in steady state
[ ] Manual alarm test sent a notification
[ ] Real metric trigger sent a notification
[ ] OK notification received when alarm cleared
[ ] Alert response time documented
```

# SURVIVE Scenario 06: Monitoring Blind Spot - Runbook

## Scenario

Critical CloudWatch alarms and log metric filters have been deleted. Incidents are going undetected. Restore all monitoring.

---

## Step 1: Audit Current Alarms

**On your local workstation:**

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[*].AlarmName' \
  --output text \
  --region us-east-1
```

Compare against the expected list from Build 04:
- devops-lab-aurora-cpu-high
- devops-lab-aurora-connections-high
- devops-lab-aurora-memory-low
- devops-lab-aurora-replica-lag-high
- devops-lab-aurora-write-latency-high
- devops-lab-aurora-read-latency-high
- devops-lab-aurora-deadlocks
- devops-lab-aurora-auth-failures

---

## Step 2: Audit Current Metric Filters

**On your local workstation:**

```bash
aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --query 'metricFilters[*].filterName' \
  --output text \
  --region us-east-1
```

Compare against the expected list:
- devops-lab-deadlock-count
- devops-lab-auth-failures
- devops-lab-temp-files
- devops-lab-wraparound-warning

---

## Step 3: Get the SNS Topic ARN

**On your local workstation:**

```bash
SNS_TOPIC_ARN=$(aws sns list-topics \
  --query "Topics[?contains(TopicArn, 'devops-lab-aurora-alerts')].TopicArn" \
  --output text --region us-east-1)
echo "SNS Topic: $SNS_TOPIC_ARN"
```

---

## Step 4: Recreate Missing Alarms

Recreate each missing alarm. Refer to Build 04 for the exact configuration.

**CPU alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-cpu-high \
  --alarm-description "Aurora CPU above 80% for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Average --period 60 --evaluation-periods 5 \
  --threshold 80 --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching --region us-east-1
```

**Memory alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-memory-low \
  --alarm-description "Freeable memory below 500 MB for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name FreeableMemory \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-w1 \
  --statistic Average --period 60 --evaluation-periods 5 \
  --threshold 524288000 --comparison-operator LessThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching --region us-east-1
```

**Replica lag alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-replica-lag-high \
  --alarm-description "Replica lag above 30 seconds for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-r1 \
  --statistic Maximum --period 60 --evaluation-periods 5 \
  --threshold 30000 --comparison-operator GreaterThanThreshold \
  --alarm-actions $SNS_TOPIC_ARN --ok-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching --region us-east-1
```

**Deadlock alarm:**

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-deadlocks \
  --alarm-description "Deadlock detected" \
  --namespace DevOpsLab/Aurora \
  --metric-name DeadlockCount \
  --statistic Sum --period 300 --evaluation-periods 1 \
  --threshold 1 --comparison-operator GreaterThanOrEqualToThreshold \
  --alarm-actions $SNS_TOPIC_ARN \
  --treat-missing-data notBreaching --region us-east-1
```

---

## Step 5: Recreate Missing Metric Filters

**Deadlock filter:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-deadlock-count \
  --filter-pattern "deadlock detected" \
  --metric-transformations \
    metricName=DeadlockCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count \
  --region us-east-1
```

**Auth failures filter:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-auth-failures \
  --filter-pattern "authentication failed" \
  --metric-transformations \
    metricName=AuthFailureCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count \
  --region us-east-1
```

**Wraparound filter:**

```bash
aws logs put-metric-filter \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-name devops-lab-wraparound-warning \
  --filter-pattern "transaction ID wraparound" \
  --metric-transformations \
    metricName=WraparoundWarningCount,metricNamespace=DevOpsLab/Aurora,metricValue=1,unit=Count \
  --region us-east-1
```

---

## Step 6: Verify All Monitoring Restored

**On your local workstation:**

```bash
echo "Alarms:"
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[*].[AlarmName,StateValue]' --output table --region us-east-1

echo ""
echo "Metric Filters:"
aws logs describe-metric-filters \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --query 'metricFilters[*].filterName' --output text --region us-east-1
```

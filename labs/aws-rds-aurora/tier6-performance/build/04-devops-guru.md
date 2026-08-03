# Build 04 - Amazon DevOps Guru for RDS

**Time:** 25 minutes
**Goal:** Enable DevOps Guru for your RDS instance, understand how it generates insights, and configure notifications so alerts reach your team.
**Prerequisites:** RDS PostgreSQL instance running. AWS CLI configured. `$DB_INSTANCE_ID` and `$REGION` set. An SNS topic for alerts (from Build 01, or create one here).

---

## Background

DevOps Guru uses machine learning to analyze your operational telemetry (CloudWatch metrics, CloudWatch Logs, CloudTrail events, resource configurations) and detect anomalies. It builds a 2-week baseline of normal behavior and then alerts when patterns deviate significantly.

For RDS specifically, it covers:
- Unusual connection counts
- Unexpected query latency spikes
- Replication lag anomalies
- Storage growth acceleration
- CPU patterns inconsistent with historical baseline
- Autovacuum running more than normal

> **Concept:** DevOps Guru generates two types of insights. A reactive insight fires when a problem is already occurring. A proactive insight fires when it predicts a problem is likely - for example, it detects your disk fill rate will exhaust storage in 3 days.

---

## Step 1 - Verify DevOps Guru Access

Check if DevOps Guru is available in your region:

```bash
aws devops-guru list-insights \
  --status-filter '{"Any":{"StartTimeRange":{"FromTime":"2024-01-01T00:00:00Z","ToTime":"2024-12-31T00:00:00Z"},"Type":"REACTIVE"}}' \
  --region "$REGION" \
  --max-results 1 2>&1 | head -5
```

If you get an error about DevOps Guru not being set up, proceed to the next step.

---

## Step 2 - Enable DevOps Guru via Console

### Enable and Configure Resource Coverage

1. Open the [DevOps Guru Console](https://console.aws.amazon.com/devops-guru/).
2. If this is your first time, click **Get started** on the welcome page.
3. On the **Specify AWS resources** page, choose **Choose later** if you want to configure coverage next, or choose **All account resources** for broad coverage.
4. For cost efficiency with RDS labs, select **CloudFormation stacks** or **AWS tags** to limit coverage to only your lab resources.
5. Click **Enable DevOps Guru**.

### Add Your RDS Instance to Coverage

1. In the DevOps Guru Console, click **Settings** in the left menu.
2. Under **Resource analysis**, click **Manage**.
3. Choose one of:
   - **All account resources** - analyzes everything (higher cost)
   - **AWS CloudFormation stacks** - only stacks you specify
   - **AWS tags** - only resources with specific tags
4. If using tags, add a tag to your RDS instance first:

```bash
aws rds add-tags-to-resource \
  --resource-name "arn:aws:rds:${REGION}:$(aws sts get-caller-identity --query Account --output text):db:${DB_INSTANCE_ID}" \
  --tags Key=DevOpsGuru,Value=enabled \
  --region "$REGION"
```

`--tags Key=DevOpsGuru,Value=enabled`: Adds a tag you will reference in DevOps Guru's tag filter.

---

## Step 3 - Enable DevOps Guru via CLI

```bash
aws devops-guru update-resource-collection \
  --action ADD \
  --resource-collection '{
    "Tags": [
      {
        "AppBoundaryKey": "DevOpsGuru",
        "TagValues": ["enabled"]
      }
    ]
  }' \
  --region "$REGION"
```

Each part explained:
- `--action ADD`: Add resources to the monitored set.
- `AppBoundaryKey`: The tag key DevOps Guru uses to identify your application boundary.
- `TagValues`: The tag values that select specific resources.

Confirm the resource collection:

```bash
aws devops-guru get-resource-collection \
  --resource-collection-type TAGS \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "ResourceCollection": {
        "Tags": [
            {
                "AppBoundaryKey": "DevOpsGuru",
                "TagValues": ["enabled"]
            }
        ]
    }
}
```

---

## Step 4 - Configure SNS Notifications

DevOps Guru needs an SNS topic to send alerts. Use the one from Build 01, or create a new one:

```bash
export GURU_SNS_ARN=$(aws sns create-topic \
  --name "devops-guru-alerts" \
  --region "$REGION" \
  --query TopicArn \
  --output text)

echo "SNS Topic ARN: $GURU_SNS_ARN"
```

Subscribe your email:

```bash
aws sns subscribe \
  --topic-arn "$GURU_SNS_ARN" \
  --protocol email \
  --notification-endpoint "your@email.com" \
  --region "$REGION"
```

Add the SNS channel to DevOps Guru:

```bash
aws devops-guru add-notification-channel \
  --config "{\"Sns\":{\"TopicArn\":\"${GURU_SNS_ARN}\"}}" \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "Id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

Verify the channel was added:

```bash
aws devops-guru list-notification-channels \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "Channels": [
        {
            "Id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
            "Config": {
                "Sns": {
                    "TopicArn": "arn:aws:sns:us-east-1:123456789012:devops-guru-alerts"
                }
            }
        }
    ]
}
```

---

## Step 5 - View Existing Insights

Check if DevOps Guru has generated any insights (may be empty if the service just started):

```bash
aws devops-guru list-insights \
  --status-filter '{"Any":{"StartTimeRange":{"FromTime":"2024-01-01T00:00:00Z"},"Type":"REACTIVE"}}' \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "ProactiveInsights": [],
    "ReactiveInsights": []
}
```

DevOps Guru needs 2 weeks of data to build its baseline. You will not see insights immediately after enabling it.

---

## Step 6 - Understand a DevOps Guru Insight

When DevOps Guru generates an insight, it looks like this in the console:

```
Insight: Unusual number of database connections

Severity: HIGH
Status: ONGOING
Start: 2024-01-31 14:23:00 UTC

Anomalous metrics:
  - DatabaseConnections: 482 (baseline: 45-65)

Recommendations:
  - Review application connection pooling configuration
  - Consider enabling RDS Proxy to reduce connection overhead
  - Check for connection leaks in application code
```

Each insight includes:
- The anomalous metrics and how they compare to baseline
- The time period of the anomaly
- Recommendations
- Links to related CloudWatch metrics

---

## Step 7 - Generate a Test Anomaly

You can trigger a connection anomaly to see DevOps Guru react (takes several minutes to appear as an insight):

```bash
# Open 50 simultaneous connections rapidly
for i in $(seq 1 50); do
  psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT pg_sleep(120);" &
done
```

Wait 5-10 minutes. DevOps Guru samples data and processes it every few minutes. Check back in the console under **Insights** for a reactive insight about connection count anomaly.

Kill the background connections when done:

```bash
# Kill all background psql connections
kill %1 %2 %3 %4 %5 2>/dev/null
pkill -f "psql.*pg_sleep" 2>/dev/null
```

---

## Step 8 - View RDS Performance Insights Anomalies

DevOps Guru for RDS has a dedicated view that integrates with Performance Insights. In the console:

1. Open [DevOps Guru Console](https://console.aws.amazon.com/devops-guru/).
2. Click **Insights** in the left menu.
3. If there are insights, click one.
4. Scroll down to **Associated metrics** to see which CloudWatch metrics were anomalous.
5. Click **View in Performance Insights** if the insight is RDS-related.

---

## Step 9 - Configure EventBridge for Automated Response

For production, route DevOps Guru insights to EventBridge so you can trigger Lambda functions for automated remediation:

```bash
aws events put-rule \
  --name "DevOpsGuruRDSInsights" \
  --event-pattern '{
    "source": ["aws.devops-guru"],
    "detail-type": ["DevOps Guru New Insight Open"],
    "detail": {
      "insightSeverity": ["HIGH", "MEDIUM"]
    }
  }' \
  --state ENABLED \
  --region "$REGION"
```

`--event-pattern`: Filters which DevOps Guru events trigger this rule. Only HIGH and MEDIUM severity insights.

This rule can then trigger a Lambda function, an SSM Automation runbook, or another SNS topic for Slack/PagerDuty routing.

---

## Cost Check

Check how many resources DevOps Guru is currently analyzing:

```bash
aws devops-guru describe-account-health \
  --region "$REGION"
```

Expected output (yours will differ):
```json
{
    "OpenReactiveInsights": 0,
    "OpenProactiveInsights": 0,
    "MetricsAnalyzed": 12,
    "ResourceHours": 8,
    "AnalyzedResourceCount": 1
}
```

`AnalyzedResourceCount: 1` - analyzing 1 resource (your RDS instance). At ~$0.0028/hr, that is about $2/month.

---

## Summary

You have:
- Enabled DevOps Guru and added your RDS instance to the monitored resource set
- Configured SNS notifications for insights
- Understood the structure of a DevOps Guru insight
- Set up an EventBridge rule for automated remediation routing

DevOps Guru is passive infrastructure - you set it up once and it watches continuously. The value comes over weeks as it learns your workload baseline.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Reactive insight | Anomaly that is currently occurring |
| Proactive insight | Predicted future problem (e.g., disk will fill in 3 days) |
| App boundary | Tag-based grouping of resources DevOps Guru analyzes together |
| Baseline | 2-week learning period during which DevOps Guru establishes normal behavior |
| MetricsAnalyzed | Number of CloudWatch metrics DevOps Guru is actively monitoring |
| EventBridge | AWS event bus used to route DevOps Guru insights to Lambda or other targets |

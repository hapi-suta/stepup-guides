# SURVIVE 05 - Maintenance Window Surprise
## Runbook: Rescheduling Maintenance Before It Fires

**Scenario:** A maintenance window is configured for Monday 14:00-14:30 UTC (peak business hours). A pending OS update is scheduled to apply during that window in 3 hours 45 minutes. Fix it before the outage happens.

**What the student sees:**
```
AWS Email: Pending maintenance for devops-lab-cluster
Scheduled window: Monday 14:00-14:30 UTC
Your maintenance window is set to business hours.
This will cause a brief outage during peak traffic.
```

---

## Your Objective

Move the maintenance window to off-hours, defer any pending maintenance to the new window, and write a notification to the application team - all within **30 minutes** of receiving the alert.

---

## Step 1 - Confirm the Current Maintenance Window

Run this command to see the current maintenance window and backup window:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{MaintenanceWindow:PreferredMaintenanceWindow,BackupWindow:PreferredBackupWindow}' \
  --output table
```

- `--db-cluster-identifier` - the Aurora cluster to inspect.
- `--query` - extracts just the maintenance and backup window fields.
- `--output table` - formats the result as a readable table.

Expected output (yours will differ):

```
--------------------------------------------
|          DescribeDBClusters              |
+-----------------------+------------------+
|  BackupWindow         |  07:00-07:30     |
|  MaintenanceWindow    |  mon:14:00-mon:14:30 |
+-----------------------+------------------+
```

The maintenance window shows `mon:14:00-mon:14:30` - this is Monday at 2:00 PM UTC, which is peak business hours.

---

## Step 2 - Check Pending Maintenance Actions

Check if there are any pending maintenance actions scheduled for the cluster:

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --query "PendingMaintenanceActions[?contains(ResourceIdentifier,'$CLUSTER_ID')]" \
  --output json
```

- `--query` - filters to show only maintenance actions for your cluster.

If there are pending actions, note two things:
- The `Action` type (e.g., `system-update`, `db-upgrade`)
- The `AutoAppliedAfterDate` - the deadline when AWS will force the update regardless of your preference

Expected output (yours will differ):

```json
[
    {
        "ResourceIdentifier": "arn:aws:rds:us-east-1:123456789012:cluster:devops-lab-cluster",
        "PendingMaintenanceActionDetails": [
            {
                "Action": "system-update",
                "AutoAppliedAfterDate": "2026-06-15T00:00:00Z",
                "Description": "New Operating System update available"
            }
        ]
    }
]
```

If the output is an empty array `[]`, there are no pending actions right now. You still need to fix the window to prevent future business-hour maintenance.

---

## Step 3 - Move the Maintenance Window to Off-Hours

Choose a safe window. Best practice: Sunday 03:00-03:30 UTC (late Saturday night in US time zones).

### Console

1. Open **RDS > Databases**.
2. Click your cluster name (`devops-lab-cluster`).
3. Click **Modify**.
4. Scroll down to **Maintenance**.
5. Under **Maintenance window**, click **Select window**.
6. Choose **Sunday** and set **Start time** to `03:00` UTC, **Duration** to 30 minutes.
7. Click **Continue**.
8. Select **Apply immediately** (this does NOT cause a reboot - it only updates the schedule).
9. Click **Modify cluster**.

### CLI

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --preferred-maintenance-window "sun:03:00-sun:03:30" \
  --region $AWS_REGION
```

- `--preferred-maintenance-window` - the new weekly window in `ddd:hh:mm-ddd:hh:mm` format.
- This change takes effect immediately. It does NOT cause any reboot or downtime.

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredMaintenanceWindow' \
  --output text
```

Expected output:

```
sun:03:00-sun:03:30
```

---

## Step 4 - Handle Pending Maintenance

If there is a pending maintenance action, you have two choices:

**Option A - Let it apply at the new Sunday window** (safer, deferred)

The window change alone is sufficient. The pending maintenance will now fire Sunday at 03:00 instead of Monday at 14:00.

Opt-in to the next maintenance window:

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_ID}" \
  --apply-action system-update \
  --opt-in-type next-maintenance \
  --region $AWS_REGION
```

- `--resource-identifier` - the full ARN of the cluster. Note: for Aurora clusters, use `cluster:` not `db:`.
- `--apply-action` - the maintenance action type from Step 2.
- `--opt-in-type next-maintenance` - schedules the action for the next maintenance window (now Sunday).

**Option B - Apply it immediately tonight** (if the deadline is soon)

If `AutoAppliedAfterDate` is before next Sunday, you may need to apply it sooner:

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_ID}" \
  --apply-action system-update \
  --opt-in-type immediate \
  --region $AWS_REGION
```

- `--opt-in-type immediate` - applies the maintenance NOW. This will cause a brief outage.

> **Warning:** `--opt-in-type immediate` will trigger a reboot. Only use this if you have alerted the application team and it is an acceptable time for downtime.

---

## Step 5 - Verify No Pending Maintenance Is Scheduled for Business Hours

Run the pending maintenance check again:

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --query "PendingMaintenanceActions[?contains(ResourceIdentifier,'$CLUSTER_ID')]" \
  --output json
```

If the output is an empty array: no pending actions remain.

If there is a pending action, confirm that `OptInStatus` shows `next-maintenance` or that the action was already applied. It should NOT show `required` with a business-hours deadline.

---

## Step 6 - Write the Application Team Notification

Write and send this message to the application team:

```
Subject: [ACTION TAKEN] Maintenance Window Corrected - Cluster devops-lab-cluster

Hi team,

We received an AWS maintenance notification scheduled for Monday 14:00-14:30 UTC,
which is during peak business hours. This has been corrected.

Action taken:
- Maintenance window moved to: Sunday 03:00-03:30 UTC
- Any pending OS updates will apply at the new window
- Expected downtime during the Sunday window: 30-60 seconds (Aurora Multi-AZ failover)

What you may see during the Sunday window:
- Brief connection errors (under 1 minute for Aurora)
- Application should reconnect automatically
- We recommend retry logic in the application connection pool

If this Sunday window conflicts with any scheduled jobs or reports, please reply
by [DATE] and we will coordinate a different time.

[YOUR NAME]
DBA Team
```

---

## Step 7 - Add a Monitoring Alert (Preventive Measure)

Set up an SNS event subscription so you never miss a maintenance notification again.

Create an SNS topic:

```bash
aws sns create-topic \
  --name rds-maintenance-alerts \
  --region $AWS_REGION \
  --query 'TopicArn' \
  --output text
```

- `--name` - a descriptive name for the notification topic.

Subscribe your email to the topic:

```bash
aws sns subscribe \
  --topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rds-maintenance-alerts" \
  --protocol email \
  --notification-endpoint "your-email@example.com" \
  --region $AWS_REGION
```

- `--protocol email` - sends notifications via email.
- `--notification-endpoint` - replace with your actual email address.

Create the RDS event subscription:

```bash
aws rds create-event-subscription \
  --subscription-name "rds-maintenance-$(date +%Y%m%d)" \
  --sns-topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rds-maintenance-alerts" \
  --source-type db-cluster \
  --event-categories maintenance notification \
  --source-ids $CLUSTER_ID \
  --region $AWS_REGION
```

- `--source-type db-cluster` - monitors cluster-level events (Aurora uses clusters, not standalone instances).
- `--event-categories` - subscribes to maintenance and notification events.
- `--source-ids` - limits the subscription to your specific cluster.

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. AWS maintenance windows default to randomly assigned times - always set them explicitly when creating a cluster
2. Moving the window is free and non-disruptive - it just changes the schedule, no reboot occurs
3. Pending maintenance has a hard deadline (`AutoAppliedAfterDate`) - AWS will apply it after that date regardless of your preference
4. Aurora handles maintenance differently than standard RDS - Aurora's Multi-AZ failover means maintenance downtime is typically 30-60 seconds, not 3-5 minutes
5. Set up SNS maintenance event subscriptions as standard practice for all production clusters
6. The maintenance window and backup window cannot overlap - check both when changing either one
7. For Aurora clusters, the maintenance window is set at the cluster level with `modify-db-cluster`, not at the instance level

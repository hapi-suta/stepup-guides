# SURVIVE 05 - Maintenance Window Surprise
## Runbook: Rescheduling Maintenance Before It Fires

**Scenario:** A maintenance window is configured for Monday 14:00-14:30 UTC (peak business hours). A pending OS update is scheduled to apply during that window in 3 hours 45 minutes. Fix it before the outage happens.

**What the student sees:**
```
AWS Email: Pending maintenance for suta-t5-primary-hfa
Scheduled window: Monday 14:00-14:30 UTC
Your maintenance window is set to business hours.
The instance is Single-AZ - this will cause ~3-5 minutes of downtime.
```

---

## Your Objective

Move the maintenance window to off-hours, defer any pending maintenance to the new window, and write a notification to the application team - all within **30 minutes** of receiving the alert.

---

## Step 1 - Confirm the Current Maintenance Window

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{MaintenanceWindow:PreferredMaintenanceWindow,MultiAZ:MultiAZ}' \
  --output table
```

Expected output showing the problem:

```
--------------------------------------------
|          DescribeDBInstances             |
+-----------------------+------------------+
|  MaintenanceWindow    |  mon:14:00-mon:14:30 |
|  MultiAZ              |  False           |
+-----------------------+------------------+
```

`MultiAZ: False` means a reboot during maintenance will cause full downtime (no standby to fail over to).

---

## Step 2 - Check Pending Maintenance Actions

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --query "PendingMaintenanceActions[?ResourceIdentifier && contains(ResourceIdentifier,'${DB_INSTANCE}')]" \
  --output json
```

If there are pending actions, record:
- The `Action` type (e.g., `system-update`)
- The `AutoAppliedAfterDate` - this is the deadline when AWS will force it

---

## Step 3 - Move the Maintenance Window to Off-Hours

Choose a safe window. Best practice: Sunday 03:00-03:30 UTC (2-3 AM Eastern, weekend).

### Console

1. Open **RDS > Databases**.
2. Click your instance.
3. Click **Modify**.
4. Scroll to **Maintenance**.
5. Under **Maintenance window**, click **Select window**.
6. Choose **Sunday** and set **Start time** to `03:00` UTC, **Duration** to 30 minutes.
7. Click **Continue**.
8. Select **Apply immediately** for the window change (does NOT cause a reboot - just updates the schedule).
9. Click **Modify DB Instance**.

### CLI

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --preferred-maintenance-window "sun:03:00-sun:03:30" \
  --region $AWS_REGION
```

Note: This change does NOT require `--apply-immediately` because it is just a schedule change, not a database modification. It takes effect immediately.

Verify the change:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].PreferredMaintenanceWindow'
```

Expected output:

```
"sun:03:00-sun:03:30"
```

---

## Step 4 - Handle Pending Maintenance

If there is a pending maintenance action, you have two choices:

**Option A - Let it apply at the new Sunday window** (safer, deferred)

The window change alone is sufficient. The pending maintenance will now fire Sunday at 03:00 instead of Monday at 14:00.

Opt-in to the next maintenance window:

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):db:${DB_INSTANCE}" \
  --apply-action system-update \
  --opt-in-type next-maintenance \
  --region $AWS_REGION
```

`--opt-in-type next-maintenance` applies the action at the next maintenance window (now Sunday).

**Option B - Apply it immediately tonight** (if Sunday is too far and the `AutoAppliedAfterDate` is soon)

If the deadline is before next Sunday, consider applying tonight at a low-traffic time:

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):db:${DB_INSTANCE}" \
  --apply-action system-update \
  --opt-in-type immediate \
  --region $AWS_REGION
```

> **Warning:** `--opt-in-type immediate` will cause a reboot NOW. Only use this if you have alerted the application team and it is an acceptable time.

---

## Step 5 - Verify No Pending Maintenance Is Scheduled for Business Hours

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --query "PendingMaintenanceActions[?ResourceIdentifier && contains(ResourceIdentifier,'${DB_INSTANCE}')]" \
  --output json
```

If the output is empty: no pending actions. The moved window is protection for future maintenance.

If there is a pending action, confirm `OptInStatus` shows `next-maintenance` or `immediate`, not `required` with a business-hours deadline.

---

## Step 6 - Write the Application Team Notification

Write and send this message to the application team:

```
Subject: [ACTION TAKEN] Maintenance Window Corrected - Database suta-t5-primary-hfa

Hi team,

We received an AWS maintenance notification scheduled for Monday 14:00-14:30 UTC,
which is during peak business hours. This has been corrected.

Action taken:
- Maintenance window moved to: Sunday 03:00-03:30 UTC (Saturday 11 PM - 11:30 PM Eastern)
- Any pending OS updates will apply at the new window
- Expected downtime: 3-5 minutes (Single-AZ instance)

What you may see during the Sunday window:
- Brief connection errors (~3-5 minutes)
- Application should reconnect automatically
- We recommend retry logic in the application connection pool

If this Sunday window conflicts with any scheduled jobs or reports, please reply
by [DATE] and we will coordinate a different time.

[YOUR NAME]
DBA Team
```

---

## Step 7 - Add a Monitoring Alert (Preventive Measure)

Set up an SNS event subscription so you never miss a maintenance notification again:

First, note your SNS topic ARN (create one if needed):

```bash
aws sns create-topic \
  --name rds-maintenance-alerts \
  --region $AWS_REGION \
  --query 'TopicArn' \
  --output text
```

Then subscribe your email:

```bash
aws sns subscribe \
  --topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rds-maintenance-alerts" \
  --protocol email \
  --notification-endpoint "your-email@example.com" \
  --region $AWS_REGION
```

Create the RDS event subscription:

```bash
aws rds create-event-subscription \
  --subscription-name "rds-maintenance-$(date +%Y%m%d)" \
  --sns-topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):rds-maintenance-alerts" \
  --source-type db-instance \
  --event-categories maintenance notification \
  --source-ids $DB_INSTANCE \
  --region $AWS_REGION
```

---

## Run Validate Script

```bash
bash validate.sh
```

---

## Key Lessons

1. AWS maintenance windows default to randomly assigned times - always set them explicitly
2. Moving the window is free and non-disruptive - it just changes the schedule
3. Pending maintenance has a hard deadline (`AutoAppliedAfterDate`) - AWS will apply it after that date regardless of your window
4. Multi-AZ reduces maintenance downtime from 3-5 minutes to 30-60 seconds - a strong argument for enabling it
5. Set up SNS maintenance event subscriptions as standard practice for all production instances
6. The maintenance window and backup window cannot overlap - check both when changing either one

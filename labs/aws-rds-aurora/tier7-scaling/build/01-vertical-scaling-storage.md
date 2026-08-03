# Tier 7 - Scaling, Integration, and Modern Patterns
## Guide 01: Vertical Scaling and Storage Autoscaling

**Objective:** Resize an RDS instance class with minimal downtime, enable and configure storage autoscaling, and set up monitoring for scaling events.
**Time:** 35 minutes
**Prerequisites:** An existing RDS PostgreSQL instance (db.t3.medium or similar). Multi-AZ recommended to observe failover behavior.
**Infrastructure:** Reuse your Tier 1 VPC and RDS instance.

---

## 1. Understand What You Are About to Do

Vertical scaling in RDS means changing the instance class. You are moving to a machine with different CPU, RAM, and network specs. The database data stays on the same storage - only the compute changes.

**What happens during the change:**
- With Multi-AZ: AWS resizes the standby first, promotes it (causing a ~30-60 second failover), then resizes the old primary in the background. Your application sees one brief interruption.
- Without Multi-AZ: AWS reboots the instance after the resize. Downtime is typically 1-5 minutes.

You should always perform instance class changes during a low-traffic window, even with Multi-AZ.

---

## 2. Record Your Current State

Before making any change, document the baseline.

### Console

1. Open the AWS Console and go to **RDS**.
2. Click **Databases** in the left sidebar.
3. Click your database identifier.
4. Under the **Configuration** tab, note:
   - Instance class
   - Multi-AZ status
   - Storage type and allocated storage
   - Storage autoscaling status

### CLI

Run these commands one at a time. Replace `[DB-IDENTIFIER]` with your actual instance name.

**Step 1.** List your instance details:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].{Class:DBInstanceClass,Storage:AllocatedStorage,StorageType:StorageType,MultiAZ:MultiAZ,AutoscalingMax:MaxAllocatedStorage}' \
  --output table
```

The `--query` flag uses JMESPath to extract specific fields. The `--output table` flag formats the result as a readable table.

Expected output (yours will differ):
```
--------------------------------------------------------------
|                    DescribeDBInstances                     |
+--------------------+---------------------------------------+
|  AutoscalingMax    |  None                                 |
|  Class             |  db.t3.medium                         |
|  MultiAZ           |  True                                 |
|  Storage           |  100                                  |
|  StorageType       |  gp3                                  |
+--------------------+---------------------------------------+
```

**Step 2.** Record the current CloudWatch baseline:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[DB-IDENTIFIER] \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 3600 \
  --statistics Average \
  --region [REGION]
```

> **Note (macOS):** Replace `date -u -d '1 hour ago'` with `date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ'` if running on macOS. The `-d` flag is GNU/Linux-only syntax; macOS uses `-v` for date arithmetic.

The `--period 3600` flag aggregates into one data point per 3600 seconds (one hour). The `--statistics Average` flag returns the average value over that period.

---

## 3. Resize the Instance Class

### Console

1. On your database detail page, click **Modify** (top right).
2. In the **Instance configuration** section, click the **DB instance class** dropdown.
3. Select the new class. For this lab, choose one step up from your current class. If you are on `db.t3.medium`, select `db.t3.large`. If already on `r` class, stay within the same family.
4. Scroll to the bottom. Under **Scheduling of modifications**, select **Apply immediately**.
5. Click **Continue**.
6. Review the summary. Confirm the **Instance class** shows the new class.
7. Click **Modify DB instance**.

### CLI

**Step 1.** Submit the modification request:

```bash
aws rds modify-db-instance \
  --db-instance-identifier [DB-IDENTIFIER] \
  --db-instance-class db.t3.large \
  --apply-immediately \
  --region [REGION]
```

The `--apply-immediately` flag starts the change now rather than waiting for the maintenance window. The response includes the entire instance description - look for `"PendingModifiedValues"` to confirm the change is queued.

Expected output (truncated):
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "my-postgres-db",
        "DBInstanceClass": "db.t3.medium",
        "PendingModifiedValues": {
            "DBInstanceClass": "db.t3.large"
        },
        ...
    }
}
```

**Step 2.** Watch the instance status:

```bash
watch -n 10 "aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}' \
  --output table"
```

The `watch -n 10` command re-runs the enclosed command every 10 seconds. You will see the status cycle through `modifying` and briefly through `rebooting` or `failing-over`, then back to `available`.

**Step 3.** Confirm the change completed:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].DBInstanceClass' \
  --output text
```

Expected output:
```
db.t3.large
```

---

## 4. Check the RDS Event Log

RDS logs scaling events. These are important for auditing and incident investigation.

### Console

1. In the RDS console, click **Events** in the left sidebar.
2. Filter by **Source type**: DB instance.
3. Filter by **Source**: your database identifier.
4. Look for events like `Applied modification to database instance class`.

### CLI

```bash
aws rds describe-events \
  --source-identifier [DB-IDENTIFIER] \
  --source-type db-instance \
  --duration 60 \
  --region [REGION] \
  --query 'Events[*].{Time:Date,Message:Message}' \
  --output table
```

The `--duration 60` flag returns events from the last 60 minutes. The output will show you exactly when the failover occurred and when the modification completed.

Expected output (yours will differ):
```
------------------------------------------------------------------------------------------------------
|                                          DescribeEvents                                            |
+----------------------------------+------------------------------------------------------------------+
|  Time                            |  Message                                                        |
+----------------------------------+------------------------------------------------------------------+
|  2024-03-15T14:22:01.000Z        |  Multi-AZ instance failover started.                            |
|  2024-03-15T14:22:45.000Z        |  DB instance restarted.                                        |
|  2024-03-15T14:23:10.000Z        |  Multi-AZ instance failover completed.                         |
|  2024-03-15T14:28:30.000Z        |  DB instance class changed from db.t3.medium to db.t3.large.  |
+----------------------------------+------------------------------------------------------------------+
```

---

## 5. Enable Storage Autoscaling

Storage autoscaling lets RDS expand your allocated storage automatically when free space drops below the threshold.

### Console

1. On your database detail page, click **Modify**.
2. Scroll to the **Storage** section.
3. Check the box next to **Enable storage autoscaling**.
4. In **Maximum storage threshold**, enter `500` (GiB). This is the ceiling. RDS will never scale beyond this.
5. Leave other storage settings unchanged.
6. Select **Apply immediately**.
7. Click **Continue**, then **Modify DB instance**.

### CLI

**Step 1.** Enable autoscaling with a 500 GiB maximum:

```bash
aws rds modify-db-instance \
  --db-instance-identifier [DB-IDENTIFIER] \
  --max-allocated-storage 500 \
  --apply-immediately \
  --region [REGION]
```

Setting `--max-allocated-storage` to any value above the current allocated storage enables autoscaling. The value you set is the maximum ceiling.

**Step 2.** Confirm autoscaling is enabled:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].{AllocatedStorage:AllocatedStorage,MaxStorage:MaxAllocatedStorage}' \
  --output table
```

Expected output:
```
-----------------------------------------
|         DescribeDBInstances           |
+------------------+--------------------+
|  AllocatedStorage|  100               |
|  MaxStorage      |  500               |
+------------------+--------------------+
```

A non-null `MaxStorage` value confirms autoscaling is active.

---

## 6. Set Up CloudWatch Alarms for Storage Events

You need to be alerted before storage fills, not after.

### Console

1. Go to **CloudWatch** in the AWS Console.
2. Click **Alarms** in the left sidebar, then **Create alarm**.
3. Click **Select metric**.
4. Navigate to **RDS** > **Per-Database Metrics**.
5. Find `FreeStorageSpace` for your database identifier and select it.
6. Click **Select metric**.
7. Set the period to **5 minutes**.
8. Set the condition: **Static** threshold, **Lower than** `10737418240` (10 GiB in bytes).
9. Click **Next**.
10. Under **Notification**, add an SNS topic or email address to receive the alert.
11. Name the alarm: `[DB-IDENTIFIER]-low-storage`.
12. Click **Create alarm**.

### CLI

**Step 1.** Create an SNS topic for storage alerts (skip if you already have one):

```bash
aws sns create-topic \
  --name rds-storage-alerts \
  --region [REGION]
```

Note the `TopicArn` in the output. You will use it in the next step.

**Step 2.** Subscribe your email to the topic:

```bash
aws sns subscribe \
  --topic-arn arn:aws:sns:[REGION]:[ACCOUNT-ID]:rds-storage-alerts \
  --protocol email \
  --notification-endpoint [YOUR-EMAIL] \
  --region [REGION]
```

Check your email and confirm the subscription before continuing.

**Step 3.** Create the CloudWatch alarm:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name "[DB-IDENTIFIER]-low-storage" \
  --alarm-description "RDS free storage below 10 GiB" \
  --metric-name FreeStorageSpace \
  --namespace AWS/RDS \
  --dimensions Name=DBInstanceIdentifier,Value=[DB-IDENTIFIER] \
  --statistic Average \
  --period 300 \
  --evaluation-periods 3 \
  --threshold 10737418240 \
  --comparison-operator LessThanThreshold \
  --alarm-actions arn:aws:sns:[REGION]:[ACCOUNT-ID]:rds-storage-alerts \
  --treat-missing-data notBreaching \
  --region [REGION]
```

Breaking down the flags:
- `--period 300` - Evaluates every 5 minutes (300 seconds).
- `--evaluation-periods 3` - Must breach for 3 consecutive periods before firing. Prevents noisy one-off alerts.
- `--threshold 10737418240` - 10 GiB expressed in bytes (10 * 1024 * 1024 * 1024).
- `--comparison-operator LessThanThreshold` - Fires when the metric drops below the threshold.
- `--treat-missing-data notBreaching` - Missing data points do not trigger the alarm.

**Step 4.** Verify the alarm was created:

```bash
aws cloudwatch describe-alarms \
  --alarm-names "[DB-IDENTIFIER]-low-storage" \
  --region [REGION] \
  --query 'MetricAlarms[0].{State:StateValue,Threshold:Threshold}' \
  --output table
```

Expected output:
```
------------------------------------------------------
|                  DescribeAlarms                    |
+-----------+----------------------------------------+
|  State    |  OK                                    |
|  Threshold|  10737418240.0                         |
+-----------+----------------------------------------+
```

---

## 7. Set Up an EventBridge Rule for Storage Scale Events

Storage autoscaling events are published to EventBridge. Wire them to a notification.

### CLI

**Step 1.** Create the EventBridge rule:

```bash
aws events put-rule \
  --name "rds-storage-autoscale-events" \
  --event-pattern '{
    "source": ["aws.rds"],
    "detail-type": ["RDS DB Instance Event"],
    "detail": {
      "EventID": ["RDS-EVENT-0224"]
    }
  }' \
  --state ENABLED \
  --region [REGION]
```

`RDS-EVENT-0224` is the event ID for storage autoscaling. The `--event-pattern` JSON matches events from the RDS service with that specific event ID.

**Step 2.** Add the SNS topic as the target:

```bash
aws events put-targets \
  --rule "rds-storage-autoscale-events" \
  --targets "Id=1,Arn=arn:aws:sns:[REGION]:[ACCOUNT-ID]:rds-storage-alerts" \
  --region [REGION]
```

---

## 8. Validate Your Setup

Run a final check to confirm everything is in order.

```bash
aws rds describe-db-instances \
  --db-instance-identifier [DB-IDENTIFIER] \
  --region [REGION] \
  --query 'DBInstances[0].{Class:DBInstanceClass,Allocated:AllocatedStorage,MaxStorage:MaxAllocatedStorage,StorageType:StorageType}' \
  --output table
```

Expected output (values will match what you configured):
```
-------------------------------------------------
|           DescribeDBInstances                  |
+------------+----+------------+----------------+
|  Allocated |  100            |                |
|  Class     |  db.t3.large   |                |
|  MaxStorage|  500           |                |
|  StorageType|  gp3          |                |
+------------+----+-----------+----------------+
```

---

## Summary

What you did in this lab:

- Recorded pre-change baseline using CLI describe commands.
- Performed an instance class change (vertical scale-up) and observed it complete through status polling.
- Enabled storage autoscaling with a maximum ceiling.
- Created a CloudWatch alarm for low storage with an SNS notification.
- Wired EventBridge to send notifications when storage autoscaling events occur.

**Key things to remember:**
- Instance class changes require a reboot. Multi-AZ minimizes but does not eliminate the interruption.
- Storage only grows - never shrinks. Set your maximum threshold deliberately.
- A CloudWatch alarm on `FreeStorageSpace` is not optional in production.
- Storage autoscaling has a 6-hour cooldown. Very fast-growing databases can outpace it.

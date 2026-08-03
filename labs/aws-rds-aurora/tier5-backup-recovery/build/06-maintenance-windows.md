# BUILD 06 - Maintenance Windows
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 25 minutes
**Goal:** View and modify the maintenance window, understand pending maintenance actions, and predict reboot and patching behavior for both single-AZ and Multi-AZ instances.

**Prerequisites:**
- An RDS PostgreSQL instance in `available` state
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export DB_INSTANCE="suta-t5-primary-hfa"
export AWS_REGION="us-east-1"
```

---

## Step 2 - View the Current Maintenance Window

### Console

1. Open **RDS > Databases**.
2. Click your instance.
3. Click the **Maintenance and backups** tab.
4. Look for **Maintenance window** under the Maintenance section.

It will show something like: `Sun:03:00-Sun:03:30` (UTC).

### CLI

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{MaintenanceWindow:PreferredMaintenanceWindow,BackupWindow:PreferredBackupWindow,MultiAZ:MultiAZ,AutoMinorVersionUpgrade:AutoMinorVersionUpgrade}' \
  --output table
```

Expected output (yours will differ):

```
--------------------------------------------------------------------
|                    DescribeDBInstances                           |
+------------------------------+-----------------------------------+
|  AutoMinorVersionUpgrade     |  True                             |
|  BackupWindow                |  08:00-09:00                      |
|  MaintenanceWindow           |  sun:03:00-sun:03:30              |
|  MultiAZ                     |  False                            |
+------------------------------+-----------------------------------+
```

> **Concept:** The maintenance window and backup window must NOT overlap. AWS enforces this. If you try to set them to the same time, the API returns an error.

---

## Step 3 - Modify the Maintenance Window

Choose a low-traffic time. For most teams, early Sunday morning UTC is safest.

### Console

1. Click your instance.
2. Click **Modify**.
3. Scroll to **Maintenance**.
4. Under **Auto minor version upgrade**, choose **Enable** or **Disable**.
5. Under **Maintenance window**, click **Select window**.
6. Choose a day and time (e.g., Sunday 03:00 - 03:30 UTC).
7. Click **Continue**.
8. Select **Apply immediately** or **Apply during next maintenance window**.
9. Click **Modify DB Instance**.

### CLI

Set the maintenance window to Sunday 04:00-04:30 UTC:

```bash
aws rds modify-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --preferred-maintenance-window "sun:04:00-sun:04:30" \
  --region $AWS_REGION
```

`--preferred-maintenance-window` uses this format: `ddd:hh24:mi-ddd:hh24:mi`.
Valid day values: `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`.
Time is always in UTC.

Note: This change does NOT require `--apply-immediately` because it is just a scheduling preference, not a database modification.

Expected output (yours will differ):

```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-t5-primary-hfa",
        "PreferredMaintenanceWindow": "sun:04:00-sun:04:30"
    }
}
```

Verify the change:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].PreferredMaintenanceWindow'
```

Expected output:

```
"sun:04:00-sun:04:30"
```

---

## Step 4 - View Pending Maintenance Actions

AWS queues maintenance actions that need to be applied. View the queue:

```bash
aws rds describe-pending-maintenance-actions \
  --region $AWS_REGION \
  --query 'PendingMaintenanceActions[*].{Resource:ResourceIdentifier,Actions:PendingMaintenanceActionDetails}' \
  --output json
```

If there are no pending actions, you will see:

```json
{
    "PendingMaintenanceActions": []
}
```

If there are pending actions (yours will differ):

```json
[
    {
        "Resource": "arn:aws:rds:us-east-1:123456789012:db:suta-t5-primary-hfa",
        "Actions": [
            {
                "Action": "system-update",
                "AutoAppliedAfterDate": "2025-06-15T00:00:00.000Z",
                "Description": "New Operating System update is available"
            }
        ]
    }
]
```

Pending action types:
- `system-update` - OS patch or security fix
- `db-upgrade` - engine version upgrade
- `hardware-maintenance` - underlying hardware needs replacement

`AutoAppliedAfterDate` is the date after which AWS will apply this action automatically during your maintenance window, whether you like it or not.

---

## Step 5 - Apply Pending Maintenance Immediately

If you have a pending action and want to apply it now instead of waiting for the maintenance window, you can force it.

> **Warning:** Applying immediately causes a reboot. For single-AZ instances, this means downtime of 1-5 minutes. For Multi-AZ, this causes a brief failover of 20-60 seconds.

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):db:${DB_INSTANCE}" \
  --apply-action system-update \
  --opt-in-type immediate \
  --region $AWS_REGION
```

`--apply-action` specifies which pending action to apply (use the exact `Action` value from Step 4).
`--opt-in-type immediate` means apply right now.
`--opt-in-type next-maintenance` applies it at the next maintenance window.
`--opt-in-type undo-opt-in` cancels a previously scheduled early application.

---

## Step 6 - Understand Reboot Behavior

### When Is a Reboot Required?

```
PARAMETER TYPES AND REBOOT REQUIREMENTS
=========================================

Dynamic parameter (e.g., work_mem, log_min_duration_statement):
- Change in parameter group takes effect immediately
- No reboot needed
- Status shows "in-sync"

Static parameter (e.g., max_connections, shared_buffers):
- Change is staged in parameter group
- Requires a reboot to take effect
- Status shows "pending-reboot" until rebooted

Engine version upgrade:
- Always requires a reboot (AWS handles this automatically)

OS patch:
- Requires a reboot (handled by AWS during maintenance window)
```

Check if your instance has parameters pending a reboot:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].DBParameterGroups'
```

Expected output:

```json
[
    {
        "DBParameterGroupName": "default.postgres15",
        "ParameterApplyStatus": "in-sync"
    }
]
```

If you see `pending-reboot`, a static parameter was changed and is waiting for a restart.

### Trigger a Manual Reboot

If you need to reboot (for example, to apply a static parameter change):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION
```

For a Multi-AZ instance, reboot with failover to minimize downtime:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier $DB_INSTANCE \
  --force-failover \
  --region $AWS_REGION
```

`--force-failover` promotes the standby to primary first, then reboots the old primary. Total downtime is the failover time (20-60 seconds) rather than the full reboot time (1-5 minutes).

---

## Step 7 - Understand OS Patching Behavior

### Single-AZ During Patching

```
Single-AZ Patching Timeline
=============================

03:00 UTC - Maintenance window opens
03:01 UTC - AWS begins OS patch
03:01 UTC - Instance goes offline (downtime starts)
            Application sees connection errors
03:04 UTC - Instance comes back online (downtime ends)
            ~3 minutes of downtime
03:30 UTC - Maintenance window closes
```

### Multi-AZ During Patching

```
Multi-AZ Patching Timeline
============================

03:00 UTC - Maintenance window opens
03:01 UTC - AWS patches STANDBY first (no impact to production)
03:04 UTC - Standby patching complete
03:04 UTC - Failover: standby becomes primary (20-60 sec blip)
            Application reconnects automatically
03:05 UTC - Old primary is now standby, gets patched
03:08 UTC - Both nodes patched, old primary returns as standby
03:30 UTC - Maintenance window closes

Total production impact: ~30 second failover event
```

> **Concept:** This is the primary reason to use Multi-AZ for any database that cannot tolerate several minutes of downtime for patching. Multi-AZ reduces OS patch downtime from 3-5 minutes to 20-60 seconds.

### Check Multi-AZ Status

```bash
aws rds describe-db-instances \
  --db-instance-identifier $DB_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{MultiAZ:MultiAZ,SecondaryAZ:SecondaryAvailabilityZone}' \
  --output table
```

If `MultiAZ: False`, you will experience full reboot downtime during patching. Consider enabling Multi-AZ for production databases.

---

## Step 8 - Prevent Surprise Maintenance

You cannot stop AWS from applying `required` maintenance. But you can:

1. Apply it yourself before the deadline (`opt-in-type immediate`)
2. Move your maintenance window to a better time
3. Use Multi-AZ to minimize impact
4. Set up CloudWatch Events to get notified when maintenance is upcoming

Set up an SNS notification for RDS maintenance events:

```bash
aws rds create-event-subscription \
  --subscription-name "rds-maintenance-alerts" \
  --sns-topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):your-alert-topic" \
  --source-type db-instance \
  --event-categories maintenance notification \
  --source-ids $DB_INSTANCE \
  --region $AWS_REGION
```

`--event-categories maintenance notification` subscribes to both maintenance and general notification events.
`--source-ids` limits alerts to this specific instance.

Replace `your-alert-topic` with an existing SNS topic ARN in your account.

---

## Summary

You can now:
- View the current maintenance window and backup window for any RDS instance
- Change the maintenance window to a time that fits your business
- View pending maintenance actions and understand the auto-apply deadline
- Apply pending maintenance immediately to avoid surprise downtime
- Explain the difference between dynamic and static parameter changes
- Describe how Multi-AZ reduces maintenance downtime from minutes to seconds
- Set up SNS notifications to receive advance warning of maintenance events

**You have completed all 6 BUILD guides for Tier 5.**

Continue to the USE exercises for hands-on practice with real scenarios.

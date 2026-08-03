# BUILD 06 - Maintenance Windows
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 25 minutes
**Goal:** View and modify the maintenance window, understand pending maintenance actions, and configure maintenance alerts.

**Prerequisites:**
- An Aurora PostgreSQL cluster in `available` state
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
```

---

## Step 2 - View the Current Maintenance Window

### Console

1. Open **RDS > Databases**.
2. Click your cluster.
3. Click the **Maintenance and backups** tab.
4. Look for **Maintenance window** under the Maintenance section.

### CLI

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{MaintenanceWindow:PreferredMaintenanceWindow,BackupWindow:PreferredBackupWindow}' \
  --output table
```

Expected output (yours will differ):

```
--------------------------------------------------------------------
|                    DescribeDBClusters                             |
+------------------------------+-----------------------------------+
|  BackupWindow                |  06:00-07:00                      |
|  MaintenanceWindow           |  sun:03:00-sun:03:30              |
+------------------------------+-----------------------------------+
```

> **Concept:** The maintenance window and backup window must NOT overlap. AWS enforces this. If you try to set them to the same time, the API returns an error.

---

## Step 3 - Modify the Maintenance Window

Choose a low-traffic time. For most teams, early Sunday morning UTC is safest.

### Console

1. Click your cluster.
2. Click **Modify**.
3. Scroll to **Maintenance**.
4. Under **Maintenance window**, click **Select window**.
5. Choose a day and time (e.g., Sunday 04:00 - 04:30 UTC).
6. Click **Continue**.
7. Click **Modify cluster**.

### CLI

Set the maintenance window to Sunday 04:00-04:30 UTC:

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --preferred-maintenance-window "sun:04:00-sun:04:30" \
  --region $AWS_REGION
```

`--preferred-maintenance-window` uses this format: `ddd:hh24:mi-ddd:hh24:mi`.
Valid day values: `mon`, `tue`, `wed`, `thu`, `fri`, `sat`, `sun`.
Time is always in UTC.

Note: This change does NOT cause a reboot - it is just a scheduling preference.

Expected output (yours will differ):

```json
{
    "DBCluster": {
        "DBClusterIdentifier": "devops-lab-cluster",
        "PreferredMaintenanceWindow": "sun:04:00-sun:04:30"
    }
}
```

Verify the change:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].PreferredMaintenanceWindow'
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

If there are no pending actions:

```json
{
    "PendingMaintenanceActions": []
}
```

If there are pending actions (yours will differ):

```json
[
    {
        "Resource": "arn:aws:rds:us-east-1:...:cluster:devops-lab-cluster",
        "Actions": [
            {
                "Action": "system-update",
                "AutoAppliedAfterDate": "2026-06-15T00:00:00.000Z",
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

`AutoAppliedAfterDate` is the deadline. After this date, AWS will apply the action automatically during your maintenance window.

---

## Step 5 - Apply Pending Maintenance Immediately

If you have a pending action and want to apply it now:

> **Warning:** Applying immediately causes a restart. For Aurora clusters with reader instances, the impact is reduced because readers can serve traffic during the writer restart.

```bash
aws rds apply-pending-maintenance-action \
  --resource-identifier "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_ID}" \
  --apply-action system-update \
  --opt-in-type immediate \
  --region $AWS_REGION
```

`--apply-action` specifies which pending action to apply.
`--opt-in-type immediate` means apply right now.
`--opt-in-type next-maintenance` applies it at the next maintenance window.
`--opt-in-type undo-opt-in` cancels a previously scheduled early application.

---

## Step 6 - Understand Patching with Reader Instances

Aurora clusters with reader instances handle maintenance more gracefully:

```
Aurora Cluster Patching with Reader Instance
===============================================

03:00 UTC - Window opens
03:01 UTC - AWS patches reader instance first (no write impact)
03:04 UTC - Reader restart complete
03:04 UTC - Failover: reader promotes to writer (~30 sec blip)
03:05 UTC - Old writer restarts with patch applied
03:08 UTC - Both instances running with patch
03:30 UTC - Window closes

Total write impact: ~30 second failover
Total read impact: Reader offline for ~3 minutes, then writer
                   offline for ~30 seconds during failover
```

Check if your cluster has reader instances:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,IsWriter:IsClusterWriter}'
```

Expected output (yours will differ):

```json
[
    {
        "Instance": "devops-lab-cluster-instance-1",
        "IsWriter": true
    },
    {
        "Instance": "devops-lab-cluster-reader-1",
        "IsWriter": false
    }
]
```

If you only have a writer instance (no readers), maintenance will cause full downtime during the writer restart.

---

## Step 7 - Set Up Maintenance Alerts

Create an SNS notification for maintenance events so you never miss an upcoming window:

```bash
aws rds create-event-subscription \
  --subscription-name "rds-maintenance-alerts" \
  --sns-topic-arn "arn:aws:sns:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):your-alert-topic" \
  --source-type db-cluster \
  --event-categories maintenance notification \
  --source-ids $CLUSTER_ID \
  --region $AWS_REGION
```

`--event-categories maintenance notification` subscribes to both maintenance and general notification events.
`--source-ids` limits alerts to this specific cluster.

Replace `your-alert-topic` with an existing SNS topic ARN in your account.

---

## Summary

You can now:
- View the current maintenance window and backup window for an Aurora cluster
- Change the maintenance window to a time that fits your business
- View pending maintenance actions and understand the auto-apply deadline
- Apply pending maintenance immediately to control when downtime occurs
- Explain how Aurora clusters with reader instances reduce maintenance downtime
- Set up SNS notifications to receive advance warning of maintenance events

**You have completed all 6 BUILD guides for Module 06.**

Continue to the USE exercises for hands-on practice with real scenarios.

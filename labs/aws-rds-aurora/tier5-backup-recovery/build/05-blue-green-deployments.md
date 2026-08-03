# BUILD 05 - Blue/Green Deployments
## Tier 5 - Backup, Recovery, and Lifecycle

**Time:** 50 minutes
**Goal:** Create a Blue/Green deployment, understand the logical replication behind it, monitor replication lag, execute a switchover, and clean up the old blue environment.

**Cost Warning:** A Blue/Green deployment runs two full instances simultaneously. At db.t3.micro pricing, this roughly doubles your instance cost for the duration of the lab. Delete the blue environment promptly after switchover.

**Prerequisites:**
- An RDS PostgreSQL instance (Blue) with automated backups enabled
- Backup retention period of at least 1 day (required for Blue/Green)
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export BLUE_INSTANCE="suta-t5-primary-hfa"
export BG_DEPLOYMENT_NAME="suta-t5-bg-deploy"
export AWS_REGION="us-east-1"
```

---

## Step 2 - Verify Prerequisites for Blue/Green

Blue/Green deployments have specific requirements. Check them before creating.

```bash
aws rds describe-db-instances \
  --db-instance-identifier $BLUE_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Engine:Engine,EngineVersion:EngineVersion,BackupRetention:BackupRetentionPeriod,MultiAZ:MultiAZ,AutoMinorVersionUpgrade:AutoMinorVersionUpgrade}' \
  --output table
```

Expected output (yours will differ):

```
---------------------------------------------------------
|               DescribeDBInstances                     |
+-------------------------------+-----------------------+
|  AutoMinorVersionUpgrade      |  true                 |
|  BackupRetention              |  14                   |
|  Engine                       |  postgres             |
|  EngineVersion                |  15.6                 |
|  MultiAZ                      |  false                |
+-------------------------------+-----------------------+
```

Requirements:
- Engine: `postgres` (standard RDS) or `aurora-postgresql` (Aurora)
- BackupRetention: must be > 0 (backups must be enabled)
- The instance must be in `available` state

> **Concept:** Blue/Green uses logical replication under the hood. Logical replication in PostgreSQL requires `wal_level = logical`. AWS sets this automatically when you create a Blue/Green deployment. You do not need to change it manually.

---

## Step 3 - Understand the Architecture Before Creating

```
Blue/Green Deployment Architecture
====================================

[Application] --> [Blue DB Endpoint]
                       |
                       | Logical Replication (AWS managed)
                       | (same writes replicated to green)
                       v
                  [Green DB Endpoint]
                  (staging - receives replicated writes)

During this phase:
- All application traffic goes to Blue
- Green receives every write from Blue via logical replication
- Green can have a different engine version, parameter group, schema changes
- Green is NOT accessible by your application yet (you control when to switch)

After switchover:
[Application] --> [Green DB Endpoint]  (Green is now production)
                  [Blue DB Endpoint]   (Blue becomes standby, then deleted)
```

---

## Step 4 - Create the Blue/Green Deployment

### Console

1. Open **RDS > Databases**.
2. Click your Blue instance.
3. Click **Actions > Create Blue/Green deployment**.
4. Enter a name: `suta-t5-bg-deploy`.
5. Under **Green DB instance settings**, you can optionally:
   - Select a different engine version (e.g., upgrade from 15.6 to 16.2)
   - Select a different DB instance class
   - Select a different parameter group
6. Leave other settings as default for this lab.
7. Click **Create Blue/Green deployment**.

### CLI

Create with the same engine version (non-upgrade scenario):

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_DEPLOYMENT_NAME \
  --source $BLUE_INSTANCE \
  --region $AWS_REGION
```

`--source` is the Blue (current production) instance identifier or ARN.
`--blue-green-deployment-name` is a label for this deployment pair.

To create with a version upgrade on Green (the main use case for major upgrades):

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_DEPLOYMENT_NAME \
  --source $BLUE_INSTANCE \
  --target-engine-version "16.2" \
  --region $AWS_REGION
```

`--target-engine-version` sets the version for the Green environment. Leave it out to use the same version as Blue.

Expected output (yours will differ):

```json
{
    "BlueGreenDeployment": {
        "BlueGreenDeploymentIdentifier": "bgd-abc123def456",
        "BlueGreenDeploymentName": "suta-t5-bg-deploy",
        "Status": "PROVISIONING",
        "Source": "arn:aws:rds:us-east-1:...:db:suta-t5-primary-hfa"
    }
}
```

Store the deployment ID:

```bash
export BG_DEPLOY_ID=$(aws rds describe-blue-green-deployments \
  --region $AWS_REGION \
  --query "BlueGreenDeployments[?BlueGreenDeploymentName=='${BG_DEPLOYMENT_NAME}'].BlueGreenDeploymentIdentifier" \
  --output text)

echo "Deployment ID: $BG_DEPLOY_ID"
```

---

## Step 5 - Monitor Deployment Status

The Blue/Green deployment goes through several states. Monitor it:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].{Status:Status,CreateTime:CreateTime,Target:Target}' \
  --output table
```

Status progression:

```
PROVISIONING -> AVAILABLE
```

`PROVISIONING` means AWS is:
1. Creating the Green instance
2. Setting up logical replication from Blue to Green
3. Performing initial data sync

This can take 10-30 minutes for small instances. Larger databases take longer for the initial sync.

Wait for the deployment to reach `AVAILABLE` status:

```bash
aws rds wait blue-green-deployment-available \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION
```

---

## Step 6 - Monitor Replication Lag Between Blue and Green

Replication lag is critical. Switchover is only safe when lag is near zero.

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].{Status:Status,SwitchoverDetails:SwitchoverDetails}' \
  --output json
```

Expected output (yours will differ):

```json
{
    "Status": "AVAILABLE",
    "SwitchoverDetails": [
        {
            "SourceMember": "arn:aws:rds:...suta-t5-primary-hfa",
            "TargetMember": "arn:aws:rds:...suta-t5-primary-hfa-green-abc123",
            "Status": "AVAILABLE"
        }
    ]
}
```

To check actual replication lag, connect to the Green instance and query replication statistics.

First, get the Green instance endpoint:

```bash
export GREEN_INSTANCE=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].SwitchoverDetails[0].TargetMember' \
  --output text | awk -F: '{print $NF}' | sed 's|db/||')

echo "Green instance: $GREEN_INSTANCE"

export GREEN_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $GREEN_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo "Green endpoint: $GREEN_HOST"
```

Connect to the Green instance and check replication lag:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

Expected output (yours will differ):

```
 replication_lag
-----------------
 00:00:00.124312
(1 row)
```

Lag under 1 second is excellent. Lag over 5 seconds is concerning. Lag over 30 seconds means you should wait before switching over.

> **Concept:** Replication lag exists because WAL records are generated on Blue and must be transmitted to Green and applied there. Network latency and write volume both affect lag. Heavy write workloads on Blue can cause Green to fall behind.

---

## Step 7 - Apply Schema Changes to Green (Optional)

One advantage of Blue/Green is that you can make schema changes to Green before switchover. These changes replicate backward from Green to Blue during the pre-switchover phase only if the changes are backward compatible.

Connect to Green and add a non-breaking schema change:

```bash
psql -h $GREEN_HOST -U postgres -d postgres
```

```sql
-- Add a nullable column (non-breaking change, backward compatible)
ALTER TABLE products ADD COLUMN IF NOT EXISTS last_reviewed_at TIMESTAMPTZ;

-- Verify the column exists on green
\d products
```

Exit:

```sql
\q
```

> **Note:** Complex schema changes like changing column types or dropping columns should be done carefully. Logical replication can break if the schema change is not backward compatible with what Blue is writing.

---

## Step 8 - Execute the Switchover

Before switching over, run a final lag check:

```bash
psql -h $GREEN_HOST -U postgres -d postgres \
  -c "SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;"
```

If lag is under 1 second, you are ready to switchover.

### Console

1. Open **RDS > Databases**.
2. Click **Blue/green deployments** in the left menu.
3. Select your deployment.
4. Click **Switch over**.
5. Review the summary - it shows Blue and Green endpoints.
6. AWS will prompt you to confirm. Click **Switch over**.

### CLI

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
{
    "BlueGreenDeployment": {
        "Status": "SWITCHOVER_IN_PROGRESS",
        "BlueGreenDeploymentName": "suta-t5-bg-deploy"
    }
}
```

### What Happens During Switchover

```
Switchover Sequence (typically under 60 seconds)
==================================================

1. AWS stops new writes to Blue (brief write pause)
2. Green applies any remaining replication lag (catch-up)
3. AWS updates the DNS endpoint to point to Green
4. Green becomes the new primary (accepts writes)
5. Blue becomes a read-only former primary

Your application:
- Connections to the OLD Blue endpoint are redirected to Green
- Applications that retry on connection failure reconnect automatically
- Applications that do NOT retry may see a brief error during switchover
```

Monitor the switchover:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].Status'
```

Status progression:

```
SWITCHOVER_IN_PROGRESS -> SWITCHOVER_COMPLETED
```

---

## Step 9 - Verify the Switchover

After switchover, the Green instance now has the original Blue DNS name. Verify:

```bash
aws rds describe-db-instances \
  --db-instance-identifier $BLUE_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].{Status:DBInstanceStatus,Engine:Engine,EngineVersion:EngineVersion}' \
  --output table
```

If you upgraded the engine version on Green, the `EngineVersion` should now show the new version.

Connect to the original Blue endpoint (which now points to Green):

```bash
export BLUE_HOST=$(aws rds describe-db-instances \
  --db-instance-identifier $BLUE_INSTANCE \
  --region $AWS_REGION \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

psql -h $BLUE_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

The version shown should be the Green version (if you upgraded).

---

## Step 10 - Rollback (If Needed)

If switchover reveals a problem, you can switch back to the original Blue environment while it still exists.

Check if Blue is still available:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].{Status:Status,SwitchoverDetails:SwitchoverDetails}'
```

To switch back (if the deployment is in `SWITCHOVER_COMPLETED` state and Blue still exists):

```bash
aws rds switchover-blue-green-deployment \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION
```

> **Important:** Once you delete the Blue environment (Step 11), rollback is no longer possible. Keep Blue running for at least 24 hours after switchover before deleting it, unless you have tested thoroughly.

---

## Step 11 - Cleanup - Delete the Old Blue Environment

After you have confirmed Green is working correctly, delete the Blue/Green deployment. This deletes the OLD Blue instance (not the new primary).

### Console

1. Go to **RDS > Blue/green deployments**.
2. Select your deployment.
3. Click **Delete**.
4. Select **Delete source (Blue)** to delete the old Blue instance.
5. Confirm and click **Delete**.

### CLI

```bash
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --delete-target \
  --region $AWS_REGION
```

`--delete-target` in this context deletes the OLD Blue environment (the source, which is now the standby after switchover).

> **Concept:** The naming can be confusing after switchover. After switchover, what was "Green" is now running as the production instance using the Blue DNS name. What was "Blue" is now the old standby. `--delete-target` deletes the old Blue standby, not the production instance.

Wait for deletion:

```bash
aws rds wait blue-green-deployment-deleted \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION
```

Confirm the deployment is gone:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION 2>&1 | head -3
```

Expected output:

```
An error occurred (BlueGreenDeploymentNotFoundFault) when calling the DescribeBlueGreenDeployments operation.
```

---

## Summary

You can now:
- Create a Blue/Green deployment with or without a version upgrade on Green
- Monitor replication lag between Blue and Green
- Apply schema changes to Green before switchover
- Execute a switchover (typically under 60 seconds of write pause)
- Explain the rollback option and when it becomes unavailable
- Delete the old Blue environment after successful switchover

**Key advantage of Blue/Green over in-place upgrade:** If the upgrade or schema change breaks your application, you can switch back to Blue without waiting for a snapshot restore. The old Blue is still there and fully operational.

---

## Recent Improvements to Blue/Green Deployments

AWS has significantly improved Blue/Green deployments since the initial launch. Here are the updates you should know about:

### Sub-5-Second Switchover Downtime (January 2026)

AWS reduced the switchover write pause from approximately 60 seconds to under 5 seconds for most workloads. This means:
- Applications experience less than 5 seconds of write unavailability during switchover
- Read traffic continues uninterrupted throughout the switchover
- No application code changes needed - the improvement is automatic

The sub-5s downtime applies to both RDS PostgreSQL and Aurora PostgreSQL Blue/Green deployments. Heavy write workloads (thousands of writes per second) may see slightly longer pauses as replication catch-up takes more time.

### RDS Proxy Integration (April 2026)

Blue/Green deployments now integrate with RDS Proxy. Previously, if your application connected through RDS Proxy, the switchover would break Proxy connections and require manual reconfiguration.

Now:
- RDS Proxy automatically follows the Blue/Green switchover
- Proxy connections are preserved - clients see a brief pause but do not need to reconnect
- Proxy pinning is handled automatically during the transition

To create a Blue/Green deployment with RDS Proxy:

```bash
# No special flags needed - if your Blue instance has an RDS Proxy attached,
# the Blue/Green deployment automatically handles the Proxy switchover
aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_DEPLOYMENT_NAME \
  --source $BLUE_INSTANCE \
  --region $AWS_REGION
```

### Aurora Global Database Support (November 2025)

Blue/Green deployments now work with Aurora Global Database clusters. This is significant because Global Database upgrades previously required detaching secondary regions, upgrading each cluster independently, and re-attaching.

Now:
- Create a Blue/Green deployment on the Global Database primary
- The Green environment replicates across all secondary regions
- Switchover updates all regions simultaneously
- Secondary regions continue serving reads during switchover

```bash
# For Aurora Global Database Blue/Green
aws rds create-blue-green-deployment \
  --blue-green-deployment-name my-global-bg-deploy \
  --source arn:aws:rds:us-east-1:123456789012:cluster:my-global-primary \
  --target-engine-version "16.6" \
  --region us-east-1
```

> **Important:** Global Database Blue/Green deployments take longer to provision because the Green environment must be replicated to all secondary regions. Plan for 30-60 minutes of provisioning time depending on database size and number of secondary regions.

---

**Next:** BUILD 06 - Maintenance Windows

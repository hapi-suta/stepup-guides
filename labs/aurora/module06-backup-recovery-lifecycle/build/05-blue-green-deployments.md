# BUILD 05 - Blue/Green Deployments
## Module 06 - Backup, Recovery, and Lifecycle

**Time:** 50 minutes
**Goal:** Create a Blue/Green deployment for an Aurora cluster, understand the logical replication behind it, monitor replication lag, execute a switchover, and clean up the old blue environment.

**Cost Warning:** A Blue/Green deployment runs two full clusters simultaneously. This roughly doubles your cluster cost for the duration. Delete the old environment promptly after switchover.

**Prerequisites:**
- An Aurora PostgreSQL cluster (Blue) with automated backups enabled
- Backup retention period of at least 1 day
- AWS CLI configured with rds permissions

---

## Step 1 - Set Your Variables

```bash
export CLUSTER_ID="devops-lab-cluster"
export BG_DEPLOYMENT_NAME="devops-lab-bg-deploy"
export AWS_REGION="us-east-1"
```

---

## Step 2 - Verify Prerequisites for Blue/Green

Blue/Green deployments have specific requirements. Check them before creating.

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].{Engine:Engine,EngineVersion:EngineVersion,BackupRetention:BackupRetentionPeriod,Status:Status}' \
  --output table
```

Expected output (yours will differ):

```
---------------------------------------------------------
|               DescribeDBClusters                      |
+-------------------------------+-----------------------+
|  BackupRetention              |  14                   |
|  Engine                       |  aurora-postgresql     |
|  EngineVersion                |  16.2                 |
|  Status                       |  available            |
+-------------------------------+-----------------------+
```

Requirements:
- Engine: `aurora-postgresql`
- BackupRetention: must be > 0 (backups must be enabled)
- Status: must be `available`

> **Concept:** Blue/Green uses logical replication under the hood. Logical replication in PostgreSQL requires `wal_level = logical`. AWS sets this automatically when you create a Blue/Green deployment. You do not need to change it manually.

---

## Step 3 - Understand the Architecture Before Creating

```
Blue/Green Deployment Architecture
====================================

[Application] --> [Blue Cluster Endpoint]
                       |
                       | Logical Replication (AWS managed)
                       | (same writes replicated to green)
                       v
                  [Green Cluster Endpoint]
                  (staging - receives replicated writes)

During this phase:
- All application traffic goes to Blue
- Green receives every write from Blue via logical replication
- Green can have a different engine version or parameter group
- Green is NOT accessible by your application yet

After switchover:
[Application] --> [Green Cluster Endpoint]  (Green is now production)
                  [Blue Cluster Endpoint]   (Blue becomes standby)
```

---

## Step 4 - Create the Blue/Green Deployment

### Console

1. Open **RDS > Databases**.
2. Click your Blue cluster.
3. Click **Actions > Create Blue/Green deployment**.
4. Enter a name: `devops-lab-bg-deploy`.
5. Optionally select a different engine version for Green.
6. Click **Create Blue/Green deployment**.

### CLI

Create with the same engine version (testing the switchover process):

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_DEPLOYMENT_NAME \
  --source "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_ID}" \
  --region $AWS_REGION
```

`--source` is the Blue (current production) cluster ARN.
`--blue-green-deployment-name` is a label for this deployment pair.

To create with a version upgrade on Green:

```bash
aws rds create-blue-green-deployment \
  --blue-green-deployment-name $BG_DEPLOYMENT_NAME \
  --source "arn:aws:rds:${AWS_REGION}:$(aws sts get-caller-identity --query Account --output text):cluster:${CLUSTER_ID}" \
  --target-engine-version "16.4" \
  --region $AWS_REGION
```

`--target-engine-version` sets the version for the Green environment.

Expected output (yours will differ):

```json
{
    "BlueGreenDeployment": {
        "BlueGreenDeploymentIdentifier": "bgd-abc123def456",
        "BlueGreenDeploymentName": "devops-lab-bg-deploy",
        "Status": "PROVISIONING",
        "Source": "arn:aws:rds:us-east-1:...:cluster:devops-lab-cluster"
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
  --query 'BlueGreenDeployments[0].{Status:Status,CreateTime:CreateTime}' \
  --output table
```

Status progression:

```
PROVISIONING -> AVAILABLE
```

`PROVISIONING` means AWS is:
1. Creating the Green cluster
2. Setting up logical replication from Blue to Green
3. Performing initial data sync

This can take 10-30 minutes for small clusters.

Wait for the deployment to reach `AVAILABLE`:

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
            "SourceMember": "arn:aws:rds:...devops-lab-cluster",
            "TargetMember": "arn:aws:rds:...devops-lab-cluster-green-abc123",
            "Status": "AVAILABLE"
        }
    ]
}
```

Get the Green cluster endpoint and check replication lag:

```bash
export GREEN_CLUSTER=$(aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].SwitchoverDetails[0].TargetMember' \
  --output text | awk -F: '{print $NF}' | sed 's|cluster/||')

echo "Green cluster: $GREEN_CLUSTER"

export GREEN_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $GREEN_CLUSTER \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

echo "Green endpoint: $GREEN_HOST"
```

Connect to Green and check replication lag:

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

> **Concept:** Replication lag exists because changes must be generated on Blue, transmitted to Green, and applied there. Network latency and write volume both affect lag. Heavy write workloads on Blue can cause Green to fall behind.

---

## Step 7 - Execute the Switchover

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
5. Review the summary. Click **Switch over** to confirm.

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
        "BlueGreenDeploymentName": "devops-lab-bg-deploy"
    }
}
```

### What Happens During Switchover

```
Switchover Sequence (typically under 60 seconds)
==================================================

1. AWS stops new writes to Blue (brief write pause)
2. Green catches up on any remaining replication lag
3. AWS updates the DNS endpoint to point to Green
4. Green becomes the new primary (accepts writes)
5. Blue becomes read-only standby

Your application:
- Same cluster endpoint hostname resolves to Green now
- Applications that retry on connection failure reconnect automatically
- Applications without retry logic may see brief errors
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

## Step 8 - Verify the Switchover

After switchover, the original Blue endpoint now resolves to Green. Verify:

```bash
export CLUSTER_HOST=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --region $AWS_REGION \
  --query 'DBClusters[0].Endpoint' \
  --output text)

psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT version();"
```

If you upgraded the engine version on Green, the version should now show the new version.

Verify your data is intact:

```bash
psql -h $CLUSTER_HOST -U postgres -d postgres \
  -c "SELECT schemaname, tablename, n_live_tup FROM pg_stat_user_tables ORDER BY tablename;"
```

---

## Step 9 - Rollback (If Needed)

If switchover reveals a problem, you can switch back while Blue still exists:

```bash
aws rds describe-blue-green-deployments \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --region $AWS_REGION \
  --query 'BlueGreenDeployments[0].Status'
```

> **Important:** Once you delete the old Blue environment (Step 10), rollback is no longer possible. Keep Blue running for at least 24 hours after switchover before deleting, unless you have tested thoroughly.

---

## Step 10 - Cleanup - Delete the Old Blue Environment

After confirming Green is working correctly, delete the deployment. This deletes the OLD Blue cluster.

### Console

1. Go to **RDS > Blue/green deployments**.
2. Select your deployment.
3. Click **Delete**.
4. Select to delete the source (Blue) resources.
5. Confirm and click **Delete**.

### CLI

```bash
aws rds delete-blue-green-deployment \
  --blue-green-deployment-identifier $BG_DEPLOY_ID \
  --delete-target \
  --region $AWS_REGION
```

`--delete-target` deletes the old Blue environment after switchover.

> **Concept:** After switchover, what was "Green" now runs as production using the original Blue DNS name. What was "Blue" is the old standby. `--delete-target` deletes the old Blue standby, not the production cluster.

---

## Summary

You can now:
- Create a Blue/Green deployment with or without a version upgrade on Green
- Monitor replication lag between Blue and Green
- Execute a switchover (typically under 60 seconds of write pause)
- Explain the rollback option and when it becomes unavailable
- Delete the old Blue environment after successful switchover

**Key advantage of Blue/Green over in-place upgrade:** If the upgrade or schema change breaks your application, you can switch back to Blue without waiting for a snapshot restore. The old Blue is still there and fully operational.

**Next:** BUILD 06 - Maintenance Windows

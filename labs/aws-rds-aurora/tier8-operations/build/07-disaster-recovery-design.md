# Tier 8 - Build Guide 07: Disaster Recovery Design

**Objective:** Define RTO/RPO targets for database workload tiers, execute an Aurora Global Database failover drill end-to-end, configure cross-region snapshot replication, and establish a DR testing schedule with automation.
**Time:** 45 minutes
**Level:** Expert
**infra_required:** true (for failover drill sections) | false (for design and planning sections)
**Prerequisites:** An Aurora PostgreSQL cluster. For Global Database sections: an Aurora Global Database with at least one secondary region. AWS CLI configured for both primary and secondary regions.

---

## 1. Define RTO/RPO Targets for Workload Tiers

RTO and RPO targets are business decisions. As a DBA or architect, your job is to present the cost and technical options, then implement whatever the business commits to.

### The RTO/RPO conversation with stakeholders

Use this framing when discussing DR requirements with business stakeholders:

- **RTO question:** "If this database became unavailable right now, how long could the business operate before it caused unacceptable financial, operational, or reputational damage?"
- **RPO question:** "If this database had to be restored from a backup, how much data loss could the business absorb? What is the maximum age of a backup we could restore without causing unacceptable consequences?"

The answers drive the architecture. Do not let business stakeholders dictate RTO/RPO without understanding the cost. Show them the cost curve.

### Tiered DR requirements reference

Define tiers based on business criticality. Adjust for your organization.

**Tier 1 - Mission Critical**

Examples: Payment processing, authentication, real-time fraud detection, trading systems.

| Target | Value | Architecture Required |
|--------|-------|----------------------|
| RTO | < 1 minute | Aurora Global Database, automatic failover |
| RPO | 0 (zero loss) | Synchronous Multi-AZ within region; Global Database for cross-region |
| Availability | 99.99% | Multi-AZ + read replicas + RDS Proxy |

Cost implication: Aurora Global Database + Multi-AZ in primary region + Multi-AZ in secondary region = 4x+ instance cost compared to a single-AZ deployment.

**Tier 2 - Business Critical**

Examples: Order management, customer records, core product APIs, billing.

| Target | Value | Architecture Required |
|--------|-------|----------------------|
| RTO | < 15 minutes | Aurora Multi-AZ, automated failover |
| RPO | < 1 minute | Aurora synchronous replication within the cluster |
| Availability | 99.95% | Multi-AZ Aurora cluster |

**Tier 3 - Important**

Examples: Reporting databases, analytics warehouses, search indexes, recommendation systems.

| Target | Value | Architecture Required |
|--------|-------|----------------------|
| RTO | < 1 hour | Multi-AZ with manual failover option |
| RPO | < 15 minutes | Automated backup + cross-region snapshot copy |
| Availability | 99.9% | Multi-AZ or single-AZ with frequent snapshots |

**Tier 4 - Standard**

Examples: Internal tools, staging environments, partner portals, batch job databases.

| Target | Value | Architecture Required |
|--------|-------|----------------------|
| RTO | < 4 hours | Single-AZ with snapshot restore |
| RPO | < 1 hour | Automated daily backup |
| Availability | 99.5% | Single-AZ |

### Communicate design cost to stakeholders

Present this as a cost ladder:

```
Tier 1 (RTO < 1 min): $X/month
Tier 2 (RTO < 15 min): $X/3 month (approximately 1/3 of Tier 1 cost)
Tier 3 (RTO < 1 hour): $X/8 month
Tier 4 (RTO < 4 hours): $X/20 month
```

When a business stakeholder asks for "Tier 1 performance at Tier 4 price," the answer is no - and this ladder makes that concrete.

---

## 2. Aurora Global Database Failover Drill

An Aurora Global Database has one primary region (read/write) and up to five secondary regions (read-only). A managed planned failover promotes a secondary region to primary with near-zero RPO and RTO under 1 minute.

### Before the drill: document the current state

```bash
# Record the current primary region cluster
aws rds describe-global-clusters \
  --region [PRIMARY-REGION] \
  --query 'GlobalClusters[*].{ID:GlobalClusterIdentifier,Status:Status,Members:GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}}' \
  --output json
```

Record:
- Primary cluster ARN and region
- Secondary cluster ARN and region
- Current cluster endpoint for the primary

Also record the current application connection string. After the drill, you will update it.

### Verify replication lag before starting

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBReplicatedWriteIO \
  --dimensions Name=DBClusterIdentifier,Value=[SECONDARY-CLUSTER-ID] \
  --start-time $(date -u -v-5M +%Y-%m-%dT%H:%M:%SZ) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --period 60 \
  --statistics Sum \
  --region [SECONDARY-REGION]
```

Also check the `AuroraGlobalDBDataTransferBytes` metric. If lag is high, wait for it to catch up before initiating the failover to minimize RPO.

### Execute the managed planned failover (Console)

1. Open the RDS console in the **primary region**.
2. Click **Global databases** in the left navigation.
3. Select your global database identifier.
4. Click **Actions > Fail over global database**.
5. Select the secondary region cluster you want to promote to primary.
6. Click **Fail over global database** to confirm.
7. Record the start time: this is T0 for your RTO measurement.

### Execute the managed planned failover (CLI)

```bash
# Get the global cluster identifier
aws rds describe-global-clusters \
  --region [PRIMARY-REGION] \
  --query 'GlobalClusters[0].GlobalClusterIdentifier' \
  --output text

# Initiate the failover
aws rds failover-global-cluster \
  --global-cluster-identifier [GLOBAL-CLUSTER-ID] \
  --target-db-cluster-identifier [SECONDARY-CLUSTER-ARN] \
  --region [PRIMARY-REGION]
```

`--target-db-cluster-identifier` is the full ARN of the secondary cluster you want to become the new primary.

Record T0: the time you ran this command.

### Monitor the failover progress

```bash
# Poll until the failover completes
watch -n 5 'aws rds describe-global-clusters \
  --region [SECONDARY-REGION] \
  --query "GlobalClusters[*].{Status:Status,Members:GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}}" \
  --output table'
```

Watch for:
1. The secondary cluster's `IsWriter` changing from `false` to `true`
2. The global cluster status returning to `available`

Record T3: the time the secondary cluster becomes the writer. RTO = T3 - T0.

### Update application connection strings

After the failover, the old primary region cluster endpoint is no longer the writer. The new primary region cluster has a new endpoint.

Get the new primary endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [NEW-PRIMARY-CLUSTER-ID] \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region [SECONDARY-REGION]
```

Update your application's database connection string to point to the new primary. In a Route 53 CNAME-based architecture, update the DNS record instead:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id [HOSTED-ZONE-ID] \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "db.internal.[COMPANY].com",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "[NEW-PRIMARY-ENDPOINT]"}]
      }
    }]
  }'
```

Record T4: the time your application confirms end-to-end health.

**Final RTO measurement:** T4 - T0.

### After the drill: fail back to the original primary region

Failing back is the same process in reverse. The original primary region cluster is now a secondary. Use the same `failover-global-cluster` command targeting the original primary cluster ARN.

---

## 3. Cross-Region Snapshot Strategy

For Tier 3 and Tier 4 workloads, cross-region snapshot copy provides a lower-cost DR option than Global Database.

### Enable automated cross-region snapshot copy (Console)

1. Open the RDS console in the primary region.
2. Select **Automated backups** in the left navigation.
3. Click the backup entry for your instance.
4. Click **Copy snapshot** or use the **Actions** dropdown.
5. To automate this, use the **Manage cross-region replication** option if available (Aurora clusters have this option directly).

For Aurora, enable cross-region snapshot copy at the cluster level:

**CLI:**
```bash
aws rds start-activity-stream \
  --region [PRIMARY-REGION]
```

For cross-region backup copy, configure it at the cluster:

```bash
# Enable automated backup replication to a secondary region
aws rds enable-cross-region-automated-backups \
  --db-cluster-identifier [CLUSTER-ID] \
  --backup-replication-region [SECONDARY-REGION] \
  --region [PRIMARY-REGION]
```

Note: This feature availability varies by region and account. Verify current AWS documentation for the exact API.

### Manual cross-region snapshot copy (CLI)

For RDS instances, copy a snapshot manually to a secondary region:

```bash
# Get the latest automated snapshot ARN
SNAPSHOT_ARN=$(aws rds describe-db-snapshots \
  --db-instance-identifier [INSTANCE-ID] \
  --snapshot-type automated \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-1].DBSnapshotArn' \
  --output text \
  --region [PRIMARY-REGION])

echo "Copying snapshot: $SNAPSHOT_ARN"

# Copy it to the secondary region
aws rds copy-db-snapshot \
  --source-db-snapshot-identifier "$SNAPSHOT_ARN" \
  --target-db-snapshot-identifier [INSTANCE-ID]-dr-$(date +%Y%m%d) \
  --source-region [PRIMARY-REGION] \
  --kms-key-id [KMS-KEY-ID-IN-SECONDARY-REGION] \
  --region [SECONDARY-REGION]
```

`--kms-key-id` is required because the encryption key in the primary region cannot be used in the secondary region - you need a KMS key in the secondary region.

### Automate snapshot copy with EventBridge

Create an EventBridge rule that triggers on new automated snapshot creation and copies it to the secondary region:

The Lambda function (conceptual - deploy via your IaC):

```python
import boto3
import os

def handler(event, context):
    primary_region = os.environ['PRIMARY_REGION']
    secondary_region = os.environ['SECONDARY_REGION']
    kms_key_id = os.environ['SECONDARY_KMS_KEY_ID']

    snapshot_arn = event['detail']['SourceArn']
    snapshot_id = event['detail']['SourceIdentifier']

    rds = boto3.client('rds', region_name=secondary_region)

    response = rds.copy_db_snapshot(
        SourceDBSnapshotIdentifier=snapshot_arn,
        TargetDBSnapshotIdentifier=f"{snapshot_id}-dr-copy",
        SourceRegion=primary_region,
        KmsKeyId=kms_key_id,
        CopyTags=True
    )

    return {'status': 'copy initiated', 'snapshot': response['DBSnapshot']['DBSnapshotIdentifier']}
```

---

## 4. DR Testing Schedule and Automation

### DR testing requirements by tier

| Tier | Test Frequency | Test Type | Participants |
|------|---------------|-----------|-------------|
| Tier 1 | Quarterly | Full failover drill with application verification | DBA, App team, On-call |
| Tier 2 | Semi-annually | Failover drill | DBA, On-call |
| Tier 3 | Annually | Snapshot restore to secondary region | DBA |
| Tier 4 | Annually or on major changes | Snapshot restore | DBA |

### DR test checklist template

Use this checklist for every DR test:

```
DR TEST CHECKLIST
Date: [DATE]
Workload: [WORKLOAD NAME]
Primary Region: [REGION]
Secondary Region: [REGION]
Participants: [NAMES]

PRE-TEST
[ ] All participants briefed on the test plan
[ ] Current primary endpoint documented: [ENDPOINT]
[ ] Application baseline health confirmed (error rate, latency)
[ ] Replication lag confirmed < [TARGET]: [ACTUAL LAG]
[ ] Test window communicated to stakeholders

FAILOVER
[ ] T0 (failover initiated): [TIME]
[ ] T1 (first health check failure detected): [TIME]
[ ] T2 (new primary accepting connections): [TIME]
[ ] T3 (application connection string updated): [TIME]
[ ] T4 (application confirmed healthy): [TIME]

MEASUREMENTS
[ ] RTO (T4 - T0): [MINUTES]
[ ] RPO (data loss, if any): [SECONDS/MINUTES]
[ ] RTO vs target ([TARGET]): PASS / FAIL

POST-TEST
[ ] All application traffic routing correctly to new primary
[ ] Failback initiated
[ ] Failback completed
[ ] Original architecture restored and verified

FINDINGS
[ ] RTO met: YES / NO
[ ] RPO met: YES / NO
[ ] Issues encountered: [DESCRIPTION]
[ ] Action items: [LIST]
```

### Automate DR test scheduling with EventBridge

Create an EventBridge schedule for quarterly DR test reminders:

```bash
aws scheduler create-schedule \
  --name quarterly-dr-test-reminder \
  --schedule-expression "cron(0 9 1 */3 ? *)" \
  --target '{
    "Arn": "[SNS-TOPIC-ARN]",
    "RoleArn": "[SCHEDULER-ROLE-ARN]",
    "Input": "{\"subject\":\"Quarterly DR Test Due\",\"message\":\"The quarterly DR test for [WORKLOAD] is due. Review the DR test checklist and schedule with the team.\"}"
  }' \
  --flexible-time-window '{"Mode": "OFF"}' \
  --region [REGION]
```

`cron(0 9 1 */3 ? *)` runs at 9:00 AM on the 1st of every 3rd month (January, April, July, October).

---

## Summary

- RTO/RPO targets must be set by the business, not assumed by the technical team. Present the cost curve so stakeholders understand they are making a cost-benefit trade-off.
- Aurora Global Database provides the strongest DR posture: sub-second RPO cross-region and RTO under 1 minute. It is also the most expensive option.
- Cross-region snapshot copy is appropriate for Tier 3/4 workloads where a recovery time of 1-4 hours is acceptable.
- DR plans are not real until they have been tested under realistic conditions. An untested DR plan provides false confidence.
- Measure actual RTO and RPO during every drill. If actual RTO exceeds the target, escalate the gap to engineering leadership immediately - it means the SLA the business is promising customers cannot be met.

**Next:** [Guide 08 - Failure Injection](./08-failure-injection.md)

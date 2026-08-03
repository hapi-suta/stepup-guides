# Runbook: Primary Region Degraded - DR Failover

**Severity:** P0 - All production traffic is impacted
**Scenario:** Primary AWS region is experiencing degradation affecting RDS connectivity. DR failover to secondary region is being evaluated.

---

## Symptoms

- AWS Health Dashboard shows service degradation in the primary region
- Application error rate near 100%
- RDS instances showing unusual status (incompatible-network, storage-full due to region-level issues)
- CloudWatch metrics unavailable from the primary region
- Cannot connect to RDS instances from the primary region

---

## Decision Gate: When to Failover

Do not failover immediately on the first alert. Premature failovers create their own problems (application connection string updates, potential data loss, complex failback). Apply the decision gate:

**Criteria to failover:**
1. AWS has confirmed region-level impact (not AZ-specific)
2. Impact duration exceeds your RTO target AND you have exceeded the retry window
3. There is no other root cause (misconfigured security group, IAM issue, application bug)
4. Authorized personnel have approved the decision (define this in advance)

**Criteria to wait:**
1. AWS Health indicates ETA under 15 minutes and your RTO target is 30 minutes
2. Only one AZ is affected and you can route around it
3. Impact is partial (only some instances, not all)

**Authorization requirement (define for your organization):**

| Time of Day | Who Can Authorize |
|-------------|------------------|
| Business hours | Engineering Manager OR Lead DBA |
| Off-hours | On-call Lead DBA (P0 authority) |
| Weekend | On-call Lead DBA (P0 authority) |

---

## Immediate Actions (first 10 minutes)

1. Verify the failure is real:

```bash
# Try to connect to the RDS instance (timeout set low)
psql \
  --host=[CLUSTER-ENDPOINT] \
  --port=5432 \
  --username=[DB-USER] \
  --dbname=[DBNAME] \
  --connect-timeout=10 \
  --command="SELECT 1;"
```

2. Check AWS Health Dashboard:

```bash
aws health describe-events \
  --filter '{"regions":["[PRIMARY-REGION]"],"services":["RDS"],"eventStatusCodes":["open","upcoming"]}' \
  --region us-east-1
```

3. Check if it is AZ-specific:

```bash
aws rds describe-db-instances \
  --db-instance-identifier [INSTANCE-ID] \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone}' \
  --region [PRIMARY-REGION]
```

4. Post initial status: "Investigating potential region-level RDS impact in [REGION]. Assessing DR requirement. Next update in 5 minutes."

---

## Diagnosis

### Confirm this is a region failure, not a configuration issue

Run these checks from outside the affected region (use your laptop or a second AWS account):

```bash
# Can you reach the AWS API in the primary region at all?
aws ec2 describe-availability-zones --region [PRIMARY-REGION]

# Is your VPC and route table intact?
aws ec2 describe-route-tables \
  --filters Name=association.main,Values=true \
  --region [PRIMARY-REGION] \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId]'

# Check RDS event stream
aws rds describe-events \
  --source-identifier [CLUSTER-ID] \
  --source-type db-cluster \
  --duration 60 \
  --region [PRIMARY-REGION]
```

---

## Remediation: Execute DR Failover

### Path A: Aurora Global Database (RTO < 2 minutes)

**Step 1:** Check replication lag before failing over:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraGlobalDBDataTransferBytes \
  --dimensions Name=DBClusterIdentifier,Value=[SECONDARY-CLUSTER-ID] \
  --start-time $(date -u -v-5M '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 300 \
  --statistics Sum \
  --region [SECONDARY-REGION]
```

If the primary region is completely unreachable, you cannot measure lag - proceed with the failover. The secondary region will have at most a few seconds of lag (typical Global Database latency is < 1 second).

**Step 2:** Initiate the managed planned failover:

```bash
# Record T0
echo "T0: $(date +%H:%M:%S.%3N)"

aws rds failover-global-cluster \
  --global-cluster-identifier [GLOBAL-CLUSTER-ID] \
  --target-db-cluster-identifier [SECONDARY-CLUSTER-ARN] \
  --region [PRIMARY-REGION]
```

If the primary region is completely unreachable, use the secondary region endpoint:

```bash
aws rds failover-global-cluster \
  --global-cluster-identifier [GLOBAL-CLUSTER-ID] \
  --target-db-cluster-identifier [SECONDARY-CLUSTER-ARN] \
  --region [SECONDARY-REGION]
```

**Step 3:** Monitor until the secondary becomes writer:

```bash
watch -n 5 'aws rds describe-global-clusters \
  --region [SECONDARY-REGION] \
  --query "GlobalClusters[*].GlobalClusterMembers[*].{Cluster:DBClusterArn,IsWriter:IsWriter}" \
  --output table'
```

**Step 4:** Get the new primary endpoint:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier [SECONDARY-CLUSTER-ID] \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region [SECONDARY-REGION]
```

**Step 5:** Update application connection strings to the new primary endpoint. If using Route 53:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id [HOSTED-ZONE-ID] \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "db.[DOMAIN]",
        "Type": "CNAME",
        "TTL": 60,
        "ResourceRecords": [{"Value": "[NEW-PRIMARY-ENDPOINT]"}]
      }
    }]
  }'
```

Record T4: when the application confirms healthy end-to-end.

### Path B: Cross-Region Snapshot Restore (RTO 30-90 minutes)

**Step 1:** Find the most recent available snapshot in the secondary region:

```bash
aws rds describe-db-snapshots \
  --region [SECONDARY-REGION] \
  --query 'sort_by(DBSnapshots, &SnapshotCreateTime)[-3:].[DBSnapshotIdentifier,SnapshotCreateTime,Status]' \
  --output table
```

**Step 2:** Restore to a new instance:

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier [WORKLOAD-NAME]-dr-restore \
  --db-snapshot-identifier [SNAPSHOT-ID] \
  --db-instance-class [INSTANCE-CLASS] \
  --db-subnet-group-name [SUBNET-GROUP-IN-SECONDARY-REGION] \
  --vpc-security-group-ids [SG-IN-SECONDARY-REGION] \
  --no-publicly-accessible \
  --deletion-protection \
  --region [SECONDARY-REGION]
```

Wait for the restore to complete (~30-60 minutes):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [WORKLOAD-NAME]-dr-restore \
  --region [SECONDARY-REGION]
```

**Step 3:** Get the endpoint and update application connection strings.

---

## Verification

After failover completes:

```sql
-- Connect to the DR endpoint and verify it is the writer
SELECT pg_is_in_recovery();
-- Expected: f (false = primary)

-- Verify recent data is present (RPO check)
SELECT max(created_at) FROM [KEY-TABLE];
-- Compare to expected data age
```

Check application health end-to-end before declaring the incident resolved.

---

## Failback Plan

After the primary region recovers:

1. Do not rush the failback. Ensure the primary region is stable for at least 2 hours before failback.
2. For Global Database: use `failover-global-cluster` again with the original primary cluster as the target.
3. For snapshot restore: snapshot the DR instance, copy to the primary region, restore, and update DNS.
4. Conduct a post-mortem with the full timeline, actual RTO/RPO, and action items.

---

## Prevention

- Aurora Global Database eliminates this risk for Tier 1 workloads.
- For Tier 2-3 workloads: cross-region snapshots are the minimum. The restore path must be tested annually.
- Define and document the failover authorization matrix before you need it. At 4 AM, you should not be debating who can approve the failover.
- Pre-configure the DR region: subnets, security groups, parameter groups, and IAM roles should all exist before the outage. Do not create infrastructure under pressure.

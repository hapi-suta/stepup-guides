# Module 10 - Build Guide 08: Chaos Testing

**Objective:** Run 8 chaos scenarios against your complete Aurora stack to verify resilience, monitoring, alerting, and recovery procedures. Each scenario tests a different failure mode.
**Time:** 60 minutes
**Level:** Senior / Staff
**Prerequisites:** Build Guides 02-07 completed (full stack deployed with monitoring, backups, and security).

---

## Why Chaos Testing

Building a production stack is half the job. The other half is proving it survives failure. Chaos testing deliberately injects failures to answer: "What happens when X breaks?" If you do not test failures in a controlled setting, you will discover them at 3 AM during a real incident.

Each scenario below follows the same pattern:
1. **Inject** - Introduce the failure
2. **Observe** - Watch monitoring, alarms, and logs
3. **Respond** - Follow the runbook or take corrective action
4. **Validate** - Verify recovery and document findings

---

## Scenario 1: Writer Instance Failure

**What you are testing:** Aurora automatic failover promotes a reader to writer. Cluster endpoint updates. Alarms fire.

### Inject

Force a failover of the Aurora cluster:

**On your local workstation:**

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier devops-lab-cluster
```

`--db-cluster-identifier` identifies the cluster to fail over. This simulates a writer crash by forcing Aurora to promote the reader.

Record the time:

```bash
date -u '+%Y-%m-%dT%H:%M:%SZ'
```

### Observe

Watch the cluster events:

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 10 \
  --query 'Events[*].[Date,Message]' \
  --output table
```

Expected output (yours will differ):
```
----------------------------------------------------------
| 2026-06-09T12:45:00Z | Started cross AZ failover to... |
| 2026-06-09T12:45:30Z | Completed failover...           |
----------------------------------------------------------
```

Check which instance is now the writer:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].[DBInstanceIdentifier,IsClusterWriter]' \
  --output table
```

Check CloudWatch alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[?StateValue!=`OK`].[AlarmName,StateValue]' \
  --output table
```

### Validate

- Failover completed in under 60 seconds
- Cluster endpoint now points to the new writer
- Former reader is now the writer
- Alarms returned to OK state after failover

Record the failover duration (time from failover command to cluster `available` status).

---

## Scenario 2: Security Group Lockout

**What you are testing:** Accidentally removing all inbound rules from the Aurora security group. Simulates a misconfigured firewall.

### Inject

**On your local workstation:**

Save the current rules first (for restoration):

```bash
AURORA_SG=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)
```

```bash
aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$AURORA_SG \
  --query 'SecurityGroupRules[?IsEgress==`false`]' \
  --output json > /tmp/aurora-sg-rules-backup.json
```

Now remove all inbound rules:

```bash
RULE_IDS=$(aws ec2 describe-security-group-rules \
  --filters Name=group-id,Values=$AURORA_SG \
  --query 'SecurityGroupRules[?IsEgress==`false`].SecurityGroupRuleId' \
  --output text)
```

```bash
for RULE_ID in $RULE_IDS; do
  aws ec2 revoke-security-group-ingress \
    --group-id $AURORA_SG \
    --security-group-rule-ids $RULE_ID
done
```

### Observe

Try to connect to the database:

```bash
psql "host=devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com port=5432 dbname=postgres user=dbadmin sslmode=require" --connect-timeout=5
```

The connection should time out. This simulates a security group misconfiguration that blocks all database access.

Check if the database connections alarm triggers:

```bash
aws cloudwatch describe-alarms \
  --alarm-names devops-lab-aurora-connections-high \
  --query 'MetricAlarms[0].StateValue' \
  --output text
```

### Respond

Restore the security group rules:

```bash
APP_SG=$(cat /tmp/aurora-sg-rules-backup.json | python3 -c "
import sys, json
rules = json.load(sys.stdin)
for r in rules:
    ref = r.get('ReferencedGroupInfo', {}).get('GroupId', '')
    if ref:
        print(ref)
" | head -1)
```

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $AURORA_SG \
  --protocol tcp \
  --port 5432 \
  --source-group $APP_SG
```

Repeat for the bastion security group if needed.

### Validate

- Connection restored after rules re-added
- Time to detect: note how long it took to realize connections were blocked
- Lesson: Use Terraform to manage security groups, not manual CLI changes

---

## Scenario 3: Parameter Group Misconfiguration

**What you are testing:** Setting an aggressive `statement_timeout` that kills legitimate queries.

### Inject

**On your local workstation:**

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters ParameterName=statement_timeout,ParameterValue=100,ApplyMethod=immediate
```

This sets statement timeout to 100 milliseconds - any query taking more than 0.1 seconds will be killed.

### Observe

Connect to the database and run a query that takes more than 100ms:

```sql
SELECT pg_sleep(1);
```

Expected output (yours will differ):
```
ERROR:  canceling statement due to statement timeout
```

Any real application query hitting the database will also be killed if it takes more than 100ms.

### Respond

Restore the correct timeout:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name devops-lab-cluster-params \
  --parameters ParameterName=statement_timeout,ParameterValue=60000,ApplyMethod=immediate
```

### Validate

- Queries complete normally after restoration
- The error appeared in CloudWatch Logs
- Lesson: Always test parameter changes in staging first

---

## Scenario 4: Connection Exhaustion

**What you are testing:** What happens when the database reaches `max_connections`.

### Inject

Connect to the database and check current max_connections:

```sql
SHOW max_connections;
```

Note the value. Then open many connections using pgbench or a script:

```bash
for i in $(seq 1 250); do
  psql "host=devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com port=5432 dbname=postgres user=dbadmin sslmode=require" -c "SELECT pg_sleep(60);" &
done
```

### Observe

Check the connections alarm:

```bash
aws cloudwatch describe-alarms \
  --alarm-names devops-lab-aurora-connections-high \
  --query 'MetricAlarms[0].StateValue' \
  --output text
```

Try to open a new connection - it should be rejected:

```bash
psql "host=devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com port=5432 dbname=postgres user=dbadmin sslmode=require" -c "SELECT 1;"
```

Expected error:
```
FATAL: remaining connection slots are reserved for non-replication superuser connections
```

### Respond

Kill idle connections from a reserved connection:

```sql
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND usename != 'rdsadmin'
AND pid != pg_backend_pid();
```

### Validate

- Connections alarm returned to OK
- New connections succeeded after termination
- Lesson: Use connection pooling (PgBouncer or RDS Proxy)

Kill the background pgbench processes:

```bash
kill $(jobs -p) 2>/dev/null
```

---

## Scenario 5: Disk Pressure Simulation

**What you are testing:** What happens when a large table consumes significant storage.

### Inject

Create a large table with random data:

```sql
CREATE TABLE app.chaos_large_table AS
SELECT
  generate_series(1, 5000000) AS id,
  md5(random()::text) AS data,
  repeat('x', 200) AS padding;
```

### Observe

Check storage metrics:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name VolumeBytesUsed \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --start-time $(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 300 \
  --statistics Maximum \
  --output table
```

### Respond

Drop the chaos table:

```sql
DROP TABLE IF EXISTS app.chaos_large_table;
```

Note: Aurora storage does not shrink immediately after dropping tables. The space is reclaimed asynchronously.

### Validate

- Storage metric showed the increase
- Aurora auto-scaled storage without downtime
- Lesson: Monitor VolumeBytesUsed and set alerts for storage growth rate

---

## Scenario 6: Replica Lag Spike

**What you are testing:** Heavy write load causes replica lag to increase.

### Inject

Generate heavy write load on the writer:

```sql
CREATE TABLE app.chaos_writes (id serial, data text, ts timestamptz default now());
```

```bash
pgbench -h devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com \
  -U dbadmin -d postgres \
  -c 20 -j 4 -T 120 \
  -f - <<'SQL'
INSERT INTO app.chaos_writes (data) VALUES (md5(random()::text));
SQL
```

### Observe

Watch replica lag:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name AuroraReplicaLag \
  --dimensions Name=DBInstanceIdentifier,Value=devops-lab-cluster-r1 \
  --start-time $(date -u -v-10M '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 60 \
  --statistics Maximum \
  --output table
```

Check if the replica lag alarm triggered:

```bash
aws cloudwatch describe-alarms \
  --alarm-names devops-lab-aurora-replica-lag-high \
  --query 'MetricAlarms[0].StateValue' \
  --output text
```

### Respond

Stop the write load (the pgbench command will finish after 120 seconds). Clean up:

```sql
DROP TABLE IF EXISTS app.chaos_writes;
```

### Validate

- Replica lag increased during heavy writes
- Replica lag alarm triggered (or nearly triggered)
- Lag returned to normal after write load stopped
- Lesson: Aurora replica lag is typically under 20ms but can spike under heavy write load

---

## Scenario 7: CloudWatch Alarm Deletion

**What you are testing:** What happens when alarms are accidentally deleted.

### Inject

Delete one alarm:

```bash
aws cloudwatch delete-alarms \
  --alarm-names devops-lab-aurora-cpu-high
```

### Observe

List remaining alarms:

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix devops-lab-aurora \
  --query 'MetricAlarms[*].AlarmName' \
  --output table
```

The CPU alarm should be missing.

### Respond

Recreate the alarm from Build 04:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name devops-lab-aurora-cpu-high \
  --alarm-description "Aurora cluster CPU utilization above 80% for 5 minutes" \
  --namespace AWS/RDS \
  --metric-name CPUUtilization \
  --dimensions Name=DBClusterIdentifier,Value=devops-lab-cluster \
  --statistic Average \
  --period 60 \
  --evaluation-periods 5 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions arn:aws:sns:us-east-1:$(aws sts get-caller-identity --query Account --output text):devops-lab-aurora-alerts \
  --ok-actions arn:aws:sns:us-east-1:$(aws sts get-caller-identity --query Account --output text):devops-lab-aurora-alerts \
  --treat-missing-data notBreaching
```

### Validate

- Alarm is restored and in OK state
- Lesson: Manage alarms in Terraform so accidental deletions are caught by `terraform plan`

---

## Scenario 8: Full Cluster Reboot

**What you are testing:** Both instances reboot simultaneously (simulates maintenance window issues).

### Inject

Reboot the writer (which causes a brief failover):

```bash
aws rds reboot-db-instance \
  --db-instance-identifier devops-lab-cluster-w1
```

Wait 30 seconds, then reboot the reader:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier devops-lab-cluster-r1
```

### Observe

Watch the events:

```bash
aws rds describe-events \
  --source-identifier devops-lab-cluster \
  --source-type db-cluster \
  --duration 10 \
  --query 'Events[*].[Date,Message]' \
  --output table
```

Check instance status:

```bash
aws rds describe-db-instances \
  --filters Name=db-cluster-id,Values=devops-lab-cluster \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceStatus]' \
  --output table
```

### Respond

Wait for both instances to return to `available`:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-w1
```

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-cluster-r1
```

### Validate

- Both instances returned to available state
- Cluster endpoint resolves correctly
- Test query succeeds
- Lesson: Stagger reboots - never reboot writer and reader simultaneously

---

## Chaos Testing Results Template

Document your results:

```markdown
# Chaos Testing Results

| # | Scenario | Injected | Detected By | Recovery Time | Status |
|---|----------|----------|-------------|---------------|--------|
| 1 | Writer failure | Forced failover | RDS events | ~30s | PASS |
| 2 | SG lockout | Removed SG rules | Connection timeout | ~2 min | PASS |
| 3 | Bad parameter | statement_timeout=100ms | Query errors | ~1 min | PASS |
| 4 | Connection flood | 250 connections | CW alarm | ~5 min | PASS |
| 5 | Disk pressure | 5M row table | Storage metric | ~1 min | PASS |
| 6 | Replica lag | Heavy writes | CW alarm | ~2 min | PASS |
| 7 | Alarm deletion | Deleted CPU alarm | Manual check | ~1 min | PASS |
| 8 | Full reboot | Both instances | RDS events | ~5 min | PASS |
```

---

## Summary

You have tested 8 chaos scenarios against your production Aurora stack:

1. **Writer failure** - Aurora automatic failover works, cluster endpoint updates
2. **Security group lockout** - Connections blocked immediately, SG rules must be backed up
3. **Parameter misconfiguration** - Bad parameters cause immediate query failures
4. **Connection exhaustion** - Alarms fire, need connection pooling strategy
5. **Disk pressure** - Aurora auto-scales storage, monitor growth rate
6. **Replica lag** - Heavy writes increase lag, alarms detect it
7. **Alarm deletion** - Manual detection only - manage alarms in IaC
8. **Full reboot** - Stagger reboots to avoid total unavailability

The key lesson from chaos testing: every manual process is a point of failure. The more you manage in Terraform and automate through alarms, the faster you detect and recover from failures.

**Next:** [Use 01 - Architecture Review](../use/01-architecture-review.md)

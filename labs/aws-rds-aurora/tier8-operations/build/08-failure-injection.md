# Tier 8 - Build Guide 08: Failure Injection and Resilience Testing

**Objective:** Use AWS Fault Injection Simulator (FIS) to inject controlled failures into RDS and Aurora, simulate AZ and instance failures, measure actual RTO against designed targets, and build a repeatable resilience testing pipeline.
**Time:** 40 minutes
**Level:** Expert
**infra_required:** true - Requires a running Aurora PostgreSQL cluster with at least one reader instance. IAM permissions to create and run FIS experiments.
**Prerequisites:** Tier 8 Build 07 completed. An Aurora cluster with at least one writer and one reader in a Multi-AZ configuration.

---

## 1. Chaos Engineering Principles Applied to RDS

Before running any failure injection, define your steady state and hypothesis.

### Define steady state for your cluster

Steady state is the normal, observable behavior of your system under typical load. For a database, steady state metrics might be:

- API error rate: < 0.1%
- Database connection success rate: > 99.9%
- Average query latency: < 20ms (p99 < 100ms)
- `DatabaseConnections` metric: stable between 40-80 connections

Write these down before the experiment. After injecting a failure, you measure whether steady state was restored and within what time frame.

### Hypothesis template

"If we inject [FAILURE TYPE] into [COMPONENT], we hypothesize that the system will [EXPECTED BEHAVIOR] within [TIME WINDOW], and that steady-state metrics will recover within [RECOVERY TIME]."

Example:
"If we inject an Aurora cluster failover, we hypothesize that the cluster endpoint will route traffic to the new writer within 30 seconds, and that application error rate will return to below 0.1% within 60 seconds of the failover completing."

### Safety rules for failure injection

1. Always test in a staging environment first.
2. Define stop conditions before starting. If a metric exceeds a defined threshold, the experiment aborts automatically.
3. Have a manual abort procedure ready. Know how to cancel the FIS experiment immediately.
4. Brief your team before running experiments in production. On-call engineers should know an experiment is running so they do not respond to alerts as real incidents.
5. Never run failure injection during peak traffic periods unless your hypothesis specifically requires it.

---

## 2. Set Up AWS FIS for RDS

### Create the FIS IAM role

FIS needs permissions to perform actions on your behalf.

**Console:**
1. Open the IAM console.
2. Click **Roles > Create role**.
3. Select **AWS service** and choose **FIS** as the use case.
4. Attach the following policies:
   - `AmazonRDSFullAccess` (for RDS/Aurora actions)
   - `CloudWatchFullAccess` (for stop conditions)
5. Name the role `FISRDSExperimentRole`.

**CLI:**

Create the trust policy file:

```bash
cat > /tmp/fis-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "fis.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
```

Create the role:

```bash
aws iam create-role \
  --role-name FISRDSExperimentRole \
  --assume-role-policy-document file:///tmp/fis-trust-policy.json

aws iam attach-role-policy \
  --role-name FISRDSExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonRDSFullAccess

aws iam attach-role-policy \
  --role-name FISRDSExperimentRole \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchFullAccess
```

Get the role ARN for use in experiments:

```bash
aws iam get-role \
  --role-name FISRDSExperimentRole \
  --query 'Role.Arn' \
  --output text
```

### Create a CloudWatch Alarm for use as a stop condition

The stop condition aborts the experiment automatically if a metric exceeds a threshold.

```bash
# Create an alarm that fires when error rate exceeds 5%
# (You need to have this metric from your application monitoring)
aws cloudwatch put-metric-alarm \
  --alarm-name fis-stop-condition-error-rate \
  --alarm-description "FIS experiment stop condition - abort if error rate > 5%" \
  --namespace [YOUR-APP-NAMESPACE] \
  --metric-name ErrorRate \
  --statistic Average \
  --period 60 \
  --evaluation-periods 1 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --alarm-actions [SNS-TOPIC-ARN] \
  --region [REGION]
```

If you do not have an application error rate metric, use the built-in RDS `DatabaseConnections` metric as a proxy - if connections drop to zero during an experiment, abort:

```bash
aws cloudwatch put-metric-alarm \
  --alarm-name fis-stop-condition-db-connections \
  --alarm-description "FIS stop condition - abort if connections drop to zero for 2 minutes" \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBClusterIdentifier,Value=[CLUSTER-ID] \
  --statistic Maximum \
  --period 60 \
  --evaluation-periods 2 \
  --threshold 0 \
  --comparison-operator LessThanOrEqualToThreshold \
  --region [REGION]
```

---

## 3. Experiment 1: Aurora Cluster Failover

This experiment forces an Aurora cluster failover and measures how long it takes for the cluster endpoint to route to the new writer and for applications to reconnect.

### Create the FIS experiment template (CLI)

```bash
cat > /tmp/aurora-failover-experiment.json << EOF
{
  "description": "Force Aurora cluster failover to measure actual RTO",
  "targets": {
    "AuroraCluster": {
      "resourceType": "aws:rds:cluster",
      "resourceArns": ["arn:aws:rds:[REGION]:[ACCOUNT-ID]:cluster:[CLUSTER-ID]"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "FailoverAuroraCluster": {
      "actionId": "aws:rds:failover-db-cluster",
      "parameters": {},
      "targets": {
        "Clusters": "AuroraCluster"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:[REGION]:[ACCOUNT-ID]:alarm:fis-stop-condition-db-connections"
    }
  ],
  "roleArn": "arn:aws:iam::[ACCOUNT-ID]:role/FISRDSExperimentRole",
  "tags": {
    "Name": "aurora-failover-rto-measurement",
    "Environment": "[ENV]"
  }
}
EOF
```

Create the experiment template:

```bash
aws fis create-experiment-template \
  --cli-input-json file:///tmp/aurora-failover-experiment.json \
  --region [REGION]
```

This returns an experiment template ID. Record it.

### Create the experiment template (Console)

1. Open the **AWS FIS** console.
2. Click **Experiment templates > Create experiment template**.
3. Set a description: "Aurora cluster failover RTO measurement".
4. Click **Add target**: Resource type = `aws:rds:cluster`, select your cluster.
5. Click **Add action**: Select `aws:rds:failover-db-cluster`, map it to the cluster target.
6. Click **Add stop condition**: Select **CloudWatch Alarm** and choose your stop condition alarm.
7. Set the IAM role to `FISRDSExperimentRole`.
8. Click **Create experiment template**.

### Run the experiment and measure RTO

Before starting, open a second terminal and run a continuous connection test:

```bash
# In a separate terminal - run this before starting the experiment
while true; do
  RESULT=$(psql \
    --host=[CLUSTER-ENDPOINT] \
    --port=5432 \
    --username=[DB-USER] \
    --dbname=[DBNAME] \
    --command="SELECT now(), pg_is_in_recovery();" \
    --no-psqlrc \
    --tuples-only 2>&1)
  echo "$(date +%H:%M:%S): $RESULT"
  sleep 1
done
```

Now start the experiment and record T0:

```bash
# Record T0
echo "T0: $(date +%H:%M:%S)"

aws fis start-experiment \
  --experiment-template-id [TEMPLATE-ID] \
  --region [REGION]
```

Watch the continuous connection test output:
- When `pg_is_in_recovery()` switches from `f` (false = primary) to `t` (true = replica/recovering), the old primary has stepped down.
- When `pg_is_in_recovery()` returns `f` again on the cluster endpoint, the new primary is serving connections.
- Record T3: the timestamp when your connection test first successfully returns `f` on the new primary.

Expected output sequence (yours will differ):
```
14:32:00:  2026-01-15 14:32:00+00 | f   <- steady state
14:32:01:  2026-01-15 14:32:01+00 | f
14:32:02: psql: error: could not connect...   <- failover started (T1)
14:32:03: psql: error: could not connect...
...
14:32:28: psql: error: could not connect...
14:32:29:  2026-01-15 14:32:29+00 | f   <- new primary accepting connections (T3)
```

**RTO in this example: ~27 seconds** (T3 - T0 = 14:32:29 - 14:32:02 = 27 seconds).

---

## 4. Experiment 2: RDS Instance Reboot (Simulated AZ Failure)

For Multi-AZ RDS instances, a reboot with failover simulates an AZ failure and forces promotion of the standby.

### Create the reboot-with-failover experiment template (CLI)

```bash
cat > /tmp/rds-az-failure-experiment.json << EOF
{
  "description": "Simulate AZ failure by rebooting with failover",
  "targets": {
    "RDSInstance": {
      "resourceType": "aws:rds:db",
      "resourceArns": ["arn:aws:rds:[REGION]:[ACCOUNT-ID]:db:[INSTANCE-ID]"],
      "selectionMode": "ALL"
    }
  },
  "actions": {
    "RebootWithFailover": {
      "actionId": "aws:rds:reboot-db-instances",
      "parameters": {
        "forceFailover": "true"
      },
      "targets": {
        "DBInstances": "RDSInstance"
      }
    }
  },
  "stopConditions": [
    {
      "source": "aws:cloudwatch:alarm",
      "value": "arn:aws:cloudwatch:[REGION]:[ACCOUNT-ID]:alarm:fis-stop-condition-db-connections"
    }
  ],
  "roleArn": "arn:aws:iam::[ACCOUNT-ID]:role/FISRDSExperimentRole"
}
EOF

aws fis create-experiment-template \
  --cli-input-json file:///tmp/rds-az-failure-experiment.json \
  --region [REGION]
```

`"forceFailover": "true"` causes the reboot to promote the Multi-AZ standby rather than simply restarting the primary. This is functionally equivalent to an AZ failure for RDS Multi-AZ instances.

### Start the experiment and measure RTO

Same procedure as Experiment 1: run the continuous connection test, record T0 when you start the experiment, and record T3 when connections succeed again.

For Multi-AZ RDS (not Aurora), expect RTO of 60-120 seconds. RDS Multi-AZ failover is slower than Aurora because it involves DNS propagation and OS-level standby promotion rather than Aurora's in-cluster replica promotion.

---

## 5. Measure Actual RTO vs Designed RTO

After each experiment, compare actual vs designed:

```
EXPERIMENT RESULTS: [DATE]
Experiment: Aurora Cluster Failover
Designed RTO: 60 seconds (Tier 2 target)

Measurements:
  T0 (experiment started):          [TIME]
  T1 (first connection failure):    [TIME] (delta from T0: [N] seconds)
  T3 (new primary accepting conn):  [TIME] (delta from T0: [N] seconds)
  T4 (application health restored): [TIME] (delta from T0: [N] seconds)

Actual RTO: [N] seconds
RTO Target: 60 seconds
Status: PASS / FAIL

Observations:
- [Any anomalies observed during the experiment]
- [DNS propagation time if observed]
- [Application reconnection behavior]

Action Items:
- [Any gaps found between actual and designed RTO]
```

### Common RTO gaps and their causes

| RTO Gap | Common Cause | Fix |
|---------|-------------|-----|
| Application takes > 60s to reconnect | Application using instance endpoint instead of cluster endpoint | Switch to cluster endpoint |
| Application takes > 60s to reconnect | DNS TTL cached at 300s in application layer | Reduce TTL to 5s; use RDS Proxy |
| Connection fails for 2+ minutes | Connection pool not configured with retry logic | Add exponential backoff and retry to connection pool |
| Failover takes > 60s | Aurora reader not promoted (no readers in cluster) | Add at least one reader instance to the cluster |
| Application health not restored after failover | Application health check route uses database, not cache | Review health check implementation |

---

## 6. Build a Resilience Testing Pipeline

A resilience testing pipeline automates the process of running FIS experiments, measuring outcomes, and reporting results.

### Pipeline design

```
EventBridge Schedule (quarterly trigger)
    |
    v
Lambda: Check prerequisites
  - Verify staging cluster is running
  - Verify monitoring is active
  - Notify team channel
    |
    v
Lambda: Start FIS experiment
  - Start the experiment
  - Record T0
    |
    v
Lambda: Monitor experiment
  - Poll FIS experiment status
  - Poll CloudWatch for connection success rate
  - Record T1, T3, T4 timestamps
    |
    v
Lambda: Generate report
  - Calculate actual RTO
  - Compare vs target
  - Write results to S3
  - Send summary to SNS topic (email/Slack)
    |
    v
S3: Store experiment results
  s3://[BUCKET]/resilience-tests/[DATE]/[EXPERIMENT-ID].json
```

### Create the experiment scheduler (EventBridge)

```bash
aws events put-rule \
  --name quarterly-resilience-test \
  --schedule-expression "cron(0 10 1 */3 ? *)" \
  --description "Trigger quarterly resilience test for staging databases" \
  --state ENABLED \
  --region [REGION]
```

```bash
aws events put-targets \
  --rule quarterly-resilience-test \
  --targets '[
    {
      "Id": "1",
      "Arn": "[LAMBDA-FUNCTION-ARN]",
      "Input": "{\"environment\": \"staging\", \"experiment\": \"aurora-failover\"}"
    }
  ]' \
  --region [REGION]
```

### Store results in S3 with a defined schema

Each experiment result should be stored as JSON:

```json
{
  "experiment_id": "[FIS-EXPERIMENT-ID]",
  "date": "2026-01-15",
  "workload": "[WORKLOAD NAME]",
  "environment": "staging",
  "failure_type": "aurora-cluster-failover",
  "t0": "2026-01-15T14:32:00Z",
  "t1": "2026-01-15T14:32:02Z",
  "t3": "2026-01-15T14:32:29Z",
  "t4": "2026-01-15T14:32:35Z",
  "actual_rto_seconds": 35,
  "designed_rto_seconds": 60,
  "rto_met": true,
  "actual_rpo_seconds": 0,
  "designed_rpo_seconds": 5,
  "rpo_met": true,
  "stop_condition_triggered": false,
  "observations": "Clean failover. Application reconnected on first retry.",
  "action_items": []
}
```

---

## Summary

- Define steady state and a clear hypothesis before every experiment. Failure injection without measurement is just chaos.
- FIS stop conditions are mandatory safety mechanisms. Never run an experiment without a stop condition tied to a meaningful metric.
- Aurora cluster failover (via FIS `aws:rds:failover-db-cluster`) is the most valuable experiment for measuring actual vs designed RTO.
- For Multi-AZ RDS, `aws:rds:reboot-db-instances` with `forceFailover=true` simulates AZ failure.
- Common RTO gaps are almost always in the application layer (DNS caching, connection pool retry logic) not the database layer. The database failover is fast; the application reconnection is the variable.
- Automate your resilience testing. A quarterly drill run manually will be skipped. A quarterly drill triggered by EventBridge and measured automatically will actually happen.

**Next:** [Guide 09 - Autonomous Diagnostics](./09-autonomous-diagnostics.md)

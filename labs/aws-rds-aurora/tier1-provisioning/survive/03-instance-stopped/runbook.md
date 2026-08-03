# Runbook: Instance Stopped
## Survive Scenario 03

**Symptom:** Application is down. Database connections fail with "Connection refused" or "Connection timed out"
**Severity:** Critical - database is offline
**Time to resolve:** 10 to 20 minutes (mostly waiting for instance to start)

---

## Your Starting Point

The application is down. Users are getting errors. You get paged.

The application error log shows:
```
Error: connect ECONNREFUSED 54.234.189.12:5432
    (or)
Error: psql: error: connection to server at "suta-rds-lab.abc123.us-east-1.rds.amazonaws.com"
       port 5432 failed: Connection refused
```

---

## Step 1 - Check the Instance Status

This is ALWAYS the first step when a database connection fails completely.

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].{Status:DBInstanceStatus,StopTime:InstanceCreateTime}" \
  --output table
```

Expected output when stopped:
```
-----------------------------
| DescribeDBInstances       |
+--------+------------------+
| Status |                  |
+--------+------------------+
| stopped|                  |
+--------+------------------+
```

The instance is stopped. That is why nobody can connect.

---

## Step 2 - Check CloudWatch for Clues

When did the instance stop? Check CloudWatch metrics to see when data stopped flowing.

Go to: AWS Console > CloudWatch > Metrics > RDS > DBInstanceIdentifier: suta-rds-lab

Look at `DatabaseConnections` and `CPUUtilization`. You will see them flatline at the time the instance stopped.

Or use the CLI to check recent events:

```bash
aws rds describe-events \
  --source-identifier suta-rds-lab \
  --source-type db-instance \
  --duration 120 \
  --query "Events[*].{Time:Date,Message:Message}" \
  --output table
```

Expected output:
```
--------------------------------------------------------------------------------
|                            DescribeEvents                                    |
+---------------------------+------------------------------------------------+
|          Message          |            Time                                |
+---------------------------+------------------------------------------------+
| DB instance stopped       | 2025-01-15T14:02:00.000Z                       |
| DB instance is being shut...| 2025-01-15T14:01:00.000Z                     |
+---------------------------+------------------------------------------------+
```

The event log tells you exactly when the instance was stopped and (sometimes) why.

---

## Step 3 - Check for Automated Stop Policies

RDS instances can be stopped automatically by:
- AWS cost management policies set by an admin
- CloudWatch Events rules (e.g., "stop all non-prod instances at 6pm")
- Infrastructure automation (Terraform scheduled jobs)
- The 7-day auto-start: AWS stops a manually stopped instance permanently if it is not restarted within 7 days... wait, actually AWS does NOT stop it automatically. AWS automatically STARTS a stopped instance after 7 days to prevent indefinite stopping.

Check if there are any EventBridge rules targeting this instance:

```bash
aws events list-rules \
  --query "Rules[?contains(Description,'rds') || contains(Description,'database')]" \
  --output table
```

Note what you find. This is important for the post-incident review.

---

## Step 4 - Start the Instance

Start the stopped instance:

```bash
aws rds start-db-instance \
  --db-instance-identifier suta-rds-lab
```

Expected output:
```json
{
    "DBInstance": {
        "DBInstanceIdentifier": "suta-rds-lab",
        "DBInstanceStatus": "starting",
        ...
    }
}
```

The status is `starting`. Wait 3 to 7 minutes.

---

## Step 5 - Wait for the Instance to Become Available

Option A - Use the AWS CLI wait command (blocks until available):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier suta-rds-lab
```

This command has no output while waiting. It returns when the instance is available.

Option B - Check status manually every 30 seconds:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text
```

Keep running this until it says `available`.

---

## Step 6 - Verify the Endpoint (In Case It Changed)

After starting, confirm the endpoint is the same:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

RDS endpoints do not change when you stop and start an instance. The endpoint should be the same as before.

---

## Step 7 - Test Port Connectivity

```bash
nc -zv suta-rds-lab.abc123.us-east-1.rds.amazonaws.com 5432
```

Expected output:
```
Connection to suta-rds-lab.abc123.us-east-1.rds.amazonaws.com port 5432 [tcp/postgresql] succeeded!
```

---

## Step 8 - Connect with psql and Verify Data

```bash
psql -h suta-rds-lab.abc123.us-east-1.rds.amazonaws.com \
  -U postgres -d labdb -p 5432
```

Once connected, check that data is intact:

```sql
-- Check no tables were dropped (list all tables)
\dt

-- Check row counts for any critical tables
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;

-- Check for any replication issues
SELECT pg_is_in_recovery();

-- Exit
\q
```

> **Concept:** Stopping and starting an RDS instance does NOT delete data. The EBS volume persists. When you restart, you pick up exactly where you left off. This is different from terminating an instance, which can delete data.

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | RDS instance was stopped (manually or by automation) |
| Impact | Complete database outage. Zero connections possible. |
| Data loss | None - EBS volume persists through stop/start |
| How to detect | Instance status = "stopped" in RDS console/CLI |
| Fix | `aws rds start-db-instance` then wait 3-7 minutes |
| Time to recover | 5 to 10 minutes total |

---

## Prevention

1. **Multi-AZ** does not help here because the standby is also stopped when the primary is stopped. Multi-AZ protects against hardware failure, not manual stops.

2. **Use AWS Config** to alert when an RDS instance changes state to `stopped`.

3. **Lock down permissions** - not everyone should be able to stop production databases. Use IAM policies to restrict `rds:StopDBInstance` in production accounts.

4. **Separate production from dev/test** using different AWS accounts. Cost-saving automation that stops dev instances should NEVER have access to the production account.

5. **Use Aurora for mission-critical workloads** - Aurora does not support the stop/start feature for production clusters (only for single-instance Aurora). This prevents accidental stops.

---

## Now Run the Validate Script

```bash
bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/03-instance-stopped/validate.sh
```

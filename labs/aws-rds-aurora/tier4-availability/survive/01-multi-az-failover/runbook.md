# SURVIVE 01 - Multi-AZ Failover Runbook
## Incident: RDS Instance Failover - Application Connection Drops

---

## What You Are Seeing

Your application is throwing database connection errors. The database was healthy minutes ago. No changes were deployed.

Typical error messages:
```
FATAL: could not connect to server: Connection refused
SSL connection has been closed unexpectedly
connection to server at "my-postgres.xxx..." failed: FATAL: the database system is starting up
```

---

## Step 1 - Is the Database Up or Down?

Do not assume anything. First, check if the RDS endpoint is reachable.

Try to connect:

```bash
psql -h my-postgres.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT 1;" \
     --connect-timeout=5
```

If it fails, check the instance status:

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,MultiAZ:MultiAZ}' \
  --output table \
  --region us-east-1
```

Expected output during failover (yours will differ):
```
-----------------------------
|   DescribeDBInstances     |
+----------+----------------+
| MultiAZ  | Status         |
+----------+----------------+
| True     | rebooting      |
+----------+----------------+
```

`rebooting` status with `MultiAZ=True` means a failover is in progress. This is a planned recovery, not a crash.

---

## Step 2 - Check the Events Log

```bash
aws rds describe-events \
  --source-identifier my-postgres \
  --source-type db-instance \
  --duration 30 \
  --region us-east-1
```

Look for events like:
- "Multi-AZ instance failover started."
- "DB instance restarted."
- "Multi-AZ instance failover completed."

Expected output (yours will differ):
```json
{
    "Events": [
        {
            "Message": "Multi-AZ instance failover started.",
            "EventCategories": ["failover"],
            "Date": "2024-01-15T15:05:02.000Z"
        }
    ]
}
```

---

## Step 3 - Wait for the Failover to Complete

A Multi-AZ failover typically takes 60-120 seconds. Do not panic. Do not try to force anything.

Watch the status:

```bash
watch -n 10 "aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].DBInstanceStatus' \
  --output text \
  --region us-east-1"
```

`watch -n 10` - runs the command every 10 seconds.

Wait until the status changes from `rebooting` to `available`.

---

## Step 4 - Verify the New Primary Is in a Different AZ

```bash
aws rds describe-db-instances \
  --db-instance-identifier my-postgres \
  --query 'DBInstances[0].{Status:DBInstanceStatus,AZ:AvailabilityZone,SecondaryAZ:SecondaryAvailabilityZone}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
---------------------------------------------
|         DescribeDBInstances               |
+------+------------------+-----------------+
| AZ   | SecondaryAZ      | Status          |
+------+------------------+-----------------+
| us-east-1b | us-east-1a | available       |
+------+------------------+-----------------+
```

The AZ values should have swapped from what they were before. This confirms the failover succeeded.

---

## Step 5 - Confirm the Endpoint Is Resolving to a New IP

```bash
dig +short my-postgres.xxxx.us-east-1.rds.amazonaws.com
```

Compare this IP to what you had before. It should be different (different subnet in different AZ).

---

## Step 6 - Test the Connection

```bash
psql -h my-postgres.xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres \
     -c "SELECT now(), inet_server_addr();"
```

Expected output:
```
            now            | inet_server_addr
---------------------------+------------------
 2024-01-15 15:06:45.000  | 10.0.2.87
```

If this works, the database is healthy. Your application should reconnect automatically.

---

## Step 7 - Verify Your Application Is Reconnected

Check your application logs for connection recovery messages. Most database libraries retry connections automatically.

If your application is NOT reconnecting:
- Check if your app is using connection pooling with persistent connections
- Persistent connections from before the failover may need to be killed and reopened
- Restart the application process if the connection pool is stuck

---

## Step 8 - Write an Incident Summary

After recovery, write a brief summary:

```
Incident: RDS Multi-AZ Failover
Date: [DATE]
Duration: [START TIME] to [END TIME] = [N minutes] downtime
Root cause: [Failover triggered by: reboot / AWS event / unknown]
Detection method: [Application errors / CloudWatch alarm / Manual check]
Resolution: Waited for automatic failover to complete
New writer AZ: [AZ NAME]
Application recovery: [Automatic reconnect / Manual restart]
Action items:
  - [ ] Confirm application retry logic works (did it reconnect automatically?)
  - [ ] Set up CloudWatch alarm for failover events
  - [ ] Review connection pool timeout settings
```

---

## Prevention / Preparation Checklist

- [ ] CloudWatch alarm on "failover" event category for the RDS instance
- [ ] Application connection retry configured (at least 3 retries with backoff)
- [ ] Connection pool max lifetime set to < 5 minutes (prevents stale connections)
- [ ] Test failover quarterly to verify RTO is within expectations
- [ ] Document the expected failover time in your SLA documentation

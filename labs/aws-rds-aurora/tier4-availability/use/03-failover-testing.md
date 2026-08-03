# USE 03 - Failover Testing: Plan, Execute, Measure
## Apply What You Learned | Tier 4

---

## What You Will Practice

- Writing a formal failover test plan
- Executing a controlled failover
- Measuring actual downtime vs expected RTO
- Documenting results for a production runbook

---

## Why Test Failover?

A failover that you have never tested is a failover plan you cannot trust. Every HA architecture should be tested at least once before going to production, and periodically after that.

Your goal in this lab: execute a clean failover test and produce a written record of what happened and how long it took.

---

## Part 1 - Write a Failover Test Plan

Before you run anything, write out your plan. Use this template:

```
FAILOVER TEST PLAN
==================
Date: [DATE]
Cluster: [CLUSTER NAME]
Region: [REGION]
Tester: [YOUR NAME]

PRE-TEST CHECKS:
- [ ] Current writer instance: [INSTANCE ID]
- [ ] Current reader instances: [LIST THEM]
- [ ] Baseline replica lag: [X ms]
- [ ] Application connection string uses endpoint (not hardcoded IP): [YES/NO]

TEST GOAL:
- Verify failover completes within [N] seconds
- Verify application reconnects automatically

RECOVERY TIME OBJECTIVE (RTO): [N seconds]

FAILOVER METHOD:
- [ ] Console: Actions -> Failover
- [ ] CLI: aws rds failover-db-cluster

TARGET INSTANCE (if forcing specific failover):
- [INSTANCE ID or "aurora chooses"]

POST-FAILOVER CHECKS:
- [ ] New writer is a different instance from old writer
- [ ] Cluster endpoint DNS points to new writer
- [ ] Reader endpoint is still accessible
- [ ] Application can write data
- [ ] Application can read data

ROLLBACK PLAN:
- If something goes wrong, run: aws rds failover-db-cluster again to failover back
```

Fill in this template for your Aurora cluster before proceeding.

---

## Part 2 - Set Up a Connection Monitor

This script runs continuously and times the failover. Run it in a dedicated terminal window.

Save this as `/tmp/monitor-failover.sh`:

```bash
#!/bin/bash

ENDPOINT="my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com"
USER="postgres"
DB="postgres"

echo "Starting connection monitor. Press Ctrl+C to stop."
echo "Timestamp | Status | Server IP | Postmaster Start"
echo "----------|--------|-----------|------------------"

FAILOVER_START=""
FAILOVER_END=""

while true; do
  RESULT=$(psql -h "$ENDPOINT" -U "$USER" -d "$DB" \
    -t -c "SELECT inet_server_addr()::text || '|' || pg_postmaster_start_time()::text" \
    2>&1)

  if echo "$RESULT" | grep -q "|"; then
    SERVER_IP=$(echo "$RESULT" | awk -F'|' '{print $1}' | tr -d ' ')
    START_TIME=$(echo "$RESULT" | awk -F'|' '{print $2}' | tr -d ' ')
    echo "$(date -u +%H:%M:%S) | OK | $SERVER_IP | $START_TIME"
    if [ -n "$FAILOVER_START" ] && [ -z "$FAILOVER_END" ]; then
      FAILOVER_END=$(date -u +%s)
      DOWNTIME=$((FAILOVER_END - FAILOVER_START))
      echo ">>> FAILOVER COMPLETE. Downtime: ${DOWNTIME} seconds"
    fi
  else
    if [ -z "$FAILOVER_START" ]; then
      FAILOVER_START=$(date -u +%s)
      echo "$(date -u +%H:%M:%S) | FAIL | Connection error - failover started"
    else
      echo "$(date -u +%H:%M:%S) | FAIL | Still recovering..."
    fi
  fi

  sleep 1
done
```

Make it executable and run it:

```bash
chmod +x /tmp/monitor-failover.sh
/tmp/monitor-failover.sh
```

Expected output (before failover):
```
Timestamp | Status | Server IP | Postmaster Start
----------|--------|-----------|------------------
15:00:01  | OK     | 10.0.1.23 | 2024-01-15 10:00:00
15:00:02  | OK     | 10.0.1.23 | 2024-01-15 10:00:00
15:00:03  | OK     | 10.0.1.23 | 2024-01-15 10:00:00
```

Leave this running.

---

## Part 3 - Record Pre-Failover State

In a second terminal, run these commands and save the output:

```bash
# Record current writer
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

```bash
# Record current DNS resolution for the writer endpoint
dig +short my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

```bash
# Record replica lag
psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres -d postgres \
     -c "SELECT now() - pg_last_xact_replay_timestamp() AS lag;"
```

Write down these values in your test plan.

---

## Part 4 - Execute the Failover

Note the exact time before running:

```bash
echo "FAILOVER TRIGGERED AT: $(date -u)"
```

Run the failover:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --region us-east-1
```

Watch your monitor terminal. You will see:

```
15:05:00  | OK     | 10.0.1.23 | 2024-01-15 10:00:00
15:05:01  | OK     | 10.0.1.23 | 2024-01-15 10:00:00
15:05:02  | FAIL   | Connection error - failover started
15:05:03  | FAIL   | Still recovering...
...
15:05:22  | OK     | 10.0.2.45 | 2024-01-15 15:05:20
>>> FAILOVER COMPLETE. Downtime: 20 seconds
```

The key observations:
1. The server IP changed (10.0.1.23 -> 10.0.2.45) - you are now on a different instance
2. The `pg_postmaster_start_time` is recent - the new writer just started
3. The downtime was 20 seconds in this example

---

## Part 5 - Record Post-Failover State

```bash
# Confirm new writer
aws rds describe-db-clusters \
  --db-cluster-identifier my-aurora-cluster \
  --query 'DBClusters[0].DBClusterMembers[*].{Instance:DBInstanceIdentifier,Writer:IsClusterWriter}' \
  --output table \
  --region us-east-1
```

```bash
# Confirm DNS updated
dig +short my-aurora-cluster.cluster-xxxx.us-east-1.rds.amazonaws.com
```

The IP from dig should be different from what you recorded before failover.

```bash
# Check events
aws rds describe-events \
  --source-identifier my-aurora-cluster \
  --source-type db-cluster \
  --duration 30 \
  --region us-east-1
```

Expected output (yours will differ):
```json
{
    "Events": [
        {
            "Message": "A failover for the DB cluster has started.",
            "Date": "2024-01-15T15:05:02.000Z"
        },
        {
            "Message": "DB cluster failover completed. my-aurora-reader-1 is now the writer instance.",
            "Date": "2024-01-15T15:05:22.000Z"
        }
    ]
}
```

---

## Part 6 - Write the Test Results

Fill in this results template:

```
FAILOVER TEST RESULTS
=====================
Date/Time: [DATE TIME UTC]
Cluster: [CLUSTER NAME]
Tester: [YOUR NAME]

PRE-FAILOVER STATE:
  Writer: [INSTANCE ID]
  Writer IP: [IP ADDRESS]
  Reader lag: [X ms]

FAILOVER EXECUTION:
  Method: [CLI / Console]
  Trigger time: [HH:MM:SS UTC]
  First error time: [HH:MM:SS UTC]
  Recovery time: [HH:MM:SS UTC]

MEASURED DOWNTIME: [N seconds]
TARGET RTO: [N seconds]
RESULT: [PASS / FAIL]

POST-FAILOVER STATE:
  New writer: [INSTANCE ID]
  New writer IP: [IP ADDRESS]
  DNS updated: [YES - confirmed by dig]

ISSUES FOUND:
  [List any problems observed]

RECOMMENDATIONS:
  [List any improvements to make]

NEXT TEST DATE:
  [When will you run this again?]
```

---

## Part 7 - Additional Exercises

### Exercise A - Test Reader Endpoint During Failover

During your next failover test, watch the reader endpoint too:

```bash
# Run this in a third terminal during failover
while true; do
  psql -h my-aurora-cluster.cluster-ro-xxxx.us-east-1.rds.amazonaws.com \
       -U postgres -d postgres \
       -c "SELECT inet_server_addr(), pg_is_in_recovery();" 2>&1
  sleep 1
done
```

**Question:** Does the reader endpoint experience downtime during a writer failover? Why or why not?

### Exercise B - Failover with a Specific Target

Force the failover to go to a specific reader:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --target-db-instance-identifier my-aurora-reader-2 \
  --region us-east-1
```

**Question:** Does failover time differ when you specify a target vs letting Aurora choose?

### Exercise C - Failover Back to Original

After the failover, the original writer is now a reader. Failover back to it:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier my-aurora-cluster \
  --target-db-instance-identifier my-aurora-writer \
  --region us-east-1
```

Run this test and measure the downtime. Is it the same as the first failover?

---

## Key Things to Record for a Production Runbook

1. Exact failover command with correct cluster identifier and region
2. Who is authorized to trigger failover (approval chain)
3. Application connection retry settings (must retry connections automatically)
4. Post-failover validation steps (check writer, check lag, run test query)
5. Rollback procedure
6. Who to notify (oncall, stakeholders)
7. Historical RTO data (so you know what to expect)

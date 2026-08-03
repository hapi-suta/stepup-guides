# USE Exercise 05: Build and Run Fleet-Wide Health Check

**Objective:** Build a complete fleet-wide health check system, run it against your RDS instances, interpret the results, and deliver a fleet health report.
**Time:** 40-50 minutes
**Level:** Expert
**infra_required:** true - Requires at least two running RDS or Aurora instances. Lambda and EventBridge permissions.
**Prerequisites:** Build Guide 09 completed.

---

## Context

You are the platform DBA at [COMPANY]. Engineering leadership has asked for a weekly "database fleet health report" that answers three questions:

1. Is every database in the fleet operating within healthy parameters right now?
2. Which databases have trends that suggest problems in the next 30 days?
3. What action items exist from this week's health check?

You need to build this system and deliver the first report by end of day.

---

## Part 1: Build the CloudWatch-Based Health Check Script

Build a shell script that checks CloudWatch metrics for all RDS instances in the account and outputs a structured health report.

**Task 1.1:** Create the health check script at `/tmp/rds-fleet-health.sh`:

```bash
#!/usr/bin/env bash
# RDS Fleet Health Check
# Usage: bash rds-fleet-health.sh [REGION]

REGION=${1:-us-east-1}
REPORT_DATE=$(date +%Y-%m-%d)
REPORT_TIME=$(date +%H:%M:%S)
ISSUES=()
WARNINGS=()

echo "==========================================="
echo "RDS Fleet Health Report"
echo "Date: ${REPORT_DATE} ${REPORT_TIME} UTC"
echo "Region: ${REGION}"
echo "==========================================="

# Get all RDS instances
INSTANCES=$(aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,MultiAZ,StorageEncrypted]' \
  --output text \
  --region ${REGION})

INSTANCE_COUNT=$(echo "${INSTANCES}" | wc -l | tr -d ' ')
echo ""
echo "Instances found: ${INSTANCE_COUNT}"
echo ""

while IFS=$'\t' read -r INSTANCE_ID INSTANCE_CLASS STATUS MULTI_AZ ENCRYPTED; do
  echo "--- ${INSTANCE_ID} (${INSTANCE_CLASS}) ---"

  # Status check
  if [[ "${STATUS}" != "available" ]]; then
    echo "  [ISSUE] Status: ${STATUS} (expected: available)"
    ISSUES+=("${INSTANCE_ID}: Status=${STATUS}")
  else
    echo "  [OK] Status: ${STATUS}"
  fi

  # Encryption check
  if [[ "${ENCRYPTED}" == "False" ]]; then
    echo "  [ISSUE] Encryption: DISABLED"
    ISSUES+=("${INSTANCE_ID}: Storage not encrypted")
  else
    echo "  [OK] Encryption: enabled"
  fi

  # Multi-AZ check (for production-tagged instances)
  ENVIRONMENT=$(aws rds list-tags-for-resource \
    --resource-name "arn:aws:rds:${REGION}:$(aws sts get-caller-identity --query Account --output text):db:${INSTANCE_ID}" \
    --query 'TagList[?Key==`Environment`].Value' \
    --output text \
    --region ${REGION} 2>/dev/null)

  if [[ "${ENVIRONMENT}" == "production" && "${MULTI_AZ}" == "False" ]]; then
    echo "  [WARN] Multi-AZ: DISABLED on production instance"
    WARNINGS+=("${INSTANCE_ID}: Production instance without Multi-AZ")
  fi

  # CPU check (last 15 min average)
  CPU=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
    --start-time $(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
    --period 900 \
    --statistics Average \
    --region ${REGION} \
    --query 'Datapoints[0].Average' \
    --output text 2>/dev/null)

  if [[ "${CPU}" != "None" && "${CPU}" != "" ]]; then
    CPU_INT=${CPU%.*}
    if [[ ${CPU_INT} -gt 80 ]]; then
      echo "  [WARN] CPU: ${CPU}% (threshold: 80%)"
      WARNINGS+=("${INSTANCE_ID}: CPU=${CPU}%")
    else
      echo "  [OK] CPU: ${CPU}%"
    fi
  else
    echo "  [SKIP] CPU: no data available"
  fi

  # Connections check
  CONNS=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name DatabaseConnections \
    --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
    --start-time $(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
    --period 900 \
    --statistics Maximum \
    --region ${REGION} \
    --query 'Datapoints[0].Maximum' \
    --output text 2>/dev/null)

  if [[ "${CONNS}" != "None" && "${CONNS}" != "" ]]; then
    echo "  [OK] Connections (max): ${CONNS}"
  fi

  # Free storage check
  FREE_BYTES=$(aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name FreeStorageSpace \
    --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
    --start-time $(date -u -v-15M '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '15 minutes ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
    --period 900 \
    --statistics Minimum \
    --region ${REGION} \
    --query 'Datapoints[0].Minimum' \
    --output text 2>/dev/null)

  if [[ "${FREE_BYTES}" != "None" && "${FREE_BYTES}" != "" ]]; then
    # Get allocated storage in GB
    ALLOC=$(aws rds describe-db-instances \
      --db-instance-identifier ${INSTANCE_ID} \
      --query 'DBInstances[0].AllocatedStorage' \
      --output text \
      --region ${REGION})
    ALLOC_BYTES=$((ALLOC * 1024 * 1024 * 1024))
    FREE_PCT=$((${FREE_BYTES%.*} * 100 / ALLOC_BYTES))

    if [[ ${FREE_PCT} -lt 10 ]]; then
      echo "  [ISSUE] Free Storage: ${FREE_PCT}% (CRITICAL - < 10%)"
      ISSUES+=("${INSTANCE_ID}: Free storage critically low (${FREE_PCT}%)")
    elif [[ ${FREE_PCT} -lt 20 ]]; then
      echo "  [WARN] Free Storage: ${FREE_PCT}% (< 20%)"
      WARNINGS+=("${INSTANCE_ID}: Free storage low (${FREE_PCT}%)")
    else
      echo "  [OK] Free Storage: ${FREE_PCT}%"
    fi
  fi

  echo ""
done <<< "${INSTANCES}"

# Summary
echo "==========================================="
echo "HEALTH SUMMARY"
echo "==========================================="
echo "Critical issues: ${#ISSUES[@]}"
for ISSUE in "${ISSUES[@]}"; do
  echo "  [CRITICAL] ${ISSUE}"
done
echo ""
echo "Warnings: ${#WARNINGS[@]}"
for WARN in "${WARNINGS[@]}"; do
  echo "  [WARNING] ${WARN}"
done
echo ""

if [[ ${#ISSUES[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
  echo "Fleet status: ALL HEALTHY"
else
  echo "Fleet status: ATTENTION REQUIRED"
fi
echo "==========================================="
```

**Task 1.2:** Run the script:

```bash
chmod +x /tmp/rds-fleet-health.sh
bash /tmp/rds-fleet-health.sh [REGION] | tee /tmp/fleet-health-report-$(date +%Y%m%d).txt
```

**Deliverable:** The complete output of the health check script saved to a file.

---

## Part 2: SQL-Based Internal Health Check

For instances you have direct connectivity to, run the internal PostgreSQL health checks.

**Task 2.1:** Connect to each instance using the `diagnostics_reader` user you created in Build Guide 09 (or the master user if the diagnostics user is not set up).

**Task 2.2:** Run the triage query library from Build Guide 09:

```sql
-- 1. Instance overview
SELECT
  current_database(),
  (SELECT count(*) FROM pg_stat_activity WHERE state != 'idle') AS active_conn,
  (SELECT count(*) FROM pg_stat_activity) AS total_conn,
  current_setting('max_connections')::int AS max_conn;

-- 2. Wraparound check
SELECT datname, age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS remaining,
       round(age(datfrozenxid) * 100.0 / 2000000000, 2) AS pct_of_limit
FROM pg_database
ORDER BY xid_age DESC;

-- 3. Bloat check
SELECT relname, n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct
FROM pg_stat_user_tables
WHERE n_live_tup > 10000
ORDER BY dead_pct DESC NULLS LAST
LIMIT 10;

-- 4. Long-running queries
SELECT pid, now() - query_start AS duration, state, left(query, 80) AS query
FROM pg_stat_activity
WHERE state != 'idle'
AND query_start < now() - interval '5 minutes'
ORDER BY duration DESC;

-- 5. Cache hit ratio
SELECT round(
  sum(heap_blks_hit)::numeric /
  NULLIF(sum(heap_blks_hit) + sum(heap_blks_read), 0) * 100, 2
) AS cache_hit_ratio
FROM pg_statio_user_tables;
```

**Task 2.3:** For each check, document the result and classify it as:
- GREEN: Within normal parameters
- YELLOW: Worth monitoring, not urgent
- RED: Requires action

**Deliverable:** Completed health check results for each instance you can connect to.

---

## Part 3: Trend Analysis

**Task 3.1:** Pull 7-day CPU utilization trends for each instance:

```bash
for INSTANCE_ID in [INSTANCE-1] [INSTANCE-2]; do
  echo "=== CPU Trend: ${INSTANCE_ID} ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/RDS \
    --metric-name CPUUtilization \
    --dimensions Name=DBInstanceIdentifier,Value=${INSTANCE_ID} \
    --start-time $(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ') \
    --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
    --period 86400 \
    --statistics Average,Maximum \
    --region [REGION] \
    --query 'sort_by(Datapoints, &Timestamp)[*].[Timestamp,Average,Maximum]' \
    --output table
done
```

**Task 3.2:** Pull 7-day free storage trend for each instance. A monotonically decreasing FreeStorageSpace indicates data growth that, if unchecked, will become a storage exhaustion incident.

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name FreeStorageSpace \
  --dimensions Name=DBInstanceIdentifier,Value=[INSTANCE-ID] \
  --start-time $(date -u -v-7d '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -d '7 days ago' '+%Y-%m-%dT%H:%M:%SZ') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%SZ') \
  --period 86400 \
  --statistics Minimum \
  --region [REGION] \
  --query 'sort_by(Datapoints, &Timestamp)[*].[Timestamp,Minimum]' \
  --output table
```

**Task 3.3:** Extrapolate the storage trend. If FreeStorageSpace is decreasing by X bytes per day, calculate:
- Days until 20% free (warning threshold)
- Days until 10% free (critical threshold)
- Days until 0% free (outage)

---

## Part 4: Produce the Fleet Health Report

Using all data gathered in Parts 1-3, produce the weekly fleet health report.

```
RDS FLEET HEALTH REPORT
Week of: [DATE]
Prepared by: [YOUR NAME]
Region: [REGION]

FLEET OVERVIEW
Total instances: [N]
Healthy (all checks pass): [N]
Warning (1+ yellow checks): [N]
Critical (1+ red checks): [N]

CRITICAL ITEMS REQUIRING IMMEDIATE ACTION
[List each critical finding with the instance affected and the action required]

WARNING ITEMS - MONITOR OR PLAN ACTION
[List each warning finding with the instance affected and the recommended timeline]

TRENDS OF CONCERN
[List any instances showing negative trends over the past 7 days]
[Include projected date when trend becomes a problem]

CAPACITY OUTLOOK - NEXT 30 DAYS
[Which instances are projected to need storage expansion?]
[Which instances are projected to reach CPU saturation?]

COMPLIANCE SPOT CHECK
[Any instances missing required tags, encryption, Multi-AZ, or audit logging?]

ACTION ITEMS
| Priority | Instance | Issue | Owner | Due Date |
|----------|----------|-------|-------|----------|
| P1       |          |       |       |          |

NO FINDINGS THIS WEEK
[List instances with zero findings - these can be deprioritized]
```

---

## Part 5: Automate for Next Week

**Task 5.1:** Create a Lambda function to run the CloudWatch-based checks automatically.

Use the Python Lambda template from Build Guide 09 as your base. Modify it to:
- Run on a schedule (every Monday at 8:00 AM UTC)
- Send the summary to your SNS topic (which routes to email or Slack)
- Store the full JSON report in S3 under `s3://[BUCKET]/fleet-health/[YEAR]/[WEEK]/`

**Task 5.2:** Create the EventBridge rule:

```bash
aws events put-rule \
  --name weekly-rds-fleet-health \
  --schedule-expression "cron(0 8 ? * MON *)" \
  --description "Weekly RDS fleet health check every Monday at 8 AM UTC" \
  --state ENABLED \
  --region [REGION]
```

`cron(0 8 ? * MON *)` - runs at 08:00 UTC every Monday.

**Task 5.3:** Verify the schedule was created:

```bash
aws events describe-rule \
  --name weekly-rds-fleet-health \
  --region [REGION]
```

---

## Reflection Questions

1. Your health check script takes 8 minutes to run across 40 instances because it makes sequential CloudWatch API calls. How would you redesign the Lambda function to complete the same check in under 1 minute?

2. The health report shows one instance with 73% CPU average over 7 days. The trend is flat (not growing). Is this a problem? What additional information do you need to make a recommendation?

3. You present the first fleet health report to engineering leadership. They ask: "Can you automate all the action items, not just detection?" How do you answer? Which action items are safe to automate, and which require human decision?

4. Your fleet grows from 5 instances to 50 instances over the next year. How does your health check system need to evolve? What breaks at 50 instances that works fine at 5?

5. The health check Lambda function connects to each database directly to run SQL triage queries. What security controls do you put around this? (IAM, network, credential management)

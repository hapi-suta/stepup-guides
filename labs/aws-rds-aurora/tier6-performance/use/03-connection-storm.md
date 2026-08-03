# USE 03 - Handle a Connection Storm and Set Up RDS Proxy

**Time:** 50 minutes
**Difficulty:** Advanced
**Prerequisites:** Build 01, 09 complete. RDS instance. Secrets Manager access. IAM permissions.

---

## Objective

Simulate a connection storm (sudden spike to near max_connections), diagnose the impact, implement immediate mitigation, then deploy RDS Proxy as the permanent solution. Verify that RDS Proxy successfully absorbs the connection spike.

---

## Part 1 - Simulate the Connection Storm

### Check Current max_connections

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SHOW max_connections;"
```

Note the value. For this exercise you will open connections to 90% of that limit.

### Calculate the storm size

```bash
MAX_CONN=$(psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -t \
  -c "SHOW max_connections;" | tr -d ' ')
STORM_CONN=$(( MAX_CONN * 90 / 100 ))
echo "Will open $STORM_CONN connections out of $MAX_CONN max"
```

### Open the connection storm

```bash
echo "Opening $STORM_CONN connections..."
for i in $(seq 1 "$STORM_CONN"); do
  psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT pg_sleep(300);" &
done
echo "Storm started. Background PIDs: $(jobs -p | wc -l)"
```

Wait 30 seconds, then try to open one more connection:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT 'connected' AS status;"
```

If max_connections is fully saturated, this will fail with:

```
FATAL:  sorry, too many clients already
```

---

## Part 2 - Diagnose the Impact

While the storm is active, run these diagnostics from a terminal that still has a connection (or use the RDS Console):

### Check connection count via CloudWatch

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=DBInstanceIdentifier,Value="$DB_INSTANCE_ID" \
  --start-time "$(date -u -v-10M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='10 minutes ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 60 \
  --statistics Maximum \
  --region "$REGION"
```

### Check wait events in Performance Insights

Open the Performance Insights dashboard in the AWS Console. You should see `Client:ClientRead` dominating the DB Load chart - sessions are holding connections but waiting for queries.

### Analyze via pg_stat_activity (if you can still get a connection)

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT
    state,
    count(*) AS sessions,
    sum(CASE WHEN wait_event IS NOT NULL THEN 1 ELSE 0 END) AS waiting
FROM pg_stat_activity
GROUP BY state
ORDER BY sessions DESC;"
```

Expected output (yours will differ):
```
        state        | sessions | waiting
---------------------+----------+---------
 active              |      432 |     432
 idle                |       12 |       0
```

### Terminate Idle Connections (Immediate Mitigation)

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle'
  AND pid != pg_backend_pid();"
```

### Stop the Storm

```bash
pkill -f "psql.*pg_sleep"
jobs -p | xargs kill 2>/dev/null
```

Verify connections dropped:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT count(*) FROM pg_stat_activity;"
```

---

## Part 3 - Deploy RDS Proxy as the Permanent Solution

Follow the steps from Build 09 to deploy an RDS Proxy. If you already have one, skip to Part 4.

Quick setup:

```bash
# Store credentials
aws secretsmanager create-secret \
  --name "rds-proxy/${DB_INSTANCE_ID}" \
  --secret-string "{\"username\":\"${DB_USER}\",\"password\":\"YOUR_PASSWORD\"}" \
  --region "$REGION"

export SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "rds-proxy/${DB_INSTANCE_ID}" \
  --query ARN --output text --region "$REGION")

# Create IAM role (abbreviated - see Build 09 for full steps)
# ... (complete IAM role creation from Build 09 steps 2-3)

# Create proxy
aws rds create-db-proxy \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --engine-family POSTGRESQL \
  --auth "[{\"AuthScheme\":\"SECRETS\",\"SecretArn\":\"${SECRET_ARN}\",\"IAMAuth\":\"DISABLED\"}]" \
  --role-arn "$PROXY_ROLE_ARN" \
  --vpc-subnet-ids $SUBNET_IDS \
  --vpc-security-group-ids "$SG_ID" \
  --require-tls \
  --region "$REGION"

aws rds wait db-proxy-available \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --region "$REGION"

export PROXY_ENDPOINT=$(aws rds describe-db-proxies \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --query "DBProxies[0].Endpoint" --output text --region "$REGION")

echo "Proxy ready at: $PROXY_ENDPOINT"
```

---

## Part 4 - Verify Proxy Absorbs the Storm

Configure the proxy's connection pool to limit DB connections:

```bash
# Get the target group
TARGET_GROUP=$(aws rds describe-db-proxy-target-groups \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --query "TargetGroups[0].TargetGroupName" --output text --region "$REGION")

# Modify the pool: allow proxy to use at most 30% of max_connections
aws rds modify-db-proxy-target-group \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --target-group-name "$TARGET_GROUP" \
  --connection-pool-config MaxConnectionsPercent=30 \
  --region "$REGION"
```

`MaxConnectionsPercent=30`: The proxy will use at most 30% of max_connections for its pool. App clients can still connect in the thousands - the proxy queues them.

Now repeat the connection storm, but this time connect through the proxy:

```bash
# Storm through the proxy - 3x more connections than max_connections allows
STORM_SIZE=$(( MAX_CONN * 3 ))
echo "Opening $STORM_SIZE connections through proxy..."
for i in $(seq 1 "$STORM_SIZE"); do
  psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT pg_sleep(60);" &
done
echo "Storm through proxy started"
```

Check how many connections the database actually has:

```bash
sleep 10
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT count(*) AS db_connections FROM pg_stat_activity;"
```

Expected output (yours will differ):
```
 db_connections
----------------
             96
```

3x max_connections worth of app connections, but the database only sees 96 (30% of max_connections). The proxy is multiplexing.

Stop the proxy storm:

```bash
pkill -f "psql.*pg_sleep"
```

---

## Task Completion Checklist

- [ ] Successfully simulated a connection storm reaching 90% of max_connections
- [ ] Identified `Client:ClientRead` as the dominant wait event during the storm
- [ ] Terminated idle connections as immediate mitigation
- [ ] Deployed RDS Proxy with 30% max_connections pool
- [ ] Demonstrated that 3x max_connections of app connections = only 30% DB connections
- [ ] Recorded before/after connection counts

---

## Key Takeaway

Without RDS Proxy: one app connection = one DB connection. A storm of 500 connections hits the database directly.
With RDS Proxy: the proxy queues excess connections and multiplexes them. The database sees only as many connections as you configure.

For serverless functions (Lambda) that can spike to thousands of concurrent invocations, RDS Proxy is not optional - it is required.

---

## Cleanup

```bash
aws rds delete-db-proxy \
  --db-proxy-name "proxy-storm-${DB_INSTANCE_ID}" \
  --region "$REGION"

aws secretsmanager delete-secret \
  --secret-id "rds-proxy/${DB_INSTANCE_ID}" \
  --force-delete-without-recovery \
  --region "$REGION"
```

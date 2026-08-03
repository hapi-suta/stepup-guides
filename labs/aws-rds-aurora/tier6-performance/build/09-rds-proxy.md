# Build 09 - RDS Proxy

**Time:** 45 minutes
**Goal:** Deploy an RDS Proxy, configure it with Secrets Manager credentials, test connection multiplexing, measure connection overhead reduction, and understand connection pinning.
**Prerequisites:** RDS PostgreSQL instance. AWS CLI configured. `$DB_INSTANCE_ID`, `$REGION`, `$DB_ENDPOINT` set. IAM permissions for RDS, Secrets Manager, and IAM role creation.

---

## Background

PostgreSQL spawns one OS process per connection. Each process consumes 5-10MB of RAM before any query memory. At 200 connections, that is 1-2GB of overhead. At 500, you are looking at 2.5-5GB just for connection overhead.

More critically, PostgreSQL's process-per-connection model has scaling limits. Context switching between hundreds of processes degrades overall throughput even when each individual query is fast.

RDS Proxy sits between your application and the database. Applications connect to the proxy (which accepts thousands of connections), and the proxy maintains a small pool of long-lived connections to PostgreSQL. The proxy multiplexes: many app connections share few DB connections.

The proxy also provides transparent failover - if the database fails over, the proxy reconnects to the new primary and the application connection stays alive (with a brief pause).

---

## Step 1 - Store Database Credentials in Secrets Manager

RDS Proxy requires credentials to be stored in AWS Secrets Manager. It fetches and rotates them automatically.

Create the secret:

```bash
aws secretsmanager create-secret \
  --name "rds-proxy-credentials/${DB_INSTANCE_ID}" \
  --description "PostgreSQL credentials for RDS Proxy" \
  --secret-string "{\"username\":\"${DB_USER}\",\"password\":\"your-db-password\"}" \
  --region "$REGION"
```

`--secret-string`: JSON string with the username and password keys. RDS Proxy expects exactly these key names.

Save the secret ARN:

```bash
export SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "rds-proxy-credentials/${DB_INSTANCE_ID}" \
  --query SecretString \
  --region "$REGION" 2>/dev/null | head -1)

# Better approach: get the ARN
export SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id "rds-proxy-credentials/${DB_INSTANCE_ID}" \
  --query ARN \
  --output text \
  --region "$REGION")

echo "Secret ARN: $SECRET_ARN"
```

Expected output (yours will differ):
```
Secret ARN: arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-proxy-credentials/mydb-AbCdEf
```

---

## Step 2 - Create an IAM Role for RDS Proxy

RDS Proxy needs an IAM role to access your secret in Secrets Manager.

Create the trust policy file:

```bash
cat > /tmp/proxy-trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "rds.amazonaws.com"
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
  --role-name "rds-proxy-role-${DB_INSTANCE_ID}" \
  --assume-role-policy-document file:///tmp/proxy-trust-policy.json \
  --description "IAM role for RDS Proxy to access Secrets Manager"
```

Create the permissions policy:

```bash
cat > /tmp/proxy-permissions.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "secretsmanager:GetSecretValue",
      "Resource": "${SECRET_ARN}"
    },
    {
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "secretsmanager.${REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
```

Attach the policy:

```bash
aws iam put-role-policy \
  --role-name "rds-proxy-role-${DB_INSTANCE_ID}" \
  --policy-name "rds-proxy-secrets-access" \
  --policy-document file:///tmp/proxy-permissions.json
```

Save the role ARN:

```bash
export PROXY_ROLE_ARN=$(aws iam get-role \
  --role-name "rds-proxy-role-${DB_INSTANCE_ID}" \
  --query Role.Arn \
  --output text)

echo "Proxy Role ARN: $PROXY_ROLE_ARN"
```

---

## Step 3 - Get Your VPC and Security Group Information

```bash
# Get VPC ID from your RDS instance
export VPC_ID=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].DBSubnetGroup.VpcId" \
  --output text \
  --region "$REGION")

echo "VPC ID: $VPC_ID"

# Get subnet IDs
export SUBNET_IDS=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].DBSubnetGroup.Subnets[*].SubnetIdentifier" \
  --output text \
  --region "$REGION")

echo "Subnet IDs: $SUBNET_IDS"

# Get security group ID
export SG_ID=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" \
  --output text \
  --region "$REGION")

echo "Security Group: $SG_ID"
```

---

## Step 4 - Create the RDS Proxy

### Via Console

1. Open the [RDS Console](https://console.aws.amazon.com/rds/).
2. Click **Proxies** in the left menu.
3. Click **Create proxy**.
4. Under **Proxy configuration**:
   - Proxy identifier: `proxy-${DB_INSTANCE_ID}` (no spaces)
   - Engine compatibility: **PostgreSQL**
   - Require Transport Layer Security: checked (recommended)
   - Idle client connection timeout: **1800** seconds
5. Under **Target group configuration**:
   - Database: select your RDS instance
   - Connection pool maximum connections: **100** (percentage of max_connections the proxy can use)
   - Connection borrow timeout: **120** seconds
6. Under **Authentication**:
   - Add the Secrets Manager secret you created
   - IAM authentication: **Required** or **Allowed**
7. Under **Connectivity**:
   - VPC: select your VPC
   - Subnets: select at least 2 subnets (different AZs)
   - VPC security group: select the security group
8. Click **Create proxy**.

### Via CLI

Format the subnet IDs for the CLI (comma-separated):

```bash
SUBNET_ARRAY=$(aws rds describe-db-instances \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --query "DBInstances[0].DBSubnetGroup.Subnets[*].SubnetIdentifier" \
  --output json \
  --region "$REGION")
```

Create the proxy:

```bash
aws rds create-db-proxy \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --engine-family POSTGRESQL \
  --auth "[{\"AuthScheme\":\"SECRETS\",\"SecretArn\":\"${SECRET_ARN}\",\"IAMAuth\":\"DISABLED\"}]" \
  --role-arn "$PROXY_ROLE_ARN" \
  --vpc-subnet-ids $(aws rds describe-db-instances \
    --db-instance-identifier "$DB_INSTANCE_ID" \
    --query "DBInstances[0].DBSubnetGroup.Subnets[*].SubnetIdentifier" \
    --output text \
    --region "$REGION") \
  --vpc-security-group-ids "$SG_ID" \
  --require-tls \
  --region "$REGION"
```

Each flag explained:
- `--engine-family POSTGRESQL`: Required to specify which protocol the proxy understands.
- `--auth`: JSON array with authentication configuration. `SECRETS` means use Secrets Manager.
- `--role-arn`: The IAM role the proxy uses to access Secrets Manager.
- `--require-tls`: Enforce encrypted connections between proxy and database.

Wait for the proxy to become available (takes 2-5 minutes):

```bash
aws rds wait db-proxy-available \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --region "$REGION"
```

---

## Step 5 - Register the Target

Associate the proxy with your RDS instance:

```bash
# Get the default target group name
export TARGET_GROUP=$(aws rds describe-db-proxy-target-groups \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --query "TargetGroups[0].TargetGroupName" \
  --output text \
  --region "$REGION")

# Register the target
aws rds register-db-proxy-targets \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --target-group-name "$TARGET_GROUP" \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"
```

`--db-instance-identifier`: The RDS instance the proxy connects to. For Aurora, use `--db-cluster-identifier` instead.

---

## Step 6 - Get the Proxy Endpoint

```bash
export PROXY_ENDPOINT=$(aws rds describe-db-proxies \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --query "DBProxies[0].Endpoint" \
  --output text \
  --region "$REGION")

echo "Proxy Endpoint: $PROXY_ENDPOINT"
```

Expected output (yours will differ):
```
Proxy Endpoint: proxy-mydb-instance.proxy-abcdef123456.us-east-1.rds.amazonaws.com
```

---

## Step 7 - Connect Through the Proxy

Connect using the proxy endpoint instead of the direct instance endpoint:

```bash
psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -p 5432
```

Verify you are connected through the proxy:

```sql
SELECT current_setting('server_version');
SELECT inet_server_addr();
```

Expected output (yours will differ):
```
 current_setting
-----------------
 16.1
```

The connection works exactly the same as a direct connection. The proxy is transparent to the application.

---

## Step 8 - Test Connection Multiplexing

Open 20 connections through the proxy simultaneously and observe how many connections the database actually sees:

```bash
# Open 20 connections through the proxy
for i in $(seq 1 20); do
  psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
    -c "SELECT pg_sleep(30);" &
done

echo "20 connections open through proxy"
```

In another terminal, check how many connections the database actually has:

```bash
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" \
  -c "SELECT count(*) AS db_connections FROM pg_stat_activity;"
```

Expected output (yours will differ):
```
 db_connections
----------------
              6
```

20 app connections became 6 database connections. This is multiplexing in action.

Kill the background connections:

```bash
pkill -f "psql.*pg_sleep"
```

---

## Step 9 - Understand Connection Pinning

Pinning breaks multiplexing. When pinning occurs, one app connection = one DB connection.

Test pinning with a SET command:

```bash
psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME"
```

```sql
-- This pins the connection
SET work_mem = '256MB';

-- All subsequent queries in this session are pinned
SELECT count(*) FROM pg_stat_activity;
```

Check the proxy logs for pinning events:

```bash
aws logs filter-log-events \
  --log-group-name "/aws/rds/proxy/proxy-${DB_INSTANCE_ID}" \
  --filter-pattern "Pinned" \
  --region "$REGION" \
  --limit 10
```

To avoid pinning, set parameters at the parameter group level (not via SET), use transaction-level advisory locks (not session-level), and avoid temp tables in pooled connections.

---

## Step 10 - Monitor the Proxy

View proxy metrics in CloudWatch:

```bash
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name DatabaseConnections \
  --dimensions Name=ProxyName,Value="proxy-${DB_INSTANCE_ID}" \
  --start-time "$(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u --date='1 hour ago' +%Y-%m-%dT%H:%M:%SZ)" \
  --end-time "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --period 300 \
  --statistics Average \
  --region "$REGION"
```

Key proxy metrics:

| Metric | What It Measures | Alert Threshold |
|--------|-----------------|-----------------|
| DatabaseConnections | Client connections to proxy | Near max per proxy |
| DatabaseConnectionRequests | Connection requests per second | Trending up rapidly |
| DatabaseConnectionsSetupFailed | Failed connection setups | > 0 sustained |
| QueryDatabaseResponseLatency | Latency from proxy to DB | > 2x baseline |
| ClientConnectionsReceived | New client connections/minute | Spike = connection storm |
| DatabaseConnectionsSetupSucceeded | Successful setups | Trending down = problem |
| Pinned Connections | Sessions that cannot multiplex | > 50% = redesign app |

---

## Cleanup

```bash
# Deregister the target
aws rds deregister-db-proxy-targets \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --target-group-name "$TARGET_GROUP" \
  --db-instance-identifier "$DB_INSTANCE_ID" \
  --region "$REGION"

# Delete the proxy
aws rds delete-db-proxy \
  --db-proxy-name "proxy-${DB_INSTANCE_ID}" \
  --region "$REGION"

# Delete the secret
aws secretsmanager delete-secret \
  --secret-id "rds-proxy-credentials/${DB_INSTANCE_ID}" \
  --force-delete-without-recovery \
  --region "$REGION"

# Delete the IAM role
aws iam delete-role-policy \
  --role-name "rds-proxy-role-${DB_INSTANCE_ID}" \
  --policy-name "rds-proxy-secrets-access"

aws iam delete-role \
  --role-name "rds-proxy-role-${DB_INSTANCE_ID}"
```

---

## Summary

You have:
- Stored DB credentials in Secrets Manager
- Created an IAM role for proxy-to-Secrets-Manager access
- Deployed an RDS Proxy
- Connected through the proxy and observed multiplexing (20 app connections -> 6 DB connections)
- Understood connection pinning and what causes it
- Set up CloudWatch monitoring for the proxy

RDS Proxy is most valuable for applications with short-lived connections (serverless functions, microservices) or applications that spike connections during high traffic. For applications with stable, long-lived connections, the multiplexing benefit is less dramatic.

---

## Core Concepts Quick Reference

| Term | Meaning |
|------|---------|
| Connection multiplexing | Multiple app connections sharing one DB connection when no session state exists |
| Connection pinning | An app connection that cannot be shared because it has session-level state |
| Proxy endpoint | The hostname applications connect to instead of the direct RDS endpoint |
| SECRETS auth scheme | Proxy fetches credentials from Secrets Manager, not from the application |
| IAMAuth | Optional: require IAM tokens in addition to or instead of DB passwords |
| Target group | The RDS instances the proxy routes connections to |
| Connection borrow timeout | Max time the proxy waits for a DB connection from the pool before erroring |

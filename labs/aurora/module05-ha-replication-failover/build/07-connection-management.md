# BUILD 07 - Connection Management: RDS Proxy Setup and Connection Pooling
## Estimated Time: 40 minutes

---

## What You Will Do

1. Create an RDS Proxy for your Aurora cluster
2. Configure IAM authentication for the proxy
3. Connect through the proxy and verify routing
4. Test failover behavior with the proxy
5. Compare connection behavior with and without proxy

> **Cost warning:** RDS Proxy pricing is based on vCPU of the underlying database instance. For db.t3.medium (2 vCPU), proxy costs ~$0.015/hr. Delete when done.

---

## Before You Start

You need:
- The Aurora cluster (`devops-lab-cluster`) from BUILD 01 with writer + reader
- AWS CLI v2 configured
- An IAM role for RDS Proxy (created in Step 1)
- A Secrets Manager secret with database credentials (created in Step 2)
- psql installed

---

## Step 1 - Create an IAM Role for RDS Proxy

RDS Proxy needs an IAM role to access Secrets Manager (where database credentials are stored).

**In your terminal:**

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

Create the IAM role:

```bash
aws iam create-role \
  --role-name devops-lab-proxy-role \
  --assume-role-policy-document file:///tmp/proxy-trust-policy.json
```

Note the role ARN from the output. You will need it later.

---

## Step 2 - Store Database Credentials in Secrets Manager

**In your terminal:**

```bash
aws secretsmanager create-secret \
  --name devops-lab-proxy-credentials \
  --description "Database credentials for RDS Proxy" \
  --secret-string '{"username":"postgres","password":"YourPassword123"}' \
  --region us-east-1
```

Note the secret ARN from the output.

Now attach a policy to the IAM role allowing it to read this secret:

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

cat > /tmp/proxy-secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:GetRandomPassword"
      ],
      "Resource": "arn:aws:secretsmanager:us-east-1:${ACCOUNT_ID}:secret:devops-lab-proxy-credentials*"
    }
  ]
}
EOF

aws iam put-role-policy \
  --role-name devops-lab-proxy-role \
  --policy-name secrets-access \
  --policy-document file:///tmp/proxy-secrets-policy.json
```

---

## Step 3 - Create the RDS Proxy

**In your terminal:**

Get your VPC subnet IDs and security group:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].{Subnets:DBSubnetGroup,VpcSGs:VpcSecurityGroups[*].VpcSecurityGroupId}' \
  --output json \
  --region us-east-1
```

Now create the proxy:

```bash
aws rds create-db-proxy \
  --db-proxy-name devops-lab-proxy \
  --engine-family POSTGRESQL \
  --auth '[{
    "AuthScheme": "SECRETS",
    "SecretArn": "arn:aws:secretsmanager:us-east-1:123456789012:secret:devops-lab-proxy-credentials-AbCdEf",
    "IAMAuth": "DISABLED"
  }]' \
  --role-arn arn:aws:iam::123456789012:role/devops-lab-proxy-role \
  --vpc-subnet-ids subnet-0abc123 subnet-0def456 \
  --vpc-security-group-ids sg-0abc123456789 \
  --region us-east-1
```

`--db-proxy-name` - the name for your proxy.
`--engine-family POSTGRESQL` - must match your database engine.
`--auth` - how the proxy authenticates. We use Secrets Manager here.
`SecretArn` - replace with your actual secret ARN from Step 2.
`--role-arn` - replace with your actual IAM role ARN from Step 1.
`--vpc-subnet-ids` - replace with your actual subnet IDs (must be in the same VPC as the database).
`--vpc-security-group-ids` - replace with your actual security group.

Expected output (yours will differ):
```json
{
    "DBProxy": {
        "DBProxyName": "devops-lab-proxy",
        "Status": "creating",
        "EngineFamily": "POSTGRESQL",
        "Endpoint": "devops-lab-proxy.proxy-xxxx.us-east-1.rds.amazonaws.com",
        ...
    }
}
```

Wait for the proxy to become "available" (3-5 minutes):

```bash
aws rds describe-db-proxies \
  --db-proxy-name devops-lab-proxy \
  --query 'DBProxies[0].Status' \
  --output text \
  --region us-east-1
```

---

## Step 4 - Register the Aurora Cluster as a Target

**In your terminal:**

```bash
aws rds register-db-proxy-targets \
  --db-proxy-name devops-lab-proxy \
  --db-cluster-identifiers devops-lab-cluster \
  --region us-east-1
```

`--db-cluster-identifiers` - register the Aurora cluster (not individual instances).

Wait for the target to become "AVAILABLE":

```bash
aws rds describe-db-proxy-targets \
  --db-proxy-name devops-lab-proxy \
  --query 'Targets[*].{Target:RdsResourceId,Type:Type,Status:TargetHealth.State}' \
  --output table \
  --region us-east-1
```

Expected output (yours will differ):
```
-----------------------------------------------
|        DescribeDBProxyTargets               |
+------------------+------+-------------------+
| Status           | Target                   |
+------------------+--------------------------+
| AVAILABLE        | devops-lab-cluster       |
+------------------+--------------------------+
```

---

## Step 5 - Get the Proxy Endpoint and Connect

**In your terminal:**

```bash
aws rds describe-db-proxies \
  --db-proxy-name devops-lab-proxy \
  --query 'DBProxies[0].Endpoint' \
  --output text \
  --region us-east-1
```

Expected output (yours will differ):
```
devops-lab-proxy.proxy-xxxx.us-east-1.rds.amazonaws.com
```

Connect through the proxy:

```bash
psql -h devops-lab-proxy.proxy-xxxx.us-east-1.rds.amazonaws.com \
     -U postgres \
     -d postgres
```

**In psql:**

```sql
SELECT
    inet_server_addr() AS server_ip,
    pg_is_in_recovery() AS is_replica,
    current_setting('server_version') AS pg_version;
```

Expected output (yours will differ):
```
 server_ip  | is_replica | pg_version
------------+------------+-----------
 10.0.1.23  | f          | 16.6
(1 row)
```

You are connected through the proxy to the Aurora writer. The proxy transparently routes your connection.

Exit psql:

```sql
\q
```

---

## Step 6 - Test Failover Behavior with Proxy

RDS Proxy handles failover faster than connecting directly because it maintains a hot connection to the database and detects failover within seconds.

**In Terminal 1:**

Set up a connection monitor through the proxy:

```bash
PROXY_ENDPOINT="devops-lab-proxy.proxy-xxxx.us-east-1.rds.amazonaws.com"

while true; do
  RESULT=$(psql -h "$PROXY_ENDPOINT" -U postgres -d postgres \
    -t -c "SELECT inet_server_addr()::text;" \
    --connect-timeout=3 2>&1)
  if echo "$RESULT" | grep -qE '^[0-9]+\.[0-9]+'; then
    echo "$(date -u +%H:%M:%S) | OK   | $(echo $RESULT | tr -d ' ')"
  else
    echo "$(date -u +%H:%M:%S) | FAIL | Connection error"
  fi
  sleep 1
done
```

**In Terminal 2:**

Trigger failover:

```bash
aws rds failover-db-cluster \
  --db-cluster-identifier devops-lab-cluster \
  --region us-east-1
```

Watch Terminal 1. With the proxy, you should see fewer FAIL lines compared to connecting directly. RDS Proxy typically reduces perceived downtime to 5-15 seconds (vs 20-35 seconds direct).

---

## Step 7 - Check Proxy Connection Statistics

**In your terminal:**

```bash
aws rds describe-db-proxy-targets \
  --db-proxy-name devops-lab-proxy \
  --query 'Targets[*].{Target:RdsResourceId,Status:TargetHealth.State,Description:TargetHealth.Description}' \
  --output table \
  --region us-east-1
```

This shows the health of the proxy's connections to each target.

---

## Key Takeaways

1. RDS Proxy pools database connections - 500 app connections become 20 database connections
2. Proxy reduces failover downtime by detecting the new writer faster than DNS TTL
3. Proxy requires Secrets Manager for credentials and an IAM role for access
4. The proxy endpoint replaces the cluster endpoint in your application connection string
5. Proxy is most valuable for Lambda functions and microservices with many short-lived connections
6. Proxy adds ~1ms of latency per query - negligible for most workloads

---

## Clean Up

```bash
aws rds deregister-db-proxy-targets \
  --db-proxy-name devops-lab-proxy \
  --db-cluster-identifiers devops-lab-cluster \
  --region us-east-1

aws rds delete-db-proxy \
  --db-proxy-name devops-lab-proxy \
  --region us-east-1
```

Wait for the proxy to be deleted, then clean up IAM and Secrets Manager:

```bash
aws iam delete-role-policy \
  --role-name devops-lab-proxy-role \
  --policy-name secrets-access

aws iam delete-role \
  --role-name devops-lab-proxy-role

aws secretsmanager delete-secret \
  --secret-id devops-lab-proxy-credentials \
  --force-delete-without-recovery \
  --region us-east-1
```

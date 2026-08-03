# Use 02 - IAM Policy Exercise

**Time:** 25 minutes
**Prerequisite:** Build 03 (IAM Database Authentication)

---

## Scenario

[COMPANY] has three application teams, each with different database access needs:

1. **Orders Service** - runs on EC2, needs read/write to `orders_db`
2. **Analytics Pipeline** - runs on Lambda, needs read-only to `analytics_db`
3. **Admin Dashboard** - runs on ECS, needs read/write to multiple databases

Your job is to write IAM policies for each team following the principle of least privilege.

---

## Setup

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

export DB_RESOURCE_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].DbClusterResourceId' \
  --output text \
  --region $AWS_REGION)

echo "Account: $AWS_ACCOUNT_ID"
echo "DB Resource ID: $DB_RESOURCE_ID"
```

Connect as master user and create the database users:

```bash
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region $AWS_REGION)

psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

```sql
CREATE ROLE orders_service WITH LOGIN;
GRANT rds_iam TO orders_service;

CREATE ROLE analytics_reader WITH LOGIN;
GRANT rds_iam TO analytics_reader;

CREATE ROLE admin_dashboard WITH LOGIN;
GRANT rds_iam TO admin_dashboard;
```

Exit:

```sql
\q
```

---

## Task 1 - Write the Orders Service Policy

The Orders Service needs to connect as `orders_service` to the Aurora cluster.

Write an IAM policy that:
- Allows ONLY `rds-db:connect`
- Scopes to ONLY the `orders_service` database user
- Scopes to ONLY your specific cluster

Write your policy in `/tmp/orders-service-policy.json`.

<details>
<summary>Solution</summary>

```bash
cat > /tmp/orders-service-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_RESOURCE_ID}/orders_service"
    }
  ]
}
EOF
```

Key points:
- The resource ARN is scoped to one specific database user on one specific cluster
- `rds-db:connect` is the only action - not `rds:*`
- No wildcard (`*`) anywhere

</details>

---

## Task 2 - Write the Analytics Pipeline Policy

The Analytics Pipeline needs to connect as `analytics_reader` from a Lambda function.

Write an IAM policy. This policy should be identical in structure to Task 1 but with the different username.

Write your policy in `/tmp/analytics-reader-policy.json`.

<details>
<summary>Solution</summary>

```bash
cat > /tmp/analytics-reader-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_RESOURCE_ID}/analytics_reader"
    }
  ]
}
EOF
```

Note: The IAM policy controls who can generate a token. The PostgreSQL grants control what the role can do once connected. Separation of concerns.

</details>

---

## Task 3 - Write the Admin Dashboard Policy

The Admin Dashboard needs to connect as `admin_dashboard`. The team also needs to:
- Describe the cluster (to get the endpoint at startup)
- Generate auth tokens

Write a policy that allows both `rds-db:connect` AND the minimum RDS describe permissions.

Write your policy in `/tmp/admin-dashboard-policy.json`.

<details>
<summary>Solution</summary>

```bash
cat > /tmp/admin-dashboard-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowDatabaseConnect",
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:${AWS_REGION}:${AWS_ACCOUNT_ID}:dbuser:${DB_RESOURCE_ID}/admin_dashboard"
    },
    {
      "Sid": "AllowDescribeCluster",
      "Effect": "Allow",
      "Action": [
        "rds:DescribeDBClusters",
        "rds:DescribeDBInstances"
      ],
      "Resource": "arn:aws:rds:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster:${CLUSTER_ID}"
    }
  ]
}
EOF
```

Key points:
- Two separate statements with different actions and resources
- `Sid` (Statement ID) labels each statement for readability
- `DescribeDBClusters` lets the app find the cluster endpoint
- The RDS resource ARN uses a different format than the rds-db ARN

</details>

---

## Task 4 - Identify the Bad Policies

Review these three policies and identify what is wrong with each one.

**Policy A:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "rds-db:connect",
      "Resource": "*"
    }
  ]
}
```

**Policy B:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds:*"],
      "Resource": "*"
    }
  ]
}
```

**Policy C:**

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["rds-db:connect"],
      "Resource": "arn:aws:rds-db:us-east-1:123456789012:dbuser:*/app_user"
    }
  ]
}
```

Write down what is wrong with each one.

<details>
<summary>Solution</summary>

**Policy A - Resource is `*`:**
This allows connecting to ANY Aurora/RDS database user on ANY cluster in the account. If there are 10 clusters with sensitive data, this identity can connect to all of them. Fix: scope the resource to the specific cluster resource ID and username.

**Policy B - Action is `rds:*`:**
This is not even the right action namespace for database connections. `rds:*` grants full control over the RDS service - the identity could delete clusters, modify settings, take snapshots, and more. The correct action for database connections is `rds-db:connect` (note the `rds-db` prefix, not `rds`). Fix: use `rds-db:connect` and scope the resource.

**Policy C - Wildcard in resource ID:**
The `*` in the resource ID position means this identity can connect to the `app_user` role on ANY cluster in the account. If a new cluster is created tomorrow, this identity automatically gets access. Fix: use the specific `DbClusterResourceId` instead of `*`.

</details>

---

## Task 5 - Create and Test One Policy

Pick one of your policies from Tasks 1-3 and actually create it:

```bash
aws iam create-policy \
  --policy-name OrdersServiceAuroraPolicy \
  --policy-document file:///tmp/orders-service-policy.json
```

Generate a token and test the connection:

```bash
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $CLUSTER_ENDPOINT \
  --port 5432 \
  --region $AWS_REGION \
  --username orders_service)

psql \
  "host=$CLUSTER_ENDPOINT \
   port=5432 \
   dbname=postgres \
   user=orders_service \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

<details>
<summary>Expected result</summary>

If your IAM user/role has the policy attached, the connection should succeed:

```
psql (16.6)
SSL connection (protocol: TLSv1.3, ...)
Type "help" for help.

postgres=>
```

If you get `PAM authentication failed`, check:
1. Is the policy attached to your IAM user/role?
2. Does the resource ARN match your cluster resource ID exactly?
3. Does the username in the ARN match the PostgreSQL role name exactly?

</details>

---

## Clean Up

```sql
-- In psql as master user
DROP ROLE orders_service;
DROP ROLE analytics_reader;
DROP ROLE admin_dashboard;
```

```bash
aws iam delete-policy \
  --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/OrdersServiceAuroraPolicy"
```

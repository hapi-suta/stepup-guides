# Use 04 - Secrets Rotation Exercise

**Time:** 25 minutes
**Prerequisite:** Build 04 (Secrets Manager Integration)

---

## Scenario

[COMPANY] stores the production database password in a plaintext config file on an EC2 instance. The security team found this during a review and flagged it as a critical risk.

Your tasks:
1. Move the credentials to Secrets Manager
2. Set up automatic rotation every 30 days
3. Test that rotation actually changes the password
4. Simulate what happens to an application when rotation occurs
5. Write a guide for the developer team

---

## Setup

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export AWS_REGION="us-east-1"
export SECRET_NAME="use04/lab/db-credentials"
```

Connect as master user and create an application user:

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

```sql
CREATE ROLE app_service WITH LOGIN PASSWORD 'InitialPass1!';
GRANT CONNECT ON DATABASE postgres TO app_service;
```

Exit:

```sql
\q
```

---

## Task 1 - Store the Credentials in Secrets Manager

Create the secret with the current credentials.

<details>
<summary>Solution</summary>

```bash
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Lab 04 - database credentials for app_service" \
  --secret-string "{
    \"username\": \"app_service\",
    \"password\": \"InitialPass1!\",
    \"host\": \"$CLUSTER_ENDPOINT\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

</details>

Verify the secret was created:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

<details>
<summary>Expected output</summary>

```json
{
    "username": "app_service",
    "password": "InitialPass1!",
    "host": "devops-lab-cluster...",
    "port": 5432,
    "dbname": "postgres",
    "engine": "postgres"
}
```

</details>

---

## Task 2 - Connect Using the Secret

Extract the credentials from Secrets Manager and connect to the database.

<details>
<summary>Solution</summary>

```bash
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION)

DB_USER=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['username'])")
DB_PASS=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")
DB_HOST=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['host'])")

PGPASSWORD=$DB_PASS psql \
  "host=$DB_HOST port=5432 dbname=postgres user=$DB_USER sslmode=require" \
  -c "SELECT current_user, now();"
```

</details>

<details>
<summary>Expected output</summary>

```
 current_user |              now
--------------+-------------------------------
 app_service  | 2026-06-09 14:23:11.456789+00
```

</details>

---

## Task 3 - Enable Rotation via the Console

Enable automatic rotation with a 30-day schedule.

1. Open the AWS Console
2. Go to **Secrets Manager**
3. Click `use04/lab/db-credentials`
4. Scroll to **Rotation configuration**
5. Click **Edit rotation**
6. Enable automatic rotation: **On**
7. Rotation schedule: **30 days**
8. Rotation function: **Create a new Lambda function**
9. Function name: `SecretsManagerLabRotation`
10. Click **Save**

---

## Task 4 - Test Manual Rotation

Force an immediate rotation:

<details>
<summary>Solution</summary>

```bash
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION
```

Wait 30 seconds for the Lambda to complete, then check:

```bash
aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --query '{RotationEnabled:RotationEnabled,LastRotatedDate:LastRotatedDate}' \
  --region $AWS_REGION
```

</details>

Verify the password changed:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

The password should be different from `InitialPass1!`.

Try connecting with the OLD password:

```bash
PGPASSWORD="InitialPass1!" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=app_service sslmode=require" \
  -c "SELECT 1;" 2>&1
```

<details>
<summary>Expected result</summary>

```
psql: error: connection to server at "..." failed:
FATAL:  password authentication failed for user "app_service"
```

Good - the old password no longer works.

</details>

Try connecting with the NEW password from Secrets Manager:

<details>
<summary>Solution</summary>

```bash
NEW_PASS=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

PGPASSWORD=$NEW_PASS psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=app_service sslmode=require" \
  -c "SELECT current_user, 'connection works' AS status;"
```

Expected output:

```
 current_user |     status
--------------+----------------
 app_service  | connection works
```

</details>

---

## Task 5 - Simulate Application Behavior During Rotation

Simulate what happens when an application has cached credentials and rotation occurs.

```bash
# Step 1: Get credentials (simulates app startup)
APP_DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

echo "App started with cached credentials"

# Step 2: Rotate (simulates rotation while app is running)
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION

echo "Waiting for rotation to complete..."
sleep 30

# Step 3: Try cached credentials (should fail)
echo "Attempting connection with cached (stale) credentials..."
PGPASSWORD=$APP_DB_PASS psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=app_service sslmode=require" \
  -c "SELECT 'connected' AS status;" 2>&1 || true
```

Now implement the retry logic:

```bash
# Step 4: Fetch fresh credentials and retry
echo "Fetching fresh credentials from Secrets Manager..."
FRESH_PASS=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

PGPASSWORD=$FRESH_PASS psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=app_service sslmode=require" \
  -c "SELECT 'reconnected successfully' AS status;"
```

<details>
<summary>Expected output</summary>

```
         status
-------------------------
 reconnected successfully
```

</details>

---

## Task 6 - View Rotation History

Check the secret versions:

```bash
aws secretsmanager list-secret-version-ids \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION \
  --query 'Versions[*].{VersionId:VersionId,Stages:VersionStages}' \
  --output table
```

<details>
<summary>Expected output</summary>

```
+-------------------------+------------------+
|       VersionId         |     Stages       |
+-------------------------+------------------+
| b2c3d4e5-...            | ['AWSCURRENT']   |
| a1b2c3d4-...            | ['AWSPREVIOUS']  |
+-------------------------+------------------+
```

`AWSCURRENT` is the active version. `AWSPREVIOUS` is the previous one.

</details>

---

## Task 7 - Write the Developer Guide

Write a short guide covering:

1. How to retrieve the secret in Python or Node.js
2. When to fetch credentials (at startup, not per-query)
3. How to handle failed connections after rotation
4. Why credentials should never be cached longer than 30 minutes
5. A code example showing retry logic

<details>
<summary>Sample guide</summary>

```
Secrets Manager Integration Guide - app_service
================================================

Secret name: use04/lab/db-credentials
Rotation: Every 30 days (automatic)

How to fetch credentials (Python):
  import boto3, json
  client = boto3.client("secretsmanager", region_name="us-east-1")
  secret = json.loads(
    client.get_secret_value(SecretId="use04/lab/db-credentials")["SecretString"]
  )
  password = secret["password"]

When to fetch:
  - At application startup
  - When a connection fails with "authentication failed"
  - Never cache for more than 30 minutes

Retry logic:
  1. Try to connect with cached credentials
  2. If "password authentication failed":
     a. Fetch fresh credentials from Secrets Manager
     b. Retry the connection once
     c. If still failing, alert the on-call team

Never do:
  - Hardcode the password in code or config files
  - Store the password in environment variables that get committed
  - Cache the password indefinitely
```

</details>

---

## Clean Up

```bash
aws secretsmanager delete-secret \
  --secret-id $SECRET_NAME \
  --force-delete-without-recovery \
  --region $AWS_REGION
```

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require" \
  -c "DROP ROLE app_service;"
```

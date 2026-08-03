# Use 05 - Secrets Rotation

**Time:** 25 minutes
**Prerequisite:** Build 05 (Secrets Manager)

---

## Scenario

[COMPANY] stores the production database password in a plaintext config file on an EC2 instance. The security team found this during a review and flagged it as a critical risk.

Your tasks:
1. Move the credentials to Secrets Manager
2. Set up automatic rotation every 30 days
3. Test that rotation actually changes the password
4. Simulate what happens to an application when rotation occurs
5. Write a guide for the developer team on how to fetch the secret in their application

---

## Setup

Make sure you have an RDS instance running. Set these variables:

```bash
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export RDS_INSTANCE_ID="my-postgres-db"
export AWS_REGION="us-east-1"
export SECRET_NAME="use05/lab/db-credentials"
```

Connect as master user and create an application user:

```bash
psql "host=$RDS_HOST port=5432 dbname=postgres user=postgres"
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

Create the secret:

```bash
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "Lab 05 - database credentials for app_service" \
  --secret-string "{
    \"username\": \"app_service\",
    \"password\": \"InitialPass1!\",
    \"host\": \"$RDS_HOST\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

Retrieve and verify it:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

Confirm the username is `app_service` and the password is `InitialPass1!`.

---

## Task 2 - Connect Using the Secret (Before Rotation)

Extract credentials and connect:

```bash
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION)

DB_USER=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['username'])")
DB_PASS=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")
DB_HOST=$(echo $SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['host'])")
```

```bash
PGPASSWORD=$DB_PASS psql \
  "host=$DB_HOST port=5432 dbname=postgres user=$DB_USER"
```

Run a test query:

```sql
SELECT current_user, now();
\q
```

Expected output:

```
 current_user │              now
──────────────┼────────────────────────────────────
 app_service  │ 2024-01-15 14:23:11.456789+00
```

---

## Task 3 - Enable Rotation via the Console

The easiest way to enable rotation is through the Console because it creates the rotation Lambda for you.

1. Open the AWS Console
2. Go to **Secrets Manager**
3. Click `use05/lab/db-credentials`
4. Scroll down to **Rotation configuration**
5. Click **Edit rotation**
6. Enable automatic rotation: **On**
7. Rotation schedule: **30 days**
8. Rotation function: choose **Create a new Lambda function**
9. Function name: `SecretsManagerLabRotation`
10. Credentials to use for rotation: select your secret
11. Click **Save**

After saving, Secrets Manager creates the Lambda and a permissions policy automatically.

---

## Task 4 - Trigger Manual Rotation

Force an immediate rotation to test it:

```bash
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION
```

Wait about 30 seconds for the Lambda to complete rotation.

Check rotation status:

```bash
aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --query '{RotationEnabled:RotationEnabled,LastRotatedDate:LastRotatedDate}' \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
{
    "RotationEnabled": true,
    "LastRotatedDate": "2024-01-15T14:30:00+00:00"
}
```

---

## Task 5 - Verify the Password Changed

Retrieve the secret again:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

The password field should now be different from `InitialPass1!`. Secrets Manager generated a new complex password and updated it in both Secrets Manager and the database.

Try connecting with the OLD password (should fail):

```bash
PGPASSWORD="InitialPass1!" psql \
  "host=$RDS_HOST port=5432 dbname=postgres user=app_service"
```

Expected output:

```
psql: error: connection to server at "..." failed:
FATAL:  password authentication failed for user "app_service"
```

Good - the old password no longer works.

Try connecting by fetching from Secrets Manager (should succeed):

```bash
NEW_SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION)

NEW_PASS=$(echo $NEW_SECRET_JSON | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

PGPASSWORD=$NEW_PASS psql \
  "host=$RDS_HOST port=5432 dbname=postgres user=app_service" \
  -c "SELECT current_user, 'connection works' AS status;"
```

Expected output:

```
 current_user │     status
──────────────┼────────────────
 app_service  │ connection works
```

---

## Task 6 - Simulate an Application During Rotation

Real applications cache the database connection. When rotation happens, the cached credentials break.

Here is how to simulate this:

```bash
# Step 1: Get credentials (simulates app startup)
APP_DB_PASS=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

echo "App started with cached credentials"

# Step 2: Rotate (simulates rotation happening while app is running)
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION

sleep 30  # Wait for rotation to complete

# Step 3: Try to use the cached (now stale) credentials
echo "Attempting connection with cached credentials..."
PGPASSWORD=$APP_DB_PASS psql \
  "host=$RDS_HOST port=5432 dbname=postgres user=app_service" \
  -c "SELECT 'connected' AS status;" 2>&1 || true
```

If the connection fails, the application would see an error and should:
1. Catch the authentication error
2. Fetch fresh credentials from Secrets Manager
3. Retry the connection

Add this retry logic:

```bash
# Step 4: Fetch fresh credentials and retry
echo "Fetching fresh credentials from Secrets Manager..."
FRESH_PASS=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

PGPASSWORD=$FRESH_PASS psql \
  "host=$RDS_HOST port=5432 dbname=postgres user=app_service" \
  -c "SELECT 'reconnected successfully' AS status;"
```

Expected output:

```
         status
─────────────────────────
 reconnected successfully
```

---

## Task 7 - View Rotation History

Check which versions of the secret exist:

```bash
aws secretsmanager list-secret-version-ids \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION \
  --query 'Versions[*].{VersionId:VersionId,Stages:VersionStages,Created:CreatedDate}' \
  --output table
```

Expected output (yours will differ):

```
+---------------------------+-----------------------+---------------------------------------------+
| Created                   | Stages                | VersionId                                   |
+---------------------------+-----------------------+---------------------------------------------+
| 2024-01-15T14:30:00+00:00 | ['AWSCURRENT']        | b2c3d4e5-f6a7-8901-bcde-f12345678901        |
| 2024-01-15T14:23:00+00:00 | ['AWSPREVIOUS']       | a1b2c3d4-e5f6-7890-abcd-ef1234567890        |
+---------------------------+-----------------------+---------------------------------------------+
```

`AWSCURRENT` is the active version. `AWSPREVIOUS` is the one just before (kept briefly for rollback).

---

## Task 8 - Write the Developer Guide

Write a short guide for the backend team covering:

1. How to retrieve the secret from Secrets Manager in their language of choice
2. When to fetch credentials (at startup, not in every function call)
3. How to handle a failed connection after rotation (catch auth errors, re-fetch, retry once)
4. Why they should NEVER cache the connection string for more than 30 minutes
5. How to test that rotation will not break their application

Include a code example using Python or Node.js from Build 05.

---

## Clean Up

```bash
aws secretsmanager delete-secret \
  --secret-id $SECRET_NAME \
  --force-delete-without-recovery \
  --region $AWS_REGION
```

```bash
psql "host=$RDS_HOST port=5432 dbname=postgres user=postgres" \
  -c "DROP ROLE app_service;"
```

Delete the rotation Lambda if you no longer need it:

In the Console, go to Lambda > find `SecretsManagerLabRotation` > Delete.

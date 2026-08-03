# Build 05 - Secrets Manager

**Time:** 35 minutes
**Goal:** Store RDS credentials in Secrets Manager, enable automatic rotation, retrieve secrets from the CLI, and understand how applications use secrets at startup.

---

## Before You Start

Read `concepts/security.md` section T2.5 first.

You need:
- A running RDS PostgreSQL instance
- AWS CLI configured
- psql installed

Set these variables:

```bash
export RDS_HOST="your-instance.abc123.us-east-1.rds.amazonaws.com"
export RDS_PORT="5432"
export RDS_INSTANCE_ID="my-postgres-db"
export RDS_DB="postgres"
export SECRET_NAME="prod/myapp/db-credentials"
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

---

## Step 1 - Create a Secret in Secrets Manager

Secrets Manager stores credentials as JSON. The standard format for RDS credentials is:

```json
{
  "username": "app_user",
  "password": "StrongPass1!",
  "host": "your-rds-endpoint.rds.amazonaws.com",
  "port": 5432,
  "dbname": "postgres"
}
```

### Using the AWS Console

1. Open the AWS Console in your browser
2. Search for **Secrets Manager** in the top search bar
3. Click **Store a new secret**
4. Secret type: **Credentials for Amazon RDS database**
5. Username: enter your database username (e.g., `app_user`)
6. Password: enter the current password
7. Database: select your RDS instance from the dropdown
8. Click **Next**
9. Secret name: `prod/myapp/db-credentials`
10. Description: `RDS credentials for the production application`
11. Click **Next**
12. Rotation - leave off for now (we will enable it in Step 3)
13. Click **Next**
14. Review and click **Store**

### Using the AWS CLI

First, make sure the `app_user` role exists in your database. Connect as master user and check:

```bash
psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=postgres" \
  -c "\du app_user"
```

If the role does not exist, create it:

```bash
psql \
  "host=$RDS_HOST port=$RDS_PORT dbname=$RDS_DB user=postgres" \
  -c "CREATE ROLE app_user WITH LOGIN PASSWORD 'StrongPass1!';"
```

Now store the credentials in Secrets Manager:

```bash
aws secretsmanager create-secret \
  --name "$SECRET_NAME" \
  --description "RDS credentials for the production application" \
  --secret-string "{
    \"username\": \"app_user\",
    \"password\": \"StrongPass1!\",
    \"host\": \"$RDS_HOST\",
    \"port\": 5432,
    \"dbname\": \"$RDS_DB\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

`--name` is the secret name. Using slashes (`/`) creates a hierarchy for organization.
`--secret-string` is the secret value as a JSON string.
`--description` helps your team understand what this secret is for.

Expected output (yours will differ):

```json
{
    "ARN": "arn:aws:secretsmanager:us-east-1:123456789012:secret:prod/myapp/db-credentials-abc123",
    "Name": "prod/myapp/db-credentials",
    "VersionId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
}
```

Save the ARN - you will need it later:

```bash
export SECRET_ARN=$(aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --query 'ARN' \
  --output text \
  --region $AWS_REGION)

echo "Secret ARN: $SECRET_ARN"
```

---

## Step 2 - Retrieve the Secret

Retrieve the full secret value:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION
```

`--secret-id` can be the name or the ARN.

Expected output (yours will differ):

```json
{
    "ARN": "arn:aws:secretsmanager:...",
    "Name": "prod/myapp/db-credentials",
    "VersionId": "a1b2c3d4-...",
    "SecretString": "{\"username\":\"app_user\",\"password\":\"StrongPass1!\",\"host\":\"...\"}",
    "CreatedDate": "2024-01-15T14:23:00+00:00"
}
```

Extract just the secret string and pretty-print it:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

`--query 'SecretString'` extracts only the secret value.
`python3 -m json.tool` formats the JSON nicely.

Expected output (yours will differ):

```json
{
    "username": "app_user",
    "password": "StrongPass1!",
    "host": "your-instance.abc123.us-east-1.rds.amazonaws.com",
    "port": 5432,
    "dbname": "postgres",
    "engine": "postgres"
}
```

---

## Step 3 - Connect to RDS Using the Secret

Extract the password from the secret and use it to connect:

```bash
export DB_PASSWORD=$(aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")
```

This command:
1. Gets the secret value
2. Extracts the `SecretString` field
3. Pipes it to Python, which parses the JSON and prints just the password

Verify it was captured (it will not print the actual value for security):

```bash
echo "Password captured: ${#DB_PASSWORD} characters"
```

Expected output (yours will differ):

```
Password captured: 12 characters
```

Now connect:

```bash
PGPASSWORD=$DB_PASSWORD psql \
  --host=$RDS_HOST \
  --port=$RDS_PORT \
  --username=app_user \
  --dbname=$RDS_DB
```

Expected output (yours will differ):

```
psql (16.6)
SSL connection (protocol: TLSv1.3, ...)
Type "help" for help.

postgres=>
```

Exit:

```sql
\q
```

---

## Step 4 - Enable Managed Rotation

Secrets Manager can rotate the password automatically using a Lambda function that AWS provides.

> **Important:** For managed rotation to work, the Lambda function must be able to reach your RDS instance. This means your Lambda must be in the same VPC as your RDS instance, or you must have a VPC endpoint for Secrets Manager.

### Using the AWS Console

1. Go to **Secrets Manager** in the Console
2. Click your secret (`prod/myapp/db-credentials`)
3. Scroll down to **Rotation configuration**
4. Click **Edit rotation**
5. Check **Enable automatic rotation**
6. Rotation schedule: **30 days** (recommended for production)
7. Rotation function: **Create a new Lambda function**
8. Lambda function name: `SecretsManagerRDSPostgresRotation`
9. Under **Use separate credentials**, choose **Use the master secret** if you have a master secret stored too
10. Click **Save**

### Using the AWS CLI

First, check if there is a Secrets Manager VPC endpoint or if your Lambda can reach the database. For this lab, if your RDS instance is publicly accessible, rotation will work without a VPC configuration.

Get the Lambda rotation function ARN from AWS (AWS publishes rotation Lambda functions by region):

```bash
aws serverlessrepo list-applications \
  --query "Applications[?Name=='SecretsManagerRDSPostgreSQLRotationSingleUser'].ApplicationId" \
  --output text \
  --region $AWS_REGION
```

For simplicity in this lab, enable rotation via the Console (Step above) or use this CLI command after you have created the rotation Lambda:

```bash
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --rotation-lambda-arn "arn:aws:lambda:${AWS_REGION}:${AWS_ACCOUNT_ID}:function:SecretsManagerRDSPostgresRotation" \
  --rotation-rules AutomaticallyAfterDays=30 \
  --region $AWS_REGION
```

`--rotation-lambda-arn` is the Lambda function that performs the rotation.
`--rotation-rules AutomaticallyAfterDays=30` rotates the secret every 30 days.

Expected output (yours will differ):

```json
{
    "ARN": "arn:aws:secretsmanager:...",
    "Name": "prod/myapp/db-credentials",
    "VersionId": "b2c3d4e5-..."
}
```

---

## Step 5 - Trigger an Immediate Rotation

Force an immediate rotation to test that it works:

```bash
aws secretsmanager rotate-secret \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION
```

This triggers the Lambda function immediately.

Check rotation status:

```bash
aws secretsmanager describe-secret \
  --secret-id $SECRET_NAME \
  --query '{RotationEnabled:RotationEnabled,LastRotatedDate:LastRotatedDate,NextRotationDate:NextRotationDate}' \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
{
    "RotationEnabled": true,
    "LastRotatedDate": "2024-01-15T14:30:00+00:00",
    "NextRotationDate": "2024-02-14T14:30:00+00:00"
}
```

After rotation, retrieve the secret again to confirm the password changed:

```bash
aws secretsmanager get-secret-value \
  --secret-id $SECRET_NAME \
  --query 'SecretString' \
  --output text \
  --region $AWS_REGION | python3 -m json.tool
```

The password field will be different from `StrongPass1!` - Secrets Manager generated a new strong password and updated it in the database.

---

## Step 6 - Update a Secret Manually

If you need to update the password manually (for example, after an emergency reset):

```bash
aws secretsmanager update-secret \
  --secret-id $SECRET_NAME \
  --secret-string "{
    \"username\": \"app_user\",
    \"password\": \"NewStrongPass2!\",
    \"host\": \"$RDS_HOST\",
    \"port\": 5432,
    \"dbname\": \"$RDS_DB\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

`update-secret` updates the secret value.
Note: this only updates the secret in Secrets Manager. It does NOT change the actual database password. You would also need to run `ALTER ROLE app_user PASSWORD 'NewStrongPass2!';` in psql.

Managed rotation handles both steps automatically. Manual updates are only for emergency situations.

---

## Step 7 - IAM Policy for Secret Access

Applications need permission to retrieve secrets. Create a minimal IAM policy:

```bash
cat > /tmp/secrets-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "$SECRET_ARN"
    }
  ]
}
EOF
```

```bash
aws iam create-policy \
  --policy-name RDSSecretsReadPolicy \
  --policy-document file:///tmp/secrets-policy.json
```

`GetSecretValue` allows reading the secret.
`DescribeSecret` allows reading metadata (but not the value itself).
Note: the `Resource` is scoped to the specific secret ARN - not all secrets.

Attach this policy to the EC2 instance role that runs your application. Do not attach it to your personal IAM user unless you are testing.

---

## Step 8 - Application Pattern

This is the pattern to use in a real application. You do not need to run this in the lab.

**Python (boto3):**

```python
import boto3
import json
import psycopg2

def get_db_credentials(secret_name: str, region: str) -> dict:
    """Fetch database credentials from Secrets Manager."""
    client = boto3.client("secretsmanager", region_name=region)
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response["SecretString"])

def create_connection():
    """Create a database connection using credentials from Secrets Manager."""
    creds = get_db_credentials("prod/myapp/db-credentials", "us-east-1")

    return psycopg2.connect(
        host=creds["host"],
        port=creds["port"],
        dbname=creds["dbname"],
        user=creds["username"],
        password=creds["password"],
        sslmode="verify-full",
        sslrootcert="/etc/ssl/certs/rds-ca-bundle.pem"
    )
```

**Node.js:**

```javascript
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { Client } from "pg";

async function getDbCredentials(secretName) {
  const client = new SecretsManagerClient({ region: "us-east-1" });
  const response = await client.send(
    new GetSecretValueCommand({ SecretId: secretName })
  );
  return JSON.parse(response.SecretString);
}

async function createConnection() {
  const creds = await getDbCredentials("prod/myapp/db-credentials");
  const client = new Client({
    host: creds.host,
    port: creds.port,
    database: creds.dbname,
    user: creds.username,
    password: creds.password,
    ssl: { ca: readFileSync("/etc/ssl/certs/rds-ca-bundle.pem") }
  });
  await client.connect();
  return client;
}
```

The key principle: fetch credentials from Secrets Manager at startup. Do not hardcode them. Do not put them in environment variables that get committed to git.

---

## Step 9 - Secret Versioning

Secrets Manager keeps multiple versions of a secret. This matters during rotation because:

1. The new password is written as a new version
2. The old password remains accessible for a brief period
3. After confirming the rotation succeeded, the old version is deprecated

View the versions:

```bash
aws secretsmanager list-secret-version-ids \
  --secret-id $SECRET_NAME \
  --region $AWS_REGION
```

Expected output (yours will differ):

```json
{
    "Versions": [
        {
            "VersionId": "a1b2c3d4-...",
            "VersionStages": ["AWSCURRENT"]
        },
        {
            "VersionId": "b2c3d4e5-...",
            "VersionStages": ["AWSPREVIOUS"]
        }
    ]
}
```

`AWSCURRENT` is the active version your applications should use.
`AWSPREVIOUS` is the last version - kept briefly in case of rollback.

---

## What You Built

- Created an RDS credential secret in Secrets Manager
- Retrieved the secret using the AWS CLI
- Connected to RDS using credentials fetched from Secrets Manager (not hardcoded)
- Enabled automatic rotation
- Triggered an immediate rotation and verified the password changed
- Learned the application pattern for fetching secrets at startup

---

## Clean Up

```bash
aws secretsmanager delete-secret \
  --secret-id $SECRET_NAME \
  --force-delete-without-recovery \
  --region $AWS_REGION
```

`--force-delete-without-recovery` deletes immediately instead of the default 7-30 day recovery window. Use this only for test secrets.

---

## Key Rules to Remember

1. Never hardcode passwords in application code or config files
2. Never put database passwords in environment variables that get committed to git
3. Scope IAM policies to specific secret ARNs - not all secrets
4. Use the alternating users rotation strategy for zero-downtime rotation
5. Fetch credentials from Secrets Manager at startup, not at package level
6. The `AWSCURRENT` version label is always the active secret

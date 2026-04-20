# SURVIVE 08 - IAM Auth Token Expired

## Symptom

An application using IAM database authentication cannot connect to RDS. The error message says "PAM authentication failed". The application was working earlier today but stopped connecting.

---

## Diagnosis

### Step 1 - Try connecting with the stored token

```bash
ENDPOINT=$(cat /path/to/endpoint.txt)
```

```bash
OLD_TOKEN=$(cat /path/to/expired_token.txt)
```

Replace `/path/to/` with the actual scenario directory path.

```bash
psql "host=${ENDPOINT} port=5432 dbname=postgres user=app_service password=${OLD_TOKEN} sslmode=require" 2>&1
```

Expected output (if token is expired):

```
psql: error: connection to server failed: FATAL: PAM authentication failed for user "app_service"
```

### Step 2 - Check when the token was generated

```bash
cat /path/to/token_generated_at.txt
```

IAM auth tokens are valid for exactly 15 minutes. If the token was generated more than 15 minutes ago, it is expired.

### Step 3 - Verify IAM auth is enabled on the instance

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].IAMDatabaseAuthenticationEnabled" \
    --output text
```

Expected output:

```
True
```

If this is `False`, IAM auth is not enabled and that is a separate problem.

### Step 4 - Verify the database user has rds_iam role

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
SELECT r.rolname AS user_name, m.rolname AS member_of
FROM pg_auth_members am
JOIN pg_roles r ON am.member = r.oid
JOIN pg_roles m ON am.roleid = m.oid
WHERE r.rolname = 'app_service';
```

Expected output:

```
 user_name   | member_of
-------------+-----------
 app_service | rds_iam
(1 row)
```

If `rds_iam` is not in the output, the user is not configured for IAM auth.

Exit psql:

```sql
\q
```

### Step 5 - Verify the IAM policy exists

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

```bash
DBI_RESOURCE_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DbiResourceId" --output text)
```

List IAM policies that mention rds-db:

```bash
aws iam list-policies \
    --scope Local \
    --query "Policies[?contains(PolicyName, 'rds')].{Name:PolicyName,Arn:Arn}" \
    --output table
```

Check the policy document to verify the resource ARN includes the correct DBI resource ID and username:

```bash
POLICY_ARN=$(aws iam list-policies --scope Local --query "Policies[?contains(PolicyName, 'rds')].Arn | [0]" --output text)
```

```bash
aws iam get-policy-version \
    --policy-arn "${POLICY_ARN}" \
    --version-id v1 \
    --query "PolicyVersion.Document"
```

The resource ARN should end with `dbuser:${DBI_RESOURCE_ID}/app_service`.

---

## Fix

### Step 6 - Generate a fresh token

```bash
FRESH_TOKEN=$(aws rds generate-db-auth-token \
    --hostname "${RDS_ENDPOINT}" \
    --port 5432 \
    --username app_service \
    --region us-east-1)
```

This generates a new token that is valid for 15 minutes.

### Step 7 - Connect with the fresh token

Download the CA bundle if needed:

```bash
curl -so /tmp/rds-combined-ca-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=app_service password=${FRESH_TOKEN} sslmode=verify-full sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

Expected output:

```
psql (15.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Verify the connection:

```sql
SELECT current_user, now();
```

Exit psql:

```sql
\q
```

### Step 8 - Fix the application configuration

The root cause is that the application is not refreshing its IAM token. The fix depends on the application:

**Pattern 1 - Generate token per connection:**
Generate a fresh token each time a new database connection is created. This is the simplest and most reliable approach.

**Pattern 2 - Token cache with refresh:**
Cache the token and refresh it every 10 minutes (5-minute buffer before the 15-minute expiry). Use this when connection pooling is in play.

**Pattern 3 - AWS SDK integration:**
Use the AWS SDK's built-in RDS auth token generation in your application code. Most SDKs handle caching and refresh automatically.

---

## Verification

Generate a token and connect:

```bash
TOKEN=$(aws rds generate-db-auth-token --hostname "${RDS_ENDPOINT}" --port 5432 --username app_service --region us-east-1)
```

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=app_service password=${TOKEN} sslmode=require"
```

Once connected, run a test query:

```sql
SELECT 'iam_auth_working' AS status;
```

Expected output:

```
      status
------------------
 iam_auth_working
(1 row)
```

Exit psql:

```sql
\q
```

---

## Discussion Questions

1. Why is the IAM auth token TTL only 15 minutes?
2. What happens to existing connections when a token expires?
3. How would you implement token refresh in a connection pool?
4. What are the advantages of IAM auth over traditional passwords?

# USE 06 - IAM Authentication

## Objective

Enable IAM database authentication, create the required IAM policy, generate an auth token, connect with the token, and verify that token expiration works as expected.

---

## Exercise

You will:
1. Enable IAM auth on your RDS instance
2. Create a database user with the rds_iam role
3. Create an IAM policy scoped to that user
4. Generate a token and connect
5. Understand token TTL and rotation

---

## Step-by-Step

### 1. Enable IAM authentication

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].IAMDatabaseAuthenticationEnabled" \
    --output text
```

If the output is `False`, enable it:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --enable-iam-database-authentication \
    --apply-immediately
```

Wait for the modification:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

Verify:

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

### 2. Create a database user for IAM auth

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
CREATE USER app_readonly WITH LOGIN;
```

```sql
GRANT rds_iam TO app_readonly;
```

The `rds_iam` role tells RDS to authenticate this user via IAM tokens instead of passwords.

Grant read-only access:

```sql
GRANT CONNECT ON DATABASE postgres TO app_readonly;
```

```sql
GRANT USAGE ON SCHEMA public TO app_readonly;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO app_readonly;
```

```sql
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO app_readonly;
```

The `ALTER DEFAULT PRIVILEGES` ensures that any tables created in the future will also be readable by app_readonly.

Verify the user:

```sql
SELECT usename, usesuper FROM pg_user WHERE usename = 'app_readonly';
```

Expected output:

```
   usename    | usesuper
--------------+----------
 app_readonly | f
(1 row)
```

Exit psql:

```sql
\q
```

### 3. Get resource identifiers for the IAM policy

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

```bash
DBI_RESOURCE_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DbiResourceId" --output text)
```

```bash
AWS_REGION=$(aws configure get region)
```

Print them to verify:

```bash
echo "Account: ${ACCOUNT_ID}"
```

```bash
echo "DBI Resource ID: ${DBI_RESOURCE_ID}"
```

```bash
echo "Region: ${AWS_REGION}"
```

### 4. Create the IAM policy

```bash
aws iam create-policy \
    --policy-name suta-rds-iam-app-readonly \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": \"rds-db:connect\",
            \"Resource\": \"arn:aws:rds-db:${AWS_REGION}:${ACCOUNT_ID}:dbuser:${DBI_RESOURCE_ID}/app_readonly\"
        }]
    }"
```

The resource ARN format is `arn:aws:rds-db:REGION:ACCOUNT:dbuser:DBI_RESOURCE_ID/DB_USERNAME`. This policy allows generating auth tokens for the `app_readonly` user only on this specific RDS instance.

Expected output (yours will differ):

```json
{
    "Policy": {
        "PolicyName": "suta-rds-iam-app-readonly",
        "PolicyId": "ANPAEXAMPLE123",
        "Arn": "arn:aws:iam::123456789012:policy/suta-rds-iam-app-readonly",
        ...
    }
}
```

Save the policy ARN:

```bash
POLICY_ARN="arn:aws:iam::${ACCOUNT_ID}:policy/suta-rds-iam-app-readonly"
```

### 5. Attach the policy

Attach to your current IAM user:

```bash
IAM_USER=$(aws sts get-caller-identity --query "Arn" --output text | rev | cut -d'/' -f1 | rev)
```

This extracts your IAM username from the caller identity ARN.

```bash
aws iam attach-user-policy \
    --user-name "${IAM_USER}" \
    --policy-arn "${POLICY_ARN}"
```

### 6. Generate an auth token

```bash
IAM_TOKEN=$(aws rds generate-db-auth-token \
    --hostname "${RDS_ENDPOINT}" \
    --port 5432 \
    --username app_readonly \
    --region "${AWS_REGION}")
```

Check the token length (it should be several hundred characters):

```bash
echo "${IAM_TOKEN}" | wc -c
```

Expected output (yours will differ):

```
     856
```

The token is a signed URL that expires in 15 minutes. It contains your AWS credentials, the target host, and a timestamp.

### 7. Connect with the IAM token

Download the RDS CA certificate if you have not already:

```bash
curl -so /tmp/rds-combined-ca-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

Connect:

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=app_readonly password=${IAM_TOKEN} sslmode=verify-full sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

The IAM token is passed as the password. SSL is required - IAM auth will not work without it.

Expected output (yours will differ):

```
psql (15.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Verify your identity:

```sql
SELECT current_user, session_user;
```

Expected output:

```
 current_user | session_user
--------------+--------------
 app_readonly | app_readonly
(1 row)
```

Verify you can read:

```sql
SELECT count(*) FROM recovery_test;
```

Verify you cannot write:

```sql
CREATE TABLE iam_test (id int);
```

Expected output:

```
ERROR:  permission denied for schema public
```

Exit psql:

```sql
\q
```

### 8. Understand token expiration

The token is valid for 15 minutes from generation. After 15 minutes, new connections using that token will fail, but existing connections remain open.

Wait 15+ minutes, then try connecting with the same token:

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=app_readonly password=${IAM_TOKEN} sslmode=verify-full sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

Expected output (after token expires):

```
psql: error: connection to server failed: FATAL: PAM authentication failed for user "app_readonly"
```

Generate a fresh token and connect again:

```bash
IAM_TOKEN=$(aws rds generate-db-auth-token --hostname "${RDS_ENDPOINT}" --port 5432 --username app_readonly --region "${AWS_REGION}")
```

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=app_readonly password=${IAM_TOKEN} sslmode=verify-full sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

This should connect successfully with the fresh token.

Exit psql:

```sql
\q
```

### 9. Application pattern for token refresh

In production, your application should:
1. Generate a new token before each connection (or every 10 minutes)
2. Use the token as the password in the connection string
3. Cache the token for up to 10 minutes (leaving 5 minutes of buffer)
4. Never store the token on disk

The advantage over passwords: no secrets to manage, rotate, or store. IAM policies control access. CloudTrail logs every token generation.

---

## Clean Up

```bash
aws iam detach-user-policy \
    --user-name "${IAM_USER}" \
    --policy-arn "${POLICY_ARN}"
```

```bash
aws iam delete-policy \
    --policy-arn "${POLICY_ARN}"
```

Remove the database user:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

```sql
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM app_readonly;
```

```sql
REVOKE USAGE ON SCHEMA public FROM app_readonly;
```

```sql
REVOKE CONNECT ON DATABASE postgres FROM app_readonly;
```

```sql
DROP USER app_readonly;
```

```sql
\q
```

---

## Key Takeaway

IAM authentication eliminates password management. Tokens expire in 15 minutes, so a leaked token has limited blast radius. Always pair IAM auth with SSL - it is required by RDS. For connection pooling, generate a new token at the pooler level, not per application instance.

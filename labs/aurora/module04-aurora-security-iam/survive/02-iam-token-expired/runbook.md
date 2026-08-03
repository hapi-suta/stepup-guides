# Runbook - Scenario 02: IAM Auth Token Expired

**Severity:** High - Application cannot connect to database
**Category:** IAM database authentication
**Estimated resolution time:** 10 minutes

---

## What Is Being Tested

Your ability to diagnose an IAM authentication failure caused by an expired token, generate a fresh token, and connect successfully.

---

## Why This Matters

IAM auth tokens expire after exactly 15 minutes. If an application caches the token at startup and never refreshes it, all new connections will fail after 15 minutes. Existing connections are not affected - only new ones. This means the application may work fine for a while and then suddenly start failing when the connection pool needs to create a new connection.

---

## Symptoms

- Application logs show: `FATAL: PAM authentication failed for user "iam_scenario_user"`
- Application was working fine before but suddenly cannot connect
- No database password was changed
- Existing connections still work, but new connections fail

---

## Diagnostic Steps

### Step 1 - Confirm the error

Try to connect using the stale token saved in `/tmp/module04-scenario02-stale-token.txt`:

```bash
PGPASSWORD=$(cat /tmp/module04-scenario02-stale-token.txt) psql \
  "host=$CLUSTER_ENDPOINT \
   port=5432 \
   dbname=postgres \
   user=iam_scenario_user \
   sslmode=require"
```

Expected output (if token is expired):

```
psql: error: connection to server at "..." failed:
FATAL:  PAM authentication failed for user "iam_scenario_user"
```

### Step 2 - Verify the PostgreSQL role exists with rds_iam

Connect as master user and check:

```bash
PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require"
```

```sql
SELECT r.rolname AS role, m.rolname AS member_of
FROM pg_auth_members am
JOIN pg_roles r ON r.oid = am.member
JOIN pg_roles m ON m.oid = am.roleid
WHERE r.rolname = 'iam_scenario_user';
```

Expected output if correct:

```
      role       | member_of
-----------------+-----------
 iam_scenario_user| rds_iam
```

If no rows are returned, the role does not have `rds_iam` and that is the problem.

### Step 3 - Check IAM auth is still enabled on the cluster

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].IAMDatabaseAuthenticationEnabled' \
  --output text \
  --region $AWS_REGION
```

Expected output:

```
True
```

If `False`, IAM auth was disabled. See Resolution B.

### Step 4 - Check your AWS credentials are still working

```bash
aws sts get-caller-identity
```

If this fails, your AWS credentials or IAM role are the problem. Fix them first.

---

## Resolution

### Resolution A - Token is expired (most common)

Generate a fresh token and connect:

```bash
export PGPASSWORD=$(aws rds generate-db-auth-token \
  --hostname $CLUSTER_ENDPOINT \
  --port 5432 \
  --region $AWS_REGION \
  --username iam_scenario_user)
```

Connect:

```bash
psql \
  "host=$CLUSTER_ENDPOINT \
   port=5432 \
   dbname=postgres \
   user=iam_scenario_user \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

If this works, the problem was simply an expired token.

**Fix in the application:** Generate a new token for each connection attempt. Do not cache tokens.

### Resolution B - IAM auth disabled on the cluster

```bash
aws rds modify-db-cluster \
  --db-cluster-identifier $CLUSTER_ID \
  --enable-iam-database-authentication \
  --apply-immediately \
  --region $AWS_REGION
```

### Resolution C - Role missing rds_iam

Connect as master user:

```sql
GRANT rds_iam TO iam_scenario_user;
```

### Resolution D - IAM policy missing or wrong resource ARN

Check the IAM policy attached to your IAM user or role:

```bash
aws iam list-attached-user-policies --user-name $MY_IAM_USER
```

Verify the policy's Resource ARN contains:
- Correct AWS account ID
- Correct DB cluster resource ID (starts with `cluster-`, not the cluster name)
- Correct username (`iam_scenario_user`)

---

## Prevention

1. Never cache IAM tokens - generate a fresh one for each connection
2. Set connection pool max lifetime shorter than 15 minutes (10 minutes is safe)
3. Add retry logic: on `PAM authentication failed`, generate a new token and retry once
4. Monitor failed connection attempts in CloudWatch - a spike indicates token expiration
5. Test token expiration in staging before deploying to production

---

## Interview Questions

1. How long is an IAM database auth token valid?
2. What happens to existing connections when a token expires?
3. Why does the IAM policy use the DB resource ID instead of the cluster name?
4. What is the correct application pattern for IAM token generation?

---

## Key Terminology

| Term | Definition |
|------|-----------|
| IAM auth token | A 15-minute signed URL used as a database password |
| rds_iam | PostgreSQL role attribute that enables IAM authentication |
| rds-db:connect | The IAM action required to generate database auth tokens |
| PAM authentication | The authentication method Aurora uses to validate IAM tokens |
| DbiResourceId | Stable internal ID for the database, used in IAM policy ARNs |

---

## Red Flags

- Application caches IAM token at startup and never refreshes
- Connection pool max lifetime set to more than 15 minutes with IAM auth
- No retry logic for `PAM authentication failed` errors
- IAM policy uses wildcard (`*`) for the resource ARN
- Application does not use SSL with IAM auth (IAM auth requires SSL)

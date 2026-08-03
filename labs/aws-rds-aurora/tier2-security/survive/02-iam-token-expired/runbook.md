# Runbook - Scenario 02: IAM Auth Token Expired

**Severity:** High - Application cannot connect to database
**Category:** IAM database authentication
**Estimated resolution time:** 10 minutes

---

## Symptoms

- Application logs show: `FATAL: PAM authentication failed for user "iam_scenario_user"`
- Application was working fine before but suddenly cannot connect
- No database password was changed

---

## Understanding IAM Tokens

IAM auth tokens expire exactly 15 minutes after generation. This is not a bug - it is a security feature. Applications must generate a fresh token before each connection. If your application:

- Generated the token at startup and never refreshed it
- Cached the token for longer than 15 minutes
- Lost its AWS credentials (IAM role detached, no network access to AWS)

...then the token is expired and connections will fail with `PAM authentication failed`.

---

## Diagnosis

### Step 1 - Confirm the error

Try to connect using the stale token saved in `/tmp/tier2-scenario02-stale-token.txt`:

```bash
PGPASSWORD=$(cat /tmp/tier2-scenario02-stale-token.txt) psql \
  "host=[YOUR-RDS-HOST] \
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
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=require"
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
      role       │ member_of
─────────────────┼───────────
 iam_scenario_user│ rds_iam
```

If no rows are returned, the role does not have `rds_iam` and that is the problem.

### Step 3 - Check IAM auth is still enabled on the instance

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].IAMDatabaseAuthenticationEnabled' \
  --output text \
  --region [YOUR-REGION]
```

Expected output:

```
true
```

If `false`, IAM auth was disabled. See Resolution Step B.

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
  --hostname [YOUR-RDS-HOST] \
  --port 5432 \
  --region [YOUR-REGION] \
  --username iam_scenario_user)
```

Connect:

```bash
psql \
  "host=[YOUR-RDS-HOST] \
   port=5432 \
   dbname=postgres \
   user=iam_scenario_user \
   sslmode=verify-full \
   sslrootcert=$HOME/rds-ca-bundle.pem"
```

If this works, the problem was simply an expired token.

**Fix in the application:** The application must generate a new token for each connection attempt. The token should not be cached. If using a connection pool, configure the pool to generate a fresh token each time it creates a new connection.

### Resolution B - IAM auth disabled on the instance

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --enable-iam-database-authentication \
  --apply-immediately \
  --region [YOUR-REGION]

aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [YOUR-REGION]
```

### Resolution C - Role missing rds_iam

Connect as master user:

```sql
GRANT rds_iam TO iam_scenario_user;
```

### Resolution D - IAM policy missing or wrong resource ARN

Check the IAM policy attached to your EC2 instance role or IAM user:

```bash
aws iam list-attached-user-policies --user-name [YOUR-IAM-USER]
```

Verify the policy's Resource ARN contains:
- Correct AWS account ID
- Correct DB resource ID (not instance ID)
- Correct username (`iam_scenario_user`)

---

## Application Fix Pattern

The correct pattern for IAM auth in an application:

```python
# WRONG - token cached, expires after 15 minutes
token = generate_token()  # at startup
connection = connect(password=token)  # cached - breaks after 15 min

# CORRECT - fresh token per connection
def connect_to_db():
    token = generate_token()  # fresh every time
    return connect(password=token)
```

---

## Prevention

1. Never cache IAM tokens - generate a fresh one for each connection
2. Set a connection pool max lifetime shorter than 15 minutes (10 minutes is safe)
3. Add retry logic: on `PAM authentication failed`, generate a new token and retry once
4. Monitor failed connection attempts in CloudWatch - spike indicates token expiration issue
5. Test token expiration in staging before deploying to production

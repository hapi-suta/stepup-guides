# Runbook - Scenario 03: Password Leaked

**Severity:** Critical - Active credential exposure
**Category:** Credential security / Incident response
**Estimated resolution time:** 20 minutes

---

## Situation

A database password has been leaked. It may have been:
- Committed to a public git repository
- Sent in plain text over Slack/email
- Found in application logs
- Included in a bug report or screenshot

The clock is ticking. Assume the password is already in attacker hands.

---

## Immediate Actions (Do These First)

The order matters. Change the password before doing anything else.

---

## Step 1 - Rotate the Password Immediately

### Option A - Rotate via psql (fastest)

Connect as master user:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=require"
```

Change the password:

```sql
ALTER ROLE payment_service WITH PASSWORD '[NEW-STRONG-PASSWORD]';
```

Generate a strong password if you need one:

```bash
openssl rand -base64 32
```

Example output (yours will be different):

```
kX9mP2vQ8nR5tY1wZ3aB6cD7eF0gH4jK=
```

Use this as the new password.

Verify the role still exists and can log in:

```sql
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'payment_service';
```

Exit:

```sql
\q
```

### Option B - Rotate via AWS CLI (if you need to rotate the master password)

```bash
aws rds modify-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --master-user-password "[NEW-STRONG-PASSWORD]" \
  --apply-immediately \
  --region [YOUR-REGION]
```

---

## Step 2 - Verify the Old Password No Longer Works

Try to connect with the old password (it should fail):

```bash
PGPASSWORD="Sup3rSecret99!" psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=payment_service sslmode=require"
```

Expected output:

```
psql: error: connection to server at "..." failed:
FATAL:  password authentication failed for user "payment_service"
```

If it still works, the ALTER ROLE command did not apply. Repeat Step 1.

---

## Step 3 - Verify Connections with the New Password Work

```bash
PGPASSWORD="[YOUR-NEW-PASSWORD]" psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=payment_service sslmode=require"
```

Expected output:

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

## Step 4 - Store the New Password in Secrets Manager

Do not put the new password in a config file. Put it in Secrets Manager.

Check if a secret already exists for this user:

```bash
aws secretsmanager describe-secret \
  --secret-id "prod/payment-service/db-credentials" \
  --region [YOUR-REGION] 2>&1 || echo "Secret not found"
```

If the secret does not exist, create it:

```bash
aws secretsmanager create-secret \
  --name "prod/payment-service/db-credentials" \
  --description "Emergency rotation - password was leaked on $(date -u +%Y-%m-%d)" \
  --secret-string "{
    \"username\": \"payment_service\",
    \"password\": \"[YOUR-NEW-PASSWORD]\",
    \"host\": \"[YOUR-RDS-HOST]\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region [YOUR-REGION]
```

If the secret already exists, update it:

```bash
aws secretsmanager update-secret \
  --secret-id "prod/payment-service/db-credentials" \
  --secret-string "{
    \"username\": \"payment_service\",
    \"password\": \"[YOUR-NEW-PASSWORD]\",
    \"host\": \"[YOUR-RDS-HOST]\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region [YOUR-REGION]
```

---

## Step 5 - Update the Application

The application that uses `payment_service` is currently configured with the old (leaked) password. Update it to fetch credentials from Secrets Manager.

For each application server:

1. Update the application code to fetch the password from Secrets Manager at startup
2. Remove any hardcoded passwords or .env files with the old password
3. Restart the application
4. Verify the application connects successfully

---

## Step 6 - Revoke Git Access to the Leaked Credential

If the password was leaked via git:

1. Immediately make the repository private (if it was public)
2. Remove the commit from git history using `git filter-branch` or `BFG Repo Cleaner`
3. Force-push the cleaned history
4. GitHub/GitLab will also need a support request to purge their caches

Note: Even after removal, assume the password is permanently compromised. It may have been copied by bots that scan public repos continuously.

---

## Step 7 - Incident Documentation

Write an incident report covering:

1. Time of discovery
2. How long the password was exposed (hours/days)
3. What the password gave access to
4. Timeline of remediation steps and when each was completed
5. Any evidence of unauthorized access (check PostgreSQL logs, CloudTrail, VPC flow logs)
6. Root cause - why was the password in a config file in the first place?
7. Process changes to prevent recurrence

---

## Checking for Unauthorized Access

Query PostgreSQL logs for connections by the compromised user during the exposure window:

```sql
-- If log_connections is enabled (check with: SHOW log_connections;)
-- Look in pg_log files on the RDS instance via CloudWatch

-- Alternatively, check current sessions
SELECT pid, usename, client_addr, backend_start, state
FROM pg_stat_activity
WHERE usename = 'payment_service'
ORDER BY backend_start;
```

Check CloudTrail for AWS API calls using credentials from the same time period.

---

## Prevention Going Forward

1. Never put credentials in code or config files that get committed to git
2. Use Secrets Manager for all database credentials
3. Set up pre-commit hooks that scan for secrets (`git-secrets`, `truffleHog`, `detect-secrets`)
4. Enable automatic rotation in Secrets Manager (30-day schedule)
5. Train developers: secrets in git = immediate rotation, no exceptions

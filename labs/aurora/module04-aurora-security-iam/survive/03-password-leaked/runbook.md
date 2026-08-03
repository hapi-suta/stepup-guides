# Runbook - Scenario 03: Password Leaked

**Severity:** Critical - Active credential exposure
**Category:** Credential security / Incident response
**Estimated resolution time:** 20 minutes

---

## What Is Being Tested

Your ability to execute an emergency password rotation after a credential leak, store the new password securely in Secrets Manager, and verify the old password no longer works.

---

## Why This Matters

When a database password is leaked, you are in a race against automated bots. Attackers continuously scan public GitHub repositories for database credentials. Within minutes of a commit containing a password, bots can find it and attempt to connect. The leaked password must be changed immediately - before any investigation or root cause analysis.

---

## Symptoms

- Security alert: database credentials found in a public repository
- Password found in application logs, Slack messages, or email
- Suspicious connection attempts from unknown IP addresses
- CloudTrail shows unusual Secrets Manager or RDS API activity

---

## Diagnostic Steps

### Step 1 - Confirm the leaked credentials work

View the leaked config file:

```bash
cat /tmp/module04-scenario03-leaked-config.env
```

Try connecting with the leaked credentials:

```bash
PGPASSWORD="Sup3rSecret99!" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=payment_service sslmode=require"
```

If the connection succeeds, the leaked password is still active. Proceed to Resolution immediately.

### Step 2 - Check for unauthorized connections

```sql
SELECT pid, usename, client_addr, backend_start, state
FROM pg_stat_activity
WHERE usename = 'payment_service'
ORDER BY backend_start;
```

Look for connections from unexpected IP addresses.

---

## Resolution

### Step 1 - Rotate the password immediately

Connect as master user:

```bash
PGPASSWORD="$MASTER_PASSWORD" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=$MASTER_USER sslmode=require"
```

Generate a strong password:

```bash
openssl rand -base64 32
```

Change the password:

```sql
ALTER ROLE payment_service WITH PASSWORD '[YOUR-NEW-STRONG-PASSWORD]';
```

Verify the role still exists and can log in:

```sql
SELECT rolname, rolcanlogin FROM pg_roles WHERE rolname = 'payment_service';
```

Exit:

```sql
\q
```

### Step 2 - Verify the old password no longer works

```bash
PGPASSWORD="Sup3rSecret99!" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=payment_service sslmode=require"
```

Expected output:

```
FATAL:  password authentication failed for user "payment_service"
```

If it still works, the ALTER ROLE command did not apply. Repeat Step 1.

### Step 3 - Verify the new password works

```bash
PGPASSWORD="[YOUR-NEW-PASSWORD]" psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=payment_service sslmode=require" \
  -c "SELECT current_user;"
```

### Step 4 - Store the new password in Secrets Manager

Check if a secret already exists:

```bash
aws secretsmanager describe-secret \
  --secret-id "prod/payment-service/db-credentials" \
  --region $AWS_REGION 2>&1 || echo "Secret not found"
```

If the secret does not exist, create it:

```bash
aws secretsmanager create-secret \
  --name "prod/payment-service/db-credentials" \
  --description "Emergency rotation - password was leaked on $(date -u +%Y-%m-%d)" \
  --secret-string "{
    \"username\": \"payment_service\",
    \"password\": \"[YOUR-NEW-PASSWORD]\",
    \"host\": \"$CLUSTER_ENDPOINT\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

If the secret already exists, update it:

```bash
aws secretsmanager update-secret \
  --secret-id "prod/payment-service/db-credentials" \
  --secret-string "{
    \"username\": \"payment_service\",
    \"password\": \"[YOUR-NEW-PASSWORD]\",
    \"host\": \"$CLUSTER_ENDPOINT\",
    \"port\": 5432,
    \"dbname\": \"postgres\",
    \"engine\": \"postgres\"
  }" \
  --region $AWS_REGION
```

---

## Prevention

1. Never put credentials in code or config files that get committed to git
2. Use Secrets Manager for all database credentials
3. Set up pre-commit hooks that scan for secrets (`git-secrets`, `truffleHog`, `detect-secrets`)
4. Enable automatic rotation in Secrets Manager (30-day schedule)
5. Train developers: secrets in git equals immediate rotation, no exceptions

---

## Interview Questions

1. What is the first thing you do when a database password is leaked?
2. Why should you change the password before investigating?
3. What is the difference between updating a secret in Secrets Manager and rotating it?
4. How would you check if an attacker already used the leaked credentials?

---

## Key Terminology

| Term | Definition |
|------|-----------|
| Credential rotation | Changing a password and updating all systems that use it |
| Secrets Manager | AWS service for storing, rotating, and managing credentials |
| AWSCURRENT | The active version label for the current secret value |
| Pre-commit hook | A git hook that runs before commits to catch secrets |
| Blast radius | The scope of damage an attacker can do with compromised credentials |

---

## Red Flags

- Password found in any git commit (even if the repo is private)
- Delay between discovering the leak and changing the password
- New password stored in the same insecure location (another config file)
- No check for unauthorized access during the exposure window
- No incident report or process improvement after the incident

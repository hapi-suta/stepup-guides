# Runbook - Scenario 01: SSL Not Enforced

**Severity:** High
**Category:** Encryption in transit
**Estimated resolution time:** 15 minutes

---

## Symptoms

- Security scan reports unencrypted connections to the database are allowed
- Connections succeed with `sslmode=disable`
- `SHOW rds.force_ssl;` returns `off` or `0`

---

## Impact

Database traffic between applications and RDS is not encrypted. Anyone who can intercept network traffic inside the VPC can read SQL queries, results, and any sensitive data in those queries.

---

## Diagnosis

### Step 1 - Verify unencrypted connections are accepted

```bash
psql \
  "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=disable"
```

If you connect successfully, SSL is not being enforced. If you get `FATAL: no pg_hba.conf entry...SSL off`, SSL is already enforced - the inject may not have applied yet.

### Step 2 - Check the parameter value

```bash
aws rds describe-db-parameters \
  --db-parameter-group-name [YOUR-PARAM-GROUP] \
  --query "Parameters[?ParameterName=='rds.force_ssl'].[ParameterName,ParameterValue,ApplyType]" \
  --output table \
  --region [YOUR-REGION]
```

Look for `rds.force_ssl` with value `0` or blank.

### Step 3 - Check current connections without SSL

Connect as master user and run:

```sql
SELECT
    sa.usename,
    sa.client_addr,
    ss.ssl,
    ss.cipher
FROM pg_stat_activity sa
JOIN pg_stat_ssl ss ON sa.pid = ss.pid
WHERE sa.backend_type = 'client backend'
ORDER BY ss.ssl;
```

Any row with `ssl = f` is an unencrypted connection.

---

## Resolution

### Step 1 - Find which parameter group your instance uses

```bash
aws rds describe-db-instances \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --query 'DBInstances[0].DBParameterGroups' \
  --output table \
  --region [YOUR-REGION]
```

Note the parameter group name.

### Step 2 - Set rds.force_ssl = 1

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name [PARAM-GROUP-NAME] \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=pending-reboot" \
  --region [YOUR-REGION]
```

### Step 3 - Reboot the instance to apply the change

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [YOUR-REGION]
```

Wait for the instance to return to available:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [YOUR-INSTANCE-ID] \
  --region [YOUR-REGION]
```

### Step 4 - Verify SSL is enforced

Try to connect without SSL:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=disable"
```

Expected - this should now fail:

```
FATAL:  no pg_hba.conf entry for host "...", user "postgres", database "postgres", SSL off
```

Connect with SSL:

```bash
psql "host=[YOUR-RDS-HOST] port=5432 dbname=postgres user=postgres sslmode=require"
```

This should succeed.

---

## Post-Resolution Checks

1. Confirm `rds.force_ssl = 1` in the parameter group
2. Confirm no connections exist with `ssl = f` in `pg_stat_ssl`
3. Check your application logs - any connection errors after the reboot? (Applications that were not using SSL will now fail to connect and need their connection strings fixed)
4. Update application connection strings to use `sslmode=require` or `sslmode=verify-full`

---

## Root Cause Analysis Template

After resolving, answer these questions for your incident report:

1. When was SSL enforcement disabled?
2. Who made the change and why?
3. How long was the database accepting unencrypted connections?
4. Were any unencrypted connections observed during that window?
5. What controls will prevent this from happening again?

---

## Prevention

- Add `rds.force_ssl = 1` to your standard parameter group template
- Use AWS Config rule `rds-instance-no-minor-version-upgrade-check` or a custom rule to detect SSL not enforced
- Include SSL enforcement in your RDS deployment checklist
- Require `sslmode=verify-full` in all application connection strings

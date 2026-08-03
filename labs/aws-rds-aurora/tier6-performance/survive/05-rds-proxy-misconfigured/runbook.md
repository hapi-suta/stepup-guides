# Runbook: RDS Proxy Misconfigured

**Scenario:** RDS Proxy is configured with incorrect credentials or a misconfigured target. Applications connecting through the proxy receive authentication failures or connection errors.

**Time limit:** 25 minutes
**Severity:** P1 - Complete application outage (if all traffic routes through proxy)

---

## Symptoms

- Applications receive: `FATAL: password authentication failed for user "..."` or `Connection refused`
- CloudWatch metric `DatabaseConnectionsSetupFailed` increasing
- Proxy target health shows `UNAVAILABLE`
- Direct connection to RDS endpoint still works

---

## Step 1 - Confirm Direct Connection Works

This confirms the database is healthy and the proxy is the problem:

```bash
# Direct connection (bypassing proxy)
psql -h "$DB_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 AS direct_connection_works;"
```

If this succeeds but the proxy connection fails, the problem is in the proxy configuration.

---

## Step 2 - Check Proxy Health

```bash
aws rds describe-db-proxies \
  --db-proxy-name "$PROXY_NAME" \
  --query "DBProxies[0].{Status:Status,Endpoint:Endpoint}" \
  --output table \
  --region "$REGION"
```

Expected when broken:
```
---------------------------------------------------------
|               DescribeDBProxies                       |
+----------+-------------------------------------------+
|  Status  |  Endpoint                                 |
+----------+-------------------------------------------+
|  available | proxy-xxx.proxy-yyy.us-east-1.rds...   |
+----------+-------------------------------------------+
```

Note: Proxy status may show `available` even when the target connections are failing.

Check the target health:

```bash
aws rds describe-db-proxy-targets \
  --db-proxy-name "$PROXY_NAME" \
  --region "$REGION"
```

Look for `TargetHealth.State`. When misconfigured:
```json
{
    "TargetHealth": {
        "State": "UNAVAILABLE",
        "Reason": "AUTH_FAILURE",
        "Description": "Proxy failed to connect to the target due to invalid credentials..."
    }
}
```

---

## Step 3 - Check Proxy Authentication Configuration

```bash
aws rds describe-db-proxies \
  --db-proxy-name "$PROXY_NAME" \
  --query "DBProxies[0].Auth" \
  --output table \
  --region "$REGION"
```

Note the `SecretArn` in use. Check what credentials that secret contains:

```bash
SECRET_ARN=$(aws rds describe-db-proxies \
  --db-proxy-name "$PROXY_NAME" \
  --query "DBProxies[0].Auth[0].SecretArn" \
  --output text --region "$REGION")

aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --query SecretString \
  --output text \
  --region "$REGION"
```

If the secret contains wrong credentials (wrong username or password), that is the root cause.

---

## Step 4 - Check CloudWatch Logs for the Proxy

```bash
aws logs filter-log-events \
  --log-group-name "/aws/rds/proxy/${PROXY_NAME}" \
  --filter-pattern "ERROR" \
  --region "$REGION" \
  --limit 20
```

Look for:
- `AUTH_FAILURE` - wrong credentials in the secret
- `INVALID_SECRET` - the secret ARN does not exist or is inaccessible
- `TARGET_UNAVAILABLE` - the database instance is not reachable

---

## Step 5a - Fix: Update the Secret with Correct Credentials

If the secret has wrong credentials, update it:

```bash
aws secretsmanager update-secret \
  --secret-id "$SECRET_ARN" \
  --secret-string "{\"username\":\"${DB_USER}\",\"password\":\"${DB_PASSWORD}\"}" \
  --region "$REGION"
```

Wait 60 seconds for the proxy to refresh the credential cache, then test:

```bash
psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 'proxy works' AS status;"
```

---

## Step 5b - Fix: Repoint the Proxy to the Correct Secret

If the proxy was accidentally pointed to a completely wrong secret ARN, repoint it:

```bash
# Find the correct secret ARN
aws secretsmanager list-secrets \
  --region "$REGION" \
  --query "SecretList[?Name.contains(@,'rds-proxy')].{Name:Name,ARN:ARN}" \
  --output table

# Repoint the proxy
aws rds modify-db-proxy \
  --db-proxy-name "$PROXY_NAME" \
  --auth "[{\"AuthScheme\":\"SECRETS\",\"SecretArn\":\"CORRECT_SECRET_ARN\",\"IAMAuth\":\"DISABLED\"}]" \
  --region "$REGION"
```

Wait for the proxy to update:

```bash
aws rds wait db-proxy-available \
  --db-proxy-name "$PROXY_NAME" \
  --region "$REGION"
```

---

## Step 6 - Verify Proxy Targets are Healthy

```bash
aws rds describe-db-proxy-targets \
  --db-proxy-name "$PROXY_NAME" \
  --region "$REGION" \
  --query "Targets[*].{Target:RdsResourceId,State:TargetHealth.State,Reason:TargetHealth.Reason}"
```

Expected after fix:
```json
[
    {
        "Target": "db-your-instance",
        "State": "AVAILABLE",
        "Reason": null
    }
]
```

---

## Step 7 - Test Application-Level Connection

```bash
psql -h "$PROXY_ENDPOINT" -U "$DB_USER" -d "$DB_NAME" -c "
SELECT 'proxy operational' AS status,
       current_user,
       current_database();"
```

Expected output:
```
       status        | current_user | current_database
---------------------+--------------+------------------
 proxy operational   | postgres     | postgres
```

---

## Prevention

1. Never manually edit secrets that proxy endpoints depend on without testing first.
2. Use Secrets Manager rotation with a test step that validates credentials before rotating.
3. Set a CloudWatch alarm on `DatabaseConnectionsSetupFailed > 0` for 5 minutes.
4. Keep the direct endpoint (non-proxy) in your monitoring toolkit for comparison testing.
5. Store the Secrets Manager ARN used by each proxy in your infrastructure documentation.

# Runbook - Scenario 01: SSL Not Enforced

**Severity:** High
**Category:** Encryption in transit
**Estimated resolution time:** 15 minutes

---

## What Is Being Tested

Your ability to detect that SSL enforcement is disabled on an Aurora cluster and restore it using the cluster parameter group.

---

## Why This Matters

When `rds.force_ssl` is set to `0`, applications can connect to the database without encryption. Anyone who can intercept network traffic inside the VPC can read SQL queries, query results, and any sensitive data (passwords, PII, financial data) in those queries.

Even if your applications use SSL by choice, a misconfigured app or a new tool deployed without SSL settings can create an unencrypted connection. Server-side enforcement eliminates this risk.

---

## Symptoms

- Security scan reports unencrypted connections to the database are allowed
- Connections succeed with `sslmode=disable`
- `SHOW rds.force_ssl;` returns `off` or `0`
- `pg_stat_ssl` shows connections with `ssl = f`

---

## Diagnostic Steps

### Step 1 - Verify unencrypted connections are accepted

```bash
psql \
  "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=disable"
```

If you connect successfully, SSL is not being enforced. If you get `FATAL: no pg_hba.conf entry...SSL off`, SSL is already enforced.

### Step 2 - Check the parameter value

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --query "Parameters[?ParameterName=='rds.force_ssl'].[ParameterName,ParameterValue]" \
  --output table \
  --region $AWS_REGION
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

### Step 1 - Find which parameter group your cluster uses

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].DBClusterParameterGroup' \
  --output text \
  --region $AWS_REGION
```

Note the parameter group name.

### Step 2 - Set rds.force_ssl = 1

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate" \
  --region $AWS_REGION
```

For Aurora, `rds.force_ssl` is a dynamic parameter. It takes effect without a reboot.

### Step 3 - Verify SSL is enforced

Try to connect without SSL:

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=disable"
```

Expected - this should now fail:

```
FATAL:  no pg_hba.conf entry for host "...", user "postgres", database "postgres", SSL off
```

Connect with SSL:

```bash
psql "host=$CLUSTER_ENDPOINT port=5432 dbname=postgres user=postgres sslmode=require"
```

This should succeed.

---

## Prevention

- Add `rds.force_ssl = 1` to your standard cluster parameter group template
- Use AWS Config rules to detect SSL not enforced
- Include SSL enforcement in your Aurora deployment checklist
- Require `sslmode=verify-full` in all application connection strings
- Set up a CloudWatch alarm that triggers when `rds.force_ssl` is modified

---

## Interview Questions

1. What is the difference between `sslmode=require` and `sslmode=verify-full`?
2. Does `rds.force_ssl = 1` require a reboot on Aurora?
3. What happens to existing connections when you enable SSL enforcement?
4. How can you detect unencrypted connections in a running system?

---

## Key Terminology

| Term | Definition |
|------|-----------|
| rds.force_ssl | Parameter that rejects non-SSL connections when set to 1 |
| sslmode | Client-side setting controlling SSL usage (disable/require/verify-full) |
| pg_stat_ssl | PostgreSQL view showing SSL status of each connection |
| TLS 1.3 | Current transport layer security protocol version |
| CA bundle | Certificate Authority file used to verify server certificates |

---

## Red Flags

- `rds.force_ssl = 0` on any production cluster
- Security group allows `0.0.0.0/0` AND SSL is not enforced
- Applications connecting with `sslmode=disable` or no sslmode set
- No monitoring for SSL enforcement changes in CloudTrail

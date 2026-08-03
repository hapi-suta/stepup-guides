# SURVIVE Scenario 02: Security Breach Simulation - Runbook

## Scenario

Credentials may be compromised. You see suspicious authentication failures in the logs and need to investigate, contain, and remediate.

---

## Step 1: Detect Authentication Failures

**On your local workstation:**

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-pattern "authentication failed" \
  --start-time $(date -u -v-30M +%s000) \
  --limit 20 \
  --query 'events[*].message' \
  --output text \
  --region us-east-1
```

Count the failures. More than 5 in a short window is suspicious.

---

## Step 2: Identify Suspicious Users

Connect to the database and check for unauthorized users:

```sql
SELECT usename, usesuper, usecreatedb, valuntil
FROM pg_user
WHERE usename NOT IN ('rdsadmin', 'dbadmin', 'app_service')
ORDER BY usename;
```

Any user you do not recognize is suspicious.

---

## Step 3: Check Privileges of Suspicious Users

```sql
SELECT grantee, privilege_type, table_schema, table_name
FROM information_schema.role_table_grants
WHERE grantee = 'compromised_user'
ORDER BY table_schema, table_name;
```

---

## Step 4: Lock the Compromised Account Immediately

```sql
ALTER ROLE compromised_user NOLOGIN;
```

This prevents any further connections from this user without dropping it (preserving audit trail).

---

## Step 5: Revoke All Privileges

```sql
REVOKE ALL PRIVILEGES ON ALL TABLES IN SCHEMA app FROM compromised_user;
```

```sql
REVOKE ALL PRIVILEGES ON SCHEMA app FROM compromised_user;
```

```sql
REVOKE CREATEDB FROM compromised_user;
```

---

## Step 6: Check pgaudit Logs for Data Access

**On your local workstation:**

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/cluster/devops-lab-cluster/postgresql \
  --filter-pattern "compromised_user" \
  --start-time $(date -u -v-1H +%s000) \
  --limit 50 \
  --query 'events[*].message' \
  --output text \
  --region us-east-1
```

Review audit entries to determine what data was accessed.

---

## Step 7: Rotate the Master Password

**On your local workstation:**

```bash
SECRET_ARN=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query 'DBClusters[0].MasterUserSecret.SecretArn' \
  --output text --region us-east-1)
```

```bash
aws secretsmanager rotate-secret \
  --secret-id $SECRET_ARN \
  --region us-east-1
```

---

## Step 8: Drop the Rogue User (After Investigation)

Only after you have collected all audit evidence:

```sql
DROP ROLE IF EXISTS compromised_user;
```

---

## Step 9: Document the Incident

Record:
- Timeline of events (when breach started, when detected, when contained)
- What data was accessed
- What credentials were compromised
- Remediation actions taken
- Preventive measures for the future

# Build 06 - Audit Logging

**Time:** 35 minutes
**Goal:** Enable the pgAudit extension on your Aurora cluster, configure log_statement, and set up CloudTrail logging for database-related API calls.

---

## Before You Start

Read `concepts/01-database-security-layers.md` (all layers - audit logging monitors them all).

You need:
- A running Aurora PostgreSQL cluster
- psql installed
- AWS CLI configured
- A custom cluster parameter group (created in Build 02 or earlier)

Set these variables:

```bash
export CLUSTER_ID="devops-lab-cluster"
export CLUSTER_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier $CLUSTER_ID \
  --query 'DBClusters[0].Endpoint' \
  --output text \
  --region us-east-1)
export CLUSTER_PORT="5432"
export MASTER_USER="postgres"
export MASTER_DB="postgres"
export PARAM_GROUP_NAME="devops-lab-cluster-params"
export AWS_REGION="us-east-1"
```

---

## Step 1 - Check Available Extensions

Connect to your Aurora cluster:

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=$MASTER_USER \
  --dbname=$MASTER_DB
```

Enter your master password when prompted.

Check if pgAudit is available:

```sql
SELECT name, default_version, installed_version
FROM pg_available_extensions
WHERE name = 'pgaudit';
```

Expected output (yours will differ):

```
  name   | default_version | installed_version
---------+-----------------+-------------------
 pgaudit | 16.0            |
```

The `installed_version` is blank because we have not installed it yet. The `default_version` shows it is available.

Exit psql:

```sql
\q
```

---

## Step 2 - Configure pgAudit in the Parameter Group

Before installing the extension, you must add `pgaudit` to the `shared_preload_libraries` parameter. This must be done in the cluster parameter group.

### Using the AWS CLI

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=shared_preload_libraries,ParameterValue=pgaudit,ApplyMethod=pending-reboot" \
  --region $AWS_REGION
```

`shared_preload_libraries` tells PostgreSQL which extensions to load at startup.
`ApplyMethod=pending-reboot` means the change takes effect after a reboot.

Expected output:

```json
{
    "DBClusterParameterGroupName": "devops-lab-cluster-params"
}
```

Now configure what pgAudit should log. Set `pgaudit.log` to capture DDL (schema changes) and ROLE (permission changes):

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=pgaudit.log,ParameterValue=ddl,ApplyMethod=immediate" \
  --region $AWS_REGION
```

`pgaudit.log` controls what categories of statements are logged.

Common values for `pgaudit.log`:

| Value | What it logs |
|-------|-------------|
| ddl | CREATE, ALTER, DROP statements |
| role | GRANT, REVOKE, CREATE ROLE statements |
| read | SELECT and COPY FROM |
| write | INSERT, UPDATE, DELETE, TRUNCATE |
| all | Everything above |
| none | Nothing (disables pgAudit) |

You can combine values: `ddl,role` logs both schema changes and permission changes.

For this lab, we will start with `ddl` (schema changes). In production, you might use `ddl,role` to also catch permission changes.

---

## Step 3 - Configure log_statement

The built-in `log_statement` parameter controls what PostgreSQL logs natively (without pgAudit).

Check the current value:

```bash
aws rds describe-db-cluster-parameters \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --query "Parameters[?ParameterName=='log_statement'].[ParameterName,ParameterValue]" \
  --output table \
  --region $AWS_REGION
```

Expected output:

```
+----------------+-----------------+
| log_statement  |  none           |
+----------------+-----------------+
```

`none` means PostgreSQL is not logging any SQL statements. Set it to `ddl` to log schema-changing statements:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=log_statement,ParameterValue=ddl,ApplyMethod=immediate" \
  --region $AWS_REGION
```

Available values for `log_statement`:

| Value | What it logs |
|-------|-------------|
| none | Nothing |
| ddl | CREATE, ALTER, DROP |
| mod | ddl + INSERT, UPDATE, DELETE |
| all | Every SQL statement (very noisy - use only for debugging) |

> **Note:** `log_statement=all` generates enormous log volumes. Use it only for troubleshooting, not in production.

---

## Step 4 - Enable Connection Logging

Enable logging of connection and disconnection events:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=log_connections,ParameterValue=1,ApplyMethod=immediate" \
  --region $AWS_REGION
```

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=log_disconnections,ParameterValue=1,ApplyMethod=immediate" \
  --region $AWS_REGION
```

`log_connections=1` logs every connection attempt with the username and source IP.
`log_disconnections=1` logs when each session ends and how long it lasted.

These are critical for security auditing - you can see who connected, from where, and for how long.

---

## Step 5 - Reboot to Apply shared_preload_libraries

The `shared_preload_libraries` change requires a reboot. Reboot each instance in the cluster:

```bash
export INSTANCE_ID=$(aws rds describe-db-instances \
  --filters "Name=db-cluster-id,Values=$CLUSTER_ID" \
  --query 'DBInstances[0].DBInstanceIdentifier' \
  --output text \
  --region $AWS_REGION)

echo "Rebooting instance: $INSTANCE_ID"
```

```bash
aws rds reboot-db-instance \
  --db-instance-identifier $INSTANCE_ID \
  --region $AWS_REGION
```

Wait for it to come back:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier $INSTANCE_ID \
  --region $AWS_REGION
```

This takes 2-5 minutes. The command returns with no output when the instance is available.

---

## Step 6 - Install the pgAudit Extension

Connect to your Aurora cluster:

```bash
psql \
  --host=$CLUSTER_ENDPOINT \
  --port=$CLUSTER_PORT \
  --username=$MASTER_USER \
  --dbname=$MASTER_DB
```

Install the extension:

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

`CREATE EXTENSION` loads the pgAudit module.
`IF NOT EXISTS` prevents an error if it is already installed.

Verify it is installed:

```sql
SELECT extname, extversion
FROM pg_extension
WHERE extname = 'pgaudit';
```

Expected output (yours will differ):

```
 extname | extversion
---------+------------
 pgaudit | 16.0
```

Check the current audit log settings:

```sql
SHOW pgaudit.log;
```

Expected output:

```
 pgaudit.log
-------------
 ddl
```

Check the shared preload libraries:

```sql
SHOW shared_preload_libraries;
```

Expected output (yours will differ):

```
 shared_preload_libraries
--------------------------
 pgaudit
```

---

## Step 7 - Generate Some Audit Events

Run some DDL to generate audit log entries:

```sql
CREATE TABLE audit_test (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL
);
```

```sql
ALTER TABLE audit_test ADD COLUMN email TEXT;
```

```sql
DROP TABLE audit_test;
```

These three DDL statements will appear in the PostgreSQL logs because both `log_statement=ddl` and `pgaudit.log=ddl` are enabled.

---

## Step 8 - View the Logs in CloudWatch

Aurora sends PostgreSQL logs to CloudWatch Logs. You can view them in the Console or CLI.

### Using the AWS Console

1. Open the AWS Console
2. Go to **RDS > Databases**
3. Click your cluster instance (not the cluster, but the instance under it)
4. Click the **Logs & events** tab
5. Under **Logs**, you will see log files
6. Click a recent log file to view its contents

### Using the AWS CLI

List available log files:

```bash
aws rds describe-db-log-files \
  --db-instance-identifier $INSTANCE_ID \
  --region $AWS_REGION \
  --query 'DescribeDBLogFiles[-3:]' \
  --output table
```

`[-3:]` shows only the three most recent log files.

Download the most recent log:

```bash
aws rds download-db-log-file-portion \
  --db-instance-identifier $INSTANCE_ID \
  --log-file-name "error/postgresql.log.2026-06-09-14" \
  --starting-token 0 \
  --output text \
  --region $AWS_REGION | head -50
```

`--log-file-name` is the log file to download (use the name from the previous command).
`--starting-token 0` starts from the beginning.

Look for lines containing `AUDIT:` (from pgAudit) and `LOG: statement:` (from log_statement).

Expected entries (yours will differ):

```
2026-06-09 14:25:00 UTC:10.0.1.50(12345):postgres@postgres:[12345]:LOG: AUDIT: SESSION,1,1,DDL,CREATE TABLE,TABLE,public.audit_test,"CREATE TABLE audit_test (id SERIAL PRIMARY KEY, name TEXT NOT NULL);"
2026-06-09 14:25:05 UTC:10.0.1.50(12345):postgres@postgres:[12345]:LOG: AUDIT: SESSION,2,1,DDL,ALTER TABLE,TABLE,public.audit_test,"ALTER TABLE audit_test ADD COLUMN email TEXT;"
2026-06-09 14:25:10 UTC:10.0.1.50(12345):postgres@postgres:[12345]:LOG: AUDIT: SESSION,3,1,DDL,DROP TABLE,TABLE,public.audit_test,"DROP TABLE audit_test;"
```

Each line shows: timestamp, client IP, user, database, the AUDIT category, and the full SQL statement.

---

## Step 9 - Configure Per-Role Auditing

You can audit specific roles more aggressively. For example, log ALL statements from `app_user` but only DDL from others:

```sql
ALTER ROLE app_user SET pgaudit.log = 'all';
```

This sets `pgaudit.log=all` only for sessions by `app_user`. Other users still follow the cluster-level setting (`ddl`).

Verify:

```sql
SELECT rolname, rolconfig
FROM pg_roles
WHERE rolname = 'app_user';
```

Expected output:

```
 rolname  |       rolconfig
----------+--------------------------
 app_user | {pgaudit.log=all}
```

To remove per-role audit settings:

```sql
ALTER ROLE app_user RESET pgaudit.log;
```

---

## Step 10 - CloudTrail for AWS API Calls

CloudTrail logs all AWS API calls related to your Aurora cluster. This includes:
- `ModifyDBCluster` - changes to cluster settings
- `CreateDBSnapshot` - snapshot creation
- `ModifyDBClusterParameterGroup` - parameter changes
- `DeleteDBCluster` - cluster deletion

### Using the AWS Console

1. Open the AWS Console
2. Search for **CloudTrail** in the top search bar
3. Click **Event history** in the left sidebar
4. Filter by **Event source**: `rds.amazonaws.com`
5. You will see all RDS API calls with who made them and when

### Using the AWS CLI

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=rds.amazonaws.com \
  --max-results 5 \
  --region $AWS_REGION \
  --query 'Events[*].{Time:EventTime,Name:EventName,User:Username}' \
  --output table
```

Expected output (yours will differ):

```
+---------------------------+-----------------------------------+-----------+
|          Time             |              Name                 |   User    |
+---------------------------+-----------------------------------+-----------+
| 2026-06-09T14:20:00Z      | ModifyDBClusterParameterGroup     | happy     |
| 2026-06-09T14:15:00Z      | RebootDBInstance                  | happy     |
| 2026-06-09T14:10:00Z      | ModifyDBCluster                   | happy     |
+---------------------------+-----------------------------------+-----------+
```

This tells you exactly who made each API call and when.

---

## Step 11 - Set Up a CloudWatch Alarm for Suspicious Activity

Create a CloudWatch metric filter that alerts on failed login attempts:

### Using the AWS Console

1. Go to **CloudWatch > Log groups**
2. Find your Aurora log group (usually `/aws/rds/cluster/devops-lab-cluster/postgresql`)
3. Click **Create metric filter**
4. Filter pattern: `FATAL:  password authentication failed`
5. Metric name: `FailedDBLogins`
6. Metric namespace: `Aurora/Security`
7. Metric value: `1`
8. Click **Create**

Then create an alarm:
1. Click the metric filter you just created
2. Click **Create alarm**
3. Threshold: greater than 5 in 5 minutes (adjust for your environment)
4. Notification: add an SNS topic for your team

This alerts you when someone is attempting to brute-force database passwords.

---

## What You Built

- Enabled pgAudit extension for detailed SQL statement auditing
- Configured `log_statement=ddl` for DDL logging
- Enabled connection and disconnection logging
- Viewed audit logs in CloudWatch
- Set up per-role audit settings
- Reviewed CloudTrail for AWS API call logging
- Learned how to create a CloudWatch alarm for failed logins

---

## Logging Summary

| Log Type | What It Captures | Where to Find It |
|----------|-----------------|-----------------|
| log_statement | SQL statements (none/ddl/mod/all) | CloudWatch Logs |
| pgaudit.log | Detailed audit with categories | CloudWatch Logs |
| log_connections | Connection attempts | CloudWatch Logs |
| log_disconnections | Session end + duration | CloudWatch Logs |
| CloudTrail | AWS API calls (modify, delete, snapshot) | CloudTrail > Event history |

---

## Clean Up (Optional)

Remove pgAudit:

```sql
DROP EXTENSION pgaudit;
```

Reset the parameter group values:

```bash
aws rds modify-db-cluster-parameter-group \
  --db-cluster-parameter-group-name $PARAM_GROUP_NAME \
  --parameters "ParameterName=pgaudit.log,ParameterValue=none,ApplyMethod=immediate" \
  --region $AWS_REGION
```

---

## Key Rules to Remember

1. Use `pgaudit.log=ddl,role` for production - logs schema changes and permission changes
2. Never use `log_statement=all` in production - the volume is too high
3. Always enable `log_connections` and `log_disconnections`
4. Review CloudTrail for who modified your cluster settings
5. Set up CloudWatch alarms for failed login attempts
6. Per-role auditing lets you log more aggressively for sensitive roles

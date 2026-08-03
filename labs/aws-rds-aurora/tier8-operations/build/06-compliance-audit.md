# Tier 8 - Build Guide 06: Compliance Audit

**Objective:** Enable and configure pgaudit for audit logging on RDS PostgreSQL, understand HIPAA and FedRAMP requirements as they apply to RDS, review audit logs, and configure compliant log retention.
**Time:** 35 minutes
**Level:** Expert
**infra_required:** true - Requires a running RDS PostgreSQL instance with a custom parameter group (default parameter groups cannot be modified).
**Prerequisites:** A custom RDS parameter group attached to your instance. IAM permissions to modify parameter groups and RDS instances.

---

## 1. Enable pgaudit on RDS PostgreSQL

pgaudit is a PostgreSQL extension that produces audit log entries in the PostgreSQL log stream. It provides detailed session and object-level auditing that satisfies audit requirements for HIPAA, PCI-DSS, and other frameworks.

### Create a custom parameter group (if you don't have one)

Default parameter groups cannot be modified. You must use a custom group.

**Console:**
1. Open the RDS console.
2. Select **Parameter groups** in the left navigation.
3. Click **Create parameter group**.
4. Set **Parameter group family** to match your PostgreSQL version (e.g., `aurora-postgresql16` for Aurora PostgreSQL 16).
5. Set a name (e.g., `prod-pg16-params`) and description.
6. Click **Create**.

**CLI:**
```bash
aws rds create-db-parameter-group \
  --db-parameter-group-name prod-pg16-params \
  --db-parameter-group-family aurora-postgresql16 \
  --description "Production Aurora PostgreSQL 16 parameter group" \
  --region [REGION]
```

### Attach the parameter group to your instance

**Console:**
1. RDS console > Databases > [INSTANCE-ID] > Modify
2. Scroll to **Additional configuration**.
3. Change **DB parameter group** to your custom group.
4. Apply during next maintenance window (parameter group change requires a restart for static parameters).

**CLI:**
```bash
aws rds modify-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --db-parameter-group-name prod-pg16-params \
  --apply-immediately \
  --region [REGION]
```

### Configure pgaudit in the parameter group

pgaudit must be loaded at startup via `shared_preload_libraries`.

**CLI:**
```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name prod-pg16-params \
  --parameters \
    ParameterName=shared_preload_libraries,ParameterValue=pgaudit,ApplyMethod=pending-reboot \
  --region [REGION]
```

`ApplyMethod=pending-reboot` is required because `shared_preload_libraries` is a static parameter - it takes effect only after a restart.

Reboot the instance to apply the static parameter:

```bash
aws rds reboot-db-instance \
  --db-instance-identifier [INSTANCE-ID] \
  --region [REGION]
```

Wait for the instance to return to `available` status (typically 2-5 minutes):

```bash
aws rds wait db-instance-available \
  --db-instance-identifier [INSTANCE-ID] \
  --region [REGION]
```

### Enable pgaudit session logging parameters

These are dynamic parameters - they apply immediately without a restart:

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name prod-pg16-params \
  --parameters \
    ParameterName=pgaudit.log,ParameterValue='ddl\,write\,role',ApplyMethod=immediate \
    ParameterName=pgaudit.log_catalog,ParameterValue=1,ApplyMethod=immediate \
    ParameterName=pgaudit.log_relation,ParameterValue=on,ApplyMethod=immediate \
    ParameterName=pgaudit.log_parameter,ParameterValue=on,ApplyMethod=immediate \
    ParameterName=pgaudit.log_statement_once,ParameterValue=off,ApplyMethod=immediate \
  --region [REGION]
```

`pgaudit.log='ddl,write,role'` audits all DDL statements (CREATE, DROP, ALTER), all data write statements (INSERT, UPDATE, DELETE, TRUNCATE), and all role/privilege changes. This is the minimum for HIPAA compliance.

`pgaudit.log_relation=on` includes the table/relation name in each log entry.
`pgaudit.log_parameter=on` includes bind parameters in log entries - critical for auditing parameterized queries.

For HIPAA and FedRAMP, also enable READ auditing (`pgaudit.log='read,ddl,write,role'`). This logs SELECT statements, which generates high volume - implement carefully.

### Create the pgaudit extension in the database

Connect to each database that requires auditing:

```bash
psql --host=[RDS-ENDPOINT] --port=5432 --username=[MASTER-USER] --dbname=[DBNAME]
```

```sql
CREATE EXTENSION IF NOT EXISTS pgaudit;
```

Verify it is loaded:

```sql
SELECT * FROM pg_extension WHERE extname = 'pgaudit';
```

Expected output:
```
 extname | extowner | extnamespace | extrelocatable | extversion | extconfig | extcondition
---------+----------+--------------+----------------+------------+-----------+--------------
 pgaudit |       10 |           11 | f              | 16.0       |           |
```

---

## 2. Verify pgaudit Is Generating Logs

Run some auditable operations and confirm they appear in the logs.

### Generate test audit events

```sql
-- DDL - should appear in pgaudit log
CREATE TABLE audit_test (id serial PRIMARY KEY, data text, created_at timestamptz DEFAULT now());

-- Write - should appear in pgaudit log
INSERT INTO audit_test (data) VALUES ('test record 1');
INSERT INTO audit_test (data) VALUES ('test record 2');

-- Role change - should appear in pgaudit log
CREATE ROLE readonly_user LOGIN PASSWORD 'changeme';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly_user;

-- Drop the test objects
DROP TABLE audit_test;
DROP ROLE readonly_user;
```

### Find the audit log entries in CloudWatch Logs

```bash
aws logs filter-log-events \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --filter-pattern "AUDIT" \
  --start-time $(date -u -v-10M +%s000) \
  --region [REGION] \
  --query 'events[*].message' \
  --output text
```

Expected output (yours will differ):
```
2026-01-15 14:30:01 UTC:172.31.10.5(52234):postgres@pgbench_test:[1234]:LOG:  AUDIT: SESSION,1,1,DDL,CREATE TABLE,TABLE,public.audit_test,create table audit_test (id serial ...
2026-01-15 14:30:02 UTC:172.31.10.5(52234):postgres@pgbench_test:[1234]:LOG:  AUDIT: SESSION,2,1,WRITE,INSERT,TABLE,public.audit_test,insert into audit_test ...
2026-01-15 14:30:03 UTC:172.31.10.5(52234):postgres@pgbench_test:[1234]:LOG:  AUDIT: SESSION,3,1,ROLE,CREATE ROLE,,,"create role readonly_user login password '***'"
```

Note that the password is masked (`'***'`) in role-related audit entries.

---

## 3. HIPAA Considerations for RDS

HIPAA does not prescribe specific technical controls but specifies safeguard categories. The following maps HIPAA Technical Safeguard requirements to RDS controls.

### HIPAA Technical Safeguards - RDS mapping

**Access Control (164.312(a)(1))**
- Unique user IDs: Create individual PostgreSQL roles per user. Do not share credentials.
- Automatic logoff: Set `idle_session_timeout` in the parameter group (PostgreSQL 14+).
- Encryption: Enable SSL/TLS connections. Set `rds.force_ssl=1` in the parameter group.

```bash
aws rds modify-db-parameter-group \
  --db-parameter-group-name prod-pg16-params \
  --parameters \
    ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate \
  --region [REGION]
```

**Audit Controls (164.312(b))**
- Record all access to PHI: Enable pgaudit with `log=read,write,ddl,role`
- Retain audit logs: 6-year retention required under HIPAA
- Review logs regularly: Implement automated monitoring for suspicious patterns

**Integrity (164.312(c)(1))**
- Enable Multi-AZ to prevent data loss from single AZ failure
- Enable automated backups with point-in-time recovery
- Enable deletion protection on all PHI-containing instances

**Transmission Security (164.312(e)(1))**
- Force SSL/TLS (`rds.force_ssl=1`)
- Use TLS 1.2 or higher (RDS enforces this by default in recent versions)
- Use a VPC with private subnets - never expose RDS to the public internet

### Execute the AWS Business Associate Agreement (BAA)

The AWS BAA is required before you can run PHI on AWS services under HIPAA. It is not automatic.

1. Open the AWS console.
2. Navigate to **AWS Artifact**.
3. Click **Agreements**.
4. Find the **AWS Business Associate Addendum** and accept it.

This agreement applies to HIPAA-eligible services across your entire AWS account.

### Verify your HIPAA configuration checklist

Run these checks against your instances:

```bash
# Check encryption at rest
aws rds describe-db-instances \
  --query 'DBInstances[*].{ID:DBInstanceIdentifier,Encrypted:StorageEncrypted,MultiAZ:MultiAZ,DeletionProtection:DeletionProtection}' \
  --output table \
  --region [REGION]
```

```bash
# Check SSL enforcement parameter
aws rds describe-db-parameters \
  --db-parameter-group-name prod-pg16-params \
  --query 'Parameters[?ParameterName==`rds.force_ssl`].{Name:ParameterName,Value:ParameterValue}' \
  --region [REGION]
```

```bash
# Verify pgaudit is in shared_preload_libraries
aws rds describe-db-parameters \
  --db-parameter-group-name prod-pg16-params \
  --query 'Parameters[?ParameterName==`shared_preload_libraries`]' \
  --region [REGION]
```

---

## 4. FedRAMP Context

FedRAMP (Federal Risk and Authorization Management Program) applies when cloud services are used by U.S. federal government agencies or contractors processing federal data.

### RDS FedRAMP authorization status

Amazon RDS is FedRAMP Moderate authorized in us-east-1, us-west-2, and the AWS GovCloud regions. Always verify current authorization status at the FedRAMP marketplace before deployment.

### Additional FedRAMP controls beyond HIPAA baseline

**FIPS 140-2 compliance:**
RDS supports FIPS 140-2 compliant endpoints for all connections. Use the FIPS endpoint:

```
rds-fips.[REGION].amazonaws.com
```

For connection strings, ensure clients connect to the FIPS endpoint.

**CloudTrail integration:**
Every RDS API action must be logged. Enable CloudTrail in your account and verify it is capturing RDS events:

```bash
aws cloudtrail get-trail-status --name [TRAIL-NAME] --region [REGION]
```

```bash
# Verify RDS events are being captured
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventSource,AttributeValue=rds.amazonaws.com \
  --max-results 10 \
  --region [REGION]
```

**Continuous monitoring (CM controls):**
FedRAMP requires continuous monitoring with automated scanning. Map your AWS Config rules (from Build Guide 02) to FedRAMP CM controls. AWS Config satisfies several FedRAMP CM-6, CM-7, and CM-8 requirements.

**Personnel security:**
FedRAMP requires that all individuals with access to federal data have appropriate background investigations. This is an HR/organizational control, not a technical one. Enforce least privilege at the IAM and database user level to minimize the number of individuals requiring clearance.

---

## 5. Audit Log Review and Retention

### Set log retention for compliance

HIPAA requires 6-year audit log retention. CloudWatch Logs supports up to 3,653 days (~10 years).

```bash
aws logs put-retention-policy \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --retention-in-days 2192 \
  --region [REGION]
```

`2192` days = 6 years. This retains logs in CloudWatch Logs. For cost management, consider:
- Storing in CloudWatch Logs for 90 days (hot - immediately queryable)
- Exporting to S3 after 90 days (warm - queryable with Athena)
- Applying S3 Glacier after 1 year (cold - 3-5 hour retrieval)

### Export logs to S3 for long-term retention

Create a log export task to S3:

```bash
aws logs create-export-task \
  --task-name audit-log-export-$(date +%Y%m%d) \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --from $(date -u -v-30d +%s000) \
  --to $(date -u +%s000) \
  --destination [S3-BUCKET-NAME] \
  --destination-prefix audit-logs/[INSTANCE-ID]/$(date +%Y/%m) \
  --region [REGION]
```

Run this monthly as a scheduled Lambda or EventBridge rule to automatically export monthly audit archives to S3.

### Automated audit log review

Create a CloudWatch Logs Insights scheduled query to surface suspicious access patterns:

```bash
# Query: Find access from unexpected IP addresses
aws logs start-query \
  --log-group-name /aws/rds/instance/[INSTANCE-ID]/postgresql \
  --start-time $(date -u -v-24H +%s) \
  --end-time $(date -u +%s) \
  --query-string 'fields @timestamp, @message
    | filter @message like /connection received/
    | parse @message "connection received: host=* port=*" as client_host, client_port
    | stats count(*) by client_host
    | sort count desc' \
  --region [REGION]
```

Any IP address that should not be connecting to your database should trigger an investigation.

---

## Summary

| Control | How to Implement | Compliance Framework |
|---------|-----------------|---------------------|
| Audit logging | pgaudit extension + CloudWatch log export | HIPAA, PCI, FedRAMP |
| Encryption at rest | RDS storage encryption (KMS) | HIPAA, FedRAMP, PCI |
| Encryption in transit | `rds.force_ssl=1` parameter | HIPAA, FedRAMP, PCI |
| Access control | Individual PostgreSQL roles, least privilege | HIPAA, FedRAMP, PCI |
| High availability | Multi-AZ enabled | HIPAA (integrity) |
| Log retention | CloudWatch + S3 lifecycle | HIPAA (6 years) |
| Continuous monitoring | AWS Config rules | FedRAMP (CM controls) |
| API activity logging | CloudTrail | FedRAMP |
| Business Associate Agreement | AWS Artifact | HIPAA (required) |

**Next:** [Guide 07 - Disaster Recovery Design](./07-disaster-recovery-design.md)

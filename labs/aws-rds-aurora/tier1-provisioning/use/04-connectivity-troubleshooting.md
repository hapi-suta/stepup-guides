# USE 04 - Connectivity Troubleshooting
## Tier 1: Provisioning and Connectivity

**Estimated time:** 35 minutes
**Type:** Scenario-based troubleshooting (no infrastructure to create)
**Prerequisite:** Build 04 complete

---

## Overview

A user cannot connect to the database. That is the most common support ticket a DBA gets. This exercise gives you five real scenarios with error messages. Your job: diagnose the root cause and describe the fix.

Work through each scenario on your own before reading the hints. The scenarios get harder as you go.

---

## How to Use This Exercise

For each scenario you will see:
- The error message the user gets
- Context about their environment
- Questions to answer
- The fix to apply
- Validation to confirm it worked

---

## Scenario 1 - The New Developer

**The complaint:**
> "I just joined the company. I followed the setup doc and ran psql. I get this error. Help!"

**Error message:**
```
psql: error: connection to server at "myapp-prod.abc123.us-east-1.rds.amazonaws.com"
(54.234.189.12), port 5432 failed:
FATAL:  password authentication failed for user "developer1"
```

**Context:**
- The developer was given these credentials: username `developer1`, password `Welcome123`
- The database was created by the senior DBA
- psql is installed correctly and the endpoint resolves (the IP appears in the error)
- The developer can ping the IP

**Questions:**

1. The connection reached PostgreSQL (you can see this because the error is `FATAL:` from PostgreSQL itself, not a network error). What does that tell you about the security group and endpoint?

2. The error says "password authentication failed for user developer1". List two possible causes.

3. What CLI command would you run to check if the user `developer1` exists in the database?

4. What is the fix?

**Hint:** The DBA needs to check if the user was created in the database. The user existing in the AWS IAM is not the same as the user existing in PostgreSQL.

**Fix (describe it in your own words):**

The senior DBA needs to connect with the master user and run:
```sql
CREATE USER developer1 WITH PASSWORD 'Welcome123';
GRANT CONNECT ON DATABASE appdb TO developer1;
```

Or, if the user exists but the password is wrong:
```sql
ALTER USER developer1 WITH PASSWORD 'Welcome123';
```

**Validation:**
```bash
psql -h myapp-prod.abc123.us-east-1.rds.amazonaws.com \
  -U developer1 -d appdb -p 5432
```
Should prompt for password and succeed.

---

## Scenario 2 - The Remote Worker

**The complaint:**
> "Everything worked fine at the office. I'm working from home now and I can't connect. Nothing changed on my end."

**Error message:**
```
psql: error: connection to server at "myapp-dev.xyz789.us-east-1.rds.amazonaws.com" (54.198.77.33),
port 5432 failed: Connection timed out
        Is the server running on that host and accepting TCP/IP connections?
```

**Context:**
- The instance is `db.t3.micro` in us-east-1
- The developer confirmed the instance is `available` in the Console
- The security group has one inbound rule: TCP 5432 from `203.45.67.89/32`
- The developer's home IP is `98.12.34.56`
- The company office IP is `203.45.67.89`

**Questions:**

1. "Connection timed out" - what does this mean at the network level?

2. Why did it work at the office but not at home?

3. What is the security group rule that is causing this?

4. What are two ways to fix this?

**The problem:**
The security group only allows the office IP (`203.45.67.89/32`). The developer's home IP (`98.12.34.56`) is not in the rule.

**Fix Option A (quick, for one person):**
```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0abc123def456789a \
  --protocol tcp \
  --port 5432 \
  --cidr 98.12.34.56/32
```

**Fix Option B (better approach - CIDR range for remote workers):**
Use a VPN. All remote workers connect through the VPN, which has a fixed IP. Add that VPN IP to the security group instead of individual home IPs.

**Validation:**
```bash
nc -zv myapp-dev.xyz789.us-east-1.rds.amazonaws.com 5432
```
Expected: `Connection to... port... succeeded!`

---

## Scenario 3 - The Wrong Environment

**The complaint:**
> "I ran some cleanup queries and now the production application is throwing database errors. I think I accidentally deleted something important."

**Error message (from the application logs):**
```
ERROR: could not translate host name "myapp-prod-new.abc123.us-east-1.rds.amazonaws.com"
to address: Name or service not known
```

**Context:**
- The application's database config file was recently updated
- The old endpoint was: `myapp-prod.abc123.us-east-1.rds.amazonaws.com`
- The new endpoint in the config is: `myapp-prod-new.abc123.us-east-1.rds.amazonaws.com`
- Running `dig myapp-prod-new.abc123.us-east-1.rds.amazonaws.com` returns nothing
- Running `dig myapp-prod.abc123.us-east-1.rds.amazonaws.com` returns an IP

**Questions:**

1. The error says "could not translate host name". What is happening at the DNS level?

2. Does this error mean PostgreSQL is down?

3. What CLI command can you use to see all RDS endpoints in your account to find the correct one?

4. What is the root cause and what is the fix?

**The problem:**
Someone changed the endpoint in the application config to an endpoint that does not exist. The old endpoint (`myapp-prod`) is still running fine.

**Find all endpoints:**
```bash
aws rds describe-db-instances \
  --query "DBInstances[*].{ID:DBInstanceIdentifier,Endpoint:Endpoint.Address,Status:DBInstanceStatus}" \
  --output table
```

**Fix:**
Update the application config file to use the correct endpoint: `myapp-prod.abc123.us-east-1.rds.amazonaws.com`

This is a configuration error, not a database problem. The database itself is fine.

**Validation:**
```bash
dig +short myapp-prod.abc123.us-east-1.rds.amazonaws.com
```
Should return an IP. The application should recover immediately after the config is fixed and the app restarted.

---

## Scenario 4 - The SSL Problem

**The complaint:**
> "My Python script was working yesterday. Today I get a weird SSL error. I didn't change anything."

**Error message:**
```
psycopg2.OperationalError: SSL connection has been closed unexpectedly
```

**Or alternately:**
```
psycopg2.OperationalError: FATAL: no pg_hba.conf entry for host "10.0.1.45",
user "appuser", database "appdb", SSL off
```

**Context:**
- The RDS instance had `rds.force_ssl = 0` (SSL optional)
- A DBA applied a new parameter group yesterday that has `rds.force_ssl = 1`
- The Python script uses this connection string:
  `postgresql://appuser:password@endpoint:5432/appdb`
- The script does not specify sslmode

**Questions:**

1. What does `rds.force_ssl = 1` do to all incoming connections?

2. When no `sslmode` is specified in a psycopg2 connection, what does it default to?

3. Why would yesterday's script work but today's fail?

4. What is the fix in the Python script?

5. What is the longer-term fix (changing what in the codebase)?

**The problem:**
The parameter group change enforced SSL. The Python script did not specify `sslmode`, which defaults to `prefer` in libpq (tries SSL, falls back to non-SSL). After `rds.force_ssl = 1`, non-SSL connections are rejected.

**Fix the script:**
```python
conn = psycopg2.connect(
    host=endpoint,
    port=5432,
    dbname="appdb",
    user="appuser",
    password=password,
    sslmode="require"      # Add this
)
```

**Validation:**
```bash
python3 your_script.py
```
Should connect without error. The `pg_stat_ssl` view in PostgreSQL will show `ssl = t` for your connection.

---

## Scenario 5 - The Stopped Instance (Multi-Part)

**The complaint:**
> "Our application has been down for 10 minutes. Everything was working. Now nobody can connect."

**Error sequence:**
- At 14:03: application starts throwing `Connection refused`
- At 14:04: application throws `Connection timed out`
- At 14:10: operations team is paged

**Context:**
- This is a production `db.m6g.xlarge` in us-east-1
- It is Single-AZ (no Multi-AZ standby)
- The DBA checks CloudWatch and sees all metrics stopped updating at 14:02
- AWS Health Dashboard shows no service disruptions for RDS in us-east-1
- The last automated backup completed at 03:00 this morning

**Questions:**

1. "Connection refused" at 14:03, then "Connection timed out" at 14:04 - why would the error type change? What sequence of events does this suggest?

2. What CLI command do you run FIRST to check the instance state?

3. Running `aws rds describe-db-instances --db-instance-identifier prod-db --query "DBInstances[0].DBInstanceStatus" --output text` returns `stopped`. How would an RDS instance end up stopped? (List at least 2 possible causes.)

4. AWS RDS instances in "stopped" state automatically restart after 7 days. The instance was stopped 2 days ago. What is the immediate fix?

5. Once the instance is started and `available`, what do you check to confirm data integrity?

6. After resolving the immediate incident, what architectural change would prevent this type of outage in the future?

**The problem:**
The instance was stopped (either manually or by an automated process). Single-AZ means no standby to take over.

**Immediate fix:**

```bash
# Start the instance
aws rds start-db-instance \
  --db-instance-identifier prod-db

# Wait (takes 3-5 minutes)
aws rds wait db-instance-available \
  --db-instance-identifier prod-db

# Get the endpoint (in case it changed - it should not, but verify)
aws rds describe-db-instances \
  --db-instance-identifier prod-db \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

**Validate data integrity:**

Connect with psql and run:

```sql
-- Check PostgreSQL reports no errors
SELECT pg_catalog.pg_database.datname,
       pg_catalog.pg_stat_database.numbackends,
       pg_catalog.pg_stat_database.deadlocks
FROM pg_catalog.pg_stat_database
JOIN pg_catalog.pg_database ON pg_database.oid = pg_stat_database.datid
WHERE datname NOT IN ('template0', 'template1', 'rdsadmin');
```

```sql
-- Check for corrupted tables (runs a VACUUM ANALYZE, which also checks for issues)
VACUUM ANALYZE;
```

**Long-term fix:**
Enable Multi-AZ for the instance. A Multi-AZ standby keeps a warm copy of the instance in a second AZ. If the primary fails or is stopped, the standby takes over automatically in 60-120 seconds.

```bash
aws rds modify-db-instance \
  --db-instance-identifier prod-db \
  --multi-az \
  --apply-immediately
```

---

## Summary: Troubleshooting Decision Tree

```
Cannot connect to RDS
         |
         v
What is the error message?
         |
    +---------+----------+----------+
    |         |          |          |
    v         v          v          v
"timed   "refused"  "could not  "password
 out"              translate"  failed"
    |         |          |          |
    v         v          v          v
SG rules  Instance   Wrong       Wrong
wrong or  stopped    endpoint    user/pass
public    or not                 or user
access=No listening              doesn't
                                 exist
```

Use `nc -zv endpoint 5432` to quickly tell the difference between a network problem (timed out, no response) and a PostgreSQL problem (connection refused or authentication error).

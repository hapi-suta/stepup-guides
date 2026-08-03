# USE 01 - Provision a Complete RDS Instance from Scratch
## Tier 1: Provisioning and Connectivity

**Estimated time:** 45 minutes
**Type:** Guided exercise with requirements (no step-by-step help)
**Prerequisite:** Build 01, Build 02, Build 04 complete

---

## Overview

You are a junior DBA at [COMPANY]. A developer has submitted this ticket:

> "We need a PostgreSQL database for the new [PROJECT] application. The app is still in development. We will have maybe 20 concurrent users at peak. The team wants to be able to connect directly from their laptops for now. Database size is expected to stay under 50 GB for the next year."

Your job: provision everything from scratch.

---

## Requirements

Work through each requirement. Use the Console OR the CLI - your choice. Reference the Build guides if you get stuck, but try each step on your own first.

### Requirement 1 - Create a Subnet Group

Create a new DB subnet group called `suta-use01-subnetgroup`.

Rules:
- Must be in your default VPC
- Must include subnets in at least 2 different Availability Zones

Hints:
- You need the VPC ID first
- Then find the subnet IDs in that VPC
- The `aws rds create-db-subnet-group` command or Console > RDS > Subnet groups

Confirm your subnet group is valid:

```bash
aws rds describe-db-subnet-groups \
  --db-subnet-group-name suta-use01-subnetgroup \
  --query "DBSubnetGroups[0].SubnetGroupStatus" \
  --output text
```

Expected output:
```
Complete
```

---

### Requirement 2 - Create a Security Group

Create a security group called `suta-use01-sg` in your default VPC.

Rules:
- Allow inbound PostgreSQL (port 5432) from your laptop's current IP only
- No other inbound rules

Confirm the rule exists:

```bash
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=suta-use01-sg" \
  --query "SecurityGroups[0].IpPermissions[0]" \
  --output json
```

Expected output should show `FromPort: 5432` and a `/32` CIDR matching your IP.

---

### Requirement 3 - Create a Parameter Group

Create a custom parameter group called `suta-use01-params` using the `postgres15` family (or the version you are using).

Commands:
- `aws rds create-db-parameter-group` OR Console > RDS > Parameter groups

You do not need to change any parameters yet. Just create the group.

Confirm it exists:

```bash
aws rds describe-db-parameter-groups \
  --db-parameter-group-name suta-use01-params \
  --query "DBParameterGroups[0].DBParameterGroupName" \
  --output text
```

Expected output:
```
suta-use01-params
```

---

### Requirement 4 - Create the RDS Instance

Create an RDS PostgreSQL instance with these exact specifications:

| Setting | Value |
|---------|-------|
| Instance identifier | `suta-use01-postgres` |
| Engine | PostgreSQL (latest available minor version) |
| Instance class | `db.t3.micro` |
| Storage type | `gp3` |
| Allocated storage | `20 GB` |
| Master username | `dbadmin` |
| Initial database | `appdb` |
| Subnet group | `suta-use01-subnetgroup` |
| Security group | `suta-use01-sg` |
| Parameter group | `suta-use01-params` |
| Public access | Yes |
| Multi-AZ | No |
| Automated backups | Disabled (retention period = 0) |

Wait until the instance status is `available` before proceeding.

---

### Requirement 5 - Verify the Instance Configuration

After the instance is available, answer each question by running the appropriate CLI command.

**Question A:** What is the endpoint address?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-use01-postgres \
  --query "DBInstances[0].Endpoint.Address" \
  --output text
```

Write down the endpoint.

**Question B:** What is the engine version that was installed?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-use01-postgres \
  --query "DBInstances[0].EngineVersion" \
  --output text
```

**Question C:** Is public access enabled?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-use01-postgres \
  --query "DBInstances[0].PubliclyAccessible" \
  --output text
```

Expected: `True`

**Question D:** Which parameter group is attached?

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-use01-postgres \
  --query "DBInstances[0].DBParameterGroups[0].DBParameterGroupName" \
  --output text
```

Expected: `suta-use01-params`

---

### Requirement 6 - Connect and Validate

Connect to the instance with psql and run these checks. Each check should pass before you move to the next.

**Check A:** Can you connect?

```bash
psql -h YOUR_ENDPOINT -U dbadmin -d appdb -p 5432
```

You should reach a psql prompt.

**Check B:** Inside psql - confirm the database name:

```sql
SELECT current_database();
```

Expected: `appdb`

**Check C:** Confirm the user is not a true superuser:

```sql
SELECT rolsuper FROM pg_roles WHERE rolname = 'dbadmin';
```

Expected: `f`

**Check D:** Confirm the connection is using SSL:

```sql
SELECT ssl FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected: `t`

**Check E:** Create the first application table:

```sql
CREATE TABLE app_users (
    id SERIAL PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO app_users (email) VALUES
    ('alice@example.com'),
    ('bob@example.com');

SELECT count(*) FROM app_users;
```

Expected: `2`

**Check F:** Exit psql:

```sql
\q
```

---

### Requirement 7 - Answer the Questions

Based on what you built, answer these questions in writing. No looking up answers - use what you know from the build guides.

1. The developer asks: "Can I connect from home tonight?" What do you tell them?

2. The team lead asks: "Is this database secure?" What are two things you would improve for a production deployment?

3. A new developer on the team asks: "Why did you create a parameter group if you didn't change any settings in it?" What is your answer?

4. The instance class is `db.t3.micro`. What happens to performance if the database has heavy queries running for 2 hours straight?

5. You look at the billing and see the instance has been running for a week with no activity. What should you do?

---

## Cleanup

When you are done, delete all resources you created. Delete in this order:

1. Delete the RDS instance (skip final snapshot)
2. Wait for deletion to complete
3. Delete the DB subnet group
4. Delete the security group
5. Delete the parameter group

CLI cleanup commands:

```bash
aws rds delete-db-instance \
  --db-instance-identifier suta-use01-postgres \
  --skip-final-snapshot

aws rds wait db-instance-deleted \
  --db-instance-identifier suta-use01-postgres

aws rds delete-db-subnet-group \
  --db-subnet-group-name suta-use01-subnetgroup

aws ec2 delete-security-group \
  --group-name suta-use01-sg

aws rds delete-db-parameter-group \
  --db-parameter-group-name suta-use01-params
```

---

## Self-Assessment

Rate yourself on each skill (1 = needed lots of help, 3 = did it independently):

| Skill | Rating |
|-------|--------|
| Creating a subnet group via CLI | 1 / 2 / 3 |
| Creating and configuring a security group | 1 / 2 / 3 |
| Creating a parameter group | 1 / 2 / 3 |
| Creating an RDS instance with specific settings | 1 / 2 / 3 |
| Verifying instance configuration with CLI queries | 1 / 2 / 3 |
| Connecting with psql and running validation queries | 1 / 2 / 3 |

If you rated yourself 1 on any skill, go back to the corresponding Build guide and do it again.

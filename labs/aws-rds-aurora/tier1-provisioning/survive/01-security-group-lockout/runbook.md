# Runbook: Security Group Lockout
## Survive Scenario 01

**Symptom:** All connections to the RDS database are failing with "Connection timed out"
**Severity:** Critical - database is unreachable
**Time to resolve:** 10 to 15 minutes

---

## Your Starting Point

Someone or something removed all inbound rules from the RDS security group. Nobody can connect to the database. The application is down.

You get this alert:
```
ALERT: Application health check failed.
Error: psql: error: connection to server at "suta-rds-lab.abc123.us-east-1.rds.amazonaws.com"
       port 5432 failed: Connection timed out
```

---

## Step 1 - Confirm the Database Instance is Running

Before touching security groups, confirm the database itself is up.

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].{Status:DBInstanceStatus,Class:DBInstanceClass}" \
  --output table
```

Expected output:
```
--------------------------
| DescribeDBInstances    |
+-------+----------------+
| Class | Status         |
+-------+----------------+
| db.t3.micro | available |
+-------+----------------+
```

If status is `available`, the database is running. The problem is in the network path.

---

## Step 2 - Test Port Connectivity

Use `nc` (netcat) to test if port 5432 is reachable independently of PostgreSQL:

```bash
nc -zv suta-rds-lab.abc123.us-east-1.rds.amazonaws.com 5432
```

Expected output when blocked:
```
nc: connectx to suta-rds-lab.abc123.us-east-1.rds.amazonaws.com port 5432 (tcp) failed:
Operation timed out
```

This confirms the port is blocked at the network layer. The problem is the security group, not PostgreSQL.

---

## Step 3 - Inspect the Security Group

Find the security group ID attached to the RDS instance:

```bash
aws rds describe-db-instances \
  --db-instance-identifier suta-rds-lab \
  --query "DBInstances[0].VpcSecurityGroups[*]" \
  --output table
```

Expected output:
```
---------------------------------------------------
|           DescribeDBInstances                   |
+------------------+------------------------------+
|   Status         |  VpcSecurityGroupId          |
+------------------+------------------------------+
|  active          |  sg-0abc123def456789a        |
+------------------+------------------------------+
```

Write down the security group ID. Now look at its inbound rules:

```bash
aws ec2 describe-security-groups \
  --group-ids sg-0abc123def456789a \
  --query "SecurityGroups[0].IpPermissions" \
  --output json
```

Expected output when all rules are removed:
```json
[]
```

Empty array. No inbound rules. That is your problem.

---

## Step 4 - Find Your Current IP

Before adding a rule, get your current IP:

```bash
curl -s https://checkip.amazonaws.com
```

Example output:
```
203.0.113.42
```

Write this down. Replace `YOUR_IP` in the next step.

---

## Step 5 - Add the Inbound Rule Back

Add a rule to allow PostgreSQL (port 5432) from your IP:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id sg-0abc123def456789a \
  --protocol tcp \
  --port 5432 \
  --cidr YOUR_IP/32
```

No output = success. If you get an error saying "the specified rule already exists", the rule is already there (someone else fixed it).

---

## Step 6 - Verify the Rule Was Added

```bash
aws ec2 describe-security-groups \
  --group-ids sg-0abc123def456789a \
  --query "SecurityGroups[0].IpPermissions" \
  --output json
```

Expected output:
```json
[
    {
        "FromPort": 5432,
        "IpProtocol": "tcp",
        "IpRanges": [
            {
                "CidrIp": "203.0.113.42/32"
            }
        ],
        "ToPort": 5432
    }
]
```

---

## Step 7 - Test Port Connectivity Again

```bash
nc -zv suta-rds-lab.abc123.us-east-1.rds.amazonaws.com 5432
```

Expected output when port is open:
```
Connection to suta-rds-lab.abc123.us-east-1.rds.amazonaws.com port 5432 [tcp/postgresql] succeeded!
```

---

## Step 8 - Connect with psql

```bash
psql -h suta-rds-lab.abc123.us-east-1.rds.amazonaws.com \
  -U postgres -d labdb -p 5432
```

Expected output:
```
psql (16.6)
SSL connection (protocol: TLSv1.3, ...)
Type "help" for help.

labdb=>
```

Run a quick test:

```sql
SELECT 'recovered' AS status;
\q
```

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | All inbound rules removed from security group |
| Impact | All connections blocked. Application down. |
| How to detect | "Connection timed out" + nc test fails + SG shows no rules |
| Fix | Add inbound TCP 5432 rule for required source CIDR |
| Time to fix | Under 5 minutes once diagnosed |

---

## Prevention

1. Enable **AWS Config rule** `restricted-ssh` (and create a similar rule for port 5432) to alert when security group rules change unexpectedly.

2. Use **CloudTrail** to log all API calls. If rules are removed, you can see who did it and when.

3. Use **IAM policies** to restrict who can modify security group rules in production.

4. Use **AWS Security Hub** to detect overly permissive or empty security groups automatically.

---

## Now Run the Validate Script

```bash
bash /Users/hafopezi/Projects/practice/labs/labs/aws-rds-aurora/tier1-provisioning/survive/01-security-group-lockout/validate.sh
```

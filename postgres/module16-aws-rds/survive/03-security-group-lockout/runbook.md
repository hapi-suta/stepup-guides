# SURVIVE 03 - Security Group Lockout

## Symptom

All connections to the RDS instance are timing out. psql hangs and eventually fails with "connection timed out". The instance status shows `available` in the AWS console, but no one can connect.

---

## Diagnosis

### Step 1 - Verify the instance is running

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Status:DBInstanceStatus,Endpoint:Endpoint.Address,Port:Endpoint.Port}" \
    --output table
```

If the status is `available`, the database itself is fine. The problem is at the network layer.

### Step 2 - Try to connect

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432 --connect-timeout=5
```

The `--connect-timeout=5` limits the attempt to 5 seconds. Without it, psql hangs for minutes.

Expected output:

```
psql: error: connection to server at "suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com" (10.0.1.50), port 5432 failed: timeout expired
```

A timeout (not refused) means the packets are being dropped - classic security group behavior.

### Step 3 - Check the security group rules

```bash
SG_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].VpcSecurityGroups[0].VpcSecurityGroupId" --output text)
```

```bash
aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query "SecurityGroups[0].{GroupName:GroupName,InboundRules:IpPermissions}" \
    --output json
```

If `IpPermissions` is an empty array `[]`, there are no inbound rules. That is the problem.

### Step 4 - Confirm no port 5432 rule exists

```bash
aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`]" \
    --output json
```

Expected output (if the rule is missing):

```json
[]
```

---

## Fix

### Step 5 - Get your current public IP

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
```

```bash
echo "My IP: ${MY_IP}"
```

### Step 6 - Add the PostgreSQL inbound rule

```bash
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 5432 \
    --cidr "${MY_IP}/32"
```

The `/32` restricts access to your exact IP. In production, you would add the application server's security group or VPC CIDR.

Expected output (yours will differ):

```json
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0abc123...",
            "GroupId": "sg-0123456...",
            "IpProtocol": "tcp",
            "FromPort": 5432,
            "ToPort": 5432,
            "CidrIpv4": "203.0.113.50/32"
        }
    ]
}
```

### Step 7 - Test the connection

Security group changes take effect immediately (within seconds):

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432 --connect-timeout=5
```

The `--connect-timeout=5` limits the attempt to 5 seconds.

Once connected, run a quick test:

```sql
SELECT 'connection restored' AS status;
```

Expected output:

```
       status
--------------------
 connection restored
(1 row)
```

Exit psql:

```sql
\q
```

### Step 8 - Verify the rule is correct

```bash
aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query "SecurityGroups[0].IpPermissions[?FromPort==\`5432\`].{Protocol:IpProtocol,Port:FromPort,Sources:IpRanges[*].CidrIp}" \
    --output table
```

Confirm port 5432 is open for your IP.

---

## Prevention

### Step 9 - Use AWS Config to detect security group changes

Set up an AWS Config rule that alerts on security group modifications:

```bash
aws configservice put-config-rule \
    --config-rule '{
        "ConfigRuleName": "rds-sg-change-detection",
        "Source": {
            "Owner": "AWS",
            "SourceIdentifier": "RESTRICTED_INCOMING_TRAFFIC"
        },
        "Scope": {
            "ComplianceResourceTypes": ["AWS::EC2::SecurityGroup"]
        }
    }'
```

This monitors security groups and flags non-compliant changes.

---

## Verification

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432 --connect-timeout=5
```

Once connected, verify the database is responding:

```sql
SELECT version();
```

Expected output (yours will differ):

```
                                                   version
--------------------------------------------------------------------------------------------------------------
 PostgreSQL 15.4 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-6), 64-bit
(1 row)
```

If this returns the PostgreSQL version, the lockout is resolved.

Exit psql:

```sql
\q
```

---

## Discussion Questions

1. Why does a missing security group rule cause a timeout instead of "connection refused"?
2. What is the difference between security groups and NACLs for troubleshooting?
3. How would you audit security group changes in production?
4. Should you ever use 0.0.0.0/0 for an RDS security group?

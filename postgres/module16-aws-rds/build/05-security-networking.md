# BUILD 05 - Security and Networking for RDS

## What You Will Build

By the end of this guide you will have IAM database authentication, enforced SSL/TLS, properly configured security groups and NACLs, Secrets Manager credential rotation, and encryption at rest. This covers the full security stack for RDS PostgreSQL.

---

## Prerequisites

- Completed BUILD 01 (RDS instance `suta-pg-lab` running)
- AWS CLI v2 configured
- psql client installed

---

## Step 1 - Enforce SSL/TLS Connections

RDS PostgreSQL supports SSL by default, but does not require it. Check current SSL status:

```bash
RDS_ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].Endpoint.Address" --output text)
```

Connect without SSL to test:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=disable"
```

If this connects, SSL is not enforced. Exit:

```sql
\q
```

Force SSL through the parameter group:

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name suta-pg15-params \
    --parameters "ParameterName=rds.force_ssl,ParameterValue=1,ApplyMethod=immediate"
```

The `rds.force_ssl` parameter is RDS-specific (not a standard PostgreSQL parameter). Setting it to `1` rejects any connection that does not use SSL.

Now test again without SSL:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=disable"
```

Expected output:

```
psql: error: connection to server at "suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com" (10.0.1.50), port 5432 failed: FATAL:  no pg_hba.conf entry for host "10.0.2.100", user "sutaadmin", database "postgres", no encryption
```

The connection is rejected. Now connect with SSL:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=require"
```

Verify SSL details once connected:

```sql
SELECT ssl, version, cipher FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:

```
 ssl | version |         cipher
-----+---------+---------------------------
 t   | TLSv1.3 | TLS_AES_256_GCM_SHA384
(1 row)
```

Exit psql:

```sql
\q
```

---

## Step 2 - Download the RDS CA Certificate

For production, use `sslmode=verify-full` to validate the server certificate:

```bash
curl -o /tmp/rds-combined-ca-bundle.pem https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
```

This downloads the RDS certificate authority bundle. It contains root CAs for all AWS regions.

Connect with full certificate verification:

```bash
psql "host=${RDS_ENDPOINT} user=sutaadmin dbname=postgres sslmode=verify-full sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

The `sslmode=verify-full` validates that the server certificate is signed by a trusted CA AND that the hostname matches. `sslrootcert` points to the CA bundle.

---

## Step 3 - Enable IAM Database Authentication

IAM auth lets you connect using an IAM token instead of a password. The token expires after 15 minutes.

Enable IAM auth on the instance:

```bash
aws rds modify-db-instance \
    --db-instance-identifier suta-pg-lab \
    --enable-iam-database-authentication \
    --apply-immediately
```

This modifies the instance to accept IAM auth tokens in addition to passwords.

Wait for the modification:

```bash
aws rds wait db-instance-available \
    --db-instance-identifier suta-pg-lab
```

---

## Step 4 - Create a Database User for IAM Auth

Connect as the master user:

```bash
psql -h "${RDS_ENDPOINT}" -U sutaadmin -d postgres -p 5432
```

Create a user with the `rds_iam` role:

```sql
CREATE USER iam_user WITH LOGIN;
```

```sql
GRANT rds_iam TO iam_user;
```

The `rds_iam` role is an RDS-specific role. Granting it to a user tells RDS to accept IAM tokens for that user instead of a password.

Grant permissions:

```sql
GRANT CONNECT ON DATABASE postgres TO iam_user;
```

```sql
GRANT USAGE ON SCHEMA public TO iam_user;
```

```sql
GRANT SELECT ON ALL TABLES IN SCHEMA public TO iam_user;
```

Exit psql:

```sql
\q
```

---

## Step 5 - Create an IAM Policy for DB Access

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
```

```bash
DBI_RESOURCE_ID=$(aws rds describe-db-instances --db-instance-identifier suta-pg-lab --query "DBInstances[0].DbiResourceId" --output text)
```

Create the IAM policy:

```bash
aws iam create-policy \
    --policy-name suta-rds-iam-connect \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": \"rds-db:connect\",
            \"Resource\": \"arn:aws:rds-db:us-east-1:${ACCOUNT_ID}:dbuser:${DBI_RESOURCE_ID}/iam_user\"
        }]
    }"
```

The `rds-db:connect` action allows generating authentication tokens. The resource ARN specifies the exact database instance and database user. Format: `arn:aws:rds-db:REGION:ACCOUNT:dbuser:DBI_RESOURCE_ID/DB_USER`.

Expected output (yours will differ):

```json
{
    "Policy": {
        "PolicyName": "suta-rds-iam-connect",
        "Arn": "arn:aws:iam::123456789012:policy/suta-rds-iam-connect",
        ...
    }
}
```

Attach the policy to your IAM user:

```bash
aws iam attach-user-policy \
    --user-name student \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/suta-rds-iam-connect"
```

Replace `student` with your actual IAM username.

---

## Step 6 - Connect Using IAM Authentication

Generate an authentication token:

```bash
IAM_TOKEN=$(aws rds generate-db-auth-token \
    --hostname "${RDS_ENDPOINT}" \
    --port 5432 \
    --username iam_user \
    --region us-east-1)
```

This generates a temporary token that acts as the password. The token is valid for 15 minutes.

Connect with the token:

```bash
psql "host=${RDS_ENDPOINT} port=5432 dbname=postgres user=iam_user password=${IAM_TOKEN} sslmode=require sslrootcert=/tmp/rds-combined-ca-bundle.pem"
```

The token is passed as the password. SSL is required for IAM authentication - it will not work without SSL.

Expected output (yours will differ):

```
psql (15.4)
SSL connection (protocol: TLSv1.3, cipher: TLS_AES_256_GCM_SHA384, compression: off)
Type "help" for help.

postgres=>
```

Verify you are connected as iam_user:

```sql
SELECT current_user, session_user;
```

Expected output:

```
 current_user | session_user
--------------+--------------
 iam_user     | iam_user
(1 row)
```

Exit psql:

```sql
\q
```

---

## Step 7 - Security Groups Deep Dive

List current security group rules:

```bash
aws ec2 describe-security-groups \
    --group-names suta-rds-sg \
    --query "SecurityGroups[0].IpPermissions[*].{Protocol:IpProtocol,Port:FromPort,Sources:IpRanges[*].CidrIp}" \
    --output table
```

Expected output (yours will differ):

```
-----------------------------------------------
|        DescribeSecurityGroups               |
+----------+------+---------------------------+
| Protocol | Port |         Sources           |
+----------+------+---------------------------+
|  tcp     | 5432 |  203.0.113.50/32          |
+----------+------+---------------------------+
```

Best practices for RDS security groups:
- Never use 0.0.0.0/0 (open to the world)
- Use /32 for individual IPs
- For applications, reference the application's security group ID instead of IP ranges
- Review and audit rules regularly

Add a rule that references another security group (for application servers):

```bash
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 5432 \
    --source-group sg-0app1234567890abc
```

Replace `sg-0app1234567890abc` with your application server's security group ID. This allows any instance in that security group to connect to RDS on port 5432.

---

## Step 8 - Network ACLs (NACLs)

NACLs are stateless firewall rules at the subnet level. They act in addition to security groups.

Find the NACLs for your subnets:

```bash
aws ec2 describe-network-acls \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "NetworkAcls[*].{AclId:NetworkAclId,Rules:Entries[?RuleAction=='allow'].[RuleNumber,Protocol,PortRange.From,PortRange.To,CidrBlock]}" \
    --output json
```

This lists all NACLs in your VPC and shows only the allow rules. Key difference from security groups:
- NACLs are stateless - you need both inbound AND outbound rules
- NACLs are numbered - rules are evaluated in order (lowest number first)
- NACLs apply to the subnet, not individual instances
- Default NACL allows all traffic

For RDS, ensure your NACL allows:
- Inbound: TCP port 5432 from your application subnets
- Outbound: TCP ephemeral ports (1024-65535) to your application subnets

---

## Step 9 - Secrets Manager for Credential Rotation

Store the RDS master password in Secrets Manager:

```bash
aws secretsmanager create-secret \
    --name suta/rds/master-password \
    --description "Master password for suta-pg-lab RDS instance" \
    --secret-string '{
        "username": "sutaadmin",
        "password": "ChangeMe-2024!",
        "engine": "postgres",
        "host": "suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com",
        "port": 5432,
        "dbname": "postgres",
        "dbInstanceIdentifier": "suta-pg-lab"
    }'
```

Replace the host value with your actual RDS endpoint. The JSON format is required for automatic rotation to work.

Retrieve the secret:

```bash
aws secretsmanager get-secret-value \
    --secret-id suta/rds/master-password \
    --query "SecretString" \
    --output text
```

Expected output (yours will differ):

```json
{"username":"sutaadmin","password":"ChangeMe-2024!","engine":"postgres","host":"suta-pg-lab.c9abcdef12gh.us-east-1.rds.amazonaws.com","port":5432,"dbname":"postgres","dbInstanceIdentifier":"suta-pg-lab"}
```

Enable automatic rotation:

```bash
aws secretsmanager rotate-secret \
    --secret-id suta/rds/master-password \
    --rotation-rules '{"AutomaticallyAfterDays": 30}'
```

The `AutomaticallyAfterDays` sets the rotation schedule. Every 30 days, Secrets Manager generates a new password, updates the RDS instance, and stores the new password. Your application retrieves the current password from Secrets Manager each time it connects.

**Important**: For automatic rotation to work, you need a Lambda function. AWS provides templates. In production, deploy the `SecretsManagerRDSPostgreSQLRotationSingleUser` Lambda.

---

## Step 10 - Verify Encryption at Rest

Check if your instance is encrypted:

```bash
aws rds describe-db-instances \
    --db-instance-identifier suta-pg-lab \
    --query "DBInstances[0].{Encrypted:StorageEncrypted,KmsKeyId:KmsKeyId}" \
    --output table
```

Expected output (yours will differ):

```
-------------------------------------------------------------------
|                    DescribeDBInstances                           |
+-----------+-----------------------------------------------------+
| Encrypted | KmsKeyId                                            |
+-----------+-----------------------------------------------------+
|  True     | arn:aws:kms:us-east-1:123456789012:key/abc-def-123  |
+-----------+-----------------------------------------------------+
```

The `KmsKeyId` shows which KMS key encrypts the storage. If you did not specify one during creation, RDS uses the default `aws/rds` key.

**Important**: You cannot enable encryption on an existing unencrypted instance. You must create a snapshot, copy it with encryption, and restore from the encrypted copy.

Check the KMS key details:

```bash
aws kms describe-key \
    --key-id "arn:aws:kms:us-east-1:123456789012:key/abc-def-123" \
    --query "KeyMetadata.{KeyId:KeyId,State:KeyState,Manager:KeyManager}"
```

Replace the key ARN with your actual value from the previous step.

---

## Step 11 - VPC Peering for Cross-Account Access

If you need to connect to RDS from another AWS account or VPC, use VPC peering.

Create a peering connection:

```bash
aws ec2 create-vpc-peering-connection \
    --vpc-id vpc-0your-vpc-id \
    --peer-vpc-id vpc-0other-vpc-id \
    --peer-owner-id 987654321098
```

Replace with actual VPC IDs and the other account's ID. The `--peer-owner-id` is the AWS account that owns the other VPC.

The peering must be accepted by the other account:

```bash
aws ec2 accept-vpc-peering-connection \
    --vpc-peering-connection-id pcx-0123456789abcdef0
```

Then update route tables in both VPCs to route traffic through the peering connection. Also update security groups to allow traffic from the peered VPC's CIDR range.

---

## Summary

You configured:
- SSL/TLS enforcement via `rds.force_ssl` parameter
- IAM database authentication with temporary tokens
- Security groups with least-privilege access rules
- Secrets Manager for secure credential storage and rotation
- Encryption at rest verified with KMS

Security checklist for production RDS:
- [ ] `rds.force_ssl = 1`
- [ ] No 0.0.0.0/0 in security groups
- [ ] IAM auth for applications (no hardcoded passwords)
- [ ] Secrets Manager for any password-based access
- [ ] Storage encrypted at rest
- [ ] Audit logging enabled (log_statement = ddl or all)
- [ ] No public accessibility
- [ ] Regular security group review

---

## Clean Up

```bash
aws iam detach-user-policy \
    --user-name student \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/suta-rds-iam-connect"
```

```bash
aws iam delete-policy \
    --policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/suta-rds-iam-connect"
```

```bash
aws secretsmanager delete-secret \
    --secret-id suta/rds/master-password \
    --force-delete-without-recovery
```

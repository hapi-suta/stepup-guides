# USE 01 - Provision and Connect

## Objective

Create an RDS PostgreSQL instance from scratch using the AWS CLI, connect with psql, and verify the configuration matches your specifications.

---

## Exercise

Create an RDS PostgreSQL 15 instance with these specifications:

| Setting | Value |
|---------|-------|
| Instance ID | `practice-pg-01` |
| Instance class | `db.t3.micro` |
| Engine version | 15.4 |
| Master username | `labadmin` |
| Master password | `Lab-Practice-2024!` |
| Storage | 20 GB gp3 |
| Backup retention | 7 days |
| Parameter group | Custom with `log_statement=all` |
| Encryption | Enabled |
| Public access | Disabled |

---

## Step-by-Step

### 1. Create the subnet group

Find two subnets in different AZs:

```bash
VPC_ID=$(aws ec2 describe-vpcs --query "Vpcs[0].VpcId" --output text)
```

```bash
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[*].[SubnetId,AvailabilityZone]" \
    --output table
```

Create the group using two subnets from different AZs:

```bash
aws rds create-db-subnet-group \
    --db-subnet-group-name practice-subnet-group \
    --db-subnet-group-description "Practice lab subnet group" \
    --subnet-ids "subnet-AAAA" "subnet-BBBB"
```

Replace `subnet-AAAA` and `subnet-BBBB` with your actual subnet IDs.

### 2. Create a security group

```bash
SG_ID=$(aws ec2 create-security-group --group-name practice-rds-sg --description "Practice RDS SG" --vpc-id "${VPC_ID}" --query "GroupId" --output text)
```

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)
```

```bash
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 5432 \
    --cidr "${MY_IP}/32"
```

### 3. Create a custom parameter group

```bash
aws rds create-db-parameter-group \
    --db-parameter-group-name practice-pg15-params \
    --db-parameter-group-family postgres15 \
    --description "Practice lab parameters"
```

```bash
aws rds modify-db-parameter-group \
    --db-parameter-group-name practice-pg15-params \
    --parameters "ParameterName=log_statement,ParameterValue=all,ApplyMethod=immediate"
```

### 4. Create the instance

```bash
aws rds create-db-instance \
    --db-instance-identifier practice-pg-01 \
    --db-instance-class db.t3.micro \
    --engine postgres \
    --engine-version 15.4 \
    --master-username labadmin \
    --master-user-password 'Lab-Practice-2024!' \
    --allocated-storage 20 \
    --storage-type gp3 \
    --db-subnet-group-name practice-subnet-group \
    --vpc-security-group-ids "${SG_ID}" \
    --db-parameter-group-name practice-pg15-params \
    --backup-retention-period 7 \
    --no-publicly-accessible \
    --storage-encrypted \
    --tags Key=Environment,Value=practice
```

### 5. Wait and connect

```bash
aws rds wait db-instance-available \
    --db-instance-identifier practice-pg-01
```

```bash
ENDPOINT=$(aws rds describe-db-instances --db-instance-identifier practice-pg-01 --query "DBInstances[0].Endpoint.Address" --output text)
```

```bash
psql -h "${ENDPOINT}" -U labadmin -d postgres -p 5432
```

---

## Verification Checklist

Run these checks and confirm each one passes:

### Check 1 - PostgreSQL version is 15.4

```sql
SELECT version();
```

You should see `PostgreSQL 15.4` in the output.

### Check 2 - log_statement is set to all

```sql
SHOW log_statement;
```

Expected output:

```
 log_statement
---------------
 all
(1 row)
```

### Check 3 - SSL is active

```sql
SELECT ssl, version FROM pg_stat_ssl WHERE pid = pg_backend_pid();
```

Expected output:

```
 ssl | version
-----+---------
 t   | TLSv1.3
(1 row)
```

### Check 4 - Storage is encrypted

Exit psql first:

```sql
\q
```

```bash
aws rds describe-db-instances \
    --db-instance-identifier practice-pg-01 \
    --query "DBInstances[0].StorageEncrypted" \
    --output text
```

Expected output:

```
True
```

### Check 5 - Instance is not publicly accessible

```bash
aws rds describe-db-instances \
    --db-instance-identifier practice-pg-01 \
    --query "DBInstances[0].PubliclyAccessible" \
    --output text
```

Expected output:

```
False
```

---

## Clean Up

```bash
aws rds delete-db-instance \
    --db-instance-identifier practice-pg-01 \
    --skip-final-snapshot \
    --delete-automated-backups
```

```bash
aws rds delete-db-parameter-group \
    --db-parameter-group-name practice-pg15-params
```

```bash
aws rds delete-db-subnet-group \
    --db-subnet-group-name practice-subnet-group
```

```bash
aws ec2 delete-security-group \
    --group-id "${SG_ID}"
```

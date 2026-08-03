# SURVIVE Scenario 08: Full Region Failover - Runbook

## Scenario

The primary region (us-east-1) is down. You must restore service from the DR region (us-west-2) using cross-region snapshots.

---

## Step 1: Verify DR Snapshot Availability

**On your local workstation:**

```bash
aws rds describe-db-cluster-snapshots \
  --snapshot-type manual \
  --query "DBClusterSnapshots[?contains(DBClusterSnapshotIdentifier, 'devops-lab') && Status=='available'].[DBClusterSnapshotIdentifier,SnapshotCreateTime]" \
  --output table \
  --region us-west-2
```

If the snapshot is still copying, wait:

```bash
aws rds wait db-cluster-snapshot-available \
  --db-cluster-snapshot-identifier devops-lab-cluster-dr-exercise \
  --region us-west-2
```

---

## Step 2: Create VPC Infrastructure in DR Region

You need a VPC with subnets and a DB subnet group in us-west-2. For this exercise, create a minimal setup:

**On your local workstation:**

```bash
DR_VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.1.0.0/16 \
  --query 'Vpc.VpcId' --output text --region us-west-2)
```

```bash
aws ec2 modify-vpc-attribute --vpc-id $DR_VPC_ID --enable-dns-support --region us-west-2
```

```bash
aws ec2 modify-vpc-attribute --vpc-id $DR_VPC_ID --enable-dns-hostnames --region us-west-2
```

Create two subnets in different AZs:

```bash
DR_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id $DR_VPC_ID --cidr-block 10.1.1.0/24 \
  --availability-zone us-west-2a \
  --query 'Subnet.SubnetId' --output text --region us-west-2)
```

```bash
DR_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id $DR_VPC_ID --cidr-block 10.1.2.0/24 \
  --availability-zone us-west-2b \
  --query 'Subnet.SubnetId' --output text --region us-west-2)
```

Create a DB subnet group:

```bash
aws rds create-db-subnet-group \
  --db-subnet-group-name devops-lab-dr-subnet-group \
  --db-subnet-group-description "DR subnet group for Aurora failover" \
  --subnet-ids $DR_SUBNET_1 $DR_SUBNET_2 \
  --region us-west-2
```

Create a security group:

```bash
DR_SG=$(aws ec2 create-security-group \
  --group-name devops-lab-dr-aurora-sg \
  --description "DR Aurora security group" \
  --vpc-id $DR_VPC_ID \
  --query 'GroupId' --output text --region us-west-2)
```

```bash
aws ec2 authorize-security-group-ingress \
  --group-id $DR_SG --protocol tcp --port 5432 \
  --cidr $(curl -s https://checkip.amazonaws.com)/32 \
  --region us-west-2
```

---

## Step 3: Restore Cluster from Snapshot

**On your local workstation:**

```bash
DR_KMS_KEY=$(aws kms describe-key \
  --key-id alias/devops-lab-aurora-cmk \
  --query 'KeyMetadata.Arn' --output text --region us-west-2)
```

```bash
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier devops-lab-dr-cluster \
  --snapshot-identifier devops-lab-cluster-dr-exercise \
  --engine aurora-postgresql \
  --db-subnet-group-name devops-lab-dr-subnet-group \
  --vpc-security-group-ids $DR_SG \
  --kms-key-id $DR_KMS_KEY \
  --region us-west-2
```

Wait for the cluster:

```bash
aws rds wait db-cluster-available \
  --db-cluster-identifier devops-lab-dr-cluster \
  --region us-west-2
```

---

## Step 4: Create a Writer Instance

**On your local workstation:**

```bash
aws rds create-db-instance \
  --db-instance-identifier devops-lab-dr-cluster-w1 \
  --db-cluster-identifier devops-lab-dr-cluster \
  --db-instance-class db.r6g.large \
  --engine aurora-postgresql \
  --publicly-accessible \
  --region us-west-2
```

Note: `--publicly-accessible` is used here only because we do not have a bastion in the DR VPC. In a real DR scenario, you would use a VPN or bastion.

Wait for the instance:

```bash
aws rds wait db-instance-available \
  --db-instance-identifier devops-lab-dr-cluster-w1 \
  --region us-west-2
```

---

## Step 5: Verify Data Integrity

Get the DR cluster endpoint:

```bash
DR_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-dr-cluster \
  --query 'DBClusters[0].Endpoint' --output text --region us-west-2)
```

Connect and verify:

```bash
psql "host=$DR_ENDPOINT port=5432 dbname=postgres user=dbadmin sslmode=require" \
  -c "SELECT schemaname, tablename FROM pg_tables WHERE schemaname = 'app' ORDER BY tablename;"
```

---

## Step 6: Document RPO and RTO

- **RPO:** Calculate the difference between the snapshot creation time and the simulated failure time. This is how much data was lost.
- **RTO:** Calculate the time from start of recovery to successful connection to the DR cluster. This is your recovery time.

---

## Step 7: Clean Up DR Resources

**On your local workstation:**

```bash
aws rds delete-db-instance \
  --db-instance-identifier devops-lab-dr-cluster-w1 \
  --skip-final-snapshot --region us-west-2
```

```bash
aws rds wait db-instance-deleted \
  --db-instance-identifier devops-lab-dr-cluster-w1 \
  --region us-west-2
```

```bash
aws rds delete-db-cluster \
  --db-cluster-identifier devops-lab-dr-cluster \
  --skip-final-snapshot --region us-west-2
```

```bash
aws rds delete-db-subnet-group \
  --db-subnet-group-name devops-lab-dr-subnet-group \
  --region us-west-2
```

```bash
aws ec2 delete-security-group --group-id $DR_SG --region us-west-2
```

```bash
aws ec2 delete-subnet --subnet-id $DR_SUBNET_1 --region us-west-2
```

```bash
aws ec2 delete-subnet --subnet-id $DR_SUBNET_2 --region us-west-2
```

```bash
aws ec2 delete-vpc --vpc-id $DR_VPC_ID --region us-west-2
```

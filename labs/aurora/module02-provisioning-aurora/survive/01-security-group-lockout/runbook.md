# Runbook: Security Group Lockout
## Survive Scenario 01

**What is being tested:** Your ability to diagnose and fix a network-layer connectivity failure caused by missing security group rules on an Aurora cluster.

**Why this matters:** Security group misconfigurations are the number one cause of "I can't connect to the database" tickets. In production, a misconfigured security group means zero connections - the entire application goes down. You need to diagnose this in under 5 minutes.

**Symptom:** All connections to the Aurora cluster are failing with "Connection timed out"
**Severity:** Critical - database is unreachable
**Time to resolve:** 10 to 15 minutes

---

## Your Starting Point

Someone or something removed all inbound rules from the Aurora cluster's security group. Nobody can connect to the database. The application is down.

You get this alert:
```
ALERT: Application health check failed.
Error: psql: error: connection to server at
  "devops-lab-cluster.cluster-abc123.us-east-1.rds.amazonaws.com"
  port 5432 failed: Connection timed out
```

---

## Symptoms

You will observe these symptoms:

1. `psql` connections time out (no response at all - not "connection refused", not "auth failed")
2. `nc -zv endpoint 5432` hangs and then times out
3. Application logs show connection timeout errors
4. CloudWatch metrics for DatabaseConnections drop to zero
5. The Aurora cluster itself shows status `available` in the console

The key clue: the cluster is `available` but nobody can connect. This points to a network problem, not a database problem.

---

## Diagnostic Steps

Work through these in order. Try each step before reading the hints.

### Step 1 - Confirm the Cluster Is Running

Before touching security groups, confirm the database itself is up.

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].Status" \
  --output text
```

**Hint:** If this returns `available`, the cluster is running. The problem is in the network path, not the database engine.

### Step 2 - Test Port Connectivity

Use netcat to test if port 5432 is reachable:

```bash
nc -zv YOUR_CLUSTER_ENDPOINT 5432
```

**Hint:** "Connection timed out" means packets are being dropped before reaching PostgreSQL. This is a firewall (security group) problem. "Connection refused" would mean PostgreSQL is not listening - a different problem.

### Step 3 - Find the Security Group

Find the security group ID attached to the Aurora cluster:

```bash
aws rds describe-db-clusters \
  --db-cluster-identifier devops-lab-cluster \
  --query "DBClusters[0].VpcSecurityGroups[*]" \
  --output table
```

Write down the security group ID.

### Step 4 - Inspect the Security Group Rules

Look at the inbound rules:

```bash
aws ec2 describe-security-groups \
  --group-ids YOUR_SG_ID \
  --query "SecurityGroups[0].IpPermissions" \
  --output json
```

**Hint:** If the output is `[]` (empty array), there are no inbound rules. That is your problem - no traffic is allowed in.

### Step 5 - Find Your Current IP

Before adding a rule, get your current public IP:

```bash
curl -s https://checkip.amazonaws.com
```

### Step 6 - Add the Inbound Rule

Add a rule to allow PostgreSQL (port 5432) from your IP:

```bash
aws ec2 authorize-security-group-ingress \
  --group-id YOUR_SG_ID \
  --protocol tcp \
  --port 5432 \
  --cidr YOUR_IP/32
```

No output means success.

### Step 7 - Verify the Rule Was Added

```bash
aws ec2 describe-security-groups \
  --group-ids YOUR_SG_ID \
  --query "SecurityGroups[0].IpPermissions" \
  --output json
```

You should see the new rule with `FromPort: 5432` and your CIDR.

### Step 8 - Test Port Connectivity Again

```bash
nc -zv YOUR_CLUSTER_ENDPOINT 5432
```

Expected output:
```
Connection to ... port 5432 [tcp/postgresql] succeeded!
```

### Step 9 - Connect with psql

```bash
psql -h YOUR_CLUSTER_ENDPOINT -U clusteradmin -d devopsdb -p 5432
```

Run a quick test:

```sql
SELECT 'recovered' AS status;
\q
```

---

## Resolution Approach

The fix is straightforward:
1. Identify the security group attached to the cluster
2. Add an inbound rule allowing TCP port 5432 from the required source CIDR
3. Verify connectivity with netcat and then psql

Security group changes take effect within seconds - no reboot or restart needed.

---

## Root Cause Summary

| | Detail |
|---|---|
| Root cause | All inbound rules removed from security group |
| Impact | All connections blocked. Application down. |
| How to detect | "Connection timed out" + nc test fails + SG shows empty rules |
| Fix | Add inbound TCP 5432 rule for required source CIDR |
| Time to fix | Under 5 minutes once diagnosed |

---

## Prevention

1. **AWS Config rule** - Create a custom Config rule that monitors security group changes. Alert when a security group attached to an RDS resource has its rules modified.

2. **CloudTrail** - All API calls are logged. If rules are removed, you can see who did it (the IAM user/role) and when (the timestamp). Search for `RevokeSecurityGroupIngress` events.

3. **IAM policies** - Restrict who can modify security groups in production. Use `ec2:RevokeSecurityGroupIngress` deny policies for non-admin roles.

4. **Infrastructure as Code** - If security groups are managed by Terraform or CloudFormation, any manual change will be reverted on the next apply. This prevents accidental changes from persisting.

5. **CloudWatch alarm on DatabaseConnections** - Set an alarm when connections drop to zero. This catches the symptom immediately.

---

## Interview Questions

**Q1: A developer reports "Connection timed out" when connecting to an Aurora cluster. The cluster status shows "available." What are the first three things you check?**

Strong answer: (1) Security group inbound rules - verify port 5432 is allowed from the developer's IP. (2) Network ACLs on the subnet - verify they allow inbound TCP 5432 and outbound ephemeral ports. (3) Public accessibility setting - if the developer is connecting from outside the VPC, the instance must have PubliclyAccessible=true and be in a public subnet.

**Q2: What is the difference between "Connection timed out" and "Connection refused"?**

Strong answer: "Connection timed out" means the packets never reached the server or were silently dropped. This is almost always a security group, NACL, or routing issue. "Connection refused" means the packets reached the server but nothing was listening on that port - this is a PostgreSQL configuration issue (wrong port, service not running). The distinction tells you where to look: network layer vs application layer.

**Q3: How would you prevent unauthorized security group changes in a production AWS account?**

Strong answer: Use IAM policies with explicit deny for `ec2:RevokeSecurityGroupIngress` and `ec2:AuthorizeSecurityGroupIngress` for all roles except the DBA team. Use AWS Config to detect drift. Use CloudTrail to audit all changes. Manage security groups through Infrastructure as Code so manual changes are automatically reverted.

---

## Key Terminology

| Term | Definition |
|------|-----------|
| Security Group | Virtual firewall that controls inbound and outbound traffic to AWS resources |
| Inbound Rule | A rule that allows traffic INTO the resource on a specific port from a specific source |
| CIDR | Classless Inter-Domain Routing notation for IP ranges (e.g., 10.0.0.0/24) |
| /32 | A CIDR block representing a single IP address |
| NACL | Network Access Control List - subnet-level firewall (stateless, unlike security groups) |

---

## Red Flags

These are answers that would concern an interviewer:

- "I would open port 5432 to 0.0.0.0/0 to fix it quickly" - Never open a database port to the entire internet, even temporarily
- "I would reboot the instance" - Rebooting does not fix security group issues
- "I would check pg_hba.conf" - On Aurora/RDS you do not have direct access to pg_hba.conf. Security groups are the network-layer firewall
- Not checking the cluster status first - Always confirm the cluster is running before diagnosing network issues

---

## Now Run the Validate Script

```bash
export CLUSTER_ID=devops-lab-cluster
export REGION=us-east-1
bash validate.sh
```

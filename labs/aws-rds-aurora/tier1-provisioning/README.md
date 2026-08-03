# Tier 1 - Provisioning and Connectivity
## AWS RDS and Aurora PostgreSQL

**Level:** Beginner
**Prerequisite:** Tier 0 (AWS account setup, IAM user, CLI configured)
**Total estimated time:** 4 to 5 hours

---

## What You Will Learn

By the end of this tier, you will be able to:

- Create an RDS PostgreSQL instance and an Aurora PostgreSQL cluster from scratch
- Choose the right instance class and storage type for a given workload
- Understand how endpoints work and how to connect securely
- Troubleshoot the most common connectivity problems
- Connect to your database from psql, pgAdmin, and Python

---

## Topics in This Tier

| # | Topic | Concepts | Build Guide | Time |
|---|-------|----------|-------------|------|
| T1.1 | Creating an RDS PostgreSQL instance | [provisioning.md](concepts/provisioning.md) | [01-create-rds-instance.md](build/01-create-rds-instance.md) | 45 min |
| T1.2 | Instance classes and storage types | [provisioning.md](concepts/provisioning.md) | [02-instance-classes-storage.md](build/02-instance-classes-storage.md) | 30 min |
| T1.3 | Creating an Aurora PostgreSQL cluster | [provisioning.md](concepts/provisioning.md) | [03-create-aurora-cluster.md](build/03-create-aurora-cluster.md) | 50 min |
| T1.4 | Connectivity deep dive | [provisioning.md](concepts/provisioning.md) | [04-connectivity-deep-dive.md](build/04-connectivity-deep-dive.md) | 35 min |
| T1.5 | Connecting clients | [provisioning.md](concepts/provisioning.md) | [05-connecting-clients.md](build/05-connecting-clients.md) | 30 min |

---

## Lab Structure

```
tier1-provisioning/
├── README.md               <- You are here
├── concepts/
│   └── provisioning.md     <- Read this first. All background knowledge.
├── build/
│   ├── 01-create-rds-instance.md
│   ├── 02-instance-classes-storage.md
│   ├── 03-create-aurora-cluster.md
│   ├── 04-connectivity-deep-dive.md
│   └── 05-connecting-clients.md
├── use/
│   ├── 01-provision-from-scratch.md
│   ├── 02-instance-right-sizing.md
│   ├── 03-aurora-cluster-setup.md
│   ├── 04-connectivity-troubleshooting.md
│   └── 05-client-connection-patterns.md
├── survive/
│   ├── config.sh
│   ├── lib/common.sh
│   ├── 01-security-group-lockout/
│   ├── 02-wrong-endpoint/
│   ├── 03-instance-stopped/
│   └── 04-storage-full/
└── interview/
    └── tier1-interview-questions.md
```

---

## How to Use This Lab

### Step 1 - Read the concepts first
Open `concepts/provisioning.md` and read it top to bottom. Do not skip it. It explains every term used in the build guides.

### Step 2 - Follow the build guides in order
Each build guide walks you through a task step by step. Do them in order (01 before 02, etc.).

### Step 3 - Do the use exercises
The use exercises have requirements but no step-by-step help. You figure it out using what you learned in the build guides.

### Step 4 - Try the survive scenarios
These simulate real outages. An inject script breaks something. You diagnose and fix it using the runbook. A validate script confirms your fix.

### Step 5 - Study the interview questions
These are the questions interviewers actually ask. Review them before any AWS database interview.

---

## Prerequisites Checklist

Before starting Tier 1, confirm you have completed all of Tier 0:

- [ ] AWS account created and billing alerts configured
- [ ] IAM user created with AdministratorAccess (for training - tighten this in production)
- [ ] AWS CLI v2 installed and configured (`aws configure` ran successfully)
- [ ] Default VPC exists in your chosen region (check: AWS Console > VPC > Your VPCs)
- [ ] `psql` installed on your local machine
- [ ] pgAdmin 4 installed on your local machine

If any item above is not checked, go back to Tier 0 before continuing.

---

## Cost Estimate

Running all labs in this tier for one day costs approximately:

| Resource | Instance Type | Approx Daily Cost |
|----------|--------------|-------------------|
| RDS PostgreSQL | db.t3.micro | $0.02 - $0.04 |
| Aurora PostgreSQL | db.t3.medium (writer + reader) | $0.10 - $0.20 |
| Storage | 20 GB gp3 | < $0.01 |

**Total: less than $1 per day.**

Always stop or delete instances when you are done for the day. The survive labs use a `db.t3.micro` which qualifies for the AWS free tier (750 hours/month for the first 12 months).

---

## Getting Help

If a command fails, check these things first:

1. Is your AWS CLI configured? Run: `aws sts get-caller-identity`
2. Are you in the right region? Check the top-right corner of the AWS Console.
3. Did the resource finish creating? RDS takes 5 to 10 minutes to become available.
4. Is your security group allowing inbound traffic on port 5432?

If you are still stuck, re-read the concepts doc for the topic and try the connectivity troubleshooting guide (Build 04).

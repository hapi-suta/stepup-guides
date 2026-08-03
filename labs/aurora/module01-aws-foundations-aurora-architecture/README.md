# Module 01: AWS Foundations and Aurora Architecture

**Track:** DevOps DBA Training
**Duration:** ~12 hours
**Week:** 1
**Prerequisites:** None - this module starts from zero

---

## What You Will Learn

This module builds your foundation. By the end, you will:

- Understand what managed databases are and why they exist
- Know how Aurora PostgreSQL works under the hood (storage layer, compute separation, endpoints)
- Have a working AWS account with CLI access
- Have a VPC ready to host your first Aurora cluster
- Know basic SQL and psql
- Understand the DevOps DBA role and what makes it different from a traditional DBA
- Know how to track and estimate AWS costs

---

## Module Contents

### Concepts (read first)
1. [Cloud Databases and AWS](concepts/01-cloud-databases-and-aws.md) - What managed databases are, shared responsibility, AWS services overview
2. [Aurora Architecture Deep Dive](concepts/02-aurora-architecture-deep-dive.md) - Storage layer, 6-copy replication, endpoints, compute vs storage
3. [The DevOps DBA Role](concepts/03-devops-dba-role.md) - Career evolution, IaC mindset, skills roadmap, job market

### BUILD (hands-on, follow step by step)
1. [AWS Account Setup](build/01-aws-account-setup.md) - IAM user, CLI, credentials (30 min)
2. [VPC Networking Basics](build/02-vpc-networking-basics.md) - VPC, subnets, security groups (45 min)
3. [RDS vs Aurora Comparison](build/03-rds-vs-aurora-comparison.md) - Side-by-side analysis (20 min)
4. [PostgreSQL Refresher](build/04-postgresql-refresher.md) - SQL basics, psql, data types (45 min)
5. [Cost Awareness](build/05-cost-awareness.md) - Pricing, budgets, cost alerts (20 min)

### USE (practice with less hand-holding)
1. [AWS Architecture Quiz](use/01-aws-architecture-quiz.md)
2. [Shared Responsibility Exercise](use/02-shared-responsibility-exercise.md)
3. [VPC Diagram Exercise](use/03-vpc-diagram-exercise.md)
4. [SQL Fundamentals Practice](use/04-sql-fundamentals-practice.md)
5. [Cost Estimation Exercise](use/05-cost-estimation-exercise.md)

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## No SURVIVE Scenarios

This module is foundational - there is no infrastructure to break yet. SURVIVE scenarios begin in Module 02 when you have a running Aurora cluster.

---

## What is Next

After completing this module, you will move to [Module 02: Provisioning Aurora](../module02-provisioning-aurora/) where you create your first Aurora PostgreSQL cluster using both the AWS Console and CLI.

---

## Cost Warning

This module creates a VPC and networking resources (BUILD 02). VPCs themselves are free. The security groups and subnets are free. No database instances are created in this module, so your AWS costs should be $0.

The PostgreSQL refresher (BUILD 04) uses a free online sandbox or local Docker - no AWS charges.

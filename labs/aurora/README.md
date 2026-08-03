# DevOps DBA Training Track - AWS Aurora PostgreSQL

**Methodology:** CBUSI (Concepts, BUILD, USE, SURVIVE, Interview)
**Duration:** 8 weeks at 2 hours/day (~112 hours total)
**Engine:** AWS Aurora PostgreSQL 16
**Stack:** Aurora + Terraform + GitHub Actions + CloudWatch + Prometheus

---

## Track Overview

This track transforms you into a DevOps DBA - someone who operates databases using infrastructure as code, CI/CD pipelines, proactive monitoring, and SRE practices. By the end, you will have built a complete, production-ready Aurora PostgreSQL stack from scratch.

---

## Modules

| # | Module | Week | BUILD | USE | SURVIVE | Focus |
|---|--------|------|-------|-----|---------|-------|
| 01 | [AWS Foundations and Aurora Architecture](module01-aws-foundations-aurora-architecture/) | 1 | 5 | 5 | 0 | Foundation |
| 02 | [Provisioning Aurora](module02-provisioning-aurora/) | 1 | 6 | 5 | 4 | Hands-on |
| 03 | [Terraform for Database Infrastructure](module03-terraform-for-databases/) | 2 | 6 | 5 | 3 | IaC |
| 04 | [Aurora Security and IAM](module04-aurora-security-iam/) | 2-3 | 6 | 5 | 4 | Security |
| 05 | [HA, Replication and Failover](module05-ha-replication-failover/) | 3-4 | 7 | 5 | 5 | Availability |
| 06 | [Backup, Recovery and Lifecycle](module06-backup-recovery-lifecycle/) | 4 | 6 | 5 | 5 | Data protection |
| 07 | [Performance, Monitoring and Observability](module07-performance-monitoring-observability/) | 5 | 8 | 6 | 6 | Observability |
| 08 | [CI/CD for Database Changes](module08-cicd-for-database-changes/) | 6 | 6 | 5 | 3 | Automation |
| 09 | [Operations at Scale and SRE](module09-operations-at-scale-sre/) | 7 | 6 | 5 | 4 | Operations |
| 10 | [Capstone: Production-Ready Aurora Stack](module10-capstone-production-ready-aurora/) | 8 | 8 | 4 | 8 | Integration |

**Totals:** ~58 BUILD guides, ~50 USE exercises, ~42 SURVIVE scenarios, 10 concepts docs, 10 interview preps

---

## How to Use This Track

### Learning Flow (per module)

1. **Read Concepts** - understand the theory and mental models
2. **Follow BUILD guides** - hands-on, step-by-step instructions
3. **Do USE exercises** - practice with less hand-holding
4. **Face SURVIVE scenarios** - chaos engineering: something breaks, you fix it
5. **Review Interview prep** - prepare for real job interviews

### Cloud-Native Context

This is a cloud-native track. Aurora is fully managed - there is no SSH to database servers. Commands run in three contexts:

- **In your terminal** - AWS CLI, Terraform, psql from your local machine
- **In the AWS Console** - web interface for visual configuration
- **In psql** - connected to Aurora via endpoint

### Cost Management

Aurora charges per hour. A minimal lab setup costs approximately $0.14/hour (writer + reader). Always clean up resources after each lab session. Each module includes cleanup instructions.

Estimated total cost for the full track: $20-40 if you clean up consistently.

---

## Prerequisites

- A computer (Mac, Windows, or Linux)
- An AWS account (Module 01 walks you through setup)
- No prior database experience required
- No prior AWS experience required
- Basic comfort with a terminal/command line (helpful but not required)

---

## What You Will Be Able To Do After This Track

- Provision and manage Aurora PostgreSQL clusters via Console, CLI, and Terraform
- Secure databases with IAM, SSL, Secrets Manager, and least-privilege access
- Configure high availability with Multi-AZ, auto-scaling, and global databases
- Implement backup strategies with PITR, cross-region snapshots, and blue-green upgrades
- Monitor with CloudWatch, Performance Insights, and Prometheus/Grafana
- Build CI/CD pipelines for schema migrations with GitHub Actions
- Apply SRE practices: SLOs, error budgets, cost optimization, incident management
- Survive 42 production chaos scenarios and know how to respond to each one
- Pass DevOps DBA job interviews with confidence

---

## Certification Alignment

This track prepares you for:
- **AWS Solutions Architect Associate** - VPC, IAM, security concepts
- **AWS Database Specialty** - Aurora deep dive, backup, HA, performance
- **Terraform Associate** - IaC fundamentals, modules, state management

---

## Status

| Module | Concepts | BUILD | USE | SURVIVE | Interview |
|--------|----------|-------|-----|---------|-----------|
| 01 | Done | Done | Done | N/A | Done |
| 02 | In progress | In progress | In progress | In progress | In progress |
| 03 | In progress | In progress | In progress | In progress | In progress |
| 04 | In progress | In progress | In progress | In progress | In progress |
| 05 | In progress | In progress | In progress | In progress | In progress |
| 06 | In progress | In progress | In progress | In progress | In progress |
| 07 | In progress | In progress | In progress | In progress | In progress |
| 08 | In progress | In progress | In progress | In progress | In progress |
| 09 | In progress | In progress | In progress | In progress | In progress |
| 10 | In progress | In progress | In progress | In progress | In progress |

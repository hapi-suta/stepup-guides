# Module 10: Capstone - Production-Ready Aurora Stack

**Track:** DevOps DBA Training
**Duration:** ~16 hours
**Week:** 8
**Prerequisites:** All previous modules (01-09)

---

## What You Will Learn

This is the final module - you build and operate a complete production-grade Aurora stack. By the end, you will:

- Design a production architecture that meets availability, security, and performance requirements
- Deploy the full stack using Terraform - VPC, Aurora cluster, Proxy, monitoring, automation
- Implement every security layer from Module 04 in a single cohesive deployment
- Validate your setup against a production readiness checklist
- Survive eight chaos scenarios that simulate real production incidents
- Write operations runbooks that your team can use on day one
- Walk away with a portfolio-ready project that proves your DevOps DBA skills

---

## Module Contents

### Concepts (read first)
1. [Production Readiness Checklist](concepts/01-production-readiness-checklist.md) - What "production ready" means - security, HA, backup, monitoring, automation, documentation

### BUILD (hands-on, follow step by step)
1. [Architecture Design](build/01-architecture-design.md) - Requirements gathering, architecture diagram, component selection (45 min)
2. [Network Foundation](build/02-network-foundation.md) - Multi-AZ VPC, private subnets, security groups via Terraform (45 min)
3. [Aurora Cluster Deployment](build/03-aurora-cluster-deployment.md) - Writer, readers, Serverless v2 via Terraform (45 min)
4. [Security Hardening](build/04-security-hardening.md) - SSL enforcement, IAM auth, Secrets Manager, RBAC, audit logging (60 min)
5. [Monitoring Stack](build/05-monitoring-stack.md) - Performance Insights, CloudWatch dashboards, alarms, SNS (45 min)
6. [Backup and Recovery](build/06-backup-and-recovery.md) - Retention policy, snapshot schedule, PITR verification (30 min)
7. [CI/CD Pipeline](build/07-cicd-pipeline.md) - GitHub Actions with Terraform and Flyway, approval gates (45 min)
8. [Chaos Testing](build/08-chaos-testing.md) - Inject failures, validate recovery, measure against SLOs (60 min)

### USE (practice with less hand-holding)
1. [Architecture Review](use/01-architecture-review.md)
2. [Security Assessment](use/02-security-assessment.md)
3. [Performance Validation](use/03-performance-validation.md)
4. [Operations Runbook](use/04-operations-runbook.md)

### SURVIVE (the gauntlet - eight scenarios back to back)
1. [Writer Instance Failure](survive/01-writer-instance-failure/) - Primary goes down, verify failover and recovery
2. [Security Breach Detected](survive/02-security-breach-detected/) - Suspicious queries in audit log, investigate and lock down
3. [Backup Recovery Under Pressure](survive/03-backup-recovery-under-pressure/) - Critical table dropped, restore with deadline
4. [Performance Degradation](survive/04-performance-degradation/) - Response times spike, diagnose root cause
5. [Pipeline Breaks Production](survive/05-pipeline-breaks-production/) - Bad migration deployed, rollback and recover
6. [Cost Budget Exceeded](survive/06-cost-budget-exceeded/) - Spending exceeds budget, find and fix the cause
7. [Connection Pool Exhaustion](survive/07-connection-pool-exhaustion/) - All connections consumed, restore service
8. [Full Region Failover](survive/08-full-region-failover/) - Simulate region failure, failover to Global Database secondary

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

You have completed the DevOps DBA Training Track. You now have the skills to manage Aurora PostgreSQL in production - from provisioning to security to incident response. The stack you built in this capstone serves as both a reference architecture and a portfolio project.

---

## Cost Warning

The full stack runs at approximately $0.30-0.50 per hour depending on instance sizes and reader count. Budget $5-10 for the entire capstone testing period. Tear down all resources when finished - the Terraform destroy command is included at the end of BUILD 08.

# Module 10 - Build Guide 01: Architecture Design

**Objective:** Design a production-ready Aurora PostgreSQL stack on paper before writing any code. Create an architecture decision document covering networking, compute, storage, security, HA, monitoring, CI/CD, and disaster recovery.
**Time:** 45 minutes
**Level:** Senior / Staff
**Prerequisites:** Completed Modules 1-9. Read the Production Readiness Checklist (Concepts 01).

---

## Why Design First

Jumping into Terraform without a design leads to rework. You make decisions implicitly - subnet CIDR ranges, instance sizing, parameter group settings - and discover conflicts when it is too late to change cheaply. A design document forces you to make every decision explicitly, get them reviewed, and create a reference for everyone who will operate this stack.

This guide walks you through each design decision. By the end, you will have a complete architecture document that serves as the blueprint for Build Guides 02-08.

---

## 1. Define the Requirements

Before designing anything, document what the stack needs to support.

Create a file called `architecture-decision-document.md` in your project directory. Start with the requirements section.

**On your local workstation:**

```bash
mkdir -p ~/capstone-aurora
```

```bash
vi ~/capstone-aurora/architecture-decision-document.md
```

Add this requirements template and fill in the values:

```markdown
# Architecture Decision Document: devops-lab-cluster

## 1. Requirements

### Business Requirements
- Application: [DESCRIBE THE APPLICATION]
- Expected users: [NUMBER]
- Availability target: 99.95% (approximately 4.4 hours downtime per year)
- Data classification: Confidential
- Compliance: SOC 2 Type II

### Technical Requirements
- Database engine: Aurora PostgreSQL 16.x
- Peak connections: 200
- Storage estimate (year 1): 100 GB
- Storage growth rate: 10 GB/month
- Read/write ratio: 80/20 (read-heavy)
- Peak transactions per second: 500
- Largest table: 50 million rows
- Recovery Point Objective (RPO): 5 minutes
- Recovery Time Objective (RTO): 30 minutes (same-region), 4 hours (cross-region)
```

---

## 2. Network Architecture

### VPC Design

The VPC is the foundation of your network isolation. Every decision here affects security, availability, and cost.

Add this section to your architecture document:

```markdown
## 2. Network Architecture

### VPC
- CIDR: 10.0.0.0/16 (65,536 addresses)
- Region: us-east-1
- DNS hostnames: enabled
- DNS resolution: enabled

### Subnets
| Subnet | CIDR | AZ | Type | Purpose |
|--------|------|----|------|---------|
| public-1 | 10.0.1.0/24 | us-east-1a | Public | NAT Gateway, bastion host |
| public-2 | 10.0.2.0/24 | us-east-1b | Public | NAT Gateway (HA) |
| private-app-1 | 10.0.11.0/24 | us-east-1a | Private | Application servers |
| private-app-2 | 10.0.12.0/24 | us-east-1b | Private | Application servers |
| private-db-1 | 10.0.21.0/24 | us-east-1a | Private | Aurora instances |
| private-db-2 | 10.0.22.0/24 | us-east-1b | Private | Aurora instances |
| private-db-3 | 10.0.23.0/24 | us-east-1c | Private | Aurora instances (future) |

### Route Tables
- Public subnets: 0.0.0.0/0 -> Internet Gateway
- Private app subnets: 0.0.0.0/0 -> NAT Gateway
- Private DB subnets: No internet route (fully isolated)

### Design Decisions
- Three DB subnets across three AZs for maximum HA flexibility
- DB subnets have NO internet route - updates come via VPC endpoints
- Application subnets route through NAT for outbound (dependency downloads, etc.)
- /24 subnets provide 251 usable IPs each - sufficient for this workload
```

### Why Three AZs for Database Subnets

Aurora can place instances in any AZ that has a subnet in the DB subnet group. With three AZs, you have three failure domains. If AZ-a goes down, Aurora can failover to AZ-b or AZ-c. With only two AZs, you have a single failover target.

### VPC Endpoints

Add VPC endpoints so the database subnet (which has no internet route) can reach AWS services:

```markdown
### VPC Endpoints
| Service | Type | Purpose |
|---------|------|---------|
| s3 | Gateway | Snapshot exports, S3 imports |
| secretsmanager | Interface | Master password retrieval |
| monitoring | Interface | Enhanced Monitoring data |
| logs | Interface | CloudWatch Logs export |
| kms | Interface | KMS key operations |
| rds | Interface | RDS API calls from private subnets |
```

---

## 3. Security Architecture

### Security Groups

Design security groups with the principle of least privilege - each group allows only the minimum traffic required.

```markdown
## 3. Security Architecture

### Security Groups
| SG Name | Inbound Rules | Outbound Rules | Attached To |
|---------|---------------|----------------|-------------|
| sg-bastion | SSH (22) from admin CIDR | All traffic | Bastion host |
| sg-app | HTTPS (443) from ALB SG | All traffic | App servers |
| sg-aurora | PostgreSQL (5432) from sg-app | None | Aurora cluster |
| sg-aurora | PostgreSQL (5432) from sg-bastion | None | Aurora cluster |

### Design Decisions
- Aurora SG allows inbound ONLY from app SG and bastion SG
- Aurora SG has NO outbound rules - database does not initiate connections
- No CIDR-based rules on Aurora SG - only security group references
- Bastion host is the only SSH entry point

### Encryption
- At rest: AWS KMS (customer-managed key, alias: aurora-capstone-cmk)
- In transit: TLS enforced via rds.force_ssl = 1
- KMS key rotation: enabled (annual automatic rotation)
- KMS key policy: restricted to RDS service and admin IAM role

### Authentication
- Master user: managed by Secrets Manager with 30-day rotation
- Application user: IAM database authentication
- Admin user: IAM database authentication with MFA-gated IAM role
- No direct master user access from applications

### Audit
- pgaudit.log = ddl,role,write
- CloudTrail: all RDS API calls logged
- PostgreSQL logs: exported to CloudWatch Logs
- Log retention: 90 days in CloudWatch, archived to S3 after
```

---

## 4. Compute Architecture

### Instance Sizing

Size your instances based on the requirements defined in Section 1.

```markdown
## 4. Compute Architecture

### Instance Sizing Analysis
| Metric | Requirement | Instance Equivalent |
|--------|-------------|-------------------|
| Peak connections: 200 | max_connections ~ 250 | db.r6g.large supports 1,000+ |
| Peak TPS: 500 | CPU headroom needed | db.r6g.large (2 vCPU, 16 GB RAM) |
| Working set: ~20 GB | Buffer cache > working set | 16 GB RAM sufficient initially |
| Storage: 100 GB year 1 | Aurora auto-grows | No action needed |

### Selected Configuration
| Role | Instance ID | Instance Class | AZ | Purpose |
|------|------------|----------------|----|---------|
| Writer | devops-lab-cluster-w1 | db.r6g.large | us-east-1a | Primary write endpoint |
| Reader | devops-lab-cluster-r1 | db.r6g.large | us-east-1b | Read scaling, failover target |

### Design Decisions
- Writer and reader use the same instance class (critical for failover)
- db.r6g.large chosen: Graviton (cost-efficient), 16 GB RAM exceeds working set
- Start with one reader; add more based on read load metrics
- Failover priority: reader-r1 at tier 0 (highest priority)
- Future: add Serverless v2 reader for variable analytics workload

### Parameter Group
- Name: devops-lab-cluster-params
- Family: aurora-postgresql16
- Key settings:
  - shared_preload_libraries: pg_stat_statements,pgaudit
  - rds.force_ssl: 1
  - log_min_duration_statement: 1000
  - log_connections: 1
  - log_disconnections: 1
  - log_lock_waits: 1
  - log_temp_files: 0
  - pgaudit.log: ddl,role,write
  - idle_in_transaction_session_timeout: 300000
  - statement_timeout: 60000
```

---

## 5. Storage Architecture

```markdown
## 5. Storage Architecture

### Aurora Storage
- Type: Aurora Standard (evaluate I/O-Optimized after 30 days of metrics)
- Initial size: auto-allocated by Aurora
- Maximum: Aurora supports up to 128 TB
- Growth rate: estimated 10 GB/month

### Design Decisions
- Start with Aurora Standard storage
- After 30 days, check I/O charges in Cost Explorer
- If I/O charges > 25% of total Aurora spend, switch to I/O-Optimized
- Storage type change has zero downtime

### Backup Storage
- Automated backup retention: 14 days
- Manual snapshots: before every major change
- Cross-region snapshot copy: us-west-2 (daily)
- Snapshot encryption: same CMK (multi-region key)
```

---

## 6. High Availability Architecture

```markdown
## 6. High Availability Architecture

### Failover Design
- Failover target: devops-lab-cluster-r1 (tier 0)
- Expected failover time: 30-60 seconds
- DNS TTL: 5 seconds (Aurora default)
- Cluster endpoint auto-updates on failover

### Failure Scenarios
| Scenario | Detection | Recovery | RTO |
|----------|-----------|----------|-----|
| Writer instance crash | Aurora automatic detection | Promote reader r1 | < 60 seconds |
| AZ-a outage | Aurora automatic detection | Promote reader r1 (in AZ-b) | < 60 seconds |
| Storage failure | Aurora automatic (6-way replication) | Transparent to application | 0 seconds |
| Region outage | CloudWatch alarm + manual | Restore from cross-region snapshot | 2-4 hours |

### Application Requirements
- Use cluster endpoint for writes (not instance endpoint)
- Use reader endpoint for reads
- Connection timeout: 5 seconds
- Retry on connection failure: 3 attempts with exponential backoff
- DNS TTL in application: 5 seconds or less

### Maintenance Strategy
- Maintenance window: Sunday 03:00-04:00 UTC
- Backup window: 02:00-03:00 UTC (before maintenance)
- Minor version upgrades: automatic
- Major version upgrades: manual, during planned maintenance
```

---

## 7. Monitoring Architecture

```markdown
## 7. Monitoring Architecture

### CloudWatch Metrics and Alarms
| Metric | Threshold | Period | Action |
|--------|-----------|--------|--------|
| CPUUtilization | > 80% for 5 min | 60s | SNS -> PagerDuty |
| DatabaseConnections | > 200 for 5 min | 60s | SNS -> Slack |
| FreeableMemory | < 500 MB for 5 min | 60s | SNS -> PagerDuty |
| AuroraReplicaLag | > 30000 ms for 5 min | 60s | SNS -> PagerDuty |
| ReadLatency | > 20 ms for 10 min | 60s | SNS -> Slack |
| WriteLatency | > 20 ms for 10 min | 60s | SNS -> Slack |
| Deadlocks | > 0 for 5 min | 300s | SNS -> Slack |

### Performance Insights
- Enabled on all instances
- Retention: 7 days (free tier)
- Key metrics: db.load by wait type

### Enhanced Monitoring
- Interval: 60 seconds
- OS metrics: CPU by process, memory breakdown, swap

### Log Metric Filters
| Filter | Pattern | Metric Name |
|--------|---------|-------------|
| Deadlocks | "deadlock detected" | DeadlockCount |
| Auth failures | "authentication failed" | AuthFailureCount |
| Temp files | "temporary file" | TempFileCount |
| Wraparound | "transaction ID wraparound" | WraparoundWarningCount |

### Dashboard
- Name: devops-lab-aurora-dashboard
- Widgets: CPU, connections, latency, memory, replica lag, custom metrics, alarm status
```

---

## 8. CI/CD Architecture

```markdown
## 8. CI/CD Architecture

### Schema Migration Pipeline
- Tool: Flyway (version-controlled SQL migrations)
- Repository: GitHub (private)
- Pipeline: GitHub Actions
- Environments: staging -> production
- Approval gate: manual approval for production

### Pipeline Flow
1. Developer creates migration file (V001__create_users.sql)
2. PR triggers: lint SQL, dry-run against staging
3. Merge to main: auto-apply to staging
4. Manual approval: apply to production
5. Post-deploy: validate migration, run smoke tests

### Rollback Strategy
- Every migration has a corresponding undo file (U001__drop_users.sql)
- Rollback is a new migration, not a state revert
- Failed migrations trigger automatic Slack notification
- Lock timeout: 5 seconds (prevents long locks during migration)

### Design Decisions
- Flyway over Liquibase: simpler, SQL-native, no XML
- No ORM migrations: raw SQL gives DBA full control
- Lock timeout prevents DDL from blocking production queries
- Staging cluster mirrors production configuration
```

---

## 9. Disaster Recovery Architecture

```markdown
## 9. Disaster Recovery Architecture

### DR Strategy: Cross-Region Snapshot Restore
- Primary region: us-east-1
- DR region: us-west-2
- Snapshot frequency: daily automated + pre-change manual
- Cross-region copy: automated daily
- KMS key: multi-region key available in both regions

### DR Procedure
1. Detect region failure (CloudWatch cross-region alarm)
2. Identify latest available snapshot in us-west-2
3. Restore cluster from snapshot in us-west-2
4. Update application DNS (Route 53 failover record)
5. Verify data integrity
6. Notify stakeholders

### RPO/RTO Targets
| Scenario | RPO | RTO |
|----------|-----|-----|
| Single AZ failure | 0 (synchronous replication) | < 60 seconds |
| Single instance failure | 0 | < 60 seconds |
| Region failure | Up to 24 hours (last snapshot) | 2-4 hours |
| Data corruption (human error) | 5 minutes (PITR) | 30-60 minutes |

### DR Testing Schedule
- Quarterly: full DR drill (restore in us-west-2, connect application)
- Monthly: verify cross-region snapshots exist and are restorable
- Weekly: verify automated backups are completing
```

---

## 10. Cost Estimate

```markdown
## 10. Cost Estimate

### Monthly Cost Breakdown (us-east-1, On-Demand)
| Resource | Specification | Monthly Cost |
|----------|--------------|-------------|
| Writer instance | db.r6g.large | $175 |
| Reader instance | db.r6g.large | $175 |
| Aurora storage | 100 GB Standard | $10 |
| Aurora I/O | Estimated 500M requests | $100 |
| Backup storage | 14 days retention, 100 GB | $2 |
| Cross-region snapshots | 100 GB in us-west-2 | $2 |
| CloudWatch | Dashboards, alarms, logs | $15 |
| Performance Insights | Free tier (7-day retention) | $0 |
| Enhanced Monitoring | Included | $0 |
| VPC endpoints | 6 interface endpoints | $45 |
| NAT Gateway | 2 (HA) | $65 |
| KMS | 1 CMK + API calls | $1 |
| Secrets Manager | 1 secret + rotation | $1 |
| **Total (On-Demand)** | | **~$591** |

### Cost Optimization Opportunities
| Optimization | Savings | Action |
|-------------|---------|--------|
| 1-year RI (All Upfront) | ~37% on compute | Purchase after stable baseline |
| I/O-Optimized storage | 20-40% if I/O-heavy | Evaluate after 30 days |
| Reduce VPC endpoints | ~$30/month | Use gateway endpoints where possible |
| Single NAT Gateway | ~$32/month | Accept reduced HA for cost savings |
```

---

## 11. Architecture Diagram

Document the architecture as a text-based diagram in your decision document:

```markdown
## 11. Architecture Diagram

```
                          Internet
                             |
                       [Internet Gateway]
                             |
                 +-----------+-----------+
                 |                       |
          [Public Subnet 1a]     [Public Subnet 1b]
          [NAT Gateway]          [NAT Gateway]
          [Bastion Host]
                 |                       |
          [Private App 1a]       [Private App 1b]
          [App Server]           [App Server]
                 |                       |
          [Private DB 1a]        [Private DB 1b]        [Private DB 1c]
          [Aurora Writer]        [Aurora Reader]         [Future Reader]
                 |                       |                      |
                 +------- Aurora Shared Storage ---------------+
                          (6-way replication across 3 AZs)
```
```

---

## 12. Review Checklist

Before proceeding to Build Guide 02, verify your architecture document covers:

- [ ] Requirements with specific numbers (connections, TPS, storage)
- [ ] VPC with at least 3 AZs for database subnets
- [ ] Security groups with least-privilege rules
- [ ] Encryption at rest and in transit
- [ ] IAM authentication strategy
- [ ] Instance sizing with justification
- [ ] Parameter group settings
- [ ] Failover design with RTO for each scenario
- [ ] Monitoring with specific alarm thresholds
- [ ] CI/CD pipeline for schema migrations
- [ ] DR strategy with RPO/RTO targets
- [ ] Cost estimate with optimization opportunities
- [ ] Architecture diagram

If any section is incomplete, fill it in now. This document is the blueprint for everything you build in Guides 02-08.

---

## Summary

You now have a complete architecture decision document for a production Aurora PostgreSQL stack. This document serves three purposes:

1. **Blueprint** - Guides the Terraform implementation in Build Guides 02-03
2. **Reference** - On-call engineers can quickly understand the architecture
3. **Audit trail** - Documents why each decision was made

The design covers all seven categories from the Production Readiness Checklist: security, HA, backup/DR, monitoring, cost, compliance, and operational maturity.

**Next:** [Build 02 - Terraform Foundation](./02-terraform-foundation.md)

# Capstone Project: Production Aurora PostgreSQL Environment

## Scenario

You are the lead DBA at [COMPANY]. The engineering team is launching a new product next month. Your job: build a production-ready Aurora PostgreSQL environment from scratch.

This capstone ties together everything from Tiers 0-8 into a single deliverable. You will provision, secure, configure, make highly available, monitor, scale, and operationalize an Aurora PostgreSQL cluster.

## Time Estimate

3-4 hours (can be split across multiple sessions)

## Cost Estimate

~$5-8 for a single session. See [COST-GUIDE.md](../COST-GUIDE.md) for details. Delete your cluster immediately after grading.

## Prerequisites

- Completed at least T0-T3 BUILD guides
- AWS CLI v2 configured with admin permissions
- Familiarity with Aurora (T4+ BUILD guides recommended but not required)

## Phases

| Phase | Topic | Tiers Referenced |
|-------|-------|-----------------|
| 1 | [Provision](phase1-provision.md) | T0-T1 |
| 2 | [Secure](phase2-secure.md) | T2 |
| 3 | [Configure](phase3-configure.md) | T3 |
| 4 | [High Availability](phase4-ha.md) | T4-T5 |
| 5 | [Monitor](phase5-monitor.md) | T6 |
| 6 | [Scale](phase6-scale.md) | T7 |
| 7 | [Operate](phase7-operate.md) | T8 |

## Grading

Run the automated scoring script after completing all phases:

```bash
export CAPSTONE_CLUSTER_ID="your-cluster-id"
export AWS_REGION="us-east-1"
bash validate.sh
```

The script runs 20 checks, each worth 5 points:

| Score | Grade |
|-------|-------|
| 100 | Master - production-ready environment |
| 80-95 | Advanced - minor gaps to address |
| 60-75 | Intermediate - review failed checks and fix |
| Below 60 | Needs work - revisit the relevant BUILD guides |

## Grading Rubric

### Provision (15 points)
- Cluster exists and is available (5)
- Writer instance is available (5)
- Correct engine version (PostgreSQL 16.x) (5)

### Security (20 points)
- Storage encryption enabled (5)
- SSL/TLS enforced via parameter group (5)
- No public access on any instance (5)
- IAM authentication enabled (5)

### Configuration (10 points)
- pg_stat_statements loaded in shared_preload_libraries (5)
- Custom cluster parameter group attached (not default) (5)

### High Availability (15 points)
- Multi-AZ (reader in different AZ than writer) (5)
- Automated backups enabled (5)
- Backup retention >= 7 days (5)

### Monitoring (15 points)
- Performance Insights enabled (5)
- At least one CloudWatch alarm exists for the cluster (5)
- Enhanced Monitoring enabled (5)

### Scale (10 points)
- At least 1 reader replica exists (5)
- Reader endpoint resolves (5)

### Operations (15 points)
- pgaudit extension installed (5)
- Audit logging configured (5)
- PostgreSQL logs exported to CloudWatch Logs (5)

## Cleanup

After grading, delete everything:

```bash
# Delete reader instances first
aws rds delete-db-instance --db-instance-identifier ${CAPSTONE_CLUSTER_ID}-reader-1

# Delete writer instance
aws rds delete-db-instance --db-instance-identifier ${CAPSTONE_CLUSTER_ID}-writer-1

# Delete the cluster
aws rds delete-db-cluster \
  --db-cluster-identifier ${CAPSTONE_CLUSTER_ID} \
  --skip-final-snapshot

# Delete CloudWatch alarms
aws cloudwatch delete-alarms --alarm-names capstone-cpu-alarm

# Delete custom parameter groups (after cluster is gone)
aws rds delete-db-cluster-parameter-group \
  --db-cluster-parameter-group-name capstone-aurora-pg16
```

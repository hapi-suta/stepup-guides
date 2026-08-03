# Tier 6 - Performance and Monitoring

**Level:** Advanced
**Prerequisites:** Tier 0-5 completed. Working RDS PostgreSQL or Aurora PostgreSQL instance.
**Total estimated time:** ~9 hours of lab work
**AWS services used:** RDS, Aurora, CloudWatch, Performance Insights, DevOps Guru, RDS Proxy, Systems Manager

---

## What This Tier Covers

Tier 6 focuses on making your AWS PostgreSQL deployments fast, observable, and self-healing. By the end you will be able to diagnose a slow database in under 10 minutes, tune memory and autovacuum for production workloads, and build a complete monitoring pipeline that catches problems before users notice.

This is the tier where good DBAs become great ones.

---

## Topics

| # | Topic | Build Guide | Time |
|---|-------|-------------|------|
| T6.1 | CloudWatch metrics + Enhanced Monitoring | 01-cloudwatch-enhanced-monitoring.md | 35 min |
| T6.2 | Performance Insights: DB load, wait events, top SQL | 02-performance-insights.md | 40 min |
| T6.3 | Tuning with wait events | 03-wait-event-tuning.md | 45 min |
| T6.4 | DevOps Guru proactive insights | 04-devops-guru.md | 25 min |
| T6.5 | pg_stat_statements in depth | 05-pg-stat-statements.md | 40 min |
| T6.6 | Optimized Reads (RDS NVMe vs Aurora tiered cache) | 06-optimized-reads.md | 30 min |
| T6.7 | Optimized Writes and Aurora I/O-Optimized | 07-optimized-writes-io.md | 30 min |
| T6.8 | Cluster cache management (CCM) | 08-cluster-cache-management.md | 30 min |
| T6.9 | Connection management, RDS Proxy | 09-rds-proxy.md | 45 min |
| T6.10 | Autovacuum at scale | 10-autovacuum-at-scale.md | 45 min |
| T6.11 | Query plan management (Aurora) | 11-query-plan-management.md | 35 min |
| T6.12 | Memory parameter tuning | 12-memory-tuning.md | 35 min |

---

## USE Exercises

| # | Exercise | Time |
|---|----------|------|
| 01 | Set up a complete monitoring pipeline | 45 min |
| 02 | Find and fix top 5 slow queries | 60 min |
| 03 | Handle a connection storm, set up RDS Proxy | 50 min |
| 04 | Tune autovacuum for large tables | 45 min |
| 05 | Diagnose a performance issue from wait events | 45 min |
| 06 | Tune memory parameters for a given workload | 40 min |

---

## SURVIVE Scenarios

Chaos scenarios with inject, runbook, and validate scripts. Each simulates a real production emergency.

| # | Scenario | Difficulty |
|---|----------|------------|
| 01 | Connection exhaustion - max_connections hit | Hard |
| 02 | Autovacuum blocked - table bloating | Hard |
| 03 | Slow query cascade - one bad query killing CPU | Expert |
| 04 | Memory pressure - work_mem OOM risk | Hard |
| 05 | RDS Proxy misconfigured - connections dropping | Expert |
| 06 | TXID wraparound approaching | Expert |

---

## Folder Structure

```
tier6-performance/
├── README.md
├── concepts/
│   └── performance.md          # All 12 topics, diagrams, reference tables
├── build/
│   ├── 01-cloudwatch-enhanced-monitoring.md
│   ├── 02-performance-insights.md
│   ├── 03-wait-event-tuning.md
│   ├── 04-devops-guru.md
│   ├── 05-pg-stat-statements.md
│   ├── 06-optimized-reads.md
│   ├── 07-optimized-writes-io.md
│   ├── 08-cluster-cache-management.md
│   ├── 09-rds-proxy.md
│   ├── 10-autovacuum-at-scale.md
│   ├── 11-query-plan-management.md
│   └── 12-memory-tuning.md
├── use/
│   ├── 01-monitoring-setup.md
│   ├── 02-slow-query-investigation.md
│   ├── 03-connection-storm.md
│   ├── 04-autovacuum-tuning.md
│   ├── 05-wait-event-analysis.md
│   └── 06-memory-optimization.md
├── survive/
│   ├── config.sh
│   ├── lib/
│   │   └── common.sh
│   ├── 01-connection-exhaustion/
│   ├── 02-autovacuum-blocked/
│   ├── 03-slow-query-cascade/
│   ├── 04-memory-pressure/
│   ├── 05-rds-proxy-misconfigured/
│   └── 06-txid-wraparound/
└── interview/
    └── tier6-interview-questions.md
```

---

## AWS Cost Estimate

Running these labs for one day in us-east-1 (approximate):

| Resource | Spec | Daily Cost |
|----------|------|-----------|
| RDS db.t3.medium | PostgreSQL 16 | ~$0.96 |
| Aurora db.r6g.large | PostgreSQL 16 | ~$2.40 |
| RDS Proxy | Per endpoint | ~$0.015/hr |
| Performance Insights | 7-day retention (free) | $0 |
| Performance Insights | 2-year retention | ~$0.02/vCPU/hr |
| Enhanced Monitoring | 60-second granularity | ~$0.30/day |
| DevOps Guru | Per resource analyzed | ~$0.0028/hr |

**Tip:** Stop your instances when not in active lab sessions. Terminate everything when done.

---

## Before You Start

1. You need an RDS PostgreSQL 16 instance (db.t3.medium or larger).
2. You need an Aurora PostgreSQL 16 cluster for topics T6.6, T6.7, T6.8, T6.11.
3. Install the AWS CLI and configure it: `aws configure`
4. Install `psql` locally or use the AWS CloudShell.
5. Set these environment variables in your terminal before starting:

```bash
export DB_INSTANCE_ID="your-rds-instance-id"
export DB_CLUSTER_ID="your-aurora-cluster-id"
export DB_ENDPOINT="your-rds-endpoint.rds.amazonaws.com"
export DB_PORT="5432"
export DB_NAME="postgres"
export DB_USER="postgres"
export REGION="us-east-1"
```

---

## Key Skills You Will Build

- Read a Performance Insights dashboard and identify the root cause of a slowdown in under 5 minutes
- Write CloudWatch alarms that page before users are impacted
- Tune autovacuum on tables with 500M+ rows
- Build an RDS Proxy setup that handles connection spikes without application changes
- Freeze transactions before wraparound shuts your database down
- Stabilize query plans in Aurora with Query Plan Management
- Calculate correct values for shared_buffers, work_mem, and effective_cache_size for any instance type

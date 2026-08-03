# Module 05: HA, Replication and Failover

**Track:** DevOps DBA Training
**Duration:** ~14 hours
**Week:** 3-4
**Prerequisites:** Module 01-04

---

## What You Will Learn

This module teaches you how Aurora stays up when things go down. By the end, you will:

- Understand how Aurora replication differs from traditional PostgreSQL streaming replication
- Deploy reader instances across multiple Availability Zones
- Configure and test automatic failover with promotion priority tiers
- Set up Aurora Serverless v2 for auto-scaling capacity
- Use RDS Proxy to handle connections during failover without app-side errors
- Build cross-region read replicas for disaster recovery
- Design connection strategies that survive instance failures

---

## Module Contents

### Concepts (read first)
1. [High Availability Concepts](concepts/01-high-availability-concepts.md) - AZs, failover mechanics, RPO/RTO, Aurora quorum writes
2. [Scaling Strategies](concepts/02-scaling-strategies.md) - Vertical vs horizontal, read replicas, Serverless v2, Global Database

### BUILD (hands-on, follow step by step)
1. [Multi-AZ Setup](build/01-multi-az-setup.md) - Add reader instances in separate AZs (30 min)
2. [Failover Configuration](build/02-failover-configuration.md) - Promotion tiers, failover priority, custom endpoints (30 min)
3. [Read Replica Scaling](build/03-read-replica-scaling.md) - Add readers, route read traffic, auto-scaling policies (45 min)
4. [Aurora Serverless v2](build/04-aurora-serverless-v2.md) - Add Serverless v2 reader, set min/max ACUs (45 min)
5. [Cross-Region Replicas](build/05-cross-region-replicas.md) - Global Database setup, managed RPO (60 min)
6. [RDS Proxy Setup](build/06-rds-proxy-setup.md) - Deploy proxy, connection pooling, failover routing (45 min)
7. [Connection Management](build/07-connection-management.md) - Endpoint strategies, retry logic, health checks (30 min)

### USE (practice with less hand-holding)
1. [Failover Exercise](use/01-failover-exercise.md)
2. [Read Scaling Exercise](use/02-read-scaling-exercise.md)
3. [Serverless Scaling Exercise](use/03-serverless-scaling-exercise.md)
4. [Cross-Region Exercise](use/04-cross-region-exercise.md)
5. [Architecture Design Exercise](use/05-architecture-design-exercise.md)

### SURVIVE (break it, fix it)
1. [Multi-AZ Failover](survive/01-multi-az-failover/) - Writer goes down, verify automatic promotion
2. [Reader Instance Crash](survive/02-reader-instance-crash/) - Reader disappears, check routing and recovery
3. [RDS Proxy Connection Drop](survive/03-rds-proxy-connection-drop/) - Proxy loses backend, diagnose and restore
4. [Cross-Region Lag](survive/04-cross-region-lag/) - Replication lag spikes, find the cause
5. [Serverless Scaling Stuck](survive/05-serverless-scaling-stuck/) - ACU scaling fails, troubleshoot capacity limits

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

After completing this module, you will move to [Module 06: Backup, Recovery and Lifecycle](../module06-backup-recovery-lifecycle/) where you master backup strategies, point-in-time recovery, and maintenance operations.

---

## Cost Warning

Additional reader instances and RDS Proxy add approximately $0.20/hour total to your running costs. Cross-region replicas (BUILD 05) incur data transfer charges - budget $1-2 for that exercise. Tear down cross-region resources when finished.

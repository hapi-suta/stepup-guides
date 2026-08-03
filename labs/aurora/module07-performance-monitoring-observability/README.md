# Module 07: Performance, Monitoring and Observability

**Track:** DevOps DBA Training
**Duration:** ~14 hours
**Week:** 5
**Prerequisites:** Module 01-06
**Cluster:** devops-lab-cluster

---

## What You Will Learn

This module turns you into someone who finds problems before users report them. By the end, you will:

- Understand Aurora's performance model - storage I/O, memory, CPU, and how the distributed storage layer affects query speed
- Set up CloudWatch dashboards with the metrics that actually matter
- Use Performance Insights to identify top SQL queries, waits, and bottlenecks
- Enable and query Enhanced Monitoring for OS-level visibility
- Analyze slow queries using pg_stat_statements and EXPLAIN plans
- Monitor connection health and prevent connection storms
- Deploy an external Prometheus + Grafana monitoring stack
- Configure alerting strategies that reduce noise and catch real problems
- Plan capacity based on trends rather than guesswork

---

## Module Contents

### Concepts (read first)
1. [Aurora Performance Model](concepts/01-aurora-performance-model.md) - How Aurora perf differs, storage I/O, memory, CPU
2. [Monitoring Stack](concepts/02-monitoring-stack.md) - CloudWatch, Performance Insights, Enhanced Monitoring, RDS Events
3. [Observability Practices](concepts/03-observability-practices.md) - Prometheus, Grafana, SLIs/SLOs for databases

### BUILD (hands-on, follow step by step)
1. [CloudWatch Metrics](build/01-cloudwatch-metrics.md) - Key metrics, alarms, dashboards (40 min)
2. [Performance Insights](build/02-performance-insights.md) - Enable PI, wait events, top SQL (40 min)
3. [Enhanced Monitoring](build/03-enhanced-monitoring.md) - OS metrics, 1s granularity (30 min)
4. [Slow Query Analysis](build/04-slow-query-analysis.md) - log_min_duration, pg_stat_statements (45 min)
5. [EXPLAIN ANALYZE](build/05-explain-analyze.md) - Query plans, indexes, optimization (45 min)
6. [Connection Monitoring](build/06-connection-monitoring.md) - Pools, idle connections, storms (35 min)
7. [Prometheus and Grafana](build/07-prometheus-grafana-setup.md) - External monitoring setup (50 min)
8. [Alerting Strategy](build/08-alerting-strategy.md) - What to alert on, thresholds, tiers (35 min)

### USE (practice with less hand-holding)
1. [Dashboard Building Exercise](use/01-dashboard-building-exercise.md)
2. [Slow Query Investigation](use/02-slow-query-investigation.md)
3. [Wait Event Analysis](use/03-wait-event-analysis.md)
4. [Alerting Validation](use/04-alerting-validation-exercise.md)
5. [Performance Baseline](use/05-performance-baseline-exercise.md)
6. [Capacity Planning](use/06-capacity-planning-exercise.md)

### SURVIVE (break it, fix it)
1. [Connection Exhaustion](survive/01-connection-exhaustion/) - Max connections reached
2. [Autovacuum Blocked](survive/02-autovacuum-blocked/) - Table bloat from long transaction
3. [Slow Query Cascade](survive/03-slow-query-cascade/) - One bad query affecting entire cluster
4. [Memory Pressure](survive/04-memory-pressure/) - Out of memory from sort operations
5. [RDS Proxy Misconfigured](survive/05-rds-proxy-misconfigured/) - Proxy pinning causing issues
6. [TXID Wraparound](survive/06-txid-wraparound/) - XID wraparound approaching

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 20 questions, Junior through Principal

---

## What is Next

After completing this module, move to Module 08: CI/CD for Database Changes where you automate schema migrations and build deployment pipelines for database changes.

---

## Cost Warning

Performance Insights free tier covers 7 days of history. Enhanced Monitoring at 1-second granularity generates ~60x more CloudWatch Logs data than 60-second granularity. CloudWatch alarms cost approximately $0.10 per alarm per month. Custom metrics cost $0.30 per metric per month. Keep alarm counts reasonable during labs.

# Tier 8 Concepts - Operations at Scale and Mastery

This document provides the conceptual foundation for all nine topics in Tier 8. Read it before starting the BUILD guides. The goal is to give you the mental models first so the hands-on work has context.

---

## T8.1 Cost Optimization

### The Problem with "Set It and Forget It" Pricing

AWS RDS and Aurora pricing is multidimensional. Most teams optimize instance type and miss the other levers. At scale, the gaps are expensive.

The four major cost levers are:

**1. Storage pricing model (I/O-Optimized vs Standard)**

Aurora offers two storage pricing modes:

- **Aurora Standard:** You pay per GB-month for storage plus per I/O request. The per-I/O cost is $0.20 per million requests. For a database doing 10 billion I/Os per month, that is $2,000 in storage I/O charges alone.
- **Aurora I/O-Optimized:** Higher base storage cost (roughly 2.25x the per-GB price) but zero per-I/O charges. Break-even typically occurs when I/O charges exceed 25% of your total Aurora cost. AWS provides a calculator, but the pattern is: write-heavy or I/O-intensive workloads benefit most from I/O-Optimized.

The wrong choice costs real money. A 500 GB Aurora cluster doing heavy OLTP can spend $3,000/month unnecessarily if the mode is mismatched to the workload.

**2. Reserved Instances**

RDS Reserved Instances (RIs) offer 30-60% savings over On-Demand pricing for a 1 or 3-year commitment. Key concepts:

- **Standard Reserved:** Fixed instance type, AZ, and region. Highest discount.
- **Convertible Reserved:** Can exchange for different instance types. Lower discount but more flexible.
- **Scope:** Regional RI applies to any AZ in the region. Zonal RI reserves capacity in a specific AZ.
- **Payment options:** All Upfront (best discount), Partial Upfront, No Upfront.

The economics: a `db.r6g.2xlarge` running 24/7 for a year costs roughly $8,700 On-Demand. The 1-year All Upfront RI costs roughly $5,500 - $3,200 in savings per instance per year. At 10 instances, that is $32,000 saved.

The risk: committing to capacity you stop using. RI management requires quarterly review aligned with engineering roadmaps.

**3. Graviton vs Intel**

AWS Graviton (ARM-based) instances (`r6g`, `r7g` families) offer 10-20% better price/performance than equivalent Intel instances for PostgreSQL workloads. The trade-off:

- Cost: Graviton is approximately 10% cheaper for equivalent compute
- Performance: PostgreSQL compiles and runs efficiently on ARM; most workloads see neutral to positive performance impact
- Compatibility: All standard PostgreSQL extensions work. Custom compiled extensions may need recompilation.
- Operational note: You cannot in-place migrate from Intel to Graviton. You create a new instance, restore a snapshot, or use Blue/Green deployment.

**4. Aurora Serverless v2 Economics**

Serverless v2 charges by Aurora Capacity Unit (ACU) per second. 1 ACU = approximately 2 GB RAM and proportional CPU. The pricing model makes sense for workloads with:

- High variability (dev/test, batch jobs, multi-tenant SaaS with variable per-tenant load)
- Predictable peaks that justify the scale-up time

It does not make sense for:
- Steady, high-throughput OLTP (provisioned is cheaper)
- Workloads requiring sub-second scale-up

Cost modeling: project the ACU-hour equivalent of your steady-state workload. If the equivalent provisioned instance costs less than the ACU-hour projection at steady state, use provisioned and scale Serverless for overflow only.

**5. Right-sizing with Cost Explorer**

AWS Cost Explorer's RDS recommendations analyze 14 days of CPU, memory, and connection metrics. Common findings:

- Instances running at <20% CPU average are candidates for downsizing
- Instances with high I/O-to-memory ratio are candidates for storage optimization
- Instances with burst patterns may be candidates for Serverless v2

Right-sizing is not purely a cost exercise - it is also a performance exercise. Under-provisioned instances under load cause incidents.

---

## T8.2 Fleet Management

### Why Fleet Management is a Distinct Discipline

Running one database is a configuration problem. Running 50 databases is an operational systems problem. At fleet scale, manual processes fail not because they are wrong but because they are not consistently applied.

**Tagging Strategy**

Tags are the primary mechanism for organizing, auditing, and cost-allocating a fleet. A well-designed tag schema answers: "Who owns this? What does it do? What environment is it in? What is the cost center?"

A production-grade tagging schema for RDS:

```
Environment:    production | staging | development | sandbox
Application:    [application name]
Team:           [team name]
CostCenter:     [cost center code]
DataClass:      public | internal | confidential | restricted
Compliance:     hipaa | pci | fedramp | none
BackupRequired: true | false
ManagedBy:      terraform | cdk | console | manual
```

Tags that are missing or inconsistent create blind spots in cost reporting and compliance audits.

**AWS Config Rules**

AWS Config continuously evaluates your AWS resources against rules you define. For RDS, critical managed rules include:

- `rds-instance-deletion-protection-enabled` - Flags instances without deletion protection
- `rds-storage-encrypted` - Flags unencrypted instances
- `rds-multi-az-support` - Flags single-AZ production instances
- `rds-no-default-port` - Flags instances using the default PostgreSQL port 5432 (security posture)
- `rds-automatic-minor-version-upgrade-enabled` - Flags instances not auto-patching
- `rds-enhanced-monitoring-enabled` - Flags instances without enhanced monitoring
- `rds-logging-enabled` - Flags instances not exporting logs to CloudWatch

Custom Config rules can enforce your organization's specific standards - for example, requiring specific tags or disallowing certain instance families.

**Drift Detection**

Drift is when an instance's actual configuration diverges from the desired state. Drift sources:

- Manual console changes that bypass IaC
- Automatic minor version upgrades that were not tested in staging
- Parameter group changes applied by on-call engineers during incidents
- Security group rule additions made under pressure

Detecting drift requires comparing the current state (from AWS API) against the desired state (from your IaC or CMDB). Config rules catch some drift automatically. For comprehensive detection, you need Config + a state reconciliation process.

**Automated Remediation**

Config rules can trigger automatic remediation via SSM Automation documents. Example: when `rds-storage-encrypted` finds a violation, an SSM document can:

1. Take a final snapshot
2. Create an encrypted copy of the snapshot
3. Restore to a new encrypted instance
4. Notify the team via SNS

Automated remediation requires careful testing. A runbook that auto-remediates a compliance violation should not also cause an outage.

---

## T8.3 Observability Pipelines

### The Difference Between Monitoring and Observability

Monitoring tells you when something is wrong. Observability tells you why. At scale, you need both.

**CloudWatch Logs for PostgreSQL**

RDS can export multiple PostgreSQL log streams to CloudWatch Logs:

- **postgresql.log** - Main database log. Contains query logs (if `log_min_duration_statement` is set), error messages, connection events, and checkpoint activity.
- **upgrade.log** - Records major version upgrade activity.
- **wal.log** - WAL-related events (less commonly used).

Each log stream creates a CloudWatch Log Group. The log group path follows the pattern: `/aws/rds/instance/[instance-identifier]/postgresql`.

Enabling log exports has a cost: CloudWatch Logs charges $0.50 per GB ingested. A verbose query log on a busy instance can generate significant volume. Always set `log_min_duration_statement` to filter only slow queries (not every query).

**Log Metric Filters**

Once logs are in CloudWatch Logs, you extract signals by creating metric filters. A metric filter defines a pattern to search for in log lines and increments a CloudWatch metric when the pattern matches.

Useful metric filters for PostgreSQL logs:

| Signal | Log Pattern | Metric Name |
|--------|-------------|-------------|
| Deadlocks | `deadlock detected` | `pg_deadlock_count` |
| Autovacuum runs | `automatic vacuum of table` | `pg_autovacuum_runs` |
| Checkpoint warnings | `checkpoint request` | `pg_checkpoint_warn` |
| Connection errors | `connection received` + `authentication failed` | `pg_auth_failures` |
| Slow queries | Threshold-based (queries over N ms) | `pg_slow_query_count` |
| Wraparound warnings | `transaction ID wraparound` | `pg_wraparound_warn` |

**CloudWatch Logs Insights**

Logs Insights is a query language for exploring log data at scale. Unlike metric filters (which are always-on), Logs Insights queries are run on demand. Useful for incident investigation.

Example: find the top 10 slowest queries logged in the last 24 hours:
```
fields @timestamp, @message
| filter @message like /duration:/
| parse @message "duration: * ms" as duration_ms
| stats max(duration_ms) as max_duration by @message
| sort max_duration desc
| limit 10
```

**Operational Dashboards**

A production dashboard for an RDS fleet should display:

- CPU utilization per instance (alert >80% sustained)
- FreeableMemory (alert <10% of total RAM)
- DatabaseConnections (alert >80% of max_connections)
- ReadLatency and WriteLatency (alert >20ms)
- FreeStorageSpace (alert <20% of provisioned)
- ReplicaLag (alert >30s for read replicas)
- AuroraVolumeBytesLeftTotal (for Aurora clusters)
- Custom metrics from metric filters (deadlocks, slow queries)

---

## T8.4 Incident Response Runbooks

### Why Runbooks Exist

An incident runbook documents the steps to diagnose and resolve a specific class of problem. The value is not that it replaces thinking - it is that it eliminates the cognitive overhead of procedure recall under stress.

A DBA who has never seen a wraparound emergency before will make mistakes if they have to reason through every step from scratch at 2 AM. A runbook converts hard-won experience into a repeatable procedure.

**Runbook Template Format**

Each runbook should follow this structure:

```
# Runbook: [Incident Name]

## Symptoms
What the on-call engineer sees first. Alerts that fire. User-visible behavior.

## Impact
What is broken or degraded. Who is affected.

## Immediate Actions (first 5 minutes)
Steps to prevent escalation. These are triage, not fix.

## Diagnosis
Queries and commands to confirm root cause.

## Remediation
Step-by-step fix. Include expected outputs.

## Verification
How to confirm the incident is resolved.

## Prevention
What systemic change prevents recurrence.

## Escalation
When to escalate and to whom.
```

**Key Incident Classes**

- **Failover event:** Planned or unplanned Multi-AZ or Aurora failover. The main risk is application connection handling - connections to the old primary must be rerouted. The cluster endpoint handles this automatically, but applications using instance endpoints will fail.

- **Storage exhaustion:** FreeStorageSpace reaches zero. Writes fail. Reads may be affected. RDS storage autoscaling can prevent this if enabled; manual resize is the emergency fix.

- **Connection storm:** max_connections is exceeded. New connections receive "too many connections" error. Root causes: application pool misconfiguration, connection leak, traffic spike without proper pooling (PgBouncer).

- **Replication lag:** A read replica or Aurora replica is lagging behind the primary. Root causes: long-running transactions on primary, high write rate exceeding replica apply throughput, replica under-provisioned relative to primary.

- **Autovacuum / wraparound:** PostgreSQL's MVCC mechanism assigns transaction IDs to every write transaction. After 2 billion transactions, IDs wrap around to zero. PostgreSQL will shut down the database to prevent data corruption when the oldest unfrozen transaction is within 1 million transactions of the wraparound limit. Early warning: `age(datfrozenxid)` approaches 1.5-1.8 billion.

- **citext vs text index bypass:** The `citext` extension provides case-insensitive text comparisons. A common trap: indexing a `text` column and querying with `citext` operators (or vice versa) causes index bypass because the operator class does not match. Symptoms are sequential scans on what should be indexed columns. Diagnosis requires examining the query plan with `EXPLAIN (ANALYZE, BUFFERS)`.

---

## T8.5 Capacity Planning with pgbench

### The Purpose of Load Testing

Load testing answers questions that monitoring alone cannot: what happens to this database at 2x current load? At what point does query latency become unacceptable? Does memory usage grow linearly with connections?

Capacity planning uses load test results to project future resource requirements.

**pgbench Methodology**

pgbench is PostgreSQL's built-in benchmark tool. It simulates a TPC-B-like workload (bank transactions). While not identical to your production workload, it provides a reproducible baseline.

The test involves:
1. Initialize the database with a dataset (`pgbench -i -s [scale_factor]`)
2. Run a timed benchmark (`pgbench -c [clients] -j [threads] -T [seconds]`)
3. Record TPS (transactions per second), latency, and connection count
4. Vary the client count to find the saturation point

**Load Testing vs Soak Testing**

- **Load test:** Ramp up load to find the breaking point. Identifies throughput ceiling and latency degradation curve.
- **Soak test:** Run at realistic load for an extended period (hours to days). Identifies memory leaks, connection exhaustion, bloat accumulation, and gradual performance degradation.

**Interpreting Results**

Key indicators of saturation:
- TPS stops increasing as client count increases (CPU or I/O bound)
- Latency grows super-linearly (contention - lock waits, connection queue)
- FreeableMemory trends downward over time during a soak test (potential memory leak or bloat)
- `pg_stat_activity` shows many sessions in `lock wait` state

---

## T8.6 Compliance

### The Compliance Landscape for Databases

Databases are almost always in scope for compliance frameworks because they hold the data the framework is designed to protect.

**HIPAA**

HIPAA (Health Insurance Portability and Accountability Act) applies to any system that stores, processes, or transmits Protected Health Information (PHI). RDS can be HIPAA-eligible if:

- You execute an AWS Business Associate Agreement (BAA)
- You enable encryption at rest (AES-256 via AWS KMS)
- You enable encryption in transit (SSL/TLS required)
- You enable audit logging via pgaudit
- You restrict access to PHI at the database user level (least privilege)
- You retain audit logs for 6 years
- You have documented access controls and incident response procedures

**FedRAMP**

FedRAMP (Federal Risk and Authorization Management Program) applies to cloud services used by U.S. federal agencies. RDS PostgreSQL is authorized at FedRAMP Moderate (and in some regions, High). If your organization processes federal data:

- Use only FedRAMP-authorized regions (us-east-1, us-west-2, us-gov regions)
- Enable FIPS 140-2 compliant encryption endpoints
- Enable CloudTrail for all RDS API actions
- Implement comprehensive audit logging
- Enforce MFA for all IAM users with RDS access

**pgaudit**

pgaudit is a PostgreSQL extension that provides audit logging at the statement and object level. It is the primary mechanism for proving that you know who accessed what data and when.

Key pgaudit settings:
- `pgaudit.log = 'ddl, write, role'` - Log all DDL, data modifications, and role changes
- `pgaudit.log = 'all'` - Log everything (very verbose, use with care)
- `pgaudit.log_relation = on` - Include the relation (table) name in each log entry
- `pgaudit.log_parameter = on` - Include bind parameters in log entries

On RDS, pgaudit must be loaded via the shared_preload_libraries parameter group setting and the extension must be created in each database.

---

## T8.7 Disaster Recovery Design

### RTO and RPO Defined

- **Recovery Time Objective (RTO):** The maximum acceptable duration of downtime. How long can the business tolerate the system being unavailable?
- **Recovery Point Objective (RPO):** The maximum acceptable data loss measured in time. How much data can the business afford to lose?

These are business decisions, not technical decisions. The DBA's job is to design a technical system that meets the business's stated RTO/RPO requirements, and to tell the business when their stated targets are not achievable within their budget.

**Tiered DR Requirements**

Different workloads have different requirements:

| Tier | Example Workload | RTO Target | RPO Target | Design |
|------|-----------------|------------|------------|--------|
| Tier 1 - Mission Critical | Payment processing, authentication | < 1 minute | 0 (no loss) | Aurora Global Database, synchronous Multi-AZ |
| Tier 2 - Business Critical | Order management, customer records | < 15 minutes | < 1 minute | Aurora Multi-AZ, automated failover |
| Tier 3 - Important | Reporting, analytics | < 1 hour | < 15 minutes | Multi-AZ, manual failover |
| Tier 4 - Standard | Internal tools, dev/staging | < 4 hours | < 1 hour | Single-AZ, automated backup restore |

**Aurora Global Database Failover**

Aurora Global Database replicates data from a primary region to up to 5 secondary regions with typical lag < 1 second. Failover process:

1. Detach the secondary region cluster from the global database
2. Promote the secondary to a standalone cluster
3. Update application connection strings to point to the new primary
4. After the primary region recovers, reattach it as a new secondary

The promoted cluster is ready for reads and writes within 1-2 minutes of initiating the promotion. This is the mechanism for achieving RTO < 5 minutes for cross-region failures.

**Cross-Region Snapshot Strategy**

For non-Global Database workloads:
- Enable automated backup copy to a secondary region
- RDS can automatically copy snapshots to a second region on a schedule
- RPO is bounded by the copy interval plus the backup window
- This is appropriate for Tier 3 and Tier 4 workloads

**DR Testing**

An untested DR plan is not a DR plan. DR testing must verify:
1. Can you actually initiate the failover? (Permissions, runbook accuracy)
2. Does the failover complete within the RTO?
3. Is data intact to within the RPO?
4. Can the application actually connect and function after failover?
5. Can you fail back to the primary region?

DR tests should be conducted quarterly for Tier 1 workloads, semi-annually for Tier 2.

---

## T8.8 Failure Injection and Resilience Testing

### Chaos Engineering Principles

Chaos engineering is the practice of deliberately injecting failures into a system to discover weaknesses before they cause real incidents. The principles:

1. Define a "steady state" - measurable, normal system behavior
2. Hypothesize that steady state will continue during the failure
3. Inject a realistic failure
4. Observe whether steady state holds
5. If not, you found a weakness to fix

For databases, typical failure scenarios:
- AZ-level failure (simulated by making the primary instance unavailable)
- Instance-level failure (kill the database process or terminate the instance)
- Network partition (block traffic between application and database)
- Storage I/O throttling (simulate storage pressure)
- CPU saturation (simulate high compute load)

**AWS Fault Injection Simulator (FIS)**

FIS is AWS's managed chaos engineering service. For RDS, it supports:
- `aws:rds:failover-db-cluster` - Triggers an Aurora cluster failover
- `aws:rds:reboot-db-instances` - Reboots specific RDS instances (with or without failover)

FIS experiments run with defined stop conditions - if a key metric (like API error rate) exceeds a threshold, the experiment aborts automatically. This is the safety mechanism that separates controlled chaos from uncontrolled failure.

**Measuring Actual RTO**

The purpose of failure injection is to measure actual RTO against designed RTO. Instrument your system to record:

- T0: When the failure is injected
- T1: When the first health check fails
- T2: When the failover is initiated (automatic or manual)
- T3: When the new primary is accepting connections
- T4: When the application confirms end-to-end health

RTO = T4 - T0. Compare this to your designed RTO target. If the actual RTO is 4 minutes and your target is 1 minute, you have a problem to solve before a real incident exposes it.

---

## T8.9 Autonomous Diagnostics

### Scaling Expertise Beyond One Person

A principal DBA knows how to diagnose any database problem. A principal DBA who has designed an autonomous diagnostic system scales that knowledge across the entire fleet without requiring their personal involvement.

The goal is not to replace human judgment. It is to ensure that routine health checks happen consistently at scale, and that a human is only engaged when the machine's rule-based logic finds something it cannot resolve automatically.

**Rule-Based Health Checks**

A rule-based health check is a defined condition evaluated against current state. If the condition is true, take a defined action (alert, auto-remediate, or escalate).

Example rules:

| Metric | Condition | Action |
|--------|-----------|--------|
| CPU > 85% for 15 min | Warning | Alert on-call |
| CPU > 95% for 5 min | Critical | Alert + create support ticket |
| FreeStorageSpace < 20% | Warning | Alert + trigger storage increase |
| FreeStorageSpace < 10% | Critical | Auto-increase storage |
| DatabaseConnections > 90% of max_connections | Critical | Alert + scale up connection pooler |
| age(datfrozenxid) > 1.5B | Critical | Alert + page DBA |
| ReplicaLag > 60s | Warning | Alert |
| ReplicaLag > 300s | Critical | Alert + remove from read endpoint |

**Read-Only Triage Queries**

All diagnostic queries should be read-only. Never run a diagnostic that could change the state of the database under investigation. This prevents a diagnostic tool from causing the incident it is trying to detect.

Key triage queries:

```sql
-- Current long-running queries
SELECT pid, now() - query_start AS duration, state, query
FROM pg_stat_activity
WHERE state != 'idle'
AND query_start < now() - interval '5 minutes'
ORDER BY duration DESC;

-- Lock waits
SELECT blocking.pid AS blocking_pid, blocked.pid AS blocked_pid,
       blocked.query AS blocked_query
FROM pg_stat_activity blocked
JOIN pg_stat_activity blocking ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;

-- Wraparound proximity
SELECT datname, age(datfrozenxid) AS xid_age,
       2000000000 - age(datfrozenxid) AS transactions_remaining
FROM pg_database
ORDER BY xid_age DESC;

-- Table bloat indicator
SELECT schemaname, relname,
       n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_ratio
FROM pg_stat_user_tables
WHERE n_live_tup > 1000
ORDER BY dead_ratio DESC NULLIF 10;
```

**Fleet-Wide Diagnostic Approach**

At fleet scale, run health checks via:
- Lambda functions on a schedule, querying the CloudWatch API for metric violations
- RDS Event Subscriptions forwarded to SNS/Lambda for instance-level events
- Custom health check scripts connecting to each instance via a bastion or VPN with read-only credentials
- AWS Health API for service-level events affecting your fleet

The output of all health checks should flow to a single operational view - whether that is a CloudWatch dashboard, a Datadog monitor, a PagerDuty integration, or a custom internal tool.

---

## Summary

Tier 8 is about operating at the organizational level. The technical skills are necessary but not sufficient. A master-level DBA also brings:

- **Judgment:** Knowing which lever to pull and when, not just how the lever works
- **Communication:** Translating technical constraints into business terms (RTO/RPO, cost trade-offs)
- **Systems thinking:** Seeing how cost, compliance, observability, and DR interact with each other
- **Organizational leverage:** Building systems and runbooks that multiply the team's capability
- **Principled disagreement:** Knowing when the business's stated requirements are technically unrealistic and saying so clearly

The topics in this tier are not independent. Cost optimization affects instance choices which affect performance which affects capacity planning which affects DR design. Treat them as a connected system, not a list of separate skills.

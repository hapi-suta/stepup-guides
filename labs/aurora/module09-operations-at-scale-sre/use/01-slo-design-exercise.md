# USE 01: SLO Design Exercise

**Module 09: Operations at Scale and SRE**
**Estimated Time:** 30-40 minutes

---

## Context

You are the DBA for a healthcare SaaS company. The application uses Aurora PostgreSQL to store patient records, appointment scheduling, and billing data. The CTO has asked you to define SLOs for the database tier. The application must comply with HIPAA regulations, and the company's SLA to hospital clients promises 99.95% uptime.

---

## Part 1: SLI Selection

<details>
<summary>Task 1.1: Identify the SLIs you would track for this healthcare database. List at least 5 SLIs and explain why each matters for a healthcare workload.</summary>

Consider these dimensions:
- Availability (can doctors access patient records?)
- Latency (how fast do queries return during a consultation?)
- Error rate (are prescriptions being saved correctly?)
- Replication lag (is the reporting database current?)
- Data durability (are backups recoverable?)

Your answer should include the SLI name, what you measure, and why it matters for healthcare specifically.

**Example answer:**

| SLI | Measurement | Healthcare Relevance |
|-----|------------|---------------------|
| Availability | SELECT 1 health check every 10 seconds | Doctors need patient records during emergencies - unavailability can impact patient safety |
| Query latency (p95) | pg_stat_statements mean_exec_time | During consultations, slow queries delay care delivery |
| Query latency (p99) | pg_stat_statements max_exec_time | Worst-case latency during peak hours (morning clinic rush) |
| Error rate | xact_rollback / total transactions | Failed transactions could mean lost prescriptions or appointment data |
| Replication lag | AuroraReplicaLag metric | Reporting queries on readers must reflect recent patient data |
| Backup recoverability | Weekly restore test to staging | HIPAA requires verified backup recovery capability |
| Connection utilization | DatabaseConnections / max_connections | Multiple clinic locations connecting simultaneously at shift change |

</details>

<details>
<summary>Task 1.2: For each SLI, define a measurement method. Specify whether you use CloudWatch, SQL queries, or external probes.</summary>

For each SLI from Task 1.1, provide:
- The exact CloudWatch metric name or SQL query
- The sampling interval (how often you measure)
- Where the measurement runs from (inside the VPC, external probe, CloudWatch native)

**Example:**

```
SLI: Availability
Method: External probe from monitoring system (Datadog/CloudWatch Synthetics)
Query: SELECT 1 with 1-second timeout
Interval: Every 10 seconds
Source: Lambda function in same VPC, separate from application

SLI: Query Latency (p95)
Method: pg_stat_statements extension
Query:
  SELECT round(mean_exec_time::numeric, 2) AS avg_ms
  FROM pg_stat_statements
  WHERE calls > 100
  ORDER BY mean_exec_time DESC;
Interval: Every 60 seconds
Source: Monitoring Lambda function
```

</details>

---

## Part 2: SLO Definition

<details>
<summary>Task 2.1: Set SLO targets for each SLI. The company SLA promises 99.95% uptime to hospital clients. What should your internal SLO be, and why?</summary>

Key considerations:
- Your SLO must be tighter than the SLA (99.95%)
- Healthcare workloads have higher stakes than typical SaaS
- More nines cost more money
- Be honest about what your architecture can deliver

**Example answer:**

| SLI | SLO Target | Rationale |
|-----|-----------|-----------|
| Availability | 99.97% | Buffer above 99.95% SLA. Aurora Multi-AZ with automated failover supports this. |
| Latency (p95) | < 50ms | Doctors expect instant response during consultations. Application timeout is 3 seconds. |
| Latency (p99) | < 200ms | Even worst-case queries must complete before users perceive delay. |
| Error rate | < 0.05% | Healthcare data loss is unacceptable. Fewer than 1 in 2,000 transactions should fail. |
| Replication lag | < 3 seconds | Reporting data must be near-real-time for clinical dashboards. |

</details>

<details>
<summary>Task 2.2: Calculate the error budget for your availability SLO. How many minutes of downtime are allowed per quarter? Per month?</summary>

Use the formula:
```
Error Budget = 1 - SLO target
Quarterly budget = 90 days * 24 hours * 60 minutes * (1 - SLO)
Monthly budget = 30 days * 24 hours * 60 minutes * (1 - SLO)
```

**Example answer (for 99.97% SLO):**

```
Error Budget = 1 - 0.9997 = 0.0003 = 0.03%

Quarterly: 90 * 24 * 60 * 0.0003 = 38.88 minutes
Monthly: 30 * 24 * 60 * 0.0003 = 12.96 minutes

This means:
- One 15-minute outage exhausts the quarterly budget
- A 30-second failover uses 0.77% of the quarterly budget
- A 5-minute connectivity issue uses 12.9% of the quarterly budget
```

</details>

---

## Part 3: Error Budget Policy

<details>
<summary>Task 3.1: Write an error budget policy document. Define what happens at each budget consumption level (healthy, warning, low, exhausted). Include HIPAA-specific considerations.</summary>

Your policy should cover:
- Budget thresholds and corresponding actions
- Who approves deployments at each level
- What types of changes are allowed or frozen
- HIPAA audit trail requirements
- Communication to hospital clients

**Example answer:**

```markdown
# Error Budget Policy: Healthcare Aurora PostgreSQL

## Budget: 38.88 minutes per quarter (99.97% SLO)

### HEALTHY (< 50% consumed, > 19.4 minutes remaining)
- Standard deployment process
- Schema migrations allowed with DBA review
- Chaos experiments permitted (failover testing)
- HIPAA audit: routine compliance checks

### WARNING (50-75% consumed, 9.7-19.4 minutes remaining)
- All deployments require DBA + engineering lead approval
- No schema migrations without rollback plan tested in staging
- No chaos experiments
- HIPAA audit: review recent incidents for PHI exposure risk

### LOW (75-100% consumed, 0-9.7 minutes remaining)
- Critical security patches only
- No feature deployments
- No maintenance operations that risk downtime
- HIPAA audit: document all remaining budget consumption for compliance
- Notify hospital clients of elevated risk posture

### EXHAUSTED (0 minutes remaining)
- Complete change freeze until next quarter
- Exception: critical security vulnerabilities (requires CISO + VP approval)
- Post-incident review for every incident that consumed budget
- HIPAA audit: formal incident report if any PHI was at risk
- Hospital clients notified with remediation plan
```

</details>

---

## Part 4: Architecture Gaps

<details>
<summary>Task 4.1: Based on your SLO targets, identify architecture gaps. What changes to your Aurora setup would be needed to reliably meet a 99.97% availability SLO?</summary>

Consider:
- Is a single Aurora cluster sufficient?
- Do you need a connection pooler?
- How fast is failover, and does the application handle it?
- Do you need cross-region capability for disaster recovery?

**Example answer:**

| Gap | Current State | Required State | Estimated Cost |
|-----|--------------|---------------|---------------|
| Connection pooler | Direct connections | RDS Proxy or PgBouncer | $50-200/month |
| Failover testing | Never tested | Quarterly automated tests | Staff time |
| Cross-region DR | Single region | Aurora Global Database | 2x compute + storage |
| Application retry | No retry logic | Exponential backoff with jitter | Development time |
| Monitoring | Basic CloudWatch | Custom SLO dashboard with error budget tracking | Lambda + SNS costs |

</details>

---

## Deliverables

By the end of this exercise, you should have:

1. A list of 5+ SLIs with measurement methods
2. SLO targets for each SLI with rationale
3. Error budget calculation (quarterly and monthly)
4. Error budget policy document with HIPAA considerations
5. Architecture gap analysis

---

## Reflection Questions

1. Why should your SLO be tighter than your SLA?
2. What happens to deployment velocity when the error budget is exhausted?
3. How would you convince leadership that spending money on a connection pooler is worth it?
4. If a 30-second failover consumes almost 1% of your quarterly budget, how many failovers can you tolerate per quarter?

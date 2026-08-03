# USE: SRE Exercises

**Module 07: Database SRE Practices**

---

## Exercise 1: SLO Definition

**Objective:** Define SLIs, SLOs, and calculate error budgets for a production PostgreSQL service.

### Scenario

You are the DBRE for a fintech company. The core PostgreSQL database powers:
- Payment processing (10,000 transactions/hour)
- Account balance lookups (50,000 queries/hour)
- Reporting dashboards (refreshed every 5 minutes)

Architecture: 1 primary + 2 standbys (Patroni), PgBouncer in front.

### Tasks

1. **Define 5 SLIs** with exact measurement methods (queries, probes, tools)

2. **Set SLOs** for each SLI. Justify each target based on the business context:
   - Payment processing needs higher availability than reporting
   - Balance lookups need low latency
   - Replication lag matters because standbys serve read traffic

3. **Calculate error budgets** for a quarterly window:
   - Availability error budget in minutes
   - Show the math

4. **Create an alert mapping:** For each SLI, define:
   - Warning threshold (SLO buffer)
   - Critical threshold (SLO breach)
   - Who gets paged

5. **Write the SLI monitoring queries** in SQL that could run in a cron job or monitoring system

### Deliverables

- `sli-definitions.yml` - SLI definitions with measurement details
- `slo-targets.yml` - SLO targets with justifications
- `error-budget-calc.sql` - SQL to calculate current error budget status
- `alert-mapping.md` - Alert thresholds and escalation paths

---

## Exercise 2: Runbook Writer

**Objective:** Write operational runbooks for 5 common database incidents.

### Requirements

Write a runbook for each of the following incidents. Each runbook must follow this structure:

1. **Trigger** - What alert fires?
2. **Severity** - SEV1/2/3/4 and criteria for escalation
3. **Impact** - What do users experience?
4. **Diagnosis** - Step-by-step SQL queries to investigate
5. **Mitigation** - Ordered options from safest to most aggressive
6. **Prevention** - How to prevent recurrence
7. **Escalation** - When and to whom

### The 5 Incidents

1. **Connection pool exhaustion**
   - PgBouncer or application pool reaches max
   - All new connections are queued or rejected
   - Diagnosis: check `SHOW POOLS` in PgBouncer, `pg_stat_activity` in PostgreSQL

2. **Long-running transaction blocking others**
   - An `IDLE IN TRANSACTION` session holds locks for 30+ minutes
   - Other queries are blocked waiting for the lock
   - Diagnosis: `pg_locks`, `pg_stat_activity`, identify the blocker

3. **Autovacuum cannot keep up (table bloat)**
   - Dead tuple count growing faster than autovacuum can clean
   - Table size growing, queries getting slower (bloat)
   - Diagnosis: `pg_stat_user_tables`, vacuum progress, dead tuple counts

4. **Patroni failover did not complete**
   - Primary went down but no standby was promoted
   - All writes failing, no primary in the cluster
   - Diagnosis: `patronictl list`, etcd health, Patroni logs

5. **Sudden query performance degradation**
   - p95 latency jumped from 50ms to 500ms in the last hour
   - No schema changes, no deployment
   - Diagnosis: `pg_stat_statements`, plan changes, `pg_stat_user_tables` (autovacuum running?)

### Acceptance Criteria

- [ ] Each runbook has all 7 sections
- [ ] SQL queries are correct and tested
- [ ] Mitigation options are ordered by risk (safest first)
- [ ] Escalation criteria are specific ("If X does not resolve in Y minutes, escalate to Z")

---

## Exercise 3: Incident Response Simulation

**Objective:** Walk through a complete SEV1 database outage, documenting everything as if it were real.

### The Scenario

**14:32 UTC** - PagerDuty fires: "PostgreSQL primary - connection refused"

The primary PostgreSQL server hosting the payment processing database is unreachable. Patroni shows no leader. Both standbys are running but in read-only mode. No writes are possible. The application is returning 500 errors on all payment endpoints.

### Tasks

1. **Declare the incident**
   - Write the initial communication (severity, impact, IC)
   - Identify who needs to be notified

2. **Build the timeline**
   - Document every action you would take, in order, with timestamps
   - Include diagnosis queries you would run
   - Include decisions made and rationale

3. **Resolve the incident**
   - Determine the root cause (choose one: disk full, OOM kill, network partition, or hardware failure)
   - Document the mitigation steps
   - Write the "all clear" communication

4. **Write the post-incident review**
   - Complete the PIR template from BUILD 02
   - Include: timeline, root cause, contributing factors, what went well, what went wrong
   - List 5 action items with owners and due dates

5. **Calculate error budget impact**
   - If the outage lasted 45 minutes, how much error budget was consumed?
   - What is the remaining budget for the quarter?

### Deliverables

- `incident-timeline.md` - Minute-by-minute timeline
- `communications.md` - All status updates that would have been sent
- `post-incident-review.md` - Complete PIR using the template
- `error-budget-impact.md` - Budget calculation showing remaining budget

---

## Exercise 4: Chaos Experiment

**Objective:** Design and execute a chaos experiment targeting connection saturation.

### The Experiment

**Hypothesis:** "When active connections reach 90% of max_connections, PgBouncer will queue new requests. Queued requests will experience increased latency (< 5 seconds) but will eventually succeed. When connections drop below 80%, latency will return to normal within 30 seconds."

### Tasks

1. **Write the gameday plan** using the template from BUILD 03:
   - Steady state measurements
   - Hypothesis
   - Blast radius
   - Rollback plan
   - Step-by-step experiment procedure

2. **Execute the experiment locally:**
   - Set `max_connections = 30` on your local PostgreSQL
   - Record baseline latency for `SELECT 1`
   - Open 25 idle connections (83% utilization)
   - Measure latency for new queries
   - Open 5 more connections (100% utilization)
   - Attempt new connections - record errors
   - Release all connections
   - Measure recovery time

3. **Document results:**
   - Fill in the results template
   - Was the hypothesis confirmed?
   - What behavior was unexpected?

4. **Write action items:**
   - What monitoring would catch this in production?
   - What automated remediation could help?
   - What configuration changes would improve resilience?

### Acceptance Criteria

- [ ] Gameday plan is complete with all sections
- [ ] Experiment was actually executed (not just planned)
- [ ] Baseline and during-chaos measurements are recorded
- [ ] Recovery time is measured
- [ ] Results document includes hypothesis evaluation
- [ ] At least 3 action items identified

---

## Exercise 5: Toil Audit

**Objective:** Catalog your actual manual DBA tasks, estimate time, and prioritize automation.

### Tasks

1. **Toil inventory** - List every manual, repetitive task you perform as a DBA. For each task, document:
   - Description
   - Frequency (daily, weekly, monthly)
   - Time per occurrence
   - Annual hours
   - Is it automatable? (Yes / Partially / No)

2. **Toil score** - Calculate:
   - Total annual hours spent on toil
   - Toil percentage (toil hours / total work hours)
   - Top 5 toil tasks by annual hours

3. **Automation plan** - For each of the top 5 toil tasks:
   - Estimated automation effort (hours to build)
   - Estimated annual hours saved
   - ROI = hours saved / hours to build
   - Implementation approach (script, tool, self-service portal)

4. **Build one automation** - Pick the task with the highest ROI and build the automation:
   - Write the script or tool
   - Test it against your local PostgreSQL
   - Document usage instructions
   - Schedule it (cron, CI/CD, or event-driven)

5. **Toil reduction report** - Write a one-page summary:
   - Current toil percentage
   - Target toil percentage (after automation)
   - Top 3 automations to build in the next quarter
   - Estimated quarterly time savings

### Deliverables

- `toil-inventory.csv` - All tasks with time estimates
- `automation-plan.md` - Prioritized automation roadmap
- `automation/` directory with the script you built
- `toil-report.md` - One-page summary for management

### Acceptance Criteria

- [ ] At least 15 tasks identified in the toil inventory
- [ ] Annual hours calculated for each task
- [ ] Top 5 prioritized by ROI
- [ ] One automation actually built and tested
- [ ] Toil reduction report is clear enough for a non-technical manager

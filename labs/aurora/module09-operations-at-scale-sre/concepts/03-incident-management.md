# Concepts 03: Incident Management

**Module 09: Operations at Scale and SRE**
**Reading Time:** 20-25 minutes

---

## Why Incident Management Matters for DBAs

Every DBA has been woken up at 2 AM by a database alert. The difference between a team that handles incidents well and one that does not is not technical skill - it is process. A structured incident management process reduces Mean Time to Recovery (MTTR), prevents panic-driven mistakes, and builds organizational learning from every failure.

Incident management is not about preventing all incidents. That is impossible. It is about detecting incidents fast (MTTD), recovering fast (MTTR), and preventing the same incident from recurring.

---

## Incident Severity Levels

Not every problem is an emergency. Severity levels prioritize response effort and communication.

| Severity | Name | Database Examples | Response Time | Who Is Notified |
|----------|------|------------------|---------------|----------------|
| **SEV1** | Critical | Primary down, all writes failing, data loss risk | < 5 min | On-call DBA, engineering lead, management |
| **SEV2** | Major | Standby down (HA degraded), severe performance degradation | 15 min | On-call DBA, engineering team |
| **SEV3** | Minor | Slow queries affecting some users, disk 85% full | 1 hour | DBA team (Slack/email) |
| **SEV4** | Cosmetic | Config drift, unused index, minor monitoring gap | Next business day | DBA backlog |

**Mapping to PostgreSQL log levels:**
- SEV1 = PANIC (system is unusable)
- SEV2 = FATAL (significant functionality broken)
- SEV3 = WARNING (something needs attention soon)
- SEV4 = NOTICE (informational, handle when convenient)

---

## On-Call Structure

### Rotation Design

A healthy on-call rotation has these properties:

- **Rotation length:** 1 week per engineer. Longer rotations cause burnout.
- **Team size:** Minimum 4-5 people to sustain a weekly rotation without exhaustion.
- **Primary/secondary:** Two on-call engineers - primary responds first, secondary is backup.
- **Handoff:** Formal handoff at rotation start covering active incidents, ongoing issues, and scheduled changes.

### On-Call Quality Metrics

| Metric | Target | What It Measures |
|--------|--------|------------------|
| Pages per week | < 5 per engineer | Alert quality and volume |
| False positive rate | < 10% | Alert tuning effectiveness |
| Acknowledge time | < 5 minutes | Response readiness |
| MTTR for SEV1 | < 30 minutes | Diagnostic and remediation speed |
| Escalation rate | < 20% | Runbook completeness |

If on-call engineers are receiving more than 5 pages per week, the alerting system needs tuning. High-volume paging causes alert fatigue - engineers start ignoring alerts, and real incidents get missed.

### Escalation Path

```
Alert fires
    |
    v
Primary on-call acknowledges (5 min SLA)
    |
    v
Primary begins diagnosis using runbook
    |
    +-- Resolved within 15 min --> Close incident
    |
    +-- Not resolved in 15 min --> Escalate to secondary
    |
    +-- Not resolved in 30 min --> Escalate to subject matter expert
    |
    +-- Customer-visible impact --> Declare SEV1, assign Incident Commander
```

---

## The Incident Commander Role

For SEV1 and SEV2 incidents, one person takes the Incident Commander (IC) role. The IC does not fix the problem - they coordinate the response.

### IC Responsibilities

1. **Declare the incident:** "This is a SEV1. I am the Incident Commander."
2. **Coordinate responders:** Assign specific tasks to specific people.
3. **Communicate status updates:** Every 15 minutes to stakeholders during SEV1.
4. **Make decisions:** "We are failing over to the standby. Proceed."
5. **Track timeline:** Document what happened and when.
6. **Declare resolution:** "The incident is resolved. Post-incident review in 48 hours."

### Communication Template

```
INCIDENT: [Brief description]
SEVERITY: SEV[1/2]
STATUS: [Investigating / Identified / Mitigating / Resolved]
IMPACT: [What is broken for users]
CURRENT ACTIONS: [What the team is doing right now]
NEXT UPDATE: [When the next update will be posted]
IC: [Name]
```

---

## Runbooks

A runbook is a documented procedure for responding to a specific incident type. Runbooks convert hard-won experience into repeatable procedures. They are essential because incidents are stressful and cognitive load must be minimized.

### Runbook Template

Every runbook should follow this structure:

```
# Runbook: [Incident Name]
Severity: Critical | High | Medium
Last Updated: [DATE]
Owner: [TEAM NAME]

## Symptoms
What the on-call engineer sees first. Alerts that fire. User-visible behavior.

## Impact
What is broken or degraded. Who is affected.

## Immediate Actions (first 5 minutes)
Steps to prevent escalation. Triage, not fix.

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

### Key Database Incident Types

| Incident | First Check | First Action | Root Cause Pattern |
|----------|-------------|--------------|-------------------|
| Failover event | RDS Events API | Monitor, do not intervene | AZ failure, instance failure |
| Storage exhaustion | FreeStorageSpace metric | Increase allocated storage | Bloat, inactive replication slots |
| Connection storm | DatabaseConnections metric | Terminate idle sessions | Missing connection pooler, leak |
| Replication lag | AuroraReplicaLag metric | Find long-running transactions | Long txns, high write rate |
| Wraparound | age(datfrozenxid) | VACUUM FREEZE | Disabled autovacuum |

### Runbook Maintenance

Runbooks rot. A runbook written 6 months ago may reference outdated commands, wrong file paths, or deprecated tools. Maintain runbooks by:

- Reviewing every runbook used during an incident. Did it work? Update it.
- Testing runbooks quarterly in staging. Walk through every step.
- Assigning an owner to each runbook. The owner is responsible for keeping it current.
- Version-controlling runbooks alongside your infrastructure code.

---

## Post-Incident Reviews (Postmortems)

After every SEV1 and SEV2 incident, conduct a blameless post-incident review (PIR). The goal is understanding what happened and preventing recurrence - not assigning blame.

### The Blameless Principle

"What allowed the system to fail?" not "Who broke it?"

Humans make mistakes. The question is whether the system made the mistake easy to make and hard to detect. A blameless PIR focuses on the system, not the individual.

### PIR Template

```
# Post-Incident Review: [Incident Title]

Date: [Date of incident]
Duration: [Start] to [Resolution] ([Total])
Severity: SEV[X]
IC: [Name]

## Summary
[2-3 sentences: what happened and the impact]

## Timeline
| Time (UTC) | Event |
|-----------|-------|
| HH:MM | Alert triggered |
| HH:MM | IC acknowledged |
| HH:MM | Root cause identified |
| HH:MM | Mitigation applied |
| HH:MM | Service restored |

## Impact
- Users affected: [Number/percentage]
- Duration of impact: [Time]
- Data loss: [Yes/No]
- Error budget consumed: [X minutes of Y remaining]

## Root Cause
[Technical description - not "someone made a mistake"]

## Contributing Factors
1. [Factor 1]
2. [Factor 2]

## What Went Well
1. [Item]

## What Went Wrong
1. [Item]

## Action Items
| ID | Action | Owner | Priority | Due |
|----|--------|-------|----------|-----|
| 1  | [Action] | [Name] | P[1-3] | [Date] |
```

### Action Item Follow-Through

The PIR is only valuable if the action items get completed. Track action item completion rate as an organizational metric. A team that generates action items but never completes them will have the same incident again.

---

## MTTD, MTTR, and MTTF

These metrics track incident response effectiveness over time:

| Metric | Full Name | What It Measures | How to Improve |
|--------|-----------|------------------|----------------|
| **MTTD** | Mean Time to Detect | Time from incident start to first alert | Better monitoring, lower thresholds |
| **MTTR** | Mean Time to Recover | Time from detection to full resolution | Better runbooks, automated remediation |
| **MTTF** | Mean Time to Failure | Time between incidents | Root cause fixes, chaos engineering |

For database services, target these benchmarks:

- MTTD: < 5 minutes for SEV1 incidents
- MTTR: < 30 minutes for SEV1 incidents
- MTTF: Improving quarter over quarter

### Tracking Incident Metrics

```sql
CREATE TABLE IF NOT EXISTS incident_log (
    incident_id SERIAL PRIMARY KEY,
    severity VARCHAR(5) NOT NULL,
    title TEXT NOT NULL,
    detected_at TIMESTAMPTZ NOT NULL,
    responded_at TIMESTAMPTZ,
    resolved_at TIMESTAMPTZ,
    root_cause TEXT,
    action_items TEXT[]
);

SELECT
    severity,
    count(*) AS incident_count,
    round(avg(extract(epoch FROM responded_at - detected_at) / 60), 1) AS avg_mttd_min,
    round(avg(extract(epoch FROM resolved_at - detected_at) / 60), 1) AS avg_mttr_min
FROM incident_log
WHERE detected_at > now() - interval '90 days'
GROUP BY severity
ORDER BY severity;
```

---

## Incident Management and Error Budgets

Incidents consume error budget. Every SEV1 that causes downtime uses up part of the quarterly availability budget. This creates a direct link between incident management and deployment velocity:

- Good incident management (fast detection, fast recovery) = less budget consumed per incident = more room for deployments
- Poor incident management (slow detection, slow recovery) = more budget consumed = change freezes

This is why investing in monitoring, runbooks, and automation has a direct business impact. It is not just "operational overhead" - it is what allows the product team to keep shipping features.

---

## Summary

| Topic | Key Takeaway |
|-------|-------------|
| Severity levels | SEV1-SEV4 prioritize response effort and communication |
| On-call | Structured rotation with primary/secondary and clear escalation |
| Incident Commander | One person coordinates - does not debug |
| Runbooks | Pre-written procedures for common incidents |
| Blameless PIR | "What allowed the system to fail?" not "who broke it?" |
| MTTD/MTTR/MTTF | Measure and improve detection, recovery, and failure intervals |
| Action items | PIRs are only valuable if action items get completed |
| Error budget link | Good incident management preserves deployment velocity |

**Next:** [BUILD 01 - SLO Definition](../build/01-slo-definition.md)

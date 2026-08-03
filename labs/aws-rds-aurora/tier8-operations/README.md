# Tier 8 - Operations at Scale and Mastery

**Level:** Expert to Master
**Prerequisites:** Tiers 0-7 completed. Deep PostgreSQL knowledge assumed. Production DBA experience strongly recommended.
**Total lab time:** ~6.5 hours across all BUILD guides

---

## What This Tier Covers

Tier 8 is the capstone of this curriculum. It covers the topics that define the difference between a senior DBA and a principal engineer or database architect. You will learn to operate RDS and Aurora at fleet scale - managing costs, enforcing compliance, executing incident response under pressure, and designing systems that can survive real-world failures.

These are not beginner topics. Every section assumes you have already built, tuned, secured, scaled, and backed up RDS instances. This tier asks the harder questions: how do you do all of that across dozens or hundreds of databases, consistently, at the organizational level?

---

## Topics

| ID   | Topic                                      | Build Time |
|------|--------------------------------------------|------------|
| T8.1 | Cost optimization: I/O-Optimized, Reserved Instances, Graviton, Serverless economics | 40 min |
| T8.2 | Fleet management: tagging, Config rules, drift detection, automated remediation | 40 min |
| T8.3 | Observability pipelines: log exports, metric filters, CloudWatch Insights dashboards | 35 min |
| T8.4 | Incident response runbooks: failover, storage exhaustion, connection storms, wraparound | 45 min |
| T8.5 | Capacity planning with pgbench: load testing, soak testing, right-sizing | 45 min |
| T8.6 | Compliance audit: pgaudit, HIPAA, FedRAMP context, log retention | 35 min |
| T8.7 | Disaster recovery design: RTO/RPO targets, Global Database failover drills, cross-region snapshots | 45 min |
| T8.8 | Failure injection and resilience testing with AWS FIS | 40 min |
| T8.9 | Autonomous diagnostics: rule-based health checks, read-only triage, fleet-wide alerting | 40 min |

---

## Directory Structure

```
tier8-operations/
├── README.md                      (this file)
├── concepts/
│   └── operations.md              (conceptual foundation for all T8 topics)
├── build/
│   ├── 01-cost-optimization.md
│   ├── 02-fleet-management.md
│   ├── 03-observability-pipelines.md
│   ├── 04-incident-response-runbooks.md
│   ├── 05-capacity-planning-pgbench.md
│   ├── 06-compliance-audit.md
│   ├── 07-disaster-recovery-design.md
│   ├── 08-failure-injection.md
│   └── 09-autonomous-diagnostics.md
├── use/
│   ├── 01-cost-audit.md
│   ├── 02-incident-simulation.md
│   ├── 03-compliance-review.md
│   ├── 04-dr-drill.md
│   └── 05-fleet-health-check.md
├── survive/
│   ├── config.sh
│   ├── lib/common.sh
│   ├── 01-cost-spike/
│   ├── 02-compliance-violation/
│   ├── 03-connection-storm/
│   ├── 04-wraparound-emergency/
│   └── 05-region-outage/
└── interview/
    └── tier8-interview-questions.md
```

---

## Learning Sequence

1. Read `concepts/operations.md` before any BUILD guide. It sets the architectural framing for everything in this tier.
2. Work through BUILD guides 01-09 in order. Cost and observability come first because they give you visibility into everything else.
3. Complete the USE exercises. These are applied assessments - they expect you to combine knowledge from multiple BUILD guides.
4. Run SURVIVE scenarios only after completing all BUILD guides. These simulate real production incidents.
5. Use the interview questions for self-assessment and interview preparation.

---

## Infrastructure Notes

- All labs use your personal AWS account.
- Some BUILD guides are architecture and decision labs (no live infrastructure required). These are marked with `infra_required: false`.
- Estimated cost for infrastructure-heavy sessions: $5-15 depending on instance types and duration.
- Tear down all resources after each session. RDS charges by the hour. Aurora Serverless v2 charges by ACU-hour.
- Region: use [REGION] consistently throughout all labs. Do not mix regions.
- Several labs require a running Aurora PostgreSQL cluster. Reuse your cluster from Tier 4 or Tier 5 if still running.

---

## SURVIVE Contract

Each SURVIVE scenario follows a three-file contract:

- `inject.sh` - Creates the problem condition. Run this, then diagnose independently.
- `runbook.md` - Step-by-step remediation. Open this only after attempting to diagnose on your own.
- `validate.sh` - Confirms the system is healthy after your fix.

The SURVIVE scenarios at this tier are designed for experienced practitioners. They model incidents that can cause data loss, cascading failures, or regulatory violations. Take them seriously.

---

## Who This Tier Is For

- Senior DBAs moving into principal or staff engineer roles
- Platform engineers who own the database layer for an organization
- Architects designing multi-region or multi-account database platforms
- Engineering managers who need deep technical fluency to lead database teams

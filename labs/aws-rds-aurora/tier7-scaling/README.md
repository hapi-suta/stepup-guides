# Tier 7 - Scaling, Integration, and Modern Patterns

**Level:** Advanced to Expert
**Prerequisites:** Tiers 0-6 completed. Solid intermediate PostgreSQL and AWS knowledge assumed.
**Total lab time:** ~5.5 hours across all BUILD guides

---

## What This Tier Covers

Tier 7 focuses on the patterns and integrations that separate production-grade database architectures from basic deployments. You will learn how to scale RDS and Aurora intelligently, connect databases to modern data pipelines, integrate with serverless compute, and execute migrations with minimal risk.

These are the topics that come up in senior and principal-level DBA interviews, architectural review boards, and production incident post-mortems.

---

## Topics

| ID  | Topic                                    | Build Time |
|-----|------------------------------------------|------------|
| T7.1 | Vertical scaling and storage autoscaling | 35 min |
| T7.2 | Aurora Serverless v2 capacity design     | 40 min |
| T7.3 | Zero-ETL to Redshift and RDS Data API   | 45 min |
| T7.4 | Lambda from RDS PostgreSQL; S3 import/export | 40 min |
| T7.5 | Logical replication and CDC patterns    | 50 min |
| T7.6 | Migration strategies: DMS, Blue/Green, dump/restore | 50 min |

---

## Directory Structure

```
tier7-scaling/
├── README.md                      (this file)
├── concepts/
│   └── scaling.md                 (conceptual foundation for all T7 topics)
├── build/
│   ├── 01-vertical-scaling-storage.md
│   ├── 02-serverless-v2-capacity.md
│   ├── 03-zero-etl-data-api.md
│   ├── 04-lambda-s3-integration.md
│   ├── 05-logical-replication-cdc.md
│   └── 06-migration-strategies.md
├── use/
│   ├── 01-scaling-plan.md
│   ├── 02-data-pipeline.md
│   ├── 03-cdc-setup.md
│   ├── 04-migration-execution.md
│   └── 05-serverless-optimization.md
├── survive/
│   ├── config.sh
│   ├── lib/common.sh
│   ├── 01-replication-slot-bloat/
│   ├── 02-dms-task-failure/
│   ├── 03-lambda-timeout/
│   └── 04-storage-autoscaling-limit/
└── interview/
    └── tier7-interview-questions.md
```

---

## Learning Sequence

1. Read `concepts/scaling.md` before any BUILD guide. It gives you the mental models.
2. Work through BUILD guides 01-06 in order. Each builds on the previous.
3. Complete the USE exercises to apply what you built.
4. Run SURVIVE scenarios after completing all BUILD guides.
5. Use the interview questions for self-assessment.

---

## Infrastructure Notes

- All labs use your personal AWS account.
- Estimated cost per session: $3-8 depending on instance types and duration.
- Tear down instances after each session. RDS charges by the hour even when idle.
- Region: use [REGION] consistently throughout. Do not mix regions within a lab.
- Some labs require VPC setup from Tier 1. Reuse that VPC.

---

## SURVIVE Contract

Each SURVIVE scenario follows a three-file contract:

- `inject.sh` - Creates the problem condition. Run this, then diagnose.
- `runbook.md` - Step-by-step remediation. Use only after attempting independently.
- `validate.sh` - Confirms the system is healthy again after your fix.

Do not read the runbook before attempting to diagnose. The point is building the muscle memory of real incident response.

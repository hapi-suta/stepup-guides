# Tier 3 - Configuration and Extensions

**Level:** Intermediate
**Audience:** DBAs and developers moving beyond default RDS/Aurora settings
**Prerequisites:** Tier 1 (Provisioning) and Tier 2 (Security) completed

---

## What This Tier Covers

Default RDS/Aurora settings work for demos. Production workloads need tuning. This tier covers every configuration lever AWS gives you - parameter groups, extensions, pgvector, trusted language extensions, foreign data wrappers, and engine version management.

By the end of this tier you will be able to:

- Create and manage custom parameter groups for RDS and Aurora
- Install and configure key PostgreSQL extensions on RDS/Aurora
- Set up pgvector for AI/ML similarity search workloads
- Build safe custom extensions with Trusted Language Extensions (TLE)
- Query remote databases using Foreign Data Wrappers
- Plan and execute major version upgrades with confidence

---

## Folder Structure

```
tier3-configuration/
├── README.md                    <- you are here
├── concepts/
│   └── configuration.md         <- deep concepts with diagrams and tables
├── build/
│   ├── 01-parameter-groups.md   <- 40 min - custom parameter groups
│   ├── 02-option-groups.md      <- 20 min - option groups overview
│   ├── 03-extensions-core.md    <- 40 min - pg_stat_statements, pgaudit, pg_repack
│   ├── 04-pgvector.md           <- 35 min - vector search for AI/ML
│   ├── 05-trusted-language-extensions.md  <- 30 min - TLE
│   ├── 06-foreign-data-wrappers.md        <- 30 min - postgres_fdw
│   └── 07-engine-versions.md    <- 20 min - versions and upgrades
├── use/
│   ├── 01-parameter-tuning.md   <- tune params for a real workload
│   ├── 02-extension-setup.md    <- monitoring stack with extensions
│   ├── 03-vector-search.md      <- semantic search with pgvector
│   ├── 04-cross-database-queries.md <- cross-instance queries with FDW
│   └── 05-version-upgrade-plan.md   <- plan a major version upgrade
├── survive/
│   ├── config.sh                <- shared environment config
│   ├── lib/common.sh            <- shared shell functions
│   ├── 01-bad-parameter-change/ <- shared_buffers too high
│   ├── 02-extension-missing/    <- dropped extension breaks app
│   ├── 03-pgvector-index-wrong/ <- wrong index type, slow queries
│   └── 04-fdw-connection-broken/ <- foreign server unreachable
└── interview/
    └── tier3-interview-questions.md  <- Junior through Principal questions
```

---

## Estimated Time

| Section | Time |
|---|---|
| Concepts | 45 min |
| BUILD 01 - Parameter Groups | 40 min |
| BUILD 02 - Option Groups | 20 min |
| BUILD 03 - Core Extensions | 40 min |
| BUILD 04 - pgvector | 35 min |
| BUILD 05 - TLE | 30 min |
| BUILD 06 - FDW | 30 min |
| BUILD 07 - Engine Versions | 20 min |
| USE Exercises (5) | 90 min |
| SURVIVE Scenarios (4) | 60 min |
| **Total** | **~6.5 hours** |

---

## AWS Services Used

- Amazon RDS (PostgreSQL)
- Amazon Aurora (PostgreSQL-compatible)
- AWS CLI v2
- psql (PostgreSQL client)

---

## Cost Estimate

Running these labs uses:
- 1-2 RDS db.t3.micro instances
- Storage: 20 GB each
- Estimated cost: **$0.02-0.05/hour** per instance

Stop or delete instances after each session to avoid charges.

---

## Lab Prerequisites

- AWS account with IAM permissions for RDS
- AWS CLI configured (`aws configure`)
- psql installed locally or on an EC2 jump host
- A VPC with a private subnet group (from Tier 1)
- A security group allowing your IP on port 5432

---

## Quick Reference - Key Commands

```bash
# List parameter groups
aws rds describe-db-parameter-groups

# List available extensions in a DB
psql -h [ENDPOINT] -U [USER] -d [DBNAME] -c "SELECT * FROM pg_available_extensions ORDER BY name;"

# Check current parameter values
aws rds describe-db-parameters --db-parameter-group-name [GROUP-NAME]

# List available engine versions
aws rds describe-db-engine-versions --engine postgres --query 'DBEngineVersions[*].EngineVersion'
```

---

## Navigation

- Previous tier: [Tier 2 - Security](../tier2-security/README.md)
- Next tier: [Tier 4 - Availability](../tier4-availability/README.md)
- Back to curriculum: [AWS RDS/Aurora Curriculum](../README.md)

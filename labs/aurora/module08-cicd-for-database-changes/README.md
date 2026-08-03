# Module 08: CI/CD for Database Changes

**Track:** DevOps DBA Training
**Duration:** ~12 hours
**Week:** 6
**Prerequisites:** Module 01-07

---

## What You Will Learn

This module brings DevOps discipline to database schema changes. By the end, you will:

- Understand why database changes need their own pipeline - not just application CI/CD
- Write versioned, idempotent schema migrations with Flyway
- Build GitHub Actions workflows that validate, test, and deploy migrations
- Implement safeguards - lock timeouts, dry runs, approval gates
- Manage Aurora infrastructure as code with Terraform
- Combine Terraform (infrastructure) and Flyway (schema) in a single pipeline
- Review database pull requests with confidence

---

## Module Contents

### Concepts (read first)
1. [Database Change Management](concepts/01-database-change-management.md) - Why ad-hoc DDL fails, migration patterns, versioning strategies, rollback tradeoffs
2. [CI/CD Pipelines for Databases](concepts/02-cicd-pipelines-for-databases.md) - Pipeline stages, testing strategies, blue-green schema deploys, approval gates

### BUILD (hands-on, follow step by step)
1. [Schema Migration Fundamentals](build/01-schema-migration-fundamentals.md) - Migration files, up/down, version control, first migration (45 min)
2. [Flyway Setup](build/02-flyway-setup.md) - Install Flyway, create project, multi-env configs, dedicated user (45 min)
3. [GitHub Actions Pipeline](build/03-github-actions-pipeline.md) - CI pipeline lint/test/apply, CD with approval gates (60 min)
4. [Zero-Downtime Migrations](build/04-zero-downtime-migrations.md) - Online DDL, concurrent index, expand-contract (60 min)
5. [Rollback Strategies](build/05-rollback-strategies.md) - When/how to rollback, forward-only, flyway repair (45 min)
6. [Terraform and Flyway Together](build/06-terraform-and-flyway-together.md) - IaC + migrations in one pipeline, state management (60 min)

### USE (practice with less hand-holding)
1. [Migration Writing Exercise](use/01-migration-writing-exercise.md)
2. [Pipeline Building Exercise](use/02-pipeline-building-exercise.md)
3. [Rollback Strategy Exercise](use/03-rollback-strategy-exercise.md)
4. [Terraform Refactoring Exercise](use/04-terraform-refactoring-exercise.md)
5. [Code Review Exercise](use/05-code-review-exercise.md)

### SURVIVE (break it, fix it)
1. [Migration Lock Timeout](survive/01-migration-lock-timeout/) - ALTER TABLE blocked by long-running query, unblock it safely
2. [Rollback Failure](survive/02-rollback-failure/) - Migration partially applied, undo script fails, recover manually
3. [Pipeline Deploys to Production](survive/03-pipeline-deploys-to-production/) - Wrong environment targeted, assess damage, implement guardrails

### Interview Prep
1. [Interview Questions](interview/01-interview-prep.md) - 15-20 questions, Junior to Senior

---

## What is Next

After completing this module, you will move to [Module 09: Operations at Scale and SRE](../module09-operations-at-scale-sre/) where you define SLOs, automate operational tasks, and practice incident management.

---

## Cost Warning

GitHub Actions free tier provides 2,000 minutes per month - more than enough for these labs. Flyway community edition is free. Terraform is free and open source. The only AWS cost is your existing Aurora cluster. Clone-based migration testing (BUILD 04) may add brief snapshot charges.

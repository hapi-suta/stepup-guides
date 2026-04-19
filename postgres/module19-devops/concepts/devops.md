# Module 19 - Concepts: PostgreSQL DevOps and CI/CD

## Database Change Management Philosophy

Database changes are fundamentally different from application code changes. You can roll back a bad deployment of application code by deploying the previous version. You cannot easily "undeploy" a database migration that dropped a column with 10 million rows of data.

This asymmetry drives everything in database DevOps:

- **Application code is stateless, databases are stateful.** Rolling back code is trivial. Rolling back data changes ranges from difficult to impossible.
- **Database changes are permanent by default.** A `DROP TABLE` is permanent. An `ALTER TABLE DROP COLUMN` is permanent. There is no undo button.
- **Database changes affect all applications simultaneously.** Unlike microservices where you can deploy independently, a schema change affects every application that uses that table at the same moment.

The core principle: **treat database changes with more caution than application changes, not less.**

---

## Schema Migration Patterns

### Sequential Migrations

The simplest pattern. Changes are numbered and applied in order.

```
V1__create_users.sql
V2__add_email_column.sql
V3__create_orders.sql
```

Strengths: Simple to understand, easy to audit. Weaknesses: Requires coordination when multiple developers work on migrations.

### The Expand/Contract Pattern

The safest pattern for zero-downtime deployments. Every destructive change is split into three phases:

**Phase 1 - Expand:** Add the new thing alongside the old thing.

```sql
-- Adding a new column format? Don't drop the old one yet.
ALTER TABLE users ADD COLUMN full_name VARCHAR(200);
```

**Phase 2 - Migrate:** Move data from old to new. Update application code to use the new thing.

```sql
UPDATE users SET full_name = first_name || ' ' || last_name;
-- Deploy application code that reads/writes full_name
```

**Phase 3 - Contract:** Remove the old thing after confirming nothing uses it.

```sql
-- Only after verifying no queries reference the old columns
ALTER TABLE users DROP COLUMN first_name;
ALTER TABLE users DROP COLUMN last_name;
```

The key insight: Phase 3 happens days or weeks after Phase 1, not in the same deployment. This gives you time to verify and roll back if needed.

### Idempotent Migrations

Every migration should be safe to run twice. Use guards:

```sql
CREATE TABLE IF NOT EXISTS users (...);
CREATE INDEX IF NOT EXISTS idx_users_email ON users (email);
ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(20);
DROP INDEX IF EXISTS old_index_name;
```

Why this matters: In a failure scenario, you may need to re-run a migration. If it is not idempotent, the second run fails and makes the situation worse.

---

## Blue/Green Deployments for Databases

Blue/green deployment for applications is straightforward: run two identical environments, deploy to the inactive one, switch traffic. Databases make this harder because both environments need the same data.

### The Shared Database Approach

Both blue and green application environments connect to the same database. Schema changes must be backward compatible:

1. **New code must work with old schema** (during rollback)
2. **Old code must work with new schema** (during canary/gradual rollout)

This means: never rename columns, never change data types without a new column, never drop columns that old code reads.

### The Dual Database Approach

Maintain two database instances. Before switching traffic:

1. Restore the latest backup to the green database
2. Apply migrations to green
3. Run full test suite against green
4. Switch traffic to green
5. Keep blue running as rollback target

Drawback: Data written between the backup and the switch is lost unless you replay it. This works for read-heavy applications but not for write-heavy ones.

### The Logical Replication Approach

Use PostgreSQL logical replication to keep both databases in sync:

1. Set up logical replication from blue to green
2. Apply schema changes to green (compatible with replication)
3. Verify green is caught up
4. Switch traffic to green
5. Reverse replication direction for future deployments

This is the most sophisticated approach and requires careful planning of replication-compatible migrations.

---

## Database Branching Concepts

Application developers create feature branches freely. Database branching is harder because databases contain state.

### Conceptual Model

Think of database branches as lightweight copies of a database at a point in time:

- **Main branch**: Production schema + reference data
- **Feature branch**: Copy of main + developer's schema changes
- **PR merge**: Migrations from feature branch applied to main

### Implementation Approaches

**Copy-on-write filesystems (ZFS/Btrfs):** Clone the database at the filesystem level. Near-instant, space-efficient.

**pg_dump/pg_restore:** Dump main, restore to a new database, apply branch migrations. Simple but slow for large databases.

**Logical replication:** Replicate main to a branch database, apply changes on the branch. Near-real-time but complex.

**Cloud-native branching (Neon, Supabase):** Some PostgreSQL cloud providers offer instant database branching as a service. Useful for CI/CD where each pull request gets its own database.

### Schema Diff as PR Check

When a feature branch modifies the database, the CI pipeline should:

1. Create a fresh database from main schema
2. Apply the branch's migrations
3. Dump the resulting schema
4. Diff against the expected schema
5. Include the diff in the PR for review

This makes database changes as reviewable as code changes.

---

## Testing Strategies for Schema Changes

### Level 1: Syntax Validation

Run migrations against an empty database. Catches typos, missing references, and syntax errors.

```bash
# Create empty DB, apply migrations, check for errors
createdb test_syntax
psql -d test_syntax -v ON_ERROR_STOP=1 -f V1__migration.sql
```

### Level 2: Data Compatibility

Run migrations against a database with realistic data. Catches:
- Type conversion failures
- Constraint violations on existing data
- Performance issues with large tables

```bash
# Restore production backup, apply migrations
pg_restore -d test_data production_backup.dump
psql -d test_data -v ON_ERROR_STOP=1 -f V1__migration.sql
```

### Level 3: Application Integration

Run the application test suite against the migrated database. Catches:
- ORM mapping failures
- Query plan regressions
- Application logic that depends on old schema

### Level 4: Performance Regression

Run load tests against the migrated database. Catches:
- Missing indexes on new queries
- Lock contention from new constraints
- Slow queries caused by schema changes

### Level 5: Rollback Testing

Verify that the rollback procedure works:
1. Apply the migration
2. Run the rollback
3. Verify the schema is back to the pre-migration state
4. Verify data is intact

---

## Infrastructure as Code for Databases

### What to Manage with IaC

| Component | Tool | Why |
|-----------|------|-----|
| Cloud instances (RDS, Aurora) | Terraform | Provision and configure the infrastructure |
| PostgreSQL settings | Ansible | Deploy postgresql.conf, pg_hba.conf consistently |
| Schema (tables, indexes) | Flyway/Liquibase | Track and apply schema changes |
| Roles and permissions | Terraform (PG provider) or Ansible | Consistent access control |
| Extensions | Terraform or migration scripts | Ensure required extensions are installed |
| Monitoring | Ansible + Terraform | Deploy exporters, configure Prometheus |

### The IaC Feedback Loop

```
Code change -> Pull Request -> Review -> Merge -> CI/CD -> Deploy -> Monitor -> Alert -> Fix -> Code change
```

Every component in this loop should be automated:
- **Code change**: Terraform/Ansible files in Git
- **Pull Request**: Automated plan/diff in PR comments
- **Review**: Human review of the plan output
- **CI/CD**: Automated apply on merge to main
- **Deploy**: Terraform apply, Ansible playbook
- **Monitor**: Prometheus + Grafana
- **Alert**: Alertmanager -> PagerDuty
- **Fix**: New code change (back to the start)

### Drift Detection

Configuration drift is when reality diverges from what IaC defines. Common causes:
- Manual changes via `ALTER SYSTEM` or AWS console
- Failed deployments that partially applied
- Shadow IT (someone creates resources outside the pipeline)

Detection methods:
- `terraform plan` on a schedule (shows diffs between state and reality)
- Ansible `--check --diff` on a schedule
- Custom scripts comparing pg_settings against expected values
- AWS Config rules for RDS parameter group changes

---

## The Observability Pyramid

### Metrics (Quantitative, Aggregated)

Metrics tell you **what** is happening at a high level. They are numeric time series collected at regular intervals.

Key PostgreSQL metrics:
- **Transactions per second (TPS)** - Overall throughput
- **Active connections** - Current load
- **Cache hit ratio** - Memory efficiency (should be > 95%)
- **Replication lag** - Standby freshness
- **Dead tuples** - Bloat / vacuum health
- **Lock waits** - Contention

Tools: Prometheus + postgres_exporter + Grafana

### Logs (Qualitative, Detailed)

Logs tell you **why** something happened. They are text records of individual events.

Key PostgreSQL logs:
- **Slow queries** (`log_min_duration_statement`) - Which queries are slow
- **Connection events** - Who connected and disconnected
- **Lock waits** - Which queries are blocking each other
- **Checkpoints** - I/O pressure indicators
- **Errors** - Failed queries, permission denials

Tools: rsyslog, Fluentd, CloudWatch Logs, Loki

### Traces (Contextual, Request-Scoped)

Traces tell you **how** a request flows through the system. Each trace follows a single request from the application through middleware, database queries, and back.

For databases, traces show:
- Which application request caused this query
- How long the database query took vs total request time
- Whether the query was part of a transaction with other queries

Tools: OpenTelemetry, Jaeger, Datadog APM

### Putting It Together

When debugging a production issue:

1. **Metrics** alert you: "TPS dropped 50%"
2. **Logs** narrow it down: "Slow query on orders table taking 30s"
3. **Traces** give context: "The slow query is caused by a new API endpoint that joins 5 tables without an index"

You need all three layers. Metrics without logs is like a fire alarm without knowing where the fire is. Logs without metrics is like reading every email to figure out company revenue.

---

## On-Call Runbook Automation

### The Runbook Hierarchy

1. **Alert fires** - Prometheus detects the problem
2. **Human notified** - PagerDuty/OpsGenie pages the on-call engineer
3. **Runbook consulted** - The alert links to a specific runbook
4. **Steps executed** - The engineer follows the runbook
5. **Problem resolved** - The engineer marks the incident resolved
6. **Post-mortem** - The team reviews what happened and improves the runbook

### What Makes a Good Runbook

A runbook should answer these questions in order:
1. **What is happening?** (1-2 sentences describing the symptom)
2. **How bad is it?** (Impact assessment: users affected, data at risk)
3. **How do I verify?** (Commands to confirm the problem)
4. **How do I fix it?** (Step-by-step commands, copy-paste ready)
5. **How do I verify the fix?** (Commands to confirm it is working)
6. **What prevents it next time?** (Root cause and permanent fix)

### Automation Levels

**Level 0 - Manual:** Engineer SSHs in and runs commands by hand. Error-prone, slow.

**Level 1 - Documented:** Runbook with copy-paste commands. Faster, fewer mistakes.

**Level 2 - Scripted:** A single script the engineer runs: `./fix-replication-lag.sh`. Even faster.

**Level 3 - Semi-automated:** Script runs automatically but waits for human approval before destructive actions.

**Level 4 - Fully automated:** The system detects the problem and fixes it without human intervention. Only safe for well-understood, low-risk issues (like clearing a full /tmp directory).

Most production database issues should be at Level 1-2. Level 4 automation for databases is dangerous because the blast radius of a wrong fix is too high.

---

## Cost of Downtime and SLA Math

### Calculating Downtime Cost

The formula:

```
Hourly Cost = (Revenue per hour) + (Productivity loss per hour) + (Reputation damage estimate)
```

For a company making $10M/year from a web application:
- Revenue per hour: $10M / 8760 hours = $1,142/hour
- Productivity: 50 employees unable to work = 50 x $50/hour = $2,500/hour
- Reputation: Hard to quantify, but consider customer churn

**Total downtime cost: roughly $3,642/hour**

This is why investing in monitoring, IaC, and CI/CD pays for itself quickly.

### SLA Nines

| SLA | Annual Downtime | Monthly Downtime |
|-----|-----------------|------------------|
| 99% (two nines) | 3.65 days | 7.3 hours |
| 99.9% (three nines) | 8.77 hours | 43.8 minutes |
| 99.95% | 4.38 hours | 21.9 minutes |
| 99.99% (four nines) | 52.6 minutes | 4.4 minutes |
| 99.999% (five nines) | 5.26 minutes | 26.3 seconds |

Each additional "nine" is exponentially harder and more expensive to achieve.

### What Buys You Nines

| Practice | Adds Approximately |
|----------|--------------------|
| Automated monitoring + alerting | Gets you to 99% |
| Documented runbooks | Gets you to 99.5% |
| Automated failover (replication) | Gets you to 99.9% |
| Multi-region / multi-AZ | Gets you to 99.95% |
| Chaos engineering + automated remediation | Gets you to 99.99% |

### RTO and RPO

**RTO (Recovery Time Objective):** How long until the system is back up.
**RPO (Recovery Point Objective):** How much data you can afford to lose.

| Backup Strategy | RTO | RPO |
|-----------------|-----|-----|
| Nightly pg_dump | 1-4 hours | Up to 24 hours |
| Streaming replication | Minutes | Seconds |
| Synchronous replication | Seconds | Zero |
| Multi-region active-active | Near-zero | Near-zero |

The cost increases dramatically from top to bottom. Choose the strategy that matches your business requirements, not the fanciest technology.

---

## Summary

Database DevOps is about applying software engineering discipline to database operations:

1. **Version everything** - Schema changes, configurations, infrastructure definitions
2. **Automate everything repeatable** - Migrations, deployments, monitoring setup
3. **Test before deploying** - Schema changes against real data, load tests against benchmarks
4. **Monitor everything in production** - Metrics, logs, and traces at every layer
5. **Plan for failure** - Runbooks, automated failover, and tested backup/restore
6. **Measure the business impact** - SLAs, downtime cost, RTO/RPO

The goal is not to prevent all failures - that is impossible. The goal is to detect failures fast, fix them fast, and prevent the same failure from happening twice.

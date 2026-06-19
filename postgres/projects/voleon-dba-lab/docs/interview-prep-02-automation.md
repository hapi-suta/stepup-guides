# Interview Prep 02 - Automation & Configuration Management

- **Date:** Wednesday, June 24, 2026, 6:00-7:00 PM EDT
- **Interviewer:** Mark Selby, Senior Systems Infrastructure Engineer, The Voleon Group
- **Format:** 1 hour Zoom

---

## 1. What Mark Will Likely Focus On

Mark is a Senior Systems Infrastructure Engineer - not a DBA. He manages the platform that databases run on. His priorities differ from a database-focused interviewer.

**What he cares about:**
- Can you work as part of an infrastructure team, not just as a siloed DBA?
- Do you treat databases as infrastructure (code-managed, reproducible, version-controlled)?
- Can you automate database operations at fleet scale, not just manage one server by hand?
- Do you understand IaC philosophy - immutable infra, drift detection, GitOps workflows?

**Expect deep dives on:**
- Ansible playbook structure, roles, handlers, templates, vault, inventory patterns
- Terraform workflow (plan/apply/state), module design, state management
- CI/CD pipelines for infrastructure and database changes
- Config management tool tradeoffs (Ansible vs Puppet vs Chef) - Voleon uses all three
- How you collaborate with infra engineers on shared tooling

**Watch for:**
- He may push on edge cases: "What happens when your Ansible run fails halfway through a rolling restart?"
- He may test your opinions: "Why Ansible over Puppet for database management?"
- He will likely ask about testing automation before production deployment

---

## 2. Top 15 Questions and Answer Outlines

### Q1: "How do you manage PostgreSQL configuration across a fleet with Ansible?"

- Ansible role with Jinja2 templates for `postgresql.conf` and `pg_hba.conf`
- Group vars define cluster-level settings (shared_buffers, work_mem scaled to host RAM)
- Host vars handle per-instance overrides (port, data directory, replication role)
- Handlers restart or reload PG only when config files actually change
- `serial: 1` for rolling deploys - never touch all nodes at once
- Validate config with `pg_ctl reload` in check mode before applying

### Q2: "Walk me through your Terraform workflow for provisioning a new database server"

- Module defines: EC2/VM instance, EBS volumes (separate for data/WAL/log), security groups, DNS
- `terraform plan` generates changeset - reviewed in PR before merge
- Apply runs through CI (Jenkins/GitHub Actions) - no local applies to production
- State stored in S3 with DynamoDB locking - never local state for shared infra
- After Terraform provisions the VM, Ansible takes over for PG installation and config
- Tags on every resource: environment, team, service, cost-center

### Q3: "How do you handle secrets management in your automation?"

- Ansible Vault for PG passwords, replication credentials, SSL certs
- Vault-encrypted files committed to git - decrypted at runtime with vault password file
- Terraform secrets: AWS Secrets Manager or HashiCorp Vault as data sources
- Never store passwords in terraform.tfstate - use `sensitive = true` on outputs
- CI/CD: secrets injected as environment variables from Jenkins credential store
- Rotation: Ansible playbook to rotate PG passwords, update connection strings, restart apps

### Q4: "What's your approach to configuration drift detection?"

- Ansible in `--check --diff` mode on a schedule (cron or Jenkins job) - reports drift without changing anything
- Compare live `postgresql.conf` against template-rendered expected config
- Alert on drift via monitoring (PagerDuty/Slack) - someone manually changed a setting
- Terraform: `terraform plan` in CI detects infra drift (instance type changed, security group modified)
- Prevention: lock down SSH access, no manual config changes - all changes through Ansible PRs
- When drift is found: investigate why, fix root cause, then enforce correct config

### Q5: "Describe a CI/CD pipeline for database changes"

- Developer writes migration SQL, commits to repo with version number (e.g., V042_add_index.sql)
- PR triggers: lint SQL (sqlfluff), dry-run against staging clone, estimate lock duration
- Merge to main triggers deployment: Flyway/sqitch applies migration to staging first
- Staging validation: run integration tests, check query plans, verify no long locks
- Production deploy: Jenkins pipeline with manual approval gate before prod apply
- Rollback plan: every migration has a corresponding down/undo script tested in CI

### Q6: "How do you handle rolling updates to database configuration?"

- Ansible `serial: 1` or `serial: "25%"` to update one node at a time
- Pre-task: verify replication lag < threshold, node is healthy
- Apply config change, reload PG (not restart unless required - e.g., shared_buffers)
- Post-task: wait for node to rejoin replication, verify lag recovers
- If any node fails health check post-change, `max_fail_percentage: 0` halts the rollout
- For settings requiring restart: failover primary to standby first, restart old primary, then swap back

### Q7: "What's the boundary between Terraform and Ansible in your workflow?"

- Terraform owns infrastructure lifecycle: VMs, networks, storage, DNS, security groups
- Ansible owns software lifecycle: install PG, configure, manage users, deploy extensions
- Boundary is "OS boot" - Terraform creates the machine, Ansible configures it
- Terraform outputs (IPs, hostnames) feed into Ansible dynamic inventory
- Never use Terraform provisioners for config management - they are a one-shot trap
- Both live in git, both run through CI, both require PR review

### Q8: "How do you test infrastructure changes before applying to production?"

- Terraform: `plan` output reviewed in PR - automated comment on the PR with plan diff
- Ansible: `--check --diff` against staging environment first
- Molecule for Ansible role testing - spins up containers, applies role, runs Testinfra assertions
- Staging environment mirrors production topology (primary + standbys + pgbouncer)
- For risky changes: provision a throwaway clone from production backup, test against it
- Canary pattern: apply to one production node, monitor for 30 minutes, then roll to rest

### Q9: "Describe your approach to disaster recovery automation"

- Automated daily base backups via pgBackRest, WAL archiving continuous to S3
- Ansible playbook for full DR restore: provision new instance, restore backup, apply WAL, promote
- Runbook-as-code: DR playbook tested monthly against production backups
- Recovery time validated: "Can we restore 2TB database in under 1 hour?" - timed and measured
- Failover automation: repmgr or Patroni handles automatic standby promotion
- Post-failover: Ansible reconfigures pgbouncer, updates DNS, notifies monitoring

### Q10: "How do you handle database schema migrations in a CI/CD pipeline?"

- Migration tool (Flyway or sqitch) version-controls every DDL change
- CI runs migrations against a disposable test database (Docker PG instance)
- Large table changes: use `pg_repack` or `CREATE INDEX CONCURRENTLY` - never block writes
- Lock timeout set in migration: `SET lock_timeout = '5s'` - fail fast, retry later
- Blue/green for breaking schema changes: deploy new schema, migrate app, drop old columns later
- Backward compatibility rule: every migration must work with current AND previous app version

### Q11: "What's your experience with Puppet or Chef? How do they compare to Ansible?"

- Used Puppet in environments with 500+ nodes where agent-based enforcement was required
- Puppet excels at continuous enforcement (agent runs every 30 min, corrects drift automatically)
- Ansible advantage for databases: agentless, push-based, easier to orchestrate ordered operations
- Chef: Ruby DSL is powerful but higher learning curve - better for teams already in Ruby ecosystem
- For databases specifically, Ansible wins because orchestration order matters (failover before restart)
- In mixed environments (Voleon uses all three): Ansible for database ops, Puppet/Chef for OS baseline

### Q12: "How do you ensure idempotency in your database automation?"

- Ansible modules are idempotent by design - `postgresql_user` checks if user exists before creating
- Custom scripts: always use `IF NOT EXISTS` / `IF EXISTS` guards on DDL
- Config templates: Ansible only triggers handler when file content actually changes (checksum compare)
- For data operations: use upserts (`ON CONFLICT DO UPDATE`) instead of raw inserts
- Test idempotency: run playbook twice in CI - second run should report zero changes
- Avoid `shell` and `command` modules when a proper Ansible module exists

### Q13: "Walk me through automating a failover procedure"

- Monitoring detects primary failure (Patroni heartbeat, repmgr health check, or custom script)
- Automated: Patroni promotes best standby (lowest replication lag, same timeline)
- Semi-automated (my preference for critical systems): alert fires, DBA reviews, triggers Ansible playbook
- Playbook steps: verify primary is truly down, pick promotion target, promote, reconfigure pgbouncer, update DNS
- Post-failover: rebuild old primary as new standby, verify replication streaming
- Notification: Slack/PagerDuty with promotion details, new topology diagram, replication status

### Q14: "How do you manage Ansible inventory for a large fleet?"

- Dynamic inventory script that queries AWS EC2 API (or internal CMDB) by tags
- Groups by: environment (prod/staging), datacenter (us-east/us-west), role (primary/standby/pgbouncer)
- Group vars set environment-specific configs (prod gets more memory, staging gets smaller instances)
- Inventory plugin for AWS: `aws_ec2` plugin with keyed groups based on instance tags
- For 15,000+ databases: inventory cached with TTL to avoid hammering AWS API on every run
- Host patterns: `ansible-playbook site.yml --limit "tag_env_prod:&tag_role_primary"` for targeted runs

### Q15: "What monitoring do you set up to validate automation changes?"

- Pre-change: snapshot key metrics (replication lag, query latency p99, connections, TPS)
- Post-change: compare same metrics - alert if regression detected within 30 minutes
- Ansible callback plugin logs every run to central logging (ELK) with play/task timing
- Terraform: CloudWatch alarms on provisioned resources (disk space, CPU, network)
- Custom Python script: after config change, run `pg_stat_activity` and `pg_stat_replication` checks
- Dashboard: Grafana panel showing "last Ansible run" timestamp and status per host

---

## 3. "Tell Me About a Time..." Stories (STAR Format)

### Story 1: Fleet-Wide PG Config Rollout Across Multiple Datacenters

**Situation:** Needed to change `max_connections` from 200 to 500 across 400+ PostgreSQL instances in 11 datacenters. This required a restart, not just a reload - high risk of downtime.

**Task:** Roll out the change with zero downtime across all environments within a maintenance window.

**Action:**
- Built Ansible playbook with `serial: 1` and health checks between each node
- For primary servers: automated failover to standby, restarted old primary, failed back
- Pre-flight check: verified all standbys were in sync before touching any cluster
- Staged rollout: dev (Monday), staging (Tuesday), prod non-critical (Wednesday), prod critical (Thursday)
- Each stage had a 24-hour bake period before proceeding

**Result:** 400+ instances updated over 4 days with zero unplanned downtime. Two nodes had issues (full pg_wal directory) caught by pre-flight checks before they caused problems. Playbook now runs quarterly for config updates.

### Story 2: Building a CI/CD Pipeline for Database Migrations

**Situation:** Development team was applying migrations manually via SSH. A bad migration dropped a column in production - 2 hours of downtime and data recovery from backup.

**Task:** Build an automated, safe migration pipeline that prevents human error.

**Action:**
- Implemented Flyway for version-controlled migrations in the application repo
- Jenkins pipeline: lint SQL, apply to Docker PG, run integration tests, deploy to staging, manual approval gate, deploy to prod
- Added safety checks: reject `DROP COLUMN` without prior deprecation period, reject `ALTER TABLE` on tables > 1GB without `CONCURRENTLY` keyword
- Built automatic rollback: if post-migration health check fails, apply down migration within 5 minutes

**Result:** Zero migration-related incidents in 18 months after implementation. Migration deploy time dropped from 45 minutes (manual SSH) to 8 minutes (automated pipeline). Developers now own their migrations with guardrails instead of waiting on DBA team.

### Story 3: Recovering from a Bad Automated Config Push

**Situation:** An Ansible playbook pushed `shared_buffers = 128GB` to a server with only 64GB RAM. PG refused to start after restart. This was a production primary serving trading analytics.

**Task:** Restore service immediately, then fix the automation to prevent recurrence.

**Action:**
- Immediate: promoted standby to primary (repmgr, 30 seconds), pointed pgbouncer to new primary
- Fixed the downed server: manually corrected `postgresql.conf`, started PG, rebuilt as standby
- Root cause: group_vars set shared_buffers as absolute value instead of percentage of RAM
- Fix: changed template to `shared_buffers = {{ (ansible_memtotal_mb * 0.25) | int }}MB` - calculated from actual host memory
- Added pre-flight assertion: `assert: that: pg_shared_buffers_mb < ansible_memtotal_mb * 0.5`

**Result:** Total downtime was 45 seconds (time to promote standby). Template now calculates memory-dependent settings dynamically. Pre-flight assertions block unsafe configs before they reach any server. Added this pattern to all memory-related PG settings.

---

## 4. Questions to Ask Mark

1. **"How does Voleon handle the boundary between infrastructure automation and database-specific automation? Is there a shared Ansible codebase, or do teams maintain separate repos?"**
   - Shows you think about team collaboration and code ownership

2. **"What does your change management process look like for infrastructure changes - do you use PR-based review with plan output, or is there a separate change advisory board?"**
   - Signals you understand regulated/careful environments (quant fund = careful)

3. **"You run Ansible, Puppet, and Chef - is there a strategy to consolidate, or do different tools own different layers? How would the DBA role fit into that?"**
   - Directly relevant to your day-to-day if hired - shows you read their stack

4. **"How do you handle database provisioning on Kubernetes vs bare metal? Are there PostgreSQL workloads on Kubernetes, or is it strictly VM-based?"**
   - Tests whether PG runs on K8s (operators like CloudNativePG) or traditional VMs

5. **"What does a typical on-call look like for infrastructure issues that involve databases - does the infra team handle first response, or does it escalate to the DBA directly?"**
   - Practical question about incident response and team boundaries

---

## 5. Quick Reference - Automation Concepts Cheat Sheet

### Ansible
| Term | What It Means |
|------|--------------|
| **Playbook** | YAML file defining tasks to run against hosts |
| **Role** | Reusable, structured collection of tasks/templates/handlers (e.g., `postgresql` role) |
| **Handler** | Task that runs only when notified by another task (e.g., restart PG after config change) |
| **Template** | Jinja2 file rendered with variables (e.g., `postgresql.conf.j2`) |
| **Vault** | Encrypts sensitive data (passwords, keys) in git-committed files |
| **serial** | Controls how many hosts to update at once (rolling deploys) |
| **Check mode** | `--check` runs playbook without making changes (dry run) |
| **Idempotency** | Running the same playbook twice produces the same result - no unintended side effects |
| **Inventory** | List of hosts, grouped by role/env/datacenter - static file or dynamic script |
| **Callback plugin** | Hook into Ansible events for logging, notifications, metrics |

### Terraform
| Term | What It Means |
|------|--------------|
| **Plan** | Preview of what Terraform will create/change/destroy - review before apply |
| **Apply** | Execute the planned changes against real infrastructure |
| **State** | JSON file tracking what Terraform manages - the source of truth for drift detection |
| **Module** | Reusable Terraform package (e.g., `module "pg_server"` with standard config) |
| **Provider** | Plugin for a specific platform (AWS, GCP, OpenStack) |
| **Import** | Bring existing infrastructure under Terraform management |
| **Workspace** | Isolated state environments (dev/staging/prod) in one codebase |
| **Remote state** | State stored in S3/GCS with locking - required for team use |
| **Data source** | Read-only query for existing resources (e.g., look up AMI ID) |

### CI/CD (Jenkins / GitHub Actions)
| Term | What It Means |
|------|--------------|
| **Pipeline** | Defined sequence of stages (build, test, deploy) |
| **Stage** | Logical grouping of steps (e.g., "Deploy to Staging") |
| **Jenkinsfile** | Pipeline-as-code - version controlled in the repo |
| **Credentials** | Secrets stored in Jenkins, injected as env vars at runtime |
| **Approval gate** | Manual approval required before proceeding (e.g., prod deploy) |
| **Artifact** | Output of a build stage (e.g., migration SQL bundle, Ansible role tarball) |

### General Concepts
| Term | What It Means |
|------|--------------|
| **IaC** | Infrastructure as Code - manage infra through version-controlled definitions |
| **GitOps** | Git as single source of truth - merge to main triggers deploy |
| **Drift detection** | Finding differences between desired state (code) and actual state (running infra) |
| **Rolling deploy** | Update one node at a time, verify health between each |
| **Blue/green** | Two identical environments - switch traffic from old to new |
| **Canary** | Deploy to small subset first, monitor, then roll to rest |
| **Immutable infra** | Never patch in place - replace with new, correctly configured instance |

---

## 6. Voleon-Specific Talking Points

### Ansible for PG Operational Management
- Position Ansible not just as a deployment tool but as an ongoing operational tool
- Daily operations automated: user management, permission grants, extension installs, config tuning
- Ansible playbooks replace runbooks - instead of documenting steps, codify them
- Example: "When a new analyst joins, I run `ansible-playbook add_user.yml -e 'username=jsmith role=readonly'` - it creates the PG user, grants schema permissions, adds to pgbouncer, and updates monitoring"

### Terraform for VM Provisioning
- Voleon likely uses OpenStack internally (quant funds often do) plus some AWS
- Emphasize Terraform's multi-provider capability - same workflow for OpenStack and AWS
- Module design: one `pg-server` module that works across providers, abstracting cloud specifics
- State management in a team: remote state with locking prevents concurrent applies

### Jenkins Pipelines for DB Migrations
- Voleon uses Jenkins - speak their language, not GitHub Actions
- Jenkinsfile in the repo, shared library for common DB pipeline steps
- Stages: validate SQL, clone staging DB, apply migration, run tests, approval gate, apply prod
- Parameterized builds: target environment, migration version, dry-run flag

### Working in a Multi-Tool Environment
- Acknowledge Puppet/Chef without dismissing them - Voleon invested in these tools
- Practical approach: "I learn whatever the team uses - the principles transfer"
- Suggest clear ownership boundaries: Puppet for OS baseline, Ansible for database layer
- Avoid religious wars about tools - focus on outcomes (reliability, speed, auditability)

### Kubernetes and Database Lifecycle
- Voleon runs Kubernetes for services - they may ask about PG on K8s
- Know the tradeoffs: K8s operators (CloudNativePG, Zalando) vs VM-based PG
- Position: "Stateless services on K8s, stateful databases on VMs" is the common pattern, but you are open to operators if the team has invested in them
- Connection pooling (PgBouncer) often runs as a K8s sidecar even when PG is on VMs

### Python Scripting Alongside Ansible
- Custom Ansible modules written in Python for PG-specific checks
- Python scripts for: backup validation, replication topology visualization, capacity forecasting
- dbaBrain.ai context: building an AI engine that automates DBA decision-making - shows you think beyond basic scripts
- Libraries: psycopg2/psycopg3 for PG connections, boto3 for AWS, paramiko for SSH automation

---

## Final Reminders

- Mark is infra, not DBA - speak his language (pipelines, modules, state, idempotency)
- Show you can operate within a team's existing toolchain, not just your preferred tools
- Concrete numbers matter: "400 instances," "11 datacenters," "15,000 databases," "45-second failover"
- If you do not know something about their specific stack (Pulumi, Slurm), say so and explain how you would learn it
- End strong: tie your automation experience to Voleon's scale and reliability requirements

# Voleon DBA Lab - Learning Path

## Overview

This lab uses the **CBUS methodology** to build deep, practical PostgreSQL skills
in a realistic quant finance environment.

- **C** - Concepts: Read the background first so commands make sense
- **B** - Build: Install and configure the full stack from scratch
- **U** - Use: Practice day-to-day DBA operations on a live system
- **S** - Survive: Break the system and fix it under pressure

The target environment is a 4-node AWS lab running PostgreSQL 17 with streaming
replication, pgBackRest backups, PgBouncer connection pooling, Redis caching,
Docker-based ancillary databases, Ansible automation, and Prometheus/Grafana
observability - modeled after a real quant hedge fund stack.

---

## Phase 1: BUILD (Install and Configure)

Work through these guides in order. Each builds on the previous one.
Do not skip ahead - the later guides assume the earlier ones are complete.

| # | Guide | Time | What You'll Build |
|---|-------|------|-------------------|
| 01 | [Install and Configure PostgreSQL 17](build/BUILD-01-install-postgresql.md) | 45 min | PostgreSQL 17 on all nodes, data directories, OS tuning |
| 02 | [Create quantdb Schema and Load Data](build/BUILD-02-create-quantdb.md) | 60 min | quantdb database, quant and ops schemas, roles, seed data |
| 03 | [Setup Streaming Replication](build/BUILD-03-streaming-replication.md) | 45 min | Primary/replica streaming replication with replicator role |
| 04 | [Setup pgBackRest with Simulated Ceph RBD](build/BUILD-04-pgbackrest-ceph-sim.md) | 60 min | pgBackRest stanza, full/incr backups, WAL archiving |
| 05 | [PgBouncer and Redis Setup](build/BUILD-05-pgbouncer-redis.md) | 45 min | PgBouncer pool on port 6432, Redis 7 caching layer |
| 06 | [Docker Databases Setup](build/BUILD-06-docker-databases.md) | 45 min | voleon-pg and voleon-mysql containers on pg-container |
| 07 | [Ansible Automation for PostgreSQL](build/BUILD-07-ansible-automation.md) | 60 min | Ansible inventory, playbooks for config and role management |
| 08 | [Prometheus and Grafana Monitoring](build/BUILD-08-prometheus-grafana.md) | 60 min | Prometheus, node_exporter, pg_exporter, Grafana dashboards |

Total estimated time: **7 hours** (spread across multiple sessions)

---

## Phase 2: USE (Day-to-Day Operations)

These exercises simulate the tasks you do every day as a production DBA.
Complete USE-01 first to get oriented. The rest can be done in any order.

| # | Exercise | Time | What You'll Practice |
|---|----------|------|----------------------|
| 01 | [Connect and Explore quantdb](use/USE-01-connect-and-explore.md) | 30 min | Connect as all roles, explore schemas, verify replica is read-only |
| 02 | [Replication Health Check](use/USE-02-replication-health.md) | 30 min | pg_stat_replication, lag monitoring, slot inspection |
| 03 | [PITR Drill](use/USE-03-pitr-drill.md) | 45 min | Restore quantdb to a point in time using pgBackRest |
| 04 | PgBouncer Operations | 30 min | Pool tuning, SHOW commands, connection management |
| 05 | [Ansible Rolling Configuration Changes](use/USE-05-ansible-rolling-changes.md) | 45 min | Push pg config changes across nodes with zero downtime |
| 06 | [Container Database Operations](use/USE-06-container-operations.md) | 50 min | Docker lifecycle, container PG queries, Redis cache inspection |
| 07 | Grafana Dashboard Deep-Dive | 30 min | Read key metrics, understand what normal looks like |
| 08 | Partition Maintenance | 40 min | Add a new partition, check bloat, manual VACUUM on a partition |

Total estimated time: **5.5 hours**

---

## Phase 3: SURVIVE (Chaos Engineering)

Scenarios are injected with `chaos/chaos.sh inject <scenario>` and scored with
`chaos/chaos.sh validate <scenario>`. Each scenario has a runbook in
`cbus/survive/` for reference - but try to solve it without looking first.

Severity guide:
- **Medium**: Important but not total outage. 15-30 minute recovery window.
- **High**: Production impact. Data or replication at risk. 10-20 minutes.
- **Critical**: Complete outage or data loss event. Every second counts.

| # | Scenario | Severity | What Breaks |
|---|----------|----------|-------------|
| 01 | [Primary Failover](survive/01-primary-failover/runbook.md) | Critical | PostgreSQL stops on primary. All writes fail. Replica must be promoted. |
| 02 | PgBouncer Pool Exhaustion | High | Connection pool flooded. New app connections queue or timeout. |
| 03 | Accidental Signal Delete | Critical | Current month signals partition wiped. PITR required to recover data. |
| 04 | Docker Container Crash | Medium | voleon-pg container killed. Port 5433 stops responding. |
| 05 | WAL Disk Full | Critical | pg_wal filesystem filled. PostgreSQL panics and shuts down. |
| 06 | Ansible Config Drift | High | pg_hba.conf corrupted with wrong CIDR. Replication breaks on reload. |
| 07 | Slow Query Blocks Partitions | Medium | Long-running query holds lock. Partition maintenance hangs. |
| 08 | Monitoring Blackout | High | Prometheus down. Replica lag builds silently. No alerts fire. |

### Running Scenarios

```bash
# From the lab root directory
cd /path/to/voleon

# See all scenarios and their last result
./chaos/chaos.sh list

# Check current lab health before injecting
./chaos/chaos.sh status

# Inject a scenario
./chaos/chaos.sh inject 01-primary-failover

# Validate your recovery (run after you believe the issue is fixed)
./chaos/chaos.sh validate 01-primary-failover

# See all scores
./chaos/chaos.sh results
```

---

## Concepts

Read these before or during the BUILD phase. They explain the "why" behind
the technologies used in this lab.

| Doc | Topic |
|-----|-------|
| [voleon-architecture.md](concepts/voleon-architecture.md) | Full lab architecture, node roles, data flow, design decisions |
| [ceph-storage-for-dbas.md](concepts/ceph-storage-for-dbas.md) | How Ceph RBD works, why finance firms use it for database storage |
| [containerized-databases.md](concepts/containerized-databases.md) | When to use containerized databases, tradeoffs vs bare-metal PG |

---

## Recommended Order

This sequence builds skills progressively from zero to autonomous incident response.

1. Read **concepts/voleon-architecture.md** to understand what you are building
2. Complete all **BUILD guides** in order (01 through 08)
3. Run **USE-01** to verify the full stack is working end-to-end
4. Work through **USE exercises** 02-08 (any order, but do 02 before 07)
5. Attempt **SURVIVE scenarios** - start with Medium severity, work up to Critical
   - Recommended order: 04 -> 07 -> 02 -> 06 -> 08 -> 05 -> 03 -> 01
6. Repeat Critical scenarios without the runbook until recovery time is under 10 minutes

### Tips for the SURVIVE phase

- Do not look at the runbook immediately. Struggle first. That is where learning happens.
- Use `./chaos/chaos.sh status` to get a snapshot of what is broken.
- Time yourself. Production incidents are measured in minutes.
- After each scenario, write down: what was the first signal you saw? what slowed you down?
- Scenario 01 (Primary Failover) is the hardest. Save it for last.

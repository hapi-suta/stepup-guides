# Capstone Concepts: The Complete PostgreSQL DBA

This document ties together everything from Modules 1-19 into a unified framework for production database management. It covers architecture patterns, operational checklists, incident management, change management, disaster recovery, capacity planning, security, and career development.

---

## 1. Production PostgreSQL Architecture Patterns

### Single-Server (Development / Small Apps)

```
[Application] --> [PostgreSQL Primary]
```

- Simplest setup
- No HA, single point of failure
- Acceptable for: dev/staging, internal tools, low-traffic apps
- Backup: pgBackRest to local disk + offsite copy

### Primary-Standby (Most Production Workloads)

```
[Application] --> [pgBouncer] --> [PostgreSQL Primary]
                                       |
                                  [Streaming Replication]
                                       |
                                  [PostgreSQL Standby]
```

- One standby for failover
- pgBouncer for connection pooling
- Synchronous replication for zero data loss
- Acceptable for: most production workloads
- This is what you built in Module 20

### Primary + Multiple Standbys (Read-Heavy Workloads)

```
                    [Read Traffic]
                    /          \
[Application] --> [pgBouncer] --> [Read Replica 1]
       |                          [Read Replica 2]
       v
[pgBouncer] --> [PostgreSQL Primary]
                       |
                  [Sync Standby] (failover target)
```

- One synchronous standby for failover
- Additional async replicas for read scaling
- pgBouncer routes reads and writes separately
- Acceptable for: SaaS, e-commerce, analytics-heavy apps

### Multi-Region (Global / Compliance)

```
Region A (Primary)              Region B (DR)
[App] --> [PG Primary]  --->  [PG Standby]
          [pgBackRest] --->  [S3 Offsite Backup]

Region C (Read Locality)
[App] --> [PG Read Replica]
```

- Cross-region async replication (sync is too slow over WAN)
- Offsite backups in a different region
- Read replicas close to users for latency
- Acceptable for: global apps, regulatory compliance (data residency)

---

## 2. The DBA Checklist

### Daily

- [ ] Check monitoring dashboards (Grafana) for anomalies
- [ ] Review alert history - were any alerts fired overnight?
- [ ] Verify backups completed successfully
- [ ] Check replication lag (should be < 1 second for sync)
- [ ] Review slow query log for new offenders
- [ ] Check disk usage trends

### Weekly

- [ ] Review pg_stat_statements for top resource consumers
- [ ] Check for table bloat (dead tuple ratio > 10%)
- [ ] Verify backup restore works (test restore to temp location)
- [ ] Review connection patterns (peak usage, idle connections)
- [ ] Check for long-running transactions (> 1 hour)
- [ ] Review autovacuum activity (any tables not being vacuumed?)
- [ ] Check for unused indexes (idx_scan = 0 for weeks)

### Monthly

- [ ] Capacity planning review (disk growth, connection trends)
- [ ] Security audit (roles, pg_hba.conf, SSL certificates)
- [ ] Test failover (promote standby, then rejoin)
- [ ] Test PITR recovery to a specific timestamp
- [ ] Review and update monitoring alert thresholds
- [ ] Review PostgreSQL release notes for new minor versions
- [ ] Update runbooks with any new findings

### Quarterly

- [ ] Full disaster recovery test (document RTO and RPO)
- [ ] Review and rotate all database passwords
- [ ] Review infrastructure costs and optimize
- [ ] Plan for upcoming major version upgrades
- [ ] Training session with the team on recent incidents

---

## 3. Incident Management Framework

### Phase 1: Detect

How you learn about the problem:
- Monitoring alerts (Prometheus/Grafana)
- Application error rates spike
- User reports
- Scheduled health checks

**Key metric**: Mean Time to Detect (MTTD) - How long between the problem starting and someone knowing about it. Target: < 5 minutes for P1 incidents.

### Phase 2: Triage

Determine severity and scope:

| Priority | Impact | Response Time | Example |
|----------|--------|--------------|---------|
| P1 | Service down, data loss risk | Immediate | Primary crash, disk full |
| P2 | Degraded performance, partial outage | 15 minutes | Replication lag, slow queries |
| P3 | No immediate impact, needs attention | 1 hour | Backup warning, minor config issue |
| P4 | Improvement opportunity | Next business day | Index optimization, config tuning |

### Phase 3: Fix

The fix should follow this order:
1. **Mitigate** - Stop the bleeding. Restore service even if the root cause is unknown.
2. **Diagnose** - Find the root cause while service is restored.
3. **Remediate** - Apply the permanent fix.
4. **Verify** - Confirm the fix works and the issue does not recur.

### Phase 4: Review

After every P1 and P2 incident:

1. **Timeline** - What happened and when
2. **Root cause** - Why it happened
3. **Impact** - Who was affected and for how long
4. **Action items** - What will prevent recurrence
5. **Lessons learned** - What can we do better

The post-incident review is not about blame. It is about learning and improving systems.

---

## 4. Change Management Process

### Before Any Change

1. **Document the change**: What, why, when, who, rollback plan
2. **Test in staging**: Run the change on a non-production environment
3. **Peer review**: Another DBA reviews the plan
4. **Schedule the window**: Coordinate with stakeholders
5. **Take a backup**: Full backup before any destructive change

### Change Categories

| Category | Examples | Requires Window? | Risk |
|----------|---------|-----------------|------|
| Config reload | log_min_duration_statement, work_mem | No | Low |
| Config restart | shared_buffers, max_connections | Yes (brief) | Medium |
| DDL | CREATE INDEX CONCURRENTLY | No | Low |
| DDL | ALTER TABLE, DROP INDEX | Yes | Medium |
| Upgrade | Minor version | Yes (brief) | Medium |
| Upgrade | Major version | Yes (extended) | High |
| Failover | Planned switchover | Yes (brief) | Medium |

### The Change Checklist

```
Before:
  [ ] Change documented and peer-reviewed
  [ ] Tested in staging
  [ ] Backup taken
  [ ] Rollback plan documented
  [ ] Stakeholders notified
  [ ] Monitoring silenced for maintenance window

During:
  [ ] Execute the change step by step
  [ ] Verify each step before proceeding
  [ ] Monitor for unexpected behavior

After:
  [ ] Verify the change is effective
  [ ] Run health checks
  [ ] Re-enable monitoring alerts
  [ ] Notify stakeholders of completion
  [ ] Document actual duration and any deviations
```

---

## 5. Disaster Recovery Planning

### RTO and RPO

- **RTO (Recovery Time Objective)**: Maximum time the database can be down. How fast can you recover?
- **RPO (Recovery Point Objective)**: Maximum data loss acceptable. How much data can you afford to lose?

| Scenario | Typical RTO | Typical RPO |
|----------|-----------|-----------|
| Standby promotion (sync replication) | 1-5 minutes | 0 (zero data loss) |
| Standby promotion (async replication) | 1-5 minutes | Seconds of data |
| PITR from local backup | 15-60 minutes | Depends on WAL archive lag |
| PITR from offsite backup | 1-4 hours | Depends on WAL archive lag |
| Full restore from dump | Hours | Last dump time |

### DR Tiers

**Tier 1: Hot Standby** (RTO < 5 min, RPO = 0)
- Synchronous standby ready to promote
- Automatic failover via repmgr/Patroni
- Cost: 2x infrastructure

**Tier 2: Warm Standby** (RTO < 30 min, RPO < 1 min)
- Asynchronous standby
- Manual or semi-automatic failover
- Cost: 2x infrastructure

**Tier 3: Backup Restore** (RTO < 4 hours, RPO < 1 hour)
- pgBackRest with WAL archiving
- Restore to new instance when needed
- Cost: Backup storage only

**Tier 4: Dump/Restore** (RTO hours-days, RPO = last dump)
- pg_dump scheduled daily
- Restore to new instance
- Cost: Dump storage only

### DR Testing Schedule

- **Monthly**: Test standby promotion and rejoin
- **Quarterly**: Full DR test (restore from backup to new instance)
- **Annually**: Multi-region failover test

---

## 6. Capacity Planning Methodology

### Step 1: Measure Current State

- Database size (pg_database_size)
- Table sizes and growth rates (pg_stat_user_tables)
- Transaction rates (pg_stat_database)
- Connection usage (pg_stat_activity)
- Cache hit ratio (pg_statio_user_tables)
- WAL generation rate (pg_current_wal_lsn over time)
- Disk IOPS (iostat)
- CPU and memory utilization (node_exporter)

### Step 2: Identify Growth Drivers

- New features adding tables/data
- User growth increasing connections and queries
- Data retention policies (how long do you keep data?)
- Seasonal patterns (holiday traffic, end-of-month processing)

### Step 3: Project Forward

Use a simple growth model:
- Linear: current_size + (monthly_growth x months)
- Exponential: current_size x (1 + growth_rate)^months

Always project at least 6 months ahead.

### Step 4: Identify Bottlenecks

| Resource | Warning Threshold | Critical Threshold | Action |
|----------|------------------|-------------------|--------|
| Disk | 70% | 85% | Expand volume or archive old data |
| CPU | 60% sustained | 80% sustained | Optimize queries or add vCPUs |
| Memory | Cache hit < 99% | Cache hit < 95% | Increase shared_buffers or RAM |
| Connections | 60% of max | 80% of max | Add pooler or increase max |
| Replication lag | 10 seconds | 30 seconds | Check network/standby I/O |

### Step 5: Recommend Actions

Prioritize by:
1. What will cause an outage first? (Fix that first)
2. What is the cheapest fix? (Optimize before scaling)
3. What has the longest lead time? (Order hardware early)

---

## 7. Security Hardening Checklist

### Authentication

- [ ] All remote connections require SSL (hostssl + hostnossl reject)
- [ ] Password encryption is scram-sha-256 (not md5)
- [ ] No trust authentication for remote connections
- [ ] Passwords rotated at least annually
- [ ] Service accounts use minimal privileges

### Authorization

- [ ] Only postgres and HA tools (repmgr) have superuser
- [ ] Application roles follow least-privilege principle
- [ ] Schemas separate application data from public
- [ ] Default privileges grant minimum needed access
- [ ] Row-level security where appropriate

### Encryption

- [ ] SSL enabled with TLS 1.2 minimum
- [ ] SSL certificate not expired (check quarterly)
- [ ] Backups encrypted at rest (pgBackRest cipher)
- [ ] Replication uses SSL

### Auditing

- [ ] Connection logging enabled
- [ ] DDL statement logging enabled
- [ ] Slow query logging enabled
- [ ] Failed authentication logged
- [ ] Log files rotated and retained for compliance period

### Network

- [ ] Firewall restricts port 5432 to known sources
- [ ] Management ports (Prometheus, Grafana) not publicly accessible
- [ ] VPN or private network for database access in production

---

## 8. Career Path: Junior DBA to Principal

### Junior DBA (0-2 years)

**Focus**: Learn the fundamentals. Break things in labs, not production.

Skills to build:
- SQL fluency (SELECT, JOIN, subqueries, CTEs)
- PostgreSQL installation and configuration
- Basic backup and restore (pg_dump, pgBackRest)
- Reading EXPLAIN plans
- Understanding MVCC and vacuum
- Basic monitoring (pg_stat_activity, pg_stat_statements)

**Typical tasks**: Running queries, taking backups, monitoring alerts, applying patches.

### Mid-Level DBA (2-5 years)

**Focus**: Own production systems. Handle incidents independently.

Skills to build:
- Replication setup and management
- Performance tuning (indexes, configuration, query optimization)
- Incident response and root cause analysis
- Automation (scripts, cron, Ansible)
- Capacity planning
- Security hardening
- Multiple PostgreSQL versions and upgrade paths

**Typical tasks**: Managing HA clusters, handling P1 incidents, planning upgrades, optimizing performance, mentoring juniors.

### Senior DBA (5-10 years)

**Focus**: Design systems. Prevent problems before they happen.

Skills to build:
- Architecture design (multi-region, multi-tenant)
- Disaster recovery planning and testing
- Change management processes
- Cross-team collaboration (dev, SRE, security)
- Cost optimization
- Cloud-native PostgreSQL (RDS, Cloud SQL, Aurora)
- Advanced internals (write-ahead logging, buffer management, planner)

**Typical tasks**: Designing database architectures, leading DR tests, defining standards, reviewing infrastructure, handling escalations.

### Principal DBA / Database Architect (10+ years)

**Focus**: Set direction. Build teams and practices.

Skills to build:
- Organization-wide database strategy
- Team building and mentorship
- Vendor evaluation and selection
- Executive communication (translate technical into business)
- Industry trends and emerging technologies
- Cross-database expertise (PostgreSQL + others)

**Typical tasks**: Setting database standards across the company, evaluating new technologies, advising on architecture decisions, building the DBA team, representing the database at the leadership table.

---

## 9. Interview Preparation: Top 20 PostgreSQL DBA Questions

### Architecture and Internals

**1. Explain the PostgreSQL process architecture.**
PostgreSQL uses a multi-process model. The postmaster process accepts connections and forks a backend process for each client. Background processes include the background writer (flushes dirty buffers), WAL writer (flushes WAL), autovacuum launcher, checkpointer, and stats collector.

**2. What is MVCC and why does PostgreSQL need VACUUM?**
Multi-Version Concurrency Control keeps old row versions so readers don't block writers. When a row is updated, the old version remains until no transaction needs it. VACUUM removes these dead tuples and makes the space reusable. Without vacuum, tables grow indefinitely (bloat) and eventually hit transaction ID wraparound.

**3. Explain the difference between shared_buffers and effective_cache_size.**
shared_buffers is the actual memory PostgreSQL allocates for caching data pages (typically 25% of RAM). effective_cache_size is a hint to the query planner about total available cache (OS cache + shared_buffers, typically 75% of RAM). shared_buffers uses real memory. effective_cache_size just affects planning decisions.

**4. What happens during a checkpoint?**
The checkpointer writes all dirty buffers from shared_buffers to disk, updates the WAL checkpoint record, and removes old WAL segments. Checkpoints guarantee a recovery starting point. Frequent checkpoints cause I/O spikes. Infrequent checkpoints mean longer recovery time.

### Replication and HA

**5. Explain streaming replication vs logical replication.**
Streaming replication sends WAL records byte-for-byte to standby servers. The standby replays the WAL to stay in sync. It replicates everything (all databases, all schemas). Logical replication decodes WAL into logical changes (INSERT, UPDATE, DELETE) and sends them to subscribers. It can replicate specific tables and works across major versions.

**6. What is the difference between synchronous and asynchronous replication?**
Asynchronous: the primary commits without waiting for the standby. Faster commits but risk of data loss if the primary crashes before the standby catches up. Synchronous: the primary waits for the standby to confirm receipt (or flush, or apply) before committing. Slower but guarantees zero data loss.

**7. How does automatic failover work with repmgr?**
repmgrd monitors the primary every N seconds. If it cannot reach the primary after a configurable number of attempts (reconnect_attempts x reconnect_interval), it initiates a failover. The standby with the best LSN promotes itself to primary. Other standbys follow the new primary. The failed primary must be manually rejoined after repair.

**8. What is split-brain and how do you prevent it?**
Split-brain occurs when two nodes both think they are primary. It happens when the standby promotes while the old primary is still running (e.g., network partition). Prevention: fencing (STONITH), witness nodes, quorum-based decisions, and never promoting without confirming the old primary is stopped.

### Backup and Recovery

**9. Explain the difference between full, differential, and incremental backups.**
Full: copies everything. Differential: copies everything that changed since the last full backup. Incremental: copies everything that changed since the last backup of any type. Full is the safest but slowest. Incremental is the fastest but depends on the full + all prior incrementals for restore.

**10. How does PITR work?**
Point-in-Time Recovery uses a base backup plus WAL archives. You restore the base backup, then PostgreSQL replays WAL segments until it reaches your target time (or LSN, or transaction ID). It can recover to any second within the WAL retention window.

**11. What is a replication slot and why is it dangerous?**
A replication slot guarantees that the primary retains WAL segments the consumer needs. Without a slot, the primary might delete WAL before the consumer reads it. The danger: if the consumer disconnects and never reconnects, the slot retains WAL indefinitely, filling the disk.

### Performance

**12. How do you diagnose a slow query?**
Start with EXPLAIN (ANALYZE, BUFFERS). Look for: sequential scans on large tables (needs index), high buffer reads (data not cached), sorts spilling to disk (increase work_mem), nested loop on large sets (planner chose wrong join type). Check pg_stat_statements for historical performance.

**13. What is the difference between an index scan and a bitmap index scan?**
Index scan reads the index and fetches each row individually. Efficient for a few rows. Bitmap index scan reads the index into a bitmap of pages, then fetches pages in order. Efficient for moderate selectivity. Sequential scan reads the entire table. Efficient when you need most of the rows.

**14. How do you handle table bloat?**
Regular VACUUM removes dead tuples and marks space as reusable but does not shrink the file. VACUUM FULL rewrites the table (shrinks it) but takes an exclusive lock. pg_repack can rewrite the table with minimal locking. For prevention: tune autovacuum to be more aggressive (lower scale_factor, more workers).

### Operations

**15. How do you perform a zero-downtime minor version upgrade?**
Upgrade standbys first (stop, update packages, start). Verify replication works. Then upgrade the primary (stop, update, start). Minor versions are binary-compatible - no data migration needed. Total downtime is the restart time of the primary (seconds).

**16. Explain your approach to capacity planning.**
Measure current state (sizes, transaction rates, cache hit ratio, disk usage). Calculate growth rates. Project 6-12 months forward. Identify which resource will become the bottleneck first. Recommend scaling actions prioritized by impact and lead time. Review quarterly.

**17. How do you handle a connection exhaustion incident?**
Immediate: terminate idle-in-transaction connections (pg_terminate_backend). Set idle_in_transaction_session_timeout. Long-term: implement connection pooling (pgBouncer), set per-role connection limits, review application connection management.

### Security

**18. What authentication methods does PostgreSQL support and which should you use?**
trust (no auth), password (cleartext), md5 (weak hash), scram-sha-256 (strong hash), peer (OS user matching), cert (SSL certificate), gss/sspi (Kerberos), ldap, radius. For production: scram-sha-256 for password auth, cert for service-to-service, peer for local admin access. Never use trust or md5 for remote connections.

**19. How do you implement least-privilege access?**
Create separate roles for different access levels (owner, readwrite, readonly). Use schemas to organize objects. Grant only the minimum permissions needed. Use ALTER DEFAULT PRIVILEGES for automatic grants on new objects. Use Row-Level Security for row-level access control. Never give application roles superuser.

**20. What would you do in the first 10 minutes of a suspected security breach?**
(1) Enable audit logging if disabled (SHOW log_connections; ALTER SYSTEM SET). (2) Check pg_roles for unauthorized superusers. (3) Check pg_hba.conf for trust rules. (4) Check pg_stat_activity for suspicious connections. (5) Terminate unauthorized sessions. (6) Rotate all credentials. (7) Check pg_stat_ssl for unencrypted connections. (8) Preserve logs for forensics.

---

## Final Thought

The difference between a junior DBA and a senior DBA is not knowledge of commands. It is judgment. A senior DBA knows when to act fast (P1 incident) and when to slow down (major upgrade). They know when to automate (daily backups) and when to do it manually (failover in ambiguous situations). They know when to fix the symptom (free disk space) and when to fix the root cause (drop the inactive replication slot).

This judgment comes from experience - which is what the Module 20 lab exercises are designed to build. Every scenario you practice reduces your response time in production. Every runbook you write saves future-you 30 minutes at 3 AM.

Build the muscle memory. Trust the process. Ship reliable databases.

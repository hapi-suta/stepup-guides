# Exercise 06 - Backup Strategy Design

**Time estimate:** 30-40 minutes
**Prerequisites:** Exercises 01-05 complete - you understand logical backups, physical backups, PITR, and pgBackRest operations

---

## Objective

Design backup strategies for real production scenarios. This is a thinking exercise - no commands to run. By the end, you should be able to walk into any organization, assess their database environment, and recommend a backup strategy with confidence.

---

## The Core Equation

Every backup strategy answers two questions:

- **RPO (Recovery Point Objective):** How much data can you afford to lose? If the answer is "5 minutes," your backup strategy must guarantee that you can recover to a state no older than 5 minutes before the failure.
- **RTO (Recovery Time Objective):** How long can you afford to be down? If the answer is "30 minutes," your restore process must complete within 30 minutes from the moment you start.

> **Concept:** RPO and RTO are business decisions, not technical ones. The CTO or VP of Engineering defines them based on the cost of data loss and downtime. Your job as a DBA is to design a strategy that meets those targets within the available budget. A tighter RPO/RTO costs more - more frequent backups, faster storage, more infrastructure.

---

## Reference: Backup Types and Trade-offs

Before you design anything, internalize this table:

| Backup Type | Tool | Scope | Speed (Backup) | Speed (Restore) | Granularity | Use Case |
|---|---|---|---|---|---|---|
| Logical - Plain SQL | pg_dump -Fp | Single database | Slow (reads all data) | Slow (executes SQL) | Table-level | Dev snapshots, version migration |
| Logical - Custom | pg_dump -Fc | Single database | Slow (reads all data) | Medium (parallel possible) | Table-level | Production logical backup |
| Logical - Directory | pg_dump -Fd | Single database | Medium (parallel dump) | Fast (parallel restore) | Table-level | Large databases needing speed |
| Physical - Plain | pg_basebackup -Fp | Entire cluster | Fast (file copy) | Fastest (copy and start) | Cluster only | Fast local recovery |
| Physical - Tar | pg_basebackup -Ft -z | Entire cluster | Medium (compression) | Medium (extract + start) | Cluster only | Offsite archival |
| pgBackRest Full | pgbackrest --type=full | Entire cluster | Medium (checksummed copy) | Fast (automated chain) | Database-level | Production base backup |
| pgBackRest Diff | pgbackrest --type=diff | Changed since full | Fast | Fast | Database-level | Daily production backup |
| pgBackRest Incr | pgbackrest --type=incr | Changed since last any | Fastest | Fast | Database-level | Hourly production backup |
| WAL Archiving | archive_command / pgBackRest | Transaction log | Continuous | N/A (used with base) | Transaction-level | Enables PITR |

> **Concept:** No single backup type covers every need. Logical backups let you restore individual tables and migrate between major versions. Physical backups give you faster full-cluster recovery and PITR. In production, you almost always use both. Logical for flexibility, physical for speed.

---

## Primary Scenario

**Your company has this environment:**

- **Database size:** 500GB, growing ~10GB/month
- **RPO:** 5 minutes (can afford to lose at most 5 minutes of data)
- **RTO:** 30 minutes (must be back online within 30 minutes)
- **Databases:** 3 - appdb (400GB), analyticsdb (80GB), configdb (20GB)
- **Compliance:** Must retain 90 days of backup history
- **Infrastructure:** 2 CentOS Stream 9 servers - pg-primary (NODE1) and pg-backup (NODE2)
- **Layout:** PGDATA at `/opt/pgsql/data`, WAL at `/opt/pgsql/wal`, backups at `/opt/pgsql/backup`, pgBackRest repo at `/opt/pgsql/backup/pgbackrest`

Design a backup strategy by answering each of these questions:

### Question 1 - What backup types do you use?

Think about what combination of tools and backup types covers every failure mode.

**Considerations:**
- Can pg_dump alone meet a 5-minute RPO on a 500GB database?
- Can you meet a 30-minute RTO with logical-only backups?
- Do you need both logical and physical backups?

### Question 2 - How often do you take each backup?

Map out the schedule - full, differential, incremental, logical.

**Considerations:**
- How large will a differential grow over a week if 10GB changes daily?
- How many incremental backups fit in the chain before restore time suffers?
- Does WAL archiving give you continuous RPO between scheduled backups?

### Question 3 - Where do you store backups?

Think about storage locations, redundancy, and cost.

**Considerations:**
- What happens if your backup server's disk fails?
- Should you store backups on the same server as the database?
- How much does cloud storage cost for 500GB+ of backup data?

### Question 4 - How do you meet the RPO?

The RPO of 5 minutes means you can lose at most 5 minutes of transactions.

**Considerations:**
- What is `archive_timeout` and what should you set it to?
- Does pgBackRest async WAL archiving help here?
- What is the difference between RPO from WAL archiving vs RPO from backup frequency?

### Question 5 - How do you meet the RTO?

The RTO of 30 minutes means full service restoration within 30 minutes.

**Considerations:**
- How long does a full restore of 500GB take from local storage?
- How does delta restore reduce that time?
- Would a streaming replica with promotion be faster than any restore?

### Question 6 - How do you monitor backup health?

Backups that fail silently are worse than no backups - you have false confidence.

**Considerations:**
- What metrics should trigger an alert?
- How do you detect WAL archive gaps?
- How do you know your backup repository is not running out of space?

### Question 7 - How often do you test restores?

A backup that has never been restored is a hope, not a backup.

**Considerations:**
- Can you automate restore testing?
- How do you test without impacting production?
- What do you check after a test restore?

---

## Suggested Approach for the Primary Scenario

| Component | Choice | Rationale |
|---|---|---|
| Primary backup tool | pgBackRest | Handles full/diff/incr, compression, verification, PITR |
| Full backup | Weekly (Sunday 02:00) | Foundation for the diff/incr chain |
| Differential | Daily (02:00 Mon-Sat) | Limits chain length, caps daily restore overhead |
| Incremental | Every 4 hours | Captures changes between daily diffs |
| WAL archiving | Continuous via pgBackRest async | archive_timeout=60 gives sub-minute RPO |
| Logical backup | Weekly pg_dump -Fc of each database | Cross-version migration safety, selective restore |
| Globals | Captured by pgBackRest (physical includes everything) | Supplemented with weekly pg_dumpall --globals-only |
| Storage - primary | Local repo at `/opt/pgsql/backup/pgbackrest` on pg-backup (NODE2) | Fast restore for RTO |
| Storage - secondary | S3-compatible cloud storage (repo2) | Disaster resilience |
| Encryption | pgBackRest repo-cipher-type=aes-256-cbc | Compliance requirement |
| Retention | repo1-retention-full=13 (13 weeks = 90 days) | Compliance requirement |
| Monitoring | Alert on: backup age > 8 hours, WAL archive lag > 5 min, repo disk > 80% | Automated health checks |
| Restore testing | Automated weekly restore to scratch instance | Proves recoverability |
| Verification | pgbackrest verify weekly | Checksums all backup files |

### Meeting the RPO

With `archive_timeout = 60`, WAL segments ship at most every 60 seconds. In practice, an active 500GB database generates WAL faster than that. The actual RPO is the age of the most recent archived WAL segment - typically under 1 minute for a busy database. The 5-minute RPO is met comfortably.

### Meeting the RTO

A delta restore of 500GB from local storage takes roughly 15-20 minutes on modern hardware (SSD/NVMe). WAL replay for the last 4 hours adds 5-10 minutes depending on write volume. Total: under 30 minutes. If restoring from cloud storage, add network transfer time - this is why local storage on the backup server matters for RTO.

### Storage Estimate

| Component | Size | Count (90 days) | Total |
|---|---|---|---|
| Full backups | 100GB compressed | 13 | 1,300GB |
| Differentials | 5GB avg | 78 (6/week x 13 weeks) | 390GB |
| Incrementals | 1GB avg | 390 (5/day x 78 days) | 390GB |
| WAL archives | 5GB/day avg | 90 days | 450GB |
| **Total** | | | **~2.5TB** |

Rule of thumb: budget 5x the database size for a 90-day retention backup repository.

---

## Company Profile 1: Startup - "ShipFast Inc."

**Profile:**
- 3-person engineering team, no dedicated DBA
- Single PostgreSQL 16 instance on a CentOS Stream 9 cloud VM (Linode, AWS, etc.)
- PGDATA at `/opt/pgsql/data`, backups at `/opt/pgsql/backup`
- 15GB database, growing 500MB/month
- One database: production app
- Budget: minimal
- Compliance: none

**Requirements:**
- RPO: 1 hour
- RTO: 2 hours

### Design Exercise

What would you recommend?

### Suggested Approach

| Component | Choice | Rationale |
|---|---|---|
| Primary backup | `/usr/pgsql-16/bin/pg_dump -Fc` via cron every 6 hours | Simple, no extra tooling |
| WAL archiving | Optional - skip initially | 15GB is small enough that 6-hour logical backups suffice |
| Storage | Local `/opt/pgsql/backup` + rsync to S3 | Two copies, low cost |
| Monitoring | Cron job checks dump file age, alerts via email | Low-tech but effective |
| Restore testing | Monthly manual test | Small team bandwidth |
| Globals | `/usr/pgsql-16/bin/pg_dumpall --globals-only` daily | Capture roles |

**Cost:** Near zero - cron + cloud storage bucket.

**Key risk:** Without WAL archiving, actual RPO is the time since the last dump. If the database fails at hour 5 of a 6-hour cycle, you lose 5 hours. For a 15GB database at a startup, this tradeoff is usually acceptable.

**When to upgrade:** When the database exceeds 50GB, dump time starts pushing past 30 minutes and RTO becomes hard to meet. That is the trigger to move to pgBackRest.

---

## Company Profile 2: Mid-Size - "DataCore Solutions"

**Profile:**
- 20-person engineering team, 1 DBA (you)
- Primary PostgreSQL 16 cluster on CentOS Stream 9 with one streaming replica
- PGDATA at `/opt/pgsql/data`, WAL at `/opt/pgsql/wal`, pgBackRest repo at `/opt/pgsql/backup/pgbackrest`
- 200GB database, growing 5GB/month
- Three databases: production app, analytics, internal tools
- Budget: moderate - dedicated backup infrastructure approved
- Compliance: SOC 2 - encryption, 90-day retention, access control

**Requirements:**
- RPO: 5 minutes
- RTO: 30 minutes

### Design Exercise

How does the streaming replica factor in? Should you back up from the primary or the replica?

### Suggested Approach

| Component | Choice | Rationale |
|---|---|---|
| Primary backup | pgBackRest with repo on dedicated backup server | Full toolchain for production |
| Full backup | Weekly from the standby (backup-standby=y) | Avoids I/O impact on primary |
| Differential | Daily | Keep restore chains short |
| Incremental | Every 4 hours | Balance between frequency and chain length |
| WAL archiving | Continuous via pgBackRest, archive_timeout=60 | Meets 5-minute RPO |
| Storage | Local repo + async replication to S3 (repo2) | Two locations |
| Encryption | AES-256 via pgBackRest | SOC 2 compliance |
| Retention | 13 weekly fulls (90 days) | SOC 2 compliance |
| Monitoring | Prometheus + Alertmanager | Track backup age, WAL lag, repo size |
| Restore testing | Automated weekly restore to staging | Proves recoverability |

**Key insight:** The streaming replica is NOT a backup. If someone runs `DELETE FROM users;` on the primary, the replica replicates the DELETE. Replicas protect against hardware failure. Backups protect against human error. You need both.

---

## Company Profile 3: Enterprise - "GlobalFinance Corp"

**Profile:**
- 200-person engineering organization, 5 DBAs
- Multiple PostgreSQL 16 clusters on CentOS Stream 9 across 3 regions (US-East, EU-West, APAC)
- PGDATA at `/opt/pgsql/data`, WAL at `/opt/pgsql/wal`, pgBackRest repo at `/opt/pgsql/backup/pgbackrest`
- 2TB primary database, 500GB analytics, 50GB per microservice (12 services)
- Budget: large - dedicated backup infrastructure, multiple cloud regions
- Compliance: PCI-DSS, GDPR, SOX

**Requirements:**
- RPO: 0 (zero data loss for financial transactions)
- RTO: 15 minutes (primary cluster), 1 hour (analytics/microservices)

### Design Exercise

How do you achieve zero data loss? Can pgBackRest alone meet a 15-minute RTO on a 2TB database?

### Suggested Approach

| Component | Choice | Rationale |
|---|---|---|
| RPO = 0 | Synchronous streaming replication to local standby | Every committed transaction exists on 2+ nodes |
| RTO = 15 min | Promote synchronous standby (takes seconds) | No restore needed for hardware failure |
| Primary backup | pgBackRest with 3 repos (local, region-2 S3, region-3 S3) | Geographic distribution |
| Full backup | Weekly per cluster | Foundation for diff/incr chains |
| Differential | Daily | Limit chain depth |
| Incremental | Hourly | Minimize data at risk |
| WAL archiving | Continuous to all 3 repos | Belt and suspenders with sync replication |
| Encryption | AES-256, keys in KMS/HSM | PCI-DSS requirement |
| Retention | 1 year minimum | SOX compliance |
| Backup source | Async standby in each region | Never touch the primary or sync standby |
| Monitoring | Prometheus + Grafana + PagerDuty | Full observability stack |
| Restore testing | Automated daily restore to isolated environment | Non-negotiable at this scale |
| Logical backups | Weekly `/usr/pgsql-16/bin/pg_dump -Fc` of each database | Cross-version migration safety |
| Microservices | Standardized pgBackRest config via Ansible/Terraform | Consistent policy across 12 databases |

**Meeting RPO = 0:** Synchronous replication guarantees every committed transaction exists on at least two nodes. The failover itself takes 30-60 seconds (detection + promotion), but zero data is lost.

**Meeting 15-minute RTO:** For a 2TB database, even delta restore from local storage takes 20-30 minutes. The solution is not to restore at all - promote the synchronous standby. Promotion takes under 30 seconds. pgBackRest backups are for scenarios where both primary and standby fail, or for recovering from logical errors (accidental deletes, bad migrations).

**Key insight:** At enterprise scale, the backup strategy and the HA strategy are tightly coupled. Backups protect against logical errors. HA (replication + promotion) protects against hardware failure. You need both, and they must be designed together.

---

## Think: Common Backup Strategy Mistakes

Review this list and check whether your design avoids each pitfall:

1. **Treating replicas as backups.** A replica replicates every mistake. `DELETE FROM users;` destroys data on both primary and replica instantly.

2. **Never testing restores.** A backup that has never been restored is a wish, not a backup. Test monthly at minimum. Automate it.

3. **Storing backups on the same disk as the database.** A disk failure takes out both. At minimum, use a separate volume. Ideally, a separate server and region. This is why `/opt/pgsql/backup` should be on a different physical volume than `/opt/pgsql/data`.

4. **Ignoring WAL archive lag.** If your archive_command falls behind or fails silently, your PITR window shrinks. Monitor `pg_stat_archiver.failed_count` and `last_archived_time`.

5. **No retention policy.** Backups accumulate forever, filling disks. Then the backup process itself fails because there is no space. Set explicit retention and run expire.

6. **Forgetting pg_dumpall --globals-only.** Physical backups capture roles, but if you only have logical backups, a restore fails because the owning roles do not exist. Always include a globals dump alongside logical backups.

7. **Not encrypting backups.** An unencrypted backup of your production database is a copy of all your customer data sitting on disk. Treat backups with the same security as the live database.

8. **RPO/RTO targets that have never been validated.** Saying "RTO is 30 minutes" means nothing until you have proven it with a timed restore drill. Run the drill. Measure. Adjust.

---

## Checkpoint

This exercise has no commands to verify. Instead, confirm:
- [ ] You can explain RPO and RTO to a non-technical stakeholder
- [ ] You designed a strategy for the primary scenario (500GB, RPO 5 min, RTO 30 min)
- [ ] You understand how the startup, mid-size, and enterprise strategies differ and why
- [ ] You know why replicas are not backups
- [ ] You can estimate storage requirements for a backup strategy
- [ ] You can identify the single biggest risk in any backup design
- [ ] You reviewed the common mistakes list and your design avoids all of them

---

**Next:** [Checklist - Knowledge Check](checklist.md)

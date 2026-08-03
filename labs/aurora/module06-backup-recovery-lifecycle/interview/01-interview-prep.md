# Module 06 Interview Questions
## Backup, Recovery, and Lifecycle - Aurora PostgreSQL

**Format:** Questions are graduated from Junior to Principal.
- **Junior:** recall and basic understanding
- **Mid-level:** application and decision-making
- **Senior:** trade-offs and design
- **Principal:** architecture, organizational, and edge cases

For each question, write your answer before reading the discussion. This builds the recall muscle interviewers are testing.

---

## Topic 1 - Automated Backups and Snapshots

**Junior**

### 1. What is the difference between an automated backup and a manual snapshot in Aurora?

**Key points to cover:**
- Automated backups are continuous and managed by AWS. They happen automatically with no performance impact on Aurora.
- Manual snapshots are triggered by the DBA or a script. They persist until you explicitly delete them.
- Automated backups are retained for 1-35 days (configurable). When the retention period expires, they are deleted.
- Manual snapshots are retained indefinitely - they survive even if you delete the cluster.
- Both are stored in S3 (managed by AWS, not visible in your S3 console).

### 2. What is the maximum backup retention period for Aurora?

**Answer:** 35 days for automated backups. Manual snapshots have no expiration - they persist until you delete them. If compliance requires 90+ days of retention, use a combination of automated backups (35 days) and scheduled manual snapshots for longer coverage.

### 3. Can you set backup retention to 0 on Aurora? What happens?

**Answer:** No. Unlike standard RDS, Aurora does not allow backup retention to be set to 0. The minimum is 1 day. Aurora's continuous backup architecture requires at least 1 day of retention. This is a key difference from standard RDS PostgreSQL, where setting retention to 0 disables automated backups entirely.

### 4. You have a manual snapshot from 3 days ago. Can you perform PITR to a specific second within the last 3 days using only that snapshot?

**Answer:** No. PITR requires automated backups to be enabled and uses the continuous backup stream (WAL records). A standalone manual snapshot only restores to the exact moment it was taken. PITR and snapshot restore are separate recovery mechanisms.

---

**Mid-level**

### 5. A customer calls and says they need to restore a table that was dropped 20 days ago. Your Aurora cluster has a 7-day backup retention. What are your options?

**Answer:** PITR is not an option - the event is outside the 7-day retention window. Your options are:
1. Check if a manual snapshot exists from that period (snapshots have no expiration).
2. Check if the table data exists in application logs, ETL pipelines, or downstream caches.
3. Check if a cross-region snapshot copy was taken as part of DR procedures.
4. If none of these exist, the data is likely unrecoverable.
5. Recommend increasing retention to 35 days going forward, and setting up scheduled manual snapshots for long-term coverage.

### 6. You need to give a disaster recovery team in a different AWS account access to your production snapshots without giving them access to your production cluster. How?

**Answer:** Share the manual cluster snapshot with the DR account ID using `modify-db-cluster-snapshot-attribute`. The DR team copies the shared snapshot into their own account using `copy-db-cluster-snapshot` and restores from their copy. They never need access to the source account's Aurora cluster. Note: you can only share manual snapshots, not automated backups.

### 7. Your company requires 90 days of backup retention for compliance. How do you meet this in Aurora?

**Answer:** Automated backups max out at 35 days. To cover 90 days:
1. Set automated backup retention to 35 days (maximum).
2. Create scheduled manual snapshots weekly or monthly using EventBridge + Lambda or a cron job.
3. Retain 3 monthly snapshots minimum for 90+ days of coverage.
4. Manual snapshots persist indefinitely until explicitly deleted.
5. For cross-region compliance, copy snapshots to a second region on the same schedule.

---

**Senior**

### 8. Describe Aurora's backup architecture. How does it differ from standard RDS PostgreSQL backups?

**Answer:** Aurora uses a fundamentally different backup architecture:
- **Standard RDS:** Takes daily full snapshots to S3, then continuously streams WAL to S3. PITR replays the nearest snapshot + WAL to reach the target time. Performance impact during snapshot window.
- **Aurora:** Continuous backup with no performance impact. Aurora's storage layer (shared distributed storage) automatically and continuously backs up data to S3. There is no discrete "backup window" that affects performance. The backup is always running at the storage layer.
- **Latest Restorable Time:** Both have a small lag (typically under 5 minutes) because WAL must finish uploading to S3 before it is usable for PITR.
- **Key difference:** Aurora backups never cause I/O suspension or performance degradation. Standard RDS can show brief I/O pause during the daily snapshot for Single-AZ instances.

### 9. A developer asks: "If I delete the Aurora cluster right now with `--skip-final-snapshot`, can I still use the automated backups to recover?" How do you respond?

**Answer:** No. Automated backups are deleted when the cluster is deleted. The `--skip-final-snapshot` flag means no manual snapshot is taken before deletion. Once the cluster is gone, the automated backups are gone too. This is irreversible. For production clusters, always use `--final-db-snapshot-identifier` to take a manual snapshot before deletion. This is the single most dangerous flag in the RDS CLI.

---

**Principal**

### 10. Design a multi-region backup and recovery architecture for Aurora PostgreSQL. Consider RPO, RTO, costs, and operational complexity.

**Discussion points:**
- **Automated backups** - 35-day retention, single region only, continuous, no cross-region capability.
- **Cross-region snapshot copies** - Schedule daily or weekly copies to the DR region. Cost: storage in both regions + data transfer fees.
- **Aurora Global Database** - Near-zero RPO (typically under 1 second replication lag). Fastest RTO for regional failover (1-2 minutes). Cost: full cluster running in the DR region at all times.
- **PITR limitations** - PITR only works within the region where backups exist. Cross-region PITR requires snapshot restore + re-enabling PITR on the new cluster.
- **Decision framework:** If RPO < 1 minute and RTO < 5 minutes, use Aurora Global Database. If RPO < 1 hour and RTO < 1 hour, use daily cross-region snapshot copies. If RPO < 24 hours and cost is a concern, use weekly cross-region snapshots.
- **Operational complexity:** Global Database requires monitoring replication lag across regions. Snapshot copies require automation (EventBridge + Lambda) and lifecycle management (deleting old copies).
- **Testing cadence:** DR drills quarterly at minimum. Restore from cross-region snapshots to verify data integrity.

---

## Topic 2 - Point-In-Time Recovery (PITR)

**Junior**

### 11. PITR creates a new cluster. True or false? Explain why.

**Answer:** True. PITR always creates a new Aurora cluster. It never modifies or overwrites the existing cluster. This protects you from accidentally destroying the still-running original. After recovery, you must create at least one DB instance in the new cluster before you can connect to it.

### 12. What is the format of the `--restore-time` flag in the AWS CLI for PITR?

**Answer:** ISO 8601 format in UTC: `2026-06-09T14:37:00Z`. The `Z` suffix indicates UTC. Always use UTC to avoid timezone confusion during an incident.

---

**Mid-level**

### 13. Describe the full procedure for recovering a single table from Aurora PITR without doing a full application cutover.

**Answer:**
1. Restore to a new cluster via PITR to a time before the data loss (`restore-db-cluster-to-point-in-time`).
2. Create a DB instance in the restored cluster (`create-db-instance`).
3. Wait for the instance to become available.
4. Connect to the restored cluster and verify the table exists with correct data.
5. Export just that table: `pg_dump -h restored-host -U postgres -d dbname -t tablename --data-only > table_data.sql`
6. Import the dump into the production cluster: `psql -h production-host -U postgres -d dbname < table_data.sql`
7. Verify row counts and checksums match.
8. Delete the restored cluster and instance when confirmed.

### 14. Your PITR restore took 45 minutes. What factors affect PITR restore time in Aurora?

**Answer:**
- **Cluster creation time** - Aurora must provision a new cluster and storage volume.
- **Instance startup time** - The DB instance must boot and reach `available` state.
- **WAL replay** - Aurora replays WAL from the continuous backup to reach the target timestamp. More WAL between the backup point and target time means longer replay.
- **Database size** - Larger databases require more storage operations during restore.
- **Instance class** - A larger instance class (more CPU/memory) replays WAL faster than a small instance.

Aurora PITR is generally faster than standard RDS PITR because the storage layer handles much of the work in parallel.

---

**Senior**

### 15. A developer ran a bad UPDATE affecting 500,000 rows 6 hours ago. The transaction committed. Walk through the full recovery strategy and trade-offs.

**Answer:**

**Option A - PITR to new cluster + table export (surgical):**
- Restore to just before the bad UPDATE.
- Export the affected table from the restored cluster.
- Compare with production to identify changed rows.
- Reload corrected data into production.
- Pro: No application downtime. Surgical fix.
- Con: 20-60 minute restore time. 6 hours of legitimate writes to that table since the bad UPDATE are NOT in the restored version - those must be handled separately.

**Option B - Full cutover to restored cluster:**
- Restore to just before the bad UPDATE.
- Point the application to the restored cluster.
- Pro: Clean state guaranteed.
- Con: 6 hours of legitimate transactions across ALL tables are lost. This is almost never acceptable.

**Option C - Application-level fix:**
- Identify the affected rows using application logs or audit tables.
- Write corrective UPDATE statements.
- Pro: Fastest, no RDS restore needed.
- Con: Requires knowing exactly what the correct values should be.

**Decision:** Option A is usually correct for single-table corruption. Option C is best if you have reliable audit logs. Option B is a last resort.

---

## Topic 3 - Blue/Green Deployments

**Junior**

### 16. What replication technology does Aurora Blue/Green Deployments use?

**Answer:** Logical replication. Aurora decodes WAL on the Blue (source) cluster and streams logical change events (INSERT, UPDATE, DELETE) to the Green (target) cluster. This allows Green to run a different engine version than Blue.

### 17. After a Blue/Green switchover, does the application need to update its connection string?

**Answer:** No. AWS automatically swaps the DNS endpoints. The original Blue cluster endpoint now points to Green. Applications using the cluster endpoint automatically connect to Green without any configuration change.

---

**Mid-level**

### 18. What causes high replication lag in a Blue/Green deployment, and why is it dangerous for switchover?

**Answer:** Common causes of high lag:
1. High write volume on Blue that Green cannot keep up with.
2. A long-running or idle-in-transaction session on Blue blocking replication slot advancement.
3. Green cluster CPU or I/O saturation.

High lag is dangerous because switchover requires a brief write pause on Blue while Green catches up. If lag is 30+ seconds, that pause becomes unacceptably long. AWS blocks switchover when lag exceeds the safe threshold. Always check `pg_stat_activity` for stuck transactions and `pg_replication_slots` for slot lag before attempting switchover.

### 19. An application has no connection retry logic. What will users experience during a Blue/Green switchover?

**Answer:** Connection errors lasting 30-60 seconds during the DNS swap. Without retry logic, the application returns errors to users during this window. After DNS propagates, new connections succeed. Existing connections open at switchover time may be terminated. Every production application should implement connection retry with exponential backoff.

---

**Senior**

### 20. Explain the difference between a Blue/Green switchover and a Multi-AZ failover.

**Answer:**
- **Multi-AZ failover:** Physical (synchronous) replication. Triggers automatically on primary failure. DNS updates in 30-60 seconds. No data loss (synchronous ensures standby is current). Purpose: high availability for unplanned failures.
- **Blue/Green switchover:** Logical replication. Manually triggered. Write pause of 30-60 seconds while Green catches up. Requires lag to be near zero. Green can be a different version. Purpose: planned upgrades and schema changes with near-zero downtime.

They solve different problems. Multi-AZ is for HA (unplanned). Blue/Green is for deployments (planned).

---

## Topic 4 - Maintenance Windows and Lifecycle

**Junior**

### 21. What is the maintenance window and when does AWS use it?

**Answer:** A weekly 30-minute scheduled window. AWS uses it to apply OS patches, minor engine version upgrades (if auto minor upgrade is enabled), and other pending maintenance actions. The window defines WHEN maintenance CAN happen - it does not mean maintenance happens every week.

### 22. Does changing a maintenance window cause a reboot?

**Answer:** No. Changing the maintenance window is a schedule change only. It does not cause any reboot, restart, or downtime.

---

**Mid-level**

### 23. What is `AutoAppliedAfterDate` in pending maintenance actions?

**Answer:** The deadline set by AWS for a required maintenance action. After this date, AWS will automatically apply the maintenance during your next maintenance window - you cannot prevent it. Before this date, you can choose to defer or apply it at a time of your choosing. If your maintenance window falls after the deadline, the action fires at that window. The safest approach is to apply maintenance yourself before the deadline at a controlled time.

### 24. You changed `max_connections` in your parameter group 2 weeks ago but it has not taken effect. What happened?

**Answer:** `max_connections` is a static parameter. It requires a reboot to take effect. The cluster is still running with the old value. Check the parameter apply status - it will show `pending-reboot`. You need to reboot the DB instances in the cluster (ideally during the maintenance window or a low-traffic period) for the new value to take effect.

---

**Senior**

### 25. Your organization runs 50 Aurora clusters across 3 regions. Design a maintenance window strategy.

**Discussion points:**
- **Tiered windows by environment:** Dev clusters get weekday off-hours windows. Staging gets weeknight windows. Production gets weekend early-morning windows.
- **Region-aware timing:** A "Sunday 03:00 UTC" window is Saturday 10 PM Eastern but Sunday 12 PM in Tokyo. Coordinate windows with the business hours of the teams using each cluster.
- **Infrastructure as code:** Define maintenance windows in Terraform/CDK so they are version-controlled and auditable. Never set windows manually in the console.
- **Automated compliance checking:** AWS Config rule or Lambda function that scans all clusters and flags any with maintenance windows during business hours.
- **Event-driven notifications:** EventBridge + SNS + Slack/PagerDuty integration so the on-call team knows when maintenance is pending and when it fires.
- **Staggered schedule:** Do not set all 50 clusters to the same window. Stagger them so that if a patch causes issues, you catch it on the first cluster before it hits the rest.
- **Pending maintenance audits:** Weekly automated scan of `describe-pending-maintenance-actions` across all clusters with a report to the DBA team.

---

## Topic 5 - Architecture and Design

**Principal**

### 26. A fintech company asks: "Should we use Blue/Green or in-place upgrades for our Aurora PostgreSQL fleet?" Design the decision framework.

**Discussion points:**
- **Blue/Green advantages:** Near-zero downtime switchover. Rollback available (old Blue still exists). Green can be tested thoroughly before cutover. Schema changes can accompany the upgrade.
- **Blue/Green constraints:** 2x instance cost during the deployment window. Logical replication has limits (DDL changes, large objects, sequence values). Cross-region not supported. Cannot combine with Aurora Global Database.
- **In-place upgrade advantages:** Simpler operationally. No replication setup. Works for all configurations. Lower cost (no duplicate instances).
- **In-place upgrade disadvantages:** Longer downtime (minutes to hours depending on size). Rollback requires full snapshot restore (30-60 minutes).
- **Recommendation framework:** Use Blue/Green for mission-critical production clusters where downtime must be under 1 minute. Use in-place for dev/test/staging where 10-30 minutes of downtime is acceptable. For very large databases (multi-TB), Blue/Green is strongly preferred because in-place upgrade time scales with database size.
- **Hybrid approach:** Blue/Green for the top 10 most critical clusters. In-place for everything else. Automate both paths.

### 27. You are designing a backup and recovery strategy for a regulated industry (healthcare/finance). The requirements are: RPO < 1 hour, RTO < 30 minutes, 7-year data retention, cross-region DR, quarterly DR testing. Design the complete architecture.

**Discussion points:**
- **RPO < 1 hour:** Aurora automated backups with 35-day retention (continuous, RPO typically under 5 minutes). Cross-region: Aurora Global Database for RPO under 1 second, or hourly cross-region snapshot copies for RPO under 1 hour.
- **RTO < 30 minutes:** PITR restore within same region takes 15-30 minutes for most clusters. Aurora Global Database failover takes 1-2 minutes. For cross-region snapshot restore, RTO is 30-60 minutes - may need Global Database to meet the 30-minute requirement.
- **7-year retention:** Automated backups only cover 35 days. Monthly manual snapshots retained for 7 years. Lifecycle policy using Lambda + EventBridge to create monthly snapshots and delete snapshots older than 7 years. Cost consideration: snapshot storage for 84 monthly snapshots per cluster.
- **Cross-region DR:** Aurora Global Database for primary DR path. Cross-region snapshot copies as a secondary backup path in case the global database has issues.
- **Quarterly DR testing:** Scripted DR drill that restores from cross-region snapshots, verifies data integrity (row counts, checksums), measures actual RTO, and produces a compliance report. Automate the drill so it can run without manual intervention.
- **Audit trail:** CloudTrail logging of all RDS API calls. SNS notifications for all backup/restore/maintenance events. Centralized logging in a compliance account.

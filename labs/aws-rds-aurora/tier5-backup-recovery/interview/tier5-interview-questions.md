# Tier 5 Interview Questions
## Backup, Recovery, and Lifecycle - AWS RDS and Aurora PostgreSQL

**Format:** Questions are graduated from Junior to Principal.
- Junior: recall and basic understanding
- Mid-level: application and decision-making
- Senior: trade-offs and design
- Principal: architecture, organizational, and edge cases

Use these to self-test or in pair interviews. For each question, write your answer before reading the discussion.

---

## Topic 1 - Automated Backups and Snapshots

**Junior**

1. What is the difference between an automated backup and a manual snapshot in RDS?
   - Key points: retention, survives instance deletion, who triggers it

2. What is the maximum backup retention period for RDS?
   - Answer: 35 days for automated backups, indefinite for manual snapshots

3. If you set backup retention to 0, what feature becomes unavailable?
   - Answer: PITR (point-in-time recovery). Setting to 0 disables all automated backups.

4. You have a manual snapshot from 3 days ago. Can you perform PITR to a specific second within the last 3 days?
   - Answer: No. PITR requires automated backups to be enabled and uses WAL records. A standalone manual snapshot only restores to the moment it was taken.

**Mid-level**

5. A customer calls and says they need to restore a table that was accidentally dropped 20 days ago. Your RDS instance has a 7-day backup retention. What options do you have?
   - Answer: Likely none via PITR (outside retention window). Check if a manual snapshot exists from that period. Check if the data exists in application logs or caches. Explain the 7-day window limitation and recommend increasing retention going forward.

6. You need to give a disaster recovery team access to your production snapshots without giving them access to your production database. How do you accomplish this?
   - Answer: Share the manual snapshot with the DR account ID using `modify-db-snapshot-attribute`. The DR team copies the snapshot into their own account and restores from there. They never need access to the source account's RDS instance.

7. Your company requires 90 days of backup retention for compliance. How do you meet this requirement in RDS?
   - Answer: Automated backups max at 35 days. Use monthly manual snapshots to cover the remaining retention. Keep 3 monthly snapshots for 90+ days of coverage. Manual snapshots are retained indefinitely until deleted.

**Senior**

8. Describe the storage architecture of RDS automated backups. Why is there a "latest restorable time" concept and why does it lag behind real-time?
   - Answer: RDS takes daily full snapshots and continuously streams WAL to S3. The latest restorable time lags because WAL must complete upload to S3 before it is usable for PITR. The lag is typically 2-5 minutes. You cannot recover to a time in the last few minutes because those WAL records have not yet been safely stored in S3.

9. A developer asks: "If I delete the RDS instance right now with `--skip-final-snapshot`, can I still use the automated backups to recover?" How do you respond?
   - Answer: No. Automated backups are deleted with the instance unless you take a final snapshot. The `--skip-final-snapshot` flag means no final manual snapshot is taken. The automated backups are also deleted. This is an irreversible action. Always use `--final-db-snapshot-identifier` for production instances.

**Principal**

10. Your organization is moving from a single-region to a multi-region DR strategy for RDS. Design the backup and recovery architecture. Consider RPO, RTO, costs, and operational complexity.
    - Discussion points: automated backups (35-day, single region); cross-region snapshot copies (weekly, daily for critical); Aurora Global Database for near-zero RPO; PITR window limitations across regions; cost model (storage + transfer); runbook for regional failover; DNS failover strategy; testing cadence for DR drills.

---

## Topic 2 - Point-In-Time Recovery (PITR)

**Junior**

1. PITR creates a new instance. True or false? Explain why.
   - Answer: True. PITR always creates a new RDS instance. It does not restore data in-place to the existing instance. This protects you from accidentally overwriting the still-running original.

2. What is the format of the `--restore-time` flag in the AWS CLI for PITR?
   - Answer: ISO 8601 format: `2025-05-30T14:37:00Z` (always UTC, Z suffix)

3. You run a PITR and the table you needed does not exist on the restored instance. What went wrong?
   - Answer: The restore timestamp was set to a time AFTER the table was dropped. The WAL was replayed past the drop event. Set the restore time to before the DROP TABLE statement executed.

**Mid-level**

4. Describe the full procedure for recovering a single table from a PITR without doing a full application cutover.
   - Answer: 1. Restore to a new instance via PITR to a time before the data loss. 2. Verify the table exists and data looks correct. 3. Export just that table with `pg_dump -t tablename --data-only`. 4. Import the dump into the production database. 5. Verify row counts and checksums. 6. Delete the restored instance.

5. Your PITR restore is taking 45 minutes for a db.t3.micro instance. What factors affect PITR restore time?
   - Answer: Instance startup time + WAL replay time. WAL replay time depends on: how much WAL exists between the snapshot and the target time (high write volume = more WAL = longer replay), instance class (faster CPU = faster WAL replay), and the size of the database. A longer gap between the last full snapshot and the target time means more WAL to replay.

6. What is the difference in behavior between `restore-db-instance-to-point-in-time` and `restore-db-instance-from-db-snapshot`?
   - Answer: PITR uses the latest full snapshot before the target time + WAL replay to reach an exact second. Snapshot restore uses only the exact state at snapshot creation time. PITR gives granular point-in-time control. Snapshot restore is faster (no WAL replay) but only recovers to the snapshot moment.

**Senior**

7. A developer made a mistake: they ran a bad UPDATE that affected 500,000 rows in production, but the transaction was committed 6 hours ago. PITR is available. Walk me through the full recovery strategy, including the trade-offs.
   - Answer: Option A (PITR to new instance + table export): Restore to just before the bad UPDATE. Export the affected table from the restored instance. Compare or reload data into production. Pro: surgical, no application downtime. Con: restored instance takes 20-60 minutes depending on size. Data written between the bad UPDATE and now is NOT in the restored instance - those rows must be handled separately. Option B (full cutover): Restore to a new instance, update app connection string. Pro: clean state. Con: 6 hours of legitimate transactions are lost. Option C (application-level fix): Identify the affected rows using application logs and fix them with an UPDATE. Pro: no RDS restore needed, fastest. Con: requires knowing exactly what values should be. Decision depends on whether 6 hours of post-corruption data is valid or not.

**Principal**

8. Explain how logical replication in Blue/Green Deployments and PITR both rely on the PostgreSQL WAL. How do they differ in their WAL consumption model?
   - Answer: Both use WAL as the source of truth for changes. PITR reads archived WAL from S3 and replays it into a new instance during recovery. Logical replication decodes WAL on the source in real-time and streams logical change events (INSERT/UPDATE/DELETE) to the target. PITR is asynchronous and backward-looking (recovery). Logical replication is near-real-time and forward-looking (replication). Both require WAL to be retained long enough: PITR retention = backup retention period; logical replication = WAL retained in the replication slot until Green confirms receipt. A crashed or lagging Green can cause WAL accumulation on Blue (replication slot lag), which is a different problem from PITR window management.

---

## Topic 3 - Aurora Fast Cloning

**Junior**

1. What does "copy-on-write" mean in the context of Aurora fast cloning?
   - Answer: Initially, both the original and clone share the same underlying storage pages. No data is physically copied. Only when a page is modified (by either cluster) does Aurora create a new physical copy of that page for the modifying cluster.

2. Is Aurora fast cloning available for standard RDS PostgreSQL?
   - Answer: No. Fast cloning is Aurora-only. Standard RDS PostgreSQL uses full snapshot restores.

3. True or false: modifying the clone will affect the original cluster's data.
   - Answer: False. Changes to the clone are isolated. Copy-on-write ensures each modified page is stored separately for the clone.

**Mid-level**

4. A clone was created from a 500 GB Aurora cluster 3 days ago. The clone has had 50 GB of writes since creation. How much storage is the clone consuming?
   - Answer: Approximately 50 GB. The clone only stores pages that have been modified since creation. The remaining 450 GB of unchanged pages are still shared with the original cluster's storage.

5. A team wants to use fast cloning for disaster recovery across regions. Is this possible?
   - Answer: No. Aurora fast cloning is limited to the same AWS account and region. For cross-region DR, you need snapshot restore. Only snapshots and Aurora Global Database work across regions.

6. Compare the time to create a 2 TB Aurora clone vs. a 2 TB RDS snapshot restore.
   - Answer: Aurora fast clone: 2-5 minutes (mostly instance startup time, actual data clone is near-instant). RDS snapshot restore: 1-4 hours (full 2 TB data copy from S3 to new instance). The difference is that cloning shares storage pages, while snapshot restore physically copies all data.

**Senior**

7. A developer asks: "Why can't I use the Aurora clone in production instead of production? It has all the data." How do you respond?
   - Answer: You can, but consider: the clone shares storage with the source. As the clone diverges (more writes), it creates more unique pages and the storage costs grow. The clone does not receive ongoing changes from the source (it is a snapshot in time). If the source cluster fails, the clone still works (storage is independent per page). The correct use of a clone is temporary (testing, migration validation) not permanent. For a permanent copy, use snapshot restore or a new cluster with backup/restore.

8. Describe when you would use clone vs PITR vs snapshot restore. Give a real-world example for each.
   - Answer: Clone - testing a new ORM migration against production data before applying it to production. Need it fast (seconds), same region, throwaway after testing. PITR - a developer dropped a table at 3:42 PM and you need to recover to 3:41 PM exactly. Precision in time matters. Snapshot restore - the production instance was deleted with a final snapshot taken. Now restoring it in a different region for DR testing. Need a full copy, cross-region.

---

## Topic 4 - Engine Version Upgrades

**Junior**

1. What CLI flag is required for a major version upgrade that is not needed for a minor version upgrade?
   - Answer: `--allow-major-version-upgrade`. This flag forces explicit opt-in so you cannot accidentally trigger a major version upgrade.

2. Can you downgrade an RDS instance from PostgreSQL 16 back to PostgreSQL 15 if you do not like the upgrade?
   - Answer: No. There is no in-place downgrade. Rollback requires restoring from a pre-upgrade snapshot. You get a new instance at the old version.

3. What is the minimum step you should always take before any major version upgrade?
   - Answer: Take a manual snapshot. This is your only rollback path.

**Mid-level**

4. List three things you should check before a major PostgreSQL version upgrade on RDS.
   - Answer: 1. Extensions - verify all installed extensions are available in the target version. 2. Parameter groups - custom parameters may need a new group for the target version; some parameters may be renamed or removed. 3. Application compatibility - deprecated or removed functions, changed behavior in catalog queries, driver versions that support the new protocol.

5. What happens to a custom parameter group when you perform a major version upgrade?
   - Answer: A custom parameter group for `postgres15` cannot be used with `postgres16`. AWS will create a default parameter group for the new version. If you have custom parameters, you must create a new parameter group for the target version family and manually migrate your custom parameters before the upgrade (or apply them after).

6. After a major version upgrade, your EXPLAIN plans look dramatically different and several queries are slower. What should you do first?
   - Answer: Run `ANALYZE` on all tables. Major upgrades can reset statistics, causing the planner to make poor decisions based on outdated statistics. After ANALYZE, re-run the slow queries. If still slow, compare EXPLAIN plans between the old and new versions to identify planner regressions.

**Senior**

7. You need to upgrade an Aurora PostgreSQL cluster from version 13 to 15, but AWS does not offer a direct 13-to-15 upgrade path. How do you do it?
   - Answer: Upgrade in steps: 13 -> 14 -> 15. Each step is a separate major version upgrade with snapshot, test, and validation in between. Check the valid upgrade targets for each version using `describe-db-engine-versions`. Some version jumps may not be direct; always verify the upgrade path before starting.

8. A major upgrade of a 1 TB production database is estimated to take 2 hours. Your maintenance window is 30 minutes. How do you handle this?
   - Answer: Expand the maintenance window for the upgrade event (to 3-4 hours). Or use Blue/Green deployment: create a Green with the target version and let it sync overnight, then switchover during the normal 30-minute window (switchover takes < 1 minute). Blue/Green is the preferred approach for large databases that cannot afford a 2-hour window.

**Principal**

9. Your company has 50 RDS instances all on different PostgreSQL versions. You are tasked with getting all of them to the latest stable version within 6 months. Design the upgrade program.
   - Discussion points: version inventory and matrix; grouping by application (low-risk dev/staging first); dependency mapping (shared schemas, logical replication chains); test environment coverage; application team engagement and code compatibility testing; staggered schedule with rollback windows; Blue/Green for production instances; post-upgrade validation automation; incident response plan for failures; stakeholder communication plan; tracking dashboard.

---

## Topic 5 - Blue/Green Deployments

**Junior**

1. What replication technology does RDS Blue/Green Deployments use?
   - Answer: Logical replication. PostgreSQL WAL is decoded and streamed as logical change events from Blue to Green.

2. After a Blue/Green switchover, which endpoint does the application need to update to reach the new primary?
   - Answer: No change needed. AWS automatically updates the DNS for the original Blue endpoint to point to Green. Applications using the Blue endpoint automatically start connecting to Green.

3. True or false: you can roll back a Blue/Green switchover after it completes.
   - Answer: True, but only if you have not deleted the old Blue environment. After deleting Blue, rollback is not possible without restoring from a snapshot.

**Mid-level**

4. What does replication lag represent in a Blue/Green deployment, and why is high lag dangerous for switchover?
   - Answer: Replication lag is the time difference between the most recent change on Blue and the most recently applied change on Green. High lag means Green is behind Blue. If you switch over with high lag, Green will continue applying changes after switchover but your application is already writing to it - this causes the catch-up period to run concurrently with new writes, potentially creating conflicts or inconsistencies.

5. You want to use Blue/Green to change the value of `max_connections` (a static parameter). Walk me through the steps.
   - Answer: 1. Create a new parameter group for Green with the desired `max_connections`. 2. Specify this parameter group in the Green configuration when creating the Blue/Green deployment. 3. The Green instance starts with the new parameter value (static parameters take effect on startup, and Green starts fresh). 4. After switchover, the application connects to Green with the new `max_connections`. 5. No reboot needed - Green started with the parameter already applied.

6. An application is not using connection retry logic. What will it experience during a Blue/Green switchover?
   - Answer: A connection error lasting ~30-60 seconds during the DNS update. Without retry logic, the application will return errors to users during this window. After the DNS update, new connections succeed. Existing connections that were open at switchover time may be terminated. Recommendation: always implement connection retry with exponential backoff for any database-backed application.

**Senior**

7. Explain the difference between a Blue/Green switchover and a Multi-AZ failover in terms of impact and mechanism.
   - Answer: Multi-AZ failover: synchronous physical replication; failover triggers automatically when primary fails; DNS updates in 30-60 seconds; no data loss (synchronous replication ensures standby is current). Blue/Green switchover: logical replication; manual trigger; write pause of ~30-60 seconds while Green catches up; requires replication lag to be near zero; Green may be a different version or schema. Multi-AZ is high availability (HA) for failures. Blue/Green is a deployment mechanism for upgrades and schema changes.

8. What are the limitations of Blue/Green Deployments for Aurora PostgreSQL?
   - Answer: Only single-region (both Blue and Green must be in the same region). Blue/Green does not support all Aurora features simultaneously (e.g., Aurora Global Database switchover cannot use Blue/Green). Cannot use Blue/Green if the source is a read replica. The logical replication relationship only goes Blue -> Green; you cannot replicate back from Green to Blue for continuous sync. Schema changes on Green must be backward compatible with what Blue is writing during the replication period.

**Principal**

9. A large fintech company asks: "Should we use Blue/Green Deployments or traditional in-place upgrades for our Aurora PostgreSQL fleet?" Design the decision framework.
   - Discussion points: Blue/Green advantages (near-zero downtime, rollback available, tested state before switchover, schema changes possible); Blue/Green constraints (cost of running 2x instances, logical replication limits, cross-region not possible, Aurora Global Database incompatible); in-place upgrade advantages (simpler, no replication setup, works for all instance types); in-place disadvantages (longer downtime, rollback requires full snapshot restore); recommendation framework based on: RTO tolerance, whether schema changes accompany the upgrade, fleet size and automation maturity, cost sensitivity; hybrid approach (Blue/Green for mission-critical, in-place for dev/test); automation considerations for running Blue/Green at fleet scale.

---

## Topic 6 - Maintenance Windows, OS Patching, and Reboots

**Junior**

1. What is the maintenance window in RDS and when does AWS use it?
   - Answer: A weekly 30-minute scheduled window. AWS uses it to apply OS patches, minor engine version upgrades (if auto minor upgrade is enabled), and other pending maintenance actions.

2. Does changing a maintenance window immediately restart the database?
   - Answer: No. Changing the maintenance window is just a schedule change. It does not cause any reboot or modification.

3. What is the difference between a dynamic and a static parameter in a parameter group?
   - Answer: Dynamic parameters apply immediately without a reboot. Static parameters only take effect after the instance is rebooted.

**Mid-level**

4. You changed `max_connections` in your parameter group 2 weeks ago, but it has not taken effect. What did you miss?
   - Answer: `max_connections` is a static parameter. It requires a reboot to take effect. The instance is still running with the old value. Check `DBParameterGroups[0].ParameterApplyStatus` - it will show `pending-reboot`.

5. Describe how AWS patches a Multi-AZ RDS instance during the maintenance window.
   - Answer: 1. Patches the standby first (no user impact). 2. Fails over (standby becomes primary, brief 20-60 second connection blip). 3. Patches the old primary (now standby). Total user-visible downtime: 20-60 seconds for the failover, compared to 3-5 minutes for Single-AZ.

6. What is `AutoAppliedAfterDate` in pending maintenance actions and what happens when it is reached?
   - Answer: This is the deadline set by AWS for a required maintenance action. After this date, AWS will automatically apply the maintenance during your next maintenance window whether you have opted in or not. You cannot prevent it after this date - you can only control WHEN it applies by choosing your maintenance window carefully or applying it early.

7. A pending maintenance action has `AutoAppliedAfterDate` set to next Tuesday, but your maintenance window is not until the following Sunday. What happens?
   - Answer: AWS will apply the maintenance during the next maintenance window AFTER the `AutoAppliedAfterDate`. Since your window is Sunday (after the Tuesday deadline), it will apply Sunday. If your maintenance window were before Tuesday, it would fire at that earlier window. The safest option is to apply it yourself early using `opt-in-type immediate` at a time of your choosing.

**Senior**

8. Your RDS instance has `AutoMinorVersionUpgrade: true`. Explain exactly when and how minor version upgrades are applied.
   - Answer: During the maintenance window, if a new minor version is `AutoUpgrade: true` in the valid upgrade targets list, and the instance has `AutoMinorVersionUpgrade: true`, AWS will apply it. This causes a reboot. For Multi-AZ: failover first, then patch. The upgrade is not instant - it is queued as a pending action and applied at the maintenance window. You can see it in `describe-pending-maintenance-actions` before it fires. Disable `AutoMinorVersionUpgrade` for instances where you want to control the upgrade timing manually.

9. How would you use CloudWatch and SNS to build a complete alerting system for RDS maintenance events?
   - Answer: 1. Create an SNS topic for RDS alerts. 2. Create an RDS event subscription for `maintenance` and `notification` categories using `create-event-subscription`. 3. Set up CloudWatch Events rule for RDS maintenance events (complementary to RDS event subscriptions). 4. Subscribe the on-call team email/PagerDuty/Slack to the SNS topic. 5. Create a Lambda function that receives maintenance events and posts to Slack with instance details and window timing. 6. Set a CloudWatch alarm on `FreeStorageSpace` and `CPUUtilization` as health checks to combine with maintenance awareness. 7. Test by manually applying a pending action and confirming the notification chain fires.

**Principal**

10. Your organization runs 200 RDS instances across 3 AWS regions. Describe how you would design and operationalize a maintenance window strategy at this scale.
    - Discussion points: centralized tagging strategy (environment, team, criticality, region); tiered maintenance windows by criticality (dev = weekday low traffic, staging = weekday off-hours, production = weekend off-hours); region-specific window timing (coordinate across time zones); infrastructure-as-code for window management (Terraform or CDK); automated compliance checking (Lambda or AWS Config rule verifying no windows during business hours); event-driven notification pipeline (EventBridge + SNS + Slack/PagerDuty); scheduled audits of pending maintenance across the fleet; runbooks for unexpected maintenance events; escalation paths for when maintenance fires outside expected windows.

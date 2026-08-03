# Phase 4: High Availability

## Objective

Make your cluster resilient to failures with Multi-AZ deployment, proper backups, and PITR capability. This draws on skills from Tier 4 (Availability) and Tier 5 (Backup/Recovery).

## Requirements

1. **Multi-AZ deployment**
   - Have at least one reader instance in a DIFFERENT Availability Zone than the writer
   - This is what gives you automatic failover

2. **Automated backups**
   - Backup retention period must be at least 7 days
   - Aurora does continuous backups automatically, but verify the retention

3. **Point-in-Time Recovery readiness**
   - Confirm PITR window by checking `EarliestRestorableTime` and `LatestRestorableTime` on the cluster
   - No action needed if backups are enabled - just verify it works

## Validation Criteria

- Writer and reader are in different AZs
- `BackupRetentionPeriod >= 7`
- Automated backups are enabled (not `0`)

## Hints

- Add a reader: `aws rds create-db-instance --db-cluster-identifier ... --availability-zone ...`
- Choose a different AZ than your writer (check with `describe-db-instances`)
- Modify retention: `aws rds modify-db-cluster --backup-retention-period 7`
- If you need a refresher on Aurora replication, see T4 Build 01-02
- For backup configuration, see T5 Build 01

## Reference

If you get stuck, review: T4 Build 01-03, T5 Build 01-02.

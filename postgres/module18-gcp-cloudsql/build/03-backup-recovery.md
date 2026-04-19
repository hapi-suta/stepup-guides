# BUILD 03 - Cloud SQL for PostgreSQL: Backup and Recovery

## What You Will Build

A comprehensive backup strategy for Cloud SQL including automated backups, on-demand backups, point-in-time recovery, cross-region backups, and export/import with Cloud Storage.

---

## Prerequisites

- Completed BUILD 01 (instance `suta-pg-lab` exists and is running)
- The `suta_lab` database with sample data from BUILD 01
- A Cloud Storage bucket (we will create one)

---

## Step 1 - Understand Cloud SQL Backup Types

Cloud SQL provides three backup mechanisms:

| Type | How | Retention | Use Case |
|---|---|---|---|
| Automated backups | Daily, scheduled | 1-365 days (default 7) | Regular disaster recovery |
| On-demand backups | Manual trigger | Until you delete them | Before risky changes |
| PITR (WAL archiving) | Continuous WAL | 1-7 days (default 7) | Recover to exact second |

Automated backups and PITR are independent. You should enable both for production.

---

## Step 2 - Verify Automated Backup Configuration

Check the current backup settings.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.backupConfiguration)"
```

Expected output (yours will differ):

```yaml
settings:
  backupConfiguration:
    backupRetentionSettings:
      retainedBackups: 7
      retentionUnit: COUNT
    enabled: true
    kind: sql#backupConfiguration
    location: us
    pointInTimeRecoveryEnabled: false
    startTime: '04:00'
    transactionLogRetentionDays: 7
```

The backup window is at 04:00 UTC. Point-in-time recovery is not yet enabled.

---

## Step 3 - Enable Point-in-Time Recovery

PITR uses continuous WAL (Write-Ahead Log) archiving. This lets you restore to any second within the retention window.

Enable PITR. The `--enable-point-in-time-recovery` flag turns on WAL archiving.

```bash
gcloud sql instances patch suta-pg-lab --enable-point-in-time-recovery
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Set the transaction log retention to 7 days. This controls how far back you can do PITR.

```bash
gcloud sql instances patch suta-pg-lab --retained-transaction-log-days=7
```

Set the backup retention count. This keeps the last 14 automated backups.

```bash
gcloud sql instances patch suta-pg-lab --retained-backups-count=14
```

Verify the updated settings.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.backupConfiguration)"
```

Expected output (yours will differ):

```yaml
settings:
  backupConfiguration:
    backupRetentionSettings:
      retainedBackups: 14
      retentionUnit: COUNT
    enabled: true
    location: us
    pointInTimeRecoveryEnabled: true
    startTime: '04:00'
    transactionLogRetentionDays: 7
```

PITR is now enabled with 7 days of WAL retention.

---

## Step 4 - Create an On-Demand Backup

Before making any risky change, take a manual backup. The `--description` flag adds a human-readable label.

```bash
gcloud sql backups create --instance=suta-pg-lab --description="pre-schema-change-backup"
```

Expected output (yours will differ):

```
Backing up Cloud SQL instance...done.
```

List all backups for the instance. The `--sort-by` flag orders by creation time.

```bash
gcloud sql backups list --instance=suta-pg-lab --sort-by=~startTime
```

Expected output (yours will differ):

```
ID           WINDOW_START_TIME            STATUS      TYPE
1681920000   2026-04-19T12:00:00.000+00:00  SUCCESSFUL  ON_DEMAND
1681833600   2026-04-19T04:00:00.000+00:00  SUCCESSFUL  AUTOMATED
1681747200   2026-04-18T04:00:00.000+00:00  SUCCESSFUL  AUTOMATED
```

On-demand backups show `ON_DEMAND` as the type. They do not count against your automated retention limit and persist until you delete them.

---

## Step 5 - Simulate Data That Needs Recovery

Connect to the database and make changes we will later recover from.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Record the current time. We will need this for PITR.

```sql
SELECT now();
```

Expected output (yours will differ):

```
              now
-------------------------------
 2026-04-19 12:10:00.123456+00
(1 row)
```

Write down this timestamp. We will use it as the PITR target.

Insert more data.

```sql
INSERT INTO students (name, email) VALUES
    ('Dave Wilson', 'dave@example.com'),
    ('Eve Brown', 'eve@example.com');
```

Verify the data.

```sql
SELECT count(*) FROM students;
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

Now simulate a disaster - drop the table.

```sql
DROP TABLE students;
```

Verify it is gone.

```sql
\dt students
```

Expected output (yours will differ):

```
Did not find any relation named "students".
```

Type `\q` to exit psql.

```
\q
```

---

## Step 6 - Restore from an On-Demand Backup

Restoring a backup in Cloud SQL creates a NEW instance. It does not overwrite the existing one. This is a safety feature.

Get the backup ID from the list.

```bash
gcloud sql backups list --instance=suta-pg-lab --filter="type=ON_DEMAND" --format="value(id)"
```

Expected output (yours will differ):

```
1681920000
```

Restore to a new instance. Replace `[BACKUP_ID]` with the ID from above.

- `--restore-instance`: Source instance that owns the backup
- `--backup-id`: The backup to restore from

```bash
gcloud sql instances clone suta-pg-lab suta-pg-restored \
  --point-in-time="2026-04-19T12:10:00.000Z"
```

Wait - this example uses PITR (next step). Let us restore from the backup instead.

```bash
gcloud sql backups restore [BACKUP_ID] --restore-instance=suta-pg-lab
```

Type `Y` when prompted. WARNING: This overwrites all data on the target instance with the backup contents.

Expected output (yours will differ):

```
Restoring Cloud SQL instance...done.
```

Reconnect and verify the table is back.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SELECT * FROM students;
```

Expected output (yours will differ):

```
 student_id |    name     |       email        |         enrolled_at
------------+-------------+--------------------+-------------------------------
          1 | Alice Chen  | alice@example.com  | 2026-04-19 10:15:00.123456+00
          2 | Bob Smith   | bob@example.com    | 2026-04-19 10:15:00.123456+00
          3 | Carol Davis | carol@example.com  | 2026-04-19 10:15:00.123456+00
(3 rows)
```

The backup was taken before the two new rows were inserted, so only the original 3 rows are present.

Type `\q` to exit psql.

```
\q
```

---

## Step 7 - Point-in-Time Recovery (PITR)

PITR lets you restore to any specific timestamp within the transaction log retention window. This is more precise than a backup restore.

Clone the instance to a specific point in time. Replace the timestamp with the one you recorded in Step 5 (before the DROP TABLE).

```bash
gcloud sql instances clone suta-pg-lab suta-pg-pitr \
  --point-in-time="2026-04-19T12:10:00.000Z"
```

Expected output (yours will differ):

```
Cloning Cloud SQL instance...done.
Created [https://sqladmin.googleapis.com/sql/v1beta4/projects/my-project/instances/suta-pg-pitr].
```

This creates a brand new instance with data as it was at that exact timestamp. It takes 5-10 minutes.

Get the IP of the new instance.

```bash
gcloud sql instances describe suta-pg-pitr --format="value(ipAddresses[0].ipAddress)"
```

Connect to the restored instance and verify data.

```bash
psql -h [PITR_INSTANCE_IP] -U postgres -d suta_lab
```

```sql
SELECT * FROM students;
```

The students table should exist with all 5 rows (including Dave and Eve) because the PITR target was after those inserts but before the DROP TABLE.

Type `\q` to exit psql.

```
\q
```

Delete the PITR clone when done.

```bash
gcloud sql instances delete suta-pg-pitr
```

---

## Step 8 - Cross-Region Backup Configuration

Store backups in a different region for disaster recovery. The `--backup-location` flag sets where backups are stored.

```bash
gcloud sql instances patch suta-pg-lab --backup-location=us-east1
```

Expected output (yours will differ):

```
Patching Cloud SQL instance...done.
```

Verify the backup location.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.backupConfiguration.location)"
```

Expected output (yours will differ):

```
us-east1
```

Backups are now stored in us-east1, separate from the instance in us-central1. If the entire us-central1 region goes down, you can restore from backups in us-east1.

---

## Step 9 - Export to Cloud Storage

Exports create SQL dump files or CSV files in Cloud Storage. Unlike backups, exports are portable and can be used with non-Cloud SQL PostgreSQL instances.

Create a Cloud Storage bucket for exports. The `-l` flag sets the location.

```bash
gcloud storage buckets create gs://[PROJECT_ID]-sql-exports -l us-central1
```

Expected output (yours will differ):

```
Creating gs://my-project-sql-exports/...
```

Export the database as a SQL dump. The `--database` flag specifies which database to export.

```bash
gcloud sql export sql suta-pg-lab gs://[PROJECT_ID]-sql-exports/suta_lab_export.sql \
  --database=suta_lab
```

Expected output (yours will differ):

```
Exporting Cloud SQL instance...done.
```

Export a specific table as CSV.

```bash
gcloud sql export csv suta-pg-lab gs://[PROJECT_ID]-sql-exports/students.csv \
  --database=suta_lab \
  --query="SELECT * FROM students ORDER BY student_id"
```

Expected output (yours will differ):

```
Exporting Cloud SQL instance...done.
```

Verify the exports exist in the bucket.

```bash
gcloud storage ls gs://[PROJECT_ID]-sql-exports/
```

Expected output (yours will differ):

```
gs://my-project-sql-exports/suta_lab_export.sql
gs://my-project-sql-exports/students.csv
```

Download and inspect the CSV export.

```bash
gcloud storage cat gs://[PROJECT_ID]-sql-exports/students.csv
```

Expected output (yours will differ):

```
1,Alice Chen,alice@example.com,2026-04-19 10:15:00.123456+00
2,Bob Smith,bob@example.com,2026-04-19 10:15:00.123456+00
3,Carol Davis,carol@example.com,2026-04-19 10:15:00.123456+00
```

---

## Step 10 - Import from Cloud Storage

Import a SQL dump into a Cloud SQL instance. This is useful for migrations and restoring from exports.

Create a new database for the import.

```bash
gcloud sql databases create suta_lab_imported --instance=suta-pg-lab
```

Import the SQL dump.

```bash
gcloud sql import sql suta-pg-lab gs://[PROJECT_ID]-sql-exports/suta_lab_export.sql \
  --database=suta_lab_imported
```

Expected output (yours will differ):

```
Importing data into Cloud SQL instance...done.
```

Verify the import.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab_imported
```

```sql
SELECT count(*) FROM students;
```

Expected output (yours will differ):

```
 count
-------
     3
(1 row)
```

Type `\q` to exit psql.

```
\q
```

---

## Step 11 - Delete Old Backups

On-demand backups persist until you delete them. Clean up backups you no longer need.

List all on-demand backups.

```bash
gcloud sql backups list --instance=suta-pg-lab --filter="type=ON_DEMAND"
```

Delete a specific backup by ID.

```bash
gcloud sql backups delete [BACKUP_ID] --instance=suta-pg-lab
```

Type `Y` when prompted.

---

## Summary

| Task | Command |
|---|---|
| Enable PITR | `gcloud sql instances patch --enable-point-in-time-recovery` |
| Create on-demand backup | `gcloud sql backups create --instance=` |
| List backups | `gcloud sql backups list --instance=` |
| Restore from backup | `gcloud sql backups restore [ID] --restore-instance=` |
| PITR clone | `gcloud sql instances clone [SRC] [DST] --point-in-time=` |
| Cross-region backup | `gcloud sql instances patch --backup-location=` |
| Export SQL | `gcloud sql export sql [INSTANCE] gs://bucket/file.sql` |
| Export CSV | `gcloud sql export csv [INSTANCE] gs://bucket/file.csv --query=` |
| Import SQL | `gcloud sql import sql [INSTANCE] gs://bucket/file.sql` |

You now have a multi-layered backup strategy: automated daily backups, on-demand snapshots, continuous WAL for PITR, cross-region storage, and portable exports.

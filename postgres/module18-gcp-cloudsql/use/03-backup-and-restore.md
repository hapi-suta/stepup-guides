# USE 03 - Backup and Restore Operations

## Objective

Create on-demand backups, list and inspect backups, perform point-in-time recovery, and export data to Cloud Storage.

---

## Exercise 1 - Create a Pre-Change Backup

Before any schema change, take a manual backup.

```bash
gcloud sql backups create --instance=suta-pg-lab --description="pre-exercise-backup"
```

List all backups, most recent first.

```bash
gcloud sql backups list --instance=suta-pg-lab --sort-by=~startTime --format="table(id,startTime,status,type,description)"
```

Expected output (yours will differ):

```
ID           START_TIME                     STATUS      TYPE        DESCRIPTION
1681920000   2026-04-19T14:00:00.000+00:00  SUCCESSFUL  ON_DEMAND   pre-exercise-backup
...
```

Note the backup ID for later use.

---

## Exercise 2 - Insert Data and Record Timestamp

Connect and insert data we will later recover.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Record the timestamp before changes.

```sql
SELECT now() AS recovery_target;
```

Write down this timestamp.

Insert data.

```sql
CREATE TABLE exercise_data (
    id SERIAL PRIMARY KEY,
    label TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
```

```sql
INSERT INTO exercise_data (label) VALUES ('row-1'), ('row-2'), ('row-3'), ('row-4'), ('row-5');
```

Verify.

```sql
SELECT * FROM exercise_data;
```

Expected output (yours will differ):

```
 id | label |          created_at
----+-------+-------------------------------
  1 | row-1 | 2026-04-19 14:05:00.123456+00
  2 | row-2 | 2026-04-19 14:05:00.123456+00
  3 | row-3 | 2026-04-19 14:05:00.123456+00
  4 | row-4 | 2026-04-19 14:05:00.123456+00
  5 | row-5 | 2026-04-19 14:05:00.123456+00
(5 rows)
```

Record a second timestamp (after inserts but before any destructive action).

```sql
SELECT now() AS post_insert_timestamp;
```

Write this down too.

Now simulate a disaster.

```sql
DROP TABLE exercise_data;
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 3 - Restore to Point in Time

Clone the instance to the post-insert timestamp (before the DROP). Replace the timestamp with yours.

```bash
gcloud sql instances clone suta-pg-lab suta-pg-exercise-pitr \
  --point-in-time="2026-04-19T14:05:30.000Z"
```

Wait for the clone to complete (5-10 minutes).

Get the new instance IP.

```bash
gcloud sql instances describe suta-pg-exercise-pitr --format="value(ipAddresses[0].ipAddress)"
```

Connect and verify the data was recovered.

```bash
psql -h [PITR_IP] -U postgres -d suta_lab
```

```sql
SELECT * FROM exercise_data;
```

All 5 rows should be present.

Type `\q` to exit psql.

```
\q
```

---

## Exercise 4 - Export to Cloud Storage

Export the recovered database as a SQL dump.

```bash
gcloud sql export sql suta-pg-exercise-pitr gs://[PROJECT_ID]-sql-exports/exercise_recovery.sql \
  --database=suta_lab
```

Export just the exercise_data table as CSV.

```bash
gcloud sql export csv suta-pg-exercise-pitr gs://[PROJECT_ID]-sql-exports/exercise_data.csv \
  --database=suta_lab \
  --query="SELECT * FROM exercise_data ORDER BY id"
```

Verify exports.

```bash
gcloud storage ls gs://[PROJECT_ID]-sql-exports/exercise*
```

Expected output (yours will differ):

```
gs://my-project-sql-exports/exercise_recovery.sql
gs://my-project-sql-exports/exercise_data.csv
```

Download and inspect the CSV.

```bash
gcloud storage cat gs://[PROJECT_ID]-sql-exports/exercise_data.csv
```

---

## Exercise 5 - Import the Recovery Data

Import the SQL dump back into the original instance.

```bash
gcloud sql databases create suta_lab_recovered --instance=suta-pg-lab
```

```bash
gcloud sql import sql suta-pg-lab gs://[PROJECT_ID]-sql-exports/exercise_recovery.sql \
  --database=suta_lab_recovered
```

Verify the import.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab_recovered
```

```sql
SELECT * FROM exercise_data;
```

Type `\q` to exit psql.

```
\q
```

---

## Cleanup

Delete the PITR clone.

```bash
gcloud sql instances delete suta-pg-exercise-pitr
```

Remove the recovered database.

```bash
gcloud sql databases delete suta_lab_recovered --instance=suta-pg-lab
```

---

## Checklist

- [ ] Created on-demand backup with description
- [ ] Listed backups and identified types (AUTOMATED vs ON_DEMAND)
- [ ] Recorded timestamps before and after data changes
- [ ] Performed PITR clone to specific timestamp
- [ ] Verified recovered data on the clone
- [ ] Exported database as SQL dump
- [ ] Exported table as CSV
- [ ] Imported SQL dump into a new database

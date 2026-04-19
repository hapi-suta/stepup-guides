# USE 03 - Backup and Restore

## Objective

Check your server's backup configuration, simulate data loss, perform a point-in-time restore, verify the restored data, and clean up.

---

## Exercise

### Task 1 - Check Backup Configuration

View the current backup settings for your server.

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, BackupRetention:backup.backupRetentionDays, GeoRedundant:backup.geoRedundantBackup, EarliestRestore:backup.earliestRestoreDate}" \
  --output table
```

Expected output (yours will differ):

```
Name                 BackupRetention  GeoRedundant  EarliestRestore
-------------------  ---------------  ------------  -------------------------
suta-pg-lab-server   35               Disabled      2026-03-15T14:30:00+00:00
```

---

### Task 2 - List Available Backups

View the backup history.

```bash
az postgres flexible-server backup list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

Expected output (yours will differ):

```
Name                                    BackupType     CompletedTime
--------------------------------------  -------------  -----------------------------
suta-pg-lab-server-20260419-000000      Full           2026-04-19T00:00:00.000+00:00
suta-pg-lab-server-20260419-000500      Incremental    2026-04-19T00:05:00.000+00:00
...
```

---

### Task 3 - Create Test Data

Connect and create a database with data to restore later.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

```sql
CREATE DATABASE restore_exercise;
```

```sql
\c restore_exercise
```

```sql
CREATE TABLE employees (
    id serial PRIMARY KEY,
    name text NOT NULL,
    department text NOT NULL,
    salary numeric(10,2) NOT NULL
);
```

```sql
INSERT INTO employees (name, department, salary)
VALUES
    ('Alice Chen', 'Engineering', 125000.00),
    ('Bob Smith', 'Marketing', 95000.00),
    ('Carol Davis', 'Engineering', 130000.00),
    ('Dave Wilson', 'Sales', 88000.00),
    ('Eve Brown', 'Engineering', 115000.00);
```

Record the current timestamp. You will restore to this point.

```sql
SELECT now() AS restore_target;
```

Expected output (yours will differ):

```
         restore_target
-------------------------------
 2026-04-19 16:00:00.123456+00
```

Write down this timestamp exactly.

Exit psql.

```sql
\q
```

---

### Task 4 - Wait and Simulate Data Loss

Wait 5 minutes for Azure to capture a transaction log backup. Then simulate accidental data deletion.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=restore_exercise user=pgadmin sslmode=require"
```

```sql
DROP TABLE employees;
```

Verify the table is gone.

```sql
\dt
```

Expected output:

```
Did not find any relations.
```

Exit psql.

```sql
\q
```

---

### Task 5 - Perform Point-in-Time Restore

Restore to the timestamp you recorded in Task 3. Replace the timestamp with your actual value.

```bash
az postgres flexible-server restore \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored-exercise \
  --source-server suta-pg-lab-server \
  --restore-time "2026-04-19T16:00:00Z"
```

This creates a new server. Wait 10-30 minutes for the restore to complete.

---

### Task 6 - Add Firewall Rule to Restored Server

The restored server does not inherit firewall rules. Add your IP. Replace `[YOUR_IP]` with your public IP.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored-exercise \
  --rule-name my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

---

### Task 7 - Verify Restored Data

Connect to the restored server and check the data.

```bash
psql "host=suta-pg-lab-restored-exercise.postgres.database.azure.com port=5432 dbname=restore_exercise user=pgadmin sslmode=require"
```

```sql
SELECT * FROM employees ORDER BY id;
```

Expected output (yours will differ):

```
 id |    name     | department  |  salary
----+-------------+-------------+-----------
  1 | Alice Chen  | Engineering | 125000.00
  2 | Bob Smith   | Marketing   |  95000.00
  3 | Carol Davis | Engineering | 130000.00
  4 | Dave Wilson | Sales       |  88000.00
  5 | Eve Brown   | Engineering | 115000.00
```

All 5 rows are restored. The DROP TABLE never happened at this restore point.

Exit psql.

```sql
\q
```

---

### Task 8 - Clean Up

Delete the restored server to avoid charges.

```bash
az postgres flexible-server delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored-exercise \
  --yes
```

---

## Checklist

- [ ] Backup configuration shows correct retention period
- [ ] Backup list shows recent full and incremental backups
- [ ] Test data created in `restore_exercise` database
- [ ] Timestamp recorded before data loss
- [ ] Data dropped (simulated loss)
- [ ] PITR completed to a new server
- [ ] Firewall rule added to restored server
- [ ] All 5 employee rows verified on restored server
- [ ] Restored server deleted

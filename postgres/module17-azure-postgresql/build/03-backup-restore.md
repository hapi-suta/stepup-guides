# BUILD 03 - Backup and Restore for Azure Database for PostgreSQL Flexible Server

## Overview

In this guide you will configure backup policies for your Flexible Server, understand how automated backups work, perform point-in-time restore (PITR), restore to a new server, and configure geo-redundant backup for disaster recovery.

---

## Prerequisites

- Completed BUILD 01 (server created and accessible)
- Azure CLI authenticated
- psql client installed locally

---

## Step 1 - Understand Automated Backups

Azure Flexible Server performs automated backups with these characteristics:

| Feature | Details |
|---------|---------|
| Backup type | Full snapshot (first) + incremental (subsequent) |
| Frequency | Full backup daily, transaction logs every 5 minutes |
| Retention | 7 days (default), configurable up to 35 days |
| Storage | Zone-redundant by default in regions with availability zones |
| Cost | Backup storage up to 100% of server storage is free |
| Encryption | AES-256 encrypted at rest |

Backups happen automatically. You do not trigger them manually. Azure manages the entire lifecycle.

---

## Step 2 - Check Current Backup Configuration

View your server's backup settings.

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
suta-pg-lab-server   7                Disabled      2026-04-12T14:30:00+00:00
```

The `EarliestRestore` shows the oldest point you can restore to. It depends on your retention period.

---

## Step 3 - Increase Backup Retention

Increase the backup retention period to 35 days (the maximum). The `--backup-retention` flag sets the number of days.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --backup-retention 35
```

Expected output (yours will differ):

```json
{
  "backup": {
    "backupRetentionDays": 35,
    "geoRedundantBackup": "Disabled"
  }
}
```

---

## Step 4 - Enable Geo-Redundant Backup

Geo-redundant backup stores copies in a paired Azure region. If your primary region goes down entirely, you can restore in the paired region.

**Important**: Geo-redundant backup can only be configured at server creation time. You cannot enable it on an existing server. Here is how you would create a new server with geo-redundant backup.

```bash
az postgres flexible-server create \
  --name suta-pg-lab-georedundant \
  --resource-group suta-pg-lab-rg \
  --location eastus \
  --admin-user pgadmin \
  --admin-password 'SutaLab2026!' \
  --sku-name Standard_D2ds_v4 \
  --tier GeneralPurpose \
  --version 16 \
  --storage-size 32 \
  --backup-retention 35 \
  --geo-redundant-backup Enabled \
  --public-access 0.0.0.0
```

The `--geo-redundant-backup` flag enables cross-region backup replication. For `eastus`, the paired region is `westus`.

---

## Step 5 - Create Test Data for PITR

Connect to the server and create data that you will later restore.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=postgres user=pgadmin sslmode=require"
```

Create a test database and table.

```sql
CREATE DATABASE pitr_test;
```

```sql
\c pitr_test
```

```sql
CREATE TABLE orders (
    id serial PRIMARY KEY,
    product text NOT NULL,
    quantity int NOT NULL,
    created_at timestamptz DEFAULT now()
);
```

Insert some data.

```sql
INSERT INTO orders (product, quantity)
VALUES
    ('Widget A', 100),
    ('Widget B', 250),
    ('Widget C', 75);
```

Verify the data.

```sql
SELECT * FROM orders;
```

Expected output (yours will differ):

```
 id | product  | quantity |          created_at
----+----------+----------+-------------------------------
  1 | Widget A |      100 | 2026-04-19 15:00:00.123456+00
  2 | Widget B |      250 | 2026-04-19 15:00:00.123789+00
  3 | Widget C |       75 | 2026-04-19 15:00:00.124012+00
```

Note the current time - you will use a timestamp just before this for PITR.

```sql
SELECT now();
```

Expected output (yours will differ):

```
              now
-------------------------------
 2026-04-19 15:00:30.456789+00
```

Write down this timestamp. You will need it later.

Exit psql.

```sql
\q
```

---

## Step 6 - Simulate Data Loss

Wait at least 5 minutes (for a transaction log backup to complete), then simulate accidental data loss.

```bash
psql "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=pitr_test user=pgadmin sslmode=require"
```

Delete all the data.

```sql
DELETE FROM orders;
```

Verify it is gone.

```sql
SELECT count(*) FROM orders;
```

Expected output:

```
 count
-------
     0
```

Exit psql.

```sql
\q
```

---

## Step 7 - Perform Point-in-Time Restore

PITR creates a new server from a backup at a specific point in time. You cannot restore in-place - it always creates a new server.

The `--restore-time` flag specifies the UTC timestamp to restore to. Use the timestamp you noted in Step 5 (before the DELETE). The `--source-server` flag identifies the server to restore from.

```bash
az postgres flexible-server restore \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored \
  --source-server suta-pg-lab-server \
  --restore-time "2026-04-19T15:00:30Z"
```

Expected output (yours will differ):

```json
{
  "id": "/subscriptions/.../flexibleServers/suta-pg-lab-restored",
  "location": "eastus",
  "name": "suta-pg-lab-restored",
  "state": "Ready"
}
```

This takes 10-30 minutes depending on data size. Wait for it to complete.

---

## Step 8 - Verify Restored Data

Add a firewall rule to the restored server so you can connect. Replace `[YOUR_IP]` with your public IP.

```bash
az postgres flexible-server firewall-rule create \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored \
  --rule-name allow-my-ip \
  --start-ip-address [YOUR_IP] \
  --end-ip-address [YOUR_IP]
```

Connect to the restored server.

```bash
psql "host=suta-pg-lab-restored.postgres.database.azure.com port=5432 dbname=pitr_test user=pgadmin sslmode=require"
```

Check the data.

```sql
SELECT * FROM orders;
```

Expected output (yours will differ):

```
 id | product  | quantity |          created_at
----+----------+----------+-------------------------------
  1 | Widget A |      100 | 2026-04-19 15:00:00.123456+00
  2 | Widget B |      250 | 2026-04-19 15:00:00.123789+00
  3 | Widget C |       75 | 2026-04-19 15:00:00.124012+00
```

All three rows are restored. The DELETE never happened in this timeline.

Exit psql.

```sql
\q
```

---

## Step 9 - Geo-Redundant Restore

If you have geo-redundant backup enabled and your primary region is down, you can restore in the paired region. The `--geo-redundant-backup-restore` flag triggers a geo-restore.

```bash
az postgres flexible-server geo-restore \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-geo-restored \
  --source-server suta-pg-lab-georedundant \
  --location westus
```

The `--location` must be the geo-paired region. This creates a new server in the target region from the geo-replicated backup.

Geo-restore RPO can be up to 1 hour because geo-replicated backups lag behind the primary.

---

## Step 10 - Understand PITR Limitations

Keep these limitations in mind:

- **Creates a new server** - PITR always restores to a new server. You cannot overwrite the original.
- **Same region only** - Standard PITR restores within the same region. Use geo-restore for cross-region.
- **Restore window** - You can only restore within your retention period (7-35 days).
- **Server parameters** - The restored server inherits the source server's parameters at the time of backup, not at the time you run the restore.
- **Firewall rules** - Firewall rules are NOT copied. You must recreate them on the restored server.
- **VNet integration** - The restored server uses the same networking mode as the source.
- **HA** - HA is not enabled on the restored server. You must re-enable it.
- **DNS** - The restored server has a different FQDN. Update your application connection strings.

---

## Step 11 - Long-Term Retention

For backups beyond 35 days, Azure offers long-term retention (LTR). This stores backups for up to 10 years.

Check if LTR is available for your server.

```bash
az postgres flexible-server backup list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

Expected output (yours will differ):

```
Name                                    BackupType     CompletedTime                  Source
--------------------------------------  -------------  -----------------------------  --------
suta-pg-lab-server-20260419-150000      Full           2026-04-19T15:00:00.000+00:00  Automatic
suta-pg-lab-server-20260419-150500      Incremental    2026-04-19T15:05:00.000+00:00  Automatic
```

For LTR beyond 35 days, consider using Azure Backup vault or exporting with pg_dump on a schedule.

---

## Step 12 - Export with pg_dump for External Backup

For extra safety, export a logical backup to Azure Blob Storage. First, create a dump file.

```bash
pg_dump "host=suta-pg-lab-server.postgres.database.azure.com port=5432 dbname=pitr_test user=pgadmin sslmode=require" --format=custom --file=/tmp/pitr_test_backup.dump
```

The `--format=custom` flag creates a compressed binary format that supports selective restore. The `--file` flag specifies the output path.

Expected output (yours will differ):

```
(no output on success, check file size)
```

Verify the backup file.

```bash
ls -lh /tmp/pitr_test_backup.dump
```

Expected output (yours will differ):

```
-rw-r--r--  1 user  staff  4.2K Apr 19 15:15 /tmp/pitr_test_backup.dump
```

---

## Step 13 - Clean Up Restored Servers

Delete the restored servers to avoid ongoing charges.

```bash
az postgres flexible-server delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-restored \
  --yes
```

```bash
az postgres flexible-server delete \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-georedundant \
  --yes
```

---

## Summary

You have completed the following:

- Understood automated backup mechanics (full + incremental, 5-minute log backups)
- Checked and increased backup retention to 35 days
- Learned how to enable geo-redundant backup at creation time
- Created test data and simulated data loss
- Performed point-in-time restore to recover deleted data
- Understood PITR limitations (new server, no firewall copy, same region)
- Explored geo-redundant restore for cross-region disaster recovery
- Created a pg_dump backup for external storage

Key takeaway: Azure handles backup scheduling and storage automatically. Your main decisions are retention period (7-35 days) and whether to enable geo-redundant backup for cross-region protection.

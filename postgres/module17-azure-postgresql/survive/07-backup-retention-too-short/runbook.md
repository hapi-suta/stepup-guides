# SURVIVE 07 - Backup Retention Too Short Runbook

## Symptom

A compliance audit reveals that backup retention is set to only 7 days. Company policy requires at least 30 days of point-in-time recovery capability. If data corruption occurred more than 7 days ago, recovery is impossible.

---

## Diagnosis

### Step 1 - Check Current Backup Retention

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{Name:name, BackupRetention:backup.backupRetentionDays, GeoRedundant:backup.geoRedundantBackup, EarliestRestore:backup.earliestRestoreDate}" \
  --output table
```

If `BackupRetention` is 7, it needs to be increased.

### Step 2 - Check Earliest Restore Point

The `EarliestRestore` value shows how far back you can currently restore. With 7-day retention, this is approximately 7 days ago.

---

## Fix

### Step 3 - Increase Backup Retention

Set retention to 30 days. The maximum is 35 days.

```bash
az postgres flexible-server update \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --backup-retention 30
```

### Step 4 - Verify the Change

```bash
az postgres flexible-server show \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --query "{BackupRetention:backup.backupRetentionDays, EarliestRestore:backup.earliestRestoreDate}" \
  --output table
```

Expected output (yours will differ):

```
BackupRetention  EarliestRestore
---------------  -------------------------
30               2026-03-20T14:30:00+00:00
```

Note: The `EarliestRestore` date will not immediately change to 30 days ago. It reflects the oldest backup that actually exists. Over the next 30 days, the restore window will expand.

### Step 5 - List Available Backups

Confirm backups are being taken.

```bash
az postgres flexible-server backup list \
  --resource-group suta-pg-lab-rg \
  --name suta-pg-lab-server \
  --output table
```

---

## Prevention

- Set backup retention to at least 30 days for all production servers
- Use Azure Policy to enforce minimum backup retention across the organization
- Consider geo-redundant backup for disaster recovery (must be set at creation time)
- For retention beyond 35 days, use Azure Backup vault or scheduled pg_dump exports
- Document backup requirements in your disaster recovery plan

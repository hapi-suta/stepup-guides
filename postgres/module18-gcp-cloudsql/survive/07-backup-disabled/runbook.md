# RUNBOOK: Automated Backups Disabled

## Symptom

Automated backups are not running. The backup list shows no recent AUTOMATED backups. PITR is unavailable.

---

## Step 1 - Check Backup Configuration

View the current backup settings.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.backupConfiguration)"
```

If `enabled: false` and `pointInTimeRecoveryEnabled: false`, backups are completely off.

---

## Step 2 - Re-enable Automated Backups

Enable backups with a scheduled window.

```bash
gcloud sql instances patch suta-pg-lab \
  --backup-start-time=04:00
```

The `--backup-start-time` flag automatically enables backups and sets the daily window.

---

## Step 3 - Re-enable Point-in-Time Recovery

Enable PITR for continuous WAL archiving.

```bash
gcloud sql instances patch suta-pg-lab --enable-point-in-time-recovery
```

Set transaction log retention to 7 days.

```bash
gcloud sql instances patch suta-pg-lab --retained-transaction-log-days=7
```

Set backup retention to keep the last 14 backups.

```bash
gcloud sql instances patch suta-pg-lab --retained-backups-count=14
```

---

## Step 4 - Take an Immediate Backup

Do not wait for the next scheduled window. Take a backup now.

```bash
gcloud sql backups create --instance=suta-pg-lab --description="emergency-backup-after-re-enable"
```

---

## Step 5 - Verify Backup Configuration

Confirm all settings are correct.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.backupConfiguration)"
```

Expected key values:
- `enabled: true`
- `pointInTimeRecoveryEnabled: true`
- `startTime: '04:00'`
- `transactionLogRetentionDays: 7`
- `retainedBackups: 14`

---

## Step 6 - Verify the Backup Exists

List recent backups.

```bash
gcloud sql backups list --instance=suta-pg-lab --sort-by=~startTime --limit=5
```

Verify your on-demand backup appears with status SUCCESSFUL.

---

## Prevention

- Set up Cloud Audit Log alerts for backup configuration changes
- Use IAM to restrict who can modify backup settings
- Include backup configuration in infrastructure-as-code (Terraform)
- Run a weekly automated check that verifies backups are enabled
- Never disable backups on production - ever

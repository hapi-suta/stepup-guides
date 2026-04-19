# RUNBOOK: Storage Full

## Symptom

Write operations are failing with "could not extend file" or "No space left on device" errors. The instance may have entered read-only mode.

---

## Step 1 - Check Current Disk Usage

Get the disk size and usage.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.dataDiskSizeGb,settings.storageAutoResize,settings.storageAutoResizeLimit)"
```

---

## Step 2 - Check If Auto-Resize Is Disabled

If `storageAutoResize` is false, the disk will not grow automatically.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.storageAutoResize)"
```

If the output is `False`, that is the problem.

---

## Step 3 - Re-enable Auto-Resize

Enable storage auto-increase with a reasonable limit.

```bash
gcloud sql instances patch suta-pg-lab \
  --storage-auto-increase \
  --storage-auto-increase-limit=100
```

The `--storage-auto-increase-limit` sets the maximum disk size in GB. Set to 0 for no limit (not recommended).

---

## Step 4 - Manually Increase Storage (If Urgent)

If auto-resize is not fast enough, manually increase the disk.

```bash
gcloud sql instances patch suta-pg-lab --storage-size=50
```

WARNING: Disk size can only be increased, never decreased. Choose wisely.

---

## Step 5 - Clean Up Bloat Data

Connect and remove unnecessary data to free space.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

Find the largest tables.

```sql
SELECT
    relname AS table_name,
    pg_size_pretty(pg_total_relation_size(oid)) AS total_size
FROM pg_class
WHERE relkind = 'r'
ORDER BY pg_total_relation_size(oid) DESC
LIMIT 10;
```

Drop bloat data if it exists.

```sql
DROP TABLE IF EXISTS bloat_data;
```

Reclaim disk space.

```sql
VACUUM FULL;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 6 - Verify Recovery

Check that writes work.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab -c "CREATE TABLE storage_test (id int); DROP TABLE storage_test;"
```

Check disk usage metrics.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.dataDiskSizeGb,settings.storageAutoResize)"
```

---

## Prevention

- Always enable `--storage-auto-increase` with a reasonable limit
- Set up alerts for `cloudsql.googleapis.com/database/disk/utilization` > 0.85
- Regularly VACUUM and clean up old data
- Monitor table bloat with `pg_stat_user_tables`

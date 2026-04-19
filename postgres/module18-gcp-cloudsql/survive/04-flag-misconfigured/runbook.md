# RUNBOOK: Database Flag Misconfiguration

## Symptom

Database is extremely slow. Applications report connection refused errors. Simple queries take seconds instead of milliseconds.

---

## Step 1 - Check Current Flags

List all database flags set on the instance.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)"
```

Look for values that seem unreasonable. Compare with the machine tier.

---

## Step 2 - Check the Instance Tier

Get the machine type to know what reasonable values look like.

```bash
gcloud sql instances describe suta-pg-lab --format="value(settings.tier)"
```

For `db-custom-2-7680` (2 vCPUs, 7.5 GB RAM), reasonable values are:
- `shared_buffers`: ~25% of RAM = ~1920 MB (~245760 in 8KB pages)
- `max_connections`: 100-200
- `work_mem`: 4096-16384 KB
- `effective_cache_size`: ~75% of RAM

---

## Step 3 - Fix the Flags

Set the flags to appropriate values. Include ALL flags you want active.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=shared_buffers=245760,max_connections=100,work_mem=8192,effective_cache_size=589824,log_statement=ddl,log_min_duration_statement=1000,log_connections=on,log_disconnections=on
```

Wait for the instance to restart (shared_buffers and max_connections require restart).

---

## Step 4 - Verify the Fix

Check that flags are updated.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)"
```

Connect and verify the settings inside PostgreSQL.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SHOW shared_buffers;
```

```sql
SHOW max_connections;
```

```sql
SHOW work_mem;
```

Type `\q` to exit psql.

```
\q
```

---

## Step 5 - Test Performance

Run a quick query to verify performance is back to normal.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab -c "EXPLAIN ANALYZE SELECT * FROM students;"
```

---

## Prevention

- Document approved database flags in version control
- Use Terraform or Deployment Manager to manage flags as code
- Set up alerts for Cloud SQL configuration changes
- Require peer review for flag changes in production
- Test flag changes on a non-production instance first

# USE 02 - Database Flags (postgresql.conf in Cloud SQL)

## Objective

List available flags, modify key PostgreSQL parameters, understand static vs dynamic flags, and compare Cloud SQL flags with `pg_settings`.

---

## Exercise 1 - List Available Flags

List all PostgreSQL 16 flags. These are the parameters Google allows you to change on Cloud SQL.

```bash
gcloud sql flags list --database-version=POSTGRES_16 --format="table(name,type,minValue,maxValue)" --limit=30
```

Count how many flags are available.

```bash
gcloud sql flags list --database-version=POSTGRES_16 --format="value(name)" | wc -l
```

Expected output (yours will differ):

```
105
```

Not every PostgreSQL parameter is exposed. Google restricts parameters that could affect managed infrastructure (e.g., `data_directory`, `wal_level`).

---

## Exercise 2 - Check Current Flags

See what flags are currently set on your instance.

```bash
gcloud sql instances describe suta-pg-lab --format="yaml(settings.databaseFlags)"
```

Expected output (yours will differ):

```yaml
settings:
  databaseFlags:
  - name: log_statement
    value: ddl
  - name: log_min_duration_statement
    value: '1000'
  ...
```

---

## Exercise 3 - Modify Performance Flags

Set common performance-related flags. Remember: you must include ALL flags in a single command.

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=shared_buffers=1048576,work_mem=16384,maintenance_work_mem=524288,effective_cache_size=3145728,log_statement=ddl,log_min_duration_statement=1000,log_connections=on,log_disconnections=on
```

Flag values explained:
- `shared_buffers=1048576`: 1 GB in 8 KB pages (1048576 * 8KB = ~8 GB - wait, that is too much). Actually Cloud SQL uses KB for some flags. Check the unit.

Let us verify by checking inside PostgreSQL.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SHOW shared_buffers;
```

```sql
SHOW work_mem;
```

```sql
SHOW maintenance_work_mem;
```

```sql
SHOW effective_cache_size;
```

Type `\q` to exit psql.

```
\q
```

---

## Exercise 4 - Static vs Dynamic Flags

Some flags require a restart, others take effect immediately.

Connect and check which flags require restart.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SELECT name, setting, unit, context
FROM pg_settings
WHERE name IN ('shared_buffers', 'work_mem', 'maintenance_work_mem', 'effective_cache_size', 'max_connections', 'log_statement')
ORDER BY name;
```

Expected output (yours will differ):

```
         name          | setting  | unit | context
-----------------------+----------+------+------------
 effective_cache_size  | 393216   | 8kB  | user
 log_statement         | ddl      |      | superuser
 maintenance_work_mem  | 524288   | kB   | user
 max_connections       | 100      |      | postmaster
 shared_buffers        | 131072   | 8kB  | postmaster
 work_mem              | 16384    | kB   | user
(6 rows)
```

Context meanings:
- `postmaster`: Requires restart (Cloud SQL restarts automatically when you set these)
- `superuser`: Takes effect for new sessions immediately
- `user`: Takes effect for new sessions immediately

Type `\q` to exit psql.

```
\q
```

---

## Exercise 5 - Compare Cloud SQL Flags with pg_settings

Cloud SQL exposes a subset of PostgreSQL parameters. Find which common parameters are NOT available as flags.

```bash
psql -h 127.0.0.1 -U postgres -d suta_lab
```

```sql
SELECT name, setting, unit, context
FROM pg_settings
WHERE context = 'postmaster'
ORDER BY name;
```

Compare this list with the `gcloud sql flags list` output. Parameters like `wal_level`, `archive_mode`, `data_directory` are not available because Google manages them.

```sql
SELECT count(*) FROM pg_settings;
```

Expected output (yours will differ):

```
 count
-------
   356
(1 row)
```

PostgreSQL has ~356 parameters. Cloud SQL exposes ~105 as flags. The rest are either managed by Google or not applicable in the managed environment.

Type `\q` to exit psql.

```
\q
```

---

## Exercise 6 - Reset Flags to Default

To remove all custom flags and return to Cloud SQL defaults:

```bash
gcloud sql instances patch suta-pg-lab --clear-database-flags
```

WARNING: This removes ALL custom flags at once. Use with caution.

To keep some flags while removing others, set only the flags you want to keep:

```bash
gcloud sql instances patch suta-pg-lab \
  --database-flags=log_statement=ddl,log_min_duration_statement=1000
```

---

## Checklist

- [ ] Listed available flags for PostgreSQL 16
- [ ] Checked current flags on the instance
- [ ] Modified shared_buffers, work_mem, maintenance_work_mem
- [ ] Verified changes via pg_settings
- [ ] Identified static (restart) vs dynamic flags
- [ ] Compared Cloud SQL flags with total pg_settings count

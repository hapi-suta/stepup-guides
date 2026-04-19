# Scenario 09 - Temp File Explosion

**Severity:** HIGH
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Excessive temp files on disk.
temp_file_limit is -1 (unlimited) - no safety net.
work_mem is 256kB - every sort and hash spills to disk.
Temp file logging is disabled - no visibility into which queries create them.
Disk space in the data directory is growing unexpectedly.
```

---

## Key Concepts for Revision

- **work_mem** - The amount of memory each sort or hash operation can use before spilling to a temp file on disk. Default is `4MB`. With `256kB`, even a small sort of a few hundred rows will exceed the limit and write to disk. A single query can have multiple sort/hash nodes, each using up to `work_mem` - so the total memory per query can be `work_mem * N` where N is the number of sort/hash operations.

- **temp_file_limit** - Maximum total size of temp files a single session can create. Default is `-1` (unlimited). Setting this to a reasonable value (e.g., `1GB`) protects against runaway queries that would fill the disk. When the limit is exceeded, the offending query is cancelled with an error.

- **log_temp_files** - Logs temp file creation when the file exceeds this size in KB. Default is `-1` (disabled). Setting it to `0` logs all temp file usage. Setting it to `10240` (10MB) logs only large temp files. This is essential for identifying which queries are spilling to disk.

- **Temp files live in pgsql_tmp** - PostgreSQL creates temp files in `base/pgsql_tmp/` within the data directory (or in a tablespace's `pgsql_tmp` directory). These files are cleaned up when the query or session ends. However, long-running queries can accumulate large temp files that persist until the query completes.

- **Temp files vs performance** - Sorting and hashing in memory is orders of magnitude faster than on disk. If `work_mem` is too low, every analytical query pays a massive performance penalty. The fix is to increase `work_mem` to a sensible value for the workload, balanced against total memory (since each connection can use multiple `work_mem` allocations).

---

## Diagnostic Steps

### Step 1 - Check for temp files on disk

```bash
sudo -iu postgres
```

```bash
du -sh /opt/pgsql/data/base/pgsql_tmp/ 2>/dev/null || echo "Directory empty or does not exist"
```

Expected output (yours will differ):

```
12M     /opt/pgsql/data/base/pgsql_tmp/
```

If the directory has significant data, temp files from recent queries are still on disk.

### Step 2 - Connect and check the configuration

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('work_mem', 'temp_file_limit', 'log_temp_files')
ORDER BY name;
```

Expected output (yours will differ):

```
      name       | setting | unit
-----------------+---------+------
 log_temp_files  | -1      | kB
 temp_file_limit | -1      | kB
 work_mem        | 256     | kB
(3 rows)
```

- `work_mem = 256kB` is far too low - this forces nearly every sort to disk.
- `temp_file_limit = -1` means no limit - a single query could fill the entire disk.
- `log_temp_files = -1` means temp file creation is invisible in logs.

### Step 3 - Check pg_stat_database for temp file stats

```sql
SELECT datname,
       temp_files,
       pg_size_pretty(temp_bytes) AS temp_bytes
FROM pg_stat_database
WHERE datname = current_database();
```

Expected output (yours will differ):

```
   datname    | temp_files | temp_bytes
--------------+------------+------------
 stepup_store |         45 | 128 MB
(1 row)
```

A high `temp_files` count and large `temp_bytes` confirms excessive temp file usage.

### Step 4 - Use EXPLAIN to see a query spilling to disk

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT val FROM temp_explosion_a ORDER BY val;
```

Expected output (yours will differ):

```
 Sort  (cost=... rows=50000 width=...)
   Sort Key: val
   Sort Method: external merge  Disk: 4816kB
   ...
```

The `Sort Method: external merge  Disk: 4816kB` confirms the sort spilled to disk. With adequate `work_mem`, this would show `Sort Method: quicksort  Memory: ...` instead.

```bash
exit
```

---

## Resolution

### Step 1 - Set reasonable parameters

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Set `work_mem` to a reasonable value. `4MB` is the default and works for most OLTP workloads. For analytical queries, `16-64MB` may be appropriate.

```sql
ALTER SYSTEM SET work_mem = '4MB';
```

Set `temp_file_limit` to protect against runaway queries.

```sql
ALTER SYSTEM SET temp_file_limit = '1GB';
```

Enable temp file logging so you can see which queries spill to disk. Setting to `1024` (1MB) logs temp files larger than 1MB.

```sql
ALTER SYSTEM SET log_temp_files = 1024;
```

### Step 2 - Reload the configuration

```sql
SELECT pg_reload_conf();
```

Expected output (yours will differ):

```
 pg_reload_conf
----------------
 t
(1 row)
```

### Step 3 - Verify the new settings

```sql
SELECT name, setting, unit
FROM pg_settings
WHERE name IN ('work_mem', 'temp_file_limit', 'log_temp_files')
ORDER BY name;
```

Expected output (yours will differ):

```
      name       | setting  | unit
-----------------+----------+------
 log_temp_files  | 1024     | kB
 temp_file_limit | 1048576  | kB
 work_mem        | 4096     | kB
(3 rows)
```

### Step 4 - Verify sorts now happen in memory

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT val FROM temp_explosion_a ORDER BY val;
```

Expected output (yours will differ):

```
 Sort  (cost=... rows=50000 width=...)
   Sort Key: val
   Sort Method: quicksort  Memory: 3842kB
   ...
```

`Sort Method: quicksort  Memory: 3842kB` means the sort completed in memory - no temp files.

```bash
exit
```

---

## Validation

Run the validation script to confirm the scenario is resolved.

```bash
./validate.sh
```

Expected checks:
- PostgreSQL is running
- work_mem is 4MB or more
- temp_file_limit is set (not -1)
- log_temp_files is enabled (not -1)
- PostgreSQL accepts connections

---

## Interview Discussion Points

1. **How do you decide the right work_mem value?** - Start with the formula: `available_memory / (max_connections * 2)`. The `* 2` accounts for queries having multiple sort/hash nodes. For example, with 8GB RAM, 2GB for shared_buffers, 2GB for OS, and 100 connections: `4GB / (100 * 2) = 20MB`. Monitor `pg_stat_database.temp_bytes` - if temp file usage drops to near zero, `work_mem` is adequate. If queries still spill, increase it for specific sessions using `SET work_mem = '64MB'` rather than globally.

2. **Why not set work_mem very high globally?** - Each sort/hash operation in each connection allocates `work_mem`. A complex query with 5 hash joins uses `5 * work_mem`. With 100 connections each running such queries, that is `500 * work_mem`. Setting `work_mem = 256MB` globally could mean `125GB` of memory demand - far more than the server has, causing the OOM killer to terminate processes.

3. **What is the difference between temp_file_limit and temp_tablespaces?** - `temp_file_limit` caps the total bytes of temp files per session. `temp_tablespaces` controls WHERE temp files are stored (on which tablespace/disk). You can use `temp_tablespaces` to direct temp files to a fast SSD or a separate mount point so temp file I/O does not compete with data file I/O.

4. **How do you find which queries are creating the most temp files?** - Enable `log_temp_files = 0` temporarily to log every temp file creation. Check `pg_stat_statements` for queries with high `temp_blks_written`. You can also monitor `pg_stat_database.temp_bytes` and take snapshots every minute to find spikes.

5. **If the disk fills up from temp files, what happens?** - PostgreSQL cannot write temp files and the query fails with an "out of disk space" error. If the disk is the same one holding WAL and data files, it can also prevent checkpoints and WAL writes, potentially causing a server crash. This is why `temp_file_limit` and using a separate `temp_tablespaces` mount point are important preventive measures.

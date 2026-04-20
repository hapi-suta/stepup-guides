# Runbook 08 - Corrupted Page Header

| Field         | Value                                           |
|---------------|-------------------------------------------------|
| Scenario      | Page 0 header corruption on a table              |
| Severity      | HIGH                                            |
| Recovery Time | 10-20 minutes                                   |
| Blast Radius  | Single table unreadable, rest of database intact |

---

## Fix Path

### Step 1 - Reproduce the Error

Try to query the corrupted table.

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT count(*) FROM chaos_corrupt_test;
"
```

You will see an error like:
```
ERROR:  invalid page in block 0 of relation base/16384/16xxx
```

This confirms a corrupted page header.

```bash
exit
```

### Step 2 - Check PostgreSQL Logs

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Look for lines mentioning:
- `invalid page in block 0`
- The relation OID or file path

Expected output (yours will differ):
```
2026-04-19 14:20:05.312 UTC [2345] ERROR:  invalid page in block 0 of relation base/16384/16421
2026-04-19 14:20:05.312 UTC [2345] STATEMENT:  SELECT count(*) FROM chaos_corrupt_test;
...
```

### Step 3 - Identify the Table from the Error

The error message includes the relation file path (e.g., `base/16384/16xxx`). Match it to a table name.

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT c.relname, c.oid, pg_relation_filepath(c.oid)
  FROM pg_class c
  WHERE pg_relation_filepath(c.oid) IS NOT NULL
  ORDER BY c.oid DESC
  LIMIT 20;
"
```
```bash
exit
```

Find the row where the filepath matches the error message.

### Step 4 - Attempt to Read Past the Corruption

The `zero_damaged_pages` parameter tells PostgreSQL to zero out corrupted pages instead of throwing an error. This causes data loss on the affected page but lets you read the rest of the table.

**WARNING**: This is a diagnostic tool, not a production fix. It permanently destroys data on the corrupted page when the page is accessed.

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SET zero_damaged_pages = on;
  SELECT count(*) FROM chaos_corrupt_test;
"
```
```bash
exit
```

PostgreSQL will report a WARNING about zeroing the page and return results from the remaining pages. The count will be less than 1000 because rows on page 0 are lost.

Expected output (yours will differ):
```
SET
WARNING:  invalid page in block 0 of relation base/16384/16421; zeroing out page
 count
-------
   909
(1 row)
```

### Step 5 - Understand Production Recovery Options

In production, you would NOT use `zero_damaged_pages` on important data. Instead:

1. **Restore from backup** - Use `pg_basebackup` or your backup tool to restore the table or database
2. **Point-in-time recovery (PITR)** - Restore to a point before the corruption occurred
3. **pg_amcheck** - Run `pg_amcheck` to scan for additional corruption across the database

For this lab, since `chaos_corrupt_test` is a test table, we can safely drop it.

### Step 6 - Drop the Corrupted Table

```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SET zero_damaged_pages = on;
  DROP TABLE IF EXISTS chaos_corrupt_test;
"
```

You may need `zero_damaged_pages = on` for the DROP to succeed if PostgreSQL tries to read the corrupted page during the operation.

### Step 7 - Verify Database Health

Check that no other tables are corrupted.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  SELECT schemaname, relname
  FROM pg_stat_user_tables;
"
```

Try a simple query on an existing table to confirm the database is functional.

```bash
/usr/pgsql-16/bin/psql -d labdb -c "SELECT 1;"
```

Expected output:
```
 ?column?
----------
        1
(1 row)
```

```bash
exit
```

---

## Revision Concepts

### Page Header Structure

Every PostgreSQL data file is divided into 8 KB pages (blocks). Each page has a 24-byte header containing:

| Bytes  | Field            | Purpose                                    |
|--------|------------------|--------------------------------------------|
| 0-7    | pd_lsn           | LSN of last WAL record that modified page  |
| 8-9    | pd_checksum       | Page checksum (if enabled)                 |
| 10-11  | pd_flags          | Page flags                                 |
| 12-13  | pd_lower          | Offset to start of free space              |
| 14-15  | pd_upper          | Offset to end of free space                |
| 16-17  | pd_special        | Offset to start of special space           |
| 18-19  | pd_pagesize_ver   | Page size and version                      |
| 20-23  | pd_prune_xid      | Oldest XID eligible for pruning            |

When the header is zeroed, PostgreSQL cannot interpret the page - the size/version check fails, producing the "invalid page" error.

### Data Checksums

PostgreSQL supports page-level checksums (enabled at `initdb` time with `--data-checksums`). When enabled:
- Every page write computes a checksum stored in `pd_checksum`
- Every page read verifies the checksum
- Corruption is detected immediately, not when a query happens to hit the page

Check if checksums are enabled:
```bash
sudo -iu postgres
```
```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data | grep checksum
```

### zero_damaged_pages

This parameter is a last-resort diagnostic tool. When set to `on`:
- PostgreSQL zeroes out any page that fails validation
- This permanently destroys all rows on that page
- It should NEVER be set globally in `postgresql.conf`
- Use it only in a session (SET) for diagnostic purposes

### pg_amcheck

PostgreSQL 14+ includes `pg_amcheck`, a tool to check for corruption across all tables and indexes:

```bash
/usr/pgsql-16/bin/pg_amcheck --all
```
```bash
exit
```

This is useful after discovering corruption to determine if it is isolated or widespread.

---

## Interview Discussion

**Q: How would you detect data corruption in production?**

If data checksums are enabled, PostgreSQL detects corruption on read and logs a WARNING. Without checksums, corruption may go undetected until a query hits the affected page - which could be days or weeks later. Proactive detection requires running `pg_amcheck` periodically or enabling checksums.

**Q: What is the danger of using zero_damaged_pages in production?**

It silently destroys data. When PostgreSQL encounters a corrupted page with this setting on, it replaces the entire page with zeros - all rows on that page are permanently lost. There is no recovery. The data is gone. It should only be used as a diagnostic step to understand the scope of damage, never as a permanent fix.

**Q: Should data checksums always be enabled?**

Yes, for production systems. The CPU overhead is minimal (1-2%). The benefit is early detection of corruption caused by storage hardware failures, firmware bugs, or filesystem issues. Without checksums, you may silently serve corrupted data. The only downside is that checksums must be enabled at initdb time (cannot be changed later without `pg_checksums` tool and downtime).

**Q: What causes data corruption?**

- Storage hardware failures (bad sectors, failing disks)
- Firmware bugs in RAID controllers or SSDs
- Filesystem bugs or misconfiguration (e.g., not using data=ordered with ext4)
- Memory (RAM) errors without ECC
- Improper use of `dd` or other tools on data files
- Killing PostgreSQL with `kill -9` during a write (rare but possible)
- VM snapshots that do not flush disk buffers

**Q: After finding corruption, what are the recovery options?**

1. Restore from a known-good backup (most reliable)
2. Point-in-time recovery to just before the corruption
3. If only indexes are corrupted, REINDEX
4. For a single table, `zero_damaged_pages` + dump the surviving rows + restore from dump
5. Use `pg_filedump` to manually inspect and salvage data from the raw file

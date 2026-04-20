# Scenario 05 - Data Checksums Mismatch

**Severity:** MEDIUM
**Expected Recovery Time:** 10-15 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: A test cluster (port 5437) has suspected
data corruption after a storage event.
Users report errors when querying certain tables.
The main cluster on port 5432 is unaffected.

Cluster data dir: /opt/pgsql/data-checksum
Cluster port: 5437
```

---

## Key Concepts for Revision

Before diving into the fix, make sure you understand these concepts:

- **Data checksums** - PostgreSQL can calculate and store a checksum for every 8KB data page on disk. When enabled (via `initdb --data-checksums`), PostgreSQL verifies the checksum every time it reads a page from disk into shared_buffers. If the checksum does not match, PostgreSQL raises a WARNING and returns an error for that page. Checksums detect silent corruption from disk hardware failures, firmware bugs, or filesystem errors.

- **pg_controldata** - A command-line tool that reads the control file (`global/pg_control`) and displays cluster metadata, including whether data checksums are enabled. The output line "Data page checksum version" shows `1` if checksums are enabled, `0` if disabled.

- **ignore_checksum_failure** - A GUC parameter (default `off`) that, when set to `on`, allows PostgreSQL to return data from corrupt pages instead of throwing an error. The corruption WARNING still appears in the logs. This is a last-resort tool for salvaging readable data from a corrupt table before restoring from backup. Never leave this on in production.

- **Block/page structure** - PostgreSQL stores table data in 8KB pages (blocks). Block 0 is the first page of a table file. Each page has a header (24 bytes) containing the checksum, LSN, and other metadata, followed by item pointers and tuple data. Corrupting even a few bytes in the header breaks the checksum.

- **Why checksums matter** - Without checksums, silent corruption goes undetected. A disk might flip a bit in a data page, and PostgreSQL would happily serve wrong data forever. Checksums catch this at read time. The tradeoff is a small CPU overhead (roughly 1-2% for write-heavy workloads). Most production deployments should enable checksums.

---

## Diagnostic Steps

### Step 1 - Verify the main cluster is healthy

Before touching the corrupt cluster, confirm the main cluster on port 5432 is fine.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 16.x on x86_64-pc-linux-gnu ...
(1 row)
```

The main cluster is healthy. Leave it alone.

```bash
exit
```

### Step 2 - Check if the corrupt cluster is running

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/pg_isready -p 5437
```

Expected output:

```
/var/run/postgresql:5437 - accepting connections
```

### Step 3 - Confirm checksums are enabled on the corrupt cluster

```bash
/usr/pgsql-16/bin/pg_controldata /opt/pgsql/data-checksum | grep checksum
```

Expected output:

```
Data page checksum version:           1
```

Checksum version `1` means checksums are enabled.

### Step 4 - Try to query the corrupted table

```bash
/usr/pgsql-16/bin/psql -p 5437 -d postgres -c "SELECT * FROM corruption_test;"
```

Expected output (yours will differ):

```
WARNING:  page verification failed, calculated checksum 12345 but expected 54321
ERROR:  invalid page in block 1 of relation base/5/16384
```

PostgreSQL detected the checksum mismatch and refused to return data from the corrupt block.

### Step 5 - Check the PostgreSQL logs for corruption details

```bash
cat /opt/pgsql/data-checksum/log/startup.log
```

Expected output (yours will differ):

```
LOG:  database system is ready to accept connections
...
```

```bash
exit
```

---

## Resolution

Since this is a corrupt test cluster with no backup, the goal is to salvage what data you can, then clean up.

### Step 1 - Attempt to read data with ignore_checksum_failure

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5437 -d postgres
```

Inside psql, enable the bypass:

```sql
SET ignore_checksum_failure = on;
```

### Step 2 - Try to read the data

```sql
SELECT count(*) FROM corruption_test;
```

Expected output (yours will differ):

```
WARNING:  page verification failed, calculated checksum 12345 but expected 54321
 count
-------
   500
(1 row)
```

PostgreSQL still warns about the corruption but returns data. Some rows from the corrupt block may contain garbage values.

### Step 3 - Salvage good data by skipping the corrupt block

```sql
SELECT count(*) FROM corruption_test WHERE ctid::text NOT LIKE '(1,%';
```

Expected output (yours will differ):

```
 count
-------
   470
(1 row)
```

This skips rows stored in block 1 (the corrupted block).

### Step 4 - Exit psql

```sql
\q
```

### Step 5 - Stop the corrupt cluster

```bash
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data-checksum stop -m fast
```

`-m fast` uses fast shutdown mode, which disconnects all clients immediately and shuts down cleanly without waiting for clients to disconnect on their own.

Expected output:

```
waiting for server to shut down.... done
server stopped
```

### Step 6 - Remove the corrupt cluster data directory

This cluster is a test cluster with no backup. In production, you would restore from a backup instead of deleting.

```bash
rm -rf /opt/pgsql/data-checksum
```

### Step 7 - Verify the directory is gone

```bash
ls /opt/pgsql/data-checksum
```

Expected output:

```
ls: cannot access '/opt/pgsql/data-checksum': No such file or directory
```

```bash
exit
```

### Step 8 - Confirm the main cluster is still healthy

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT count(*) FROM pg_stat_activity;"
```

Expected output (yours will differ):

```
 count
-------
     5
(1 row)
```

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
- Main PostgreSQL (port 5432) is running
- Main PostgreSQL accepts connections
- Corrupt temp cluster (port 5437) is stopped
- Corrupt cluster data directory removed
- Main PostgreSQL is fully functional

---

## Interview Discussion Points

1. **Should you enable data checksums on a production database?** - Yes. The PostgreSQL community strongly recommends it. The CPU overhead is minimal (1-2%), and the protection against silent corruption is invaluable. Without checksums, a bad disk sector could silently corrupt data that gets served to applications for months before anyone notices. Since PG12, you can enable checksums on an existing cluster using `pg_checksums --enable` (requires downtime).

2. **What causes data page corruption in practice?** - The most common causes are: (a) failing storage hardware (bad sectors, dying SSDs), (b) firmware bugs in RAID controllers or SSDs, (c) filesystem bugs, (d) memory errors (ECC RAM prevents this), (e) bugs in storage drivers. Less common: operator error (running `dd` on a database file, restoring from a partial backup). Checksums catch all of these at read time.

3. **What is the difference between checksum corruption and WAL corruption?** - Checksum corruption affects data pages (the heap, indexes). WAL corruption affects the write-ahead log segments used for crash recovery and replication. They are detected differently: data checksums catch page corruption at read time, while WAL has its own CRC checks validated during replay. WAL corruption is generally more dangerous because it can prevent crash recovery and break replication.

4. **In production, how would you handle a checksum failure?** - First, identify the affected table and block from the error message. Check if you have a recent backup. If so, use `pg_dump` with `ignore_checksum_failure = on` to export whatever readable data exists, restore the table from the backup, and investigate the root cause (disk health, SMART data). If no backup exists, `SET ignore_checksum_failure = on` lets you read surviving data, but the corrupt block's data may be garbage. Rebuild indexes on the affected table as well.

5. **How does pg_checksums differ from the CHECKPOINT-based checksum verification?** - `pg_checksums` is an offline tool that can verify (or enable/disable) checksums on a stopped cluster by scanning every data page. It is thorough but requires downtime. Online, checksums are only verified when a page is read from disk into shared_buffers - pages that are never read are never checked. Running `pg_checksums --check` periodically on a stopped cluster (during maintenance windows) is the only way to proactively scan for corruption in cold data.

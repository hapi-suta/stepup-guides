# Exercise 04: Partition-Based Archival Workflow

**Duration:** 25 minutes
**Objective:** Implement a complete archival workflow: detach an old partition, export it to CSV, verify the export, then drop the partition. Zero data loss.

**Prerequisites:**
- `orders_partitioned` with data (Exercise 02 complete)
- `ec2-user` access to the server

---

## Background

One of the biggest benefits of partitioned tables is near-instant data archival. On a non-partitioned table, deleting 12 months of old orders requires a slow DELETE that processes each row, generates WAL for each row deleted, and runs autovacuum to reclaim the space. On a partitioned table, you DETACH the partition (a metadata-only operation), archive the data, then DROP the now-standalone table (instant file system operation). The whole process is fast and does not block other partitions.

The workflow is:

1. Export the partition data to CSV (while it is still attached or after detach)
2. Detach the partition concurrently
3. Verify the export matches the row count
4. Drop the standalone table

---

## Step 1: Identify the Archival Candidate

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

You will archive the January 2023 partition. First, check how much data it holds:

```sql
SELECT
    COUNT(*) AS row_count,
    MIN(order_date) AS earliest,
    MAX(order_date) AS latest,
    pg_size_pretty(pg_total_relation_size('orders_2023_01')) AS size
FROM orders_2023_01;
```

Expected output (yours will differ):

```
 row_count |  earliest  |   latest   |  size
-----------+------------+------------+--------
     38741 | 2023-01-01 | 2023-01-31 | 8192 kB
(1 row)
```

Record the row count: **38741** (yours will differ). You will verify the CSV has exactly this many rows after export.

---

## Step 2: Export the Partition to CSV

Export the January 2023 data to CSV before detaching. The `\COPY` command in psql writes the file on the server with the privileges of the postgres user:

```sql
\COPY orders_2023_01 TO '/opt/pgsql/backup/orders_2023_01.csv' WITH (FORMAT csv, HEADER true);
```

Expected output (yours will differ):

```
COPY 38741
```

The number after COPY is the row count exported. It must match the row count from Step 1.

Exit psql:

```sql
\q
```

Verify the CSV file exists and is not empty:

```bash
ls -lh /opt/pgsql/backup/orders_2023_01.csv
```

Expected output (yours will differ):

```
-rw-r--r-- 1 postgres postgres 3.8M Apr 19 14:32 /opt/pgsql/backup/orders_2023_01.csv
```

Count the lines in the CSV (subtract 1 for the header row):

```bash
wc -l /opt/pgsql/backup/orders_2023_01.csv
```

Expected output (yours will differ):

```
38742 /opt/pgsql/backup/orders_2023_01.csv
```

38742 lines = 38741 data rows + 1 header row. Matches the database row count.

Spot-check the CSV content to confirm it looks correct:

```bash
head -3 /opt/pgsql/backup/orders_2023_01.csv
```

Expected output (yours will differ):

```
order_id,customer_id,order_date,status,total_amount,region
1,12345,2023-01-01,completed,129.99,Northeast
2,67890,2023-01-01,shipped,45.00,West
```

---

## Step 3: Detach the Partition

Go back into psql:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

Detach the January 2023 partition using CONCURRENTLY to avoid blocking the parent table:

```sql
ALTER TABLE orders_partitioned
    DETACH PARTITION orders_2023_01 CONCURRENTLY;
```

Expected output:

```
ALTER TABLE
```

Verify the partition no longer appears in the partitioned table:

```sql
SELECT child.relname
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
AND child.relname = 'orders_2023_01';
```

Expected output:

```
 relname
---------
(0 rows)
```

Verify the data in `orders_partitioned` is unaffected (the total count should be lower by exactly the detached partition's row count):

```sql
SELECT COUNT(*) FROM orders_partitioned;
```

Expected output (yours will differ - should be previous total minus 38741):

```
  count
---------
 1443559
(1 row)
```

Verify the detached table still exists as a standalone table:

```sql
SELECT COUNT(*) FROM orders_2023_01;
```

Expected output (yours will differ):

```
 count
-------
 38741
(1 row)
```

The data is still there - just no longer attached to the partitioned parent.

---

## Step 4: Verify the Archive Before Dropping

Before dropping the partition permanently, do a final verification that your CSV export is complete and not corrupted. Load the CSV into a temporary table and compare:

```sql
CREATE TEMP TABLE orders_2023_01_verify (
    order_id     integer,
    customer_id  integer,
    order_date   date,
    status       varchar(20),
    total_amount numeric(10,2),
    region       varchar(50)
);
```

Expected output:

```
CREATE TABLE
```

Load the CSV into the temp table:

```sql
\COPY orders_2023_01_verify FROM '/opt/pgsql/backup/orders_2023_01.csv' WITH (FORMAT csv, HEADER true);
```

Expected output (yours will differ):

```
COPY 38741
```

Compare the CSV load count against the original partition count:

```sql
SELECT
    (SELECT COUNT(*) FROM orders_2023_01) AS partition_rows,
    (SELECT COUNT(*) FROM orders_2023_01_verify) AS csv_rows,
    (SELECT COUNT(*) FROM orders_2023_01) - (SELECT COUNT(*) FROM orders_2023_01_verify) AS difference;
```

Expected output:

```
 partition_rows | csv_rows | difference
----------------+----------+------------
          38741 |    38741 |          0
(1 row)
```

Zero difference - the CSV is a perfect copy. You can safely drop the partition.

---

## Step 5: Drop the Archived Partition

Drop the standalone partition table:

```sql
DROP TABLE orders_2023_01;
```

Expected output:

```
DROP TABLE
```

Confirm the table is gone:

```sql
SELECT COUNT(*) FROM pg_class WHERE relname = 'orders_2023_01';
```

Expected output:

```
 count
-------
     0
(1 row)
```

The data is archived in `/opt/pgsql/backup/orders_2023_01.csv` and the database space is freed.

Exit psql:

```sql
\q
```

---

## Step 6: Write a Reusable Archival Script

Exit the postgres user session:

```bash
exit
```

Create a reusable archival script:

```bash
vi /opt/pgsql/scripts/archive_partition.sh
```

Enter the following content:

```bash
#!/usr/bin/env bash
# archive_partition.sh - Archive and drop one monthly partition from orders_partitioned
# Run this script as the postgres user.
# Usage: archive_partition.sh YYYY MM
# Example: archive_partition.sh 2023 02

# -e: exit on any error. -u: error on undefined variables. -o pipefail: catch errors in pipes.
set -euo pipefail

YEAR="${1:?Usage: $0 YYYY MM}"
MONTH="${2:?Usage: $0 YYYY MM}"
MONTH_PAD=$(printf "%02d" "$MONTH")
PARTITION_NAME="orders_$(printf "%04d" "$YEAR")_${MONTH_PAD}"
BACKUP_DIR="/opt/pgsql/backup"
BACKUP_FILE="${BACKUP_DIR}/${PARTITION_NAME}.csv"
PSQL="/usr/pgsql-16/bin/psql -p 5432 -d stepup_store"

log() {
    printf "[%s] %s\n" "$(date +%F\ %T)" "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

log "Starting archival of ${PARTITION_NAME}"

# Step 1: verify partition exists
# -t: tuples only (no headers). -A: no alignment. -c: run command.
EXISTS=$($PSQL -t -A -c "
  SELECT COUNT(*) FROM pg_class WHERE relname = '${PARTITION_NAME}'
")
if [[ "$EXISTS" -ne "1" ]]; then
    die "Partition ${PARTITION_NAME} does not exist"
fi

# Step 2: get row count
ROW_COUNT=$($PSQL -t -A -c "SELECT COUNT(*) FROM ${PARTITION_NAME}")
log "Partition has ${ROW_COUNT} rows"

# Step 3: export to CSV
log "Exporting to ${BACKUP_FILE}"
$PSQL -c "\COPY ${PARTITION_NAME} TO '${BACKUP_FILE}' WITH (FORMAT csv, HEADER true)"

# Step 4: verify CSV row count
CSV_ROWS=$(( $(wc -l < "$BACKUP_FILE") - 1 ))
if [[ "$CSV_ROWS" -ne "$ROW_COUNT" ]]; then
    die "CSV has ${CSV_ROWS} rows but partition has ${ROW_COUNT}"
fi
log "CSV verified: ${CSV_ROWS} rows match"

# Step 5: detach partition
log "Detaching ${PARTITION_NAME}"
$PSQL -c "ALTER TABLE orders_partitioned DETACH PARTITION ${PARTITION_NAME} CONCURRENTLY"

# Step 6: drop partition
log "Dropping ${PARTITION_NAME}"
$PSQL -c "DROP TABLE ${PARTITION_NAME}"

log "Archival complete. Backup: ${BACKUP_FILE}"
```

Save and exit vi (`:wq`).

Make the script executable:

```bash
chmod +x /opt/pgsql/scripts/archive_partition.sh
```

Switch to the `postgres` user to test the script:

```bash
sudo -iu postgres
```

Test the script by archiving February 2023:

```bash
bash /opt/pgsql/scripts/archive_partition.sh 2023 02
```

Expected output (yours will differ):

```
[2025-04-19 14:45:01] Starting archival of orders_2023_02
[2025-04-19 14:45:01] Partition has 35290 rows
[2025-04-19 14:45:02] Exporting to /opt/pgsql/backup/orders_2023_02.csv
[2025-04-19 14:45:03] CSV verified: 35290 rows match
[2025-04-19 14:45:03] Detaching orders_2023_02
[2025-04-19 14:45:04] Dropping orders_2023_02
[2025-04-19 14:45:04] Archival complete. Backup: /opt/pgsql/backup/orders_2023_02.csv
```

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

- [ ] You exported a partition to CSV using `\COPY` and verified the row count
- [ ] You detached a partition using `DETACH PARTITION CONCURRENTLY` without blocking the parent
- [ ] You loaded the CSV into a temp table and verified zero row difference before dropping
- [ ] You dropped the standalone partition with `DROP TABLE`
- [ ] You wrote a reusable archival script that handles export, verification, detach, and drop in sequence
- [ ] You understand why DETACH CONCURRENTLY is preferred over plain DETACH in production

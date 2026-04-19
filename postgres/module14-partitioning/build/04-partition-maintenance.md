# Module 14 - Table Partitioning
## Guide 04: Partition Maintenance

**Objective:** Automate monthly partition creation with a shell script, run VACUUM and ANALYZE per-partition, monitor partition sizes, and move a partition to a different tablespace.

**Time:** 30-35 minutes

**Prerequisites:**
- Completed Guides 01, 02, and 03
- `orders_partitioned` table with data in `stepup_store`
- `ec2-user` access to the server

---

## 1. Monitor Partition Sizes

Knowing which partitions are biggest tells you where your hot data lives and which old partitions are candidates for archival.

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Connect to `stepup_store`:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store
```

List all partitions of `orders_partitioned` with their sizes:

```sql
SELECT
    child.relname AS partition_name,
    pg_size_pretty(pg_total_relation_size(child.oid)) AS total_size,
    pg_size_pretty(pg_relation_size(child.oid)) AS table_size,
    pg_size_pretty(pg_indexes_size(child.oid)) AS index_size,
    child.reltuples::bigint AS estimated_rows
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
ORDER BY pg_total_relation_size(child.oid) DESC;
```

Expected output (yours will differ):

```
  partition_name  | total_size | table_size | index_size | estimated_rows
------------------+------------+------------+------------+----------------
 orders_2024_06   | 12 MB      | 7432 kB    | 4752 kB    |          40312
 orders_2024_05   | 11 MB      | 7184 kB    | 4512 kB    |          39401
 orders_2024_07   | 11 MB      | 7056 kB    | 4416 kB    |          38774
 ...
 orders_default   | 8192 bytes | 0 bytes    | 8192 bytes |              0
(18 rows)
```

This view shows you total size (table + indexes), table data only, index space, and the planner's row estimate. Use this query regularly to identify partitions that are growing unexpectedly.

Check which partition gets the most recent inserts (the hot partition):

```sql
SELECT
    child.relname AS partition_name,
    pg_get_expr(child.relpartbound, child.oid) AS bounds
FROM pg_class parent
JOIN pg_inherits ON pg_inherits.inhparent = parent.oid
JOIN pg_class child ON child.oid = pg_inherits.inhrelid
WHERE parent.relname = 'orders_partitioned'
ORDER BY child.relname DESC
LIMIT 3;
```

Expected output (yours will differ):

```
 partition_name  |                    bounds
-----------------+----------------------------------------------
 orders_default  | DEFAULT
 orders_2025_06  | FOR VALUES FROM ('2025-06-01') TO ('2025-07-01')
 orders_2025_05  | FOR VALUES FROM ('2025-05-01') TO ('2025-06-01')
(3 rows)
```

Exit psql:

```sql
\q
```

---

## 2. VACUUM and ANALYZE Per-Partition

Autovacuum runs on individual partitions automatically, but you sometimes need to trigger VACUUM or ANALYZE manually - for example, after a large bulk load into one partition.

Run ANALYZE on a specific partition to update the planner's row statistics:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ANALYZE orders_2024_06;"
```

Expected output:

```
ANALYZE
```

Run VACUUM on a specific partition to reclaim dead tuple space:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "VACUUM orders_2024_06;"
```

Expected output:

```
VACUUM
```

Run VACUUM ANALYZE on all partitions at once by targeting the parent table. PostgreSQL cascades to all children:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "VACUUM ANALYZE orders_partitioned;"
```

Expected output:

```
VACUUM
```

Check autovacuum statistics per-partition to see when each was last vacuumed:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "
SELECT
    relname AS partition_name,
    n_live_tup,
    n_dead_tup,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables
WHERE relname LIKE 'orders_202%'
   OR relname = 'orders_default'
ORDER BY relname;
"
```

Expected output (yours will differ):

```
  partition_name  | n_live_tup | n_dead_tup | last_vacuum | last_autovacuum | last_analyze | last_autoanalyze
------------------+------------+------------+-------------+-----------------+--------------+------------------
 orders_2024_02   |      38940 |          0 |             | 2025-04-19 ...  |              | 2025-04-19 ...
 orders_2024_03   |      39210 |          0 |             | 2025-04-19 ...  |              | 2025-04-19 ...
 ...
(17 rows)
```

> **Concept - Autovacuum treats each partition independently**
> Autovacuum considers each partition as a separate table for vacuum scheduling. A partition with heavy inserts and updates will trigger autovacuum more frequently than a read-only archived partition. This is a benefit of partitioning: you can tune `autovacuum_vacuum_scale_factor` and similar settings per-partition using `ALTER TABLE ... SET (autovacuum_vacuum_scale_factor = 0.01)`, giving the hot partition more aggressive vacuuming without affecting others.

---

## 3. Automate Partition Creation with a Shell Script

In production, you must create next month's partition before the end of the current month - before any rows with next month's dates start arriving. If you miss it, those rows go to the default partition.

This script creates the next 3 months of partitions if they do not already exist. Exit psql first (if still connected), then create the script:

Exit the postgres user session:

```bash
exit
```

Create the partition management script as `ec2-user`:

```bash
vi /opt/pgsql/scripts/create_partitions.sh
```

Enter the following content:

```bash
#!/usr/bin/env bash
# create_partitions.sh - Create monthly partitions for orders_partitioned
# Run this script monthly (first of the month) to stay ahead of the data.
# Creates the next 3 months of partitions if they do not already exist.

set -euo pipefail

PSQL="/usr/pgsql-16/bin/psql"
DB="stepup_store"
TABLE="orders_partitioned"
MONTHS_AHEAD=3

log() { printf "[%s] %s\n" "$(date +%F\ %T)" "$*"; }

for i in $(seq 1 $MONTHS_AHEAD); do
    # Calculate the target month
    PARTITION_START=$(date -d "$(date +%Y-%m-01) +${i} months" +%Y-%m-01)
    PARTITION_END=$(date -d "${PARTITION_START} +1 month" +%Y-%m-01)
    PARTITION_NAME="${TABLE%_partitioned}_$(date -d "$PARTITION_START" +%Y_%m)"

    # Check if partition already exists
    EXISTS=$(sudo -u postgres $PSQL -d $DB -t -A -c "
        SELECT COUNT(*) FROM pg_class
        WHERE relname = '${PARTITION_NAME}'
    ")

    if [[ "$EXISTS" -eq "0" ]]; then
        log "Creating partition: $PARTITION_NAME ($PARTITION_START to $PARTITION_END)"
        sudo -u postgres $PSQL -d $DB -c "
            CREATE TABLE ${PARTITION_NAME}
                PARTITION OF ${TABLE}
                FOR VALUES FROM ('${PARTITION_START}') TO ('${PARTITION_END}');
        "
        log "Created: $PARTITION_NAME"
    else
        log "Already exists: $PARTITION_NAME - skipping"
    fi
done

log "Partition maintenance complete."
```

Save and exit vi (`:wq`).

Make the script executable:

```bash
chmod +x /opt/pgsql/scripts/create_partitions.sh
```

Test the script by running it:

```bash
bash /opt/pgsql/scripts/create_partitions.sh
```

Expected output (yours will differ):

```
[2025-04-19 14:23:01] Already exists: orders_2025_05 - skipping
[2025-04-19 14:23:01] Already exists: orders_2025_06 - skipping
[2025-04-19 14:23:01] Creating partition: orders_2025_07 (2025-07-01 to 2025-08-01)
[2025-04-19 14:23:02] Created: orders_2025_07
[2025-04-19 14:23:02] Partition maintenance complete.
```

> **Concept - pg_partman: the production alternative**
> The shell script above works and is educational, but the PostgreSQL community uses `pg_partman` for production partition management. pg_partman is an extension that handles partition creation, maintenance, and retention automatically. It supports time-based and serial-based partitioning, background partition creation, and automated retention policies (drop old partitions after N months). On managed cloud services (RDS, Aurora), pg_partman is often pre-installed. For SUTA Labs, the shell script teaches the mechanics. In a real job, ask whether pg_partman is available before writing your own scripts.

Set up a cron job to run the script on the 1st of every month:

Switch to root to add the cron job:

```bash
sudo su -
```

Open the crontab for the postgres user:

```bash
crontab -u postgres -e
```

Add this line (runs at 01:00 on the 1st of each month):

```
0 1 1 * * /opt/pgsql/scripts/create_partitions.sh >> /opt/pgsql/log/partition_maintenance.log 2>&1
```

Save and exit (`:wq`).

Verify the cron job was saved:

```bash
crontab -u postgres -l
```

Expected output:

```
0 1 1 * * /opt/pgsql/scripts/create_partitions.sh >> /opt/pgsql/log/partition_maintenance.log 2>&1
```

Exit root:

```bash
exit
```

---

## 4. Move a Partition to a Different Tablespace

In production, old (cold) partitions are sometimes moved to cheaper, slower storage (a different tablespace backed by spinning disks or a cold-storage volume) while hot partitions stay on fast NVMe storage.

Create a tablespace pointing to an alternate directory to simulate cold storage:

Switch to root:

```bash
sudo su -
```

Create the cold storage directory:

```bash
mkdir -p /opt/pgsql/cold_storage
```

Set ownership to postgres:

```bash
chown postgres:postgres /opt/pgsql/cold_storage
```

Exit root:

```bash
exit
```

Switch to the `postgres` user:

```bash
sudo -iu postgres
```

Create the tablespace in PostgreSQL:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "
CREATE TABLESPACE cold_storage LOCATION '/opt/pgsql/cold_storage';
"
```

Expected output:

```
CREATE TABLESPACE
```

Move the January 2024 partition to cold storage. This rewrites the partition's data files to the new tablespace location:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "
ALTER TABLE orders_2024_02 SET TABLESPACE cold_storage;
"
```

Expected output:

```
ALTER TABLE
```

Verify the partition is now in the `cold_storage` tablespace:

```bash
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "
SELECT
    c.relname AS partition_name,
    t.spcname AS tablespace
FROM pg_class c
LEFT JOIN pg_tablespace t ON t.oid = c.reltablespace
WHERE c.relname = 'orders_2024_02';
"
```

Expected output:

```
 partition_name | tablespace
----------------+-------------
 orders_2024_02 | cold_storage
(1 row)
```

> **Concept - Tablespace migration is online but blocks the table**
> `ALTER TABLE ... SET TABLESPACE` rewrites the table's data files to the new location. On a running system, this operation holds an `ACCESS EXCLUSIVE` lock for the entire duration of the copy - blocking all reads and writes to that partition. For a large partition, this can be minutes or hours. Always do tablespace migrations in a maintenance window or after detaching the partition (which avoids the lock on the parent). A detached partition is just a plain table - you can move it to cold storage independently, then drop it.

Exit the postgres session:

```bash
exit
```

---

## Checkpoint

You have completed Guide 04. Verify you understand the following:

- [ ] You can query partition sizes using `pg_total_relation_size` joined with `pg_inherits`
- [ ] You can run VACUUM and ANALYZE on individual partitions and on the parent (which cascades to all partitions)
- [ ] You can check per-partition autovacuum statistics from `pg_stat_user_tables`
- [ ] You can write a shell script to create upcoming monthly partitions idempotently (skips if already exists)
- [ ] You can set up a cron job to run partition maintenance monthly
- [ ] You understand that `pg_partman` is the production alternative to custom scripts
- [ ] You can create a tablespace and move a partition to it with `ALTER TABLE ... SET TABLESPACE`
- [ ] You understand that tablespace migration holds an ACCESS EXCLUSIVE lock and should be done in a maintenance window

---

This completes the Module 14 BUILD guides. Proceed to the **USE Exercises** to apply these skills to real scenarios.

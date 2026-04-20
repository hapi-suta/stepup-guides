# Guide 01 - Upgrade Planning

Before touching a single file, you need a plan. PostgreSQL upgrades are not dangerous if you approach them systematically. This guide walks you through the pre-upgrade checklist: checking version compatibility, auditing extensions, estimating downtime, and doing a dry run with `pg_upgrade --check`.

**Run on:** NODE1 only

---

## 1. Understand What Version You Are Running

SSH into NODE1.

```
ssh ec2-user@NODE1
```

Switch to the postgres user.

```
sudo -iu postgres
```

Check the running PostgreSQL version.

```
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                  version
-----------------------------------------------------------------------------------------------------------
 PostgreSQL 16.3 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 11.4.1 20231218 (Red Hat 11.4.1-3), 64-bit
(1 row)
```

Also check what PostgreSQL binaries are installed on the system.

```
exit
```

```
ls /usr/pgsql-*/bin/postgres
```

Expected output (yours will differ):

```
/usr/pgsql-15/bin/postgres
/usr/pgsql-16/bin/postgres
```

(`/usr/pgsql-*/bin/postgres` = wildcard that expands to every installed PostgreSQL major version.)

> **Concept - Major vs Minor Upgrades**: PostgreSQL minor versions (e.g. 16.1 to 16.3) are safe to apply by replacing binaries - no data migration needed. Major versions (e.g. 15 to 16) change the on-disk data format and require a migration tool like `pg_upgrade` or logical replication. Never confuse the two.

---

## 2. Read the Release Notes

Before upgrading, you must read the release notes for every major version you are skipping. For a 15 to 16 upgrade, read the PostgreSQL 16 release notes.

```
sudo -iu postgres
```

Check the installed version of the target binary.

```
/usr/pgsql-16/bin/postgres --version
```

Expected output:

```
postgres (PostgreSQL) 16.3
```

```
exit
```

The official release notes are at https://www.postgresql.org/docs/16/release.html. Key things to look for:

- Parameters that were renamed or removed
- Default value changes for configuration parameters
- Behavior changes in SQL functions
- Extension API changes
- Authentication changes

---

## 3. Document Current Configuration

Before any upgrade, capture a snapshot of your current settings. This gives you a reference point and makes it easy to reconfigure the new cluster.

```
sudo -iu postgres
```

Dump all non-default settings from the running cluster.

```
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT name, setting, unit FROM pg_settings WHERE source NOT IN ('default', 'override') ORDER BY name;" > /tmp/current_settings.txt
```

View the saved settings.

```
cat /tmp/current_settings.txt
```

Expected output (yours will differ):

```
              name               | setting | unit
---------------------------------+---------+------
 checkpoint_completion_target    | 0.9     |
 log_checkpoints                 | on      |
 max_wal_size                    | 4096    | MB
 shared_buffers                  | 131072  | 8kB
 work_mem                        | 65536   | kB
...
```

Also capture the list of databases.

```
/usr/pgsql-16/bin/psql -p 5432 -l
```

Expected output (yours will differ):

```
                                  List of databases
   Name    |  Owner   | Encoding |   Collate   |    Ctype    |   Access privileges
-----------+----------+----------+-------------+-------------+-----------------------
 labdb     | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 postgres  | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 |
 template0 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
 template1 | postgres | UTF8     | en_US.UTF-8 | en_US.UTF-8 | =c/postgres          +
(4 rows)
```

Note the collation (`en_US.UTF-8`) and encoding (`UTF8`). The new cluster must be initialized with identical values.

```
exit
```

> **Concept - Collation Matters**: If you initialize the new cluster with a different locale or collation, `pg_upgrade` will refuse to proceed. String sorting, indexing, and regular expressions all depend on collation. Changing collation between versions corrupts index ordering.

---

## 4. Audit Extensions

Extensions are the most common cause of upgrade failures. An extension that works on PG15 may not have a compatible version for PG16, or the binary may not be installed in the new version's lib directory.

```
sudo -iu postgres
```

List all extensions installed across all databases. First, list the non-template databases.

```
/usr/pgsql-16/bin/psql -p 5432 -c "SELECT datname FROM pg_database WHERE datistemplate = false;" -t -A
```

Expected output (yours will differ):

```
postgres
labdb
```

Check extensions in each database. Start with the postgres database.

```
/usr/pgsql-16/bin/psql -p 5432 -d postgres -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Expected output (yours will differ):

```
      extname      | extversion
-------------------+------------
 pg_stat_statements| 1.10
(1 row)
```

Check extensions in the labdb database.

```
/usr/pgsql-16/bin/psql -p 5432 -d labdb -c "SELECT extname, extversion FROM pg_extension ORDER BY extname;"
```

Expected output (yours will differ):

```
      extname      | extversion
-------------------+------------
 pg_stat_statements| 1.10
 plpgsql           | 1.0
(2 rows)
```

Repeat for any additional databases you have.

For each extension, verify its binary exists in the PG16 lib directory.

```
ls /usr/pgsql-16/lib/pg_stat_statements.so
```

Expected output:

```
/usr/pgsql-16/lib/pg_stat_statements.so
```

```
ls /usr/pgsql-16/share/extension/pg_stat_statements--*.sql
```

Expected output (yours will differ):

```
/usr/pgsql-16/share/extension/pg_stat_statements--1.4--1.5.sql
/usr/pgsql-16/share/extension/pg_stat_statements--1.5--1.6.sql
...
/usr/pgsql-16/share/extension/pg_stat_statements--1.10.sql
```

```
exit
```

> **Concept - Extension Compatibility**: Each extension has a version matrix. PG16 ships with updated extension control files. If an extension was installed as a third-party RPM (like `timescaledb` or `postgis`), you need to install the PG16 version of that RPM before running `pg_upgrade`. The extension binary (`*.so`) must exist in the new version's lib directory.

---

## 5. Check Disk Space

`pg_upgrade` needs enough disk space to hold both the old and new data directories. With `--link` mode it is minimal (hardlinks), but with `--copy` mode you need roughly the size of your current data directory in free space.

```
df -h /opt/pgsql
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1     50G   12G   38G  24% /opt/pgsql
```

Check the size of the current data directory.

```
sudo du -sh /opt/pgsql/data
```

Expected output (yours will differ):

```
1.2G    /opt/pgsql/data
```

(`-s` = summary, `-h` = human-readable.)

Rule of thumb: For `--copy` mode, you need free space equal to the data directory size. For `--link` mode, you need only a few hundred MB.

---

## 6. Run pg_upgrade --check (Dry Run)

The safest step in upgrade planning is the dry run. `pg_upgrade --check` examines the old and new clusters for compatibility issues without making any changes.

For this dry run, we will check a PG15 test cluster against PG16. The PG15 cluster is at `/opt/pgsql/data15` running on port 5433. (Guide 02 creates this cluster - if you have not done Guide 02 yet, return to this step after completing it.)

Both clusters must be stopped for `pg_upgrade --check` to work.

```
sudo systemctl stop postgresql-15
```

```
sudo systemctl stop postgresql-16
```

Switch to postgres user.

```
sudo -iu postgres
```

Run the compatibility check.

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --check
```

(`--check` = run compatibility checks only, make no changes. `--old-bindir` = path to the old PostgreSQL binaries. `--new-bindir` = path to the new binaries. `--old-datadir` = path to the old data directory. `--new-datadir` = path to the new data directory.)

Expected output (yours will differ):

```
Performing Consistency Checks
-----------------------------
Checking cluster versions                                     ok
Checking database user is the install user                    ok
Checking database connection settings                         ok
Checking for prepared transactions                            ok
Checking for system-defined composite types in user tables    ok
Checking for reg* data types in user tables                   ok
Checking for contrib/isn with bigint-passing mismatch         ok
Checking for tables WITH OIDS                                 ok
Checking for invalid "sql_identifier" user columns            ok
Checking for presence of required libraries                   ok
Checking database user is the install user                    ok
Checking for multiple databases in the same tablespace        ok
Checking for presence of required libraries                   ok

*Clusters are compatible*
```

If you see any line that does not say `ok`, stop and resolve the issue before proceeding.

```
exit
```

Restart both clusters.

```
sudo systemctl start postgresql-15
```

```
sudo systemctl start postgresql-16
```

> **Concept - pg_upgrade --check is Safe**: The `--check` flag makes pg_upgrade read-only. It connects to both clusters (which is why they must be stopped - pg_upgrade connects via socket to the data directory directly, not through the postmaster), examines catalog tables, and reports any incompatibilities. Run this check on production before scheduling the maintenance window.

---

## 7. Estimate Downtime

Downtime depends on the upgrade method and database size.

| Method | Speed | Disk usage | Safe rollback? |
|---|---|---|---|
| `pg_upgrade --link` | Very fast (minutes) | Minimal | No - old files modified |
| `pg_upgrade --copy` | Slow (proportional to size) | 2x data directory | Yes |
| Logical replication | Near-zero downtime | Varies | Yes |

For a 1 GB database:

- `--link`: 1-3 minutes
- `--copy`: 5-10 minutes
- Logical replication: minutes to hours for initial sync, then seconds for cutover

For a 100 GB database:

- `--link`: 3-5 minutes
- `--copy`: 30-90 minutes
- Logical replication: hours for initial sync, seconds for cutover

Write down your estimate before scheduling the maintenance window. Always add 50% buffer for unexpected issues.

---

## 8. Create a Backup Before the Upgrade

Never upgrade without a backup. This is non-negotiable.

```
sudo -iu postgres
```

Take a base backup of the current running PG16 cluster (your production cluster).

```
/usr/pgsql-16/bin/pg_basebackup -p 5432 -D /opt/pgsql/backup/pre-upgrade-$(date +%Y%m%d) -Fp -Xs -P
```

(`-Fp` = plain format, keeps files as-is. `-Xs` = include WAL using streaming. `-P` = show progress.)

Expected output (yours will differ):

```
33620/33620 kB (100%), 1/1 tablespace
```

```
exit
```

---

## Checkpoint

By the end of this guide, you should have:

- [ ] Identified the PostgreSQL versions installed on the server
- [ ] Documented current non-default settings
- [ ] Listed all installed extensions and verified PG16 binaries exist
- [ ] Checked disk space for the upgrade method you plan to use
- [ ] Run `pg_upgrade --check` and confirmed `Clusters are compatible`
- [ ] Estimated downtime for your chosen upgrade method
- [ ] Taken a backup of the current cluster

**Proceed to:** `02-pg-upgrade-in-place.md`

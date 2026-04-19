# Guide 02 - pg_upgrade In-Place Upgrade

In this guide you will create a PG15 cluster, load test data into it, and then upgrade it to PG16 using `pg_upgrade`. You will practice both `--link` mode (fast, shared files) and understand when to use `--copy` mode (safe, independent copy).

**Run on:** NODE1 only

---

## 1. Create the PG15 Test Cluster

PG15 binaries are installed at `/usr/pgsql-15/bin`. You will initialize a fresh PG15 data directory at `/opt/pgsql/data15` on port 5433.

Switch to the postgres user.

```
sudo -iu postgres
```

Create the data directory for PG15.

```
mkdir -p /opt/pgsql/data15
```

Initialize the PG15 cluster. The locale and encoding must match your PG16 cluster.

```
/usr/pgsql-15/bin/initdb -D /opt/pgsql/data15 --encoding=UTF8 --locale=en_US.UTF-8
```

(`-D` = data directory to initialize. `--encoding` = character encoding for new databases. `--locale` = locale for collation and character classification. These must match the target cluster.)

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Success. You can now start the database server using:

    /usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l logfile start
```

Set the port for the PG15 cluster to 5433 so it does not conflict with PG16.

```
echo "port = 5433" >> /opt/pgsql/data15/postgresql.conf
```

Also set a distinct unix socket directory.

```
echo "unix_socket_directories = '/run/postgresql'" >> /opt/pgsql/data15/postgresql.conf
```

```
exit
```

> **Concept - Multiple Clusters on One Server**: PostgreSQL identifies clusters by their data directory and port. You can run PG15 and PG16 simultaneously by giving each a unique port. During an upgrade, both clusters are stopped, so the port does not matter for the upgrade itself - but you need both to be startable for testing before and after.

---

## 2. Start the PG15 Cluster

```
sudo -iu postgres
```

Start the PG15 cluster manually using pg_ctl (the systemd service is configured for PG16).

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

(`-D` = data directory. `-l` = log file to write startup output to. `start` = start the server.)

Expected output:

```
waiting for server to start.... done
server started
```

Verify PG15 is accepting connections on port 5433.

```
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output (yours will differ):

```
/run/postgresql:5433 - accepting connections
```

```
exit
```

---

## 3. Load Test Data Into PG15

```
sudo -iu postgres
```

Create a test database in PG15.

```
/usr/pgsql-15/bin/psql -p 5433 -c "CREATE DATABASE upgradetest;"
```

Expected output:

```
CREATE DATABASE
```

Create a table and load 100,000 rows of test data.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "CREATE TABLE employees (id SERIAL PRIMARY KEY, name TEXT, department TEXT, salary NUMERIC, created_at TIMESTAMPTZ DEFAULT now());"
```

Expected output:

```
CREATE TABLE
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "INSERT INTO employees (name, department, salary) SELECT 'Employee ' || i, CASE WHEN i % 3 = 0 THEN 'Engineering' WHEN i % 3 = 1 THEN 'Sales' ELSE 'HR' END, 50000 + (random() * 50000)::int FROM generate_series(1, 100000) i;"
```

Expected output:

```
INSERT 0 100000
```

Verify the row count.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT count(*) FROM employees;"
```

Expected output:

```
 count
--------
 100000
(1 row)
```

Install pg_stat_statements on PG15 so you have an extension to migrate.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "CREATE EXTENSION pg_stat_statements;"
```

Expected output:

```
CREATE EXTENSION
```

```
exit
```

---

## 4. Initialize the PG16 Target Cluster

For `pg_upgrade` to work, you need a freshly initialized PG16 data directory at a separate path. You will use `/opt/pgsql/data16` as the upgrade target. (This is different from `/opt/pgsql/data` which is your existing PG16 production cluster.)

```
sudo -iu postgres
```

Create the target directory.

```
mkdir -p /opt/pgsql/data16
```

Initialize PG16 with the same locale and encoding as PG15.

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Success. You can now start the database server using:

    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l logfile start
```

Do NOT start this cluster. `pg_upgrade` requires both clusters to be stopped.

```
exit
```

> **Concept - Why initdb First**: `pg_upgrade` does not create the new cluster for you. You must initialize it first with `initdb` because `pg_upgrade` needs a valid PG16 system catalog structure to upgrade into. The `initdb` step creates the catalog tables, pg_hba.conf, and postgresql.conf. `pg_upgrade` then replaces the user data inside this fresh cluster.

---

## 5. Stop the PG15 Cluster

Both clusters must be completely stopped before running `pg_upgrade`.

```
sudo -iu postgres
```

Stop PG15 cleanly.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

(`-m fast` = fast shutdown mode. Rolls back any open transactions and stops immediately. Do not use `immediate` mode - it skips checkpoint and may require crash recovery.)

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Verify PG15 is no longer listening.

```
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - no response
```

```
exit
```

---

## 6. Run pg_upgrade --link

Now run the actual upgrade. `--link` mode creates hard links between the old and new data directories instead of copying files. This is extremely fast even for large databases.

```
sudo -iu postgres
```

Run pg_upgrade in link mode.

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --link
```

(`--link` = use hard links instead of copying files. Files are shared between old and new directories. Much faster than copy but you cannot use the old cluster after this - the files belong to both.)

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

Performing Upgrade
------------------
Setting next OID for new cluster                              ok
Restoring database schemas in the new cluster                 ok
Setting next transaction ID and epoch for new cluster         ok
Setting next multixact ID and offset for new cluster          ok
Setting oldest multixact ID in new cluster                    ok
Restoring database schemas in the new cluster                 ok
Adding ".old" suffix to old global/pg_control                 ok
Setting next OID for new cluster                              ok
Restoring user relation files
                                                              ok
Setting next relfilenode for new cluster                      ok
Adding ".old" suffix to old global/pg_control                 ok
Copying user relation files
                                                              ok
Setting next OID for new cluster                              ok
Sync data directory to disk                                   ok
Creating script to delete old cluster                         ok

Upgrade Complete
----------------
Optimizer statistics are not transferred by pg_upgrade.
Once you start the new server, consider running:
    /opt/pgsql/data16/analyze_new_cluster.sh

Running this script will delete the old cluster's data files:
    /opt/pgsql/data16/delete_old_cluster.sh
```

The upgrade is complete when you see `Upgrade Complete`.

> **Concept - Hard Links and --link Mode**: With `--link`, pg_upgrade creates hard links - directory entries that point to the same underlying disk blocks. Both `/opt/pgsql/data15/base/...` and `/opt/pgsql/data16/base/...` point to the same physical blocks. This is why `--link` is so fast: no data is copied. The tradeoff is that you cannot safely start the old cluster after a `--link` upgrade because it shares data blocks with the new cluster.

---

## 7. Start the New PG16 Cluster and Verify

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l /opt/pgsql/log/pg16-upgraded.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

Verify the version.

```
/usr/pgsql-16/bin/psql -p 5434 -c "SELECT version();"
```

Wait - the default port in `/opt/pgsql/data16/postgresql.conf` may still be 5432. Check the port first.

```
grep ^port /opt/pgsql/data16/postgresql.conf
```

Expected output (yours will differ):

```
port = 5432
```

If port 5432 conflicts with your running PG16 production cluster, update it.

```
echo "port = 5434" >> /opt/pgsql/data16/postgresql.conf
```

Stop and restart on the new port.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop
```

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l /opt/pgsql/log/pg16-upgraded.log start
```

Connect and verify data.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "SELECT count(*) FROM employees;"
```

Expected output:

```
 count
--------
 100000
(1 row)
```

Verify the extension migrated.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "SELECT extname, extversion FROM pg_extension;"
```

Expected output (yours will differ):

```
       extname        | extversion
----------------------+------------
 plpgsql              | 1.0
 pg_stat_statements   | 1.10
(2 rows)
```

---

## 8. Run analyze_new_cluster.sh

After `pg_upgrade`, the new cluster has no optimizer statistics. Without statistics, the query planner makes poor decisions. Run the generated script to rebuild statistics.

```
/opt/pgsql/data16/analyze_new_cluster.sh
```

(`analyze_new_cluster.sh` = a script generated by pg_upgrade that runs ANALYZE on every database in the new cluster. This populates `pg_statistic` so the planner can make good decisions.)

Expected output (yours will differ):

```
This script will generate minimal optimizer statistics rapidly
so your system is usable, and then gather statistics twice more
with increasing target settings, like the default.  When it is
done, your system will have the default level of optimizer
statistics.

If you have used ALTER TABLE to modify the statistics target for
specific tables or columns, revise the target after running this
script, delete the improper statistics, and run ANALYZE on those
tables and columns.

vacuumdb: processing database "upgradetest": Generating minimal optimizer statistics (1 target)
vacuumdb: processing database "postgres": Generating minimal optimizer statistics (1 target)
...
Done
```

```
exit
```

> **Concept - Optimizer Statistics After Upgrade**: pg_upgrade transfers your data but not the statistics stored in `pg_statistic`. Statistics are version-specific and tied to the internal OID structure. Until you run ANALYZE, `pg_statistic` is empty and the planner assumes default selectivity for every query. This can cause sequential scans where index scans are appropriate, leading to 10x-100x slower queries on the first day after an upgrade.

---

## 9. Stop the Upgraded Cluster

Stop the test cluster now that you have verified the upgrade.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

```
exit
```

---

## Checkpoint

By the end of this guide, you should have:

- [ ] Initialized a PG15 cluster at `/opt/pgsql/data15` on port 5433
- [ ] Loaded 100,000 rows of test data and installed an extension
- [ ] Initialized a fresh PG16 cluster at `/opt/pgsql/data16`
- [ ] Stopped both clusters
- [ ] Run `pg_upgrade --link` successfully and seen `Upgrade Complete`
- [ ] Started the upgraded cluster and verified the row count and extension
- [ ] Run `analyze_new_cluster.sh` to rebuild optimizer statistics

**Proceed to:** `03-logical-replication-upgrade.md`

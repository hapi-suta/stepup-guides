# Guide 03 - Zero-Downtime Upgrade with Logical Replication

`pg_upgrade` requires taking your database offline. For high-availability environments where any downtime is unacceptable, you can use logical replication to stream changes from a PG15 publisher to a PG16 subscriber, then cut over with only seconds of application pause.

This guide demonstrates the concept using two local clusters: PG15 on port 5433 as the publisher, and a fresh PG16 cluster on port 5434 as the subscriber.

**Run on:** NODE1 only

---

## 1. Understand the Zero-Downtime Flow

The logical replication upgrade process has five stages:

1. **Set up PG16 subscriber** - Initialize and start a PG16 cluster
2. **Create a publication on PG15** - Tell PG15 to publish all table changes
3. **Create a subscription on PG16** - PG16 connects to PG15 and copies all existing data, then streams changes in real time
4. **Wait for sync** - Confirm the subscriber has caught up to the publisher
5. **Cutover** - Stop writes to PG15, verify subscriber is fully synced, update application connection string to point to PG16

During stages 2-4, both databases are running and PG16 stays in sync. The application only pauses for the brief moment between stopping writes to PG15 and pointing the application at PG16.

> **Concept - Logical Replication vs Physical**: Physical replication (streaming replication) copies raw disk blocks and requires both servers to run the same PostgreSQL major version. Logical replication works at the SQL statement level - it decodes the WAL into row changes (INSERT, UPDATE, DELETE) and applies them to the subscriber. This means the publisher and subscriber can run different major versions, making it the foundation for zero-downtime upgrades.

---

## 2. Start the PG15 Publisher

If the PG15 cluster from Guide 02 is still running, use it. If not, start it now.

```
sudo -iu postgres
```

Check if PG15 is already running on port 5433.

```
/usr/pgsql-15/bin/pg_isready -p 5433
```

Expected output:

```
/run/postgresql:5433 - accepting connections
```

If you see `no response`, start it.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

```
exit
```

---

## 3. Configure PG15 for Logical Replication

Logical replication requires `wal_level = logical` on the publisher. Check the current setting.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/psql -p 5433 -c "SHOW wal_level;"
```

Expected output:

```
 wal_level
-----------
 replica
(1 row)
```

The default is `replica`. You need to set it to `logical`.

```
/usr/pgsql-15/bin/psql -p 5433 -c "ALTER SYSTEM SET wal_level = logical;"
```

Expected output:

```
ALTER SYSTEM
```

Restart PG15 for the change to take effect (`wal_level` requires a restart).

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 restart -m fast
```

Expected output (yours will differ):

```
waiting for server to shut down.... done
waiting for server to start.... done
server started
```

Verify `wal_level` is now `logical`.

```
/usr/pgsql-15/bin/psql -p 5433 -c "SHOW wal_level;"
```

Expected output:

```
 wal_level
-----------
 logical
(1 row)
```

> **Concept - wal_level = logical**: WAL (Write-Ahead Log) normally records physical changes at the block level. At `wal_level = logical`, PostgreSQL also records enough information to decode those changes back into row-level operations (which table, which row, which columns changed). This extra information is used by the logical decoding infrastructure to stream row changes to a subscriber. The cost is slightly more WAL volume.

```
exit
```

---

## 4. Create a Fresh PG16 Subscriber Cluster

Initialize a PG16 cluster at `/opt/pgsql/data16sub` on port 5434.

```
sudo -iu postgres
```

```
mkdir -p /opt/pgsql/data16sub
```

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16sub --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):

```
The files belonging to this database system will be owned by user "postgres".
...
Success. You can now start the database server using:

    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16sub -l logfile start
```

Set the port to 5434.

```
echo "port = 5434" >> /opt/pgsql/data16sub/postgresql.conf
```

Start the PG16 subscriber cluster.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16sub -l /opt/pgsql/log/pg16sub.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

Verify it is ready on port 5434.

```
/usr/pgsql-16/bin/pg_isready -p 5434
```

Expected output:

```
/run/postgresql:5434 - accepting connections
```

Create the target database on PG16.

```
/usr/pgsql-16/bin/psql -p 5434 -c "CREATE DATABASE upgradetest;"
```

Expected output:

```
CREATE DATABASE
```

```
exit
```

---

## 5. Create the Table Structure on PG16

Logical replication copies data but not DDL. You must create the table structure on the subscriber first.

```
sudo -iu postgres
```

Get the table definition from PG15 and apply it to PG16. First, dump only the schema.

```
/usr/pgsql-15/bin/pg_dump -p 5433 -d upgradetest --schema-only -t employees -f /tmp/employees_schema.sql
```

(`--schema-only` = dump only table definitions, no data. `-t employees` = only the employees table.)

Apply the schema to PG16.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -f /tmp/employees_schema.sql
```

Expected output (yours will differ):

```
SET
SET
SET
SET
SET
 set_config
------------

(1 row)

SET
SET
SET
SET
CREATE TABLE
ALTER TABLE
CREATE SEQUENCE
ALTER SEQUENCE
...
```

Verify the table exists in PG16.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "\dt"
```

Expected output:

```
          List of relations
 Schema |   Name    | Type  |  Owner
--------+-----------+-------+----------
 public | employees | table | postgres
(1 row)
```

```
exit
```

---

## 6. Create the Publication on PG15

A publication is a named set of tables whose changes will be streamed.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "CREATE PUBLICATION upgrade_pub FOR ALL TABLES;"
```

(`CREATE PUBLICATION` = creates a logical replication publication. `FOR ALL TABLES` = publish changes from every table in the database. In production, you can restrict to specific tables with `FOR TABLE tablename`.)

Expected output:

```
CREATE PUBLICATION
```

Verify the publication was created.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "SELECT pubname, puballtables FROM pg_publication;"
```

Expected output:

```
  pubname    | puballtables
-------------+--------------
 upgrade_pub | t
(1 row)
```

```
exit
```

---

## 7. Create the Subscription on PG16

A subscription tells PG16 to connect to PG15, copy all existing data, and then stream changes continuously.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "CREATE SUBSCRIPTION upgrade_sub CONNECTION 'host=/run/postgresql port=5433 user=postgres dbname=upgradetest' PUBLICATION upgrade_pub;"
```

(`CREATE SUBSCRIPTION` = creates a logical replication subscriber. `CONNECTION` = the connection string to the publisher. `PUBLICATION upgrade_pub` = subscribe to the publication you created on PG15. `host=/run/postgresql` = use the Unix socket.)

Expected output:

```
NOTICE:  created replication slot "upgrade_sub" on publisher
CREATE SUBSCRIPTION
```

> **Concept - Replication Slots**: When you create a subscription, PostgreSQL automatically creates a replication slot on the publisher. The slot guarantees that the publisher retains WAL segments until the subscriber has processed them. If the subscriber disconnects, the publisher keeps the WAL. Be careful - a disconnected subscriber with a slot can cause unbounded WAL accumulation on the publisher.

Check the initial sync status. PG16 is now copying all existing data from PG15.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "SELECT subname, subenabled FROM pg_subscription;"
```

Expected output:

```
  subname    | subenabled
-------------+------------
 upgrade_sub | t
(1 row)
```

Check sync state of individual tables.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "SELECT srrelid::regclass, srsubstate FROM pg_subscription_rel;"
```

Expected output (yours will differ):

```
  srrelid   | srsubstate
------------+------------
 employees  | r
(1 row)
```

(`srsubstate = r` = ready, sync complete. Other values: `i` = initializing, `d` = data is being copied, `s` = synchronized.)

```
exit
```

---

## 8. Verify Data is in Sync

```
sudo -iu postgres
```

Check the row count on PG15 (the publisher).

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

Check the row count on PG16 (the subscriber).

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

Simulate ongoing writes to PG15 (as if your application is still writing).

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "INSERT INTO employees (name, department, salary) VALUES ('New Employee', 'Engineering', 75000);"
```

Expected output:

```
INSERT 0 1
```

Immediately check PG16.

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "SELECT count(*) FROM employees;"
```

Expected output:

```
 count
--------
 100001
(1 row)
```

The new row replicated instantly.

```
exit
```

---

## 9. Cutover

In a real upgrade, you would:

1. Stop your application from writing to PG15
2. Wait for the replication lag to reach zero
3. Verify the row counts match
4. Update your application's connection string to point to PG16 port 5434
5. Start the application

Check replication lag before cutover.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/psql -p 5433 -c "SELECT application_name, sent_lsn, write_lsn, flush_lsn, replay_lsn, (sent_lsn - replay_lsn) AS replay_lag FROM pg_stat_replication;"
```

Expected output (yours will differ):

```
 application_name |  sent_lsn  | write_lsn  | flush_lsn  | replay_lsn | replay_lag
------------------+------------+------------+------------+------------+------------
 upgrade_sub      | 0/3000060  | 0/3000060  | 0/3000060  | 0/3000060  |          0
(1 row)
```

When `replay_lag` is 0, the subscriber is fully caught up. You can now cut over.

```
exit
```

> **Concept - The Cutover Window**: The actual application downtime in a logical replication upgrade is just the time between stopping writes on the old server and reconnecting on the new server. This is typically 1-10 seconds. Contrast this with `pg_upgrade --copy` where downtime is proportional to database size. For a 1 TB database, logical replication reduces 4+ hours of downtime to under a minute.

---

## 10. Clean Up

Drop the subscription on PG16.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -c "DROP SUBSCRIPTION upgrade_sub;"
```

Expected output:

```
NOTICE:  dropped replication slot "upgrade_sub" on publisher
DROP SUBSCRIPTION
```

Drop the publication on PG15.

```
/usr/pgsql-15/bin/psql -p 5433 -d upgradetest -c "DROP PUBLICATION upgrade_pub;"
```

Expected output:

```
DROP PUBLICATION
```

Stop the PG16 subscriber cluster.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16sub stop
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

- [ ] Configured PG15 with `wal_level = logical`
- [ ] Created a PG16 subscriber cluster on port 5434
- [ ] Replicated the schema from PG15 to PG16 manually
- [ ] Created a publication on PG15 and a subscription on PG16
- [ ] Verified all 100,000+ rows replicated to PG16
- [ ] Tested that new writes on PG15 immediately appear on PG16
- [ ] Checked replication lag is 0 before simulated cutover
- [ ] Cleaned up the publication, subscription, and test cluster

**Proceed to:** `04-post-upgrade-tasks.md`

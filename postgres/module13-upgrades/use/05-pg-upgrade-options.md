# Exercise 05 - pg_upgrade Options: --link vs --copy

Compare the two pg_upgrade data transfer modes in depth. Understand the tradeoffs so you can choose the right mode for any situation.

**Run on:** NODE1 only

---

## Part A: How --copy Works

In `--copy` mode (the default), pg_upgrade reads every data file from the old cluster and writes an independent copy to the new cluster. The two directories are completely separate after the upgrade.

```
sudo -iu postgres
```

Check disk space before running a --copy upgrade.

```
df -h /opt/pgsql
```

Expected output (yours will differ):

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme1n1     50G   12G   38G  24% /opt/pgsql
```

Note the used space. After a --copy upgrade it will roughly double temporarily.

After the --copy upgrade completes, compare inode numbers. Different inode = different physical file.

Stop PG15 first.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

```
rm -rf /opt/pgsql/data16
```

```
mkdir -p /opt/pgsql/data16
```

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8 2>/dev/null
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16
```

Expected output (yours will differ):

```
...
Upgrade Complete
```

Find the main data file for the employees table in PG16.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l /opt/pgsql/log/pg16.log start
```

```
OID=$(/usr/pgsql-16/bin/psql -p 5432 -d upgradetest -t -A -c "SELECT relfilenode FROM pg_class WHERE relname = 'employees';")
```

```
echo "Relfilenode: $OID"
```

Expected output (yours will differ):

```
Relfilenode: 16385
```

Check the inode of the file in the new cluster.

```
stat /opt/pgsql/data16/base/$(psql -p 5432 -t -A -c "SELECT oid FROM pg_database WHERE datname='upgradetest';")/$(echo $OID)
```

Note the inode number. The old cluster uses the same relfilenode value since the data was copied during the upgrade. The inode numbers will be different - they are separate files on disk.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop -m fast
```

```
exit
```

---

## Part B: How --link Works

In `--link` mode, pg_upgrade creates hard links from the new cluster directory to the same disk blocks used by the old cluster. No data is copied.

```
sudo -iu postgres
```

```
rm -rf /opt/pgsql/data16
```

```
mkdir -p /opt/pgsql/data16
```

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8 2>/dev/null
```

```
/usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --link
```

Expected output (yours will differ):

```
...
Upgrade Complete
```

Start the new PG16 cluster and look up the file location.

```
echo "port = 5434" >> /opt/pgsql/data16/postgresql.conf
```

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l /opt/pgsql/log/pg16.log start
```

```
DB_OID=$(/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -t -A -c "SELECT oid FROM pg_database WHERE datname='upgradetest';")
```

```
REL_OID=$(/usr/pgsql-16/bin/psql -p 5434 -d upgradetest -t -A -c "SELECT relfilenode FROM pg_class WHERE relname = 'employees';")
```

```
stat /opt/pgsql/data16/base/$DB_OID/$REL_OID
```

Expected output (yours will differ):

```
  File: /opt/pgsql/data16/base/16384/16385
  Size: 5210112         Blocks: 10176      IO Block: 4096   regular file
Device: fd01h/64769d    Inode: 131078      Links: 2
...
```

Notice `Links: 2`. This means two directory entries point to the same inode (the old and new clusters). With `--copy`, `Links: 1`.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop -m fast
```

```
exit
```

---

## Part C: Side-by-Side Comparison

Fill in this table based on your measurements and the guide concepts:

| Criteria | --copy (default) | --link |
|---|---|---|
| How it moves data | Physical file copy | Hard links (directory entries) |
| Speed for 10 GB DB | ~minutes | ~seconds |
| Extra disk space needed | Equal to data directory size | Minimal (a few MB for metadata) |
| Can roll back without backup? | Yes - old files untouched | No - files are shared |
| Safe to start old cluster after? | Yes | No |
| Link count on data files | 1 | 2 |
| Best for... | Safety-first upgrades | Large databases, fast maintenance windows |

---

## Part D: Choose the Right Mode

Answer each scenario with the mode you would recommend and why.

**Scenario 1:** Your database is 2 TB. Your maintenance window is 4 hours. A `--copy` upgrade would take 6 hours based on your measured copy rate.

> Your choice and reasoning:

**Scenario 2:** Your database is 50 GB. Your backup policy requires keeping the old cluster for 48 hours after upgrade as a rollback option. Disk space is limited.

> Your choice and reasoning:

**Scenario 3:** Your database is 200 GB. You have 500 GB free disk space. Your SLA requires the ability to roll back within 15 minutes if application errors exceed 10%.

> Your choice and reasoning:

**Scenario 4:** Your database is 10 GB. Speed does not matter. You want the maximum rollback safety.

> Your choice and reasoning:

---

## Checkpoint

- [ ] Ran a `--copy` upgrade and observed that data files have link count of 1
- [ ] Ran a `--link` upgrade and observed that data files have link count of 2
- [ ] Filled in the comparison table
- [ ] Answered all four scenario questions with a mode choice and reasoning

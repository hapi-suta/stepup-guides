# Exercise 03 - Downtime Estimation

Calculate the expected upgrade downtime for your test cluster using both `--link` and `--copy` modes. Then extrapolate to a larger database.

**Run on:** NODE1 only

---

## Task 1: Measure Current Database Size

Start PG15 and measure the size of the database you will upgrade.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

Check the size of each database.

```
/usr/pgsql-15/bin/psql -p 5433 -c "SELECT datname, pg_size_pretty(pg_database_size(datname)) AS size FROM pg_database ORDER BY pg_database_size(datname) DESC;"
```

Expected output (yours will differ):

```
   datname    |  size
--------------+---------
 upgradetest  | 6472 kB
 postgres     | 7400 kB
 template0    | 7309 kB
 template1    | 7309 kB
(4 rows)
```

Check the total data directory size on disk.

```
exit
```

```
sudo du -sh /opt/pgsql/data15
```

Expected output (yours will differ):

```
42M     /opt/pgsql/data15
```

Record this number. You will use it for the downtime calculation.

---

## Task 2: Time a --link Upgrade

Stop PG15.

```
sudo -iu postgres
```

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 stop -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Re-initialize the PG16 target directory (wipe and recreate so you start fresh).

```
rm -rf /opt/pgsql/data16
```

```
mkdir -p /opt/pgsql/data16
```

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):

```
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l logfile start
```

Now time the `--link` upgrade. The `time` command measures elapsed duration.

```
time /usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16 \
  --link
```

Expected output (yours will differ):

```
Performing Consistency Checks
...
Upgrade Complete
----------------
...

real    0m4.321s
user    0m0.512s
sys     0m0.143s
```

Record the `real` time. This is your actual downtime for `--link` mode.

---

## Task 3: Time a --copy Upgrade

Wipe the PG16 target directory again and re-initialize for a clean `--copy` test.

```
rm -rf /opt/pgsql/data16
```

```
mkdir -p /opt/pgsql/data16
```

```
/usr/pgsql-16/bin/initdb -D /opt/pgsql/data16 --encoding=UTF8 --locale=en_US.UTF-8
```

Expected output (yours will differ):

```
...
Success. You can now start the database server using:
    /usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 -l logfile start
```

Time the `--copy` upgrade.

```
time /usr/pgsql-16/bin/pg_upgrade \
  --old-bindir=/usr/pgsql-15/bin \
  --new-bindir=/usr/pgsql-16/bin \
  --old-datadir=/opt/pgsql/data15 \
  --new-datadir=/opt/pgsql/data16
```

(`no --link flag` = defaults to `--copy` mode, which physically copies all data files.)

Expected output (yours will differ):

```
Performing Consistency Checks
...
Upgrade Complete
----------------
...

real    0m8.102s
user    0m1.204s
sys     0m0.521s
```

Record the `real` time. For a small test database, the difference is small. For a large database, the ratio holds.

```
exit
```

---

## Task 4: Calculate Estimated Downtime for Larger Databases

Use the measurements from Tasks 2 and 3 to fill in the table.

Your test database size: __________ MB
Your --link time: __________ seconds
Your --copy time: __________ seconds

Calculate the copy rate in MB/second:

```
# copy_rate_MB_per_sec = database_size_MB / copy_time_seconds
# Example: 42 MB / 8.1 seconds = 5.2 MB/sec
```

Now estimate downtime for common production sizes:

| Database Size | --link (estimate) | --copy (estimate) |
|---|---|---|
| 10 GB | | |
| 100 GB | | |
| 500 GB | | |
| 1 TB | | |

Assume your measured copy rate holds linearly (it roughly does for disk-bound workloads).

For `--link` mode: downtime is nearly constant regardless of database size because you are only creating directory entries, not copying data. Use your measured `--link` time directly as the estimate for all sizes.

---

## Task 5: Add Buffer Time

Your table shows raw pg_upgrade times. A real maintenance window needs additional time for:

- Pre-upgrade verification and checks: +5-10 minutes
- Running `analyze_new_cluster.sh`: proportional to database size (roughly 1/3 of copy time)
- Smoke testing the new cluster: +5-10 minutes
- Application connection reconfiguration: +2-5 minutes
- Buffer for unexpected issues: +30-50% of total

Recalculate your table with these additions.

| Database Size | --link total window | --copy total window |
|---|---|---|
| 10 GB | | |
| 100 GB | | |
| 500 GB | | |
| 1 TB | | |

---

## Checkpoint

- [ ] Measured PG15 test cluster data directory size
- [ ] Timed a `--link` upgrade and recorded the elapsed time
- [ ] Timed a `--copy` upgrade and recorded the elapsed time
- [ ] Calculated the copy rate in MB/second
- [ ] Estimated downtime for 10 GB, 100 GB, 500 GB, and 1 TB databases
- [ ] Added maintenance window buffer time to the estimates

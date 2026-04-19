# Exercise 04 - Rollback Plan

If the upgrade fails or if critical application errors appear after cutover, you need a tested rollback procedure. This exercise walks you through documenting and practicing a rollback for each upgrade method.

**Run on:** NODE1 only

---

## Part A: Rollback After --copy Upgrade

`--copy` mode is the safest for rollback because the old data directory is untouched.

### Scenario

You ran `pg_upgrade --copy`. The new PG16 cluster is running. You discover a critical application bug 30 minutes after cutover. You need to roll back.

### Rollback Steps

**Step 1: Stop the new PG16 cluster immediately.**

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

**Step 2: Verify the old PG15 data directory is intact.**

```
ls -la /opt/pgsql/data15/PG_VERSION
```

Expected output:

```
-rw-------. 1 postgres postgres 3 Oct 15 10:00 /opt/pgsql/data15/PG_VERSION
```

```
cat /opt/pgsql/data15/PG_VERSION
```

Expected output:

```
15
```

**Step 3: Start the old PG15 cluster.**

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15 -l /opt/pgsql/log/pg15-rollback.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

**Step 4: Verify PG15 accepts connections.**

```
/usr/pgsql-15/bin/psql -p 5433 -c "SELECT version();"
```

Expected output (yours will differ):

```
                                                 version
---------------------------------------------------------------------------------------------------------
 PostgreSQL 15.x on x86_64-pc-linux-gnu, compiled by gcc ...
(1 row)
```

**Step 5: Verify row count matches pre-upgrade snapshot.**

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

**Step 6: Update the application connection string back to PG15.**

In a real rollback, this means updating your load balancer, PgBouncer config, or application environment variable to point back to port 5433 (or the old server IP).

```
exit
```

---

## Part B: Rollback After --link Upgrade

`--link` mode is more complex because the old and new clusters share data files via hard links.

### What You Cannot Do

After a `--link` upgrade, you CANNOT simply start the old PG15 cluster. pg_upgrade renames the old global/pg_control file to `pg_control.old` and puts a new one in place. If you start the old cluster, it may corrupt the shared files.

### What You Can Do

**Option 1: Use a backup taken before the upgrade.**

This is why Guide 01 step 8 (take a backup before upgrade) is non-negotiable.

Restore from the pre-upgrade backup and point your application back to it.

**Option 2: Use the old pg_control file that pg_upgrade saved.**

pg_upgrade saves `global/pg_control.old` in the old data directory. In theory you can restore it, but this is risky and not recommended unless you have tested this procedure.

### The Correct Approach

```
sudo -iu postgres
```

Check that your pre-upgrade backup exists.

```
ls /opt/pgsql/backup/
```

Expected output (yours will differ):

```
pre-upgrade-20241015
```

```
ls /opt/pgsql/backup/pre-upgrade-20241015/ | head -10
```

Expected output (yours will differ):

```
backup_label
base
global
pg_commit_ts
pg_dynshmem
pg_hba.conf
pg_ident.conf
pg_logical
pg_multixact
pg_notify
...
```

Stop the new cluster.

```
/usr/pgsql-16/bin/pg_ctl -D /opt/pgsql/data16 stop -m fast
```

Expected output:

```
waiting for server to shut down.... done
server stopped
```

Restore the backup to a new directory (not overwriting data15 - the shared files may have been modified).

```
cp -r /opt/pgsql/backup/pre-upgrade-20241015 /opt/pgsql/data15-restored
```

Start PG15 from the restored backup.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15-restored -l /opt/pgsql/log/pg15-restored.log start
```

Expected output:

```
waiting for server to start.... done
server started
```

Verify data.

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

Stop it when done with this test.

```
/usr/pgsql-15/bin/pg_ctl -D /opt/pgsql/data15-restored stop -m fast
```

```
exit
```

---

## Part C: Document Your Rollback Plan

Fill in the following rollback plan template for a production upgrade. This is what you would hand to your incident response team.

```
ROLLBACK PLAN - PostgreSQL Major Version Upgrade

Trigger Conditions:
- Application error rate > 5% after cutover
- P50 query latency > 2x baseline
- Any FATAL errors in PG16 logs within first 30 minutes

Rollback Decision Owner: [DBA ON CALL]
Rollback Decision Window: 60 minutes after cutover

Rollback Procedure (--copy mode):
1. DBA runs: pg_ctl -D [NEW_DATA_DIR] stop -m fast     [Est. 30 sec]
2. DBA verifies: ls [OLD_DATA_DIR]/PG_VERSION           [Est. 10 sec]
3. DBA runs: pg_ctl -D [OLD_DATA_DIR] start             [Est. 30 sec]
4. DBA runs connectivity test: psql -p [OLD_PORT] -c "SELECT 1;"
5. App team updates connection string to [OLD_PORT]      [Est. 2 min]
6. DBA monitors error rate for 10 minutes

Total estimated rollback time: 5-10 minutes

Rollback Procedure (--link mode):
1. DBA runs: pg_ctl -D [NEW_DATA_DIR] stop -m fast     [Est. 30 sec]
2. DBA restores from backup: cp -r [BACKUP_DIR] [RESTORE_DIR]  [Est. proportional to size]
3. DBA runs: pg_ctl -D [RESTORE_DIR] start             [Est. 30 sec]
4. DBA runs connectivity test: psql -p [OLD_PORT] -c "SELECT 1;"
5. App team updates connection string to [OLD_PORT]      [Est. 2 min]
6. DBA monitors error rate for 10 minutes

Total estimated rollback time: 10-30 minutes (depends on backup restore speed)

Communication:
- Notify on-call manager when rollback starts
- Post in #incidents channel every 5 minutes with status
- Declare incident resolved when error rate < 1% for 10 consecutive minutes
```

---

## Checkpoint

- [ ] Practiced rollback procedure for `--copy` mode: stopped new cluster, started old cluster, verified data
- [ ] Understood why `--link` rollback requires a backup
- [ ] Restored from a pg_basebackup backup to a new directory and verified it starts
- [ ] Filled in the rollback plan template with real values from this lab

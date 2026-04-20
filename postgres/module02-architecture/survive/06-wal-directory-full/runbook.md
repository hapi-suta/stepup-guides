# Runbook 06 - WAL Directory Full

| Field         | Value                                    |
|---------------|------------------------------------------|
| Scenario      | WAL partition filled, PostgreSQL PANIC    |
| Severity      | CRITICAL                                 |
| Recovery Time | 5-10 minutes                             |
| Blast Radius  | Full database outage - all connections fail |

---

## Fix Path

### Step 1 - Confirm the Problem

Check if PostgreSQL is running.

```bash
sudo systemctl status postgresql-16
```

You should see the service is inactive (dead) or failed.

Expected output (yours will differ):
```
● postgresql-16.service - PostgreSQL 16 database server
     Loaded: loaded (/usr/lib/systemd/system/postgresql-16.service; enabled)
     Active: failed (Result: exit-code) since Sat 2026-04-19 14:32:10 UTC
    Process: 1234 ExecStart=/usr/pgsql-16/bin/postmaster -D /opt/pgsql/data (code=exited, status=1/FAILURE)
...
```

Check the PostgreSQL logs for the PANIC message.

```bash
sudo tail -50 /opt/pgsql/log/postgresql-*.log
```

Look for lines like:
- `PANIC: could not write to file "pg_wal/...": No space left on device`
- `LOG: WAL writer process (PID ...) was terminated by signal 6`

### Step 2 - Check WAL Directory Disk Usage

```bash
df -h /opt/pgsql/wal
```

The output will show the partition is at 95%+ usage. Note the "Avail" column - it should be very low.

Expected output (yours will differ):
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvdf       2.0G  1.9G   48M  98% /opt/pgsql/wal
```

### Step 3 - Identify the Problem File

List files in the WAL directory sorted by size.

```bash
ls -lhS /opt/pgsql/wal/
```

Look for any file that does not match the WAL segment naming pattern (24-character hex names like `000000010000000000000001`). In this case you will see `chaos_fill_file.dat` - a large file that should not be there.

### Step 4 - Remove the Injected File

```bash
sudo rm /opt/pgsql/wal/chaos_fill_file.dat
```

Verify space was freed.

```bash
df -h /opt/pgsql/wal
```

The usage should now be well below 90%.

Expected output (yours will differ):
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/xvdf       2.0G   33M  1.9G   2% /opt/pgsql/wal
```

### Step 5 - Start PostgreSQL

```bash
sudo systemctl start postgresql-16
```

PostgreSQL will perform crash recovery automatically using the remaining WAL files.

### Step 6 - Verify Crash Recovery Completed

Check the logs for successful recovery.

```bash
sudo tail -30 /opt/pgsql/log/postgresql-*.log
```

Look for:
- `LOG: database system was not shut down cleanly`
- `LOG: redo starts at ...`
- `LOG: database system is ready to accept connections`

### Step 7 - Verify WAL Writes Work

Connect and run a quick write test.

```bash
sudo -iu postgres
```

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  CREATE TABLE IF NOT EXISTS wal_test_verify (id serial, ts timestamp default now());
  INSERT INTO wal_test_verify DEFAULT VALUES;
  SELECT * FROM wal_test_verify;
"
```

If the INSERT succeeds, WAL writes are working normally.

Expected output (yours will differ):
```
CREATE TABLE
INSERT 0 1
 id |             ts
----+----------------------------
  1 | 2026-04-19 14:35:22.491832
(1 row)
```

### Step 8 - Clean Up Test Table

```bash
/usr/pgsql-16/bin/psql -d labdb -c "
  DROP TABLE IF EXISTS chaos_wal_trigger;
  DROP TABLE IF EXISTS wal_test_verify;
"
```

```bash
exit
```

---

## Revision Concepts

### Why WAL Exists

WAL (Write-Ahead Logging) is PostgreSQL's durability mechanism. Every change is written to the WAL before it is applied to data files. This guarantees that if PostgreSQL crashes, it can replay the WAL to recover any committed transactions.

### What Happens When WAL Cannot Be Written

When the WAL partition runs out of space, PostgreSQL cannot write the next WAL record. Since WAL is the durability guarantee, PostgreSQL has no safe option - it issues a PANIC and shuts down immediately. A PANIC is the most severe error level. It means "we cannot guarantee data integrity if we continue."

The shutdown sequence during a PANIC:
1. PostgreSQL detects the write failure
2. It issues PANIC to the server log
3. All child processes are terminated
4. The postmaster exits

### Crash Recovery

When PostgreSQL starts after a PANIC, it enters crash recovery mode:
1. It reads the `pg_control` file to find the last checkpoint location
2. It replays all WAL from that checkpoint forward
3. Once replay is complete, it marks the database as consistent
4. It begins accepting connections

### Separate WAL Partition Best Practice

Placing `pg_wal` on its own partition (or a symlink to a separate mount) is a production best practice for two reasons:

1. **Isolation** - WAL writes cannot fill the data partition, and data growth cannot block WAL writes
2. **Performance** - WAL writes are sequential; placing them on a separate disk avoids seek contention with random data file I/O

In this lab, `/opt/pgsql/wal` is already a separate path, which makes it easy to monitor independently.

### Monitoring Disk Usage

Production systems should monitor WAL directory usage with alerts at:
- **Warning**: 70% usage
- **Critical**: 85% usage
- **Emergency**: 95% usage

Tools like `pg_stat_wal` (PG 14+) can also track WAL generation rate to predict when the partition will fill.

---

## Interview Discussion

**Q: What is WAL and why is it important?**

WAL ensures durability. Every transaction is written to the log before data files are modified. If the server crashes, PostgreSQL replays the WAL to recover committed transactions. Without WAL, any crash could leave data files in an inconsistent state.

**Q: Why does PostgreSQL PANIC instead of just refusing new writes?**

PostgreSQL cannot selectively refuse WAL writes. WAL is not optional - every data modification, even internal operations like autovacuum, must write WAL. If WAL writes fail partway through a transaction, the database could be left in an inconsistent state. PANIC is the only safe response.

**Q: Should pg_wal be on a separate partition in production?**

Yes. Separating WAL onto its own partition (or disk) provides both isolation and performance benefits. Isolation prevents data growth from blocking WAL writes. Performance improves because WAL writes are sequential and benefit from dedicated I/O bandwidth.

**Q: What other scenarios can fill the WAL directory?**

- Replication slots that are not consumed (WAL accumulates because PostgreSQL cannot recycle segments)
- `wal_keep_size` set too high
- Long-running transactions that prevent WAL recycling
- A failed `pg_basebackup` holding a replication slot open
- Archive command failures when `archive_mode = on` (WAL segments pile up waiting to be archived)

**Q: How do you monitor for this proactively?**

Monitor disk usage on the WAL partition with alerting thresholds. Also monitor `pg_replication_slots` for slots with large `wal_status` lag, and track `pg_stat_wal` for WAL generation rate. Set up alerts on archive failures if using WAL archiving.

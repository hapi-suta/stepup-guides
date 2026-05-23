# Runbook 09 - OOM Kill on Standby

**Severity:** High - No replication redundancy, standby is down
**Time to resolve:** 5-10 minutes

---

## Fix Path

### Step 1: Check if PostgreSQL is running on the standby

SSH to [NODE2] and check the service:

```bash
sudo systemctl status postgresql-16
```

Check if PostgreSQL is accepting connections. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

```bash
exit
```

Expected: Service is not running or shows "Main process exited" with a signal.

### Step 2: Check for OOM evidence in system logs

On [NODE2], look for OOM killer messages:

Check the kernel ring buffer for OOM messages. The pipe to `grep -i` filters case-insensitively, and `tail -10` shows only the last 10 matches:

```bash
sudo dmesg | grep -i "out of memory" | tail -10
```

Also check the system log:

```bash
sudo grep -i "oom" /var/log/syslog | tail -10
```

Or on systems using journald (`-k` shows only kernel messages):

```bash
sudo journalctl -k | grep -i "oom" | tail -10
```

Look for: "Out of memory: Killed process XXXX (postgres)"

Expected output (yours will differ):
```
[12345.678901] Out of memory: Killed process 1234 (postgres) total-vm:1234567kB, anon-rss:987654kB
...
```

> **Concept - OOM Killer**: When Linux runs out of memory, the kernel's OOM killer selects and terminates processes to free memory. PostgreSQL processes are frequent targets because they can consume large amounts of memory for sort operations, hash joins, and shared buffers.

### Step 3: Check PostgreSQL logs for crash evidence

```bash
sudo tail -30 /var/lib/pgsql/16/data/log/postgresql-*.log
```

Look for: "server process was terminated by signal 9: Killed" followed by "terminating any other active server processes".

### Step 4: Clean up any stale PID file

After a SIGKILL, PostgreSQL may leave a stale PID file:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
ls -la /var/lib/pgsql/16/data/postmaster.pid
```

If the PID file exists but the process is not running, PostgreSQL's startup will handle it. If startup fails with "lock file postmaster.pid already exists":

```bash
rm /var/lib/pgsql/16/data/postmaster.pid
```

```bash
exit
```

### Step 5: Restart PostgreSQL

On [NODE2]:

```bash
sudo systemctl start postgresql-16
```

Verify it started:

```bash
sudo systemctl status postgresql-16
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
pg_isready -p 5432
```

```bash
exit
```

> **Concept - Crash Recovery**: After an unclean shutdown (SIGKILL), PostgreSQL performs crash recovery on startup. It replays WAL from the last checkpoint to restore the database to a consistent state. This is automatic and usually takes seconds.

### Step 6: Verify standby is in recovery and streaming

On [NODE2]:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SELECT pg_is_in_recovery();"
```

Expected: `t` (true).

```bash
exit
```

On [NODE1] (primary), verify replication resumed. Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "
  SELECT client_addr, state,
         pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
"
```

Expected output (yours will differ):
```
 client_addr  |   state   | lag_bytes
--------------+-----------+-----------
 10.0.1.52    | streaming |      2048
...
```

```bash
exit
```

Expected: `state` is `streaming` and lag is decreasing.

### Step 7: Verify data consistency

On both nodes:

```sql
SELECT count(*) FROM employees;
```

Counts should match once the standby catches up.

### Step 8: Investigate and prevent future OOM kills

Check current memory settings:

Switch to the postgres user:

```bash
sudo -iu postgres
```

```bash
psql -c "SHOW shared_buffers;"
```

```bash
psql -c "SHOW work_mem;"
```

```bash
psql -c "SHOW maintenance_work_mem;"
```

```bash
exit
```

Check system memory. `-h` shows sizes in human-readable format:

```bash
free -h
```

If memory is consistently tight, consider:
- Reducing work_mem or shared_buffers
- Adding swap space
- Increasing the VM's memory
- Tuning vm.overcommit_memory

---

## Key Concepts for Revision

- **SIGKILL (signal 9)** cannot be caught or handled by the process. PostgreSQL dies immediately without running any cleanup. The postmaster's child processes also terminate.
- **Crash recovery** is PostgreSQL's mechanism for recovering from an unclean shutdown. It replays WAL from the last checkpoint, which is why frequent checkpointing reduces recovery time.
- **vm.overcommit_memory**: Linux setting that controls memory allocation policy. Setting it to 2 prevents overcommit and can help avoid OOM situations. PostgreSQL recommends this setting.
- **oom_score_adj**: You can protect PostgreSQL from the OOM killer by setting a low oom_score_adj value (e.g., -1000) for the postmaster process. This makes other processes more likely to be killed first.
- **Shared buffers** should typically be set to 25% of total RAM. Setting it too high can contribute to OOM pressure, especially with many concurrent connections.
- **work_mem** is allocated per-sort per-query. With many concurrent queries each doing multiple sorts, total memory usage can be many multiples of work_mem.
- **Standby resilience**: Because a standby's replication slot retains WAL on the primary, a brief standby outage (OOM + restart) is usually recoverable without data loss.

---

## Interview Discussion Points

1. **OOM prevention**: What steps do you take to prevent PostgreSQL from being OOM-killed? Discuss vm.overcommit_memory, oom_score_adj, resource limits, and memory tuning.

2. **Diagnosing OOM**: Walk through how you diagnose an OOM kill in production. What logs do you check? How do you determine which process consumed the most memory?

3. **Memory sizing**: How do you calculate appropriate values for shared_buffers, work_mem, and maintenance_work_mem? How do these interact with the number of connections?

4. **Crash recovery time**: After an unclean shutdown, what determines how long crash recovery takes? How does checkpoint_timeout and max_wal_size affect recovery time?

5. **Standby vs primary OOM**: How does an OOM kill on a standby differ from one on a primary in terms of impact and recovery? Which is more dangerous?

6. **Connection pooling and memory**: How does PgBouncer or connection pooling help prevent OOM situations? Explain the relationship between max_connections, work_mem, and total memory usage.

7. **Automated recovery**: Should you configure systemd to auto-restart PostgreSQL after a crash? What are the risks of Restart=always vs Restart=on-failure? When should a human intervene instead?

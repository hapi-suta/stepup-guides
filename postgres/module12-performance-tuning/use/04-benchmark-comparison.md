# Use Exercise 04 - Benchmark Comparison with pgbench

Use pgbench to measure TPS (transactions per second) before and after tuning changes. Record and compare results.

**Server:** NODE1 only

---

## What You Will Do

1. Baseline the default configuration with pgbench
2. Apply two tuning changes
3. Run pgbench again and compare TPS

---

## Setup

SSH into NODE1.

```
ssh -i ~/your-key.pem ec2-user@<NODE1-IP>
```

Check that pgbench is installed.

```
/usr/pgsql-16/bin/pgbench --version
```

Expected output:

```
pgbench (PostgreSQL) 16.x
```

Switch to postgres.

```
sudo -iu postgres
```

---

## Step 1 - Initialize pgbench Test Database

pgbench has its own test tables (accounts, branches, tellers, history). Initialize them at scale factor 10 (roughly 1 million rows in pgbench_accounts).

```
/usr/pgsql-16/bin/pgbench -i -s 10 -d stepup_store
```

(`-i` = initialize, `-s 10` = scale factor 10, `-d stepup_store` = database to use)

Expected output (yours will differ):

```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 8.23 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 12.45 s (drop tables 0.01 s, create tables 0.01 s, client-side generate 7.85 s, vacuum 0.82 s, primary keys 3.76 s).
```

This creates four pgbench tables inside stepup_store. At scale 10 there are:
- 1,000,000 rows in pgbench_accounts
- 10 rows in pgbench_branches
- 100 rows in pgbench_tellers
- 0 rows in pgbench_history (grows during the test)

---

## Step 2 - Record Current Settings

Before benchmarking, record what you are testing against.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT name, setting, unit FROM pg_settings WHERE name IN ('shared_buffers','work_mem','checkpoint_timeout','max_wal_size') ORDER BY name;"
```

Expected output (yours will differ):

```
          name         | setting | unit
-----------------------+---------+------
 checkpoint_timeout    | 300     | s
 max_wal_size          | 1024    | MB
 shared_buffers        | 16384   | 8kB
 work_mem              | 4096    | kB
(4 rows)
```

Write these down. They are your baseline configuration.

---

## Step 3 - Run Baseline Benchmark

Run a 60-second read-write workload with 4 clients (transactions per second is your key metric).

```
/usr/pgsql-16/bin/pgbench -c 4 -j 2 -T 60 -d stepup_store
```

(`-c 4` = 4 client connections, `-j 2` = 2 worker threads, `-T 60` = run for 60 seconds)

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 4
number of threads: 2
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 2841
number of failed transactions: 0
latency average = 84.479 ms
initial connection time = 4.388 ms
tps = 47.353 (without initial connection time)
```

**Record your baseline TPS:**

```
Baseline TPS: ___________
Baseline latency average: ___________
```

---

## Step 4 - Apply Tuning Changes

Apply two specific tuning changes that should improve write-heavy TPS.

Change 1: Raise checkpoint_timeout and max_wal_size so checkpoints fire less often and cause less I/O disruption.

```
exit
```

```
sudo vi /opt/pgsql/data/postgresql.conf
```

Update these lines.

```
checkpoint_timeout = 15min
max_wal_size = 2GB
checkpoint_completion_target = 0.9
```

Save and exit (`:wq`).

Change 2: Raise work_mem to reduce sort spills during the benchmark.

```
sudo -iu postgres
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "ALTER SYSTEM SET work_mem = '16MB';"
```

Expected output:

```
ALTER SYSTEM
```

Reload configuration.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_reload_conf();"
```

Expected output:

```
 pg_reload_conf
----------------
 t
(1 row)
```

Verify the changes took effect.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW checkpoint_timeout;"
```

Expected output:

```
 checkpoint_timeout
--------------------
 15min
(1 row)
```

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SHOW work_mem;"
```

Expected output:

```
 work_mem
----------
 16MB
(1 row)
```

---

## Step 5 - Reset pgbench and bgwriter Stats

Reset bgwriter stats so you get clean numbers for this run.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT pg_stat_reset_shared('bgwriter');"
```

Expected output:

```
 pg_stat_reset_shared
----------------------

(1 row)
```

---

## Step 6 - Run Tuned Benchmark

Run the same benchmark with the same parameters.

```
/usr/pgsql-16/bin/pgbench -c 4 -j 2 -T 60 -d stepup_store
```

Expected output (yours will differ):

```
pgbench (16.x)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
...
tps = 54.821 (without initial connection time)
```

**Record your tuned TPS:**

```
Tuned TPS: ___________
Tuned latency average: ___________
```

---

## Step 7 - Compare Checkpoint Behavior

Check bgwriter stats to see checkpoint impact during the tuned run.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "SELECT checkpoints_timed, checkpoints_req, checkpoint_write_time, buffers_checkpoint, buffers_backend FROM pg_stat_bgwriter;"
```

Expected output (yours will differ):

```
 checkpoints_timed | checkpoints_req | checkpoint_write_time | buffers_checkpoint | buffers_backend
-------------------+-----------------+-----------------------+--------------------+-----------------
                 0 |               0 |                   0.0 |                  0 |             450
(1 row)
```

Because `checkpoint_timeout = 15min` and the test ran for 60 seconds, you should see `checkpoints_timed = 0` - no checkpoint fired during the test. In the baseline with 5-minute timeout, a checkpoint likely fired mid-test and disrupted TPS.

---

## Step 8 - Fill In Your Comparison Table

```
| Metric                | Baseline | Tuned | % Change |
|-----------------------|----------|-------|----------|
| TPS                   |          |       |          |
| Latency avg (ms)      |          |       |          |
| checkpoints_req       |          |       |          |
| buffers_backend       |          |       |          |
```

---

## Cleanup

Remove the pgbench tables to avoid cluttering stepup_store.

```
/usr/pgsql-16/bin/pgbench -i --unlogged-tables --init-steps=d -d stepup_store
```

Or drop them manually.

```
/usr/pgsql-16/bin/psql -p 5432 -d stepup_store -c "DROP TABLE IF EXISTS pgbench_accounts, pgbench_branches, pgbench_tellers, pgbench_history;"
```

Expected output:

```
DROP TABLE
```

```
exit
```

---

## Checkpoint

- [ ] You ran the baseline benchmark and recorded TPS
- [ ] You applied checkpoint and work_mem tuning changes
- [ ] You ran the tuned benchmark with the same parameters
- [ ] Your comparison table is filled in
- [ ] You can explain why reducing checkpoint frequency should improve write TPS

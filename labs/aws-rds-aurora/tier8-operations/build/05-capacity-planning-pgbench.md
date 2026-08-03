# Tier 8 - Build Guide 05: Capacity Planning with pgbench

**Objective:** Install and configure pgbench, run baseline benchmarks, execute load and soak tests, interpret results, and translate findings into capacity recommendations.
**Time:** 45 minutes
**Level:** Expert
**infra_required:** true - Requires a running RDS or Aurora PostgreSQL instance and an EC2 instance in the same VPC to run pgbench from.
**Prerequisites:** An EC2 instance (Amazon Linux 2023, t3.medium or larger) in the same VPC as your RDS instance. PostgreSQL client tools installed on the EC2 instance.

---

## 1. Install pgbench

pgbench is included with the PostgreSQL client package. It does not need to be installed separately if you already have the client tools.

### Install on Amazon Linux 2023 (EC2)

Connect to your EC2 instance via SSH, then:

```bash
sudo dnf install -y postgresql15
```

Verify pgbench is available:

```bash
pgbench --version
```

Expected output:
```
pgbench (PostgreSQL) 15.x
```

### Install on Ubuntu 22.04

```bash
sudo apt-get install -y postgresql-client-15
```

pgbench is included in the `postgresql-client` package on Ubuntu.

---

## 2. Configure the Test Database

pgbench requires a dedicated test database. Do not run pgbench against a production database.

### Create the test database on your RDS instance

Connect to your RDS instance using the master user:

```bash
psql \
  --host=[RDS-ENDPOINT] \
  --port=5432 \
  --username=[MASTER-USER] \
  --dbname=postgres
```

Then create the test database:

```sql
CREATE DATABASE pgbench_test;
\q
```

### Initialize pgbench tables

The `-i` flag initializes the pgbench schema. The `-s` flag sets the scale factor, which determines dataset size. Scale factor 10 creates approximately 150 MB of data (10 million rows in the accounts table).

```bash
pgbench \
  -h [RDS-ENDPOINT] \
  -p 5432 \
  -U [MASTER-USER] \
  --initialize \
  --scale=10 \
  pgbench_test
```

`--scale=10`: Creates 10 x 100,000 = 1,000,000 rows in the `pgbench_accounts` table. Each scale unit is approximately 15 MB of data. Adjust to your instance's memory - the benchmark performs best when the working set fits in memory.

Expected output (yours will differ):
```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 12.34 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 18.45 s (drop tables 0.01 s, create tables 0.01 s, client-side generate 12.34 s, vacuum 2.10 s, primary keys 3.99 s).
```

---

## 3. Run a Baseline Benchmark

The baseline benchmark establishes your current system's throughput ceiling under the standard TPC-B-like workload.

### Run a short baseline test

```bash
pgbench \
  -h [RDS-ENDPOINT] \
  -p 5432 \
  -U [MASTER-USER] \
  --time=60 \
  --client=10 \
  --jobs=2 \
  --progress=10 \
  pgbench_test
```

`--time=60`: Run for 60 seconds.
`--client=10`: Simulate 10 concurrent clients.
`--jobs=2`: Use 2 threads to drive the clients. Should match the number of CPUs on your EC2 client machine.
`--progress=10`: Print progress every 10 seconds so you can watch TPS in real time.

Expected output (yours will differ):
```
pgbench (16.6)
starting vacuum...end.
progress: 10.0 s, 892.3 tps, lat 11.195 ms stddev 4.821, 0 failed
progress: 20.0 s, 887.5 tps, lat 11.270 ms stddev 4.933, 0 failed
progress: 30.0 s, 901.2 tps, lat 11.094 ms stddev 4.721, 0 failed
progress: 40.0 s, 895.6 tps, lat 11.163 ms stddev 4.802, 0 failed
progress: 50.0 s, 888.9 tps, lat 11.244 ms stddev 4.869, 0 failed
progress: 60.0 s, 893.1 tps, lat 11.193 ms stddev 4.830, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 10
number of threads: 2
duration: 60 s
number of transactions actually processed: 53569
number of failed transactions: 0 (0.000%)
latency average = 11.193 ms
latency stddev = 4.831 ms
initial connection time = 42.156 ms
tps = 892.785 (without initial connection time)
```

Record: `tps`, `latency average`, and `latency stddev`. These are your baseline numbers.

---

## 4. Load Testing - Find the Saturation Point

Load testing ramps up concurrency to find where the system saturates. Saturation shows as TPS stopping to grow or latency growing super-linearly.

### Run a concurrency ramp test

Run the same benchmark at increasing client counts and record TPS and average latency for each:

```bash
for CLIENTS in 1 5 10 20 50 100 200; do
  echo "=== Testing with $CLIENTS clients ==="
  pgbench \
    -h [RDS-ENDPOINT] \
    -p 5432 \
    -U [MASTER-USER] \
    --time=30 \
    --client=$CLIENTS \
    --jobs=4 \
    --log \
    --log-prefix=pgbench_run_${CLIENTS}c \
    pgbench_test 2>&1 | grep -E "tps =|latency average"
done
```

`--log` writes per-transaction latency to a file for post-processing.
`--log-prefix` sets the output file name prefix.

Record the results in a table:

| Clients | TPS | Avg Latency (ms) |
|---------|-----|-----------------|
| 1       | ~95 | ~10 |
| 5       | ~450 | ~11 |
| 10      | ~890 | ~11 |
| 20      | ~1,600 | ~12 |
| 50      | ~2,800 | ~18 |
| 100     | ~3,200 | ~31 |
| 200     | ~3,100 | ~65 |

In this example (yours will differ), TPS plateaus around 100 clients and latency begins growing super-linearly. The saturation point is approximately 80-100 concurrent clients for this instance and scale factor.

### What saturation looks like

- **CPU-bound saturation:** TPS grows until CPU hits ~100%, then flattens. Latency grows slowly because there is no queuing, just slower processing.
- **I/O-bound saturation:** TPS drops and latency spikes when the working set exceeds available memory and queries start hitting disk.
- **Lock-contention saturation:** TPS plateaus and `stddev` of latency grows significantly. Check `pg_stat_activity` for sessions in `lock wait` state.

### Check for lock contention during load test

In a separate terminal, connect to the database during the load test:

```sql
SELECT count(*), wait_event_type, wait_event
FROM pg_stat_activity
WHERE state != 'idle'
GROUP BY wait_event_type, wait_event
ORDER BY count DESC;
```

Expected output during a healthy run (yours will differ):
```
 count | wait_event_type | wait_event
-------+-----------------+------------
    48 | Client          | ClientRead
     8 |                 |
     2 | Lock            | relation
```

`Lock` wait events during a load test indicate contention. Many concurrent sessions waiting on the same lock is a problem to optimize at the application level, not the database level.

---

## 5. Soak Testing for Memory and Stability

A soak test runs at realistic load for an extended period (1-8 hours). It reveals:
- Memory leaks (FreeableMemory trending downward over time)
- Connection accumulation (connection count growing, not stable)
- Bloat accumulation (query performance degrading over the test run)
- Autovacuum impact (does autovacuum keep up with the write rate?)

### Run a soak test

Set the client count to your realistic peak load (from the load test, stay below the saturation point):

```bash
pgbench \
  -h [RDS-ENDPOINT] \
  -p 5432 \
  -U [MASTER-USER] \
  --time=3600 \
  --client=50 \
  --jobs=4 \
  --progress=60 \
  --log \
  --log-prefix=soak_test \
  pgbench_test
```

`--time=3600` runs for 1 hour. Extend to 4-8 hours for a thorough soak test.
`--progress=60` prints TPS every 60 seconds, giving you a time-series view of throughput stability.

### Monitor during the soak test

Open CloudWatch in the console and watch these metrics over the test duration:

- `FreeableMemory` - should be stable, not trending downward
- `CPUUtilization` - should be stable at your target utilization
- `DatabaseConnections` - should be stable at your configured client count
- `ReadIOPS` / `WriteIOPS` - watch for unexpected growth
- `SwapUsage` - should remain zero; any swap usage indicates memory pressure

### Check autovacuum keeping up during soak test

Partway through the soak test, check for table bloat:

```sql
SELECT schemaname, relname,
       n_dead_tup, n_live_tup,
       round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) AS dead_pct,
       last_autovacuum
FROM pg_stat_user_tables
WHERE relname LIKE 'pgbench%'
ORDER BY n_dead_tup DESC;
```

If `dead_pct` climbs steadily over hours without autovacuum clearing it, your autovacuum settings are not aggressive enough for this write rate.

---

## 6. Interpret Results and Plan Capacity

### Read-out template

After completing load and soak tests, produce a capacity report with these sections:

**1. Current Baseline**
- Instance type and current resource utilization at steady state (from CloudWatch averages)
- Baseline TPS at typical concurrent connection count
- Average and p95 query latency at baseline

**2. Load Test Results**
- Maximum sustainable TPS before latency degrades unacceptably
- Concurrency level at saturation
- Bottleneck resource (CPU, I/O, memory, or lock contention)

**3. Soak Test Results**
- Was performance stable over the test duration?
- Any resource trends (memory, bloat)?
- Did autovacuum keep up?

**4. Capacity Recommendation**
- Current headroom: what percentage of capacity is being used?
- Projected growth: based on business projections, when will the current instance class be insufficient?
- Recommendation: scale up at what threshold? To what instance class?
- Cost impact: current vs recommended instance class monthly cost

### Right-sizing decision matrix

| Current avg CPU | Current avg connections | Recommendation |
|----------------|------------------------|----------------|
| < 20% | < 30% of max | Downsize - over-provisioned |
| 20-60% | 30-60% of max | Correct - monitor quarterly |
| 60-80% | 60-80% of max | Plan upgrade within 6 months |
| > 80% | > 80% of max | Upgrade now - insufficient headroom |

### Instance class upgrade recommendations

When upgrading for more capacity, prefer vertical scale before adding read replicas for write-bound workloads:

| Bottleneck | Solution |
|------------|----------|
| CPU | Scale up instance class |
| Memory (FreeableMemory low) | Scale up to larger memory class |
| I/O | Switch to I/O-Optimized or use Provisioned IOPS (gp3) |
| Connection count | Add PgBouncer, or upgrade to larger class |
| Write throughput | Scale up writer; consider partitioning high-write tables |
| Read throughput | Add read replicas and route read traffic |

---

## Summary

- pgbench provides a reproducible baseline for comparing performance before and after changes (instance class upgrades, configuration changes, major version upgrades).
- Always initialize pgbench with a scale factor that roughly matches or exceeds your instance's memory to test real I/O behavior.
- Load tests find the saturation point. Soak tests find stability problems. Both are necessary.
- Capacity planning requires combining pgbench results with business growth projections, not just current utilization.
- The goal is to maintain 30-40% headroom above your sustained peak load so that unexpected traffic spikes do not cause incidents.

**Next:** [Guide 06 - Compliance Audit](./06-compliance-audit.md)

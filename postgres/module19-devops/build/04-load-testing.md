# Module 19 - BUILD 04: Load Testing with pgbench

## Overview

Load testing tells you how your database performs under stress before your users find out the hard way. pgbench is PostgreSQL's built-in benchmarking tool. It generates synthetic workloads, measures transactions per second (TPS), and reports latency. This guide covers built-in benchmarks, custom scripts, result interpretation, and continuous load testing.

---

## Prerequisites

- CentOS Stream 9 server with PostgreSQL 16 installed and running
- `postgres` OS user configured
- At least 1 GB of free disk space for test data

---

## Part 1: pgbench Built-in Benchmarks

### 1.1 Create a Test Database

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create a dedicated database for load testing. Never run benchmarks against a production database.

```bash
createdb pgbench_lab
```

### 1.2 Initialize pgbench Tables

pgbench needs to create its own tables before running benchmarks. The `-i` flag means "initialize." The `-s` flag sets the scaling factor - each unit of scale creates 100,000 rows in the `pgbench_accounts` table.

```bash
pgbench -i -s 10 pgbench_lab
```

The `-s 10` creates 1,000,000 rows (10 x 100,000). This gives you roughly 150 MB of test data.

Expected output (yours will differ):
```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 1.23 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 2.45 s (drop tables 0.01 s, create tables 0.01 s, client-side generate 1.23 s, vacuum 0.34 s, primary keys 0.86 s).
```

### 1.3 Check What pgbench Created

```bash
psql -d pgbench_lab -c "\dt+ pgbench_*"
```

Expected output (yours will differ):
```
                            List of relations
 Schema |       Name       | Type  |  Owner   |  Size   | Description
--------+------------------+-------+----------+---------+-------------
 public | pgbench_accounts | table | postgres | 128 MB  |
 public | pgbench_branches | table | postgres | 40 kB   |
 public | pgbench_history  | table | postgres | 0 bytes |
 public | pgbench_tellers  | table | postgres | 40 kB   |
(4 rows)
```

### 1.4 Run a Simple Benchmark

Run the default TPC-B-like benchmark. The flags mean:
- `-c 10` - 10 concurrent clients
- `-j 2` - 2 worker threads
- `-T 30` - Run for 30 seconds

```bash
pgbench -c 10 -j 2 -T 30 pgbench_lab
```

Expected output (yours will differ):
```
pgbench (16.2)
starting vacuum...end.
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 10
query mode: simple
number of clients: 10
number of threads: 2
maximum number of seconds of each test: 30
number of transactions actually processed: 45230
number of failed transactions: 0 (0.000%)
latency average = 6.631 ms
latency stddev = 3.214 ms
initial connection time = 12.345 ms
tps = 1507.553842 (without initial connection time)
```

### 1.5 Understand the Output

| Metric | Meaning |
|--------|---------|
| **transaction type** | Which benchmark was run (TPC-B is the default) |
| **scaling factor** | How much data is in the test tables |
| **number of clients** | Concurrent connections |
| **number of transactions** | Total transactions completed in the time window |
| **failed transactions** | Errors (should be 0 on a healthy server) |
| **latency average** | Average time per transaction in milliseconds |
| **latency stddev** | How much latency varies (lower is more consistent) |
| **tps** | Transactions per second - the headline number |

### 1.6 Read-Only Benchmark

The `-S` flag runs SELECT-only queries. This is useful for testing read replica performance.

```bash
pgbench -c 10 -j 2 -T 30 -S pgbench_lab
```

Expected output (yours will differ):
```
transaction type: <builtin: select only>
...
tps = 28543.234567 (without initial connection time)
```

Notice TPS is much higher for read-only - no write locks, no WAL generation.

### 1.7 Benchmark with Progress Reporting

The `-P` flag prints progress every N seconds. This is useful for spotting performance drops during the test.

```bash
pgbench -c 10 -j 2 -T 60 -P 10 pgbench_lab
```

Expected output (yours will differ):
```
progress: 10.0 s, 1523.4 tps, lat 6.564 ms stddev 3.102 ms, 0 failed
progress: 20.0 s, 1498.7 tps, lat 6.672 ms stddev 3.245 ms, 0 failed
progress: 30.0 s, 1511.2 tps, lat 6.617 ms stddev 3.178 ms, 0 failed
progress: 40.0 s, 1505.8 tps, lat 6.641 ms stddev 3.201 ms, 0 failed
progress: 50.0 s, 1489.3 tps, lat 6.714 ms stddev 3.312 ms, 0 failed
progress: 60.0 s, 1502.1 tps, lat 6.657 ms stddev 3.189 ms, 0 failed
...
```

If TPS drops suddenly at a specific interval, that usually means a checkpoint or vacuum kicked in.

---

## Part 2: pgbench Custom Scripts

### 2.1 Why Custom Scripts?

The built-in TPC-B benchmark tests generic workloads. Real applications have specific query patterns - maybe 80% reads, 15% inserts, 5% updates. Custom scripts let you simulate your actual workload.

### 2.2 Create Test Tables

First, create realistic tables to benchmark against.

```bash
psql -d pgbench_lab
```

```sql
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    stock INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
);
```

```sql
CREATE TABLE IF NOT EXISTS orders (
    id SERIAL PRIMARY KEY,
    product_id INTEGER REFERENCES products(id),
    quantity INTEGER NOT NULL,
    total NUMERIC(10,2) NOT NULL,
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);
```

```sql
CREATE INDEX IF NOT EXISTS idx_products_category ON products (category);
```

```sql
CREATE INDEX IF NOT EXISTS idx_orders_status ON orders (status);
```

```sql
CREATE INDEX IF NOT EXISTS idx_orders_product_id ON orders (product_id);
```

Seed some products.

```sql
INSERT INTO products (name, price, stock, category)
SELECT
    'Product ' || i,
    (random() * 100 + 1)::numeric(10,2),
    (random() * 1000)::integer,
    CASE (i % 5)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Books'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Food'
        WHEN 4 THEN 'Tools'
    END
FROM generate_series(1, 10000) AS i;
```

Exit psql.

```sql
\q
```

### 2.3 Write a Read-Heavy Custom Script

pgbench custom scripts use a specific syntax. Variables are set with `\set` and referenced with `:variable_name`.

```bash
vi /opt/pgsql/benchmark-read-heavy.sql
```

```sql
-- Read-heavy benchmark: product lookups by category
-- \set picks a random value for the variable
\set product_id random(1, 10000)
\set category_num random(0, 4)

-- Simulate a product detail page view
SELECT id, name, price, stock, category
FROM products
WHERE id = :product_id;

-- Simulate a category browse page
SELECT id, name, price
FROM products
WHERE category = CASE :category_num
    WHEN 0 THEN 'Electronics'
    WHEN 1 THEN 'Books'
    WHEN 2 THEN 'Clothing'
    WHEN 3 THEN 'Food'
    WHEN 4 THEN 'Tools'
END
ORDER BY price DESC
LIMIT 20;

-- Simulate checking order count for a product
SELECT count(*) FROM orders WHERE product_id = :product_id;
```

### 2.4 Write a Write-Heavy Custom Script

```bash
vi /opt/pgsql/benchmark-write-heavy.sql
```

```sql
-- Write-heavy benchmark: placing orders
\set product_id random(1, 10000)
\set quantity random(1, 10)

-- Start a transaction
BEGIN;

-- Check product stock
SELECT stock FROM products WHERE id = :product_id FOR UPDATE;

-- Place an order
INSERT INTO orders (product_id, quantity, total, status)
SELECT :product_id, :quantity, price * :quantity, 'pending'
FROM products
WHERE id = :product_id;

-- Decrement stock
UPDATE products
SET stock = stock - :quantity
WHERE id = :product_id AND stock >= :quantity;

COMMIT;
```

### 2.5 Write a Mixed Workload Script

```bash
vi /opt/pgsql/benchmark-mixed.sql
```

```sql
-- Mixed workload: 70% reads, 20% writes, 10% updates
\set product_id random(1, 10000)
\set action random(1, 100)

-- 70% of the time: read a product
SELECT id, name, price, stock FROM products WHERE id = :product_id;

-- 20% of the time: insert an order (simulated by checking action range)
\set quantity random(1, 5)
INSERT INTO orders (product_id, quantity, total, status)
SELECT :product_id, :quantity, price * :quantity, 'pending'
FROM products
WHERE id = :product_id AND :action <= 20;

-- 10% of the time: update stock
UPDATE products SET stock = stock + 100
WHERE id = :product_id AND :action > 90;
```

### 2.6 Run Custom Scripts

The `-f` flag specifies a custom script file.

Run the read-heavy benchmark.

```bash
pgbench -c 10 -j 2 -T 30 -P 5 -f /opt/pgsql/benchmark-read-heavy.sql pgbench_lab
```

Expected output (yours will differ):
```
pgbench (16.2)
starting vacuum...end.
transaction type: /opt/pgsql/benchmark-read-heavy.sql
scaling factor: 1
query mode: simple
number of clients: 10
number of threads: 2
maximum number of seconds of each test: 30
...
tps = 3245.123456 (without initial connection time)
```

Run the write-heavy benchmark.

```bash
pgbench -c 10 -j 2 -T 30 -P 5 -f /opt/pgsql/benchmark-write-heavy.sql pgbench_lab
```

Run the mixed workload.

```bash
pgbench -c 20 -j 4 -T 60 -P 10 -f /opt/pgsql/benchmark-mixed.sql pgbench_lab
```

---

## Part 3: Interpreting pgbench Results

### 3.1 Save Results to a File

The `-l` flag logs individual transaction times to a file for later analysis.

```bash
pgbench -c 10 -j 2 -T 30 -l -f /opt/pgsql/benchmark-read-heavy.sql pgbench_lab
```

This creates files named `pgbench_log.NNNNN` (one per thread) in the current directory.

### 3.2 Analyze Latency Distribution

Look at the log files. Each line has: client_id, transaction_number, time_in_microseconds, script_number, epoch, lag.

```bash
ls -la pgbench_log.*
```

Calculate percentiles from the log. The `sort -t' ' -k3 -n` sorts by the third column (time) numerically.

```bash
cat pgbench_log.* | sort -t' ' -k3 -n | awk '{times[NR]=$3} END {
    printf "p50: %.2f ms\n", times[int(NR*0.5)]/1000;
    printf "p90: %.2f ms\n", times[int(NR*0.9)]/1000;
    printf "p95: %.2f ms\n", times[int(NR*0.95)]/1000;
    printf "p99: %.2f ms\n", times[int(NR*0.99)]/1000;
    printf "max: %.2f ms\n", times[NR]/1000;
}'
```

Expected output (yours will differ):
```
p50: 2.34 ms
p90: 5.67 ms
p95: 8.12 ms
p99: 15.43 ms
max: 45.21 ms
```

### 3.3 What Good Numbers Look Like

For a well-tuned PostgreSQL on modern hardware:

| Metric | Good | Warning | Critical |
|--------|------|---------|----------|
| TPS (mixed) | > 1000 | 500-1000 | < 500 |
| p50 latency | < 5 ms | 5-20 ms | > 20 ms |
| p99 latency | < 50 ms | 50-200 ms | > 200 ms |
| Failed transactions | 0 | < 0.1% | > 0.1% |

These numbers depend heavily on hardware, data size, and workload. Always compare against your own baseline.

### 3.4 Comparing Configurations

Run the same benchmark before and after a configuration change to measure impact.

Before change - record baseline.

```bash
pgbench -c 20 -j 4 -T 60 pgbench_lab 2>&1 | tee /tmp/pgbench_before.txt
```

The `tee` command writes output to both the screen and a file.

After changing a setting (example: shared_buffers), run the same test.

```bash
pgbench -c 20 -j 4 -T 60 pgbench_lab 2>&1 | tee /tmp/pgbench_after.txt
```

Compare the key metrics.

```bash
grep "tps\|latency" /tmp/pgbench_before.txt
```

```bash
grep "tps\|latency" /tmp/pgbench_after.txt
```

---

## Part 4: Scaling Factors and Realistic Workloads

### 4.1 Choosing the Right Scale

The scaling factor determines how much data pgbench creates:

| Scale (-s) | Accounts Rows | Data Size (approx) | Use Case |
|------------|---------------|---------------------|----------|
| 1 | 100,000 | 15 MB | Quick smoke tests |
| 10 | 1,000,000 | 150 MB | Development testing |
| 100 | 10,000,000 | 1.5 GB | Realistic workloads |
| 1000 | 100,000,000 | 15 GB | Production-like tests |

The key: your test data should exceed `shared_buffers`. If all data fits in memory, you are testing RAM speed, not database performance.

### 4.2 Match Production Connection Counts

Check your production connection count first.

```bash
psql -d pgbench_lab -c "SHOW max_connections;"
```

Expected output (yours will differ):
```
 max_connections
-----------------
 200
(1 row)
```

Run benchmarks at various client counts to find your server's breaking point.

10 clients.

```bash
pgbench -c 10 -j 2 -T 30 pgbench_lab 2>&1 | grep tps
```

50 clients.

```bash
pgbench -c 50 -j 4 -T 30 pgbench_lab 2>&1 | grep tps
```

100 clients.

```bash
pgbench -c 100 -j 4 -T 30 pgbench_lab 2>&1 | grep tps
```

150 clients.

```bash
pgbench -c 150 -j 4 -T 30 pgbench_lab 2>&1 | grep tps
```

TPS usually increases with clients up to a point, then plateaus or drops. The optimal client count is typically 2-3x your CPU core count.

### 4.3 Prepared Statements Mode

The `-M prepared` flag uses prepared statements, which is how most applications actually query PostgreSQL.

```bash
pgbench -c 10 -j 2 -T 30 -M prepared pgbench_lab
```

Compare the TPS against the default simple mode. Prepared statements are usually 10-20% faster because PostgreSQL caches the query plan.

---

## Part 5: Continuous Load Testing in CI

### 5.1 Create a Load Test Script for CI

```bash
vi /opt/pgsql/ci-loadtest.sh
```

```bash
#!/bin/bash
# ci-loadtest.sh - Run pgbench in CI and check thresholds
set -e

DB_URL="${DATABASE_URL:-pgbench_lab}"
CLIENTS="${PGBENCH_CLIENTS:-10}"
DURATION="${PGBENCH_DURATION:-30}"
MIN_TPS="${PGBENCH_MIN_TPS:-500}"

echo "=== CI Load Test ==="
echo "Database: $DB_URL"
echo "Clients: $CLIENTS"
echo "Duration: ${DURATION}s"
echo "Minimum TPS threshold: $MIN_TPS"
echo ""

# Initialize pgbench tables
pgbench -i -s 10 "$DB_URL" 2>&1

# Run the benchmark and capture output
OUTPUT=$(pgbench -c "$CLIENTS" -j 2 -T "$DURATION" -P 10 "$DB_URL" 2>&1)
echo "$OUTPUT"

# Extract TPS from output
TPS=$(echo "$OUTPUT" | grep "tps = " | tail -1 | awk '{print $3}' | cut -d'.' -f1)

echo ""
echo "Measured TPS: $TPS"
echo "Threshold: $MIN_TPS"

# Check against threshold
if [ "$TPS" -lt "$MIN_TPS" ]; then
    echo "FAIL: TPS ($TPS) is below threshold ($MIN_TPS)"
    exit 1
fi

echo "PASS: TPS ($TPS) meets threshold ($MIN_TPS)"
```

```bash
chmod +x /opt/pgsql/ci-loadtest.sh
```

### 5.2 GitHub Actions Workflow for Load Testing

```bash
vi /opt/pgsql/ci-loadtest-workflow.yml
```

```yaml
name: Database Load Test

on:
  pull_request:
    branches: [main]
    paths:
      - 'db/**'
  schedule:
    # Run nightly at 2 AM UTC
    - cron: '0 2 * * *'

jobs:
  load-test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_USER: postgres
          POSTGRES_PASSWORD: postgres
          POSTGRES_DB: loadtest
        ports:
          - 5432:5432
        options: >-
          --health-cmd="pg_isready -U postgres"
          --health-interval=10s
          --health-timeout=5s
          --health-retries=5

    env:
      PGPASSWORD: postgres

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Install PostgreSQL client
        run: |
          sudo apt-get update
          sudo apt-get install -y postgresql-client

      - name: Run migrations first
        run: |
          for migration in db/migrations/V*.sql; do
            psql -h localhost -U postgres -d loadtest -f "$migration"
          done

      - name: Run load test
        env:
          PGBENCH_CLIENTS: 10
          PGBENCH_DURATION: 60
          PGBENCH_MIN_TPS: 500
        run: |
          pgbench -i -s 10 -h localhost -U postgres loadtest
          pgbench -c 10 -j 2 -T 60 -P 10 -h localhost -U postgres loadtest

      - name: Custom workload test
        if: hashFiles('db/benchmarks/*.sql') != ''
        run: |
          for script in db/benchmarks/*.sql; do
            echo "Running: $script"
            pgbench -c 10 -j 2 -T 30 -f "$script" -h localhost -U postgres loadtest
          done
```

### 5.3 Track Performance Over Time

Save benchmark results to a CSV for trending.

```bash
vi /opt/pgsql/benchmark-to-csv.sh
```

```bash
#!/bin/bash
# benchmark-to-csv.sh - Append pgbench results to a CSV file
set -e

CSV_FILE="${1:-/opt/pgsql/benchmark-history.csv}"
DB_NAME="${2:-pgbench_lab}"

# Create CSV header if file does not exist
if [ ! -f "$CSV_FILE" ]; then
    echo "timestamp,clients,duration,tps,latency_avg,latency_stddev,transactions,failed" > "$CSV_FILE"
fi

CLIENTS=10
DURATION=30

# Run benchmark
OUTPUT=$(pgbench -c $CLIENTS -j 2 -T $DURATION "$DB_NAME" 2>&1)

# Parse results
TPS=$(echo "$OUTPUT" | grep "tps = " | tail -1 | awk '{print $3}')
LAT_AVG=$(echo "$OUTPUT" | grep "latency average" | awk '{print $4}')
LAT_STD=$(echo "$OUTPUT" | grep "latency stddev" | awk '{print $4}')
TRANSACTIONS=$(echo "$OUTPUT" | grep "number of transactions actually processed" | awk '{print $6}')
FAILED=$(echo "$OUTPUT" | grep "number of failed" | awk '{print $5}')
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Append to CSV
echo "$TIMESTAMP,$CLIENTS,$DURATION,$TPS,$LAT_AVG,$LAT_STD,$TRANSACTIONS,$FAILED" >> "$CSV_FILE"

echo "Results appended to $CSV_FILE"
echo "TPS: $TPS | Latency avg: ${LAT_AVG}ms | Transactions: $TRANSACTIONS"
```

```bash
chmod +x /opt/pgsql/benchmark-to-csv.sh
```

---

## Cleanup

Switch to postgres user.

```bash
sudo -iu postgres
```

Drop the test database.

```bash
dropdb pgbench_lab
```

Remove benchmark files.

```bash
rm -f /opt/pgsql/benchmark-read-heavy.sql
```

```bash
rm -f /opt/pgsql/benchmark-write-heavy.sql
```

```bash
rm -f /opt/pgsql/benchmark-mixed.sql
```

```bash
rm -f pgbench_log.*
```

Exit postgres user.

```bash
exit
```

---

## Key Takeaways

1. pgbench is built into PostgreSQL - no additional install needed
2. Always initialize with `-i` before running benchmarks
3. The scaling factor should create data larger than shared_buffers for realistic tests
4. Use `-P` for progress reporting to spot performance drops during tests
5. Custom scripts let you simulate your real application workload
6. Compare results before/after configuration changes using the same benchmark
7. Use `-M prepared` for realistic application-like behavior
8. Track benchmark results over time to catch performance regressions
9. Optimal client count is typically 2-3x your CPU core count

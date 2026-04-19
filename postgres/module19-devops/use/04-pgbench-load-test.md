# Module 19 - USE 04: pgbench Load Test Exercise

## Objective

Run standard pgbench benchmarks, write a custom pgbench script, compare results across configurations, and generate a load test report.

---

## Setup

Switch to the postgres user.

```bash
sudo -iu postgres
```

Create a dedicated benchmark database.

```bash
createdb bench_exercise
```

Initialize pgbench with scale factor 10 (1 million rows).

```bash
pgbench -i -s 10 bench_exercise
```

Expected output (yours will differ):
```
dropping old tables...
creating tables...
generating data (client-side)...
1000000 of 1000000 tuples (100%) done (elapsed 1.12 s, remaining 0.00 s)
vacuuming...
creating primary keys...
done in 2.34 s
```

---

## Exercise 1: Run Standard Benchmarks

### Read-Write Benchmark

Run the default TPC-B benchmark with 10 clients for 30 seconds. The `-P 5` flag prints progress every 5 seconds.

```bash
pgbench -c 10 -j 2 -T 30 -P 5 bench_exercise
```

Write down the results:
- TPS: ______
- Latency average: ______ ms
- Latency stddev: ______ ms

### Read-Only Benchmark

The `-S` flag runs SELECT-only transactions.

```bash
pgbench -c 10 -j 2 -T 30 -P 5 -S bench_exercise
```

Write down the results:
- TPS: ______
- Latency average: ______ ms

Compare: read-only TPS should be significantly higher than read-write because there are no locks or WAL writes.

### Prepared Statements Mode

The `-M prepared` flag uses prepared statements. This is how real applications query PostgreSQL.

```bash
pgbench -c 10 -j 2 -T 30 -M prepared bench_exercise
```

Write down the TPS: ______

Compare against simple mode TPS from Exercise 1. Prepared mode is usually 10-20% faster.

---

## Exercise 2: Write a Custom pgbench Script

Create a custom table for testing.

```bash
psql -d bench_exercise
```

```sql
CREATE TABLE IF NOT EXISTS products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    price NUMERIC(10,2) NOT NULL,
    stock INTEGER NOT NULL DEFAULT 0,
    category VARCHAR(50),
    updated_at TIMESTAMP DEFAULT NOW()
);
```

```sql
INSERT INTO products (name, price, stock, category)
SELECT
    'Product ' || i,
    (random() * 200 + 1)::numeric(10,2),
    (random() * 500)::integer,
    CASE (i % 4)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Books'
        WHEN 2 THEN 'Clothing'
        WHEN 3 THEN 'Home'
    END
FROM generate_series(1, 50000) AS i;
```

```sql
CREATE INDEX IF NOT EXISTS idx_products_category ON products (category);
```

Exit psql.

```sql
\q
```

Now write the custom benchmark script.

```bash
vi /tmp/custom_bench.sql
```

```sql
\set pid random(1, 50000)
\set qty random(1, 10)

BEGIN;
SELECT id, name, price, stock FROM products WHERE id = :pid;
UPDATE products SET stock = stock - :qty, updated_at = NOW() WHERE id = :pid AND stock >= :qty;
COMMIT;
```

Run the custom script.

```bash
pgbench -c 10 -j 2 -T 30 -P 5 -f /tmp/custom_bench.sql bench_exercise
```

Write down:
- TPS: ______
- Latency average: ______ ms

---

## Exercise 3: Compare Results Across Configurations

### Baseline

Record the current shared_buffers value.

```bash
psql -d bench_exercise -tAc "SHOW shared_buffers;"
```

Run the baseline benchmark. The `tee` command saves output to a file while also printing it.

```bash
pgbench -c 20 -j 4 -T 60 -P 10 bench_exercise 2>&1 | tee /tmp/bench_baseline.txt
```

### Test with Different Client Counts

5 clients.

```bash
pgbench -c 5 -j 2 -T 30 bench_exercise 2>&1 | tee /tmp/bench_c5.txt
```

20 clients.

```bash
pgbench -c 20 -j 4 -T 30 bench_exercise 2>&1 | tee /tmp/bench_c20.txt
```

50 clients.

```bash
pgbench -c 50 -j 4 -T 30 bench_exercise 2>&1 | tee /tmp/bench_c50.txt
```

100 clients.

```bash
pgbench -c 100 -j 4 -T 30 bench_exercise 2>&1 | tee /tmp/bench_c100.txt
```

Extract TPS from each result.

```bash
grep "tps = " /tmp/bench_c5.txt
```

```bash
grep "tps = " /tmp/bench_c20.txt
```

```bash
grep "tps = " /tmp/bench_c50.txt
```

```bash
grep "tps = " /tmp/bench_c100.txt
```

Fill in this table:

| Clients | TPS | Avg Latency (ms) |
|---------|-----|-------------------|
| 5 | | |
| 20 | | |
| 50 | | |
| 100 | | |

At what client count does TPS stop increasing? That is your server's saturation point.

---

## Exercise 4: Generate a Load Test Report

Create a script that runs multiple benchmarks and produces a report.

```bash
vi /tmp/benchmark_report.sh
```

```bash
#!/bin/bash
set -e

DB="bench_exercise"
REPORT="/tmp/pgbench_report.txt"
DURATION=30

echo "========================================" > "$REPORT"
echo "  PostgreSQL Benchmark Report" >> "$REPORT"
echo "  Date: $(date)" >> "$REPORT"
echo "  Database: $DB" >> "$REPORT"
echo "========================================" >> "$REPORT"
echo "" >> "$REPORT"

# Server info
echo "--- Server Configuration ---" >> "$REPORT"
psql -d "$DB" -tAc "SELECT 'PostgreSQL ' || version();" >> "$REPORT"
psql -d "$DB" -tAc "SELECT 'shared_buffers: ' || current_setting('shared_buffers');" >> "$REPORT"
psql -d "$DB" -tAc "SELECT 'work_mem: ' || current_setting('work_mem');" >> "$REPORT"
psql -d "$DB" -tAc "SELECT 'max_connections: ' || current_setting('max_connections');" >> "$REPORT"
psql -d "$DB" -tAc "SELECT 'effective_cache_size: ' || current_setting('effective_cache_size');" >> "$REPORT"
echo "" >> "$REPORT"

# Data size
echo "--- Data Size ---" >> "$REPORT"
psql -d "$DB" -tAc "SELECT pg_size_pretty(pg_database_size('$DB'));" >> "$REPORT"
echo "" >> "$REPORT"

echo "--- Benchmark Results ---" >> "$REPORT"
echo "" >> "$REPORT"

# Read-write test
echo "Test 1: Read-Write (TPC-B), 10 clients, ${DURATION}s" >> "$REPORT"
pgbench -c 10 -j 2 -T "$DURATION" "$DB" 2>&1 | grep -E "tps|latency|transactions" >> "$REPORT"
echo "" >> "$REPORT"

# Read-only test
echo "Test 2: Read-Only, 10 clients, ${DURATION}s" >> "$REPORT"
pgbench -c 10 -j 2 -T "$DURATION" -S "$DB" 2>&1 | grep -E "tps|latency|transactions" >> "$REPORT"
echo "" >> "$REPORT"

# Prepared statements test
echo "Test 3: Read-Write (Prepared), 10 clients, ${DURATION}s" >> "$REPORT"
pgbench -c 10 -j 2 -T "$DURATION" -M prepared "$DB" 2>&1 | grep -E "tps|latency|transactions" >> "$REPORT"
echo "" >> "$REPORT"

# High concurrency test
echo "Test 4: Read-Write, 50 clients, ${DURATION}s" >> "$REPORT"
pgbench -c 50 -j 4 -T "$DURATION" "$DB" 2>&1 | grep -E "tps|latency|transactions" >> "$REPORT"
echo "" >> "$REPORT"

echo "========================================" >> "$REPORT"
echo "  Report complete" >> "$REPORT"
echo "========================================" >> "$REPORT"

echo "Report saved to: $REPORT"
cat "$REPORT"
```

Make it executable.

```bash
chmod +x /tmp/benchmark_report.sh
```

Run the report.

```bash
/tmp/benchmark_report.sh
```

Expected output (yours will differ):
```
========================================
  PostgreSQL Benchmark Report
  Date: Sat Apr 19 10:00:00 UTC 2026
  Database: bench_exercise
========================================

--- Server Configuration ---
PostgreSQL PostgreSQL 16.2 on x86_64-pc-linux-gnu
shared_buffers: 256MB
work_mem: 4MB
max_connections: 200
effective_cache_size: 1GB

--- Data Size ---
157 MB

--- Benchmark Results ---

Test 1: Read-Write (TPC-B), 10 clients, 30s
number of transactions actually processed: 45230
latency average = 6.631 ms
tps = 1507.553842 (without initial connection time)
...
```

---

## Cleanup

Drop the test database.

```bash
dropdb bench_exercise
```

Remove temp files.

```bash
rm -f /tmp/custom_bench.sql
```

```bash
rm -f /tmp/bench_*.txt
```

```bash
rm -f /tmp/benchmark_report.sh
```

```bash
rm -f /tmp/pgbench_report.txt
```

Exit the postgres user.

```bash
exit
```

---

## Checklist

- [ ] Ran standard read-write and read-only benchmarks
- [ ] Compared simple vs prepared statement modes
- [ ] Wrote a custom pgbench script with transactions
- [ ] Tested multiple client counts to find the saturation point
- [ ] Generated a benchmark report with server configuration
- [ ] Understand the relationship between clients, TPS, and latency

# USE Exercise 07: Parquet Export and Data Format Exploration

| | |
|---|---|
| **Time** | 45 minutes |
| **Server** | pg-container (34.235.89.112), pg-primary (3.90.199.62) |
| **OS** | CentOS Stream 9 |
| **Skill level** | Complete beginner |

## What You'll Practice

- Verifying that pyarrow and duckdb are installed and working
- Exporting PostgreSQL data to CSV as a baseline
- Converting CSV to Parquet using Python and pyarrow
- Comparing file sizes between formats
- Querying Parquet files using DuckDB without loading them into a database
- Building a direct pipeline from PostgreSQL to Parquet
- Running analytical queries across multiple Parquet files
- Understanding why Parquet matters for quantitative finance workloads

---

## Why Parquet Matters at Voleon

Before you start, understand the problem Parquet solves.

Voleon runs machine learning pipelines on large financial datasets. A typical table like `quant.market_data` has millions of rows with dozens of columns. When an ML pipeline needs only 3 of those columns, reading the entire row from CSV or a database result wastes I/O.

Parquet is a columnar format. It stores data column by column rather than row by row. Reading 3 columns from a 50-column Parquet file touches only about 6% of the file's bytes. This directly reduces the time it takes to build ML feature vectors.

Parquet also compresses each column independently using type-aware compression (like Snappy or Zstd). Numeric columns like prices and volumes compress far better than they would in CSV, because all the values in a column have similar magnitude and distribution.

The result: Parquet files are typically 5-15x smaller than equivalent CSV files for financial data, and analytical queries run 10-50x faster because far less data is read from disk.

---

## Exercise 1: Verify the Environment

SSH into pg-container. On **pg-container**, as **ec2-user**:

```bash
ssh -i ~/.ssh/id_ed25519 ec2-user@34.235.89.112
```

Check that Python 3 is available. On **pg-container**, as **ec2-user**:

```bash
python3 --version
```

Expected output (yours will differ):

```
Python 3.11.x
```

Check that pyarrow is installed. On **pg-container**, as **ec2-user**:

```bash
python3 -c "import pyarrow; print(pyarrow.__version__)"
```

Expected output (yours will differ):

```
14.0.1
```

Check that duckdb is installed. On **pg-container**, as **ec2-user**:

```bash
python3 -c "import duckdb; print(duckdb.__version__)"
```

Expected output (yours will differ):

```
0.10.1
```

If either import fails with `ModuleNotFoundError`, install the missing package before continuing. On **pg-container**, as **ec2-user**:

```bash
pip3 install pyarrow duckdb
```

---

## Exercise 2: Export Data from PostgreSQL to CSV

The CSV export is your baseline. It lets you compare file sizes and query performance against Parquet later.

You will export from the `quant.instruments` table on pg-primary. The `quant_readonly` role has SELECT access and no write permissions.

On **pg-container**, as **ec2-user**:

```bash
psql -h 3.90.199.62 -U quant_readonly -d quantdb \
  -c "COPY (SELECT * FROM quant.instruments LIMIT 1000) TO STDOUT WITH CSV HEADER" \
  > /tmp/instruments.csv
```

Verify the file was created and has the expected number of lines. On **pg-container**, as **ec2-user**:

```bash
wc -l /tmp/instruments.csv
```

Expected output (yours will differ):

```
1001 /tmp/instruments.csv
```

The count is 1001 because 1000 data rows plus 1 header row equals 1001 lines.

Look at the first few rows. On **pg-container**, as **ec2-user**:

```bash
head -5 /tmp/instruments.csv
```

Expected output (yours will differ):

```
instrument_id,symbol,name,asset_class,exchange,currency,active,created_at
1,AAPL,Apple Inc,equity,NASDAQ,USD,t,2024-01-01 00:00:00
2,MSFT,Microsoft Corp,equity,NASDAQ,USD,t,2024-01-01 00:00:00
3,BTC-USD,Bitcoin USD,crypto,COINBASE,USD,t,2024-01-01 00:00:00
...
```

Check the file size. On **pg-container**, as **ec2-user**:

```bash
ls -lh /tmp/instruments.csv
```

Write down the file size. You will compare this to the Parquet file size in the next exercise.

---

## Exercise 3: Convert CSV to Parquet Using pyarrow

You will write a Python script to convert the CSV file to Parquet with Snappy compression.

On **pg-container**, as **ec2-user**:

```bash
vi /tmp/csv_to_parquet.py
```

Enter the following content:

```python
import pyarrow.csv as pv
import pyarrow.parquet as pq

# Read the CSV file into an Arrow table
# pyarrow infers column types automatically
table = pv.read_csv('/tmp/instruments.csv')

# Print the schema so you can see what types pyarrow inferred
print("Schema:")
print(table.schema)
print(f"\nRow count: {table.num_rows}")
print(f"Column count: {table.num_columns}")

# Write the table to a Parquet file
# compression='snappy' is fast and widely supported
pq.write_table(table, '/tmp/instruments.parquet', compression='snappy')

print("\nParquet file written to /tmp/instruments.parquet")
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

Run the script. On **pg-container**, as **ec2-user**:

```bash
python3 /tmp/csv_to_parquet.py
```

Expected output (yours will differ):

```
Schema:
instrument_id: int64
symbol: string
name: string
asset_class: string
exchange: string
currency: string
active: bool
created_at: timestamp[s]

Row count: 1000
Column count: 8

Parquet file written to /tmp/instruments.parquet
```

Note that pyarrow automatically detected integer, boolean, and timestamp types from the CSV. CSV has no type information - everything is a string. Parquet stores the actual types.

---

## Exercise 4: Compare File Sizes

On **pg-container**, as **ec2-user**:

```bash
ls -lh /tmp/instruments.csv /tmp/instruments.parquet
```

Expected output (yours will differ):

```
-rw-r--r--. 1 ec2-user ec2-user 68K Jun 15 14:40 /tmp/instruments.csv
-rw-r--r--. 1 ec2-user ec2-user 12K Jun 15 14:41 /tmp/instruments.parquet
```

For this dataset the Parquet file is typically 5-8x smaller than the CSV. With larger datasets containing numeric time series data (price, volume, volatility), the compression ratio is often much higher.

---

## Exercise 5: Query Parquet with DuckDB

DuckDB can query Parquet files directly. You do not need to load the data into any database first. DuckDB treats the file path as a table name.

On **pg-container**, as **ec2-user**:

```bash
vi /tmp/query_parquet.py
```

Enter the following content:

```python
import duckdb

# Query 1: count by asset_class
print("=== Asset class distribution ===")
result = duckdb.sql(
    "SELECT asset_class, count(*) as cnt "
    "FROM '/tmp/instruments.parquet' "
    "GROUP BY 1 ORDER BY 2 DESC"
)
print(result)

# Query 2: count active vs inactive
print("\n=== Active status ===")
result = duckdb.sql(
    "SELECT active, count(*) as cnt "
    "FROM '/tmp/instruments.parquet' "
    "GROUP BY 1"
)
print(result)

# Query 3: currencies used
print("\n=== Currencies ===")
result = duckdb.sql(
    "SELECT DISTINCT currency "
    "FROM '/tmp/instruments.parquet' "
    "ORDER BY 1"
)
print(result)

# Query 4: only the columns you need (columnar advantage)
print("\n=== Symbols in equity class ===")
result = duckdb.sql(
    "SELECT symbol, exchange "
    "FROM '/tmp/instruments.parquet' "
    "WHERE asset_class = 'equity' "
    "LIMIT 5"
)
print(result)
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

Run the queries. On **pg-container**, as **ec2-user**:

```bash
python3 /tmp/query_parquet.py
```

Expected output (yours will differ):

```
=== Asset class distribution ===
┌─────────────┬───────┐
│ asset_class │  cnt  │
│   varchar   │ int64 │
├─────────────┼───────┤
│ equity      │   450 │
│ futures     │   280 │
│ fx          │   180 │
│ crypto      │    90 │
└─────────────┴───────┘

=== Active status ===
...
```

Notice that DuckDB uses a columnar query engine internally. When query 4 reads only `symbol` and `exchange`, it reads only those two columns from the Parquet file. The other 6 columns are never read from disk.

---

## Exercise 6: Export market_data Directly to Parquet

For large tables, piping through CSV first doubles the I/O and time. You can build a direct pipeline: read from PostgreSQL using psycopg2 (or psql stdout), load directly into an Arrow table, and write to Parquet in one pass.

On **pg-container**, as **ec2-user**:

```bash
vi /tmp/pg_to_parquet.py
```

Enter the following content:

```python
import subprocess
import pyarrow.csv as pv
import pyarrow.parquet as pq
import io

# Use psql COPY to stream data directly to this script's stdin
# We limit to 10000 rows for this exercise
psql_cmd = [
    "psql",
    "-h", "3.90.199.62",
    "-U", "quant_readonly",
    "-d", "quantdb",
    "-c", "COPY (SELECT * FROM quant.market_data LIMIT 10000) TO STDOUT WITH CSV HEADER"
]

print("Streaming data from PostgreSQL...")
result = subprocess.run(psql_cmd, capture_output=True, text=True)

if result.returncode != 0:
    print(f"psql error: {result.stderr}")
    exit(1)

# Parse the CSV output in memory
csv_bytes = result.stdout.encode("utf-8")
table = pv.read_csv(io.BytesIO(csv_bytes))

print(f"Received {table.num_rows} rows, {table.num_columns} columns")
print(f"Schema: {table.schema}")

# Write to Parquet
output_path = "/tmp/market_data.parquet"
pq.write_table(table, output_path, compression='snappy')

print(f"\nWritten to {output_path}")

# Show the size
import os
size_kb = os.path.getsize(output_path) / 1024
print(f"File size: {size_kb:.1f} KB")
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

Run the export. On **pg-container**, as **ec2-user**:

```bash
python3 /tmp/pg_to_parquet.py
```

Expected output (yours will differ):

```
Streaming data from PostgreSQL...
Received 10000 rows, 7 columns
Schema:
market_data_id: int64
instrument_id: int64
trade_date: date32[day]
open_price: double
close_price: double
volume: int64
created_at: timestamp[s]

Written to /tmp/market_data.parquet
File size: 142.3 KB
```

---

## Exercise 7: Query Across Multiple Parquet Files

DuckDB supports glob patterns for querying multiple Parquet files at once. This is useful when data is partitioned by date or instrument.

First, create a second Parquet file from a different instrument range. On **pg-container**, as **ec2-user**:

```bash
vi /tmp/make_second_parquet.py
```

Enter the following content:

```python
import subprocess
import pyarrow.csv as pv
import pyarrow.parquet as pq
import io

psql_cmd = [
    "psql",
    "-h", "3.90.199.62",
    "-U", "quant_readonly",
    "-d", "quantdb",
    "-c", "COPY (SELECT * FROM quant.market_data LIMIT 10000 OFFSET 10000) TO STDOUT WITH CSV HEADER"
]

result = subprocess.run(psql_cmd, capture_output=True, text=True)
if result.returncode != 0:
    print(f"Error: {result.stderr}")
    exit(1)

csv_bytes = result.stdout.encode("utf-8")
table = pv.read_csv(io.BytesIO(csv_bytes))
pq.write_table(table, '/tmp/market_data_2.parquet', compression='snappy')
print(f"Written {table.num_rows} rows to /tmp/market_data_2.parquet")
```

Save and exit vi: press `Esc`, then type `:wq`, then press `Enter`.

On **pg-container**, as **ec2-user**:

```bash
python3 /tmp/make_second_parquet.py
```

Now query both files together using a glob pattern. On **pg-container**, as **ec2-user**:

```bash
python3 - << 'EOF'
import duckdb

# The glob pattern matches both market_data.parquet and market_data_2.parquet
result = duckdb.sql("""
    SELECT
        count(*) as total_rows,
        min(trade_date) as earliest_date,
        max(trade_date) as latest_date,
        avg(close_price) as avg_close
    FROM '/tmp/market_data*.parquet'
""")
print(result)
EOF
```

Expected output (yours will differ):

```
┌────────────┬───────────────┬──────────────┬────────────────────┐
│ total_rows │ earliest_date │ latest_date  │      avg_close     │
│   int64    │     date      │     date     │       double       │
├────────────┼───────────────┼──────────────┼────────────────────┤
│      20000 │  2020-01-02   │  2026-06-14  │  187.432891234567  │
└────────────┴───────────────┴──────────────┴────────────────────┘
```

DuckDB read both files as if they were one table. In a real Voleon pipeline, you might have hundreds of Parquet files partitioned by year or month, and DuckDB handles them all with the same glob query.

---

## Exercise 8: Inspect Parquet File Metadata

Parquet files carry schema and row group statistics inside the file footer. DuckDB exposes this.

On **pg-container**, as **ec2-user**:

```bash
python3 - << 'EOF'
import duckdb

# Parquet metadata including row group stats
result = duckdb.sql("SELECT * FROM parquet_metadata('/tmp/market_data.parquet')")
print(result)

# Just the schema
result = duckdb.sql("SELECT * FROM parquet_schema('/tmp/market_data.parquet')")
print(result)
EOF
```

The row group statistics include min and max values for each column in each chunk of rows. This is how query engines can skip entire row groups when the filter condition cannot match any value in that group - called predicate pushdown. It is another reason Parquet is so much faster than CSV for analytical queries.

---

## Summary

In this exercise you:
- Verified that pyarrow and duckdb are installed on pg-container
- Exported 1000 rows from PostgreSQL to CSV as a baseline
- Converted the CSV to Parquet using pyarrow with Snappy compression
- Confirmed the Parquet file is significantly smaller than the CSV
- Queried the Parquet file with DuckDB without loading it into any database
- Built a direct pipeline from PostgreSQL to Parquet using subprocess and pyarrow
- Created two Parquet files and queried both together with a glob pattern
- Inspected Parquet file metadata and row group statistics

The key idea is that Parquet plus DuckDB gives Voleon's ML pipelines fast, memory-efficient access to financial datasets without needing a running database server. Feature extraction for model training can read exactly the columns it needs, for exactly the date range it needs, in minimal time.

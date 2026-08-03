# Build 02: Pandas Data Analysis

Pandas is SQL for Python. If you can write a SELECT query, you can use Pandas. This guide teaches you to load, filter, group, and clean data - the exact skills you need before feeding data into any AI model.

---

## Step 1. Create a DataFrame

A DataFrame is a table - rows and columns, just like a SQL result set.

On your **Mac terminal**, run:

```bash
python3 -c "
import pandas as pd

data = {
    'database': ['PostgreSQL', 'MySQL', 'MongoDB', 'Redis', 'PostgreSQL'],
    'query_time_ms': [45, 120, 89, 12, 230],
    'rows_returned': [1500, 3200, 890, 50, 15000],
    'status': ['ok', 'slow', 'ok', 'ok', 'slow']
}
df = pd.DataFrame(data)
print(df)
print()
print('Shape:', df.shape)
print('Columns:', list(df.columns))
print('Dtypes:')
print(df.dtypes)
"
```

Expected output:
```
     database  query_time_ms  rows_returned status
0  PostgreSQL             45           1500     ok
1       MySQL            120           3200   slow
2     MongoDB             89            890     ok
3       Redis             12             50     ok
4  PostgreSQL            230          15000   slow

Shape: (5, 4)
Columns: ['database', 'query_time_ms', 'rows_returned', 'status']
Dtypes:
database         object
query_time_ms     int64
rows_returned     int64
status           object
dtype: object
```

- `pd.DataFrame(data)` takes a dictionary and makes a table. Keys become column names.
- `shape (5, 4)` means 5 rows, 4 columns
- `object` dtype means text (like `varchar` in SQL)
- `int64` means integers (like `bigint` in SQL)

---

## Step 2. Filter rows (WHERE clause)

In SQL: `SELECT * FROM queries WHERE query_time_ms > 100`
In Pandas: `df[df['query_time_ms'] > 100]`

```bash
python3 -c "
import pandas as pd

data = {
    'database': ['PostgreSQL', 'MySQL', 'MongoDB', 'Redis', 'PostgreSQL'],
    'query_time_ms': [45, 120, 89, 12, 230],
    'rows_returned': [1500, 3200, 890, 50, 15000],
    'status': ['ok', 'slow', 'ok', 'ok', 'slow']
}
df = pd.DataFrame(data)

slow = df[df['query_time_ms'] > 100]
print('Slow queries (>100ms):')
print(slow)
"
```

Expected output:
```
Slow queries (>100ms):
     database  query_time_ms  rows_returned status
1       MySQL            120           3200   slow
4  PostgreSQL            230          15000   slow
```

- `df['query_time_ms'] > 100` creates a True/False mask for each row
- `df[mask]` keeps only the True rows - same as a WHERE clause

---

## Step 3. Group and aggregate (GROUP BY)

In SQL: `SELECT database, AVG(query_time_ms) FROM queries GROUP BY database`

```bash
python3 -c "
import pandas as pd

data = {
    'database': ['PostgreSQL', 'MySQL', 'MongoDB', 'Redis', 'PostgreSQL'],
    'query_time_ms': [45, 120, 89, 12, 230],
    'rows_returned': [1500, 3200, 890, 50, 15000],
    'status': ['ok', 'slow', 'ok', 'ok', 'slow']
}
df = pd.DataFrame(data)

grouped = df.groupby('database')['query_time_ms'].mean()
print('Avg query time by database:')
print(grouped)
print()

sorted_df = df.sort_values('query_time_ms', ascending=False)
print('Sorted by query time (desc):')
print(sorted_df)
"
```

Expected output:
```
Avg query time by database:
database
MongoDB        89.0
MySQL         120.0
PostgreSQL    137.5
Redis          12.0
Name: query_time_ms, dtype: float64

Sorted by query time (desc):
     database  query_time_ms  rows_returned status
4  PostgreSQL            230          15000   slow
1       MySQL            120           3200   slow
2     MongoDB             89            890     ok
0  PostgreSQL             45           1500     ok
3       Redis             12             50     ok
```

- `.groupby('database')` groups rows by database name
- `['query_time_ms'].mean()` calculates the average for each group
- `.sort_values()` works like ORDER BY

---

## Step 4. Quick statistics (DESCRIBE)

```bash
python3 -c "
import pandas as pd

data = {
    'database': ['PostgreSQL', 'MySQL', 'MongoDB', 'Redis', 'PostgreSQL'],
    'query_time_ms': [45, 120, 89, 12, 230],
    'rows_returned': [1500, 3200, 890, 50, 15000],
    'status': ['ok', 'slow', 'ok', 'ok', 'slow']
}
df = pd.DataFrame(data)

print('Statistics:')
print(df.describe())
print()

print('Status counts:')
print(df['status'].value_counts())
print()

df['rows_per_ms'] = (df['rows_returned'] / df['query_time_ms']).round(1)
print('With calculated column:')
print(df)
"
```

Expected output:
```
Statistics:
       query_time_ms  rows_returned
count       5.000000       5.000000
mean       99.200000    4128.000000
std        83.944625    6186.329283
min        12.000000      50.000000
25%        45.000000     890.000000
50%        89.000000    1500.000000
75%       120.000000    3200.000000
max       230.000000   15000.000000

Status counts:
status
ok      3
slow    2
Name: count, dtype: int64

With calculated column:
     database  query_time_ms  rows_returned status  rows_per_ms
0  PostgreSQL             45           1500     ok         33.3
1       MySQL            120           3200   slow         26.7
2     MongoDB             89            890     ok         10.0
3       Redis             12             50     ok          4.2
4  PostgreSQL            230          15000   slow         65.2
```

- `.describe()` gives you count, mean, std, min, max, quartiles - like a quick data audit
- `.value_counts()` is `SELECT status, COUNT(*) GROUP BY status ORDER BY COUNT(*) DESC`
- You can add columns with simple math - Pandas applies it row by row automatically

---

## Step 5. Read a CSV file

Most real data comes from files. Let's create a query log CSV and analyze it.

First, create the sample data:

```bash
cat > /tmp/query_log.csv << 'EOF'
timestamp,database,query,duration_ms,status
2026-06-09 10:00:01,PostgreSQL,SELECT * FROM users,45,ok
2026-06-09 10:00:02,PostgreSQL,UPDATE orders SET status='shipped',230,slow
2026-06-09 10:00:03,MySQL,SELECT COUNT(*) FROM products,120,slow
2026-06-09 10:00:04,PostgreSQL,INSERT INTO logs VALUES(...),8,ok
2026-06-09 10:00:05,MongoDB,db.users.find({}),89,ok
2026-06-09 10:00:06,Redis,GET session:abc123,2,ok
2026-06-09 10:00:07,PostgreSQL,DELETE FROM temp_data,340,slow
2026-06-09 10:00:08,MySQL,SELECT * FROM orders JOIN users,180,slow
2026-06-09 10:00:09,PostgreSQL,VACUUM ANALYZE users,500,slow
2026-06-09 10:00:10,Redis,SET cache:page1,3,ok
EOF
```

Now analyze it:

```bash
python3 -c "
import pandas as pd

df = pd.read_csv('/tmp/query_log.csv')
print(df.head())
print()
print('Shape:', df.shape)
print()

slow = df[df['status'] == 'slow']
# f-string: the f before the quotes lets you put variables inside {braces}.
# DBA analogy: like format() in PL/pgSQL or string concatenation with ||
print(f'Slow queries: {len(slow)} out of {len(df)}')
print()

print('Avg duration by database:')
print(df.groupby('database')['duration_ms'].agg(['mean', 'max', 'count']).round(1))
"
```

Expected output:
```
             timestamp    database  ... duration_ms  status
0  2026-06-09 10:00:01  PostgreSQL  ...          45      ok
1  2026-06-09 10:00:02  PostgreSQL  ...         230    slow
2  2026-06-09 10:00:03       MySQL  ...         120    slow
3  2026-06-09 10:00:04  PostgreSQL  ...           8      ok
4  2026-06-09 10:00:05     MongoDB  ...          89      ok

[5 rows x 5 columns]

Shape: (10, 5)

Slow queries: 5 out of 10

Avg duration by database:
             mean  max  count
database
MongoDB      89.0   89      1
MySQL       150.0  180      2
PostgreSQL  224.6  500      5
Redis         2.5    3      2
```

- `pd.read_csv()` loads a CSV into a DataFrame in one line
- `.head()` shows the first 5 rows (like `LIMIT 5`)
- `.agg(['mean', 'max', 'count'])` applies multiple aggregations at once
- PostgreSQL has the highest average AND the slowest single query (500ms VACUUM)

---

## Step 6. Handle missing data

Real datasets have gaps. AI models choke on missing values. You need to find and fix them.

```bash
python3 -c "
import pandas as pd
import numpy as np

data = {
    'server': ['pg-primary', 'pg-standby', 'pg-primary', 'pg-standby', 'pg-primary'],
    'cpu_percent': [45.2, np.nan, 78.1, 62.3, np.nan],
    'memory_gb': [12.4, 8.1, np.nan, 7.9, 14.2],
    'connections': [150, 0, 200, np.nan, 180]
}
df = pd.DataFrame(data)
print('Original (with NaN):')
print(df)
print()

print('Missing values per column:')
print(df.isna().sum())
print()

filled = df.fillna({
    'cpu_percent': df['cpu_percent'].mean(),
    'memory_gb': 0,
    'connections': 0
})
print('After filling NaN:')
print(filled)
"
```

Expected output:
```
Original (with NaN):
       server  cpu_percent  memory_gb  connections
0  pg-primary         45.2       12.4        150.0
1  pg-standby          NaN        8.1          0.0
2  pg-primary         78.1        NaN        200.0
3  pg-standby         62.3        7.9          NaN
4  pg-primary          NaN       14.2        180.0

Missing values per column:
server         0
cpu_percent    2
memory_gb      1
connections    1
dtype: int64

After filling NaN:
       server  cpu_percent  memory_gb  connections
0  pg-primary    45.200000       12.4        150.0
1  pg-standby    61.866667        8.1          0.0
2  pg-primary    78.100000        0.0        200.0
3  pg-standby    62.300000        7.9          0.0
4  pg-primary    61.866667       14.2        180.0
```

- `np.nan` represents missing data (like NULL in SQL)
- `.isna().sum()` counts NULLs per column - your first data quality check
- `.fillna()` replaces NaN with a value. Common strategies:
  - Use the mean (for numeric data where average makes sense)
  - Use 0 (for counts or when missing means "none")
  - Use `.dropna()` to remove rows with missing data entirely

---

## What You Learned

| Pandas | SQL Equivalent | When You'll Use It in AI |
|--------|---------------|-------------------------|
| `pd.DataFrame()` | CREATE TABLE + INSERT | Building training datasets |
| `df[condition]` | WHERE | Filtering training data |
| `df.groupby()` | GROUP BY | Analyzing model performance by category |
| `df.describe()` | Statistical summary | Data exploration before training |
| `pd.read_csv()` | COPY FROM | Loading datasets |
| `df.isna()` | IS NULL | Data quality checks |
| `df.fillna()` | COALESCE | Handling missing values |

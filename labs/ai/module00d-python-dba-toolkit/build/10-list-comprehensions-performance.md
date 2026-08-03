# BUILD 10: List Comprehensions - Slow Query Finder (Performance Tuning)

**What you will build:** `~/pgdba/slow_query_finder.py` - a script that queries `pg_stat_activity` and `pg_stat_user_tables`, filters slow queries using list comprehensions, identifies tables with missing indexes, and ranks results.

**Python concepts covered:** list comprehensions, filtered comprehensions, dict comprehensions, set comprehensions, sorted() with key=, enumerate()

**Time to complete:** ~50 minutes

---

## Prerequisites

- `~/pgdba/pg_utils.py` available (from BUILD 07)
- psycopg2-binary installed: `pip3 install psycopg2-binary`
- PostgreSQL running locally on port 5432

---

## Step 1: List comprehension - transform a list

In SQL, `SELECT col FROM table` transforms a result set - you pick specific columns from rows. A list comprehension does the same thing to a Python list: it transforms each item and gives you a new list.

The syntax is: `[expression for item in collection]`

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
# Raw list of (pid, query_duration_seconds) tuples - like rows from pg_stat_activity
rows = [(101, 0.3), (102, 5.1), (103, 12.7), (104, 0.8), (105, 3.2)]

# SQL: SELECT pid FROM rows
pids = [row[0] for row in rows]

# SQL: SELECT duration FROM rows
durations = [row[1] for row in rows]

print('PIDs:      ', pids)
print('Durations: ', durations)
"
```

What this does: `[row[0] for row in rows]` loops over every `row` in `rows` and pulls out element `[0]` (the pid). It returns a new list without modifying the original - like a SELECT that does not mutate the table.

Expected output (yours will differ):

```
PIDs:       [101, 102, 103, 104, 105]
Durations:  [0.3, 5.1, 12.7, 0.8, 3.2]
```

---

## Step 2: Filtered comprehension - SELECT ... WHERE

Add an `if` clause at the end of a comprehension to filter rows, just like a `WHERE` clause.

The syntax is: `[expression for item in collection if condition]`

On your **Mac terminal**:

```bash
python3 -c "
rows = [(101, 0.3), (102, 5.1), (103, 12.7), (104, 0.8), (105, 3.2)]

# SQL: SELECT pid FROM rows WHERE duration > 1.0
slow_pids = [row[0] for row in rows if row[1] > 1.0]

# SQL: SELECT pid, duration FROM rows WHERE duration > 1.0
slow_rows = [(row[0], row[1]) for row in rows if row[1] > 1.0]

print('Slow PIDs:  ', slow_pids)
print('Slow rows:  ', slow_rows)
"
```

What this does: the `if row[1] > 1.0` at the end acts as a filter - only rows where the duration is over 1 second make it into the result list.

Expected output (yours will differ):

```
Slow PIDs:   [102, 103, 105]
Slow rows:   [(102, 5.1), (103, 12.7), (105, 3.2)]
```

---

## Step 3: Query pg_stat_activity - get all current queries

Now connect to PostgreSQL and apply what you just learned to real data. `pg_stat_activity` shows every current backend connection and what it is running.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT pid,
           usename,
           state,
           EXTRACT(EPOCH FROM (NOW() - query_start))::NUMERIC(10,2) AS duration_sec,
           left(query, 60) AS query_snippet
    FROM pg_stat_activity
    WHERE state IS NOT NULL
      AND pid <> pg_backend_pid()
    ORDER BY duration_sec DESC NULLS LAST
    LIMIT 10
''')

rows = cur.fetchall()
print(f'Active backends: {len(rows)}')
for row in rows:
    print(row)

cur.close()
conn.close()
"
```

What each part does:
- `EXTRACT(EPOCH FROM ...)` - converts an interval to seconds (same concept you use in monitoring queries)
- `left(query, 60)` - truncates the query text so the output is readable
- `pid <> pg_backend_pid()` - excludes this script's own connection from the results
- `cur.fetchall()` - retrieves all rows as a Python list of tuples

Expected output (yours will differ):

```
Active backends: 2
(12345, 'postgres', 'idle', 0.0, 'SELECT pg_sleep(0)')
(12346, 'appuser', 'active', 2.43, 'SELECT * FROM orders WHERE ...')
```

---

## Step 4: Filter with a comprehension - find slow queries

Take the rows from Step 3 and use a filtered comprehension to find queries running longer than 1 second. Duration is at index `[3]` in each row tuple.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT pid,
           usename,
           state,
           EXTRACT(EPOCH FROM (NOW() - query_start))::NUMERIC(10,2) AS duration_sec,
           left(query, 80) AS query_snippet
    FROM pg_stat_activity
    WHERE state IS NOT NULL
      AND pid <> pg_backend_pid()
''')

all_rows = cur.fetchall()

# SQL: SELECT ... WHERE duration_sec > 1.0
slow_queries = [row for row in all_rows if row[3] is not None and row[3] > 1.0]

print(f'Total backends:  {len(all_rows)}')
print(f'Slow (>1s):      {len(slow_queries)}')
for q in slow_queries:
    print(f'  PID {q[0]}: {q[3]}s - {q[4]}')

cur.close()
conn.close()
"
```

What this does: `row[3] is not None` handles the case where `query_start` is NULL (idle connections have no start time). The second condition `row[3] > 1.0` then filters for duration over 1 second. Both conditions must be true - same as `WHERE duration IS NOT NULL AND duration > 1.0` in SQL.

Expected output (yours will differ):

```
Total backends:  3
Slow (>1s):      1
  PID 12346: 2.43s - SELECT * FROM orders WHERE customer_id = 99999
```

---

## Step 5: Dict comprehension - build a pid-to-query lookup

A dict comprehension builds a dictionary (key-value store) from a list. Think of it as building a lookup table in memory - like a hash join that stores one side in a dict before scanning the other.

The syntax is: `{key_expr: value_expr for item in collection}`

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT pid,
           usename,
           left(query, 60) AS query_snippet
    FROM pg_stat_activity
    WHERE state IS NOT NULL
      AND pid <> pg_backend_pid()
''')

rows = cur.fetchall()

# Build a lookup: {pid: query} - like an in-memory hash index
pid_to_query = {row[0]: row[2] for row in rows}

# Build a lookup: {pid: username}
pid_to_user = {row[0]: row[1] for row in rows}

print('pid_to_query:', pid_to_query)
print()

# Now you can look up instantly by PID - O(1) just like a hash index
for pid in list(pid_to_query.keys())[:3]:
    print(f'PID {pid} ({pid_to_user[pid]}): {pid_to_query[pid]}')

cur.close()
conn.close()
"
```

What this does: `{row[0]: row[2] for row in rows}` creates a dictionary where each PID maps directly to its query text. Lookups by PID become O(1) - like using a hash index instead of a sequential scan.

Expected output (yours will differ):

```
pid_to_query: {12345: 'SELECT pg_sleep(0)', 12346: 'SELECT * FROM orders WHERE ...'}

PID 12345 (postgres): SELECT pg_sleep(0)
PID 12346 (appuser): SELECT * FROM orders WHERE customer_id = ...
```

---

## Step 6: sorted() with key= - rank by duration

`sorted()` returns a sorted copy of a list. The `key=` argument is a function that tells Python what value to sort by - same as `ORDER BY column` in SQL.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT pid,
           usename,
           EXTRACT(EPOCH FROM (NOW() - query_start))::NUMERIC(10,2) AS duration_sec,
           left(query, 50) AS query_snippet
    FROM pg_stat_activity
    WHERE state IS NOT NULL
      AND query_start IS NOT NULL
      AND pid <> pg_backend_pid()
''')

rows = cur.fetchall()

# SQL: ORDER BY duration_sec DESC
ranked = sorted(rows, key=lambda row: row[2], reverse=True)

print('Queries ranked by duration (slowest first):')
for row in ranked:
    print(f'  {row[2]:>8.2f}s  PID {row[0]}  {row[1]}  {row[3]}')

cur.close()
conn.close()
"
```

What each part does:
- `key=lambda row: row[2]` - a lambda is an anonymous function; this one takes a row and returns element `[2]` (duration). Python uses that value to compare rows.
- `reverse=True` - sort descending, same as `ORDER BY duration DESC`
- `{row[2]:>8.2f}` - right-align the duration in 8 characters with 2 decimal places, like `LPAD(ROUND(duration, 2)::TEXT, 8)`

Expected output (yours will differ):

```
Queries ranked by duration (slowest first):
     2.43s  PID 12346  appuser  SELECT * FROM orders WHERE customer_id
     0.00s  PID 12345  postgres  SELECT pg_sleep(0)
```

---

## Step 7: enumerate() - add row numbers

`enumerate()` wraps a list and adds a counter to each item - like `ROW_NUMBER() OVER (ORDER BY ...)` in SQL. It returns pairs of `(index, item)`.

On your **Mac terminal**:

```bash
python3 -c "
queries = [
    (12346, 'appuser', 2.43, 'SELECT * FROM orders WHERE ...'),
    (12345, 'postgres', 0.8, 'VACUUM ANALYZE orders'),
    (12347, 'reporting', 0.1, 'SELECT COUNT(*) FROM events'),
]

# enumerate() starts counting at 0 by default; start=1 makes it 1-based
# like ROW_NUMBER() in SQL
print('Rank  PID    User       Duration  Query')
print('-' * 65)
for rank, row in enumerate(queries, start=1):
    print(f'{rank:>4}  {row[0]}  {row[1]:<10}  {row[2]:>6.2f}s   {row[3]}')
"
```

What this does: `for rank, row in enumerate(queries, start=1)` unpacks the `(counter, item)` pair on each iteration. `start=1` makes the first rank `1` instead of `0`.

Expected output (yours will differ):

```
Rank  PID    User       Duration  Query
-----------------------------------------------------------------
   1  12346  appuser        2.43s   SELECT * FROM orders WHERE ...
   2  12345  postgres       0.80s   VACUUM ANALYZE orders
   3  12347  reporting      0.10s   SELECT COUNT(*) FROM events
```

---

## Step 8: Query pg_stat_user_tables - find tables with missing indexes

`pg_stat_user_tables` tracks how many sequential scans vs index scans each table has received. A high `seq_scan` count with low `idx_scan` count signals a missing index - the database is reading the whole table every time.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT schemaname,
           relname AS table_name,
           seq_scan,
           idx_scan,
           n_live_tup,
           pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS table_size
    FROM pg_stat_user_tables
    ORDER BY seq_scan DESC
    LIMIT 20
''')

rows = cur.fetchall()

# Filter: tables with more than 100 seq_scans and fewer than 10 index scans
# (index scans may be NULL if none have happened yet - treat NULL as 0)
missing_index = [
    row for row in rows
    if row[2] > 100 and (row[3] is None or row[3] < 10)
]

print(f'Tables scanned:          {len(rows)}')
print(f'Likely missing indexes:  {len(missing_index)}')
for t in missing_index:
    print(f'  {t[0]}.{t[1]:<30} seq_scan={t[2]}  idx_scan={t[3]}  rows={t[4]}  size={t[5]}')

cur.close()
conn.close()
"
```

What this does: the `or` operator handles NULLs - `row[3] is None or row[3] < 10` catches tables that have never had a single index scan (NULL) as well as those with very few.

Expected output (yours will differ):

```
Tables scanned:          12
Likely missing indexes:  2
  public.orders                     seq_scan=4521  idx_scan=3   rows=985432  size=342 MB
  public.events                     seq_scan=1204  idx_scan=0   rows=2341021 size=1.2 GB
```

---

## Step 9: Set comprehension - find unique users running queries

A set comprehension is like `SELECT DISTINCT` - it removes duplicates automatically. Sets use curly braces `{}` and only store unique values.

The syntax is: `{expression for item in collection}`

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

cur.execute('''
    SELECT pid, usename, state, left(query, 40) AS q
    FROM pg_stat_activity
    WHERE state IS NOT NULL
      AND pid <> pg_backend_pid()
''')

rows = cur.fetchall()

# SQL: SELECT DISTINCT usename FROM pg_stat_activity
active_users = {row[1] for row in rows if row[1] is not None}

# SQL: SELECT DISTINCT state FROM pg_stat_activity
active_states = {row[2] for row in rows if row[2] is not None}

print(f'Unique users connected:  {active_users}')
print(f'Unique connection states: {active_states}')
print(f'User count:              {len(active_users)}')

cur.close()
conn.close()
"
```

What this does: curly braces `{}` with a comprehension inside makes a set, not a dict (a dict comprehension uses `key: value` pairs). Sets automatically discard duplicate values, so you get one entry per unique username.

Expected output (yours will differ):

```
Unique users connected:   {'postgres', 'appuser', 'reporting'}
Unique connection states: {'idle', 'active', 'idle in transaction'}
User count:               3
```

---

## Step 10: Nested comprehension - find large tables per schema

A nested comprehension has two `for` clauses. It is like a `JOIN` or a correlated subquery - for each item in the outer loop, you iterate the inner loop.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
cur = conn.cursor()

# Get all schemas that have tables
cur.execute(\"SELECT DISTINCT schemaname FROM pg_stat_user_tables ORDER BY 1\")
schemas = [row[0] for row in cur.fetchall()]

# Get all table sizes
cur.execute('''
    SELECT schemaname, relname,
           pg_total_relation_size(schemaname||'.'||relname) AS size_bytes
    FROM pg_stat_user_tables
''')
all_tables = cur.fetchall()

# Nested comprehension: for each schema, list tables over 10MB
# SQL equivalent: SELECT schema, table FROM tables WHERE schema = s AND size > 10MB
large_per_schema = [
    (schema, table, size_bytes)
    for schema in schemas
    for (s, table, size_bytes) in all_tables
    if s == schema and size_bytes > 10 * 1024 * 1024
]

print(f'Schemas found: {schemas}')
print(f'Large tables (>10MB): {len(large_per_schema)}')
for schema, table, size_bytes in large_per_schema:
    print(f'  {schema}.{table}: {size_bytes / (1024*1024):.1f} MB')

cur.close()
conn.close()
"
```

What this does: the two `for` clauses work like nested loops - first iterating schemas, then all tables. The `if` at the end filters to only matching schema + size threshold. In practice, for large datasets you would push this filter into SQL.

Expected output (yours will differ):

```
Schemas found: ['public']
Large tables (>10MB): 2
  public.orders: 342.1 MB
  public.events: 1228.5 MB
```

---

## Step 11: Write slow_query_finder.py

Now combine everything into a single script with three functions. Each function uses the comprehension techniques from the previous steps.

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/slow_query_finder.py
```

Press `i` to enter insert mode, then paste the following:

```python
import psycopg2
from psycopg2.extras import RealDictCursor

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'dbname': 'postgres',
}

SLOW_QUERY_THRESHOLD_SEC = 1.0   # flag queries running longer than this
MIN_SEQ_SCAN = 100               # flag tables with more seq_scans than this
MAX_IDX_SCAN = 10                # flag tables with fewer index scans than this
BLOAT_MIN_DEAD_PCT = 10          # flag tables where dead tuples > this % of live


def get_connection() -> psycopg2.extensions.connection:
    """Open a connection to the local PostgreSQL instance."""
    return psycopg2.connect(**DB_CONFIG)


def find_slow_queries(min_seconds: float = SLOW_QUERY_THRESHOLD_SEC) -> list[dict]:
    """
    Return queries currently running longer than min_seconds.
    Queries pg_stat_activity and filters with a list comprehension.
    """
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute('''
        SELECT pid,
               usename,
               state,
               EXTRACT(EPOCH FROM (NOW() - query_start))::NUMERIC(10,2) AS duration_sec,
               wait_event_type,
               wait_event,
               left(query, 100) AS query_snippet
        FROM pg_stat_activity
        WHERE state IS NOT NULL
          AND query_start IS NOT NULL
          AND pid <> pg_backend_pid()
    ''')

    all_rows = cur.fetchall()
    cur.close()
    conn.close()

    # List comprehension with filter - SELECT ... WHERE duration > threshold
    slow = [
        row for row in all_rows
        if row['duration_sec'] is not None and row['duration_sec'] > min_seconds
    ]

    # Sort by duration descending - ORDER BY duration_sec DESC
    return sorted(slow, key=lambda r: r['duration_sec'], reverse=True)


def find_missing_indexes(min_seq_scans: int = MIN_SEQ_SCAN,
                          max_idx_scans: int = MAX_IDX_SCAN) -> list[dict]:
    """
    Return tables that have high sequential scan counts and low index usage.
    These are candidates for new indexes.
    """
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute('''
        SELECT schemaname,
               relname AS table_name,
               seq_scan,
               COALESCE(idx_scan, 0) AS idx_scan,
               n_live_tup AS row_estimate,
               pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS table_size,
               pg_total_relation_size(schemaname||'.'||relname) AS size_bytes
        FROM pg_stat_user_tables
        ORDER BY seq_scan DESC
    ''')

    rows = cur.fetchall()
    cur.close()
    conn.close()

    # Filtered comprehension: tables that look like they are missing an index
    return [
        row for row in rows
        if row['seq_scan'] > min_seq_scans and row['idx_scan'] < max_idx_scans
    ]


def find_bloated_tables(min_dead_pct: float = BLOAT_MIN_DEAD_PCT) -> list[dict]:
    """
    Return tables where dead tuples exceed min_dead_pct percent of live tuples.
    These are candidates for VACUUM.
    """
    conn = get_connection()
    cur = conn.cursor(cursor_factory=RealDictCursor)

    cur.execute('''
        SELECT schemaname,
               relname AS table_name,
               n_live_tup,
               n_dead_tup,
               last_vacuum,
               last_autovacuum,
               pg_size_pretty(pg_total_relation_size(schemaname||'.'||relname)) AS table_size
        FROM pg_stat_user_tables
        WHERE n_live_tup > 1000
        ORDER BY n_dead_tup DESC
    ''')

    rows = cur.fetchall()
    cur.close()
    conn.close()

    # Dict comprehension to compute dead pct per table
    # {table_name: dead_pct} - an in-memory metric lookup
    dead_pcts = {
        row['table_name']: (row['n_dead_tup'] / row['n_live_tup']) * 100
        for row in rows
        if row['n_live_tup'] > 0
    }

    # Filter tables where dead pct exceeds threshold
    bloated = [
        row for row in rows
        if dead_pcts.get(row['table_name'], 0) > min_dead_pct
    ]

    # Sort by dead pct descending
    return sorted(bloated, key=lambda r: dead_pcts.get(r['table_name'], 0), reverse=True)


def print_report() -> None:
    """Run all three checks and print a ranked report."""
    print('=' * 70)
    print('  Slow Query Finder Report')
    print('=' * 70)

    # --- Slow queries ---
    slow = find_slow_queries()
    print(f'\n[1] SLOW QUERIES (>{SLOW_QUERY_THRESHOLD_SEC}s)  found: {len(slow)}')
    print(f'    {"Rank":<5} {"PID":<8} {"User":<12} {"Duration":>10}  {"State":<20}  Query')
    print(f'    {"-"*65}')
    for rank, row in enumerate(slow, start=1):
        print(f'    {rank:<5} {row["pid"]:<8} {row["usename"]:<12} '
              f'{float(row["duration_sec"]):>9.2f}s  '
              f'{str(row["state"]):<20}  {row["query_snippet"]}')
    if not slow:
        print('    No slow queries. Good.')

    # --- Missing indexes ---
    missing = find_missing_indexes()
    print(f'\n[2] TABLES LIKELY MISSING INDEXES  found: {len(missing)}')
    print(f'    {"Table":<40} {"seq_scan":>10}  {"idx_scan":>10}  {"Rows":>12}  Size')
    print(f'    {"-"*85}')
    for rank, row in enumerate(missing, start=1):
        table_fqn = f'{row["schemaname"]}.{row["table_name"]}'
        print(f'    {rank}. {table_fqn:<38} {row["seq_scan"]:>10}  '
              f'{row["idx_scan"]:>10}  {row["row_estimate"]:>12,}  {row["table_size"]}')
    if not missing:
        print('    No missing indexes detected.')

    # --- Bloated tables ---
    bloated = find_bloated_tables()
    print(f'\n[3] BLOATED TABLES (dead > {BLOAT_MIN_DEAD_PCT}% of live)  found: {len(bloated)}')
    print(f'    {"Table":<40} {"Live tup":>12}  {"Dead tup":>12}  {"Last autovacuum":<22}  Size')
    print(f'    {"-"*100}')
    for rank, row in enumerate(bloated, start=1):
        table_fqn = f'{row["schemaname"]}.{row["table_name"]}'
        last_av = str(row['last_autovacuum'])[:19] if row['last_autovacuum'] else 'never'
        print(f'    {rank}. {table_fqn:<38} {row["n_live_tup"]:>12,}  '
              f'{row["n_dead_tup"]:>12,}  {last_av:<22}  {row["table_size"]}')
    if not bloated:
        print('    No bloated tables detected.')

    # --- Summary: unique users with active queries ---
    conn = get_connection()
    cur = conn.cursor()
    cur.execute('''
        SELECT usename FROM pg_stat_activity
        WHERE state = 'active' AND pid <> pg_backend_pid()
    ''')
    active_users = {row[0] for row in cur.fetchall() if row[0]}
    cur.close()
    conn.close()

    print(f'\n[4] USERS WITH ACTIVE QUERIES: {active_users if active_users else "none"}')
    print('\n' + '=' * 70)


if __name__ == '__main__':
    print_report()
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 12: Run the script

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/slow_query_finder.py
```

Expected output (yours will differ):

```
======================================================================
  Slow Query Finder Report
======================================================================

[1] SLOW QUERIES (>1.0s)  found: 0
    No slow queries. Good.

[2] TABLES LIKELY MISSING INDEXES  found: 1
    Table                                    seq_scan    idx_scan          Rows  Size
    -------------------------------------------------------------------------------------
    1. public.events                              4521           3       985,432  342 MB

[3] BLOATED TABLES (dead > 10% of live)  found: 0
    No bloated tables detected.

[4] USERS WITH ACTIVE QUERIES: none

======================================================================
```

Note: if you have no user tables yet, sections 2 and 3 will show empty results. That is expected on a fresh installation.

---

## What you built

You now have `~/pgdba/slow_query_finder.py` - a performance triage tool that runs three real DBA checks. Here is how the Python concepts map to what you already know:

| Python concept | DBA analogy |
|---|---|
| `[x for x in rows]` | `SELECT col FROM table` |
| `[x for x in rows if cond]` | `SELECT ... WHERE cond` |
| `{key: val for row in rows}` | In-memory hash index / lookup table |
| `{val for row in rows}` | `SELECT DISTINCT col FROM table` |
| `sorted(rows, key=..., reverse=True)` | `ORDER BY col DESC` |
| `enumerate(rows, start=1)` | `ROW_NUMBER() OVER (ORDER BY ...)` |
| Nested comprehension | Nested loop join / correlated subquery |

Next: BUILD 11 - Context Managers: Replication Health Checker

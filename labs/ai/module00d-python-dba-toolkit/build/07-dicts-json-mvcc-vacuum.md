# BUILD 07: Dictionaries and JSON - Vacuum Stats Collector

**What you will build:** `~/pgdba/vacuum_stats.py` - a script that queries `pg_stat_user_tables` for dead tuple counts, last vacuum times, and bloat estimates, stores results as JSON, and on subsequent runs shows you the delta since the last snapshot.

**Python concepts covered:** dict creation, accessing/adding/updating keys, `.get()` with defaults, `.keys()` / `.values()` / `.items()`, nested dicts, `json.dumps()`, `json.loads()`, `json.dump()` to file, `json.load()` from file

**Time to complete:** ~50 minutes

---

## Prerequisites

- `~/pgdba/` directory exists
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)
- PostgreSQL running locally on port 5432
- At least one user table with some activity (the `postgres` database is fine)

---

## Step 1: Dict creation - a row stored as key-value pairs

In PostgreSQL you have `hstore` - a key/value extension that stores a row as `'host=>localhost, port=>5432'`. In Python, a **dict** is the built-in version of that. You define it with curly braces `{}`, and each entry is a `key: value` pair separated by a colon.

Think of a dict as one row from a query result - column names are keys, column values are values.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
# One table's stats - like one row from pg_stat_user_tables
table_stats = {
    'table_name': 'orders',
    'n_dead_tup': 4821,
    'n_live_tup': 91200,
    'last_vacuum': '2026-06-10 03:00:00',
    'last_autovacuum': '2026-06-12 14:22:17'
}

print(table_stats)
print(type(table_stats))
"
```

Expected output (yours will differ):

```
{'table_name': 'orders', 'n_dead_tup': 4821, 'n_live_tup': 91200, 'last_vacuum': '2026-06-10 03:00:00', 'last_autovacuum': '2026-06-12 14:22:17'}
<class 'dict'>
```

---

## Step 2: Accessing keys - column access and COALESCE

In SQL you write `SELECT n_dead_tup FROM pg_stat_user_tables`. In Python you access a dict value by its key using square brackets: `d['key']`. That raises a `KeyError` if the key is missing - the equivalent of a column that does not exist.

To handle missing keys safely, use `.get('key', default)`. This is exactly like `COALESCE(column, default)` in SQL - return the default if the value is NULL (or missing).

On your **Mac terminal**:

```bash
python3 -c "
table_stats = {
    'table_name': 'orders',
    'n_dead_tup': 4821,
    'n_live_tup': 91200,
    'last_vacuum': '2026-06-10 03:00:00'
}

# Direct access - works when key exists
print(table_stats['table_name'])
print(table_stats['n_dead_tup'])

# .get() with default - like COALESCE(last_autovacuum, 'never')
last_auto = table_stats.get('last_autovacuum', 'never')
print(f'Last autovacuum: {last_auto}')

# Direct access on a missing key raises KeyError
try:
    print(table_stats['missing_column'])
except KeyError as e:
    print(f'KeyError: {e}')
"
```

Expected output (yours will differ):

```
orders
4821
Last autovacuum: never
KeyError: 'missing_column'
```

---

## Step 3: Adding and updating keys

In SQL you use `UPDATE table SET col = new_value`. In a dict, you just assign: `d['key'] = value`. If the key already exists, it updates it. If it does not exist, it adds it. No `INSERT OR UPDATE` / `ON CONFLICT` needed.

On your **Mac terminal**:

```bash
python3 -c "
table_stats = {
    'table_name': 'orders',
    'n_dead_tup': 4821,
    'n_live_tup': 91200
}

# Add a new key
table_stats['bloat_ratio'] = round(4821 / (4821 + 91200) * 100, 2)

# Update an existing key
table_stats['n_dead_tup'] = 4950

print(table_stats)
print(f'Bloat ratio: {table_stats[\"bloat_ratio\"]}%')
print(f'Updated dead tuples: {table_stats[\"n_dead_tup\"]}')
"
```

Expected output (yours will differ):

```
{'table_name': 'orders', 'n_dead_tup': 4950, 'n_live_tup': 91200, 'bloat_ratio': 5.03}
Bloat ratio: 5.03%
Updated dead tuples: 4950
```

---

## Step 4: .items() - iterating over columns in a row

In PL/pgSQL you loop over a record's fields. In Python, `.items()` gives you both the key and value at the same time as you loop - like getting column name and value together in one pass.

On your **Mac terminal**:

```bash
python3 -c "
table_stats = {
    'table_name': 'orders',
    'n_dead_tup': 4821,
    'n_live_tup': 91200,
    'last_vacuum': '2026-06-10 03:00:00',
    'last_autovacuum': 'never'
}

# .items() gives (key, value) pairs - like iterating columns
print('--- Table stats ---')
for column_name, column_value in table_stats.items():
    print(f'  {column_name:<20} {column_value}')

# .keys() - just the column names
print()
print('Columns:', list(table_stats.keys()))

# .values() - just the values
print('Values: ', list(table_stats.values()))
"
```

What each piece does:
- `.items()` - returns each `(key, value)` pair as a tuple, one at a time
- `{column_name:<20}` - left-aligns the string in a 20-character field (like `LPAD` in SQL)
- `.keys()` and `.values()` - return just the keys or just the values

Expected output (yours will differ):

```
--- Table stats ---
  table_name           orders
  n_dead_tup           4821
  n_live_tup           91200
  last_vacuum          2026-06-10 03:00:00
  last_autovacuum      never

Columns: ['table_name', 'n_dead_tup', 'n_live_tup', 'last_vacuum', 'last_autovacuum']
Values:  ['orders', 4821, 91200, '2026-06-10 03:00:00', 'never']
```

---

## Step 5: Nested dicts - JSONB nested objects

A dict value can itself be a dict. This is exactly like JSONB in PostgreSQL - you can nest objects inside objects. Here you will model the full stats snapshot: `{database: {schema.table: {stat: value}}}`.

On your **Mac terminal**:

```bash
python3 -c "
# Nested dict: database -> table -> stats
# Like a JSONB column: {'postgres': {'public.orders': {'n_dead_tup': 4821}}}
snapshot = {
    'postgres': {
        'public.orders': {
            'n_dead_tup': 4821,
            'n_live_tup': 91200,
            'last_vacuum': '2026-06-10 03:00:00'
        },
        'public.customers': {
            'n_dead_tup': 12,
            'n_live_tup': 5300,
            'last_vacuum': '2026-06-13 01:00:00'
        }
    }
}

# Access like JSONB: snapshot->'postgres'->'public.orders'->>'n_dead_tup'
dead = snapshot['postgres']['public.orders']['n_dead_tup']
print(f'orders dead tuples: {dead}')

# Iterate all tables in a database
for table_name, stats in snapshot['postgres'].items():
    print(f'  {table_name}: {stats[\"n_dead_tup\"]} dead tuples')
"
```

Expected output (yours will differ):

```
orders dead tuples: 4821
  public.orders: 4821 dead tuples
  public.customers: 12 dead tuples
```

---

## Step 6: Query pg_stat_user_tables

Now connect to PostgreSQL and pull real vacuum stats. The `pg_stat_user_tables` view is your primary source - it tracks dead tuples, live tuples, last vacuum/autovacuum timestamps, and more for every user table.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

# On Mac Homebrew, the default superuser matches your Mac username
DB_USER = os.environ.get('USER', 'postgres')
conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres', user=DB_USER)
cur = conn.cursor()

cur.execute('''
    SELECT
        schemaname || '.' || relname AS table_name,
        n_dead_tup,
        n_live_tup,
        last_vacuum::TEXT,
        last_autovacuum::TEXT
    FROM pg_stat_user_tables
    ORDER BY n_dead_tup DESC
    LIMIT 5
''')

rows = cur.fetchall()
print(f'Found {len(rows)} tables')
for row in rows:
    print(row)

cur.close()
conn.close()
"
```

What each piece does:
- `os.environ.get('USER', 'postgres')` - reads your Mac username from the environment, falling back to `postgres`
- `schemaname || '.' || relname` - same SQL concatenation you already know, gives `public.orders`
- `::TEXT` - casts the timestamp to a string so Python receives it as a plain string (otherwise it comes as a Python `datetime` object)
- `fetchall()` - retrieves all result rows as a list of tuples

Expected output (yours will differ):

```
Found 3 tables
('public.orders', 4821, 91200, '2026-06-10 03:00:00', '2026-06-12 14:22:17')
('public.line_items', 312, 45600, None, '2026-06-13 02:05:00')
('public.customers', 12, 5300, '2026-06-13 01:00:00', None)
```

If you see `Found 0 tables`, your `postgres` database has no user tables. That is fine - steps 7 onwards will show empty dicts and the script will still work correctly.

---

## Step 7: Store query results in a nested dict structure

Convert the raw query rows into a nested dict: `{database: {schema.table: {dead_tuples: N, ...}}}`. This mirrors how you would store it in a JSONB column.

On your **Mac terminal**:

```bash
python3 -c "
import psycopg2
import os

DB_USER = os.environ.get('USER', 'postgres')
conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres', user=DB_USER)
cur = conn.cursor()

cur.execute('''
    SELECT
        schemaname || '.' || relname,
        n_dead_tup,
        n_live_tup,
        last_vacuum::TEXT,
        last_autovacuum::TEXT
    FROM pg_stat_user_tables
    ORDER BY n_dead_tup DESC
''')

rows = cur.fetchall()
cur.close()
conn.close()

# Build nested dict - {database: {schema.table: {stats}}}
snapshot = {'postgres': {}}

for table_name, n_dead, n_live, last_vac, last_autovac in rows:
    snapshot['postgres'][table_name] = {
        'n_dead_tup': n_dead,
        'n_live_tup': n_live,
        'last_vacuum': last_vac if last_vac else 'never',
        'last_autovacuum': last_autovac if last_autovac else 'never'
    }

# Print summary
for table, stats in snapshot['postgres'].items():
    print(f'{table}: dead={stats[\"n_dead_tup\"]}  live={stats[\"n_live_tup\"]}  last_vac={stats[\"last_vacuum\"]}')
"
```

What each piece does:
- `for table_name, n_dead, n_live, last_vac, last_autovac in rows` - unpacks each tuple into named variables, one per column
- `last_vac if last_vac else 'never'` - Python's inline conditional (like `COALESCE(last_vacuum, 'never')`)

Expected output (yours will differ):

```
public.orders: dead=4821  live=91200  last_vac=2026-06-10 03:00:00
public.line_items: dead=312  live=45600  last_vac=never
public.customers: dead=12  live=5300  last_vac=2026-06-13 01:00:00
```

---

## Step 8: json.dumps() - convert dict to a JSON string

`json.dumps()` serializes a Python dict into a JSON string. In PostgreSQL terms, this is equivalent to `to_jsonb(row)` or `row_to_json()` - converting a structured object into a JSON representation you can store or transmit.

On your **Mac terminal**:

```bash
python3 -c "
import json

stats = {
    'n_dead_tup': 4821,
    'n_live_tup': 91200,
    'last_vacuum': '2026-06-10 03:00:00',
    'last_autovacuum': 'never'
}

# Convert to compact JSON string
compact = json.dumps(stats)
print('Compact:')
print(compact)
print()

# Convert to pretty-printed JSON string - indent=2 adds whitespace
pretty = json.dumps(stats, indent=2)
print('Pretty:')
print(pretty)
"
```

What each piece does:
- `json.dumps(dict)` - 'dumps' means dump to **string** (the `s` stands for string)
- `indent=2` - adds 2-space indentation to make the output human-readable
- The result is a plain string - not a file, not a database record, just text

Expected output (yours will differ):

```
Compact:
{"n_dead_tup": 4821, "n_live_tup": 91200, "last_vacuum": "2026-06-10 03:00:00", "last_autovacuum": "never"}

Pretty:
{
  "n_dead_tup": 4821,
  "n_live_tup": 91200,
  "last_vacuum": "2026-06-10 03:00:00",
  "last_autovacuum": "never"
}
```

---

## Step 9: json.dump() - write stats to a file

`json.dump()` (no `s`) writes a dict directly to a file. Think of this like `COPY table TO '/path/file.json'` in PostgreSQL - you are persisting the data to disk for later retrieval.

On your **Mac terminal**:

```bash
python3 -c "
import json
import datetime

snapshot = {
    'captured_at': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
    'postgres': {
        'public.orders': {
            'n_dead_tup': 4821,
            'n_live_tup': 91200,
            'last_vacuum': '2026-06-10 03:00:00',
            'last_autovacuum': 'never'
        }
    }
}

output_path = '/Users/' + __import__('os').environ.get('USER', 'postgres') + '/pgdba/vacuum_stats.json'

# Open the file for writing and dump the dict into it
with open(output_path, 'w') as f:
    json.dump(snapshot, f, indent=2)

print(f'Wrote snapshot to {output_path}')
"
```

What each piece does:
- `json.dump(obj, f, indent=2)` - writes the dict to the open file `f` with 2-space indentation
- `with open(path, 'w') as f:` - opens the file for writing; `with` ensures the file is closed automatically, like a transaction that commits on exit
- `datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')` - formats the current timestamp (like `to_char(now(), 'YYYY-MM-DD HH24:MI:SS')`)

Verify the file was written:

```bash
cat ~/pgdba/vacuum_stats.json
```

Expected output (yours will differ):

```json
{
  "captured_at": "2026-06-13 09:45:02",
  "postgres": {
    "public.orders": {
      "n_dead_tup": 4821,
      "n_live_tup": 91200,
      "last_vacuum": "2026-06-10 03:00:00",
      "last_autovacuum": "never"
    }
  }
}
```

---

## Step 10: json.load() - read a previous snapshot

`json.load()` reads a JSON file back into a Python dict. This is like `COPY table FROM '/path/file.json'` or reading from a state table that stores your last known values. You will use it to compare the current stats against the previous run.

On your **Mac terminal**:

```bash
python3 -c "
import json
import os

snapshot_path = os.path.expanduser('~/pgdba/vacuum_stats.json')

with open(snapshot_path, 'r') as f:
    previous = json.load(f)

print(f'Previous snapshot captured at: {previous[\"captured_at\"]}')
print(f'Databases in snapshot: {list(previous.keys())}')

for table, stats in previous['postgres'].items():
    print(f'  {table}: {stats[\"n_dead_tup\"]} dead tuples')
"
```

What each piece does:
- `json.load(f)` - reads the file and converts JSON back into a Python dict (the reverse of `json.dump`)
- `os.path.expanduser('~/pgdba/...')` - expands the `~` shortcut to the actual home directory path

Expected output (yours will differ):

```
Previous snapshot captured at: 2026-06-13 09:45:02
Databases in snapshot: ['captured_at', 'postgres']
  public.orders: 4821 dead tuples
```

---

## Step 11: Build a compare function - delta in dead tuples

Now write a function that compares the current snapshot against the previous one and shows how dead tuples have changed. This is the core value of the script - trend detection.

On your **Mac terminal**:

```bash
python3 -c "
def compare_snapshots(previous, current):
    '''
    Compare two vacuum snapshots and print the delta in dead tuples.
    previous and current are both dicts with structure: {db: {table: {stats}}}.
    '''
    print(f'  {\"TABLE\":<35} {\"PREV DEAD\":>10} {\"CURR DEAD\":>10} {\"DELTA\":>10}')
    print('  ' + '-' * 70)

    prev_tables = previous.get('postgres', {})
    curr_tables = current.get('postgres', {})

    # All tables that appear in either snapshot
    all_tables = set(prev_tables.keys()) | set(curr_tables.keys())

    for table in sorted(all_tables):
        prev_dead = prev_tables.get(table, {}).get('n_dead_tup', 0)
        curr_dead = curr_tables.get(table, {}).get('n_dead_tup', 0)
        delta = curr_dead - prev_dead

        # Flag tables with growing dead tuples
        flag = ' <-- GROWING' if delta > 100 else ''
        print(f'  {table:<35} {prev_dead:>10} {curr_dead:>10} {delta:>+10}{flag}')

# Example: simulate previous vs current
previous = {
    'postgres': {
        'public.orders':    {'n_dead_tup': 4821},
        'public.customers': {'n_dead_tup': 12}
    }
}
current = {
    'postgres': {
        'public.orders':    {'n_dead_tup': 5340},
        'public.customers': {'n_dead_tup': 8},
        'public.payments':  {'n_dead_tup': 230}
    }
}

compare_snapshots(previous, current)
"
```

What each piece does:
- `set(a.keys()) | set(b.keys())` - union of both key sets, so you catch tables that appear in one but not the other (like a `FULL OUTER JOIN`)
- `.get(table, {}).get('n_dead_tup', 0)` - double `.get()` with default, safe even if the table is new and has no previous entry
- `{delta:>+10}` - formats the number right-aligned in 10 chars, always showing `+` or `-` sign (like `SIGN()` in SQL)

Expected output (yours will differ):

```
  TABLE                               PREV DEAD  CURR DEAD      DELTA
  ----------------------------------------------------------------------
  public.customers                           12          8         -4
  public.orders                            4821       5340       +519 <-- GROWING
  public.payments                             0        230       +230 <-- GROWING
```

---

## Step 12: Combine into vacuum_stats.py

Open vi and write the complete script:

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/vacuum_stats.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
import psycopg2
import json
import os
import datetime

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
DB_HOST = 'localhost'
DB_PORT = 5432
DB_NAME = 'postgres'
DB_USER = os.environ.get('USER', 'postgres')
SNAPSHOT_FILE = os.path.expanduser('~/pgdba/vacuum_stats.json')

# -------------------------------------------------------
# Collect current vacuum stats from pg_stat_user_tables
# -------------------------------------------------------
def collect_vacuum_stats() -> dict:
    conn = psycopg2.connect(host=DB_HOST, port=DB_PORT, dbname=DB_NAME, user=DB_USER)
    cur = conn.cursor()

    cur.execute('''
        SELECT
            schemaname || '.' || relname,
            n_dead_tup,
            n_live_tup,
            last_vacuum::TEXT,
            last_autovacuum::TEXT
        FROM pg_stat_user_tables
        ORDER BY n_dead_tup DESC
    ''')

    rows = cur.fetchall()
    cur.close()
    conn.close()

    snapshot: dict = {
        'captured_at': datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S'),
        'postgres': {}
    }

    for table_name, n_dead, n_live, last_vac, last_autovac in rows:
        snapshot['postgres'][table_name] = {
            'n_dead_tup': n_dead,
            'n_live_tup': n_live,
            'last_vacuum':     last_vac     if last_vac     else 'never',
            'last_autovacuum': last_autovac if last_autovac else 'never'
        }

    return snapshot

# -------------------------------------------------------
# Load previous snapshot from file (if it exists)
# -------------------------------------------------------
def load_previous_snapshot() -> dict:
    if not os.path.exists(SNAPSHOT_FILE):
        return {}
    with open(SNAPSHOT_FILE, 'r') as f:
        return json.load(f)

# -------------------------------------------------------
# Save current snapshot to file
# -------------------------------------------------------
def save_snapshot(snapshot: dict) -> None:
    with open(SNAPSHOT_FILE, 'w') as f:
        json.dump(snapshot, f, indent=2)

# -------------------------------------------------------
# Compare two snapshots and print the delta
# -------------------------------------------------------
def compare_snapshots(previous: dict, current: dict) -> None:
    prev_tables = previous.get('postgres', {})
    curr_tables = current.get('postgres', {})
    all_tables = set(prev_tables.keys()) | set(curr_tables.keys())

    print(f'  {"TABLE":<35} {"PREV DEAD":>10} {"CURR DEAD":>10} {"DELTA":>10}')
    print('  ' + '-' * 70)

    for table in sorted(all_tables):
        prev_dead = prev_tables.get(table, {}).get('n_dead_tup', 0)
        curr_dead = curr_tables.get(table, {}).get('n_dead_tup', 0)
        delta = curr_dead - prev_dead
        flag = ' <-- GROWING' if delta > 100 else ''
        print(f'  {table:<35} {prev_dead:>10} {curr_dead:>10} {delta:>+10}{flag}')

# -------------------------------------------------------
# Main
# -------------------------------------------------------
print('=' * 75)
print('  Vacuum Stats Collector')
print('=' * 75)

previous = load_previous_snapshot()
current  = collect_vacuum_stats()

print(f'  Current snapshot:  {current["captured_at"]}')
if previous:
    print(f'  Previous snapshot: {previous.get("captured_at", "unknown")}')
    print()
    compare_snapshots(previous, current)
else:
    print('  No previous snapshot found - this is the baseline run.')
    print()
    print(f'  {"TABLE":<35} {"DEAD TUPLES":>12} {"LIVE TUPLES":>12}')
    print('  ' + '-' * 62)
    for table, stats in sorted(current['postgres'].items()):
        print(f'  {table:<35} {stats["n_dead_tup"]:>12} {stats["n_live_tup"]:>12}')

save_snapshot(current)
print()
print(f'  Snapshot saved to: {SNAPSHOT_FILE}')
print('=' * 75)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 13: Run twice to see deltas

Run it the first time to capture a baseline:

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/vacuum_stats.py
```

Expected output (first run, yours will differ):

```
===========================================================================
  Vacuum Stats Collector
===========================================================================
  Current snapshot:  2026-06-13 09:45:02
  No previous snapshot found - this is the baseline run.

  TABLE                               DEAD TUPLES  LIVE TUPLES
  --------------------------------------------------------------
  public.customers                             12         5300
  public.orders                              4821        91200

  Snapshot saved to: /Users/hafopezi/pgdba/vacuum_stats.json
===========================================================================
```

Now run it a second time to see the delta comparison:

```bash
python3 ~/pgdba/vacuum_stats.py
```

Expected output (second run, yours will differ):

```
===========================================================================
  Vacuum Stats Collector
===========================================================================
  Current snapshot:  2026-06-13 09:47:15
  Previous snapshot: 2026-06-13 09:45:02

  TABLE                               PREV DEAD  CURR DEAD      DELTA
  ----------------------------------------------------------------------
  public.customers                           12         12         +0
  public.orders                            4821       4821         +0

  Snapshot saved to: /Users/hafopezi/pgdba/vacuum_stats.json
===========================================================================
```

In a real environment you would see positive deltas between runs. Schedule this with `cron` or run it before and after a heavy write workload to observe dead tuple accumulation rate.

---

## What you built

You now have `~/pgdba/vacuum_stats.py` - a vacuum trending tool that demonstrates:

| Python concept | DBA analogy |
|---|---|
| `dict = {key: value}` | `hstore` / one row as key-value pairs |
| `d['key']` | Column access in SQL |
| `d.get('key', default)` | `COALESCE(column, default)` |
| `d['key'] = value` | `UPDATE table SET col = value` |
| `.items()` | Iterating columns in a row |
| Nested dicts | JSONB nested objects |
| `json.dumps()` | `to_jsonb()` / `row_to_json()` |
| `json.dump()` to file | `COPY table TO '/path/file.json'` |
| `json.load()` from file | `COPY table FROM '/path/file.json'` |

Next: BUILD 08 - Classes and OOP: PG Monitor

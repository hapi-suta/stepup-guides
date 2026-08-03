# BUILD 15: Generators - Partition Scanner (Partitioning)

**What you will build:** `~/pgdba/partition_scanner.py` - a memory-efficient scanner for large partition sets. Instead of loading stats for all 1000 partitions into a list, it yields one partition at a time. Operators can pipe results to `itertools.islice` (LIMIT) or `itertools.chain` (UNION ALL) without ever holding the full result set in RAM.

**Python concepts covered:** yield, generator functions, generator expressions, next(), itertools (islice, chain), memory efficiency, lazy evaluation

**Time to complete:** ~55 minutes

---

## Prerequisites

- Completed BUILD 13 (`~/pgdba/audit_logger.py` exists)
- Completed BUILD 14 (`~/pgdba/decorators.py` exists)
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)
- PostgreSQL running locally on port 5432

---

## Step 1: The problem - 1000 partitions, too much memory

Imagine a `transactions` table partitioned by month with 1000 partitions. Each partition has a name, row count, dead tuple count, last vacuum time, and size in bytes. If you run one query and load all that into a Python list, you are holding 1000 rows in memory simultaneously.

On a monitoring script that runs every minute across 50 databases, that adds up fast. And if your partition count grows to 10,000, the list blows up proportionally.

On your **Mac terminal**, as your **normal user**, check how many pg_class rows exist locally:

```bash
python3 -c "
import psycopg2, os
conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                        user=os.environ.get('USER'), connect_timeout=3)
cur = conn.cursor()
cur.execute('SELECT count(*) FROM pg_class')
print(f'pg_class rows: {cur.fetchone()[0]}')
conn.close()
"
```

Expected output (yours will differ):

```
pg_class rows: 417
```

On a production system with range partitioning, `pg_class` can have tens of thousands of rows. Loading them all at once is wasteful when you only need to process them one at a time.

---

## Step 2: yield vs return - the key difference

`return` hands back a value and the function is done - it exits, and all local variables are destroyed. The caller gets one thing back.

`yield` is like a cursor that pauses. The function produces one value, hands it to the caller, and then freezes - all local variables stay alive. When the caller asks for the next value, the function resumes exactly where it paused.

Think of it this way:
- `return` = `SELECT * FROM partitions` - loads everything, hands back the full result, query is over
- `yield` = `DECLARE cur CURSOR FOR SELECT * FROM partitions; FETCH NEXT FROM cur;` - fetches one row at a time, the cursor stays open between fetches

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def all_at_once():
    return [1, 2, 3, 4, 5]   # loads everything immediately

def one_at_a_time():
    yield 1   # pauses here, gives 1 to caller
    yield 2   # resumes, pauses here, gives 2
    yield 3
    yield 4
    yield 5   # last one

print('--- return ---')
result = all_at_once()
print(type(result), result)

print('--- yield ---')
gen = one_at_a_time()
print(type(gen), gen)   # it is a generator object, not a list
"
```

Expected output (yours will differ):

```
--- return ---
<class 'list'> [1, 2, 3, 4, 5]
--- yield ---
<class 'generator'> <generator object one_at_a_time at 0x10a3b2c40>
```

The generator is a lazy object - it has produced nothing yet. It is waiting for you to ask for values.

---

## Step 3: Basic generator function with yield

Any function that contains at least one `yield` statement becomes a generator function. When you call it, you get back a generator object, not the function's result. Values only come out when you iterate over it.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def partition_names():
    # Simulating partition names from pg_inherits
    yield 'transactions_2023_01'
    yield 'transactions_2023_02'
    yield 'transactions_2023_03'
    print('  (generator paused here until next iteration)')
    yield 'transactions_2023_04'

gen = partition_names()   # nothing runs yet

print('Starting iteration...')
for name in gen:
    print(f'Processing: {name}')
"
```

Expected output (yours will differ):

```
Starting iteration...
Processing: transactions_2023_01
Processing: transactions_2023_02
Processing: transactions_2023_03
  (generator paused here until next iteration)
Processing: transactions_2023_04
```

The `print('(generator paused here...')`)` demonstrates that code between `yield` statements runs lazily - only when the `for` loop asks for the next value.

---

## Step 4: Iterating over a generator with a for loop

A `for` loop calls `next()` on the generator automatically, one value at a time, until the generator raises `StopIteration` (which happens when the function returns without yielding). You never see `StopIteration` - the `for` loop handles it silently.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def scan_schemas():
    schemas = ['public', 'audit', 'archive', 'staging']
    for schema in schemas:
        yield schema

# for loop: calls next() under the hood each iteration
print('Schemas with partitioned tables:')
for schema in scan_schemas():
    print(f'  checking schema: {schema}')

print('Done - generator exhausted')
"
```

Expected output (yours will differ):

```
Schemas with partitioned tables:
  checking schema: public
  checking schema: audit
  checking schema: archive
  checking schema: staging
Done - generator exhausted
```

---

## Step 5: next() - manually advance the generator

In PostgreSQL, `FETCH NEXT FROM cur` explicitly pulls one row from a cursor. Python's `next()` function does the same - it asks the generator for exactly one value and returns it. This lets you inspect values one at a time without a full loop.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def partition_stats():
    yield {'name': 'orders_2024_01', 'rows': 1_200_000, 'dead_tuples': 5_400}
    yield {'name': 'orders_2024_02', 'rows': 980_000,  'dead_tuples': 200}
    yield {'name': 'orders_2024_03', 'rows': 1_100_000, 'dead_tuples': 88_000}

gen = partition_stats()

# Fetch one at a time - like FETCH NEXT FROM cur
first  = next(gen)
second = next(gen)

print(f'First partition:  {first[\"name\"]}  dead_tuples={first[\"dead_tuples\"]}')
print(f'Second partition: {second[\"name\"]} dead_tuples={second[\"dead_tuples\"]}')

# Call next() when the generator is exhausted raises StopIteration
# Provide a default value as second argument to avoid the error
third  = next(gen)
fourth = next(gen, None)   # returns None instead of raising StopIteration
print(f'Third:  {third[\"name\"]}')
print(f'Fourth: {fourth}')
"
```

Expected output (yours will differ):

```
First partition:  orders_2024_01  dead_tuples=5400
Second partition: orders_2024_02 dead_tuples=200
Third:  orders_2024_03
Fourth: None
```

---

## Step 6: Generator expressions - lazy list comprehensions

List comprehension: `[x*2 for x in items]` - builds the entire list immediately, holds everything in memory.
Generator expression: `(x*2 for x in items)` - same syntax but with `()` instead of `[]`, produces values lazily.

In database terms: a list comprehension is like `SELECT * INTO TEMP TABLE ...` (materializes everything). A generator expression is like keeping a cursor open and fetching one row at a time.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import sys

items = range(1_000_000)   # 1 million items

# List comprehension - builds full list in memory RIGHT NOW
list_result = [x * 2 for x in items]

# Generator expression - builds nothing yet
gen_result = (x * 2 for x in items)

print(f'List size in memory:      {sys.getsizeof(list_result):>12,} bytes')
print(f'Generator size in memory: {sys.getsizeof(gen_result):>12,} bytes')
print()
print(f'List type:      {type(list_result)}')
print(f'Generator type: {type(gen_result)}')
"
```

Expected output (yours will differ):

```
List size in memory:      8,448,728 bytes
Generator size in memory:           200 bytes

List type:      <class 'list'>
Generator type: <class 'generator'>
```

8 MB vs 200 bytes for one million items. The generator wins because it stores only the state needed to compute the next value, not the values themselves.

---

## Step 7: Memory comparison with a real pg_class query

Compare loading all rows from `pg_class` into a list versus streaming them through a generator.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import sys
import psycopg2
import os

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                        user=os.environ.get('USER'), connect_timeout=3)
cur = conn.cursor()
cur.execute(\"SELECT relname, reltuples, relpages FROM pg_class\")

# Approach 1: fetchall() - loads EVERYTHING into memory as a list
all_rows = cur.fetchall()
print(f'fetchall() list size: {sys.getsizeof(all_rows):,} bytes ({len(all_rows)} rows)')

conn.close()

# Approach 2: generator - yields one row at a time
def stream_pg_class():
    conn2 = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                             user=os.environ.get('USER'), connect_timeout=3)
    cur2 = conn2.cursor()
    cur2.execute(\"SELECT relname, reltuples, relpages FROM pg_class\")
    for row in cur2:
        yield row   # one row at a time, cursor stays open
    conn2.close()

gen = stream_pg_class()
print(f'Generator object size:  {sys.getsizeof(gen):,} bytes (all {len(all_rows)} rows available lazily)')
"
```

Expected output (yours will differ):

```
fetchall() list size: 3,672 bytes (417 rows)
Generator object size:  200 bytes (all 417 rows available lazily)
```

On a table with 50,000 rows each returning 10 columns, the difference is dramatic. The generator always stays at ~200 bytes regardless of result set size.

---

## Step 8: Query pg_catalog for real partition info

Before building the scanner, understand the pg_catalog tables involved in partitioning:

- `pg_inherits` - parent-to-child relationships (partitioned table to its partitions)
- `pg_class` - every table/index/sequence, including partition names and metadata
- `pg_stat_user_tables` - live/dead tuple counts, last vacuum/analyze times

On your **Mac terminal**, as your **normal user**, explore partition metadata:

```bash
python3 -c "
import psycopg2, os

conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                        user=os.environ.get('USER'), connect_timeout=3)
cur = conn.cursor()

# Find partitioned tables (relkind='p') and their partition count
cur.execute('''
    SELECT
        parent.relname        AS parent_table,
        count(child.relname)  AS partition_count
    FROM pg_inherits
    JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
    JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
    WHERE parent.relkind = 'p'
    GROUP BY parent.relname
    ORDER BY partition_count DESC
    LIMIT 10
''')
rows = cur.fetchall()
if rows:
    print('Partitioned tables found:')
    for row in rows:
        print(f'  {row[0]}: {row[1]} partitions')
else:
    print('No partitioned tables found in this database.')
    print('The scanner will still work - it will return an empty result set.')

conn.close()
"
```

Expected output (yours will differ):

```
No partitioned tables found in this database.
The scanner will still work - it will return an empty result set.
```

If you have a partitioned table, you will see it listed. The scanner works regardless - it simply yields nothing for databases without partitioning.

---

## Step 9: Build partition_scanner() - yields one partition at a time

This is the core generator. It queries `pg_inherits` + `pg_stat_user_tables` and yields one dict per partition. The caller processes each partition as it arrives - no waiting for the full result set.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import psycopg2, os

def partition_scanner(parent_table: str, dbname: str = 'postgres'):
    '''
    Generator: yield stats for each partition of parent_table, one at a time.

    Each yielded dict contains:
        name, n_live_tup, n_dead_tup, last_vacuum, last_analyze, size_pretty
    '''
    conn = psycopg2.connect(host='localhost', port=5432, dbname=dbname,
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute('''
        SELECT
            child.relname                                           AS partition_name,
            COALESCE(stat.n_live_tup, 0)                           AS live_rows,
            COALESCE(stat.n_dead_tup, 0)                           AS dead_rows,
            stat.last_vacuum,
            stat.last_analyze,
            pg_size_pretty(pg_total_relation_size(child.oid))      AS total_size
        FROM pg_inherits
        JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
        JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
        LEFT JOIN pg_stat_user_tables stat ON stat.relname = child.relname
        WHERE parent.relname = %s
        ORDER BY child.relname
    ''', (parent_table,))

    for row in cur:   # psycopg2 cursor is already lazy - fetches server-side
        yield {
            'name':         row[0],
            'live_rows':    row[1],
            'dead_rows':    row[2],
            'last_vacuum':  str(row[3]) if row[3] else 'never',
            'last_analyze': str(row[4]) if row[4] else 'never',
            'size':         row[5],
        }

    conn.close()

# Test it - use 'orders' or whatever partitioned table you have, or any table name
# (will yield nothing if no partitions exist - that is correct behavior)
count = 0
for partition in partition_scanner('orders'):
    print(f'{partition[\"name\"]}: {partition[\"live_rows\"]:,} rows, size={partition[\"size\"]}')
    count += 1

print(f'Total partitions scanned: {count}')
"
```

Expected output (yours will differ):

```
Total partitions scanned: 0
```

If you have a partitioned table, replace `'orders'` with its name and you will see each partition printed as it is yielded.

---

## Step 10: Build scan_large_tables() - yields tables over a size threshold

A second generator that finds any table (not just partitions) exceeding a row count threshold. Useful for identifying candidates that need partitioning, or for checking which tables are candidates for archival.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import psycopg2, os

def scan_large_tables(min_rows: int = 1_000_000, dbname: str = 'postgres'):
    '''
    Generator: yield tables with n_live_tup >= min_rows, one at a time.

    Analogy: a cursor walking pg_stat_user_tables filtered by row count,
             fetching one row at a time with FETCH NEXT.
    '''
    conn = psycopg2.connect(host='localhost', port=5432, dbname=dbname,
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute('''
        SELECT
            schemaname,
            relname,
            n_live_tup,
            n_dead_tup,
            pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
            last_vacuum,
            last_analyze
        FROM pg_stat_user_tables
        WHERE n_live_tup >= %s
        ORDER BY n_live_tup DESC
    ''', (min_rows,))

    for row in cur:
        yield {
            'schema':       row[0],
            'table':        row[1],
            'live_rows':    row[2],
            'dead_rows':    row[3],
            'size':         row[4],
            'last_vacuum':  str(row[5]) if row[5] else 'never',
            'last_analyze': str(row[6]) if row[6] else 'never',
        }

    conn.close()

# On a fresh local PostgreSQL there may be no user tables over 1M rows
# Lower the threshold to see results
print('Tables with > 0 live rows (threshold lowered for demo):')
count = 0
for tbl in scan_large_tables(min_rows=0):
    bloat_pct = (tbl['dead_rows'] / max(tbl['live_rows'], 1)) * 100
    print(f'  {tbl[\"schema\"]}.{tbl[\"table\"]}: {tbl[\"live_rows\"]:,} rows, '
          f'bloat={bloat_pct:.1f}%, size={tbl[\"size\"]}')
    count += 1

if count == 0:
    print('  (no user tables found - run on a database with data)')
print(f'Total: {count} tables')
"
```

Expected output (yours will differ):

```
Tables with > 0 live rows (threshold lowered for demo):
  public.accounts: 15,842 rows, bloat=2.1%, size=1832 kB
  public.orders: 0 rows, bloat=0.0%, size=8192 bytes
Total: 2 tables
```

---

## Step 11: itertools.islice - take the first N results (LIMIT)

A generator never stops yielding unless you exhaust it or stop iterating. `itertools.islice` wraps a generator and stops it after N items - equivalent to `LIMIT N` in SQL.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import itertools
import psycopg2, os

def all_tables(dbname: str = 'postgres'):
    'Generator: yield every user table name, one at a time.'
    conn = psycopg2.connect(host='localhost', port=5432, dbname=dbname,
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute('SELECT relname FROM pg_class WHERE relkind = %s ORDER BY relname', ('r',))
    for row in cur:
        yield row[0]
    conn.close()

# itertools.islice(generator, N) = LIMIT N
# Only the first 5 rows are ever fetched from the generator
print('First 5 tables (LIMIT 5 via islice):')
for table_name in itertools.islice(all_tables(), 5):
    print(f'  {table_name}')
"
```

Expected output (yours will differ):

```
First 5 tables (LIMIT 5 via islice):
  accounts
  orders
  pg_aggregate
  pg_am
  pg_amop
```

`islice` does not materialize the generator. It asks for one value, yields it, and stops when it has yielded N. The underlying generator is paused after the 5th row - the remaining rows are never fetched.

---

## Step 12: itertools.chain - combine multiple generators (UNION ALL)

`itertools.chain(gen1, gen2)` exhausts `gen1` first, then `gen2`. This is the Python equivalent of `UNION ALL` - combine results from two queries into one stream, without loading either into memory.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import itertools
import psycopg2, os

def tables_in_schema(schema: str, dbname: str = 'postgres'):
    'Generator: yield table names in a specific schema.'
    conn = psycopg2.connect(host='localhost', port=5432, dbname=dbname,
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute('''
        SELECT schemaname || '.' || tablename
        FROM pg_tables
        WHERE schemaname = %s
        ORDER BY tablename
    ''', (schema,))
    for row in cur:
        yield row[0]
    conn.close()

# Chain two generators - like UNION ALL across two schemas
# public + pg_catalog tables, first 8 total
print('Tables in public + pg_catalog (first 8 via chain + islice):')
combined = itertools.chain(
    tables_in_schema('public'),
    tables_in_schema('pg_catalog')
)
for name in itertools.islice(combined, 8):
    print(f'  {name}')
"
```

Expected output (yours will differ):

```
Tables in public + pg_catalog (first 8 via chain + islice):
  public.accounts
  public.orders
  pg_catalog.pg_aggregate
  pg_catalog.pg_am
  pg_catalog.pg_amop
  pg_catalog.pg_amop_fam_strat_index
  pg_catalog.pg_amproc
  pg_catalog.pg_amproc_fam_trdt_index
```

Neither generator loaded its full result set into memory. `chain` consumed `public` first, then seamlessly switched to `pg_catalog`.

---

## Step 13: Combine into partition_scanner.py

Now write the final, clean module combining all the generators.

On your **Mac terminal**, as your **normal user**:

```bash
cat > ~/pgdba/partition_scanner.py << 'PYEOF'
#!/usr/bin/env python3
"""
partition_scanner.py - Memory-efficient PostgreSQL partition and large-table scanner.

Generators:
    partition_scanner(parent_table, dbname)     - yield stats for each partition
    scan_large_tables(min_rows, dbname)          - yield tables exceeding row threshold
    scan_all_partitioned(dbname)                 - yield (parent, partition_count) for all partitioned tables

Utilities:
    top_n_partitions(parent, n, dbname)          - yield first N partitions (uses islice / LIMIT)
    scan_multiple_parents(parents, dbname)       - yield from multiple parent tables (uses chain / UNION ALL)

Analogy:
    Every generator here is a named cursor:
    DECLARE cur CURSOR FOR SELECT ... ; FETCH NEXT FROM cur;
    Values are produced one at a time without materializing the full result set.
"""

import os
import sys
import itertools
from typing import Iterator, Dict, Any

import psycopg2

sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger
from decorators import timed

logger = setup_logger('partition_scanner')

DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'user': os.environ.get('USER'),
    'connect_timeout': 5,
}


def _connect(dbname: str = 'postgres') -> psycopg2.extensions.connection:
    return psycopg2.connect(dbname=dbname, **DB_CONFIG)


def partition_scanner(
    parent_table: str,
    dbname: str = 'postgres'
) -> Iterator[Dict[str, Any]]:
    """
    Generator: yield stats for each partition of parent_table, one at a time.

    Args:
        parent_table: Name of the partitioned table (e.g. 'orders').
        dbname:       Database name. Default 'postgres'.

    Yields:
        dict with keys: name, live_rows, dead_rows, last_vacuum, last_analyze, size
    """
    logger.debug(f'partition_scanner: scanning partitions of {parent_table!r}')
    conn = _connect(dbname)
    cur = conn.cursor()
    cur.execute('''
        SELECT
            child.relname                                           AS partition_name,
            COALESCE(stat.n_live_tup, 0)                           AS live_rows,
            COALESCE(stat.n_dead_tup, 0)                           AS dead_rows,
            stat.last_vacuum,
            stat.last_analyze,
            pg_size_pretty(pg_total_relation_size(child.oid))      AS total_size
        FROM pg_inherits
        JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
        JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
        LEFT JOIN pg_stat_user_tables stat ON stat.relname = child.relname
        WHERE parent.relname = %s
        ORDER BY child.relname
    ''', (parent_table,))

    count = 0
    for row in cur:
        count += 1
        yield {
            'name':         row[0],
            'live_rows':    row[1],
            'dead_rows':    row[2],
            'last_vacuum':  str(row[3]) if row[3] else 'never',
            'last_analyze': str(row[4]) if row[4] else 'never',
            'size':         row[5],
        }

    conn.close()
    logger.debug(f'partition_scanner: yielded {count} partitions for {parent_table!r}')


def scan_large_tables(
    min_rows: int = 1_000_000,
    dbname: str = 'postgres'
) -> Iterator[Dict[str, Any]]:
    """
    Generator: yield tables where n_live_tup >= min_rows.

    Args:
        min_rows: Minimum live row count threshold. Default 1,000,000.
        dbname:   Database name. Default 'postgres'.

    Yields:
        dict with keys: schema, table, live_rows, dead_rows, size, last_vacuum, last_analyze
    """
    logger.debug(f'scan_large_tables: threshold={min_rows:,} rows, db={dbname}')
    conn = _connect(dbname)
    cur = conn.cursor()
    cur.execute('''
        SELECT
            schemaname,
            relname,
            n_live_tup,
            n_dead_tup,
            pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
            last_vacuum,
            last_analyze
        FROM pg_stat_user_tables
        WHERE n_live_tup >= %s
        ORDER BY n_live_tup DESC
    ''', (min_rows,))

    count = 0
    for row in cur:
        count += 1
        yield {
            'schema':       row[0],
            'table':        row[1],
            'live_rows':    row[2],
            'dead_rows':    row[3],
            'size':         row[4],
            'last_vacuum':  str(row[5]) if row[5] else 'never',
            'last_analyze': str(row[6]) if row[6] else 'never',
        }

    conn.close()
    logger.debug(f'scan_large_tables: yielded {count} tables')


def scan_all_partitioned(
    dbname: str = 'postgres'
) -> Iterator[Dict[str, Any]]:
    """
    Generator: yield (parent_table, partition_count) for every partitioned table.

    Yields:
        dict with keys: parent, partition_count
    """
    conn = _connect(dbname)
    cur = conn.cursor()
    cur.execute('''
        SELECT
            parent.relname        AS parent_table,
            count(child.relname)  AS partition_count
        FROM pg_inherits
        JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
        JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
        WHERE parent.relkind = 'p'
        GROUP BY parent.relname
        ORDER BY partition_count DESC
    ''')
    for row in cur:
        yield {'parent': row[0], 'partition_count': row[1]}
    conn.close()


def top_n_partitions(
    parent_table: str,
    n: int = 10,
    dbname: str = 'postgres'
) -> Iterator[Dict[str, Any]]:
    """
    Yield only the first N partitions. Analogy: LIMIT N in SQL.

    Uses itertools.islice - stops the generator after N yields.
    """
    return itertools.islice(partition_scanner(parent_table, dbname), n)


def scan_multiple_parents(
    parents: list,
    dbname: str = 'postgres'
) -> Iterator[Dict[str, Any]]:
    """
    Yield partitions from multiple parent tables in sequence.
    Analogy: UNION ALL across multiple partition sets.

    Uses itertools.chain - exhausts each generator before moving to the next.
    """
    generators = [partition_scanner(p, dbname) for p in parents]
    return itertools.chain(*generators)


@timed
def run_full_scan(dbname: str = 'postgres') -> None:
    """
    Demo: run a full scan showing all generators in action.
    """
    logger.info('=== Partition Scanner Full Demo ===')

    # 1. Show all partitioned tables
    logger.info('--- Partitioned tables in this database ---')
    found_any = False
    for info in scan_all_partitioned(dbname):
        found_any = True
        logger.info(f'  {info["parent"]}: {info["partition_count"]} partitions')
    if not found_any:
        logger.info('  (no partitioned tables found)')

    # 2. Show large tables (threshold = 0 to see all user tables on a fresh install)
    logger.info('--- User tables (all, threshold=0 for demo) ---')
    count = 0
    for tbl in scan_large_tables(min_rows=0, dbname=dbname):
        bloat = (tbl['dead_rows'] / max(tbl['live_rows'], 1)) * 100
        logger.info(
            f'  {tbl["schema"]}.{tbl["table"]}: '
            f'{tbl["live_rows"]:,} rows, bloat={bloat:.1f}%, size={tbl["size"]}'
        )
        count += 1
    if count == 0:
        logger.info('  (no user tables found)')
    logger.info(f'  Total user tables: {count}')

    logger.info('=== Scan complete ===')


if __name__ == '__main__':
    run_full_scan()
PYEOF
echo "partition_scanner.py written to ~/pgdba/"
```

Expected output (yours will differ):

```
partition_scanner.py written to ~/pgdba/
```

---

## Step 14: Run the scanner and see stats yielded one at a time

Run the full demo:

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/partition_scanner.py
```

Expected output (yours will differ):

```
[INFO] partition_scanner: === Partition Scanner Full Demo ===
[INFO] partition_scanner: --- Partitioned tables in this database ---
[INFO] partition_scanner: (no partitioned tables found)
[INFO] partition_scanner: --- User tables (all, threshold=0 for demo) ---
[INFO] partition_scanner: public.accounts: 15,842 rows, bloat=2.1%, size=1832 kB
[INFO] partition_scanner: public.orders: 0 rows, bloat=0.0%, size=8192 bytes
[INFO] partition_scanner: Total user tables: 2
[INFO] decorators: [TIMED] run_full_scan: 0.0142s
[INFO] partition_scanner: === Scan complete ===
```

Now test `top_n_partitions` (LIMIT) and `scan_multiple_parents` (UNION ALL) directly:

```bash
python3 -c "
import sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
from partition_scanner import top_n_partitions, scan_multiple_parents, scan_large_tables
import itertools

# LIMIT: top 3 large tables (using scan_large_tables as a stand-in)
print('=== Top 3 tables by row count (islice / LIMIT) ===')
for tbl in itertools.islice(scan_large_tables(min_rows=0), 3):
    print(f'  {tbl[\"schema\"]}.{tbl[\"table\"]}: {tbl[\"live_rows\"]:,} rows')

# UNION ALL across two schemas using chain (will show nothing if no partitions)
print()
print('=== Multiple parent scan - no output expected if no partitions ===')
count = 0
for p in scan_multiple_parents(['orders', 'transactions']):
    print(f'  partition: {p[\"name\"]}')
    count += 1
print(f'  Total partitions across both parents: {count}')
"
```

Expected output (yours will differ):

```
=== Top 3 tables by row count (islice / LIMIT) ===
  public.accounts: 15,842 rows
  public.orders: 0 rows

=== Multiple parent scan - no output expected if no partitions ===
  Total partitions across both parents: 0
```

---

## What you built

You now have `~/pgdba/partition_scanner.py` with five generators:

- `partition_scanner(parent_table)` - streams partition stats one dict at a time
- `scan_large_tables(min_rows)` - streams tables over a row count threshold
- `scan_all_partitioned()` - streams all partitioned table summaries
- `top_n_partitions(parent, n)` - wraps `partition_scanner` with `islice` (LIMIT)
- `scan_multiple_parents(parents)` - chains multiple `partition_scanner` generators (UNION ALL)

The scanner uses ~200 bytes of memory regardless of how many partitions exist, because it never holds more than one row in Python memory at a time.

---

## What you learned

| Python concept | DBA analogy |
|---|---|
| `yield` (pauses function) | `DECLARE cur CURSOR FOR SELECT ...` |
| Generator object | An open cursor waiting for `FETCH` |
| `for row in generator` | `FETCH ALL FROM cur` (one row per iteration) |
| `next(gen)` | `FETCH NEXT FROM cur` |
| Generator expression `(x for x in items)` | Cursor vs `SELECT INTO temp` |
| `itertools.islice(gen, n)` | `LIMIT n` |
| `itertools.chain(gen1, gen2)` | `UNION ALL` |
| Memory: 200 bytes vs 8 MB | Cursor streaming vs `fetchall()` |
| `for row in psycopg2_cursor` | Server-side cursor row streaming |

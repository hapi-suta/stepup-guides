# BUILD 04: Algorithms Thinking for DBAs

**Module:** 00b - Data Structures
**Prerequisites:** BUILD 01-03 (lists, dicts, sets, comprehensions)
**Time:** 35-45 minutes

As a DBA, you already think algorithmically. When you look at `EXPLAIN ANALYZE` output and see "Seq Scan" vs "Index Scan," you are comparing algorithms. When you add an index to speed up a query, you are choosing a faster algorithm. This guide makes those intuitions explicit in Python.

---

## Step 1: What Is an Algorithm?

An **algorithm** is a step-by-step procedure to solve a problem. Every query PostgreSQL runs follows an algorithm. The query planner **chooses** the best algorithm based on table statistics.

**DBA analogy:** An algorithm is a **query execution plan**. Just like PostgreSQL can choose between a sequential scan, index scan, or bitmap scan to find a row - Python code can use different approaches to find an item in a list.

The question is always the same: **how does the work scale as the data grows?**

---

## Step 2: Linear Search - The Sequential Scan

The simplest search: check every item one by one until you find a match. This is what `x in my_list` does under the hood.

**DBA analogy:** This is a **sequential scan** - reading every row in the table to find matches. Works fine on small tables, painful on large ones.

```bash
python3 -c "
databases = ['postgres', 'template0', 'template1', 'myapp_prod', 'analytics']

# Linear search - check every element
def linear_search(items, target):
    for i, item in enumerate(items):
        if item == target:
            return i  # found - return the index
    return -1  # not found

# Search for 'analytics' (last element - worst case)
result = linear_search(databases, 'analytics')
print(f'Found at index: {result}')

# Search for something that does not exist
result = linear_search(databases, 'mysql')
print(f'Search for mysql: {result}')

# Python's 'in' operator does the same thing
print('analytics' in databases)  # True - but it checked every element up to it
"
```

Expected output (yours will differ):
```
Found at index: 4
Search for mysql: -1
True
```

If the list has 1 million items and your target is at the end, you check 1 million items. If it is at the beginning, you check 1. On average, you check half the list.

---

## Step 3: Binary Search - The Index Lookup

If the data is **sorted**, you can use binary search: check the middle element, then decide whether to look in the left half or right half. Each step cuts the search space in half.

**DBA analogy:** This is a **B-tree index lookup**. PostgreSQL's B-tree index does exactly this - it starts at the root, compares values, and navigates left or right down the tree. On a table with 1 million rows, a B-tree index lookup touches about 20 nodes instead of 1 million rows.

```bash
python3 -c "
def binary_search(sorted_items, target):
    low = 0
    high = len(sorted_items) - 1
    steps = 0

    while low <= high:
        steps += 1
        mid = (low + high) // 2
        if sorted_items[mid] == target:
            return mid, steps
        elif sorted_items[mid] < target:
            low = mid + 1
        else:
            high = mid - 1

    return -1, steps

# Must be sorted first
databases = ['analytics', 'myapp_prod', 'postgres', 'reporting', 'template0', 'template1']

index, steps = binary_search(databases, 'reporting')
print(f'Found \"reporting\" at index {index} in {steps} steps')
print(f'Linear search would check up to {len(databases)} items')

# Bigger example
import random
big_list = sorted(range(1_000_000))
index, steps = binary_search(big_list, 873_291)
print(f'Found 873291 in list of {len(big_list):,} items using {steps} steps')
print(f'Linear search would check up to {len(big_list):,} items')
"
```

Expected output (yours will differ):
```
Found "reporting" at index 3 in 3 steps
Linear search would check up to 6 items
Found 873291 in list of 1,000,000 items using 20 steps
Linear search would check up to 1,000,000 items
```

20 steps vs 1,000,000. That is the power of the right algorithm - and the reason you create indexes.

---

## Step 4: Why Sorting Matters for Searching

Binary search requires sorted data. This is exactly why **indexes speed up queries** - an index keeps data sorted so lookups can use binary search instead of sequential scan.

**DBA analogy:** Creating an index on a column is like pre-sorting your data so all future lookups are fast. The sort itself costs time (like `CREATE INDEX` takes time), but every lookup after that is faster.

```bash
python3 -c "
import time

# Generate a large unsorted list
data = list(range(1_000_000))
import random
random.shuffle(data)

# Linear search (unsorted - no choice but sequential scan)
target = 999_999
start = time.time()
found = target in data  # Python's 'in' does linear search on lists
linear_time = time.time() - start

# Sort it first (like CREATE INDEX)
start = time.time()
data.sort()
sort_time = time.time() - start

# Now use a set for O(1) lookup (like a hash index)
start = time.time()
data_set = set(data)
set_build_time = time.time() - start

start = time.time()
found = target in data_set  # O(1) lookup
set_lookup_time = time.time() - start

print(f'Linear search:    {linear_time:.4f}s')
print(f'Sort (one-time):  {sort_time:.4f}s')
print(f'Set build:        {set_build_time:.4f}s')
print(f'Set lookup:       {set_lookup_time:.6f}s')
"
```

Expected output (yours will differ):
```
Linear search:    0.0156s
Sort (one-time):  0.0892s
Set build:        0.0341s
Set lookup:       0.000001s
```

Key insight: Converting a list to a set is like building a hash index. It takes time upfront, but every lookup after that is nearly instant.

---

## Step 5: Counting Patterns - GROUP BY with Dicts

One of the most common patterns: counting how often each value appears.

**DBA analogy:** This is `SELECT value, COUNT(*) FROM table GROUP BY value`.

```bash
python3 -c "
# Log entries - which operations happen most?
log_entries = [
    'SELECT', 'SELECT', 'INSERT', 'SELECT', 'UPDATE',
    'SELECT', 'DELETE', 'INSERT', 'SELECT', 'UPDATE',
    'SELECT', 'SELECT', 'INSERT', 'UPDATE', 'SELECT',
]

# GROUP BY + COUNT using a dict
counts = {}
for op in log_entries:
    if op in counts:
        counts[op] += 1
    else:
        counts[op] = 1

# Display results (ORDER BY count DESC)
for op, count in sorted(counts.items(), key=lambda x: x[1], reverse=True):
    print(f'{op:<10} {count:>3} times')

print(f'Total:     {sum(counts.values()):>3} entries')
"
```

Expected output (yours will differ):
```
SELECT       8 times
INSERT       3 times
UPDATE       3 times
DELETE       1 times
Total:      15 entries
```

There is a shorter way using `.get()`:

```bash
python3 -c "
log_entries = ['SELECT', 'SELECT', 'INSERT', 'SELECT', 'UPDATE', 'DELETE', 'INSERT']

# Shorter pattern using .get(key, default)
counts = {}
for op in log_entries:
    counts[op] = counts.get(op, 0) + 1

print(counts)
"
```

Expected output (yours will differ):
```
{'SELECT': 3, 'INSERT': 2, 'UPDATE': 1, 'DELETE': 1}
```

`counts.get(op, 0)` returns the current count (or 0 if the key does not exist yet), then adds 1. This eliminates the `if/else` block.

---

## Step 6: Finding Duplicates

**DBA analogy:** Finding duplicates is like `SELECT col, COUNT(*) FROM table GROUP BY col HAVING COUNT(*) > 1`.

```bash
python3 -c "
# Find duplicate database names across servers
all_databases = [
    'myapp_prod', 'analytics', 'postgres',
    'myapp_prod', 'reporting', 'analytics',
    'postgres', 'myapp_staging', 'analytics',
]

# Method 1: Using a dict to count (GROUP BY ... HAVING COUNT > 1)
counts = {}
for db in all_databases:
    counts[db] = counts.get(db, 0) + 1

duplicates = {db: count for db, count in counts.items() if count > 1}
print('Duplicates:', duplicates)

# Method 2: Using a set to detect as you go
seen = set()
dupes = set()
for db in all_databases:
    if db in seen:
        dupes.add(db)
    seen.add(db)
print('Duplicate names:', dupes)
"
```

Expected output (yours will differ):
```
Duplicates: {'myapp_prod': 2, 'analytics': 3, 'postgres': 2}
Duplicate names: {'analytics', 'myapp_prod', 'postgres'}
```

Method 2 is more memory-efficient for very large datasets - you only store unique values, not all counts.

---

## Step 7: String Operations

Strings in Python have built-in methods that map directly to PostgreSQL string functions. You will use these constantly for parsing logs, configs, and query output.

**DBA analogy:**

| Python               | PostgreSQL                        |
| --------------------- | --------------------------------- |
| `s.split(',')`        | `string_to_array(s, ',')`        |
| `','.join(items)`     | `array_to_string(items, ',')`     |
| `s.strip()`           | `trim(s)`                         |
| `s.replace(a, b)`     | `replace(s, a, b)`               |
| `s.startswith('x')`   | `s LIKE 'x%'` or `starts_with()` |
| `s.upper()`           | `upper(s)`                        |
| `s.lower()`           | `lower(s)`                        |

```bash
python3 -c "
# split - break a string into a list
csv_line = 'myapp_prod,1024,50,active'
parts = csv_line.split(',')
print('Split:', parts)
print('DB name:', parts[0])
print('Size:', parts[1])

# join - combine a list into a string (opposite of split)
databases = ['myapp_prod', 'analytics', 'reporting']
result = ', '.join(databases)
print('Joined:', result)

# strip - remove whitespace from both ends
messy = '   pg-primary   '
print(f'Before strip: \"{messy}\"')
print(f'After strip:  \"{messy.strip()}\"')

# replace
connstring = 'host=pg-primary port=5432 dbname=myapp'
updated = connstring.replace('pg-primary', 'pg-replica')
print('Replaced:', updated)

# startswith / endswith
log_line = 'ERROR: connection refused'
print('Is error:', log_line.startswith('ERROR'))
print('Ends with refused:', log_line.endswith('refused'))
"
```

Expected output (yours will differ):
```
Split: ['myapp_prod', '1024', '50', 'active']
DB name: myapp_prod
Size: 1024
Joined: myapp_prod, analytics, reporting
Before strip: "   pg-primary   "
After strip:  "pg-primary"
Replaced: host=pg-replica port=5432 dbname=myapp
Is error: True
Ends with refused: True
```

---

## Step 8: Sorting with Custom Keys

You saw `sorted()` with `key=lambda` in BUILD 03. Here are more practical examples.

**DBA analogy:** `ORDER BY expression` - the key function is the expression.

```bash
python3 -c "
# Sort strings by length (ORDER BY length(name))
databases = ['pg', 'myapp_production', 'analytics', 'db']
by_length = sorted(databases, key=lambda x: len(x))
print('By length:', by_length)

# Sort dicts by a field (ORDER BY size DESC)
servers = [
    {'host': 'pg-primary', 'connections': 150},
    {'host': 'pg-replica', 'connections': 50},
    {'host': 'pg-analytics', 'connections': 300},
]

by_conns = sorted(servers, key=lambda s: s['connections'], reverse=True)
for s in by_conns:
    print(f'  {s[\"host\"]:<15} {s[\"connections\"]:>5} connections')
"
```

Expected output (yours will differ):
```
By length: ['pg', 'db', 'analytics', 'myapp_production']
  pg-analytics      300 connections
  pg-primary        150 connections
  pg-replica         50 connections
```

---

## Step 9: Big O Basics - Why Performance Matters

**Big O notation** describes how an algorithm's work scales as the input grows. As a DBA, you already think about this when you see query plan costs.

| Big O       | Name           | DBA Analogy                       | Example                              |
| ----------- | -------------- | --------------------------------- | ------------------------------------ |
| O(1)        | Constant       | Hash index lookup                 | `dict[key]`, `x in set`             |
| O(log n)    | Logarithmic    | B-tree index lookup               | Binary search                        |
| O(n)        | Linear         | Sequential scan                   | `x in list`, simple loop             |
| O(n log n)  | Linearithmic   | Sort operation                    | `list.sort()`, `sorted()`            |
| O(n^2)      | Quadratic      | Nested loop join                  | Loop inside a loop                   |

```bash
python3 -c "
import time

def time_operation(name, func):
    start = time.time()
    result = func()
    elapsed = time.time() - start
    print(f'{name:<30} {elapsed:.6f}s')
    return result

n = 100_000

# O(1) - dict lookup (hash index)
d = {i: i*2 for i in range(n)}
time_operation('O(1) dict lookup', lambda: d.get(99_999))

# O(1) - set membership (hash index)
s = set(range(n))
time_operation('O(1) set membership', lambda: 99_999 in s)

# O(n) - list search (seq scan)
lst = list(range(n))
time_operation('O(n) list search', lambda: 99_999 in lst)

# O(n log n) - sort
import random
unsorted = list(range(n))
random.shuffle(unsorted)
time_operation('O(n log n) sort', lambda: sorted(unsorted))
"
```

Expected output (yours will differ):
```
O(1) dict lookup               0.000001s
O(1) set membership            0.000001s
O(n) list search               0.001234s
O(n log n) sort                0.012345s
```

The key takeaway: **choosing the right data structure is like choosing the right index.** Using a dict or set for lookups instead of a list is like adding an index to avoid sequential scans.

---

## Step 10: Practical Example - Parsing a Slow Query Log

Let's put everything together. This example parses a mock PostgreSQL slow query log and produces a summary report - just like `pg_stat_statements` but built from scratch.

```bash
python3 -c "
# Mock slow query log entries
log_lines = [
    'duration: 1523.456 ms  statement: SELECT * FROM orders WHERE status = active',
    'duration: 45.123 ms  statement: SELECT id FROM users WHERE email = test@test.com',
    'duration: 8234.567 ms  statement: SELECT * FROM orders WHERE created_at > 2024-01-01',
    'duration: 123.456 ms  statement: INSERT INTO audit_log VALUES (1, login, now())',
    'duration: 2345.678 ms  statement: SELECT * FROM orders WHERE customer_id = 42',
    'duration: 67.890 ms  statement: UPDATE users SET last_login = now() WHERE id = 5',
    'duration: 5678.901 ms  statement: SELECT count(*) FROM orders GROUP BY status',
    'duration: 34.567 ms  statement: SELECT 1',
    'duration: 4567.890 ms  statement: SELECT * FROM orders JOIN customers ON orders.customer_id = customers.id',
    'duration: 89.012 ms  statement: DELETE FROM sessions WHERE expired_at < now()',
]

# Step 1: Parse each line into structured data
queries = []
for line in log_lines:
    # Split on 'statement: ' to get duration and query
    parts = line.split('statement: ')
    duration_str = parts[0].replace('duration: ', '').replace(' ms  ', '')
    duration = float(duration_str)
    statement = parts[1]

    # Determine query type (first word)
    query_type = statement.split()[0]

    # Determine target table (simplified - look for FROM or INTO)
    words = statement.upper().split()
    table = 'unknown'
    for i, word in enumerate(words):
        if word in ('FROM', 'INTO') and i + 1 < len(words):
            table = words[i + 1].lower()
            break

    queries.append({
        'duration': duration,
        'type': query_type,
        'table': table,
        'statement': statement,
    })

# Step 2: Summary by query type (GROUP BY type)
print('=== Query Type Summary ===')
type_stats = {}
for q in queries:
    t = q['type']
    if t not in type_stats:
        type_stats[t] = {'count': 0, 'total_ms': 0.0}
    type_stats[t]['count'] += 1
    type_stats[t]['total_ms'] += q['duration']

print(f'{\"Type\":<10} {\"Count\":>6} {\"Total ms\":>12} {\"Avg ms\":>10}')
print('-' * 40)
for qtype, stats in sorted(type_stats.items(), key=lambda x: x[1]['total_ms'], reverse=True):
    avg = stats['total_ms'] / stats['count']
    print(f'{qtype:<10} {stats[\"count\"]:>6} {stats[\"total_ms\"]:>12.1f} {avg:>10.1f}')

# Step 3: Top 3 slowest queries
print()
print('=== Top 3 Slowest Queries ===')
slowest = sorted(queries, key=lambda q: q['duration'], reverse=True)[:3]
for i, q in enumerate(slowest, 1):
    print(f'{i}. [{q[\"duration\"]:,.1f} ms] {q[\"statement\"][:60]}')

# Step 4: Tables with most slow queries
print()
print('=== Most Queried Tables ===')
table_counts = {}
for q in queries:
    table_counts[q['table']] = table_counts.get(q['table'], 0) + 1
for table, count in sorted(table_counts.items(), key=lambda x: x[1], reverse=True):
    print(f'  {table:<20} {count} queries')
"
```

Expected output (yours will differ):
```
=== Query Type Summary ===
Type        Count     Total ms     Avg ms
----------------------------------------
SELECT          7      22430.2     3204.3
INSERT          1        123.5      123.5
DELETE          1         89.0       89.0
UPDATE          1         67.9       67.9

=== Top 3 Slowest Queries ===
1. [8,234.6 ms] SELECT * FROM orders WHERE created_at > 2024-01-01
2. [5,678.9 ms] SELECT count(*) FROM orders GROUP BY status
3. [4,567.9 ms] SELECT * FROM orders JOIN customers ON orders.customer_id =

=== Most Queried Tables ===
  orders               5 queries
  unknown              2 queries
  users                1 queries
  audit_log            1 queries
  sessions             1 queries
```

This example uses nearly everything from BUILD 01-04: lists, dicts, string operations, sorting, comprehensions, counting patterns, and formatted output.

---

## What You Learned

| Concept                 | Python Approach                         | DBA Analogy                          |
| ----------------------- | --------------------------------------- | ------------------------------------ |
| Linear search           | `for item in list`                     | Sequential scan                      |
| Binary search           | Divide and conquer on sorted data      | B-tree index lookup                  |
| Why sorting helps       | Enables binary search                  | Why indexes speed up queries         |
| Frequency counting      | Dict with `.get(key, 0) + 1`          | `GROUP BY col, COUNT(*)`            |
| Finding duplicates      | Set to track seen items                | `HAVING COUNT(*) > 1`               |
| split()                 | `s.split(',')`                         | `string_to_array()`                 |
| join()                  | `','.join(items)`                      | `array_to_string()`                 |
| strip()                 | `s.strip()`                            | `trim()`                            |
| replace()               | `s.replace(old, new)`                  | `replace()`                         |
| startswith()            | `s.startswith('x')`                    | `LIKE 'x%'`                        |
| Custom sort key         | `sorted(items, key=func)`             | `ORDER BY expression`               |
| O(1) - constant         | Dict/set lookup                        | Hash index                           |
| O(log n) - logarithmic  | Binary search                          | B-tree index                         |
| O(n) - linear           | List scan                              | Sequential scan                      |
| O(n log n)              | Sorting                                | Sort node in query plan              |
| O(n^2) - quadratic      | Nested loops                           | Nested loop join                     |

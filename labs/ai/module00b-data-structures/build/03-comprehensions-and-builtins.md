# BUILD 03: Comprehensions and Built-in Power Tools

**Module:** 00b - Data Structures
**Prerequisites:** BUILD 01 (lists/tuples), BUILD 02 (dicts/sets)
**Time:** 30-40 minutes

In BUILD 01 and 02, you built lists and dicts step by step - create an empty collection, loop, append. Python has a shorthand for this called **comprehensions**. They let you build collections in a single expression. Combined with Python's built-in functions, they give you the power of `SELECT`, `WHERE`, `ORDER BY`, and aggregate functions - all in one line.

---

## Step 1: List Comprehension - The Basics

A **list comprehension** builds a new list from an existing one in a single line. The syntax is:

```
[expression for item in iterable]
```

**DBA analogy:** This is `SELECT expression FROM iterable`.

```bash
python3 -c "
databases = ['myapp_prod', 'analytics', 'reporting', 'myapp_staging']

# Without comprehension (the long way from Module 00a)
upper_dbs = []
for db in databases:
    upper_dbs.append(db.upper())
print('Long way:', upper_dbs)

# With comprehension (the Python way)
upper_dbs = [db.upper() for db in databases]
print('Short way:', upper_dbs)
"
```

Expected output (yours will differ):
```
Long way: ['MYAPP_PROD', 'ANALYTICS', 'REPORTING', 'MYAPP_STAGING']
Short way: ['MYAPP_PROD', 'ANALYTICS', 'REPORTING', 'MYAPP_STAGING']
```

Both produce the same result. The comprehension is shorter, faster, and considered more "Pythonic."

---

## Step 2: List Comprehension with Filter

Add an `if` clause to filter which items make it into the new list.

**DBA analogy:** `[expression for item in iterable if condition]` is `SELECT expression FROM iterable WHERE condition`.

```bash
python3 -c "
databases = ['myapp_prod', 'analytics', 'template0', 'template1', 'myapp_staging']

# SELECT db FROM databases WHERE db NOT LIKE 'template%'
user_dbs = [db for db in databases if not db.startswith('template')]
print('User databases:', user_dbs)

# SELECT db FROM databases WHERE db LIKE '%prod%'
prod_dbs = [db for db in databases if 'prod' in db]
print('Prod databases:', prod_dbs)
"
```

Expected output (yours will differ):
```
User databases: ['myapp_prod', 'analytics', 'myapp_staging']
Prod databases: ['myapp_prod']
```

```bash
python3 -c "
sizes = [50, 1024, 256, 8192, 100, 4096]

# SELECT size FROM sizes WHERE size > 500
large = [s for s in sizes if s > 500]
print('Large (>500 MB):', large)

# SELECT size * 1024 FROM sizes WHERE size > 500 (transform + filter)
large_kb = [s * 1024 for s in sizes if s > 500]
print('Large in KB:', large_kb)
"
```

Expected output (yours will differ):
```
Large (>500 MB): [1024, 8192, 4096]
Large in KB: [1048576, 8388608, 4194304]
```

---

## Step 3: List Comprehension with Transform

The `expression` part can be any valid Python expression - math, string formatting, function calls, conditionals.

**DBA analogy:** This is like `SELECT expression(col) FROM table` - applying a function or formula to every row.

```bash
python3 -c "
sizes_mb = [50, 1024, 256, 8192, 4096]

# SELECT size_mb / 1024.0 AS size_gb FROM ...
sizes_gb = [s / 1024 for s in sizes_mb]
print('In GB:', sizes_gb)

# SELECT CASE WHEN size > 1000 THEN 'large' ELSE 'small' END FROM ...
labels = ['large' if s > 1000 else 'small' for s in sizes_mb]
print('Labels:', labels)

# Combine transform and filter
# SELECT size || ' GB' FROM sizes WHERE size > 1000
big_formatted = [f'{s/1024:.1f} GB' for s in sizes_mb if s > 1000]
print('Big formatted:', big_formatted)
"
```

Expected output (yours will differ):
```
In GB: [0.048828125, 1.0, 0.25, 8.0, 4.0]
Labels: ['small', 'large', 'small', 'large', 'large']
Big formatted: ['1.0 GB', '8.0 GB', '4.0 GB']
```

The `'large' if s > 1000 else 'small'` syntax is called a **conditional expression** (or ternary operator). It is like a SQL `CASE WHEN` in a single line.

---

## Step 4: Dict Comprehension

Same idea as list comprehension but produces a dictionary.

**DBA analogy:** `{key_expr: val_expr for item in iterable}` is like `SELECT key_col, value_col FROM table` but stored as a lookup table.

```bash
python3 -c "
databases = ['myapp_prod', 'analytics', 'reporting']
sizes = [1024, 8192, 256]

# Build a lookup dict: db name -> size
db_sizes = {db: size for db, size in zip(databases, sizes)}
print(db_sizes)
print('analytics size:', db_sizes['analytics'])
"
```

Expected output (yours will differ):
```
{'myapp_prod': 1024, 'analytics': 8192, 'reporting': 256}
analytics size: 8192
```

```bash
python3 -c "
# Transform values: convert MB to GB
sizes = {'myapp_prod': 1024, 'analytics': 8192, 'reporting': 256}
sizes_gb = {db: mb / 1024 for db, mb in sizes.items()}
print(sizes_gb)

# Filter: only databases over 500 MB
big_dbs = {db: mb for db, mb in sizes.items() if mb > 500}
print('Big dbs:', big_dbs)
"
```

Expected output (yours will differ):
```
{'myapp_prod': 1.0, 'analytics': 8.0, 'reporting': 0.25}
Big dbs: {'myapp_prod': 1024, 'analytics': 8192}
```

---

## Step 5: Set Comprehension

Produces a set - useful for extracting unique values from a collection.

**DBA analogy:** `{expr for item in iterable}` is like `SELECT DISTINCT expr FROM iterable`.

```bash
python3 -c "
# List of (database, server) tuples
assignments = [
    ('myapp', 'pg-primary'),
    ('analytics', 'pg-primary'),
    ('myapp', 'pg-replica'),
    ('reporting', 'pg-analytics'),
    ('analytics', 'pg-replica'),
]

# SELECT DISTINCT server FROM assignments
unique_servers = {server for db, server in assignments}
print('Unique servers:', unique_servers)

# SELECT DISTINCT database FROM assignments
unique_dbs = {db for db, server in assignments}
print('Unique databases:', unique_dbs)
"
```

Expected output (yours will differ):
```
Unique servers: {'pg-analytics', 'pg-primary', 'pg-replica'}
Unique databases: {'analytics', 'myapp', 'reporting'}
```

---

## Step 6: enumerate() - Loop with Row Numbers

`enumerate()` gives you both the **index** and the **value** during a loop. In BUILD 01, we used `range(len(...))` for this - `enumerate()` is cleaner.

**DBA analogy:** This is like `ROW_NUMBER() OVER ()` - adding a sequential number to each row.

```bash
python3 -c "
databases = ['postgres', 'myapp_prod', 'analytics', 'reporting']

# Without enumerate (ugly)
for i in range(len(databases)):
    print(f'{i}: {databases[i]}')

print()

# With enumerate (clean)
for i, db in enumerate(databases):
    print(f'{i}: {db}')

print()

# Start numbering from 1 instead of 0
for num, db in enumerate(databases, start=1):
    print(f'{num}. {db}')
"
```

Expected output (yours will differ):
```
0: postgres
1: myapp_prod
2: analytics
3: reporting

0: postgres
1: myapp_prod
2: analytics
3: reporting

1. postgres
2. myapp_prod
3. analytics
4. reporting
```

---

## Step 7: zip() - Pairing Up Lists

`zip()` takes two (or more) lists and pairs their elements by position. It stops at the shortest list.

**DBA analogy:** Like joining two arrays by position, or like a `LATERAL` join on array indices.

```bash
python3 -c "
servers = ['pg-primary', 'pg-replica', 'pg-analytics']
ips = ['10.0.1.50', '10.0.1.51', '10.0.2.10']
ports = [5432, 5432, 5433]

# Pair them up
for server, ip, port in zip(servers, ips, ports):
    print(f'{server:<15} {ip:<15} :{port}')
"
```

Expected output (yours will differ):
```
pg-primary      10.0.1.50       :5432
pg-replica      10.0.1.51       :5432
pg-analytics    10.0.2.10       :5433
```

You already saw `dict(zip(keys, values))` in BUILD 02 - that is the most common use of `zip()`.

---

## Step 8: map() and filter()

`map()` applies a function to every element. `filter()` keeps only elements where a function returns True.

**DBA analogy:**
- `map(func, items)` is like applying a function to every row - `SELECT func(col) FROM table`
- `filter(func, items)` is like a WHERE clause - `SELECT * FROM table WHERE func(col)`

```bash
python3 -c "
sizes_str = ['1024', '256', '8192', '50', '4096']

# map - apply int() to every element (convert strings to integers)
sizes_int = list(map(int, sizes_str))
print('As integers:', sizes_int)

# filter - keep only sizes over 500
big = list(filter(lambda s: s > 500, sizes_int))
print('Over 500:', big)
"
```

Expected output (yours will differ):
```
As integers: [1024, 256, 8192, 50, 4096]
Over 500: [1024, 8192, 4096]
```

Note: `map()` and `filter()` return iterators, not lists. Wrap them in `list()` to see the results. In practice, most Python developers prefer comprehensions over `map()` and `filter()` - they are easier to read. But you will see both in real code.

---

## Step 9: sorted() with key Parameter

`sorted()` returns a new sorted list without modifying the original. The `key` parameter tells it **what to sort by**.

**DBA analogy:** `sorted(items, key=func)` is like `ORDER BY expression`. The `key` function defines the expression.

```bash
python3 -c "
databases = [
    ('myapp_prod', 1024),
    ('analytics', 8192),
    ('reporting', 256),
    ('staging', 50),
]

# Sort by name (first element) - default
by_name = sorted(databases)
print('By name:', by_name)

# Sort by size (second element) - need a key function
by_size = sorted(databases, key=lambda row: row[1])
print('By size ASC:', by_size)

# Sort by size descending
by_size_desc = sorted(databases, key=lambda row: row[1], reverse=True)
print('By size DESC:', by_size_desc)
"
```

Expected output (yours will differ):
```
By name: [('analytics', 8192), ('myapp_prod', 1024), ('reporting', 256), ('staging', 50)]
By size ASC: [('staging', 50), ('reporting', 256), ('myapp_prod', 1024), ('analytics', 8192)]
By size DESC: [('analytics', 8192), ('myapp_prod', 1024), ('reporting', 256), ('staging', 50)]
```

---

## Step 10: lambda - Tiny Unnamed Functions

A `lambda` is a one-line function without a name. You just saw it in Step 9.

**DBA analogy:** A lambda is like an inline expression in an `ORDER BY` or `WHERE` clause. You do not create a stored function for `ORDER BY upper(name)` - you write the expression inline. Same idea.

```bash
python3 -c "
# A regular function
def double(x):
    return x * 2

# The same thing as a lambda
double_lambda = lambda x: x * 2

print(double(5))
print(double_lambda(5))

# Lambdas are most useful inline - you do not need to name them
sizes = [1024, 256, 8192, 50]
print('Sorted:', sorted(sizes))
print('Sorted by last digit:', sorted(sizes, key=lambda x: x % 10))
"
```

Expected output (yours will differ):
```
10
10
Sorted: [50, 256, 1024, 8192]
Sorted by last digit: [50, 8192, 1024, 256]
```

**Keep lambdas simple.** If your lambda is hard to read, write a regular function instead.

---

## Step 11: any() and all()

`any()` returns True if **at least one** element is True. `all()` returns True if **every** element is True.

**DBA analogy:**
- `any()` is like `bool_or()` or `EXISTS` - is there at least one match?
- `all()` is like `bool_and()` or a check that ALL rows satisfy a condition

```bash
python3 -c "
sizes = [1024, 256, 8192, 50, 4096]

# any - is ANY database over 5000 MB?
print('Any over 5000:', any(s > 5000 for s in sizes))

# all - are ALL databases over 100 MB?
print('All over 100:', all(s > 100 for s in sizes))

# Practical: check if any server is down
statuses = ['up', 'up', 'down', 'up']
has_outage = any(s == 'down' for s in statuses)
print('Has outage:', has_outage)

all_healthy = all(s == 'up' for s in statuses)
print('All healthy:', all_healthy)
"
```

Expected output (yours will differ):
```
Any over 5000: True
All over 100: False
Has outage: True
All healthy: False
```

Note the syntax inside `any()` and `all()`: it is a **generator expression** - like a comprehension but without the brackets. It evaluates lazily (stops as soon as it has an answer).

---

## Step 12: Aggregate Functions - sum(), min(), max()

**DBA analogy:** These are exactly what they sound like - `SUM()`, `MIN()`, `MAX()` aggregate functions.

```bash
python3 -c "
sizes = [1024, 256, 8192, 50, 4096]

print('SUM:', sum(sizes))
print('MIN:', min(sizes))
print('MAX:', max(sizes))
print('COUNT:', len(sizes))
print('AVG:', sum(sizes) / len(sizes))

# min/max with key - like MIN(size) but returning the whole row
databases = [
    ('myapp_prod', 1024),
    ('analytics', 8192),
    ('reporting', 256),
]

smallest = min(databases, key=lambda row: row[1])
largest = max(databases, key=lambda row: row[1])
print(f'Smallest: {smallest[0]} ({smallest[1]} MB)')
print(f'Largest: {largest[0]} ({largest[1]} MB)')
"
```

Expected output (yours will differ):
```
SUM: 13618
MIN: 50
MAX: 8192
COUNT: 5
AVG: 2723.6
Smallest: reporting (256 MB)
Largest: analytics (8192 MB)
```

---

## Step 13: Chaining Operations Together

The real power comes from combining these tools. This is like writing a complex query with SELECT, WHERE, ORDER BY, and aggregate functions.

```bash
python3 -c "
# Raw data: (database, size_mb, environment)
databases = [
    ('myapp_prod', 1024, 'prod'),
    ('analytics', 8192, 'prod'),
    ('reporting', 256, 'prod'),
    ('myapp_staging', 128, 'staging'),
    ('analytics_dev', 64, 'dev'),
    ('myapp_dev', 32, 'dev'),
]

# Query: SELECT name, size_mb FROM databases
#        WHERE environment = 'prod'
#        ORDER BY size_mb DESC
result = sorted(
    [(name, size) for name, size, env in databases if env == 'prod'],
    key=lambda row: row[1],
    reverse=True
)

print('Production databases (largest first):')
for name, size in result:
    print(f'  {name:<20} {size:>6} MB')

total = sum(size for name, size, env in databases if env == 'prod')
print(f'Total prod size: {total} MB')
"
```

Expected output (yours will differ):
```
Production databases (largest first):
  analytics                8192 MB
  myapp_prod               1024 MB
  reporting                 256 MB
Total prod size: 9472 MB
```

---

## What You Learned

| Concept                  | Python Syntax                                    | SQL Analogy                       |
| ------------------------ | ------------------------------------------------ | --------------------------------- |
| List comprehension       | `[x for x in items]`                            | `SELECT x FROM items`             |
| With filter              | `[x for x in items if cond]`                    | `SELECT x FROM items WHERE cond`  |
| With transform           | `[f(x) for x in items]`                         | `SELECT f(x) FROM items`          |
| Dict comprehension       | `{k: v for k, v in items}`                      | `SELECT k, v` as lookup table     |
| Set comprehension        | `{x for x in items}`                            | `SELECT DISTINCT x`               |
| enumerate()              | `for i, x in enumerate(items):`                 | `ROW_NUMBER() OVER ()`            |
| zip()                    | `for a, b in zip(xs, ys):`                      | Join arrays by position           |
| map()                    | `list(map(func, items))`                        | `SELECT func(col) FROM ...`       |
| filter()                 | `list(filter(func, items))`                     | `WHERE func(col)`                 |
| sorted() with key        | `sorted(items, key=lambda x: x[1])`            | `ORDER BY col2`                   |
| lambda                   | `lambda x: x * 2`                               | Inline expression                 |
| any()                    | `any(x > 5 for x in items)`                    | `EXISTS` / `bool_or()`            |
| all()                    | `all(x > 5 for x in items)`                    | `bool_and()` / ALL condition      |
| sum(), min(), max()      | `sum(items)`, `min(items)`, `max(items)`        | `SUM()`, `MIN()`, `MAX()`         |

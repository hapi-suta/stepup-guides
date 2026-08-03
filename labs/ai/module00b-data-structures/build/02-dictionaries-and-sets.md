# BUILD 02: Dictionaries and Sets - Key-Value Pairs and Unique Collections

**Module:** 00b - Data Structures
**Prerequisites:** BUILD 01 (lists and tuples)
**Time:** 30-40 minutes

In BUILD 01, you accessed list elements by **position** (index 0, 1, 2...). But in database work, you rarely think in positions - you think in **names**. You do not say "give me column 3" - you say "give me the `host` column."

That is exactly what a **dictionary** does. And when you need to guarantee uniqueness - like `SELECT DISTINCT` - you use a **set**.

---

## Step 1: Creating a Dictionary

A **dictionary** (dict) stores **key-value pairs**. Every value is accessed by its key, not by position.

**DBA analogy:** A dict is like a **lookup table with a primary key**, or a **hash index**. You give it a key, it returns the value instantly - no scanning.

```bash
python3 -c "
# A dictionary - curly braces, key: value pairs
server = {
    'host': 'pg-primary',
    'ip': '10.0.1.50',
    'port': 5432,
    'is_primary': True
}

print(server)
print(type(server))
"
```

Expected output (yours will differ):
```
{'host': 'pg-primary', 'ip': '10.0.1.50', 'port': 5432, 'is_primary': True}
<class 'dict'>
```

Keys are usually strings but can be any immutable type (strings, numbers, tuples). Values can be anything.

---

## Step 2: Accessing Values - dict[key] vs dict.get()

There are two ways to get a value from a dict.

**DBA analogy:**
- `dict[key]` is like a strict lookup - if the key does not exist, it crashes (like a foreign key violation)
- `dict.get(key, default)` is like `COALESCE(col, default)` - returns a fallback if the key is missing

```bash
python3 -c "
server = {
    'host': 'pg-primary',
    'ip': '10.0.1.50',
    'port': 5432,
}

# Direct access - works when key exists
print(server['host'])
print(server['port'])

# Direct access - crashes when key is missing
try:
    print(server['datacenter'])
except KeyError as e:
    print(f'KeyError: {e}')

# Safe access with .get() - returns None if missing
print(server.get('datacenter'))

# Safe access with a default value - like COALESCE
print(server.get('datacenter', 'us-east-1'))
"
```

Expected output (yours will differ):
```
pg-primary
5432
KeyError: 'datacenter'
None
us-east-1
```

**Rule of thumb:** Use `dict[key]` when the key **must** exist (and a crash is the right behavior). Use `.get()` when the key **might** be missing and you have a sensible default.

---

## Step 3: Adding and Updating Entries

**DBA analogy:** Adding or updating a dict entry is like `INSERT ON CONFLICT DO UPDATE` (UPSERT). If the key does not exist, it gets created. If it does exist, the value gets overwritten.

```bash
python3 -c "
server = {'host': 'pg-primary', 'port': 5432}

# Add a new key (INSERT)
server['ip'] = '10.0.1.50'
print('After add:', server)

# Update an existing key (UPDATE)
server['port'] = 5433
print('After update:', server)

# Update multiple keys at once with .update()
server.update({'port': 5432, 'max_connections': 200, 'ssl': True})
print('After bulk update:', server)
"
```

Expected output (yours will differ):
```
After add: {'host': 'pg-primary', 'port': 5432, 'ip': '10.0.1.50'}
After update: {'host': 'pg-primary', 'port': 5433, 'ip': '10.0.1.50'}
After bulk update: {'host': 'pg-primary', 'port': 5432, 'ip': '10.0.1.50', 'max_connections': 200, 'ssl': True}
```

---

## Step 4: Removing Entries

**DBA analogy:** `del dict[key]` and `.pop(key)` are like `DELETE FROM table WHERE key = 'x'`. The difference is `.pop()` returns the deleted value.

```bash
python3 -c "
server = {'host': 'pg-primary', 'port': 5432, 'ip': '10.0.1.50', 'ssl': True}

# del - remove a key (no return value)
del server['ssl']
print('After del:', server)

# pop - remove and return the value
ip = server.pop('ip')
print(f'Popped ip: {ip}')
print('After pop:', server)

# pop with default - safe removal (does not crash if missing)
result = server.pop('datacenter', 'not found')
print(f'Popped missing key: {result}')
"
```

Expected output (yours will differ):
```
After del: {'host': 'pg-primary', 'port': 5432, 'ip': '10.0.1.50'}
Popped ip: 10.0.1.50
After pop: {'host': 'pg-primary', 'port': 5432}
Popped missing key: not found
```

---

## Step 5: Looping Over Dictionaries

There are three ways to loop over a dict - by keys, by values, or by both.

**DBA analogy:**
- `.keys()` is like `SELECT key_column FROM lookup_table`
- `.values()` is like `SELECT value_column FROM lookup_table`
- `.items()` is like `SELECT key_column, value_column FROM lookup_table`

```bash
python3 -c "
server = {'host': 'pg-primary', 'ip': '10.0.1.50', 'port': 5432}

# Loop over keys
print('--- Keys ---')
for key in server.keys():
    print(key)

# Loop over values
print('--- Values ---')
for value in server.values():
    print(value)

# Loop over both (most common - uses tuple unpacking from BUILD 01)
print('--- Key-Value Pairs ---')
for key, value in server.items():
    print(f'{key:<10} = {value}')
"
```

Expected output (yours will differ):
```
--- Keys ---
host
ip
port
--- Values ---
pg-primary
10.0.1.50
5432
--- Key-Value Pairs ---
host       = pg-primary
ip         = 10.0.1.50
port       = 5432
```

Note: You can also just write `for key in server:` - it loops over keys by default. But `.keys()` is more explicit and readable.

---

## Step 6: Checking if a Key Exists

**DBA analogy:** `key in dict` is like `SELECT EXISTS(SELECT 1 FROM table WHERE key = 'x')`.

```bash
python3 -c "
server = {'host': 'pg-primary', 'port': 5432}

# Check if a key exists
if 'host' in server:
    print('host key exists')

if 'datacenter' not in server:
    print('datacenter key is missing')

# Common pattern: check before access
config_key = 'max_connections'
if config_key in server:
    print(f'{config_key} = {server[config_key]}')
else:
    print(f'{config_key} not configured, using default')
"
```

Expected output (yours will differ):
```
host key exists
datacenter key is missing
max_connections not configured, using default
```

---

## Step 7: Nested Dictionaries

Dicts can contain other dicts as values. This is extremely common - it is how you model structured data.

**DBA analogy:** A nested dict is like a **JSONB column** in PostgreSQL. When you store `{"primary": {"host": "10.0.1.50", "port": 5432}}` in a JSONB column, you access nested values with `->` and `->>`. In Python, you chain square brackets.

```bash
python3 -c "
# Nested dict - like JSONB
cluster = {
    'primary': {
        'host': 'pg-primary',
        'ip': '10.0.1.50',
        'port': 5432,
    },
    'replica': {
        'host': 'pg-replica',
        'ip': '10.0.1.51',
        'port': 5432,
    }
}

# Access nested values (like JSONB -> 'primary' ->> 'host')
print(cluster['primary']['host'])
print(cluster['replica']['ip'])

# Loop over the top-level keys
for role, info in cluster.items():
    print(f'{role}: {info[\"host\"]} ({info[\"ip\"]}:{info[\"port\"]})')
"
```

Expected output (yours will differ):
```
pg-primary
10.0.1.51
primary: pg-primary (10.0.1.50:5432)
replica: pg-replica (10.0.1.51:5432)
```

---

## Step 8: Building a Dict from Two Lists with zip()

The `zip()` function pairs up elements from two lists by position. Combined with `dict()`, it creates a dict from a list of keys and a list of values.

**DBA analogy:** This is like joining two arrays by position - `SELECT unnest(keys) AS key, unnest(values) AS value`.

```bash
python3 -c "
# Two parallel lists
columns = ['datname', 'size_mb', 'connections']
values = ['myapp_prod', 1024, 50]

# zip pairs them up: ('datname', 'myapp_prod'), ('size_mb', 1024), ...
# dict() converts those pairs into a dictionary
row = dict(zip(columns, values))
print(row)
print(row['datname'])
print(row['size_mb'])
"
```

Expected output (yours will differ):
```
{'datname': 'myapp_prod', 'size_mb': 1024, 'connections': 50}
myapp_prod
1024
```

This pattern is very useful when you have column headers and row data as separate lists (like when parsing CSV files or query results).

---

## Step 9: Sets - Unique Collections

A **set** is an unordered collection of **unique** elements. No duplicates allowed. No indexing (because there is no order).

**DBA analogy:** A set is like `SELECT DISTINCT`. If you insert a duplicate, it just gets ignored.

```bash
python3 -c "
# Create a set
active_dbs = {'postgres', 'myapp_prod', 'analytics'}
print(active_dbs)
print(type(active_dbs))

# Duplicates are automatically removed
with_dupes = {'postgres', 'myapp_prod', 'postgres', 'analytics', 'myapp_prod'}
print('Duplicates removed:', with_dupes)

# Create a set from a list (deduplication)
raw_list = ['postgres', 'myapp', 'postgres', 'analytics', 'myapp']
unique = set(raw_list)
print('Unique from list:', unique)
print('Original had', len(raw_list), 'items, unique has', len(unique))
"
```

Expected output (yours will differ):
```
{'analytics', 'myapp_prod', 'postgres'}
<class 'set'>
Duplicates removed: {'analytics', 'myapp_prod', 'postgres'}
Unique from list: {'analytics', 'myapp', 'postgres'}
Original had 5 items, unique has 3
```

**Warning:** An empty set is created with `set()`, not `{}`. Using `{}` creates an empty **dict**.

```bash
python3 -c "
empty_dict = {}
empty_set = set()
print(type(empty_dict))
print(type(empty_set))
"
```

Expected output (yours will differ):
```
<class 'dict'>
<class 'set'>
```

---

## Step 10: Set Operations

Sets support mathematical set operations. These map directly to SQL set operations.

**DBA analogy:**
- `|` (union) = `UNION`
- `&` (intersection) = `INTERSECT`
- `-` (difference) = `EXCEPT`

```bash
python3 -c "
prod_dbs = {'postgres', 'myapp_prod', 'analytics', 'reporting'}
staging_dbs = {'postgres', 'myapp_staging', 'analytics'}

# Union - all databases across both environments (like UNION)
all_dbs = prod_dbs | staging_dbs
print('UNION:', all_dbs)

# Intersection - databases in BOTH environments (like INTERSECT)
shared = prod_dbs & staging_dbs
print('INTERSECT:', shared)

# Difference - databases only in prod (like EXCEPT)
prod_only = prod_dbs - staging_dbs
print('EXCEPT (prod only):', prod_only)

# Difference the other way
staging_only = staging_dbs - prod_dbs
print('EXCEPT (staging only):', staging_only)

# Symmetric difference - in one OR the other, but not both
exclusive = prod_dbs ^ staging_dbs
print('XOR (exclusive):', exclusive)
"
```

Expected output (yours will differ):
```
UNION: {'analytics', 'postgres', 'myapp_prod', 'myapp_staging', 'reporting'}
INTERSECT: {'analytics', 'postgres'}
EXCEPT (prod only): {'myapp_prod', 'reporting'}
EXCEPT (staging only): {'myapp_staging'}
XOR (exclusive): {'myapp_prod', 'myapp_staging', 'reporting'}
```

---

## Step 11: Adding and Removing Set Elements

```bash
python3 -c "
databases = {'postgres', 'myapp_prod'}

# Add an element
databases.add('analytics')
print('After add:', databases)

# Adding a duplicate does nothing (no error)
databases.add('postgres')
print('After duplicate add:', databases)

# Remove an element (raises error if missing)
databases.remove('analytics')
print('After remove:', databases)

# Discard - like remove but no error if missing
databases.discard('nonexistent')
print('After discard:', databases)
"
```

Expected output (yours will differ):
```
After add: {'analytics', 'myapp_prod', 'postgres'}
After duplicate add: {'analytics', 'myapp_prod', 'postgres'}
After remove: {'myapp_prod', 'postgres'}
After discard: {'myapp_prod', 'postgres'}
```

---

## Step 12: When to Use Dict vs List vs Set

| Data Structure | Use When...                                    | DBA Analogy                    |
| -------------- | ---------------------------------------------- | ------------------------------ |
| **List**       | Order matters, duplicates OK, need indexing     | Result set, array column       |
| **Dict**       | Need key-value lookup, named access             | Lookup table, hash index, JSONB |
| **Set**        | Need uniqueness, set operations, membership     | DISTINCT, UNION/INTERSECT      |
| **Tuple**      | Immutable ordered data, dict keys, function returns | Frozen row, composite type  |

A practical rule: if you find yourself writing `for item in my_list: if item['id'] == target_id:` - you probably want a dict keyed by `id` instead. That turns an O(n) scan into an O(1) lookup.

```bash
python3 -c "
# Practical example: inventory by server
inventory = {}

# Add databases to servers
inventory['pg-primary'] = ['myapp_prod', 'analytics', 'reporting']
inventory['pg-replica'] = ['myapp_prod', 'analytics']
inventory['pg-staging'] = ['myapp_staging']

# Quick lookup - how many dbs on pg-primary?
print(f'pg-primary has {len(inventory[\"pg-primary\"])} databases')

# All unique database names across all servers
all_dbs = set()
for server, dbs in inventory.items():
    for db in dbs:
        all_dbs.add(db)
print(f'Unique databases across all servers: {all_dbs}')
print(f'Total unique: {len(all_dbs)}')
"
```

Expected output (yours will differ):
```
pg-primary has 3 databases
Unique databases across all servers: {'analytics', 'myapp_staging', 'myapp_prod', 'reporting'}
Total unique: 4
```

---

## What You Learned

| Concept                  | Python Syntax                        | SQL Analogy                          |
| ------------------------ | ------------------------------------ | ------------------------------------ |
| Create a dict            | `d = {'key': 'val'}`                | Lookup table / hash index            |
| Access value             | `d['key']`                           | Exact match lookup                   |
| Safe access              | `d.get('key', default)`             | `COALESCE(col, default)`            |
| Add/update               | `d['key'] = val`                    | `INSERT ON CONFLICT UPDATE`          |
| Delete                   | `del d['key']` / `d.pop('key')`     | `DELETE FROM WHERE key = x`          |
| Loop keys                | `for k in d.keys():`               | `SELECT key FROM ...`                |
| Loop values              | `for v in d.values():`             | `SELECT value FROM ...`              |
| Loop both                | `for k, v in d.items():`           | `SELECT key, value FROM ...`         |
| Key exists               | `'key' in d`                        | `EXISTS(SELECT 1 WHERE ...)`         |
| Nested dict              | `d['a']['b']`                       | JSONB `-> 'a' ->> 'b'`              |
| Dict from lists          | `dict(zip(keys, vals))`            | Join two arrays by position          |
| Create a set             | `s = {'a', 'b'}`                    | `SELECT DISTINCT`                    |
| Union                    | `s1 \| s2`                          | `UNION`                              |
| Intersection             | `s1 & s2`                           | `INTERSECT`                          |
| Difference               | `s1 - s2`                           | `EXCEPT`                             |

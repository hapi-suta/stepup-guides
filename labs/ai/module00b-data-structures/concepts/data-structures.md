# Concepts Reference: Python Data Structures

**Module:** 00b - Data Structures
**Purpose:** Quick-reference for all data structure concepts from BUILD 01-04

---

## Which Data Structure Should I Use?

| I need to...                                  | Use a...      | Why                                        |
| --------------------------------------------- | ------------- | ------------------------------------------ |
| Store items in order, add/remove freely       | **list**      | Ordered, mutable, allows duplicates        |
| Store a fixed row of data that never changes  | **tuple**     | Ordered, immutable, hashable (dict key)    |
| Look up values by name/key instantly          | **dict**      | O(1) key-value lookup                      |
| Track unique items, check membership fast     | **set**       | O(1) membership, automatic dedup           |
| Count occurrences of each item                | **dict**      | Key = item, value = count                  |
| Find items in two collections (overlap, diff) | **set**       | Built-in union, intersection, difference   |
| Parse structured data (JSON, configs)         | **dict**      | Natural key-value structure                |
| Return multiple values from a function        | **tuple**     | Immutable, supports unpacking              |
| Process items in FIFO order (queue)           | **list**      | `.append()` + `.pop(0)` (or `collections.deque`) |
| Store tabular data (rows and columns)         | **list of dicts** or **list of tuples** | Each row is a dict or tuple |

---

## Python Data Structures vs SQL Equivalents

| Python                                | SQL Equivalent                                |
| ------------------------------------- | --------------------------------------------- |
| `my_list = [a, b, c]`                | Result set from `SELECT`                      |
| `my_list[0]`                          | `OFFSET 0` / first row                        |
| `my_list[-1]`                         | Last row of result set                        |
| `my_list[1:3]`                        | `LIMIT 2 OFFSET 1`                            |
| `my_list.append(x)`                  | `INSERT INTO table VALUES (x)`                |
| `my_list.remove(x)`                  | `DELETE FROM table WHERE val = x LIMIT 1`     |
| `my_list.sort()`                      | `ORDER BY col ASC`                            |
| `len(my_list)`                        | `SELECT COUNT(*)`                              |
| `x in my_list`                        | `WHERE x IN (...)`                             |
| `my_tuple = (a, b, c)`              | Frozen row / composite type                    |
| `a, b = my_tuple`                    | `SELECT col1, col2 INTO var1, var2`            |
| `my_dict = {'k': 'v'}`              | Lookup table with primary key / hash index     |
| `my_dict['key']`                      | Exact-match lookup by primary key              |
| `my_dict.get('key', default)`        | `COALESCE(col, default)`                       |
| `my_dict['key'] = val`              | `INSERT ON CONFLICT DO UPDATE` (UPSERT)        |
| `del my_dict['key']`                | `DELETE FROM table WHERE key = x`              |
| `'key' in my_dict`                  | `EXISTS(SELECT 1 FROM table WHERE key = x)`    |
| `my_dict.items()`                    | `SELECT key, value FROM table`                 |
| `nested_dict['a']['b']`             | JSONB `-> 'a' ->> 'b'`                        |
| `my_set = {a, b, c}`                | `SELECT DISTINCT col`                          |
| `set_a \| set_b`                     | `UNION`                                        |
| `set_a & set_b`                      | `INTERSECT`                                    |
| `set_a - set_b`                      | `EXCEPT`                                       |
| `[x for x in items]`                | `SELECT x FROM items`                          |
| `[x for x in items if cond]`        | `SELECT x FROM items WHERE cond`               |
| `{k: v for k, v in items}`          | `SELECT key, value FROM items` as lookup       |
| `{x for x in items}`                | `SELECT DISTINCT x FROM items`                 |
| `enumerate(items)`                   | `ROW_NUMBER() OVER ()`                         |
| `zip(list_a, list_b)`               | Join two arrays by position                    |
| `sorted(items, key=func)`           | `ORDER BY expression`                          |
| `any(cond for x in items)`          | `bool_or()` / `EXISTS`                         |
| `all(cond for x in items)`          | `bool_and()` / ALL subquery                    |
| `sum(items)`                         | `SUM(col)`                                     |
| `min(items)` / `max(items)`         | `MIN(col)` / `MAX(col)`                        |
| `len(items)`                         | `COUNT(*)`                                     |
| `s.split(',')`                       | `string_to_array(s, ',')`                      |
| `','.join(items)`                    | `array_to_string(items, ',')`                  |
| `s.strip()`                          | `trim(s)`                                      |
| `s.replace(a, b)`                   | `replace(s, a, b)`                             |
| `s.startswith('x')`                 | `starts_with(s, 'x')` / `s LIKE 'x%'`         |

---

## Common Patterns Cheat Sheet

### Counting (GROUP BY + COUNT)

```python
counts = {}
for item in items:
    counts[item] = counts.get(item, 0) + 1
```

### Grouping (GROUP BY with aggregation)

```python
groups = {}
for item in items:
    key = item['category']
    if key not in groups:
        groups[key] = []
    groups[key].append(item)
```

### Filtering (WHERE clause)

```python
# Comprehension style
filtered = [x for x in items if x['status'] == 'active']

# filter() style
filtered = list(filter(lambda x: x['status'] == 'active', items))
```

### Transforming (SELECT expression)

```python
# Comprehension style
transformed = [x['name'].upper() for x in items]

# map() style
transformed = list(map(lambda x: x['name'].upper(), items))
```

### Sorting (ORDER BY)

```python
# Ascending
result = sorted(items, key=lambda x: x['size'])

# Descending
result = sorted(items, key=lambda x: x['size'], reverse=True)
```

### Deduplication (DISTINCT)

```python
unique = list(set(items))  # loses order
unique = list(dict.fromkeys(items))  # preserves order
```

### Finding Duplicates (HAVING COUNT > 1)

```python
seen = set()
dupes = set()
for item in items:
    if item in seen:
        dupes.add(item)
    seen.add(item)
```

### Building a Lookup Dict (Hash Index)

```python
lookup = {item['id']: item for item in items}
# Now: lookup[42] is O(1) instead of scanning the list
```

### Top N (ORDER BY ... LIMIT N)

```python
top_5 = sorted(items, key=lambda x: x['score'], reverse=True)[:5]
```

---

## Big O Reference Table

| Big O      | Name          | Operations on 1M items | DBA Analogy              | Python Example                    |
| ---------- | ------------- | ---------------------- | ------------------------ | --------------------------------- |
| O(1)       | Constant      | 1                      | Hash index lookup        | `dict[key]`, `x in set`          |
| O(log n)   | Logarithmic   | ~20                    | B-tree index lookup      | Binary search on sorted list      |
| O(n)       | Linear        | 1,000,000              | Sequential scan          | `x in list`, simple for loop      |
| O(n log n) | Linearithmic  | ~20,000,000            | Sort node in EXPLAIN     | `sorted()`, `list.sort()`         |
| O(n^2)     | Quadratic     | 1,000,000,000,000      | Nested loop join (no index) | Nested for loops               |

### Rules of Thumb

1. **O(1) beats everything.** If you are doing repeated lookups, convert your list to a dict or set first. This is like adding an index.

2. **O(n) is fine for small data.** Just like PostgreSQL uses sequential scans on small tables, linear operations on lists under ~10,000 items are plenty fast.

3. **O(n^2) is a red flag.** A nested loop over 10,000 items means 100 million operations. If you see a loop inside a loop, ask: can I use a dict/set to avoid the inner loop?

4. **Sorting costs O(n log n) but enables O(log n) searches.** This is exactly why `CREATE INDEX` is worth the upfront cost.

5. **Choose the right data structure first.** The difference between `x in list` (O(n)) and `x in set` (O(1)) is the difference between a sequential scan and a hash index lookup.

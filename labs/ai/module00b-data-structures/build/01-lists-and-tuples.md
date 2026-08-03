# BUILD 01: Lists and Tuples - Ordered Collections

**Module:** 00b - Data Structures
**Prerequisites:** Module 00a (variables, types, loops, functions, file I/O, try/except)
**Time:** 30-40 minutes

In Module 00a you worked with single values - one string, one number, one boolean. But in the real world, you deal with **collections** of data. A query returns multiple rows. A server has multiple databases. A table has multiple columns.

Python gives you several ways to store collections. We start with the two **ordered** ones: **lists** and **tuples**.

---

## Step 1: Creating a List

A **list** is an ordered, mutable collection of items. Think of it like a **result set** from a query - rows in a specific order that you can add to, remove from, or modify.

In SQL terms:
- A list is like the rows returned by `SELECT * FROM pg_database;`
- Each element is one row

```bash
python3 -c "
databases = ['postgres', 'template0', 'template1', 'myapp_prod', 'myapp_staging']
print(databases)
print(type(databases))
"
```

Expected output (yours will differ):
```
['postgres', 'template0', 'template1', 'myapp_prod', 'myapp_staging']
<class 'list'>
```

Lists use square brackets `[]`. Items are separated by commas. A list can hold any type - strings, numbers, even other lists.

```bash
python3 -c "
# Lists can hold mixed types (though usually you keep them uniform)
server_info = ['pg-primary', 5432, True, 99.97]
print(server_info)

# An empty list
empty = []
print(empty)
"
```

Expected output (yours will differ):
```
['pg-primary', 5432, True, 99.97]
[]
```

---

## Step 2: Indexing - Accessing Elements by Position

Every element in a list has a **position number** called an **index**. Python uses **zero-based indexing** - the first element is at index 0, not 1.

**DBA analogy:** This is like `OFFSET 0` in SQL. When you write `SELECT * FROM t LIMIT 1 OFFSET 0`, you get the first row. `OFFSET 1` gets the second row.

```bash
python3 -c "
databases = ['postgres', 'template0', 'template1', 'myapp_prod', 'myapp_staging']

# First element - index 0
print(databases[0])

# Third element - index 2
print(databases[2])

# Last element - index -1 (negative indexing counts from the end)
print(databases[-1])

# Second to last
print(databases[-2])
"
```

Expected output (yours will differ):
```
postgres
template1
myapp_staging
myapp_prod
```

**Key insight:** Negative indices count backward from the end. `-1` is always the last element, `-2` is second to last, and so on. This is extremely useful when you don't know the length of the list.

---

## Step 3: Slicing - Getting a Subset

**Slicing** lets you grab a range of elements from a list. The syntax is `list[start:end]` where `start` is included and `end` is excluded.

**DBA analogy:** Slicing is like `LIMIT` and `OFFSET` combined.
- `databases[1:3]` is like `SELECT * FROM databases LIMIT 2 OFFSET 1`
- `databases[:3]` is like `SELECT * FROM databases LIMIT 3`
- `databases[-2:]` is like getting the last 2 rows

```bash
python3 -c "
databases = ['postgres', 'template0', 'template1', 'myapp_prod', 'myapp_staging']

# Elements from index 1 up to (not including) index 3
print(databases[1:3])

# First 3 elements (start defaults to 0)
print(databases[:3])

# Last 2 elements (end defaults to the end of the list)
print(databases[-2:])

# Everything except the first element
print(databases[1:])
"
```

Expected output (yours will differ):
```
['template0', 'template1']
['postgres', 'template0', 'template1']
['myapp_prod', 'myapp_staging']
['template0', 'template1', 'myapp_prod', 'myapp_staging']
```

The most common slicing mistake: the end index is **excluded**. `[1:3]` gives you indices 1 and 2, not 1, 2, and 3.

---

## Step 4: List Methods - append, insert, remove, pop

Lists are **mutable** - you can change them after creation. Here are the core methods for adding and removing elements.

**DBA analogy:**
- `.append()` is like `INSERT INTO ... VALUES (...)` at the end
- `.insert(pos, val)` is like inserting at a specific position
- `.remove(val)` is like `DELETE FROM ... WHERE name = 'x'` (removes first match)
- `.pop()` is like removing the last row and returning it

```bash
python3 -c "
databases = ['postgres', 'myapp_prod']

# append - add to the end
databases.append('myapp_staging')
print('After append:', databases)

# insert - add at a specific position (index 1)
databases.insert(1, 'template1')
print('After insert:', databases)

# remove - delete by value (first occurrence only)
databases.remove('template1')
print('After remove:', databases)

# pop - remove and return the last element
last = databases.pop()
print('Popped:', last)
print('After pop:', databases)

# pop with index - remove and return element at position
first = databases.pop(0)
print('Popped index 0:', first)
print('After pop(0):', databases)
"
```

Expected output (yours will differ):
```
After append: ['postgres', 'myapp_prod', 'myapp_staging']
After insert: ['postgres', 'template1', 'myapp_prod', 'myapp_staging']
After remove: ['postgres', 'myapp_prod', 'myapp_staging']
Popped: myapp_staging
After pop: ['postgres', 'myapp_prod']
Popped index 0: postgres
After pop(0): ['myapp_prod']
```

---

## Step 5: Sorting and Reversing

**DBA analogy:**
- `.sort()` is like `ORDER BY column ASC`
- `.sort(reverse=True)` is like `ORDER BY column DESC`
- `.reverse()` just flips the current order (not the same as sorting descending)

```bash
python3 -c "
sizes = [1024, 50, 8192, 256, 4096]

# sort modifies the list in place (ascending by default)
sizes.sort()
print('Sorted ASC:', sizes)

# sort descending
sizes.sort(reverse=True)
print('Sorted DESC:', sizes)

# reverse just flips the current order
names = ['charlie', 'alice', 'bob']
names.reverse()
print('Reversed:', names)
"
```

Expected output (yours will differ):
```
Sorted ASC: [50, 256, 1024, 4096, 8192]
Sorted DESC: [8192, 4096, 1024, 256, 50]
Reversed: ['bob', 'alice', 'charlie']
```

**Important:** `.sort()` and `.reverse()` modify the list **in place** and return `None`. They do not return a new list. If you need a new sorted list without modifying the original, use `sorted()` (we will cover this in BUILD 03).

---

## Step 6: len() and Membership Testing with `in`

**DBA analogy:**
- `len(list)` is like `SELECT COUNT(*) FROM table`
- `x in list` is like `WHERE x IN ('a', 'b', 'c')`

```bash
python3 -c "
databases = ['postgres', 'template0', 'template1', 'myapp_prod', 'myapp_staging']

# len - count of elements
print('Database count:', len(databases))

# Check membership with 'in'
print('postgres exists:', 'postgres' in databases)
print('mysql exists:', 'mysql' in databases)

# Use 'not in' to check absence
print('mysql is missing:', 'mysql' not in databases)
"
```

Expected output (yours will differ):
```
Database count: 5
postgres exists: True
mysql exists: False
mysql is missing: True
```

The `in` operator is clean and readable. You will use it constantly.

---

## Step 7: Looping Over Lists

You learned `for` loops in Module 00a. Looping over a list is the most common use.

**DBA analogy:** This is like a **cursor loop** in PL/pgSQL - `FOR rec IN SELECT * FROM table LOOP ... END LOOP`.

```bash
python3 -c "
databases = ['postgres', 'myapp_prod', 'myapp_staging']

# Simple loop
for db in databases:
    print(f'Checking database: {db}')
"
```

Expected output (yours will differ):
```
Checking database: postgres
Checking database: myapp_prod
Checking database: myapp_staging
```

```bash
python3 -c "
# Loop with index using range(len(...))
databases = ['postgres', 'myapp_prod', 'myapp_staging']

for i in range(len(databases)):
    print(f'  [{i}] {databases[i]}')
"
```

Expected output (yours will differ):
```
  [0] postgres
  [1] myapp_prod
  [2] myapp_staging
```

Note: There is a better way to loop with an index using `enumerate()` - we cover that in BUILD 03.

---

## Step 8: Nested Lists

A **nested list** is a list of lists. Each inner list is like a **row** in a result set, with each element being a **column value**.

**DBA analogy:** A nested list is like a multi-column result set.
- `[['myapp', 1024, 50], ['analytics', 8192, 200]]` is like:

```sql
SELECT datname, size_mb, connections FROM pg_stat_database;
```

```bash
python3 -c "
# Each inner list is a row: [name, size_mb, connections]
databases = [
    ['myapp_prod', 1024, 50],
    ['myapp_staging', 256, 10],
    ['analytics', 8192, 200],
]

# Access a specific row
print('First row:', databases[0])

# Access a specific cell (row 2, column 0)
print('Third db name:', databases[2][0])

# Loop over all rows
print()
print(f'{\"Database\":<20} {\"Size MB\":>10} {\"Conns\":>8}')
print('-' * 40)
for row in databases:
    name = row[0]
    size = row[1]
    conns = row[2]
    print(f'{name:<20} {size:>10} {conns:>8}')
"
```

Expected output (yours will differ):
```
First row: ['myapp_prod', 1024, 50]
Third db name: analytics

Database               Size MB    Conns
----------------------------------------
myapp_prod                1024       50
myapp_staging              256       10
analytics                 8192      200
```

---

## Step 9: Tuples - Immutable Ordered Collections

A **tuple** is like a list but **immutable** - once created, you cannot change it. No appending, no removing, no modifying elements.

**DBA analogy:** A tuple is like a **frozen row** or a **composite type** in PostgreSQL. Once a row is returned by a query, that result is fixed. You cannot reach into a result set and change a value in place - you would write an UPDATE instead.

Tuples use parentheses `()` instead of brackets `[]`.

```bash
python3 -c "
# A tuple - like a frozen row
server = ('pg-primary', '10.0.1.50', 5432)
print(server)
print(type(server))

# You can index and slice tuples just like lists
print('Host:', server[0])
print('Port:', server[2])

# But you CANNOT modify them
try:
    server[0] = 'pg-replica'
except TypeError as e:
    print(f'Error: {e}')
"
```

Expected output (yours will differ):
```
('pg-primary', '10.0.1.50', 5432)
<class 'tuple'>
Host: pg-primary
Port: 5432
Error: 'tuple' object does not support item assignment
```

---

## Step 10: Tuple Unpacking

**Tuple unpacking** lets you assign each element of a tuple to a separate variable in one line.

**DBA analogy:** This is like `SELECT host, ip, port INTO v_host, v_ip, v_port FROM servers WHERE id = 1;` in PL/pgSQL.

```bash
python3 -c "
# Tuple unpacking - assign each element to a variable
server = ('pg-primary', '10.0.1.50', 5432)
host, ip, port = server

print(f'Host: {host}')
print(f'IP:   {ip}')
print(f'Port: {port}')
"
```

Expected output (yours will differ):
```
Host: pg-primary
IP:   10.0.1.50
Port: 5432
```

```bash
python3 -c "
# Unpacking works in loops too - very common pattern
servers = [
    ('pg-primary', '10.0.1.50', 5432),
    ('pg-replica', '10.0.1.51', 5432),
    ('pg-analytics', '10.0.2.10', 5433),
]

for host, ip, port in servers:
    print(f'{host:<15} {ip:<15} :{port}')
"
```

Expected output (yours will differ):
```
pg-primary      10.0.1.50       :5432
pg-replica      10.0.1.51       :5432
pg-analytics    10.0.2.10       :5433
```

---

## Step 11: When to Use List vs Tuple

| Use a **list** when...                        | Use a **tuple** when...                         |
| --------------------------------------------- | ----------------------------------------------- |
| You need to add/remove items                  | The data should never change                    |
| The collection grows over time                | You are returning multiple values from a function |
| Order matters AND content changes             | You want to use it as a dict key (lists cannot) |
| Example: list of active connections           | Example: a (host, port) pair                    |

**DBA analogy:**
- **List** = a table you INSERT into and DELETE from
- **Tuple** = a read-only view or a returned row from a function

---

## Step 12: Converting Between Lists and Tuples

Use `list()` to convert a tuple to a list, and `tuple()` to convert a list to a tuple.

```bash
python3 -c "
# Tuple to list - when you need to modify it
frozen_row = ('pg-primary', 5432, True)
mutable_row = list(frozen_row)
mutable_row[2] = False  # now you can modify it
print('As list:', mutable_row)

# List to tuple - when you want to freeze it
servers = ['pg-primary', 'pg-replica']
frozen_servers = tuple(servers)
print('As tuple:', frozen_servers)

# Practical use: freeze a list so it can be used as a dict key
# (we will use this in BUILD 02)
"
```

Expected output (yours will differ):
```
As list: ['pg-primary', 5432, False]
As tuple: ('pg-primary', 'pg-replica')
```

---

## What You Learned

| Concept               | Python Syntax                   | SQL Analogy                              |
| --------------------- | ------------------------------- | ---------------------------------------- |
| Create a list         | `items = [a, b, c]`            | Result set from a query                  |
| Index (first)         | `items[0]`                      | `OFFSET 0`                               |
| Index (last)          | `items[-1]`                     | Last row of a result set                 |
| Slice                 | `items[1:3]`                    | `LIMIT 2 OFFSET 1`                       |
| Append                | `items.append(x)`              | `INSERT INTO` (at end)                   |
| Remove                | `items.remove(x)`              | `DELETE FROM WHERE val = x`              |
| Sort                  | `items.sort()`                  | `ORDER BY col ASC`                       |
| Length                 | `len(items)`                    | `COUNT(*)`                               |
| Membership            | `x in items`                    | `WHERE x IN (...)`                       |
| Loop                  | `for x in items:`              | Cursor loop                              |
| Nested list           | `[[a,b], [c,d]]`              | Multi-column result set                  |
| Tuple                 | `(a, b, c)`                    | Frozen row / composite type              |
| Tuple unpacking       | `a, b = (1, 2)`               | `SELECT INTO var1, var2`                 |
| List to tuple         | `tuple(my_list)`               | Freeze a mutable result                  |
| Tuple to list         | `list(my_tuple)`               | Make a frozen row mutable                |

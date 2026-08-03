# BUILD 02: Control Flow - Making Decisions and Repeating

**Module:** module00a-python-from-scratch
**Time:** 35-45 minutes
**Prerequisites:** BUILD 01 completed

In SQL, you filter rows with WHERE and branch logic with CASE WHEN. Python has its own way of making decisions and repeating work. Every concept here maps to something you already know.

---

## Step 1: Comparison Operators

**SQL analogy:** These are your WHERE clause comparisons. Almost identical syntax.

| Python | SQL | Meaning |
|--------|-----|---------|
| `==` | `=` | Equal to |
| `!=` | `!=` or `<>` | Not equal to |
| `<` | `<` | Less than |
| `>` | `>` | Greater than |
| `<=` | `<=` | Less than or equal |
| `>=` | `>=` | Greater than or equal |

The big gotcha: Python uses `==` for comparison and `=` for assignment. SQL uses `=` for both (context-dependent). This will trip you up at first.

```bash
python3 -c "
connections = 150
max_connections = 200

print(connections == 200)    # False
print(connections != 200)    # True
print(connections < max_connections)   # True
print(connections >= 100)    # True
"
```

Expected output:
```
False
True
True
True
```

Comparisons return `True` or `False` - Python booleans. In SQL, comparisons return `t` or `f`.

---

## Step 2: if / elif / else

**SQL analogy:**
```sql
CASE
    WHEN cpu > 90 THEN 'CRITICAL'
    WHEN cpu > 70 THEN 'WARNING'
    ELSE 'OK'
END
```

Python version:

```bash
python3 -c "
cpu = 85

if cpu > 90:
    print('CRITICAL - CPU overloaded')
elif cpu > 70:
    print('WARNING - CPU elevated')
elif cpu > 50:
    print('INFO - CPU moderate')
else:
    print('OK - CPU normal')
"
```

Expected output:
```
WARNING - CPU elevated
```

Key rules:
- Each condition ends with a colon `:`
- The code block under each condition is **indented** (4 spaces). Indentation IS the structure in Python - there are no BEGIN/END blocks like PL/pgSQL
- `elif` is Python's version of `ELSE WHEN` (short for "else if")
- Only the FIRST matching condition runs (just like CASE WHEN)

Try changing `cpu = 95` or `cpu = 30` and re-run to see different branches fire.

---

## Step 3: Boolean Operators - and, or, not

**SQL analogy:** `AND`, `OR`, `NOT` in your WHERE clause. Python uses lowercase.

| Python | SQL |
|--------|-----|
| `and` | `AND` |
| `or` | `OR` |
| `not` | `NOT` |

```bash
python3 -c "
cpu = 85
memory = 92
connections = 150
max_connections = 200

# AND - both conditions must be true
if cpu > 80 and memory > 80:
    print('Both CPU and memory are high')

# OR - at least one condition must be true
if cpu > 90 or memory > 90:
    print('At least one resource is critical')

# NOT - inverts the condition
is_replica = False
if not is_replica:
    print('This is a primary server')

# Combined - just like a complex WHERE clause
if (connections / max_connections * 100) >= 75 and not is_replica:
    print('Primary server connection pool over 75%')
"
```

Expected output:
```
Both CPU and memory are high
At least one resource is critical
This is a primary server
Primary server connection pool over 75%
```

---

## Step 4: Truthy and Falsy Values

**SQL analogy:** In SQL, `NULL` is neither true nor false - it is unknown. Python has a different system: certain values are "falsy" (treated as False), everything else is "truthy."

Falsy values in Python:
- `False`
- `0` (zero)
- `0.0` (zero float)
- `''` (empty string)
- `None` (Python's NULL)
- `[]` (empty list - you will learn lists in the next module)

```bash
python3 -c "
# Empty string is falsy
db_name = ''
if db_name:
    print(f'Database: {db_name}')
else:
    print('No database name provided')

# Zero is falsy
active_connections = 0
if active_connections:
    print(f'{active_connections} connections active')
else:
    print('No active connections')

# None is falsy - like NULL in SQL
replica_lag = None
if replica_lag:
    print(f'Lag: {replica_lag} seconds')
else:
    print('No lag data available')
"
```

Expected output:
```
No database name provided
No active connections
No lag data available
```

This is powerful for quick checks: `if db_name:` is cleaner than `if db_name != '':`.

---

## Step 5: for Loops with range()

**SQL analogy:** `SELECT generate_series(0, 4);` produces rows 0, 1, 2, 3, 4. Python's `range()` is almost the same, but it stops BEFORE the end number.

```bash
python3 -c "
# range(5) gives 0, 1, 2, 3, 4  (like generate_series(0, 4))
for i in range(5):
    print(f'Iteration {i}')
"
```

Expected output:
```
Iteration 0
Iteration 1
Iteration 2
Iteration 3
Iteration 4
```

`range()` variations:

```bash
python3 -c "
# range(start, stop) - stop is exclusive
print('range(1, 4):')
for i in range(1, 4):
    print(f'  {i}')

# range(start, stop, step) - like generate_series(0, 10, 2)
print('range(0, 11, 2):')
for i in range(0, 11, 2):
    print(f'  {i}')

# Countdown - like generate_series(5, 1, -1)
print('Countdown:')
for i in range(5, 0, -1):
    print(f'  {i}')
"
```

Expected output:
```
range(1, 4):
  1
  2
  3
range(0, 11, 2):
  0
  2
  4
  6
  8
  10
Countdown:
  5
  4
  3
  2
  1
```

---

## Step 6: for Loops Over Lists

**SQL analogy:** A cursor looping over query results. Each iteration gives you the next row.

A list in Python is like a result set. Square brackets `[]` define a list:

```bash
python3 -c "
databases = ['production', 'staging', 'analytics', 'reporting']

for db in databases:
    print(f'Checking database: {db}')
"
```

Expected output:
```
Checking database: production
Checking database: staging
Checking database: analytics
Checking database: reporting
```

You can also loop over a list of numbers:

```bash
python3 -c "
connection_counts = [150, 42, 89, 201, 67]

total = 0
for count in connection_counts:
    total = total + count
    print(f'  Added {count}, running total: {total}')

print(f'Total connections: {total}')
"
```

Expected output:
```
  Added 150, running total: 150
  Added 42, running total: 192
  Added 89, running total: 281
  Added 201, running total: 482
  Added 67, running total: 549
Total connections: 549
```

---

## Step 7: while Loops

**SQL analogy:** `WHILE condition LOOP ... END LOOP;` in PL/pgSQL. Keeps running as long as the condition is true.

```bash
python3 -c "
# Simulate waiting for replica to catch up
lag_seconds = 30

while lag_seconds > 0:
    print(f'Replica lag: {lag_seconds}s - waiting...')
    lag_seconds = lag_seconds - 8  # simulate lag decreasing

print('Replica caught up!')
"
```

Expected output:
```
Replica lag: 30s - waiting...
Replica lag: 22s - waiting...
Replica lag: 14s - waiting...
Replica lag: 6s - waiting...
Replica caught up!
```

Danger: if the condition never becomes False, you get an infinite loop. Always make sure the loop variable changes in a way that eventually exits the loop.

---

## Step 8: break and continue

**SQL analogy:** In PL/pgSQL, `EXIT` leaves a loop early. `CONTINUE` skips to the next iteration. Python uses `break` and `continue`.

```bash
python3 -c "
databases = ['production', 'staging', 'test_old', 'analytics', 'reporting']

# CONTINUE - skip test databases (like CONTINUE in PL/pgSQL)
print('Active databases:')
for db in databases:
    if db.startswith('test'):
        continue  # skip this iteration
    print(f'  {db}')
"
```

Expected output:
```
Active databases:
  production
  staging
  analytics
  reporting
```

```bash
python3 -c "
# BREAK - stop searching once you find what you need (like EXIT in PL/pgSQL)
servers = ['replica1', 'replica2', 'primary', 'replica3']

print('Searching for primary...')
for server in servers:
    print(f'  Checking {server}...')
    if server == 'primary':
        print(f'  Found primary: {server}')
        break  # exit the loop entirely
"
```

Expected output:
```
Searching for primary...
  Checking replica1...
  Checking replica2...
  Checking primary...
  Found primary: primary
```

Notice: `replica3` was never checked because `break` stopped the loop.

---

## Step 9: Nested Loops

**SQL analogy:** A self-join or nested cursors. The inner loop runs completely for each iteration of the outer loop.

```bash
python3 -c "
servers = ['primary', 'replica1', 'replica2']
checks = ['cpu', 'memory', 'disk']

for server in servers:
    print(f'{server}:')
    for check in checks:
        print(f'  Running {check} check...')
    print()  # blank line between servers
"
```

Expected output:
```
primary:
  Running cpu check...
  Running memory check...
  Running disk check...

replica1:
  Running cpu check...
  Running memory check...
  Running disk check...

replica2:
  Running cpu check...
  Running memory check...
  Running disk check...

```

3 servers x 3 checks = 9 lines of output. Just like a cross join.

---

## Step 10: The in Keyword for Membership Testing

**SQL analogy:** `WHERE status IN ('active', 'idle')`. Python's `in` works the same way.

```bash
python3 -c "
critical_dbs = ['production', 'payments', 'auth']

db = 'payments'
if db in critical_dbs:
    print(f'{db} is a critical database - extra monitoring enabled')

db = 'staging'
if db not in critical_dbs:
    print(f'{db} is not critical - standard monitoring')

# Also works for checking substrings in strings
query = 'SELECT * FROM users WHERE id = 1'
if 'SELECT' in query:
    print('This is a SELECT query')
if 'DROP' not in query:
    print('Safe - no DROP statement')
"
```

Expected output:
```
payments is a critical database - extra monitoring enabled
staging is not critical - standard monitoring
This is a SELECT query
Safe - no DROP statement
```

---

## What You Learned

| Concept | Python | SQL Equivalent |
|---------|--------|----------------|
| Equality check | `==` | `=` |
| Not equal | `!=` | `!=` or `<>` |
| Conditional branch | `if/elif/else` | `CASE WHEN/THEN/ELSE/END` |
| Logical AND | `and` | `AND` |
| Logical OR | `or` | `OR` |
| Logical NOT | `not` | `NOT` |
| Python's NULL | `None` | `NULL` |
| Counted loop | `for i in range(n)` | `generate_series()` |
| Loop over items | `for x in list` | Cursor LOOP |
| Conditional loop | `while condition` | `WHILE ... LOOP` |
| Exit loop early | `break` | `EXIT` |
| Skip iteration | `continue` | `CONTINUE` |
| Membership test | `x in list` | `x IN (...)` |

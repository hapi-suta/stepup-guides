# BUILD 03: Functions - Reusable Code Blocks

**Module:** module00a-python-from-scratch
**Time:** 35-45 minutes
**Prerequisites:** BUILD 01-02 completed

You have written hundreds of PostgreSQL functions. Python functions work the same way conceptually - you define them once and call them many times. The syntax is different, but the idea is identical.

---

## Step 1: Why Functions?

**SQL analogy:** `CREATE FUNCTION` - write logic once, call it from anywhere.

Without functions, you repeat yourself:

```sql
-- SQL without a function: copy-paste everywhere
SELECT CASE WHEN cpu > 90 THEN 'CRITICAL' WHEN cpu > 70 THEN 'WARNING' ELSE 'OK' END FROM server1;
SELECT CASE WHEN cpu > 90 THEN 'CRITICAL' WHEN cpu > 70 THEN 'WARNING' ELSE 'OK' END FROM server2;
```

With a function, you write it once:

```sql
CREATE FUNCTION classify_cpu(cpu NUMERIC) RETURNS TEXT AS $$
    SELECT CASE WHEN cpu > 90 THEN 'CRITICAL' WHEN cpu > 70 THEN 'WARNING' ELSE 'OK' END;
$$ LANGUAGE sql;
```

Python functions solve the same problem.

---

## Step 2: def Keyword, Parameters, return

**SQL analogy:** `CREATE FUNCTION classify_cpu(cpu NUMERIC) RETURNS TEXT` becomes `def classify_cpu(cpu):`.

```bash
python3 -c "
def classify_cpu(cpu):
    if cpu > 90:
        return 'CRITICAL'
    elif cpu > 70:
        return 'WARNING'
    else:
        return 'OK'

# Now call it - like SELECT classify_cpu(85)
result = classify_cpu(85)
print(result)
"
```

Expected output:
```
WARNING
```

Breaking it down:
- `def` - keyword that starts a function definition (like `CREATE FUNCTION`)
- `classify_cpu` - the function name
- `(cpu)` - the parameter (no type declaration needed - Python figures it out)
- `:` - ends the function header (like `AS $$` in SQL)
- Indented block - the function body (like the code between `$$` markers)
- `return` - sends a value back to the caller (like `RETURN` in PL/pgSQL)

---

## Step 3: Calling Functions

**SQL analogy:** `SELECT classify_cpu(85);` - you call the function by name with arguments in parentheses. Python is the same.

```bash
python3 -c "
def connection_pct(active, total):
    return (active / total) * 100

# Call with positional arguments
print(connection_pct(150, 200))

# Call with named arguments (like named parameters in SQL functions)
print(connection_pct(active=75, total=100))

# Named arguments can be in any order
print(connection_pct(total=200, active=50))
"
```

Expected output:
```
75.0
75.0
25.0
```

Named arguments are especially useful when a function has many parameters - they make the call self-documenting.

---

## Step 4: Default Parameter Values

**SQL analogy:** `CREATE FUNCTION check_health(threshold INTEGER DEFAULT 80)` - parameters with defaults can be omitted when calling.

```bash
python3 -c "
def check_health(cpu, threshold=80):
    if cpu > threshold:
        return 'UNHEALTHY'
    return 'HEALTHY'

# Use default threshold (80)
print(check_health(75))

# Override the default
print(check_health(75, threshold=70))
"
```

Expected output:
```
HEALTHY
UNHEALTHY
```

Rule: parameters with defaults must come AFTER parameters without defaults. `def f(a=1, b)` is invalid - same rule as SQL.

---

## Step 5: Multiple Return Values

**SQL analogy:** `RETURNS TABLE(name TEXT, value INT)` or using `OUT` parameters. Python can return multiple values as a tuple.

```bash
python3 -c "
def server_stats(connections, max_conn, cpu):
    pct = (connections / max_conn) * 100
    status = 'OK'
    if cpu > 90 or pct > 90:
        status = 'CRITICAL'
    elif cpu > 70 or pct > 70:
        status = 'WARNING'
    return pct, status  # returns two values

# Unpack into two variables
pct, status = server_stats(150, 200, 85)
print(f'Connection usage: {pct}%')
print(f'Status: {status}')
"
```

Expected output:
```
Connection usage: 75.0%
Status: WARNING
```

The `pct, status = server_stats(...)` line unpacks the two return values into two separate variables. In SQL, you would use `SELECT * INTO pct, status FROM server_stats(...)`.

---

## Step 6: Scope - Local vs Global

**SQL analogy:** Variables declared inside a function are local to that function. Session variables (like `SET` variables) are global. Same in Python.

```bash
python3 -c "
server_name = 'pg-primary'  # global variable

def check_server():
    local_status = 'OK'     # local - only exists inside this function
    print(f'Checking {server_name}: {local_status}')  # can READ global
    return local_status

check_server()

# This would cause an error if uncommented:
# print(local_status)  # NameError: local_status is not defined
print(f'Server: {server_name}')  # global still accessible
"
```

Expected output:
```
Checking pg-primary: OK
Server: pg-primary
```

Key rules:
- Functions CAN read global variables
- Functions CANNOT modify global variables without the `global` keyword (avoid this - it is bad practice)
- Variables created inside a function disappear when the function ends
- This is the same as PL/pgSQL function variables vs session-level `SET` variables

---

## Step 7: Docstrings

**SQL analogy:** `COMMENT ON FUNCTION classify_cpu IS 'Classifies CPU usage into severity levels';`

A docstring is a triple-quoted string right after the `def` line. It documents what the function does.

```bash
python3 -c "
def classify_cpu(cpu):
    \"\"\"Classify CPU usage into severity levels.

    Args:
        cpu: CPU usage percentage (0-100)

    Returns:
        String: 'CRITICAL', 'WARNING', or 'OK'
    \"\"\"
    if cpu > 90:
        return 'CRITICAL'
    elif cpu > 70:
        return 'WARNING'
    return 'OK'

# You can access the docstring with help()
help(classify_cpu)
"
```

Expected output (yours will differ):
```
Help on function classify_cpu in module __main__:

classify_cpu(cpu)
    Classify CPU usage into severity levels.

    Args:
        cpu: CPU usage percentage (0-100)

    Returns:
        String: 'CRITICAL', 'WARNING', or 'OK'
```

Docstrings are optional but highly recommended. They are the Python equivalent of inline documentation.

---

## Step 8: Built-in Functions

**SQL analogy:** Python has built-in functions just like SQL has `count()`, `sum()`, `max()`, `min()`, `length()`, `abs()`, `round()`.

| Python | SQL | Description |
|--------|-----|-------------|
| `len(x)` | `length()` / `count(*)` | Length of string or list |
| `max(a, b)` | `GREATEST(a, b)` | Largest value |
| `min(a, b)` | `LEAST(a, b)` | Smallest value |
| `sum(list)` | `SUM(column)` | Sum of all values |
| `sorted(list)` | `ORDER BY` | Returns sorted copy |
| `abs(x)` | `ABS(x)` | Absolute value |
| `round(x, n)` | `ROUND(x, n)` | Round to n decimal places |

```bash
python3 -c "
connections = [150, 42, 89, 201, 67]

print(f'Count: {len(connections)}')
print(f'Max: {max(connections)}')
print(f'Min: {min(connections)}')
print(f'Sum: {sum(connections)}')
print(f'Sorted: {sorted(connections)}')
print(f'Abs of -5: {abs(-5)}')
print(f'Round 3.14159 to 2 decimal places: {round(3.14159, 2)}')

# len() on strings works like length() in SQL
db_name = 'production'
print(f'Length of \"{db_name}\": {len(db_name)}')
"
```

Expected output:
```
Count: 5
Max: 201
Min: 42
Sum: 549
Sorted: [42, 67, 89, 150, 201]
Abs of -5: 5
Round 3.14159 to 2 decimal places: 3.14
Length of "production": 10
```

---

## Step 9: None - Python's NULL

**SQL analogy:** `NULL` in SQL. A value that means "nothing" or "unknown."

```bash
python3 -c "
def find_primary(servers):
    \"\"\"Find the primary server. Returns None if not found.\"\"\"
    for server in servers:
        if server == 'primary':
            return server
    return None  # nothing found - like returning NULL

# Test with primary present
result = find_primary(['replica1', 'primary', 'replica2'])
print(f'Found: {result}')

# Test without primary
result = find_primary(['replica1', 'replica2', 'replica3'])
print(f'Found: {result}')

# Check for None (like IS NULL in SQL)
if result is None:
    print('No primary found - FAILOVER NEEDED')
"
```

Expected output:
```
Found: primary
Found: None
No primary found - FAILOVER NEEDED
```

Key rule: use `is None` and `is not None` to check for None. Do NOT use `== None`. This is like SQL where you use `IS NULL`, not `= NULL`.

---

## Step 10: Functions Calling Other Functions

**SQL analogy:** Nested function calls like `SELECT upper(concat('db_', lower(name))) FROM servers;`

```bash
python3 -c "
def connection_pct(active, total):
    \"\"\"Calculate connection usage percentage.\"\"\"
    return (active / total) * 100

def classify_usage(pct):
    \"\"\"Classify a percentage into a severity level.\"\"\"
    if pct > 90:
        return 'CRITICAL'
    elif pct > 70:
        return 'WARNING'
    return 'OK'

def server_report(name, active, total):
    \"\"\"Generate a full server status report.\"\"\"
    pct = connection_pct(active, total)
    status = classify_usage(pct)
    return f'{name}: {pct:.1f}% connections used - {status}'

# Each function does one job, then we compose them
print(server_report('pg-primary', 185, 200))
print(server_report('pg-replica1', 42, 200))
print(server_report('pg-replica2', 150, 200))
"
```

Expected output:
```
pg-primary: 92.5% connections used - CRITICAL
pg-replica1: 21.0% connections used - OK
pg-replica2: 75.0% connections used - WARNING
```

`:.1f` in the f-string formats the float to 1 decimal place. Think of it like `to_char(pct, '999.9')` in PostgreSQL.

---

## What You Learned

| Concept | Python | SQL Equivalent |
|---------|--------|----------------|
| Define function | `def func_name(params):` | `CREATE FUNCTION func_name(params)` |
| Return value | `return value` | `RETURN value` |
| Default params | `def f(x, y=10):` | `CREATE FUNCTION f(x INT, y INT DEFAULT 10)` |
| Multiple returns | `return a, b` | `RETURNS TABLE` / `OUT` params |
| Local variables | Inside function | `DECLARE` block variables |
| Global variables | Module level | Session `SET` variables |
| Documentation | `"""docstring"""` | `COMMENT ON FUNCTION` |
| No value | `None` | `NULL` |
| Check for None | `is None` / `is not None` | `IS NULL` / `IS NOT NULL` |
| Length | `len(x)` | `length(x)` / `count(*)` |
| Max/Min | `max()` / `min()` | `GREATEST()` / `LEAST()` |
| Sum | `sum(list)` | `SUM(column)` |
| Sort | `sorted(list)` | `ORDER BY` |
| Absolute value | `abs(x)` | `ABS(x)` |
| Round | `round(x, n)` | `ROUND(x, n)` |

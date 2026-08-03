# BUILD 04: Files and Error Handling

**Module:** module00a-python-from-scratch
**Time:** 35-45 minutes
**Prerequisites:** BUILD 01-03 completed

As a DBA, you read and write config files daily - pg_hba.conf, postgresql.conf, recovery.conf. You also handle errors in PL/pgSQL with EXCEPTION blocks. This guide teaches the Python equivalents.

---

## Step 1: Create a Sample File to Work With

Before we read files, we need one. Let's create a sample server config file.

```bash
python3 -c "
# Create a sample config file
with open('/tmp/servers.conf', 'w') as f:
    f.write('# Server Configuration\n')
    f.write('primary_host=10.0.1.10\n')
    f.write('primary_port=5432\n')
    f.write('replica1_host=10.0.1.11\n')
    f.write('replica1_port=5432\n')
    f.write('max_connections=200\n')
    f.write('# End of config\n')

print('File created: /tmp/servers.conf')
"
```

Expected output:
```
File created: /tmp/servers.conf
```

Don't worry about the `with open(...)` syntax yet - we will break it down in the next steps.

---

## Step 2: Reading a File with open()

**SQL analogy:** `COPY table FROM '/path/to/file';` or reading pg_hba.conf. You open the file, read its contents, then close it.

```bash
python3 -c "
# Read the entire file as one big string
with open('/tmp/servers.conf', 'r') as f:
    content = f.read()

print(content)
"
```

Expected output:
```
# Server Configuration
primary_host=10.0.1.10
primary_port=5432
replica1_host=10.0.1.11
replica1_port=5432
max_connections=200
# End of config

```

Breaking it down:
- `open('/tmp/servers.conf', 'r')` - opens the file in read mode (`'r'`)
- `as f` - gives the open file a variable name `f` (like an alias)
- `f.read()` - reads the entire file into a string
- The `with` block auto-closes the file when done (explained in Step 4)

---

## Step 3: Reading Line by Line

**SQL analogy:** Like a cursor loop that processes one row at a time.

```bash
python3 -c "
with open('/tmp/servers.conf', 'r') as f:
    for line in f:
        # strip() removes the trailing newline - like TRIM() in SQL
        line = line.strip()
        print(f'Line: [{line}]')
"
```

Expected output:
```
Line: [# Server Configuration]
Line: [primary_host=10.0.1.10]
Line: [primary_port=5432]
Line: [replica1_host=10.0.1.11]
Line: [replica1_port=5432]
Line: [max_connections=200]
Line: [# End of config]
```

You can also read all lines into a list with `readlines()`:

```bash
python3 -c "
with open('/tmp/servers.conf', 'r') as f:
    lines = f.readlines()

print(f'Total lines: {len(lines)}')
print(f'First line: {lines[0].strip()}')
print(f'Last line: {lines[-1].strip()}')
"
```

Expected output:
```
Total lines: 7
First line: # Server Configuration
Last line: # End of config
```

`lines[0]` is the first element (Python uses zero-based indexing). `lines[-1]` is the last element - negative indexing counts from the end.

---

## Step 4: The with Statement for Auto-Closing

**SQL analogy:** When you open a database connection, you must close it when done. The `with` statement auto-closes the file, even if an error occurs. Think of it as a connection pool that automatically returns connections.

Without `with` (the old way - don't do this):
```python
f = open('/tmp/servers.conf', 'r')
content = f.read()
f.close()  # you must remember to close manually
```

With `with` (the right way):
```python
with open('/tmp/servers.conf', 'r') as f:
    content = f.read()
# file is automatically closed here - even if an error happened
```

Always use `with` for file operations. It is like having a `finally { connection.close() }` built in.

---

## Step 5: Writing a File with open() in Write Mode

**SQL analogy:** `COPY table TO '/path/to/file';` or generating a config file.

```bash
python3 -c "
servers = [
    ('pg-primary', '10.0.1.10', 5432),
    ('pg-replica1', '10.0.1.11', 5432),
    ('pg-replica2', '10.0.1.12', 5433),
]

with open('/tmp/server_report.txt', 'w') as f:
    f.write('Server Inventory Report\n')
    f.write('=' * 40 + '\n')
    for name, ip, port in servers:
        f.write(f'{name:15s} {ip:15s} {port}\n')
    f.write(f'\nTotal servers: {len(servers)}\n')

print('Report written to /tmp/server_report.txt')
"
```

Expected output:
```
Report written to /tmp/server_report.txt
```

Verify the file:

```bash
python3 -c "
with open('/tmp/server_report.txt', 'r') as f:
    print(f.read())
"
```

Expected output:
```
Server Inventory Report
========================================
pg-primary      10.0.1.10       5432
pg-replica1     10.0.1.11       5432
pg-replica2     10.0.1.12       5433

Total servers: 3

```

Warning: `'w'` mode overwrites the file completely. If the file exists, its old contents are destroyed - like `TRUNCATE` then `INSERT`.

---

## Step 6: Appending to Files with 'a' Mode

**SQL analogy:** `INSERT INTO log_table VALUES (...)` - adding rows without removing existing ones.

```bash
python3 -c "
import datetime

with open('/tmp/db_log.txt', 'w') as f:
    f.write('Database Activity Log\n')
    f.write('=' * 40 + '\n')

# Now append entries (like INSERT INTO a log table)
events = ['Backup started', 'Backup completed', 'VACUUM running']
for event in events:
    with open('/tmp/db_log.txt', 'a') as f:
        f.write(f'[LOG] {event}\n')

# Read and display the log
with open('/tmp/db_log.txt', 'r') as f:
    print(f.read())
"
```

Expected output:
```
Database Activity Log
========================================
[LOG] Backup started
[LOG] Backup completed
[LOG] VACUUM running

```

`'a'` mode appends to the end of the file. If the file does not exist, it creates a new one.

---

## Step 7: Reading CSV-Like Data

**SQL analogy:** `COPY table FROM '/tmp/data.csv' WITH (FORMAT csv, HEADER true);`

First, create a sample CSV:

```bash
python3 -c "
with open('/tmp/databases.csv', 'w') as f:
    f.write('name,size_gb,connections,status\n')
    f.write('production,500,150,active\n')
    f.write('staging,50,12,active\n')
    f.write('analytics,200,89,active\n')
    f.write('old_archive,100,0,inactive\n')

print('CSV created: /tmp/databases.csv')
"
```

Expected output:
```
CSV created: /tmp/databases.csv
```

Now parse it:

```bash
python3 -c "
with open('/tmp/databases.csv', 'r') as f:
    header = f.readline().strip()  # read first line (header)
    columns = header.split(',')
    print(f'Columns: {columns}')
    print()

    for line in f:
        line = line.strip()
        if not line:  # skip empty lines
            continue
        fields = line.split(',')
        name = fields[0]
        size_gb = int(fields[1])
        connections = int(fields[2])
        status = fields[3]
        print(f'DB: {name:15s} Size: {size_gb:>4d} GB  Conns: {connections:>4d}  Status: {status}')
"
```

Expected output:
```
Columns: ['name', 'size_gb', 'connections', 'status']

DB: production       Size:  500 GB  Conns:  150  Status: active
DB: staging          Size:   50 GB  Conns:   12  Status: active
DB: analytics        Size:  200 GB  Conns:   89  Status: active
DB: old_archive      Size:  100 GB  Conns:    0  Status: inactive
```

Key methods used:
- `strip()` - removes whitespace/newlines from both ends (like `TRIM()`)
- `split(',')` - splits a string into a list at each comma (like `string_to_array()` in PostgreSQL)
- `readline()` - reads one line at a time

---

## Step 8: try/except Basics

**SQL analogy:**
```sql
BEGIN
    -- risky operation
EXCEPTION WHEN division_by_zero THEN
    RAISE NOTICE 'Cannot divide by zero';
END;
```

Python's equivalent:

```bash
python3 -c "
# Without error handling - this would crash
# result = 10 / 0  # ZeroDivisionError!

# With error handling
try:
    result = 10 / 0
except ZeroDivisionError:
    print('Cannot divide by zero')
    result = 0

print(f'Result: {result}')
"
```

Expected output:
```
Cannot divide by zero
Result: 0
```

The structure:
- `try:` - the code that MIGHT fail (like the main body in PL/pgSQL)
- `except ErrorType:` - what to do if that specific error occurs (like `EXCEPTION WHEN`)
- Code after the try/except block continues normally

---

## Step 9: Common Exceptions

Here are the exceptions you will encounter most often:

```bash
python3 -c "
# FileNotFoundError - file does not exist
try:
    with open('/tmp/nonexistent.conf', 'r') as f:
        content = f.read()
except FileNotFoundError:
    print('ERROR: Config file not found')

# ValueError - wrong type conversion (like invalid CAST in SQL)
try:
    port = int('not_a_number')
except ValueError:
    print('ERROR: Cannot convert to integer')

# TypeError - wrong operation on wrong type
try:
    result = 'hello' + 42
except TypeError:
    print('ERROR: Cannot add string and integer')

# ZeroDivisionError - division by zero
try:
    pct = 100 / 0
except ZeroDivisionError:
    print('ERROR: Division by zero')
"
```

Expected output:
```
ERROR: Config file not found
ERROR: Cannot convert to integer
ERROR: Cannot add string and integer
ERROR: Division by zero
```

You can catch multiple exception types:

```bash
python3 -c "
try:
    value = int('abc')
except (ValueError, TypeError) as e:
    print(f'Conversion error: {e}')
"
```

Expected output:
```
Conversion error: invalid literal for int() with base 10: 'abc'
```

The `as e` captures the error message into variable `e`. This is like `SQLERRM` in PL/pgSQL.

---

## Step 10: try/except/finally

**SQL analogy:** An EXCEPTION block with cleanup code that always runs, whether the operation succeeds or fails.

```bash
python3 -c "
def read_config(filepath):
    \"\"\"Read a config file with full error handling.\"\"\"
    try:
        with open(filepath, 'r') as f:
            lines = f.readlines()
        print(f'Successfully read {len(lines)} lines from {filepath}')
        return lines
    except FileNotFoundError:
        print(f'ERROR: File not found: {filepath}')
        return None
    except PermissionError:
        print(f'ERROR: No permission to read: {filepath}')
        return None
    finally:
        print(f'Finished attempting to read: {filepath}')

# Test with existing file
result = read_config('/tmp/servers.conf')
print()

# Test with missing file
result = read_config('/tmp/does_not_exist.conf')
"
```

Expected output:
```
Successfully read 7 lines from /tmp/servers.conf
Finished attempting to read: /tmp/servers.conf

ERROR: File not found: /tmp/does_not_exist.conf
Finished attempting to read: /tmp/does_not_exist.conf
```

The `finally` block ALWAYS runs - success or failure. Use it for cleanup operations like closing connections or releasing locks.

---

## Step 11: Raising Your Own Exceptions

**SQL analogy:** `RAISE EXCEPTION 'max_connections must be positive';` in PL/pgSQL.

```bash
python3 -c "
def set_max_connections(value):
    \"\"\"Set max connections with validation.\"\"\"
    if not isinstance(value, int):
        raise TypeError(f'Expected integer, got {type(value).__name__}')
    if value < 1:
        raise ValueError(f'max_connections must be positive, got {value}')
    if value > 10000:
        raise ValueError(f'max_connections too high: {value} (max 10000)')
    print(f'max_connections set to {value}')
    return value

# Valid call
set_max_connections(200)

# Invalid calls - caught by try/except
try:
    set_max_connections(-5)
except ValueError as e:
    print(f'Validation error: {e}')

try:
    set_max_connections('two hundred')
except TypeError as e:
    print(f'Type error: {e}')
"
```

Expected output:
```
max_connections set to 200
Validation error: max_connections must be positive, got -5
Type error: Expected integer, got str
```

`raise` throws an exception up to the caller, just like `RAISE EXCEPTION` in PL/pgSQL.

---

## Step 12: Practical Example - Config File Parser

Let's combine everything into a practical tool that reads a config file and handles errors.

```bash
python3 -c "
def parse_config(filepath):
    \"\"\"Parse a key=value config file. Skips comments and blank lines.\"\"\"
    config = {}

    try:
        with open(filepath, 'r') as f:
            line_num = 0
            for line in f:
                line_num = line_num + 1
                line = line.strip()

                # Skip empty lines and comments
                if not line or line.startswith('#'):
                    continue

                # Parse key=value
                if '=' not in line:
                    print(f'WARNING: Line {line_num} has no = sign, skipping: {line}')
                    continue

                key, value = line.split('=', 1)  # split on first = only
                key = key.strip()
                value = value.strip()
                config[key] = value

    except FileNotFoundError:
        print(f'ERROR: Config file not found: {filepath}')
        return None

    return config

# Parse our config file
config = parse_config('/tmp/servers.conf')

if config is not None:
    print(f'Loaded {len(config)} settings:')
    for key, value in config.items():
        print(f'  {key} = {value}')

    # Access specific values
    print()
    print(f'Primary host: {config[\"primary_host\"]}')
    print(f'Max connections: {config[\"max_connections\"]}')

# Try a missing file
print()
parse_config('/tmp/missing.conf')
"
```

Expected output:
```
Loaded 5 settings:
  primary_host = 10.0.1.10
  primary_port = 5432
  replica1_host = 10.0.1.11
  replica1_port = 5432
  max_connections = 200

Primary host: 10.0.1.10
Max connections: 200

ERROR: Config file not found: /tmp/missing.conf
```

New concept: `config = {}` creates a dictionary - Python's version of a key-value store. Think of it as a single-row table where column names are keys. `config['primary_host']` accesses a value by its key, like `SELECT primary_host FROM config`. Dictionaries are covered in depth in the next module.

---

## What You Learned

| Concept | Python | SQL Equivalent |
|---------|--------|----------------|
| Read file | `open(path, 'r')` | `COPY FROM` / reading pg_hba.conf |
| Write file | `open(path, 'w')` | `COPY TO` / writing configs |
| Append file | `open(path, 'a')` | `INSERT INTO log_table` |
| Auto-close | `with open(...) as f:` | Connection pool auto-return |
| Read all | `f.read()` | Read entire file as one string |
| Read lines | `for line in f:` | Cursor loop over rows |
| Split string | `line.split(',')` | `string_to_array(line, ',')` |
| Trim whitespace | `line.strip()` | `TRIM(line)` |
| Error handling | `try/except` | `BEGIN...EXCEPTION WHEN...END` |
| Error message | `as e` | `SQLERRM` |
| Cleanup | `finally:` | Cleanup code after EXCEPTION block |
| Throw error | `raise ValueError(...)` | `RAISE EXCEPTION '...'` |
| File not found | `FileNotFoundError` | Relation does not exist error |
| Bad conversion | `ValueError` | Invalid CAST error |
| Type mismatch | `TypeError` | Operator type mismatch |

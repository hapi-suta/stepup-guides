# USE 01: Python Fundamentals Exercises

**Module:** module00a-python-from-scratch
**Time:** 45-60 minutes
**Prerequisites:** BUILD 01-04 completed

These exercises reinforce everything from BUILD 01-04 using DBA scenarios. Each exercise has starter code with `TODO` comments - fill them in and run the program.

---

## Exercise 1: Variable Calculator

**Scenario:** You are calculating database capacity metrics during a planning meeting. Given raw numbers, compute derived values.

Create the file:

```bash
vi /tmp/ex1_variable_calculator.py
```

Paste this starter code:

```python
# Exercise 1: Variable Calculator
# Calculate database capacity metrics

# Given values (do not change these)
total_disk_gb = 500
used_disk_gb = 375
max_connections = 200
active_connections = 163
total_tables = 847
tables_with_bloat = 122

# TODO 1: Calculate disk usage percentage (used / total * 100)
disk_pct = 0  # replace 0 with your calculation

# TODO 2: Calculate available disk in GB
available_disk_gb = 0  # replace 0

# TODO 3: Calculate connection usage percentage
conn_pct = 0  # replace 0

# TODO 4: Calculate available connections
available_connections = 0  # replace 0

# TODO 5: Calculate bloat percentage (tables with bloat / total tables * 100)
bloat_pct = 0  # replace 0

# Print the report using f-strings
print("Database Capacity Report")
print("=" * 40)
print(f"Disk Usage:       {disk_pct:.1f}%  ({used_disk_gb}/{total_disk_gb} GB)")
print(f"Available Disk:   {available_disk_gb} GB")
print(f"Connection Usage: {conn_pct:.1f}%  ({active_connections}/{max_connections})")
print(f"Available Conns:  {available_connections}")
print(f"Table Bloat:      {bloat_pct:.1f}%  ({tables_with_bloat}/{total_tables} tables)")
```

Run it:

```bash
python3 /tmp/ex1_variable_calculator.py
```

**Expected output:**

```
Database Capacity Report
========================================
Disk Usage:       75.0%  (375/500 GB)
Available Disk:   125 GB
Connection Usage: 81.5%  (163/200)
Available Conns:  37
Table Bloat:      14.4%  (122/847 tables)
```

**Hints:**
- Disk percentage: `used_disk_gb / total_disk_gb * 100`
- Available: total minus used
- `:.1f` formats a float to 1 decimal place

---

## Exercise 2: Server Health Checker

**Scenario:** You need to classify server health based on CPU, memory, and disk metrics. Each metric has its own threshold levels.

Create the file:

```bash
vi /tmp/ex2_health_checker.py
```

Paste this starter code:

```python
# Exercise 2: Server Health Checker
# Classify server health based on multiple metrics

servers = [
    ("pg-primary",  92, 85, 70),   # name, cpu%, memory%, disk%
    ("pg-replica1", 45, 60, 55),
    ("pg-replica2", 78, 91, 40),
    ("pg-analytics", 30, 25, 95),
    ("pg-staging",   15, 20, 30),
]

def classify_metric(value, name):
    """Classify a single metric into CRITICAL, WARNING, or OK.

    Thresholds:
        CRITICAL: above 90
        WARNING:  above 70
        OK:       70 or below
    """
    # TODO 1: Implement the classification logic using if/elif/else
    # Return 'CRITICAL', 'WARNING', or 'OK'
    pass  # remove this line and add your code

def overall_status(cpu_status, mem_status, disk_status):
    """Determine overall server status.

    Rules:
        - If ANY metric is CRITICAL, overall is CRITICAL
        - If ANY metric is WARNING (and none CRITICAL), overall is WARNING
        - Otherwise, overall is OK
    """
    # TODO 2: Implement the overall status logic
    # Hint: check for CRITICAL first using 'in' keyword with a list
    pass  # remove this line and add your code

# TODO 3: Loop through each server and print the health report
print("Server Health Report")
print("=" * 65)
print(f"{'Server':<15} {'CPU':>5} {'MEM':>5} {'DISK':>5}  {'Status':<10}")
print("-" * 65)

for name, cpu, mem, disk in servers:
    # TODO: Get status for each metric using classify_metric()
    # TODO: Get overall status using overall_status()
    # TODO: Print the formatted line
    pass  # remove and add your code
```

Run it:

```bash
python3 /tmp/ex2_health_checker.py
```

**Expected output:**

```
Server Health Report
=================================================================
Server            CPU   MEM  DISK  Status
-----------------------------------------------------------------
pg-primary         92    85    70  CRITICAL
pg-replica1        45    60    55  OK
pg-replica2        78    91    40  CRITICAL
pg-analytics       30    25    95  CRITICAL
pg-staging         15    20    30  OK
```

**Hints:**
- `classify_metric` does not need the `name` parameter for logic, but it is there for debugging
- For `overall_status`, use: `if 'CRITICAL' in [cpu_status, mem_status, disk_status]:`
- The `:<15` format left-aligns in a 15-character field, `:>5` right-aligns in 5

---

## Exercise 3: Connection Counter

**Scenario:** You have a list of database connections. Count how many connections each database has, find the database with the most connections, and calculate the total.

Create the file:

```bash
vi /tmp/ex3_connection_counter.py
```

Paste this starter code:

```python
# Exercise 3: Connection Counter
# Count connections by database

connections = [
    "production", "production", "analytics", "production",
    "staging", "analytics", "production", "reporting",
    "production", "staging", "analytics", "production",
    "reporting", "production", "analytics", "staging",
    "production", "analytics", "production", "reporting",
]

# TODO 1: Count connections per database
# Use a dictionary to track counts
# Hint: loop through connections, for each db name:
#   - if it is already in the dict, add 1
#   - if it is not in the dict, set it to 1
counts = {}

for db in connections:
    # TODO: implement counting logic
    pass  # remove and add your code

# TODO 2: Print the counts sorted by database name
print("Connection Counts by Database")
print("=" * 35)
for db_name in sorted(counts.keys()):
    # TODO: print each database and its count
    pass  # remove and add your code

# TODO 3: Find the database with the most connections
# Hint: use a for loop to track the max
busiest_db = ""
busiest_count = 0

for db_name, count in counts.items():
    # TODO: compare and track the max
    pass  # remove and add your code

print(f"\nTotal connections: {len(connections)}")
print(f"Busiest database: {busiest_db} ({busiest_count} connections)")
```

Run it:

```bash
python3 /tmp/ex3_connection_counter.py
```

**Expected output:**

```
Connection Counts by Database
===================================
analytics       :  5
production      :  9
reporting       :  3
staging         :  3

Total connections: 20
Busiest database: production (9 connections)
```

**Hints:**
- Check membership with `if db in counts:`
- `counts[db] = counts[db] + 1` increments a count
- `counts.keys()` returns all dictionary keys
- `counts.items()` returns key-value pairs for looping

---

## Exercise 4: Query Logger Function

**Scenario:** Write a function that formats query execution information into a standardized log line, then use it to log several queries.

Create the file:

```bash
vi /tmp/ex4_query_logger.py
```

Paste this starter code:

```python
# Exercise 4: Query Logger Function
# Format and log query execution information

def format_log_entry(query, duration_ms, rows_affected, status="success"):
    """Format a query execution into a log line.

    Args:
        query: the SQL query that was executed
        duration_ms: execution time in milliseconds
        rows_affected: number of rows affected
        status: 'success' or 'error' (default: 'success')

    Returns:
        A formatted log string
    """
    # TODO 1: Classify the duration
    # fast: under 100ms
    # moderate: 100ms to 999ms
    # slow: 1000ms and above
    speed = ""  # replace with your classification logic

    # TODO 2: Truncate query to 40 characters if longer
    # Hint: use len() to check, then slice with query[:40] + "..."
    display_query = query  # replace with truncation logic

    # TODO 3: Build and return the formatted log string
    # Format: [STATUS] speed | duration_ms ms | rows_affected rows | display_query
    # Example: [SUCCESS] slow | 2500 ms | 1000000 rows | SELECT * FROM large_table WHERE crea...
    return ""  # replace with your f-string

# Test data - queries to log
queries = [
    ("SELECT count(*) FROM users", 15, 1),
    ("UPDATE accounts SET status = 'active' WHERE last_login > now() - interval '30 days'", 450, 8432),
    ("SELECT * FROM large_table WHERE created_at > '2024-01-01'", 2500, 1000000),
    ("INSERT INTO audit_log VALUES (1, 'login', now())", 3, 1),
    ("DELETE FROM sessions WHERE expired_at < now()", 1200, 45000),
]

# TODO 4: Loop through queries and print each log entry
print("Query Execution Log")
print("=" * 80)
for query, duration, rows in queries:
    # TODO: call format_log_entry and print the result
    pass  # remove and add your code

# TODO 5: Log a failed query using the status parameter
print()
print("Error Log")
print("=" * 80)
# TODO: call format_log_entry with status="error" for this query:
#   query: "DROP TABLE production_users"
#   duration: 0
#   rows: 0
```

Run it:

```bash
python3 /tmp/ex4_query_logger.py
```

**Expected output:**

```
Query Execution Log
================================================================================
[SUCCESS] fast     |   15 ms |       1 rows | SELECT count(*) FROM users
[SUCCESS] moderate |  450 ms |    8432 rows | UPDATE accounts SET status = 'activ...
[SUCCESS] slow     | 2500 ms | 1000000 rows | SELECT * FROM large_table WHERE cr...
[SUCCESS] fast     |    3 ms |       1 rows | INSERT INTO audit_log VALUES (1, 'l...
[SUCCESS] slow     | 1200 ms |   45000 rows | DELETE FROM sessions WHERE expired_...

Error Log
================================================================================
[ERROR]   fast     |    0 ms |       0 rows | DROP TABLE production_users
```

**Hints:**
- Speed classification: `if duration_ms < 100:` for fast
- Truncation: `query[:40] + "..."` if `len(query) > 40`, otherwise just `query`
- Format alignment: `{status.upper():<7}`, `{speed:<8}`, `{duration_ms:>4}`, `{rows_affected:>7}`

---

## Exercise 5: Config File Parser

**Scenario:** Write a program that reads a database config file, validates the values, and reports any errors. This combines file I/O, functions, loops, and error handling.

First, create the config file:

```bash
python3 -c "
with open('/tmp/ex5_db.conf', 'w') as f:
    f.write('# Database Configuration\n')
    f.write('host=10.0.1.10\n')
    f.write('port=5432\n')
    f.write('dbname=production\n')
    f.write('max_connections=200\n')
    f.write('shared_buffers_mb=4096\n')
    f.write('work_mem_mb=64\n')
    f.write('maintenance_work_mem_mb=512\n')
    f.write('\n')
    f.write('# Bad values for testing\n')
    f.write('port_alt=not_a_number\n')
    f.write('timeout=-5\n')
    f.write('bad line without equals\n')
print('Config file created: /tmp/ex5_db.conf')
"
```

Now create the parser:

```bash
vi /tmp/ex5_config_parser.py
```

Paste this starter code:

```python
# Exercise 5: Config File Parser
# Read, parse, validate, and report on a config file

def parse_config(filepath):
    """Parse a key=value config file.

    Returns a dictionary of settings, or None if file not found.
    Skips comments (lines starting with #) and empty lines.
    Prints a warning for lines that cannot be parsed.
    """
    config = {}
    warnings = []
    line_num = 0

    # TODO 1: Open and read the file with error handling
    # Use try/except for FileNotFoundError
    # Loop through each line:
    #   - increment line_num
    #   - strip whitespace
    #   - skip empty lines and comment lines
    #   - if no '=' in line, add a warning message and continue
    #   - split on '=' (only first one), strip key and value
    #   - store in config dict

    # Your code here

    return config, warnings

def validate_numeric(config, key, min_val=0, max_val=None):
    """Validate that a config value is a valid positive number.

    Returns (True, int_value) if valid, (False, error_message) if not.
    """
    # TODO 2: Implement validation
    # Check if key exists in config
    # Try to convert to int (use try/except ValueError)
    # Check if value >= min_val
    # Check if value <= max_val (if max_val is not None)
    # Return (True, int_value) or (False, "error message")

    pass  # remove and add your code

def print_report(config, warnings):
    """Print a formatted config report."""
    # TODO 3: Print all settings
    print("\nParsed Configuration")
    print("=" * 45)

    for key in sorted(config.keys()):
        # TODO: print each key-value pair formatted nicely
        pass  # remove and add your code

    # TODO 4: Print warnings if any
    if warnings:
        print(f"\nWarnings ({len(warnings)}):")
        for w in warnings:
            print(f"  WARNING: {w}")

    # TODO 5: Validate numeric fields
    print("\nValidation Results")
    print("=" * 45)

    checks = [
        ("port", 1, 65535),
        ("max_connections", 1, 10000),
        ("shared_buffers_mb", 1, None),
        ("work_mem_mb", 1, None),
        ("port_alt", 1, 65535),
        ("timeout", 0, None),
    ]

    for key, min_v, max_v in checks:
        valid, result = validate_numeric(config, key, min_v, max_v)
        if valid:
            print(f"  PASS: {key} = {result}")
        else:
            print(f"  FAIL: {key} - {result}")

# Run the parser
filepath = "/tmp/ex5_db.conf"
config, warnings = parse_config(filepath)

if config is not None:
    print_report(config, warnings)
else:
    print(f"Could not load config from {filepath}")
```

Run it:

```bash
python3 /tmp/ex5_config_parser.py
```

**Expected output:**

```
Parsed Configuration
=============================================
dbname              = production
host                = 10.0.1.10
maintenance_work_mem_mb = 512
max_connections     = 200
port                = 5432
port_alt            = not_a_number
shared_buffers_mb   = 4096
timeout             = -5
work_mem_mb         = 64

Warnings (1):
  WARNING: Line 12: no '=' sign found: bad line without equals

Validation Results
=============================================
  PASS: port = 5432
  PASS: max_connections = 200
  PASS: shared_buffers_mb = 4096
  PASS: work_mem_mb = 64
  FAIL: port_alt - invalid number: 'not_a_number'
  FAIL: timeout - value -5 is below minimum 0
```

**Hints:**
- `line.split('=', 1)` splits on only the first `=` sign
- For `validate_numeric`, check key existence first: `if key not in config: return (False, "key not found")`
- Wrap `int(config[key])` in try/except ValueError
- Return a tuple: `(True, int_value)` or `(False, "error message")`

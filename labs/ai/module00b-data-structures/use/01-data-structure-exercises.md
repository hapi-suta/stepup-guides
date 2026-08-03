# USE 01: Data Structures Exercises

**Module:** 00b - Data Structures
**Prerequisites:** BUILD 01-04 completed
**Time:** 45-60 minutes

These exercises reinforce everything from BUILD 01-04. Each one has a DBA-relevant scenario, starter code with TODOs, expected output, and hints.

---

## Exercise 1: Query Result Parser

**Scenario:** You have query results stored as a list of tuples (like what `cursor.fetchall()` returns from a database driver). Each tuple is `(database_name, size_mb, connection_count, is_active)`. You need to filter, sort, and summarize the results.

**Create the file:**

```bash
vi /tmp/exercise1_query_parser.py
```

**Paste this starter code:**

```python
# Exercise 1: Query Result Parser
# Each tuple: (db_name, size_mb, connections, is_active)

results = [
    ('myapp_prod', 2048, 150, True),
    ('analytics', 8192, 300, True),
    ('old_reporting', 512, 0, False),
    ('myapp_staging', 256, 25, True),
    ('legacy_crm', 1024, 0, False),
    ('metrics', 4096, 100, True),
    ('template0', 8, 0, False),
    ('postgres', 8, 5, True),
]

# TODO 1: Use a list comprehension to get only ACTIVE databases
# Hint: filter on the 4th element (index 3) being True
active_dbs = []  # Replace with comprehension
print("Active databases:")
for db in active_dbs:
    print(f"  {db[0]}")

# TODO 2: Sort active databases by size_mb descending
# Hint: use sorted() with key=lambda and reverse=True
sorted_active = []  # Replace with sorted()
print("\nActive databases by size (largest first):")
for name, size, conns, active in sorted_active:
    print(f"  {name:<20} {size:>6} MB  {conns:>4} conns")

# TODO 3: Calculate total size of active databases
# Hint: use sum() with a generator expression
total_size = 0  # Replace with sum()
print(f"\nTotal active size: {total_size} MB ({total_size/1024:.1f} GB)")

# TODO 4: Find the database with the most connections
# Hint: use max() with key=lambda
busiest = None  # Replace with max()
print(f"Busiest database: {busiest[0]} ({busiest[2]} connections)")

# TODO 5: Use tuple unpacking in a loop to create a formatted report
# of inactive databases
print("\nInactive databases (candidates for cleanup):")
# Replace pass with a for loop using tuple unpacking
pass
```

**Run it:**

```bash
python3 /tmp/exercise1_query_parser.py
```

**Expected output:**

```
Active databases:
  myapp_prod
  analytics
  myapp_staging
  metrics
  postgres

Active databases by size (largest first):
  analytics                8192 MB   300 conns
  metrics                  4096 MB   100 conns
  myapp_prod               2048 MB   150 conns
  myapp_staging             256 MB    25 conns
  postgres                    8 MB     5 conns

Total active size: 14600 MB (14.3 GB)
Busiest database: analytics (300 connections)

Inactive databases (candidates for cleanup):
  old_reporting       512 MB
  legacy_crm         1024 MB
  template0             8 MB
```

**Hints:**
- TODO 1: `[row for row in results if row[3]]`
- TODO 2: `sorted(active_dbs, key=lambda r: r[1], reverse=True)`
- TODO 3: `sum(row[1] for row in active_dbs)`
- TODO 4: `max(active_dbs, key=lambda r: r[2])`
- TODO 5: `for name, size, conns, active in results: if not active: print(...)`

---

## Exercise 2: Database Inventory

**Scenario:** You manage PostgreSQL across multiple servers. Build a dict-based inventory system that tracks databases per server and produces summary reports.

**Create the file:**

```bash
vi /tmp/exercise2_db_inventory.py
```

**Paste this starter code:**

```python
# Exercise 2: Database Inventory
# Track databases across servers using dicts

inventory = {
    'pg-primary': {
        'ip': '10.0.1.50',
        'databases': {
            'myapp_prod': {'size_mb': 2048, 'connections': 150},
            'analytics': {'size_mb': 8192, 'connections': 300},
            'reporting': {'size_mb': 512, 'connections': 20},
        }
    },
    'pg-replica': {
        'ip': '10.0.1.51',
        'databases': {
            'myapp_prod': {'size_mb': 2048, 'connections': 50},
            'analytics': {'size_mb': 8192, 'connections': 100},
        }
    },
    'pg-staging': {
        'ip': '10.0.2.10',
        'databases': {
            'myapp_staging': {'size_mb': 256, 'connections': 10},
            'analytics_dev': {'size_mb': 1024, 'connections': 5},
        }
    },
}

# TODO 1: Print total size per server
# Loop over inventory.items(), then sum sizes of all databases on each server
print("=== Size per Server ===")
for server, info in inventory.items():
    total = 0  # Replace: sum the size_mb of all databases on this server
    print(f"  {server:<15} {info['ip']:<15} {total:>8} MB")

# TODO 2: Find total connections across ALL servers
# Hint: nested loop over servers -> databases -> connections
total_conns = 0  # Replace with nested comprehension or loop
print(f"\nTotal connections across all servers: {total_conns}")

# TODO 3: Build a set of ALL unique database names across all servers
# Hint: loop through servers and collect database names into a set
all_db_names = set()  # Replace: populate this set
print(f"\nUnique databases: {sorted(all_db_names)}")
print(f"Total unique: {len(all_db_names)}")

# TODO 4: Find which databases exist on multiple servers
# Hint: for each unique db name, count how many servers have it
print("\nDatabases replicated across servers:")
# Your code here

# TODO 5: Find the server with the most total storage used
# Hint: use max() with a key function that sums database sizes
print("\nServer with most storage:")
# Your code here
```

**Run it:**

```bash
python3 /tmp/exercise2_db_inventory.py
```

**Expected output:**

```
=== Size per Server ===
  pg-primary      10.0.1.50          10752 MB
  pg-replica      10.0.1.51          10240 MB
  pg-staging      10.0.2.10           1280 MB

Total connections across all servers: 635

Unique databases: ['analytics', 'analytics_dev', 'myapp_prod', 'myapp_staging', 'reporting']
Total unique: 5

Databases replicated across servers:
  myapp_prod: on 2 servers
  analytics: on 2 servers

Server with most storage:
  pg-primary (10752 MB)
```

**Hints:**
- TODO 1: `sum(db['size_mb'] for db in info['databases'].values())`
- TODO 2: Nested loop or `sum(db['connections'] for info in inventory.values() for db in info['databases'].values())`
- TODO 3: `for info in inventory.values(): for db_name in info['databases']: all_db_names.add(db_name)`
- TODO 4: Count each db name across servers, print those with count > 1
- TODO 5: `max(inventory.items(), key=lambda x: sum(...))`

---

## Exercise 3: Log Analyzer

**Scenario:** You have a list of PostgreSQL log entries. Use comprehensions and built-in functions to filter, transform, and summarize them.

**Create the file:**

```bash
vi /tmp/exercise3_log_analyzer.py
```

**Paste this starter code:**

```python
# Exercise 3: Log Analyzer
# Analyze mock PostgreSQL log entries using comprehensions

log_entries = [
    "2024-03-15 10:00:01 ERROR: connection refused for user admin",
    "2024-03-15 10:00:05 LOG: checkpoint starting: time",
    "2024-03-15 10:00:12 WARNING: could not open statistics file",
    "2024-03-15 10:01:00 ERROR: duplicate key violates unique constraint",
    "2024-03-15 10:01:30 LOG: checkpoint complete: wrote 128 buffers",
    "2024-03-15 10:02:00 ERROR: connection refused for user app_readonly",
    "2024-03-15 10:02:15 LOG: automatic vacuum of table myapp.orders",
    "2024-03-15 10:03:00 WARNING: archive command failed with exit code 1",
    "2024-03-15 10:03:30 ERROR: out of shared memory",
    "2024-03-15 10:04:00 LOG: checkpoint starting: xlog",
    "2024-03-15 10:04:45 ERROR: connection refused for user reporting",
    "2024-03-15 10:05:00 LOG: checkpoint complete: wrote 256 buffers",
]

# TODO 1: Use a list comprehension to get only ERROR entries
errors = []  # Replace with comprehension
print(f"Error count: {len(errors)}")
for e in errors:
    print(f"  {e}")

# TODO 2: Use a dict comprehension to count entries by severity level
# Hint: first extract severity with split(), then count
# Severity is the 3rd word in each line (after date and time)
print("\n=== Counts by Severity ===")
# Your code here

# TODO 3: Use a list comprehension to extract just the timestamps of errors
# Hint: timestamp is the first 19 characters of each line
error_times = []  # Replace with comprehension
print("\nError timestamps:")
for t in error_times:
    print(f"  {t}")

# TODO 4: Find all unique error messages (set comprehension)
# Hint: the message is everything after "ERROR: "
unique_errors = set()  # Replace with set comprehension
print(f"\nUnique error types ({len(unique_errors)}):")
for err in sorted(unique_errors):
    print(f"  {err}")

# TODO 5: Count "connection refused" errors and identify affected users
# Hint: filter for "connection refused", then extract the last word (username)
print("\n=== Connection Refused Analysis ===")
# Your code here
```

**Run it:**

```bash
python3 /tmp/exercise3_log_analyzer.py
```

**Expected output:**

```
Error count: 5
  2024-03-15 10:00:01 ERROR: connection refused for user admin
  2024-03-15 10:01:00 ERROR: duplicate key violates unique constraint
  2024-03-15 10:02:00 ERROR: connection refused for user app_readonly
  2024-03-15 10:03:30 ERROR: out of shared memory
  2024-03-15 10:04:45 ERROR: connection refused for user reporting

=== Counts by Severity ===
  ERROR:     5
  LOG:       5
  WARNING:   2

Error timestamps:
  2024-03-15 10:00:01
  2024-03-15 10:01:00
  2024-03-15 10:02:00
  2024-03-15 10:03:30
  2024-03-15 10:04:45

Unique error types (3):
  connection refused for user admin
  duplicate key violates unique constraint
  out of shared memory

=== Connection Refused Analysis ===
  Connection refused errors: 3
  Affected users: admin, app_readonly, reporting
```

**Hints:**
- TODO 1: `[e for e in log_entries if 'ERROR' in e]`
- TODO 2: Count using split to get severity, then use the counting pattern from BUILD 04
- TODO 3: `[e[:19] for e in log_entries if 'ERROR' in e]`
- TODO 4: `{e.split('ERROR: ')[1] for e in errors}` - note: this groups "connection refused" variants together, so you may need a different approach for truly unique messages
- TODO 5: Filter for 'connection refused', extract last word with `.split()[-1]`

---

## Exercise 4: Duplicate Finder

**Scenario:** You suspect there are duplicate database names across your infrastructure. Build a tool that finds them using sets and dicts.

**Create the file:**

```bash
vi /tmp/exercise4_duplicate_finder.py
```

**Paste this starter code:**

```python
# Exercise 4: Duplicate Finder
# Find duplicate entries using sets and dicts

# Database entries from different config files
# Format: (db_name, host, port)
config_entries = [
    ('myapp_prod', 'pg-primary', 5432),
    ('analytics', 'pg-primary', 5432),
    ('myapp_prod', 'pg-replica', 5432),
    ('reporting', 'pg-analytics', 5433),
    ('analytics', 'pg-replica', 5432),
    ('myapp_prod', 'pg-dr', 5432),
    ('metrics', 'pg-metrics', 5434),
    ('analytics', 'pg-analytics', 5433),
    ('reporting', 'pg-primary', 5432),
    ('myapp_staging', 'pg-staging', 5432),
]

# TODO 1: Find all unique database names using a set comprehension
unique_names = set()  # Replace with set comprehension
print(f"Unique database names: {sorted(unique_names)}")
print(f"Total entries: {len(config_entries)}, Unique names: {len(unique_names)}")

# TODO 2: Find which database names appear more than once
# Use the "seen + dupes" pattern from BUILD 04
print("\nDuplicate database names:")
# Your code here

# TODO 3: For each duplicate, show all its entries
# Use a dict where key=db_name, value=list of (host, port) tuples
print("\nDuplicate details:")
# Your code here

# TODO 4: Find duplicate (db_name, port) combinations
# These are true conflicts - same db name on the same port
print("\nPotential conflicts (same name + port):")
# Your code here

# TODO 5: Find entries that are completely unique (appear only once)
print("\nSingleton entries (no replicas):")
# Your code here
```

**Run it:**

```bash
python3 /tmp/exercise4_duplicate_finder.py
```

**Expected output:**

```
Unique database names: ['analytics', 'metrics', 'myapp_prod', 'myapp_staging', 'reporting']
Total entries: 10, Unique names: 5

Duplicate database names:
  myapp_prod (3 occurrences)
  analytics (3 occurrences)
  reporting (2 occurrences)

Duplicate details:
  myapp_prod:
    - pg-primary:5432
    - pg-replica:5432
    - pg-dr:5432
  analytics:
    - pg-primary:5432
    - pg-replica:5432
    - pg-analytics:5433
  reporting:
    - pg-analytics:5433
    - pg-primary:5432

Potential conflicts (same name + port):
  ('myapp_prod', 5432): 3 entries
  ('analytics', 5432): 2 entries
  ('reporting', 5432): 1 entries
  ('reporting', 5433): 1 entries
  ('analytics', 5433): 1 entries

Singleton entries (no replicas):
  metrics on pg-metrics:5434
  myapp_staging on pg-staging:5432
```

**Hints:**
- TODO 1: `{entry[0] for entry in config_entries}`
- TODO 2: Count occurrences of each name, filter for count > 1
- TODO 3: Build a dict with `db_name -> list of (host, port)`
- TODO 4: Count occurrences of `(db_name, port)` tuples
- TODO 5: Names that appear exactly once in the count dict

---

## Exercise 5: Connection Pool Simulator

**Scenario:** Simulate a database connection pool using lists and dicts. Connections can be checked out and returned.

**Create the file:**

```bash
vi /tmp/exercise5_conn_pool.py
```

**Paste this starter code:**

```python
# Exercise 5: Connection Pool Simulator
# Simulate a connection pool using lists and dicts

# TODO 1: Initialize the pool
# Create a dict with:
#   'max_size': 5
#   'available': a list of 5 connection dicts, each with 'id' and 'status'
#   'in_use': an empty list
# Hint: use a list comprehension to create the 5 connection dicts
#   Each connection: {'id': 'conn_1', 'status': 'idle', 'user': None}
pool = {}  # Replace with your initialization

def show_pool(pool):
    """Display current pool state."""
    avail = len(pool['available'])
    used = len(pool['in_use'])
    print(f"  Pool: {avail} available, {used} in use, {pool['max_size']} max")

print("=== Initial Pool ===")
show_pool(pool)

# TODO 2: Write a checkout function
# - If available list is empty, print error and return None
# - Otherwise, pop a connection from available, set status to 'active'
#   and user to the given username, append to in_use, return the connection
def checkout(pool, username):
    pass  # Replace with your implementation

# TODO 3: Write a checkin function
# - Find the connection in in_use by id
# - Remove it from in_use, reset status to 'idle' and user to None
# - Append it back to available
def checkin(pool, conn_id):
    pass  # Replace with your implementation

# Test the pool
print("\n=== Checking out connections ===")
c1 = checkout(pool, 'app_user')
print(f"Checked out: {c1['id']} for {c1['user']}")
show_pool(pool)

c2 = checkout(pool, 'report_user')
print(f"Checked out: {c2['id']} for {c2['user']}")
show_pool(pool)

c3 = checkout(pool, 'admin')
c4 = checkout(pool, 'batch_job')
c5 = checkout(pool, 'monitoring')
show_pool(pool)

# TODO 4: Try to checkout when pool is exhausted
print("\n=== Pool exhausted ===")
c6 = checkout(pool, 'overflow_user')
show_pool(pool)

# TODO 5: Return connections and show pool recovery
print("\n=== Returning connections ===")
checkin(pool, c1['id'])
print(f"Returned: {c1['id']}")
show_pool(pool)

checkin(pool, c3['id'])
print(f"Returned: {c3['id']}")
show_pool(pool)

# Show who still has connections
print("\n=== Active connections ===")
for conn in pool['in_use']:
    print(f"  {conn['id']}: {conn['user']}")
```

**Run it:**

```bash
python3 /tmp/exercise5_conn_pool.py
```

**Expected output:**

```
=== Initial Pool ===
  Pool: 5 available, 0 in use, 5 max

=== Checking out connections ===
Checked out: conn_1 for app_user
  Pool: 4 available, 1 in use, 5 max
Checked out: conn_2 for report_user
  Pool: 3 available, 2 in use, 5 max
  Pool: 0 available, 5 in use, 5 max

=== Pool exhausted ===
ERROR: No connections available (0/5 in pool)
  Pool: 0 available, 5 in use, 5 max

=== Returning connections ===
Returned: conn_1
  Pool: 1 available, 4 in use, 5 max
Returned: conn_3
  Pool: 2 available, 3 in use, 5 max

=== Active connections ===
  conn_2: report_user
  conn_4: batch_job
  conn_5: monitoring
```

**Hints:**
- TODO 1: `pool = {'max_size': 5, 'available': [{'id': f'conn_{i}', 'status': 'idle', 'user': None} for i in range(1, 6)], 'in_use': []}`
- TODO 2: Use `.pop(0)` to get from available, modify the dict, `.append()` to in_use
- TODO 3: Loop through `in_use` to find the connection by id, use `.remove()`, reset fields, `.append()` back to available
- TODO 4: Check `len(pool['available']) == 0` and print the error
- TODO 5: The checkin function handles this - just call it

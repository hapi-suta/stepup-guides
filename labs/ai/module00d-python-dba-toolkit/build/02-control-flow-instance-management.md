# BUILD 02: Control Flow - Instance Controller

**What you will build:** `~/pgdba/instance_ctl.py` - a script that checks PostgreSQL status, evaluates state across multiple ports, and reports a decision for each instance.

**Python concepts covered:** if/elif/else, comparison operators, for loops, while loops, range(), break, continue, boolean operators (and/or/not)

**Time to complete:** ~45 minutes

---

## Prerequisites

- BUILD 01 complete (`~/pgdba/` directory exists)
- PostgreSQL running locally on port 5432
- `psutil` not required - this guide uses only stdlib

---

## Step 1: if/elif/else - decide based on a condition

In SQL you use `CASE WHEN condition THEN result ELSE fallback END`. In Python, the same logic is written as `if / elif / else`. `elif` is short for "else if" - it checks a second condition if the first was false.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import subprocess

result = subprocess.run(['pg_isready', '-h', 'localhost', '-p', '5432'], capture_output=True, text=True)
exit_code = result.returncode

if exit_code == 0:
    status = 'ACCEPTING CONNECTIONS'
elif exit_code == 1:
    status = 'REJECTING CONNECTIONS'
elif exit_code == 2:
    status = 'NO RESPONSE'
else:
    status = 'UNKNOWN'

print(f'Exit code: {exit_code}')
print(f'Status:    {status}')
"
```

What this does:
- `pg_isready` - PostgreSQL's built-in readiness probe. Returns 0 if accepting connections, 1 if rejecting, 2 if not responding.
- `result.returncode` - the integer exit code from the command (like `$?` in bash)
- Each `elif` branch is checked in order - only the first matching branch runs, just like `CASE WHEN` evaluates top to bottom

Expected output (yours will differ):

```
Exit code: 0
Status:    ACCEPTING CONNECTIONS
```

---

## Step 2: Comparison operators - the same as SQL WHERE clauses

Python comparison operators map directly to SQL:

| Python | SQL equivalent | Meaning               |
|--------|----------------|-----------------------|
| `==`   | `=`            | equal to              |
| `!=`   | `<>`           | not equal to          |
| `<`    | `<`            | less than             |
| `>`    | `>`            | greater than          |
| `<=`   | `<=`           | less than or equal    |
| `>=`   | `>=`           | greater than or equal |

On your **Mac terminal**:

```bash
python3 -c "
max_connections = 100
current_connections = 87
warning_threshold = 80
critical_threshold = 95

pct_used = (current_connections / max_connections) * 100

print(f'Connections: {current_connections}/{max_connections} ({pct_used:.1f}%)')
print(f'Above warning  (>= {warning_threshold}%): {pct_used >= warning_threshold}')
print(f'Above critical (>= {critical_threshold}%): {pct_used >= critical_threshold}')
print(f'Exactly at max (== {max_connections}): {current_connections == max_connections}')
print(f'Has headroom   (!= {max_connections}): {current_connections != max_connections}')
"
```

Expected output (yours will differ):

```
Connections: 87/100 (87.0%)
Above warning  (>= 80%): True
Above critical (>= 95%): False
Exactly at max (== 100): False
Has headroom   (!= 100): True
```

---

## Step 3: Boolean operators - and / or / not

In SQL you combine conditions in a WHERE clause with `AND`, `OR`, `NOT`. Python uses the same words, just lowercase: `and`, `or`, `not`.

On your **Mac terminal**:

```bash
python3 -c "
port_open = True
process_running = True
data_dir_exists = True
is_standby = False

# and - ALL conditions must be true (like WHERE a = 1 AND b = 2)
fully_up = port_open and process_running and data_dir_exists
print(f'Fully up:          {fully_up}')

# or - ANY condition being true is enough (like WHERE a = 1 OR b = 2)
has_issue = not port_open or not process_running
print(f'Has issue:         {has_issue}')

# not - inverts a boolean (like WHERE NOT is_standby)
is_primary = not is_standby
print(f'Is primary:        {is_primary}')

# Combined - parentheses work exactly like SQL
ready_for_traffic = fully_up and (not is_standby)
print(f'Ready for traffic: {ready_for_traffic}')
"
```

Expected output (yours will differ):

```
Fully up:          True
Has issue:         False
Is primary:        True
Ready for traffic: True
```

---

## Step 4: for loop - iterate over a list of ports

In PL/pgSQL you use a cursor `FOR rec IN SELECT ... LOOP`. In Python, `for item in collection:` loops over any list. Think of it as iterating over a result set, but the data comes from a Python list instead of a query.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess

ports = [5432, 5433, 5434]

for port in ports:
    result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', str(port)],
        capture_output=True,
        text=True
    )
    status = 'UP' if result.returncode == 0 else 'DOWN'
    print(f'Port {port}: {status}')
"
```

What this does:
- `ports = [5432, 5433, 5434]` - a list (like an array in PL/pgSQL or a row set)
- `for port in ports:` - assigns each value to `port` one at a time, runs the indented block
- Indentation (4 spaces) marks what is inside the loop - Python uses whitespace instead of `BEGIN/END`
- `str(port)` - converts the integer to a string because `subprocess.run` needs all arguments as strings

Expected output (yours will differ):

```
Port 5432: UP
Port 5433: DOWN
Port 5434: DOWN
```

---

## Step 5: range() - generate a sequence of numbers

`range()` is Python's equivalent of `generate_series()` in PostgreSQL. It produces a sequence of integers without storing them in memory.

On your **Mac terminal**:

```bash
python3 -c "
# range(start, stop) - stop is EXCLUSIVE, like generate_series(5432, 5434)
print('Ports to scan:')
for port in range(5432, 5436):
    print(f'  {port}')

# range(start, stop, step) - like generate_series(0, 100, 10)
print('Connection thresholds:')
for pct in range(0, 101, 25):
    print(f'  {pct}%')
"
```

What this does:
- `range(5432, 5436)` - generates 5432, 5433, 5434, 5435 (stops BEFORE 5436)
- `range(0, 101, 25)` - generates 0, 25, 50, 75, 100 (step of 25, stops before 101)

Expected output (yours will differ):

```
Ports to scan:
  5432
  5433
  5434
  5435
Connection thresholds:
  0%
  25%
  50%
  75%
  100%
```

---

## Step 6: while loop - wait for PostgreSQL to start with a timeout

In PL/pgSQL you write `WHILE condition LOOP ... END LOOP`. Python uses `while condition:` followed by an indented block. This is useful for polling - waiting until PostgreSQL is ready or a timeout expires.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess
import time

max_attempts = 5
attempt = 0
ready = False

while attempt < max_attempts and not ready:
    result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', '5432'],
        capture_output=True,
        text=True
    )
    ready = result.returncode == 0
    attempt = attempt + 1
    print(f'Attempt {attempt}/{max_attempts}: {\"ready\" if ready else \"not ready yet\"}')
    if not ready:
        time.sleep(1)

if ready:
    print('PostgreSQL is up!')
else:
    print(f'Timed out after {max_attempts} attempts.')
"
```

What this does:
- `while attempt < max_attempts and not ready:` - loop continues while BOTH conditions are true
- `attempt = attempt + 1` - increment the counter (same as `counter := counter + 1` in PL/pgSQL)
- `time.sleep(1)` - pause for 1 second between attempts (like `pg_sleep(1)` in SQL)

Expected output (yours will differ):

```
Attempt 1/5: ready
PostgreSQL is up!
```

---

## Step 7: break and continue - skip or stop the loop early

`break` exits the loop immediately. `continue` skips the rest of the current iteration and moves to the next one. These are the same as `EXIT` and `CONTINUE` in PL/pgSQL loops.

On your **Mac terminal**:

```bash
python3 -c "
ports = [5432, 5433, 5434, 5435]

print('-- break: stop at first live instance --')
for port in ports:
    import subprocess
    result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', str(port)],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        print(f'Found active instance on port {port}. Stopping.')
        break
    print(f'Port {port}: skipping (not active)')

print()
print('-- continue: report only DOWN instances --')
for port in ports:
    result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', str(port)],
        capture_output=True, text=True
    )
    if result.returncode == 0:
        continue   # skip UP instances - we only care about problems
    print(f'ALERT: port {port} is not responding')
"
```

Expected output (yours will differ):

```
-- break: stop at first live instance --
Found active instance on port 5432. Stopping.

-- continue: report only DOWN instances --
ALERT: port 5433 is not responding
ALERT: port 5434 is not responding
ALERT: port 5435 is not responding
```

---

## Step 8: Nested conditions - check port AND process AND data directory

Real instance health checks combine multiple conditions. This mirrors a WHERE clause with several AND conditions.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess
import os

def check_instance(port, data_dir):
    # Check 1: pg_isready
    pg_result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', str(port)],
        capture_output=True, text=True
    )
    port_ok = pg_result.returncode == 0

    # Check 2: Data directory exists
    dir_ok = os.path.isdir(data_dir)

    # Nested condition: determine overall health
    if port_ok and dir_ok:
        health = 'HEALTHY'
    elif port_ok and not dir_ok:
        health = 'WARNING - port up but data_dir missing'
    elif not port_ok and dir_ok:
        health = 'DOWN - data_dir exists but port not responding'
    else:
        health = 'CRITICAL - port down and data_dir missing'

    print(f'Port {port}: port_ok={port_ok}, dir_ok={dir_ok} -> {health}')

check_instance(5432, '/usr/local/var/postgresql@16')
check_instance(5433, '/tmp/fake-pg-data')
"
```

What this does: defines a function (covered fully in BUILD 03) and calls it with two different sets of arguments. Notice how the nested `if/elif/else` reads like a decision table - exactly how you think through a triage checklist.

Expected output (yours will differ):

```
Port 5432: port_ok=True, dir_ok=True -> HEALTHY
Port 5433: port_ok=False, dir_ok=False -> CRITICAL - port down and data_dir missing
```

---

## Step 9: Combine everything into instance_ctl.py

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/instance_ctl.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
import subprocess
import os
import sys

# -------------------------------------------------------
# Configuration - edit to match your instances
# -------------------------------------------------------
INSTANCES = [
    {'port': 5432, 'data_dir': '/usr/local/var/postgresql@16', 'name': 'primary'},
    {'port': 5433, 'data_dir': '/usr/local/var/postgresql@17', 'name': 'standby-1'},
    {'port': 5434, 'data_dir': '/tmp/pg-test',                'name': 'test'},
]

MAX_POLL_ATTEMPTS = 5
POLL_INTERVAL_SEC = 1


def check_port(port):
    """Return True if pg_isready reports the port is accepting connections."""
    result = subprocess.run(
        ['pg_isready', '-h', 'localhost', '-p', str(port)],
        capture_output=True,
        text=True
    )
    return result.returncode == 0


def check_instance(name, port, data_dir):
    """Check one PostgreSQL instance and return a status string."""
    port_ok = check_port(port)
    dir_ok = os.path.isdir(data_dir)

    if port_ok and dir_ok:
        health = 'HEALTHY'
    elif port_ok and not dir_ok:
        health = 'WARNING  - port accepting but data_dir missing'
    elif not port_ok and dir_ok:
        health = 'DOWN     - data_dir exists but port not responding'
    else:
        health = 'CRITICAL - port down and data_dir missing'

    return health


def wait_for_instance(port, max_attempts=MAX_POLL_ATTEMPTS):
    """Poll a port until PostgreSQL responds or timeout."""
    attempt = 0
    while attempt < max_attempts:
        if check_port(port):
            return True
        attempt = attempt + 1
        import time
        time.sleep(POLL_INTERVAL_SEC)
    return False


# -------------------------------------------------------
# Main: check each configured instance
# -------------------------------------------------------
print('=' * 60)
print('  Instance Controller - Status Report')
print('=' * 60)
print(f'  {"NAME":<12} {"PORT":<8} {"DATA DIR":<35} STATUS')
print('-' * 60)

issues = 0
for instance in INSTANCES:
    name = instance['name']
    port = instance['port']
    data_dir = instance['data_dir']

    health = check_instance(name, port, data_dir)

    if 'HEALTHY' not in health:
        issues = issues + 1

    print(f'  {name:<12} {port:<8} {data_dir:<35} {health}')

print('-' * 60)
print(f'  Instances checked: {len(INSTANCES)}')
print(f'  Issues found:      {issues}')
print('=' * 60)

# Exit with a non-zero code if any instance has an issue
# (useful when calling this script from a monitoring cron job)
if issues > 0:
    sys.exit(1)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 10: Run the final script

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/instance_ctl.py
```

Expected output (yours will differ):

```
============================================================
  Instance Controller - Status Report
============================================================
  NAME         PORT     DATA DIR                            STATUS
------------------------------------------------------------
  primary      5432     /usr/local/var/postgresql@16        HEALTHY
  standby-1    5433     /usr/local/var/postgresql@17        CRITICAL - port down and data_dir missing
  test         5434     /tmp/pg-test                        CRITICAL - port down and data_dir missing
------------------------------------------------------------
  Instances checked: 3
  Issues found:      2
============================================================
```

Check the exit code:

```bash
echo "Exit code: $?"
```

Expected output (yours will differ):

```
Exit code: 1
```

A non-zero exit code means issues were found. This makes the script safe to call from a cron job or monitoring system - it signals failure the same way a failing shell script would.

---

## What you built

You now have `~/pgdba/instance_ctl.py` - a multi-instance health checker you can run on any machine that has `pg_isready` on the PATH.

| Python concept         | DBA analogy                                        |
|------------------------|----------------------------------------------------|
| `if / elif / else`     | `CASE WHEN ... THEN ... ELSE ... END` in SQL       |
| Comparison operators   | `WHERE` clause operators (`=`, `<>`, `<`, `>=`)   |
| `and / or / not`       | `AND / OR / NOT` in a WHERE clause                |
| `for item in list:`    | Cursor `FOR rec IN SELECT ... LOOP` in PL/pgSQL   |
| `range()`              | `generate_series()` in PostgreSQL                  |
| `while condition:`     | `WHILE condition LOOP` in PL/pgSQL                |
| `break`                | `EXIT` in a PL/pgSQL loop                         |
| `continue`             | `CONTINUE` in a PL/pgSQL loop                     |
| `sys.exit(1)`          | `RAISE EXCEPTION` to signal a failure             |

Next: BUILD 03 - Functions: SQL Runner

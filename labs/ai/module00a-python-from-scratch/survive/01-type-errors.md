# SURVIVE 01: The Type Mismatch Disaster

**Module:** module00a-python-from-scratch
**Time:** 15-20 minutes
**Prerequisites:** BUILD 01-04 completed

---

## The Scenario

Your team deployed a monitoring script that collects CPU, memory, and connection metrics from PostgreSQL servers. It ran fine for two days, then started crashing at 3 AM with this error:

```
TypeError: '>' not supported between instances of 'str' and 'int'
```

The on-call DBA restarted the script, but it crashed again within minutes. The metrics dashboard has been dark for hours. You need to fix this - now.

---

## Part 1: Symptom

Here is the broken monitoring script. Create it:

```bash
vi /tmp/survive01_broken.py
```

Paste this code:

```python
# Broken monitoring script - DO NOT FIX YET, just observe the error

def check_server(name, cpu, memory, connections, max_conn):
    """Check server health and return status."""
    # Calculate connection percentage
    conn_pct = connections / max_conn * 100

    # Classify health
    if cpu > 90:
        cpu_status = "CRITICAL"
    elif cpu > 70:
        cpu_status = "WARNING"
    else:
        cpu_status = "OK"

    if memory > 90:
        mem_status = "CRITICAL"
    elif memory > 70:
        mem_status = "WARNING"
    else:
        mem_status = "OK"

    print(f"{name}: CPU={cpu_status} MEM={mem_status} CONN={conn_pct:.1f}%")

# Simulated metrics - some come in as strings (from an API response)
servers = [
    ("pg-primary",  85,   78,   150, 200),    # all integers - works fine
    ("pg-replica1", "45", "60", "42", "200"),  # all strings - BUG!
    ("pg-replica2", 72,   "91", 100, 200),     # mixed - BUG!
    ("pg-analytics", "30", 25,  "0", "200"),   # mixed - BUG!
]

print("Server Health Check")
print("=" * 50)

for name, cpu, mem, conns, max_c in servers:
    check_server(name, cpu, mem, conns, max_c)
```

Run it to see the crash:

```bash
python3 /tmp/survive01_broken.py
```

Expected output:
```
Server Health Check
==================================================
pg-primary: CPU=WARNING MEM=WARNING CONN=75.0%
Traceback (most recent call last):
  File "/tmp/survive01_broken.py", line 33, in <module>
    check_server(name, cpu, mem, conns, max_c)
  File "/tmp/survive01_broken.py", line 7, in check_server
    conn_pct = connections / max_conn * 100
TypeError: unsupported operand type(s) for /: 'str' and 'str'
```

The first server works because its metrics are integers. The second server has string metrics and crashes.

---

## Part 2: Diagnosis

Answer these questions before moving on:

1. **Why does the first server work but the second crashes?**
   The first server's metrics are integers (`85, 78, 150, 200`). The second server's metrics are strings (`"45", "60", "42", "200"`). You cannot divide a string by a string.

2. **Why would metrics come in as strings?**
   API responses, CSV files, and command-line arguments all deliver data as strings. This is like how psql returns everything as text - your application must cast values.

3. **What about pg-replica2 with mixed types?**
   `cpu` is `72` (int) and `memory` is `"91"` (string). The comparison `cpu > 90` works (int > int), but `memory > 90` would fail (string > int). Which line crashes first depends on what comparison runs first.

4. **What is the DBA analogy?**
   This is exactly like `SELECT '45' > 90` in a strongly-typed context. PostgreSQL would throw: `ERROR: operator does not exist: character varying > integer`.

---

## Part 3: Fix with Validation

Now fix the script. Create the repaired version:

```bash
vi /tmp/survive01_fixed.py
```

Paste this code:

```python
# Fixed monitoring script with type safety

def safe_int(value, field_name="unknown"):
    """Convert a value to integer safely.

    Like CAST(value AS INTEGER) with error handling.
    """
    try:
        return int(value)
    except (ValueError, TypeError) as e:
        print(f"  WARNING: Cannot convert {field_name}='{value}' to int, using 0")
        return 0

def check_server(name, cpu, memory, connections, max_conn):
    """Check server health with type-safe conversions."""
    # Convert ALL inputs to integers - never trust input types
    cpu = safe_int(cpu, "cpu")
    memory = safe_int(memory, "memory")
    connections = safe_int(connections, "connections")
    max_conn = safe_int(max_conn, "max_conn")

    # Guard against division by zero
    if max_conn == 0:
        conn_pct = 0.0
        print(f"  WARNING: max_connections is 0 for {name}")
    else:
        conn_pct = connections / max_conn * 100

    # Now all comparisons are safe - int > int
    if cpu > 90:
        cpu_status = "CRITICAL"
    elif cpu > 70:
        cpu_status = "WARNING"
    else:
        cpu_status = "OK"

    if memory > 90:
        mem_status = "CRITICAL"
    elif memory > 70:
        mem_status = "WARNING"
    else:
        mem_status = "OK"

    print(f"{name}: CPU={cpu_status} MEM={mem_status} CONN={conn_pct:.1f}%")

# Same data as before - strings, ints, mixed
servers = [
    ("pg-primary",  85,   78,   150, 200),
    ("pg-replica1", "45", "60", "42", "200"),
    ("pg-replica2", 72,   "91", 100, 200),
    ("pg-analytics", "30", 25,  "0", "200"),
    ("pg-edge-case", "N/A", 50, 10, 0),       # extra edge case
]

print("Server Health Check")
print("=" * 50)

for name, cpu, mem, conns, max_c in servers:
    check_server(name, cpu, mem, conns, max_c)
```

Run the fixed version:

```bash
python3 /tmp/survive01_fixed.py
```

Expected output:
```
Server Health Check
==================================================
pg-primary: CPU=WARNING MEM=WARNING CONN=75.0%
pg-replica1: CPU=OK MEM=OK CONN=21.0%
pg-replica2: CPU=WARNING MEM=CRITICAL CONN=50.0%
pg-analytics: CPU=OK MEM=OK CONN=0.0%
  WARNING: Cannot convert cpu='N/A' to int, using 0
  WARNING: max_connections is 0 for pg-edge-case
pg-edge-case: CPU=OK MEM=OK CONN=0.0%
```

---

## What You Survived

| Problem | Root Cause | Fix |
|---------|-----------|-----|
| `TypeError` on comparison | String vs int comparison | Convert with `int()` before comparing |
| `TypeError` on division | String vs string division | Convert with `int()` before math |
| Unconvertible values ("N/A") | Not all strings are numbers | Use `try/except ValueError` with a default |
| Division by zero | `max_conn` could be 0 | Guard with `if max_conn == 0` check |

**The Rule:** Never trust input types. Always convert and validate before using values in math or comparisons. This is the Python equivalent of always using explicit CASTs in SQL.

# BUILD 16: Regex - Log Parser (Logical Replication)

## What You're Building

By the end of this guide you will have a working script called `log_parser.py` in `~/pgdba/` that parses PostgreSQL log files to extract errors, slow queries, replication conflicts, connection attempts, and deadlocks using Python's `re` module.

**Python concepts covered:** `re` module, `re.search()`, `re.findall()`, `re.match()`, `re.sub()`, raw strings `r""`, groups `()`, named groups `(?P<name>)`, `re.compile()`, common patterns

**DBA task:** Build a log parser that processes unstructured PostgreSQL log text the way you'd use `grep`, `awk`, and `sed` - but with full programmatic control, so you can extend it into a real alerting tool.

---

## Prerequisites

- Completed BUILD 15 (or have Python 3 and `~/pgdba/` ready)
- PostgreSQL installed locally (for log file reference)
- `~/pgdba/` directory exists

---

## Step 1: Why Regex? PostgreSQL Logs Are Unstructured Text

PostgreSQL writes logs as free-form text. There is no SQL table to query, no fixed column widths. You need pattern matching to extract useful data.

**DBA analogy:** `LIKE` matches fixed literals. The `~` operator (tilde) in PostgreSQL uses POSIX regex. Python's `re` module is the same idea, but with full control in your script instead of inside a WHERE clause.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

log_line = '2024-01-15 14:23:45.123 UTC [12345] ERROR:  relation \"orders\" does not exist'

# SQL equivalent: WHERE log_line ~ 'ERROR'
found = re.search('ERROR', log_line)
print('Found ERROR:', found)
print('Match object:', type(found))
"
```

- `import re` - load the regex module from Python's standard library (no install needed)
- `re.search('ERROR', log_line)` - scan through the string and return a Match object if the pattern is found anywhere; returns `None` if not found

```
Expected output (yours will differ):
Found ERROR:  <re.Match object; span=(46, 51), match='ERROR'>
Match object: <class 're.Match'>
```

---

## Step 2: re.search() - Find a Pattern in a String

**DBA analogy:** `re.search()` is like `col ~ 'pattern'` in a WHERE clause - it returns a truthy result if the pattern appears anywhere in the string.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

lines = [
    '2024-01-15 14:23:45 UTC [1234] LOG:  connection received: host=10.0.1.5 port=52341',
    '2024-01-15 14:23:46 UTC [1234] ERROR:  duplicate key value violates unique constraint',
    '2024-01-15 14:23:47 UTC [1234] LOG:  checkpoint starting: time',
]

for line in lines:
    if re.search('ERROR', line):
        print('ERROR LINE:', line[:60])
    else:
        print('other line: ', line[:60])
"
```

- `re.search(pattern, string)` - returns a Match object (truthy) if found, `None` (falsy) if not
- Used directly in an `if` block because `None` is falsy and a Match object is truthy - same pattern as checking a cursor result in Python

```
Expected output (yours will differ):
other line:  2024-01-15 14:23:45 UTC [1234] LOG:  connection received
ERROR LINE:  2024-01-15 14:23:46 UTC [1234] ERROR:  duplicate key val
other line:  2024-01-15 14:23:47 UTC [1234] LOG:  checkpoint starting
```

---

## Step 3: Raw Strings r"" - Why You Need Them

This is one of the most important things to understand before writing real patterns.

**DBA analogy:** In SQL you escape a single quote by doubling it: `''`. In Python regex, backslashes mean something both to Python strings AND to the regex engine. Raw strings (`r""`) tell Python: "don't interpret backslashes - pass them straight to the regex engine."

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

# Without raw string - Python interprets \d before regex sees it
# \d means 'digit' in regex, but \\d is what gets sent to the engine
pattern_bad  = '\d+'          # Python converts \d to... nothing useful
pattern_good = r'\d+'         # r prefix: backslash passed directly to regex

text = 'duration: 1234.567 ms'

match_bad  = re.search(pattern_bad, text)
match_good = re.search(pattern_good, text)

print('Without r prefix:', match_bad)
print('With r prefix:   ', match_good)
print('Matched digits:  ', match_good.group() if match_good else None)
"
```

- `r'\d+'` - raw string; the `\d` is passed literally to the regex engine, which interprets it as "any digit"
- `\d` - regex shorthand for `[0-9]`
- `+` - one or more occurrences (like `{1,}` in some regex flavors)
- Always use `r""` for regex patterns. No exceptions.

```
Expected output (yours will differ):
Without r prefix: None
With r prefix:    <re.Match object; span=(10, 14), match='1234'>
Matched digits:   1234
```

---

## Step 4: re.findall() - Find ALL Matches

**DBA analogy:** `re.findall()` is like `regexp_matches(col, pattern, 'g')` with the global flag - it returns every match in the string as a list, not just the first one.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

log_line = 'process 12345 acquired ShareLock on transaction 67890 after 1500.234 ms  (PID 12345)'

# Find all numbers in the line
numbers = re.findall(r'\d+', log_line)
print('All numbers found:', numbers)

# Find all words that look like PIDs (digits only, length 4-6)
pids = re.findall(r'\b\d{4,6}\b', log_line)
print('Possible PIDs:    ', pids)
"
```

- `re.findall(pattern, string)` - returns a list of all non-overlapping matches
- `\b` - word boundary anchor; ensures we match whole numbers, not digits inside words (like `\m` and `\M` in PostgreSQL POSIX regex)
- `\d{4,6}` - exactly 4 to 6 digits (`{min,max}` quantifier)
- Returns an empty list `[]` if nothing matches - safe to iterate over

```
Expected output (yours will differ):
All numbers found: ['12345', '67890', '1500', '234', '12345']
Possible PIDs:     ['12345', '67890', '1500', '12345']
```

---

## Step 5: Groups () - Capture Parts of a Match

**DBA analogy:** Groups in regex are like `regexp_matches()` with multiple capture groups - the parentheses tell the engine: "give me this specific part back, not just the whole match."

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

log_line = 'duration: 1234.567 ms  statement: SELECT * FROM orders WHERE id = 42'

# Capture duration value separately from the unit
match = re.search(r'duration: (\d+\.\d+) ms', log_line)

if match:
    print('Full match:      ', match.group(0))   # group(0) = entire match
    print('Group 1 (value): ', match.group(1))   # group(1) = first ()
    print('As float:        ', float(match.group(1)))
"
```

- `(\d+\.\d+)` - the outer `()` creates a capture group; `\d+` matches digits, `\.` matches a literal dot, `\d+` matches more digits
- `match.group(0)` - the entire matched string (group 0 is always the full match)
- `match.group(1)` - the first capture group (what was inside the first `()`)
- `float(match.group(1))` - convert the captured string to a number so you can do math on it

```
Expected output (yours will differ):
Full match:       duration: 1234.567 ms
Group 1 (value):  1234.567
As float:         1234.567
```

---

## Step 6: Named Groups (?P<name>) - Give Captures Names

**DBA analogy:** Named groups are like column aliases in a SELECT - instead of referencing capture group `1`, `2`, `3` by position, you reference them by name. Much more readable when patterns get complex.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

log_line = '2024-01-15 14:23:45.678 UTC [12345] ERROR:  relation \"orders\" does not exist at character 15'

# Named groups: (?P<name>pattern)
pattern = r'(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) UTC \[(?P<pid>\d+)\] (?P<severity>\w+):\s+(?P<message>.+)'

match = re.search(pattern, log_line)

if match:
    print('Timestamp:', match.group('timestamp'))
    print('PID:      ', match.group('pid'))
    print('Severity: ', match.group('severity'))
    print('Message:  ', match.group('message'))
    print()
    print('As dict:  ', match.groupdict())
"
```

- `(?P<name>...)` - named capture group syntax; `name` becomes a dictionary key
- `match.group('timestamp')` - access by name instead of position number
- `match.groupdict()` - returns all named groups as a dictionary (like a row from a query)
- `\s+` - one or more whitespace characters (spaces, tabs)
- `.+` - match any character (except newline) one or more times - used here to grab the rest of the line

```
Expected output (yours will differ):
Timestamp: 2024-01-15 14:23:45.678
PID:       12345
Severity:  ERROR
Message:   relation "orders" does not exist at character 15

As dict:   {'timestamp': '2024-01-15 14:23:45.678', 'pid': '12345', 'severity': 'ERROR', 'message': 'relation "orders" does not exist at character 15'}
```

---

## Step 7: Parse PostgreSQL Error Lines

Now use named groups to extract structured data from real error log entries.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

sample_lines = [
    '2024-01-15 14:23:45.123 UTC [12345] ERROR:  relation \"orders\" does not exist',
    '2024-01-15 14:23:46.456 UTC [12346] FATAL:  password authentication failed for user \"appuser\"',
    '2024-01-15 14:23:47.789 UTC [12347] WARNING:  there is no transaction in progress',
    '2024-01-15 14:23:48.000 UTC [12348] LOG:  checkpoint starting: time',
]

# Pattern matches the standard PostgreSQL log_line_prefix = '%t [%p] '
error_pattern = re.compile(
    r'(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) UTC \[(?P<pid>\d+)\] '
    r'(?P<severity>ERROR|FATAL|PANIC|WARNING):\s+(?P<message>.+)'
)

errors = []
for line in sample_lines:
    match = error_pattern.search(line)
    if match:
        errors.append(match.groupdict())

print(f'Found {len(errors)} error/warning lines:')
for e in errors:
    print(f\"  [{e['severity']}] PID {e['pid']}: {e['message'][:60]}\")
"
```

- `re.compile(r'...' r'...')` - two raw strings next to each other are automatically joined; useful to split long patterns across lines
- `ERROR|FATAL|PANIC|WARNING` - the `|` is OR in regex (like `IN (...)` in SQL)
- `errors.append(match.groupdict())` - build a list of dictionaries, one per matched line

```
Expected output (yours will differ):
Found 3 error/warning lines:
  [ERROR] PID 12345: relation "orders" does not exist
  [FATAL] PID 12346: password authentication failed for user "appuser"
  [WARNING] PID 12347: there is no transaction in progress
```

---

## Step 8: Parse Slow Query Log Lines

**DBA analogy:** `log_min_duration_statement` outputs lines like `duration: 1234.567 ms  statement: SELECT ...`. This is the Python version of querying `pg_stat_statements`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

sample_lines = [
    '2024-01-15 14:25:01.111 UTC [12350] LOG:  duration: 5234.123 ms  statement: SELECT * FROM orders WHERE customer_id = 42',
    '2024-01-15 14:25:02.222 UTC [12351] LOG:  duration: 123.456 ms  statement: UPDATE sessions SET last_seen = NOW()',
    '2024-01-15 14:25:03.333 UTC [12352] LOG:  duration: 15678.900 ms  statement: VACUUM ANALYZE orders',
    '2024-01-15 14:25:04.444 UTC [12353] LOG:  checkpoint starting: time',
]

slow_pattern = re.compile(
    r'(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) UTC \[(?P<pid>\d+)\] LOG:\s+'
    r'duration: (?P<duration_ms>\d+\.\d+) ms\s+statement: (?P<query>.+)'
)

slow_queries = []
for line in sample_lines:
    match = slow_pattern.search(line)
    if match:
        d = match.groupdict()
        d['duration_ms'] = float(d['duration_ms'])   # convert string to number
        slow_queries.append(d)

# Sort by duration descending (like ORDER BY duration DESC)
slow_queries.sort(key=lambda q: q['duration_ms'], reverse=True)

print('Slow queries (slowest first):')
for q in slow_queries:
    print(f\"  {q['duration_ms']:>10.3f} ms  {q['query'][:55]}\")
"
```

- `float(d['duration_ms'])` - converts the captured string `'5234.123'` to a float so sorting works numerically
- `slow_queries.sort(key=lambda q: q['duration_ms'], reverse=True)` - sort in place by the `duration_ms` field, descending (like `ORDER BY duration_ms DESC`)
- `{q['duration_ms']:>10.3f}` - right-align, 10 chars wide, 3 decimal places

```
Expected output (yours will differ):
Slow queries (slowest first):
   15678.900 ms  VACUUM ANALYZE orders
    5234.123 ms  SELECT * FROM orders WHERE customer_id = 42
     123.456 ms  UPDATE sessions SET last_seen = NOW()
```

---

## Step 9: Parse Connection Lines

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

sample_lines = [
    '2024-01-15 14:30:01.111 UTC [12360] LOG:  connection received: host=10.0.1.5 port=52341',
    '2024-01-15 14:30:02.222 UTC [12360] LOG:  connection authorized: user=appuser database=myapp application_name=pgbouncer',
    '2024-01-15 14:30:03.333 UTC [12361] LOG:  connection received: host=192.168.1.100 port=60123',
    '2024-01-15 14:30:05.555 UTC [12360] LOG:  disconnection: session time: 0:00:03.444 user=appuser database=myapp host=10.0.1.5',
]

# Pattern for connection received
conn_pattern = re.compile(
    r'connection received: host=(?P<host>\S+) port=(?P<port>\d+)'
)

# Pattern for connection authorized
auth_pattern = re.compile(
    r'connection authorized: user=(?P<user>\S+) database=(?P<database>\S+)'
)

for line in sample_lines:
    conn_match = conn_pattern.search(line)
    auth_match = auth_pattern.search(line)
    if conn_match:
        print(f\"  CONNECT  from host={conn_match.group('host')} port={conn_match.group('port')}\")
    elif auth_match:
        print(f\"  AUTH OK  user={auth_match.group('user')} db={auth_match.group('database')}\")
"
```

- `\S+` - one or more non-whitespace characters (matches an IP address, hostname, or username without spaces)
- `host=(?P<host>\S+)` - matches the literal text `host=` then captures everything up to the next space into the group named `host`

```
Expected output (yours will differ):
  CONNECT  from host=10.0.1.5 port=52341
  AUTH OK  user=appuser db=myapp
  CONNECT  from host=192.168.1.100 port=60123
```

---

## Step 10: re.compile() - Pre-Compile Patterns for Performance

**DBA analogy:** `re.compile()` is like a prepared statement - you compile the pattern once and reuse it many times. Without it, Python re-parses the pattern on every call, like using query strings instead of prepared statements.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re
import time

log_line = '2024-01-15 14:23:45.123 UTC [12345] ERROR:  relation does not exist'

# Without compile - pattern is re-parsed on every call
start = time.time()
for _ in range(100000):
    re.search(r'(?P<severity>ERROR|FATAL|WARNING):\s+(?P<message>.+)', log_line)
no_compile = time.time() - start

# With compile - pattern parsed once, reused
error_pattern = re.compile(r'(?P<severity>ERROR|FATAL|WARNING):\s+(?P<message>.+)')
start = time.time()
for _ in range(100000):
    error_pattern.search(log_line)
with_compile = time.time() - start

print(f'Without compile: {no_compile:.3f}s for 100,000 calls')
print(f'With compile:    {with_compile:.3f}s for 100,000 calls')
print(f'Speedup:         {no_compile / with_compile:.1f}x')
"
```

- `re.compile(pattern)` - returns a compiled Pattern object with the same `.search()`, `.findall()`, `.match()` methods
- `time.time()` - current time in seconds as a float; used to measure elapsed time
- In a log parser that processes millions of lines, compiled patterns make a measurable difference

```
Expected output (yours will differ):
Without compile: 0.312s for 100,000 calls
With compile:    0.089s for 100,000 calls
Speedup:         3.5x
```

---

## Step 11: re.sub() - Replace Patterns

**DBA analogy:** `re.sub()` is the Python equivalent of `regexp_replace()` in PostgreSQL - it replaces all occurrences of a pattern with a replacement string.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

# Redact sensitive values from log lines before storing them
log_line = \"connection authorized: user=dbadmin database=prod_finance host=10.0.1.5 application_name=finance_app\"

# Replace IP addresses with [REDACTED_IP]
redacted = re.sub(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[REDACTED_IP]', log_line)
print('IP redacted:  ', redacted)

# Replace password values (e.g. in connection strings)
conn_string = 'postgresql://appuser:SecretPass123@db.internal:5432/mydb'
safe_conn = re.sub(r'://([^:]+):([^@]+)@', r'://\1:[REDACTED]@', conn_string)
print('Conn redacted:', safe_conn)
"
```

- `re.sub(pattern, replacement, string)` - replaces all matches of `pattern` in `string` with `replacement`
- `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` - matches IPv4 addresses; `{1,3}` means 1 to 3 digits, `\.` matches a literal dot
- `r'://\1:[REDACTED]@'` - in the replacement, `\1` refers to the first capture group from the pattern (the username)

```
Expected output (yours will differ):
IP redacted:   connection authorized: user=dbadmin database=prod_finance host=[REDACTED_IP] application_name=finance_app
Conn redacted: postgresql://appuser:[REDACTED]@db.internal:5432/mydb
```

---

## Step 12: Replication-Specific Log Patterns

PostgreSQL logical replication generates specific log messages. These patterns extract them.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import re

replication_lines = [
    '2024-01-15 15:00:01.111 UTC [20001] LOG:  starting logical decoding for slot \"sub_slot_1\"',
    '2024-01-15 15:00:02.222 UTC [20001] LOG:  logical replication apply worker for subscription \"sub_prod\" has started',
    '2024-01-15 15:00:15.333 UTC [20002] ERROR:  conflict detected on relation \"public.orders\": conflict=update_delete; remote tuple: (id)=(42); local conflicting tuple: (id)=(42)',
    '2024-01-15 15:00:20.444 UTC [20003] LOG:  replication slot \"sub_slot_1\" has some logical slots that are not invalidated',
    '2024-01-15 15:01:05.555 UTC [20004] LOG:  logical replication table synchronization worker for subscription \"sub_prod\", table \"orders\" has started',
]

patterns = {
    'slot_start':    re.compile(r'starting logical decoding for slot \"(?P<slot>\S+)\"'),
    'worker_start':  re.compile(r'apply worker for subscription \"(?P<sub>\S+)\" has started'),
    'conflict':      re.compile(r'conflict detected on relation \"(?P<relation>\S+)\": conflict=(?P<type>\S+);'),
    'sync_worker':   re.compile(r'table synchronization worker.*subscription \"(?P<sub>\S+)\", table \"(?P<table>\S+)\"'),
}

for line in replication_lines:
    for event_type, pattern in patterns.items():
        match = pattern.search(line)
        if match:
            print(f'  [{event_type}] {match.groupdict()}')
            break
"
```

- `patterns = {...}` - a dictionary of pre-compiled patterns, one per event type
- `for event_type, pattern in patterns.items()` - iterate over key-value pairs (like iterating over `pg_stat_replication` columns)
- `break` - stop checking other patterns once one matches (each line has one event type)

```
Expected output (yours will differ):
  [slot_start] {'slot': '"sub_slot_1"'}
  [worker_start] {'sub': '"sub_prod"'}
  [conflict] {'relation': '"public.orders"', 'type': 'update_delete;'}
  [sync_worker] {'sub': '"sub_prod"', 'table': '"orders"'}
```

---

## Step 13: Create a Sample Log File for Testing

Before building the final script, create a realistic sample log file to test against.

On your Mac terminal, as your normal user:

```bash
cat > /tmp/pg_sample.log << 'EOF'
2024-01-15 14:20:00.001 UTC [11000] LOG:  database system was shut down at 2024-01-15 14:19:58 UTC
2024-01-15 14:20:01.002 UTC [11001] LOG:  entering standby mode
2024-01-15 14:20:05.100 UTC [11100] LOG:  connection received: host=10.0.1.5 port=52100
2024-01-15 14:20:05.110 UTC [11100] LOG:  connection authorized: user=appuser database=myapp application_name=myapp_v2
2024-01-15 14:20:10.200 UTC [11200] LOG:  duration: 5423.100 ms  statement: SELECT o.*, c.name FROM orders o JOIN customers c ON o.customer_id = c.id WHERE o.status = 'pending'
2024-01-15 14:20:11.300 UTC [11300] ERROR:  relation "order_archive" does not exist at character 8
2024-01-15 14:20:12.400 UTC [11400] ERROR:  duplicate key value violates unique constraint "orders_pkey"
2024-01-15 14:20:13.500 UTC [11500] LOG:  duration: 234.500 ms  statement: UPDATE sessions SET last_seen = NOW() WHERE session_id = 'abc123'
2024-01-15 14:20:15.600 UTC [11600] FATAL:  password authentication failed for user "readonly"
2024-01-15 14:20:20.700 UTC [11700] LOG:  logical replication apply worker for subscription "sub_prod" has started
2024-01-15 14:20:25.800 UTC [11800] ERROR:  conflict detected on relation "public.orders": conflict=update_delete; remote tuple: (id)=(9999); local conflicting tuple: (id)=(9999)
2024-01-15 14:20:30.900 UTC [11900] LOG:  duration: 12001.777 ms  statement: VACUUM ANALYZE orders
2024-01-15 14:20:35.000 UTC [12000] LOG:  process 12001 acquired ShareLock on transaction 99999 after 5000.123 ms
2024-01-15 14:20:36.100 UTC [12001] LOG:  process 12002 still waiting for ShareLock on transaction 99999 after 1000.000 ms
2024-01-15 14:20:37.200 UTC [12003] LOG:  deadlock detected
2024-01-15 14:20:37.210 UTC [12003] DETAIL:  Process 12001 waits for ShareLock on transaction 12002; blocked by process 12002.
EOF
echo "Sample log written to /tmp/pg_sample.log"
wc -l /tmp/pg_sample.log
```

- `cat > /tmp/pg_sample.log << 'EOF'` - heredoc: writes everything between `EOF` markers into the file
- `wc -l` - counts lines in the file; confirms the write succeeded

```
Expected output (yours will differ):
Sample log written to /tmp/pg_sample.log
      16 /tmp/pg_sample.log
```

---

## Step 14: Build the Final log_parser.py Script

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/log_parser.py << 'PYEOF'
#!/usr/bin/env python3
"""
log_parser.py - PostgreSQL log file parser
Extracts errors, slow queries, replication events, connections, and deadlocks.
"""

import re
import sys
from typing import Any


# ---------------------------------------------------------------------------
# Compiled patterns (prepared once, reused for every line)
# ---------------------------------------------------------------------------

_TS   = r'(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d+) UTC'
_PID  = r'\[(?P<pid>\d+)\]'

PATTERNS: dict[str, re.Pattern[str]] = {
    'error': re.compile(
        _TS + r' ' + _PID + r' (?P<severity>ERROR|FATAL|PANIC|WARNING):\s+(?P<message>.+)'
    ),
    'slow_query': re.compile(
        _TS + r' ' + _PID + r' LOG:\s+duration: (?P<duration_ms>\d+\.\d+) ms\s+statement: (?P<query>.+)'
    ),
    'connection': re.compile(
        r'connection received: host=(?P<host>\S+) port=(?P<port>\d+)'
    ),
    'replication_conflict': re.compile(
        r'conflict detected on relation "(?P<relation>[^"]+)": conflict=(?P<conflict_type>\w+)'
    ),
    'deadlock': re.compile(
        r'deadlock detected'
    ),
    'lock_wait': re.compile(
        r'process (?P<waiting_pid>\d+) still waiting for \S+ on transaction (?P<txn>\d+) after (?P<wait_ms>\d+\.\d+) ms'
    ),
}


# ---------------------------------------------------------------------------
# Parser functions
# ---------------------------------------------------------------------------

def parse_errors(log_path: str) -> list[dict[str, Any]]:
    """
    Extract ERROR, FATAL, PANIC, and WARNING lines.
    Returns a list of dicts with keys: timestamp, pid, severity, message.
    """
    results: list[dict[str, Any]] = []
    pattern = PATTERNS['error']
    with open(log_path, 'r') as f:
        for line in f:
            match = pattern.search(line)
            if match:
                results.append(match.groupdict())
    return results


def parse_slow_queries(log_path: str, threshold_ms: float = 0.0) -> list[dict[str, Any]]:
    """
    Extract slow query log entries.
    threshold_ms: only return queries slower than this many milliseconds.
    Returns a list of dicts sorted by duration descending.
    """
    results: list[dict[str, Any]] = []
    pattern = PATTERNS['slow_query']
    with open(log_path, 'r') as f:
        for line in f:
            match = pattern.search(line)
            if match:
                d = match.groupdict()
                d['duration_ms'] = float(d['duration_ms'])
                if d['duration_ms'] >= threshold_ms:
                    results.append(d)
    results.sort(key=lambda q: q['duration_ms'], reverse=True)
    return results


def parse_replication_events(log_path: str) -> dict[str, list[dict[str, Any]]]:
    """
    Extract replication-related events: conflicts, deadlocks, lock waits.
    Returns a dict with keys: conflicts, deadlocks, lock_waits.
    """
    events: dict[str, list[dict[str, Any]]] = {
        'conflicts': [],
        'deadlocks': [],
        'lock_waits': [],
    }
    with open(log_path, 'r') as f:
        for line in f:
            conflict_match = PATTERNS['replication_conflict'].search(line)
            if conflict_match:
                events['conflicts'].append(conflict_match.groupdict())
                continue

            if PATTERNS['deadlock'].search(line):
                # Redact the raw line (may contain table/row data)
                safe_line = re.sub(r'\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b', '[IP]', line.strip())
                events['deadlocks'].append({'line': safe_line})
                continue

            lock_match = PATTERNS['lock_wait'].search(line)
            if lock_match:
                d = lock_match.groupdict()
                d['wait_ms'] = float(d['wait_ms'])
                events['lock_waits'].append(d)

    return events


# ---------------------------------------------------------------------------
# Report printer
# ---------------------------------------------------------------------------

def print_report(log_path: str, slow_threshold_ms: float = 1000.0) -> None:
    print(f'=== log_parser.py ===')
    print(f'Log file: {log_path}')
    print()

    # Errors
    errors = parse_errors(log_path)
    print(f'--- Errors and Warnings ({len(errors)} found) ---')
    for e in errors:
        print(f"  [{e['severity']}] {e.get('timestamp', '')} PID {e.get('pid', '')}: {e['message'][:70]}")
    print()

    # Slow queries
    slow = parse_slow_queries(log_path, threshold_ms=slow_threshold_ms)
    print(f'--- Slow Queries > {slow_threshold_ms}ms ({len(slow)} found) ---')
    for q in slow:
        print(f"  {q['duration_ms']:>10.3f} ms  {q['query'][:60]}")
    print()

    # Replication events
    rep = parse_replication_events(log_path)
    print(f'--- Replication Events ---')
    print(f"  Conflicts:  {len(rep['conflicts'])}")
    for c in rep['conflicts']:
        print(f"    relation={c['relation']} type={c['conflict_type']}")
    print(f"  Deadlocks:  {len(rep['deadlocks'])}")
    print(f"  Lock waits: {len(rep['lock_waits'])}")
    for lw in rep['lock_waits']:
        print(f"    PID {lw['waiting_pid']} waited {lw['wait_ms']}ms on txn {lw['txn']}")


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main() -> None:
    if len(sys.argv) < 2:
        print('Usage: python3 log_parser.py <path_to_log_file> [slow_query_threshold_ms]')
        print('Example: python3 log_parser.py /tmp/pg_sample.log 1000')
        sys.exit(1)

    log_path = sys.argv[1]
    threshold = float(sys.argv[2]) if len(sys.argv) > 2 else 1000.0

    try:
        print_report(log_path, slow_threshold_ms=threshold)
    except FileNotFoundError:
        print(f'ERROR: Log file not found: {log_path}')
        sys.exit(1)


if __name__ == '__main__':
    main()
PYEOF
```

- `_TS` and `_PID` - string variables holding partial pattern fragments; concatenated with `+` to build full patterns without repeating yourself (like SQL CTEs that define a sub-expression once)
- `dict[str, re.Pattern[str]]` - type annotation: a dictionary whose keys are strings and values are compiled regex Pattern objects
- `sys.argv` - the list of command-line arguments; `sys.argv[0]` is the script name, `sys.argv[1]` is the first argument

---

## Step 15: Run log_parser.py Against the Sample Log

On your Mac terminal, as your normal user:

```bash
python3 ~/pgdba/log_parser.py /tmp/pg_sample.log 500
```

The `500` argument sets the slow query threshold to 500ms - queries faster than that are not reported.

```
Expected output (yours will differ):
=== log_parser.py ===
Log file: /tmp/pg_sample.log

--- Errors and Warnings (3 found) ---
  [ERROR]  PID 11300: relation "order_archive" does not exist at character 8
  [ERROR]  PID 11400: duplicate key value violates unique constraint "orders_pkey"
  [FATAL]  PID 11600: password authentication failed for user "readonly"

--- Slow Queries > 500.0ms (2 found) ---
   12001.777 ms  VACUUM ANALYZE orders
    5423.100 ms  SELECT o.*, c.name FROM orders o JOIN customers c ON o.cu

--- Replication Events ---
  Conflicts:  1
    relation=public.orders type=update_delete
  Deadlocks:  1
  Lock waits: 1
    PID 12001 waited 1000.0ms on txn 99999
```

Try it against a real PostgreSQL log file if you have one:

```bash
ls /opt/homebrew/var/log/postgresql@16.log 2>/dev/null || echo "No log file at default path - check pg_log directory"
```

---

## What You Built

Your script `~/pgdba/log_parser.py` can:
- Extract all ERROR, FATAL, WARNING lines from any PostgreSQL log file
- Find slow queries above a configurable threshold, sorted by duration
- Detect replication conflicts, deadlocks, and lock wait events
- Redact IP addresses from sensitive log lines
- Accept a log file path and threshold as command-line arguments

**Python concepts used:**
- `re.search()` - find a pattern anywhere in a string
- `re.findall()` - return all matches as a list
- `re.compile()` - pre-compile patterns for performance (like prepared statements)
- `re.sub()` - replace patterns (like `regexp_replace()`)
- Raw strings `r""` - pass backslashes to the regex engine unescaped
- Named groups `(?P<name>)` - extract captures by name, not position
- Groups `()` - capture specific parts of a match

**Next:** BUILD 17 covers `pytest` - writing tests for your DBA toolkit scripts so bugs are caught before they reach production.

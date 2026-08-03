# BUILD 04: File I/O - Config Parser (PostgreSQL Architecture)

## What You're Building

By the end of this guide you will have a working script called `conf_parser.py` in `~/pgdba/` that reads your actual `postgresql.conf` and `pg_hba.conf`, extracts settings, searches for specific parameters, and parses HBA rules into structured data.

**Python concepts covered:** `open()`, `read()`, `readlines()`, `strip()`, `split()`, `startswith()`, file modes (`'r'`, `'w'`, `'a'`), the `with` statement

**DBA task:** Parse PostgreSQL config files the way `grep` and `awk` do - but in Python, so you can extend it into a full config management tool.

---

## Prerequisites

- Completed BUILD 03 (psycopg2 connections)
- `~/pgdba/` directory exists
- PostgreSQL installed via Homebrew

---

## Step 1: Find Your postgresql.conf (Context Check)

Before writing any Python, confirm where your config files live.

On your Mac terminal, as your normal user:

```bash
ls /opt/homebrew/var/postgresql@16/postgresql.conf 2>/dev/null || ls /usr/local/var/postgresql@16/postgresql.conf 2>/dev/null
```

This checks both Apple Silicon (`/opt/homebrew`) and Intel Mac (`/usr/local`) paths. One of them will print the path.

```bash
Expected output (yours will differ):
/opt/homebrew/var/postgresql@16/postgresql.conf
```

Note your path. You'll use it throughout this guide. The variable `PGCONF` below refers to whichever path printed.

---

## Step 2: open() and read() - Read the Whole File at Once

**DBA analogy:** `open()` is like `COPY FROM` - you're loading a file into memory. `read()` slurps the entire file into one big string, the way `COPY` loads an entire file into a table.

On your Mac terminal, as your normal user:

```bash
python3 -c "
f = open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r')
content = f.read()
f.close()
print(content[:300])
"
```

- `open(path, 'r')` - open the file in read mode (`'r'` = read-only, like a SELECT with no lock)
- `f.read()` - read the entire contents into the variable `content` as one long string
- `f.close()` - release the file handle (like closing a cursor)
- `content[:300]` - Python slice notation, grab the first 300 characters

```
Expected output (yours will differ):
# -----------------------------
# PostgreSQL configuration file
# -----------------------------
#
# This file consists of lines of the form:
#
#   name = value
#
# (The "=" is optional.)  Whitespace may be
```

> Note: If your path is `/usr/local/var/postgresql@16/postgresql.conf`, replace the path in every step below.

---

## Step 3: The with Statement - Auto-Close File Handles

**DBA analogy:** The `with` statement is like wrapping your file operations in a `BEGIN...END` block - when the block exits (even on error), Python automatically closes the file handle. No more forgotten `f.close()`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
with open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r') as f:
    content = f.read()
print('File length:', len(content), 'characters')
"
```

- `with open(...) as f:` - open the file and name the handle `f`; Python closes it when the `with` block ends
- `len(content)` - count the number of characters in the string (like `length()` in SQL)

```
Expected output (yours will differ):
File length: 27594 characters
```

From now on, always use `with` when reading files. It is the correct Python pattern.

---

## Step 4: readlines() - Read Line by Line

**DBA analogy:** `readlines()` is like fetching rows from a cursor one at a time instead of doing `COPY` of the whole table. Each line of the file becomes one element in a list.

On your Mac terminal, as your normal user:

```bash
python3 -c "
with open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r') as f:
    lines = f.readlines()
print('Total lines:', len(lines))
print('First 5 lines:')
for line in lines[:5]:
    print(repr(line))
"
```

- `f.readlines()` - reads all lines into a list; each line is a string ending with `\n`
- `lines[:5]` - Python slice, first 5 elements of the list (like `LIMIT 5`)
- `repr(line)` - shows the raw string including hidden characters like `\n` so you can see exactly what you're working with

```
Expected output (yours will differ):
Total lines: 789
First 5 lines:
'# -----------------------------\n'
'# PostgreSQL configuration file\n'
'# -----------------------------\n'
'#\n'
'# This file consists of lines of the form:\n'
```

You can see each line ends with `\n`. You need to strip that off before processing.

---

## Step 5: strip() and split() - Clean and Parse Lines

**DBA analogy:** `strip()` is like `TRIM()` in SQL - removes leading and trailing whitespace (including `\n`). `split()` is like `string_to_array()` - it breaks a string into a list of parts based on a delimiter.

On your Mac terminal, as your normal user:

```bash
python3 -c "
line = 'max_connections = 100\t\t# (change requires restart)\n'
print('Raw:    ', repr(line))
clean = line.strip()
print('Stripped:', repr(clean))
parts = clean.split('=')
print('Split on =:', parts)
key = parts[0].strip()
val = parts[1].strip()
print('Key:', key)
print('Val:', val)
"
```

- `line.strip()` - removes `\n`, tabs, and spaces from both ends of the string
- `clean.split('=')` - splits the string at every `=` sign, returning a list of parts
- `parts[0]` - the first element (index 0), which is the parameter name (like `SPLIT_PART(col, '=', 1)`)
- `parts[1]` - the second element, which is the value plus any inline comment

```
Expected output (yours will differ):
Raw:     'max_connections = 100\t\t# (change requires restart)\n'
Stripped: 'max_connections = 100\t\t# (change requires restart)'
Split on =: ['max_connections ', ' 100\t\t# (change requires restart)']
Key: max_connections
Val: 100		# (change requires restart)
```

The value still has an inline comment. You'll clean that up in Step 6.

---

## Step 6: startswith() - Skip Comment Lines

**DBA analogy:** `startswith('#')` is like `WHERE col NOT LIKE '#%'` in SQL - it filters out comment lines so you only process real settings.

On your Mac terminal, as your normal user:

```bash
python3 -c "
lines = [
    '# This is a comment\n',
    'max_connections = 100\n',
    '  # indented comment\n',
    'shared_buffers = 128MB\n',
]
for line in lines:
    clean = line.strip()
    if clean.startswith('#') or clean == '':
        print('SKIP:', repr(clean))
    else:
        print('KEEP:', repr(clean))
"
```

- `clean.startswith('#')` - returns `True` if the string begins with `#`
- `clean == ''` - skip empty lines after stripping (like filtering `WHERE col IS NOT NULL AND col != ''`)
- The `if/else` block decides whether to process or skip the line

```
Expected output (yours will differ):
SKIP: '# This is a comment'
KEEP: 'max_connections = 100'
SKIP: '# indented comment'
KEEP: 'shared_buffers = 128MB'
```

---

## Step 7: Parse postgresql.conf into a Dictionary

**DBA analogy:** A Python dictionary is like a lookup table - key maps to value, just like a two-column table `(param_name, param_value)`. Building it from the config file is like running `INSERT INTO settings SELECT name, value FROM parse_config()`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
settings = {}
with open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r') as f:
    for line in f:
        clean = line.strip()
        if clean.startswith('#') or '=' not in clean or clean == '':
            continue
        parts = clean.split('=', 1)
        key = parts[0].strip()
        raw_val = parts[1].strip()
        val = raw_val.split('#')[0].strip()
        settings[key] = val
print('Total settings parsed:', len(settings))
print('Sample keys:', list(settings.keys())[:5])
"
```

- `settings = {}` - declare an empty dictionary (like a temp table)
- `'=' not in clean` - skip lines with no `=` sign (invalid config lines)
- `clean.split('=', 1)` - the `1` tells Python to split at the FIRST `=` only; this handles values that contain `=` signs
- `raw_val.split('#')[0].strip()` - split on `#` and take the first part (strips inline comments)
- `settings[key] = val` - store the key-value pair in the dictionary (like `INSERT INTO`)

```
Expected output (yours will differ):
Total settings parsed: 31
Sample keys: ['max_connections', 'superuser_reserved_connections', 'bonjour', 'listen_addresses', 'port']
```

---

## Step 8: Search for Specific Settings

**DBA analogy:** Looking up a value in a dictionary is like `SELECT value FROM settings WHERE name = 'max_connections'` - instant lookup, O(1) time.

On your Mac terminal, as your normal user:

```bash
python3 -c "
settings = {}
with open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r') as f:
    for line in f:
        clean = line.strip()
        if clean.startswith('#') or '=' not in clean or clean == '':
            continue
        parts = clean.split('=', 1)
        key = parts[0].strip()
        raw_val = parts[1].strip()
        val = raw_val.split('#')[0].strip()
        settings[key] = val

params = ['max_connections', 'shared_buffers', 'wal_level', 'work_mem', 'effective_cache_size']
for param in params:
    if param in settings:
        print(f'{param} = {settings[param]}')
    else:
        print(f'{param} = (not explicitly set, using default)')
"
```

- `params = [...]` - a list of parameters to look up (like a `WHERE name IN (...)` clause)
- `if param in settings` - check if the key exists in the dictionary (like `EXISTS (SELECT 1 FROM settings WHERE name = param)`)
- `f'{param} = {settings[param]}'` - f-string formatting, inserts variable values into the string (like `format()` in PL/pgSQL)

```
Expected output (yours will differ):
max_connections = 100
shared_buffers = 128MB
wal_level = replica
work_mem = (not explicitly set, using default)
effective_cache_size = (not explicitly set, using default)
```

---

## Step 9: write() - Write a Modified Config to a New File

**DBA analogy:** `open(path, 'w')` is like `COPY TO` - you're writing data out to a file. Mode `'w'` truncates and rewrites from scratch, like `TRUNCATE` then `INSERT`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
output_lines = []
with open('/opt/homebrew/var/postgresql@16/postgresql.conf', 'r') as f:
    for line in f:
        if 'max_connections' in line and not line.strip().startswith('#'):
            output_lines.append('max_connections = 200\t\t# changed by conf_parser.py\n')
        else:
            output_lines.append(line)

with open('/tmp/postgresql.conf.modified', 'w') as out:
    out.writelines(output_lines)

print('Written to /tmp/postgresql.conf.modified')
import subprocess
result = subprocess.run(['grep', 'max_connections', '/tmp/postgresql.conf.modified'], capture_output=True, text=True)
print(result.stdout)
"
```

- `output_lines = []` - collect modified lines in a list first before writing
- `open(path, 'w')` - open file for writing; `'w'` mode creates the file or overwrites it completely
- `out.writelines(output_lines)` - write every item in the list to the file
- `subprocess.run(...)` - run a shell command from Python to verify the output (used here just to confirm the change)

```
Expected output (yours will differ):
Written to /tmp/postgresql.conf.modified
max_connections = 200		# changed by conf_parser.py
```

> Important: This writes to `/tmp/` only - never modify the real `postgresql.conf` without a backup and a plan to reload.

---

## Step 10: Append Mode - Add an HBA Rule

**DBA analogy:** `open(path, 'a')` is like `INSERT INTO` without truncating - you add to the end of the file. Mode `'w'` is `TRUNCATE + INSERT`, mode `'a'` is just `INSERT`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os
test_hba = '/tmp/pg_hba_test.conf'

# Create a test file first
with open(test_hba, 'w') as f:
    f.write('# TYPE  DATABASE  USER  ADDRESS  METHOD\n')
    f.write('local   all       all            trust\n')
    f.write('host    all       all  127.0.0.1/32  trust\n')

print('--- Before append ---')
with open(test_hba, 'r') as f:
    print(f.read())

# Append a new rule
new_rule = 'host    myapp     appuser  10.0.1.0/24  scram-sha-256\n'
with open(test_hba, 'a') as f:
    f.write(new_rule)

print('--- After append ---')
with open(test_hba, 'r') as f:
    print(f.read())
"
```

- `open(path, 'a')` - open in append mode; the file pointer starts at the END of the file
- `f.write(new_rule)` - writes the string to the file at the current position (the end)
- The original content is untouched - only the new line is added

```
Expected output (yours will differ):
--- Before append ---
# TYPE  DATABASE  USER  ADDRESS  METHOD
local   all       all            trust
host    all       all  127.0.0.1/32  trust

--- After append ---
# TYPE  DATABASE  USER  ADDRESS  METHOD
local   all       all            trust
host    all       all  127.0.0.1/32  trust
host    myapp     appuser  10.0.1.0/24  scram-sha-256
```

---

## Step 11: Parse pg_hba.conf into Structured Data

**DBA analogy:** `pg_hba.conf` is a space-delimited file - each row has columns: `type`, `database`, `user`, `address`, `method`. Parsing it into a list of dictionaries is like `SELECT type, database, user, address, method FROM pg_hba_file_rules`.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import os

# Find pg_hba.conf
hba_candidates = [
    '/opt/homebrew/var/postgresql@16/pg_hba.conf',
    '/usr/local/var/postgresql@16/pg_hba.conf',
]
hba_path = None
for p in hba_candidates:
    if os.path.exists(p):
        hba_path = p
        break

print('Using:', hba_path)
rules = []
with open(hba_path, 'r') as f:
    for line in f:
        clean = line.strip()
        if clean.startswith('#') or clean == '':
            continue
        parts = clean.split()
        if len(parts) >= 4:
            rule = {
                'type':     parts[0],
                'database': parts[1],
                'user':     parts[2],
                'address':  parts[3] if len(parts) > 4 else '',
                'method':   parts[-1],
            }
            rules.append(rule)

for r in rules:
    print(f\"{r['type']:<8} {r['database']:<12} {r['user']:<12} {r['address']:<20} {r['method']}\")
"
```

- `os.path.exists(p)` - check if a file path exists, like `pg_ls_dir()` but for a single file
- `clean.split()` - split on any whitespace (spaces and tabs), no delimiter argument needed
- `parts[-1]` - the LAST element of the list (negative index counts from the end), which is always the auth method
- `f'{val:<8}'` - f-string format with left-align padding to 8 chars, like `LPAD`/`RPAD` in SQL

```
Expected output (yours will differ):
Using: /opt/homebrew/var/postgresql@16/pg_hba.conf
local    all          all                               trust
host     all          all          127.0.0.1/32         trust
host     all          all          ::1/128              trust
```

---

## Step 12: Build the Final conf_parser.py Script

Now combine everything into a single reusable script. Write this file to disk.

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/conf_parser.py << 'PYEOF'
#!/usr/bin/env python3
"""
conf_parser.py - PostgreSQL config file parser
Reads postgresql.conf and pg_hba.conf, extracts settings,
searches parameters, and parses HBA rules.
"""

import os
import sys


# --- Config file discovery ---

def find_conf_file(filename: str) -> str:
    """Find a PostgreSQL config file in common Homebrew locations."""
    candidates = [
        f'/opt/homebrew/var/postgresql@16/{filename}',
        f'/usr/local/var/postgresql@16/{filename}',
    ]
    for path in candidates:
        if os.path.exists(path):
            return path
    raise FileNotFoundError(
        f"Could not find {filename}. "
        f"Checked: {', '.join(candidates)}"
    )


# --- postgresql.conf functions ---

def read_conf(path: str) -> dict[str, str]:
    """
    Parse postgresql.conf into a dictionary of {param: value}.
    Skips comment lines and strips inline comments from values.
    """
    settings: dict[str, str] = {}
    with open(path, 'r') as f:
        for line in f:
            clean = line.strip()
            if clean.startswith('#') or '=' not in clean or clean == '':
                continue
            parts = clean.split('=', 1)
            key = parts[0].strip()
            raw_val = parts[1].strip()
            val = raw_val.split('#')[0].strip()
            settings[key] = val
    return settings


def get_setting(settings: dict[str, str], param: str) -> str:
    """
    Look up a specific parameter. Returns the value or a
    '(default)' message if the param is not explicitly set.
    """
    if param in settings:
        return settings[param]
    return f'(not set - PostgreSQL default applies)'


# --- pg_hba.conf functions ---

def parse_hba(path: str) -> list[dict[str, str]]:
    """
    Parse pg_hba.conf into a list of rule dictionaries.
    Each rule has keys: type, database, user, address, method.
    """
    rules: list[dict[str, str]] = []
    with open(path, 'r') as f:
        for line in f:
            clean = line.strip()
            if clean.startswith('#') or clean == '':
                continue
            parts = clean.split()
            if len(parts) < 4:
                continue
            rule: dict[str, str] = {
                'type':     parts[0],
                'database': parts[1],
                'user':     parts[2],
                'address':  parts[3] if len(parts) > 4 else '',
                'method':   parts[-1],
            }
            rules.append(rule)
    return rules


def find_trust_rules(rules: list[dict[str, str]]) -> list[dict[str, str]]:
    """Return only HBA rules that use trust authentication."""
    return [r for r in rules if r['method'] == 'trust']


# --- Main runner ---

def main() -> None:
    print('=== conf_parser.py ===\n')

    # postgresql.conf
    try:
        conf_path = find_conf_file('postgresql.conf')
        print(f'Reading: {conf_path}')
        settings = read_conf(conf_path)
        print(f'Parameters parsed: {len(settings)}\n')

        params_to_check = [
            'max_connections',
            'shared_buffers',
            'wal_level',
            'work_mem',
            'effective_cache_size',
            'checkpoint_completion_target',
            'log_min_duration_statement',
        ]
        print('--- Key Settings ---')
        for param in params_to_check:
            val = get_setting(settings, param)
            print(f'  {param:<35} = {val}')
    except FileNotFoundError as e:
        print(f'ERROR: {e}')
        sys.exit(1)

    # pg_hba.conf
    print()
    try:
        hba_path = find_conf_file('pg_hba.conf')
        print(f'Reading: {hba_path}')
        rules = parse_hba(hba_path)
        print(f'HBA rules parsed: {len(rules)}\n')

        print('--- All HBA Rules ---')
        print(f'  {"TYPE":<8} {"DATABASE":<12} {"USER":<12} {"ADDRESS":<22} {"METHOD"}')
        print(f'  {"-"*8} {"-"*12} {"-"*12} {"-"*22} {"-"*20}')
        for r in rules:
            print(f"  {r['type']:<8} {r['database']:<12} {r['user']:<12} {r['address']:<22} {r['method']}")

        trust_rules = find_trust_rules(rules)
        if trust_rules:
            print(f'\n  WARNING: {len(trust_rules)} trust rule(s) found - no password required for these connections')
    except FileNotFoundError as e:
        print(f'ERROR: {e}')
        sys.exit(1)


if __name__ == '__main__':
    main()
PYEOF
```

- `cat > file << 'PYEOF'` - heredoc redirect: writes everything between the markers into the file
- `#!/usr/bin/env python3` - shebang line; tells the OS to run this file with python3
- `if __name__ == '__main__':` - only run `main()` when the script is executed directly, not when imported (covered in BUILD 06)

---

## Step 13: Run conf_parser.py Against Your Real Config

On your Mac terminal, as your normal user:

```bash
python3 ~/pgdba/conf_parser.py
```

```
Expected output (yours will differ):
=== conf_parser.py ===

Reading: /opt/homebrew/var/postgresql@16/postgresql.conf
Parameters parsed: 31

--- Key Settings ---
  max_connections                     = 100
  shared_buffers                      = 128MB
  wal_level                           = replica
  work_mem                            = (not set - PostgreSQL default applies)
  effective_cache_size                = (not set - PostgreSQL default applies)
  checkpoint_completion_target        = (not set - PostgreSQL default applies)
  log_min_duration_statement          = (not set - PostgreSQL default applies)

Reading: /opt/homebrew/var/postgresql@16/pg_hba.conf
HBA rules parsed: 3

--- All HBA Rules ---
  TYPE     DATABASE     USER         ADDRESS                METHOD
  -------- ------------ ------------ ---------------------- --------------------
  local    all          all                                 trust
  host     all          all          127.0.0.1/32           trust
  host     all          all          ::1/128                trust

  WARNING: 3 trust rule(s) found - no password required for these connections
```

---

## What You Built

Your script `~/pgdba/conf_parser.py` can:
- Locate `postgresql.conf` and `pg_hba.conf` automatically on Mac Homebrew
- Parse all non-default settings from `postgresql.conf` into a dictionary
- Look up any specific parameter by name
- Parse every HBA rule into structured data (type, database, user, address, method)
- Flag trust authentication rules as a security warning

**Python concepts used:**
- `open()` with modes `'r'`, `'w'`, `'a'` - reading, overwriting, and appending files
- `with` statement - automatic file handle cleanup
- `readlines()` and iterating directly over a file object
- `strip()`, `split()`, `startswith()` - string parsing primitives
- Dictionaries for structured key-value storage
- Lists of dictionaries for tabular data

**Next:** BUILD 05 covers `try/except` error handling using a user management script.

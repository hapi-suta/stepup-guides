# BUILD 01: Variables, Types, and Print - Pre-Install Checker

**What you will build:** `~/pgdba/install_checker.py` - a script that validates a system is ready for PostgreSQL installation. It checks Python version, OS, required paths, port availability, and disk space.

**Python concepts covered:** variables, int, float, str, bool, print(), f-strings, type(), type conversion

**Time to complete:** ~45 minutes

---

## Prerequisites

- Mac terminal open
- Python 3 installed (comes with macOS 12+)
- PostgreSQL installed locally (used to verify the checker works)

---

## Step 1: Create the ~/pgdba/ working directory

This is your Python DBA workspace. Every script in this module lives here.

On your **Mac terminal**, as your **normal user**:

```bash
mkdir -p ~/pgdba
```

This flag means:
- `-p` - create parent directories as needed, no error if it already exists

Verify it was created:

```bash
ls -la ~/pgdba
```

Expected output (yours will differ):

```
total 0
drwxr-xr-x   2 postgres  staff   64 Jun 13 10:00 .
drwxr-xr-x  45 postgres  staff  1440 Jun 13 10:00 ..
```

---

## Step 2: Check your Python version

Before writing any code, confirm Python 3 is available.

On your **Mac terminal**, as your **normal user**:

```bash
python3 --version
```

Expected output (yours will differ):

```
Python 3.12.3
```

You need version 3.8 or higher. If this command fails, install Python via Homebrew: `brew install python3`.

---

## Step 3: Variables - store configuration values

In PL/pgSQL you write `DECLARE my_var TEXT := 'value';` before using a variable. In Python, there is no DECLARE keyword - you just assign directly. Python figures out the type automatically.

On your **Mac terminal**, run this one-liner to try it out:

```bash
python3 -c "
host = 'localhost'
port = 5432
data_dir = '/opt/homebrew/var/postgresql@17'  # adjust to your version/path
print(host)
print(port)
print(data_dir)
"
```

What this does: assigns three variables and prints each one. The `=` sign is assignment (same as `:=` in PL/pgSQL).

Expected output (yours will differ):

```
localhost
5432
/usr/local/var/postgresql@16
```

---

## Step 4: Data types - int, float, str, bool

In PostgreSQL you declare column types explicitly: `port INTEGER`, `min_disk NUMERIC`, `host_name TEXT`, `is_installed BOOLEAN`. Python has the same types but uses different names, and it infers them automatically.

| PostgreSQL type | Python type | Example            |
|-----------------|-------------|--------------------|
| INTEGER         | int         | `port = 5432`      |
| NUMERIC / REAL  | float       | `min_disk_gb = 10.0` |
| TEXT / VARCHAR  | str         | `data_dir = '/var/...'` |
| BOOLEAN         | bool        | `is_installed = True` |

On your **Mac terminal**:

```bash
python3 -c "
port = 5432
min_disk_gb = 10.0
data_dir = '/opt/homebrew/var/postgresql@17'  # adjust to your version/path
is_installed = True

print(port)
print(min_disk_gb)
print(data_dir)
print(is_installed)
"
```

Expected output (yours will differ):

```
5432
10.0
/usr/local/var/postgresql@16
True
```

Note: Python booleans are `True` and `False` (capital T and F). Lowercase `true` is an error.

---

## Step 5: type() - inspect a variable's type

In PostgreSQL, `pg_typeof(expression)` tells you the data type of a value. In Python, `type(variable)` does the same thing.

On your **Mac terminal**:

```bash
python3 -c "
port = 5432
min_disk_gb = 10.0
data_dir = '/opt/homebrew/var/postgresql@17'  # adjust to your version/path
is_installed = True

print(type(port))
print(type(min_disk_gb))
print(type(data_dir))
print(type(is_installed))
"
```

Expected output (yours will differ):

```
<class 'int'>
<class 'float'>
<class 'str'>
<class 'bool'>
```

The output format `<class 'int'>` is just how Python displays type information. The part you care about is the name inside the quotes.

---

## Step 6: Type conversion - casting between types

In PostgreSQL you use `CAST(value AS type)` or the shorthand `value::type`. In Python, you wrap the value in the target type: `int()`, `str()`, `float()`.

On your **Mac terminal**:

```bash
python3 -c "
# Start with a string (like reading a config file value)
port_as_string = '5432'
min_disk_as_string = '10.5'

# Convert to the types we actually need - like CAST in SQL
port = int(port_as_string)
min_disk_gb = float(min_disk_as_string)
port_label = str(port)

print(type(port_as_string), port_as_string)
print(type(port), port)
print(type(min_disk_gb), min_disk_gb)
print(type(port_label), port_label)
"
```

Expected output (yours will differ):

```
<class 'str'> 5432
<class 'int'> 5432
<class 'float'> 10.5
<class 'str'> 5432
```

This matters when reading config files or environment variables - everything comes in as a string and you cast it to the right type, exactly like you would in SQL ETL work.

---

## Step 7: f-strings - format output with variable values

In PostgreSQL, you concatenate strings with `||`: `'Port: ' || port::TEXT`. In Python, f-strings do the same thing more cleanly. Put `f` before the opening quote, then use `{variable_name}` inside the string.

On your **Mac terminal**:

```bash
python3 -c "
host = 'localhost'
port = 5432
data_dir = '/opt/homebrew/var/postgresql@17'  # adjust to your version/path
min_disk_gb = 10.0

print(f'Host:      {host}')
print(f'Port:      {port}')
print(f'Data dir:  {data_dir}')
print(f'Min disk:  {min_disk_gb} GB')
"
```

Expected output (yours will differ):

```
Host:      localhost
Port:      5432
Data dir:  /usr/local/var/postgresql@16
Min disk:  10.0 GB
```

The `{variable}` syntax inside f-strings replaces the variable with its value at runtime - same idea as `format()` or `RAISE NOTICE` with `%` placeholders in PL/pgSQL.

---

## Step 8: Check if PostgreSQL is installed using subprocess

The `subprocess` module lets Python run shell commands - like calling `psql`, `pg_isready`, or any OS command from inside a script. Think of it as running a command from within PL/pgSQL using `EXECUTE`.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess

# Run 'which postgres' the same way you would in the terminal
result = subprocess.run(['which', 'postgres'], capture_output=True, text=True)

print(f'Return code: {result.returncode}')
print(f'Output:      {result.stdout.strip()}')
print(f'Found:       {result.returncode == 0}')
"
```

What each piece does:
- `import subprocess` - loads the module (like `\dx` to see installed extensions, you load what you need)
- `subprocess.run(...)` - runs the command and waits for it to finish
- `capture_output=True` - captures stdout and stderr instead of printing them directly
- `text=True` - returns output as a string instead of raw bytes
- `result.returncode` - 0 means success, non-zero means failure (same as `$?` in bash)
- `.strip()` - removes trailing newline from the output

Expected output (yours will differ):

```
Return code: 0
Output:      /usr/local/bin/postgres
Found:       True
```

---

## Step 9: Check port availability and disk space

Before installing PostgreSQL, you should verify port 5432 is not already in use and there is enough disk space.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess
import shutil

# Check if port 5432 is in use
lsof_result = subprocess.run(
    ['lsof', '-i', f'TCP:5432'],
    capture_output=True,
    text=True
)
port_in_use = lsof_result.returncode == 0

# Check disk space on the home directory
total, used, free = shutil.disk_usage('/')
free_gb = free / (1024 ** 3)

print(f'Port 5432 in use: {port_in_use}')
print(f'Free disk space:  {free_gb:.1f} GB')
print(f'Disk OK (>=10GB): {free_gb >= 10.0}')
"
```

What each piece does:
- `shutil.disk_usage('/')` - returns total, used, and free bytes for the filesystem at that path
- `free / (1024 ** 3)` - converts bytes to gigabytes (1024^3 = 1,073,741,824)
- `:.1f` inside the f-string - formats the float to 1 decimal place (like `ROUND(value, 1)` in SQL)

Expected output (yours will differ):

```
Port 5432 in use: True
Free disk space:  245.3 GB
Disk OK (>=10GB): True
```

Port in use = True is expected if PostgreSQL is already running. The checker will report this as a finding, not necessarily a failure.

---

## Step 10: Check Python version programmatically

The script itself needs to verify the Python running it is new enough. The `sys` module exposes runtime information about Python itself.

On your **Mac terminal**:

```bash
python3 -c "
import sys

major = sys.version_info.major
minor = sys.version_info.minor
patch = sys.version_info.micro
version_string = f'{major}.{minor}.{patch}'

is_supported = major == 3 and minor >= 8

print(f'Python version: {version_string}')
print(f'Major:          {major}')
print(f'Minor:          {minor}')
print(f'Supported:      {is_supported}')
"
```

What each piece does:
- `sys.version_info` - a tuple with major, minor, micro (patch) version numbers
- `major == 3 and minor >= 8` - boolean expression combining two comparisons with `and`

Expected output (yours will differ):

```
Python version: 3.12.3
Major:          3
Minor:          12
Supported:      True
```

---

## Step 11: Combine everything into install_checker.py

Now write the complete script to a file. You will use `vi` to create it.

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/install_checker.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
import subprocess
import shutil
import sys
import platform

# -------------------------------------------------------
# Configuration - change these to match your environment
# -------------------------------------------------------
HOST = 'localhost'
PORT = 5432
# Auto-detect: Apple Silicon uses /opt/homebrew, Intel uses /usr/local
import glob
pg_dirs = glob.glob('/opt/homebrew/var/postgresql@*') + glob.glob('/usr/local/var/postgresql@*')
DATA_DIR = pg_dirs[0] if pg_dirs else '/opt/homebrew/var/postgresql@16'
MIN_DISK_GB = 10.0
MIN_PYTHON_MINOR = 8

# -------------------------------------------------------
# Check 1: Python version
# -------------------------------------------------------
major = sys.version_info.major
minor = sys.version_info.minor
patch = sys.version_info.micro
python_version = f'{major}.{minor}.{patch}'
python_ok = major == 3 and minor >= MIN_PYTHON_MINOR

# -------------------------------------------------------
# Check 2: Operating system
# -------------------------------------------------------
os_name = platform.system()
os_version = platform.mac_ver()[0] if os_name == 'Darwin' else platform.version()

# -------------------------------------------------------
# Check 3: Is PostgreSQL binary on PATH?
# -------------------------------------------------------
pg_result = subprocess.run(['which', 'postgres'], capture_output=True, text=True)
pg_found = pg_result.returncode == 0
pg_path = pg_result.stdout.strip() if pg_found else 'not found'

# -------------------------------------------------------
# Check 4: Is port 5432 available (or already in use)?
# -------------------------------------------------------
lsof_result = subprocess.run(
    ['lsof', '-i', f'TCP:{PORT}'],
    capture_output=True,
    text=True
)
port_in_use = lsof_result.returncode == 0

# -------------------------------------------------------
# Check 5: Data directory exists?
# -------------------------------------------------------
import os
data_dir_exists = os.path.isdir(DATA_DIR)

# -------------------------------------------------------
# Check 6: Disk space
# -------------------------------------------------------
total_bytes, used_bytes, free_bytes = shutil.disk_usage('/')
free_gb = free_bytes / (1024 ** 3)
disk_ok = free_gb >= MIN_DISK_GB

# -------------------------------------------------------
# Report
# -------------------------------------------------------
print('=' * 55)
print('  PostgreSQL Pre-Install Checker')
print('=' * 55)
print(f'  Host:            {HOST}')
print(f'  Port:            {PORT}')
print(f'  Data dir:        {DATA_DIR}')
print('-' * 55)
print(f'  Python version:  {python_version}  {"OK" if python_ok else "FAIL - need 3.8+"}')
print(f'  OS:              {os_name} {os_version}')
print(f'  postgres binary: {pg_path}  {"OK" if pg_found else "FAIL - not installed"}')
print(f'  Port {PORT}:      {"IN USE (PG already running?)" if port_in_use else "available"}')
print(f'  Data dir exists: {data_dir_exists}')
print(f'  Free disk:       {free_gb:.1f} GB  {"OK" if disk_ok else f"FAIL - need {MIN_DISK_GB} GB"}')
print('-' * 55)

all_ok = python_ok and pg_found and disk_ok
print(f'  Overall status:  {"READY" if all_ok else "ISSUES FOUND - review above"}')
print('=' * 55)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 12: Run the final script

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/install_checker.py
```

Expected output (yours will differ):

```
=======================================================
  PostgreSQL Pre-Install Checker
=======================================================
  Host:            localhost
  Port:            5432
  Data dir:        /usr/local/var/postgresql@16
-------------------------------------------------------
  Python version:  3.12.3  OK
  OS:              Darwin 14.5.0
  postgres binary: /usr/local/bin/postgres  OK
  Port 5432:       IN USE (PG already running?)
  Data dir exists: True
  Free disk:       245.3 GB  OK
-------------------------------------------------------
  Overall status:  READY
=======================================================
```

---

## What you built

You now have `~/pgdba/install_checker.py` - a reusable pre-flight script you can run before any PostgreSQL installation. It demonstrates:

| Python concept  | DBA analogy                          |
|-----------------|--------------------------------------|
| Variables       | `DECLARE` block in PL/pgSQL          |
| int / float / str / bool | Column data types in a table |
| `type()`        | `pg_typeof()`                        |
| `int()` / `str()` / `float()` | `CAST(value AS type)` |
| f-strings       | `'text' \|\| variable::TEXT` in SQL  |
| `subprocess.run()` | Running shell commands from PL/pgSQL via `EXECUTE` |

Next: BUILD 02 - Control Flow: Instance Controller

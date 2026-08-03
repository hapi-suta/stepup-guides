# BUILD 01: Your First Python Program

**Module:** module00a-python-from-scratch
**Time:** 30-40 minutes
**Prerequisites:** Mac terminal access, zero Python experience

You already think in SQL. This guide teaches Python by connecting every concept to something you already know from PostgreSQL. Every command runs as a copy-paste `python3 -c "..."` in your Mac terminal - no IDE, no setup fuss.

---

## Step 1: Verify Python 3 Is Installed

Open your Mac terminal and run:

```bash
python3 --version
```

Expected output (yours will differ):
```
Python 3.11.6
```

If you see `Python 3.x.x` (any version 3.8+), you are good. If not, install it with `brew install python3`.

---

## Step 2: The print() Function - Your First Output

**SQL analogy:** `SELECT 'Hello, DBA!' ;` - a SELECT with no FROM table. You are just producing output.

Run this in your terminal:

```bash
python3 -c "print('Hello, DBA!')"
```

Expected output:
```
Hello, DBA!
```

`print()` sends text to the screen. The parentheses hold what you want to print. The quotes define a text value (a string).

You can print numbers without quotes:

```bash
python3 -c "print(42)"
```

Expected output:
```
42
```

You can print multiple items separated by commas:

```bash
python3 -c "print('Connections:', 150)"
```

Expected output:
```
Connections: 150
```

---

## Step 3: Variables - Storing Values

**SQL analogy:** In PL/pgSQL you write `DECLARE db_name VARCHAR := 'production';`. Python is simpler - no DECLARE, no type keyword.

```bash
python3 -c "
db_name = 'production'
max_connections = 200
print(db_name)
print(max_connections)
"
```

Expected output:
```
production
200
```

Key differences from SQL:
- No DECLARE keyword needed
- No semicolons at the end of lines
- No type declaration - Python figures out the type automatically
- Single `=` for assignment (in SQL, `:=` is used in PL/pgSQL)

---

## Step 4: Data Types - int, float, str, bool

**SQL analogy:**

| Python Type | SQL Type | Example |
|-------------|----------|---------|
| `int` | INTEGER | `max_connections = 200` |
| `float` | NUMERIC / DOUBLE PRECISION | `cpu_usage = 78.5` |
| `str` | VARCHAR / TEXT | `db_name = 'production'` |
| `bool` | BOOLEAN | `is_primary = True` |

```bash
python3 -c "
max_connections = 200
cpu_usage = 78.5
db_name = 'production'
is_primary = True

print(max_connections)
print(cpu_usage)
print(db_name)
print(is_primary)
"
```

Expected output:
```
200
78.5
production
True
```

Notice: Python booleans are `True` and `False` (capitalized). In SQL they are `true` / `false` or `TRUE` / `FALSE`.

---

## Step 5: Type Checking with type()

**SQL analogy:** `SELECT pg_typeof(42);` returns `integer`. Python's `type()` does the same thing.

```bash
python3 -c "
max_connections = 200
cpu_usage = 78.5
db_name = 'production'
is_primary = True

print(type(max_connections))
print(type(cpu_usage))
print(type(db_name))
print(type(is_primary))
"
```

Expected output:
```
<class 'int'>
<class 'float'>
<class 'str'>
<class 'bool'>
```

`<class 'int'>` means the value is an integer. Think of `class` as Python's word for "type."

---

## Step 6: Type Conversion - int(), float(), str()

**SQL analogy:** `SELECT CAST('200' AS INTEGER);` or `SELECT '200'::INTEGER;`. Python uses function calls instead of CAST.

```bash
python3 -c "
# String to integer - like CAST('200' AS INTEGER)
connections_str = '200'
connections_int = int(connections_str)
print(connections_int + 50)

# Integer to string - like CAST(200 AS VARCHAR)
port = 5432
port_str = str(port)
print('Port: ' + port_str)

# String to float - like CAST('78.5' AS NUMERIC)
cpu_str = '78.5'
cpu_float = float(cpu_str)
print(cpu_float)
"
```

Expected output:
```
250
Port: 5432
78.5
```

Why this matters: if you read a value from a config file, it comes in as a string. You must convert it before doing math. This is just like how `psql` returns everything as text and your application must cast.

---

## Step 7: f-strings for Formatted Output

**SQL analogy:** In SQL you concatenate with `||`: `SELECT 'DB: ' || db_name || ' has ' || num_connections || ' connections';`. Python's f-strings are cleaner.

Put an `f` before the opening quote, then use `{}` to embed variables:

```bash
python3 -c "
db_name = 'production'
connections = 150
cpu = 78.5

print(f'Database: {db_name}')
print(f'Connections: {connections}')
print(f'CPU Usage: {cpu}%')
print(f'{db_name} has {connections} active connections using {cpu}% CPU')
"
```

Expected output:
```
Database: production
Connections: 150
CPU Usage: 78.5%
production has 150 active connections using 78.5% CPU
```

You can also do math inside the curly braces:

```bash
python3 -c "
used = 150
total = 200
print(f'Usage: {used}/{total} ({used/total*100}%)')
"
```

Expected output:
```
Usage: 150/200 (75.0%)
```

---

## Step 8: Comments with #

**SQL analogy:** `-- this is a SQL comment`. Python uses `#` instead of `--`.

```bash
python3 -c "
# This is a comment - Python ignores it
db_name = 'production'  # inline comment after code
print(db_name)
"
```

Expected output:
```
production
```

Comments exist to explain WHY, not WHAT. `# set db_name to production` is useless. `# production DB has stricter connection limits` is useful.

---

## Step 9: Getting User Input with input()

**SQL analogy:** Think of `\prompt` in psql, which asks the user to type something.

```bash
python3 -c "
name = input('Enter database name: ')
print(f'You entered: {name}')
"
```

When you run this, it will pause and wait for you to type something, then press Enter. The value you type is stored in `name` as a string.

Note: `input()` always returns a string. If you need a number, you must convert it with `int()` or `float()`. We will not use `input()` much in the AI track - most of our data comes from files and APIs.

---

## Step 10: Math Operators

**SQL analogy:** SQL arithmetic works almost identically, with a few differences.

| Python | SQL Equivalent | Description | Example |
|--------|---------------|-------------|---------|
| `+` | `+` | Addition | `5 + 3` = 8 |
| `-` | `-` | Subtraction | `10 - 4` = 6 |
| `*` | `*` | Multiplication | `6 * 7` = 42 |
| `/` | `/` (on floats) | Division (always returns float) | `10 / 3` = 3.333... |
| `//` | `/` (on integers) | Integer division (floor) | `10 // 3` = 3 |
| `%` | `%` or `MOD()` | Modulo (remainder) | `10 % 3` = 1 |
| `**` | `power()` | Exponentiation | `2 ** 10` = 1024 |

```bash
python3 -c "
total_connections = 200
active = 150

# Division always returns a float in Python
print(f'Ratio: {active / total_connections}')

# Integer division floors the result
print(f'Integer division: {10 // 3}')

# Modulo - remainder after division
print(f'Remainder: {10 % 3}')

# Power - like power() in SQL
print(f'2^10 = {2 ** 10}')

# Practical: percentage calculation
pct_used = (active / total_connections) * 100
print(f'Connection usage: {pct_used}%')
"
```

Expected output:
```
Ratio: 0.75
Integer division: 3
Remainder: 1
2^10 = 1024
Connection usage: 75.0%
```

Key gotcha: In Python 3, `/` ALWAYS returns a float, even `10 / 2` gives `5.0`. In PostgreSQL, `SELECT 10 / 3;` returns `3` (integer division) because both operands are integers. Python requires `//` for that behavior.

---

## What You Learned

| Concept | Python | SQL Equivalent |
|---------|--------|----------------|
| Output | `print('hello')` | `SELECT 'hello';` |
| Variable | `x = 42` | `DECLARE x INTEGER := 42;` |
| Integer | `int` | `INTEGER` |
| Float | `float` | `NUMERIC` / `DOUBLE PRECISION` |
| String | `str` | `VARCHAR` / `TEXT` |
| Boolean | `bool` (`True`/`False`) | `BOOLEAN` (`true`/`false`) |
| Type check | `type(x)` | `pg_typeof(x)` |
| Type convert | `int()`, `float()`, `str()` | `CAST(x AS type)` |
| Format string | `f'value: {x}'` | `'value: ' \|\| x` |
| Comment | `# comment` | `-- comment` |
| Division | `/` (float), `//` (integer) | `/` (depends on operand types) |
| Power | `**` | `power()` |
| Modulo | `%` | `%` or `MOD()` |

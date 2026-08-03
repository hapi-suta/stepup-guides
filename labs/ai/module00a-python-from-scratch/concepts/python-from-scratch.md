# Concepts Reference: Python from Scratch

**Module:** module00a-python-from-scratch
**Purpose:** Quick reference for everything covered in BUILD 01-04

---

## Python vs SQL Quick Reference

| Python | SQL | Notes |
|--------|-----|-------|
| `x = 42` | `DECLARE x INTEGER := 42;` | No type declaration needed in Python |
| `print(x)` | `SELECT x;` / `RAISE NOTICE` | Output to screen |
| `type(x)` | `pg_typeof(x)` | Check the type of a value |
| `int('42')` | `CAST('42' AS INTEGER)` | Convert string to integer |
| `str(42)` | `CAST(42 AS VARCHAR)` | Convert integer to string |
| `float('3.14')` | `CAST('3.14' AS NUMERIC)` | Convert string to float |
| `f'hello {x}'` | `'hello ' \|\| x` | String formatting |
| `# comment` | `-- comment` | Single-line comment |
| `==` | `=` (comparison) | Equality test |
| `=` | `:=` (PL/pgSQL) | Assignment |
| `!=` | `!=` or `<>` | Not equal |
| `and` / `or` / `not` | `AND` / `OR` / `NOT` | Boolean operators |
| `if/elif/else` | `CASE WHEN/THEN/ELSE/END` | Conditional branching |
| `for i in range(n)` | `SELECT generate_series(0,n-1)` | Counted loop |
| `for x in list` | Cursor `LOOP` | Iterate over items |
| `while cond:` | `WHILE cond LOOP` | Conditional loop |
| `break` | `EXIT` (PL/pgSQL) | Exit loop early |
| `continue` | `CONTINUE` (PL/pgSQL) | Skip to next iteration |
| `x in list` | `x IN (...)` | Membership test |
| `def func():` | `CREATE FUNCTION func()` | Define a function |
| `return val` | `RETURN val` | Return from function |
| `None` | `NULL` | Absence of value |
| `x is None` | `x IS NULL` | Check for None/NULL |
| `len(x)` | `length(x)` / `count(*)` | Length/count |
| `max()` / `min()` | `GREATEST()` / `LEAST()` | Max/min of values |
| `sum(list)` | `SUM(col)` | Sum |
| `sorted(list)` | `ORDER BY` | Sort |
| `abs(x)` | `ABS(x)` | Absolute value |
| `round(x, n)` | `ROUND(x, n)` | Round |
| `open(f, 'r')` | `COPY FROM` | Read file |
| `open(f, 'w')` | `COPY TO` | Write file |
| `open(f, 'a')` | `INSERT INTO log` | Append to file |
| `try/except` | `BEGIN...EXCEPTION WHEN...END` | Error handling |
| `raise Error()` | `RAISE EXCEPTION` | Throw error |
| `"""docstring"""` | `COMMENT ON FUNCTION` | Document function |

---

## Data Types

| Python Type | SQL Type(s) | Example | Falsy Value |
|-------------|-------------|---------|-------------|
| `int` | `INTEGER`, `BIGINT` | `42`, `-7`, `0` | `0` |
| `float` | `NUMERIC`, `DOUBLE PRECISION` | `3.14`, `-0.5` | `0.0` |
| `str` | `VARCHAR`, `TEXT` | `'hello'`, `""` | `''` (empty) |
| `bool` | `BOOLEAN` | `True`, `False` | `False` |
| `None` | `NULL` | `None` | `None` |
| `list` | Array / result set | `[1, 2, 3]` | `[]` (empty) |
| `dict` | Single row / hstore | `{'key': 'val'}` | `{}` (empty) |

---

## Operators Quick Reference

### Arithmetic

| Operator | Name | Example | Result |
|----------|------|---------|--------|
| `+` | Addition | `5 + 3` | `8` |
| `-` | Subtraction | `10 - 4` | `6` |
| `*` | Multiplication | `6 * 7` | `42` |
| `/` | Division (float) | `10 / 3` | `3.333...` |
| `//` | Integer division | `10 // 3` | `3` |
| `%` | Modulo | `10 % 3` | `1` |
| `**` | Power | `2 ** 10` | `1024` |

### Comparison

| Operator | Meaning |
|----------|---------|
| `==` | Equal to |
| `!=` | Not equal to |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |
| `is` | Identity (use for `None`) |
| `in` | Membership test |

### Boolean

| Operator | Meaning |
|----------|---------|
| `and` | Both must be True |
| `or` | At least one True |
| `not` | Invert boolean |

---

## Control Flow Patterns

### if / elif / else

```python
if condition1:
    # runs when condition1 is True
elif condition2:
    # runs when condition1 is False AND condition2 is True
else:
    # runs when all conditions are False
```

### for loop

```python
# Over a range of numbers
for i in range(5):        # 0, 1, 2, 3, 4
for i in range(1, 6):     # 1, 2, 3, 4, 5
for i in range(0, 10, 2): # 0, 2, 4, 6, 8

# Over a list
for item in my_list:
    # process each item
```

### while loop

```python
while condition:
    # runs as long as condition is True
    # MUST change something so condition eventually becomes False
```

---

## Function Patterns

### Basic function

```python
def function_name(param1, param2):
    """Docstring explaining what the function does."""
    # function body
    return result
```

### Default parameters

```python
def connect(host, port=5432, dbname='postgres'):
    # port defaults to 5432, dbname defaults to 'postgres'
    pass
```

### Multiple return values

```python
def get_stats():
    return cpu, memory, disk  # returns a tuple

cpu, mem, disk = get_stats()  # unpack into variables
```

---

## File I/O Patterns

### Read entire file

```python
with open('/path/to/file', 'r') as f:
    content = f.read()
```

### Read line by line

```python
with open('/path/to/file', 'r') as f:
    for line in f:
        line = line.strip()
        # process each line
```

### Write file (overwrites)

```python
with open('/path/to/file', 'w') as f:
    f.write('content here\n')
```

### Append to file

```python
with open('/path/to/file', 'a') as f:
    f.write('new line appended\n')
```

### Parse key=value config

```python
config = {}
with open('config.conf', 'r') as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        key, value = line.split('=', 1)
        config[key.strip()] = value.strip()
```

---

## Error Handling Patterns

### Basic try/except

```python
try:
    risky_operation()
except SpecificError as e:
    print(f'Error: {e}')
```

### Multiple exception types

```python
try:
    value = int(user_input)
except ValueError:
    print('Not a valid number')
except TypeError:
    print('Wrong type provided')
```

### try/except/finally

```python
try:
    result = operation()
except SomeError:
    handle_error()
finally:
    cleanup()  # ALWAYS runs
```

### Common exceptions

| Exception | When It Happens | SQL Equivalent |
|-----------|----------------|----------------|
| `FileNotFoundError` | File does not exist | Relation does not exist |
| `ValueError` | Bad value conversion | Invalid CAST |
| `TypeError` | Wrong type in operation | Operator type mismatch |
| `ZeroDivisionError` | Division by zero | Division by zero |
| `KeyError` | Dict key not found | Column does not exist |
| `IndexError` | List index out of range | Array subscript out of range |
| `PermissionError` | No file access | Insufficient privileges |

---

## String Methods Quick Reference

| Method | Description | SQL Equivalent |
|--------|-------------|----------------|
| `s.strip()` | Remove whitespace from both ends | `TRIM(s)` |
| `s.lower()` | Convert to lowercase | `LOWER(s)` |
| `s.upper()` | Convert to uppercase | `UPPER(s)` |
| `s.startswith('x')` | Check if starts with 'x' | `s LIKE 'x%'` |
| `s.endswith('x')` | Check if ends with 'x' | `s LIKE '%x'` |
| `s.split(',')` | Split into list at commas | `string_to_array(s, ',')` |
| `s.replace('a', 'b')` | Replace all 'a' with 'b' | `REPLACE(s, 'a', 'b')` |
| `','.join(list)` | Join list into string | `array_to_string(arr, ',')` |
| `s.find('x')` | Find position of 'x' (-1 if not found) | `POSITION('x' IN s)` |
| `len(s)` | String length | `LENGTH(s)` |

---

## Truthy and Falsy Values

Values that evaluate to `False` in boolean context:

| Value | Type | Note |
|-------|------|------|
| `False` | bool | The boolean False |
| `0` | int | Zero |
| `0.0` | float | Zero |
| `''` | str | Empty string |
| `None` | NoneType | Python's NULL |
| `[]` | list | Empty list |
| `{}` | dict | Empty dictionary |

Everything else is truthy. This means `if my_list:` checks "is the list non-empty?" without needing `if len(my_list) > 0:`.

---

## Common Gotchas for DBAs

1. **`=` vs `==`**: `=` is assignment, `==` is comparison. SQL uses `=` for both.
2. **`/` always returns float**: `10 / 2` gives `5.0`, not `5`. Use `//` for integer division.
3. **Indentation matters**: Python uses indentation instead of BEGIN/END. A missing indent is a syntax error.
4. **Zero-based indexing**: `list[0]` is the first element. SQL arrays start at 1.
5. **`is None` not `== None`**: Always use `is` to check for None, just like `IS NULL` in SQL.
6. **Strings are immutable**: `s.upper()` returns a NEW string. `s` is unchanged. You must do `s = s.upper()`.
7. **`input()` returns strings**: Always convert with `int()` or `float()` before math.
8. **`True`/`False` are capitalized**: Not `true`/`false` like SQL.

# INTERVIEW 01: Python Fundamentals Interview Questions

**Module:** module00a-python-from-scratch
**Purpose:** Prepare for Python fundamentals questions in AI/ML engineering interviews
**Context:** These questions are framed for someone transitioning from DBA work into AI engineering

---

## Question 1: What is the difference between `==` and `is` in Python?

**What the interviewer is looking for:**
Understanding of value equality vs identity (object reference). This tests whether you know Python's object model beyond surface syntax.

**Strong answer:**
`==` checks if two values are equal - it compares the contents. `is` checks if two variables point to the exact same object in memory - it compares identity.

For example, two separate lists can have the same contents (`==` returns True) but be different objects (`is` returns False):

```python
a = [1, 2, 3]
b = [1, 2, 3]
print(a == b)  # True - same contents
print(a is b)  # False - different objects in memory
```

The one place you MUST use `is` instead of `==` is when checking for `None`:

```python
if x is None:    # correct - like IS NULL in SQL
if x == None:    # works but wrong style - like using = NULL in SQL
```

This is exactly like PostgreSQL where `WHERE x = NULL` always returns no rows (because NULL = NULL is unknown), but `WHERE x IS NULL` works correctly. Python does not have this NULL-trap with `== None`, but the convention exists to prevent subtle bugs with objects that override the `==` operator.

**Weak answer:**
"They're basically the same thing. I always use `==`."

---

## Question 2: Explain mutable vs immutable types in Python

**What the interviewer is looking for:**
Understanding that some Python types can be changed in place and others cannot. This matters for function arguments, dictionary keys, and avoiding bugs.

**Strong answer:**
Immutable types cannot be changed after creation. If you "modify" them, Python creates a new object. Mutable types can be changed in place.

| Category | Types | DBA Analogy |
|----------|-------|-------------|
| Immutable | `int`, `float`, `str`, `bool`, `tuple` | Like a read-only view or a value in a WHERE clause - you can use it but not change it |
| Mutable | `list`, `dict`, `set` | Like a table - you can INSERT, UPDATE, DELETE rows |

```python
# String is immutable
name = "production"
name.upper()       # returns "PRODUCTION" but does NOT change name
print(name)        # still "production"
name = name.upper() # you must reassign to keep the change

# List is mutable
servers = ["pg1", "pg2"]
servers.append("pg3")  # modifies the list in place
print(servers)         # ["pg1", "pg2", "pg3"] - changed!
```

Why this matters: if you pass a mutable object (like a list) to a function, the function can modify the original. This is like passing a table name to a function that does `DELETE FROM` on it - the caller's data is affected. With immutable types, the original is always safe.

**Weak answer:**
"Mutable means you can change it, immutable means you can't. I don't really think about it much."

---

## Question 3: What happens when you divide by zero in Python vs SQL?

**What the interviewer is looking for:**
Understanding of exception handling and how Python differs from SQL in error behavior. Shows you can think across language boundaries.

**Strong answer:**
In Python, dividing by zero raises a `ZeroDivisionError` exception and the program crashes immediately unless you catch it with `try/except`:

```python
# Python - crashes
result = 10 / 0  # ZeroDivisionError: division by zero

# Python - handled
try:
    result = 10 / 0
except ZeroDivisionError:
    result = 0
```

In PostgreSQL, the behavior depends on context:
- In a plain query: `SELECT 10 / 0;` raises `ERROR: division by zero` and the entire transaction is aborted
- In PL/pgSQL: you can catch it with `EXCEPTION WHEN division_by_zero THEN`
- With `NULLIF`: `SELECT 10 / NULLIF(0, 0);` returns NULL instead of erroring

The key difference is that PostgreSQL aborts the whole transaction on an unhandled error, while Python only crashes the current program. In both languages, the best practice is to prevent the error rather than catch it - check for zero before dividing, or use `NULLIF` / an `if` guard.

**Weak answer:**
"Both give an error. You just wrap it in a try/catch."

---

## Question 4: How does Python's `for` loop differ from a SQL cursor?

**What the interviewer is looking for:**
Understanding of iteration patterns and the ability to compare paradigms. This is relevant in AI work where you process datasets row by row vs in bulk.

**Strong answer:**
Python's `for` loop and SQL cursors both process items one at a time, but they differ in several important ways:

| Aspect | Python `for` | SQL Cursor |
|--------|-------------|------------|
| Declaration | None needed | `DECLARE cursor_name CURSOR FOR query` |
| Opening | Automatic | `OPEN cursor_name` |
| Fetching | Automatic (one per iteration) | `FETCH NEXT FROM cursor_name` |
| Closing | Automatic | `CLOSE cursor_name` (or auto on transaction end) |
| Memory | Loads items as needed | Depends on cursor type (WITH HOLD, scrollable, etc.) |
| Performance | Normal iteration pattern | Usually discouraged in SQL - set-based is faster |

The biggest conceptual difference: in SQL, cursors are a last resort. Set-based operations (`UPDATE ... WHERE`, `JOIN`, `GROUP BY`) are almost always better. In Python, `for` loops are the normal way to process data. However, in AI/ML work with libraries like NumPy and pandas, you often avoid Python loops in favor of vectorized operations - which is philosophically similar to SQL's preference for set-based operations.

```python
# Python loop - normal and fine
for server in servers:
    check_health(server)

# SQL cursor - usually a code smell
DECLARE cur CURSOR FOR SELECT * FROM servers;
LOOP
    FETCH NEXT FROM cur INTO server_rec;
    EXIT WHEN NOT FOUND;
    PERFORM check_health(server_rec);
END LOOP;
-- Better: SELECT check_health(s) FROM servers s;
```

**Weak answer:**
"They're the same thing, just different syntax."

---

## Question 5: When would you use `try/except` vs `if/else` for error handling?

**What the interviewer is looking for:**
Understanding of EAFP (Easier to Ask Forgiveness than Permission) vs LBYL (Look Before You Leap) - two error handling philosophies. Shows mature thinking about code design.

**Strong answer:**
Python has two approaches:

**LBYL (Look Before You Leap)** - check before acting, using `if/else`:
```python
if denominator != 0:
    result = numerator / denominator
else:
    result = 0
```

**EAFP (Easier to Ask Forgiveness than Permission)** - try it and handle failure, using `try/except`:
```python
try:
    result = numerator / denominator
except ZeroDivisionError:
    result = 0
```

When to use which:

| Use `if/else` when... | Use `try/except` when... |
|----------------------|------------------------|
| The check is simple and cheap | The check would be expensive or redundant |
| The error condition is common/expected | The error is rare (exceptional) |
| You are validating user input | You are accessing external resources (files, network, APIs) |
| You want to be explicit about what you check | Multiple things could go wrong at once |

The DBA analogy: `if/else` is like adding a `WHERE EXISTS` check before an `INSERT`. `try/except` is like just doing the `INSERT` and catching the unique constraint violation. If duplicates are rare, the `INSERT`-and-catch approach is faster because you avoid the extra SELECT. If duplicates are common, checking first is better.

In AI/ML engineering, `try/except` is heavily used for file I/O, API calls, and model loading - anything that involves external systems. `if/else` is used for data validation and business logic checks.

**Weak answer:**
"I always use try/except because it catches everything. I just wrap my whole program in one big try block."

(This is a red flag because it means errors are silently swallowed and debugging becomes impossible - like having a PL/pgSQL function with `EXCEPTION WHEN OTHERS THEN NULL` that hides every error.)

# Concepts: Python Fundamentals

**Read this before you touch the keyboard.** This is the vocabulary and mental model you need so the BUILD guide (Project 1) makes sense. You are a DBA moving into AI - you already think in data, sets, and types. Python is how you glue models, APIs, and databases together. It is the default language of the AI world for one reason: the libraries (the AI SDKs, data tools, web frameworks) are all Python-first.

Everything here maps to code you will actually write in `app.py` and `test_app.py`.

---

## 1. Variables and data types

A variable is a name that points at a value. Python figures out the type from the value - you do not declare it like in C or Java.

```python
name = "labdb"        # a string
port = 5432           # an integer (int)
ratio = 0.75          # a floating-point number (float)
is_primary = True     # a boolean (bool): True or False
```

The four core scalar types:

- **str** - text. Written in single or double quotes. `"cannot log in"`.
- **int** - whole numbers, any size. `10`, `-3`, `999999999`. Python integers have unlimited precision - no 32/64-bit overflow like C or Java (see: Python docs, Numeric Types).
- **float** - numbers with a decimal point. `0.34`, `3.14`. Beware: floats are approximate (IEEE 754 double precision), so never use them for money - use integers of cents or the `decimal` module.
- **bool** - `True` or `False`. Comes from comparisons: `port == 5432` gives `True`. Note `bool` is technically a subclass of `int`, so `True == 1` and `False == 0` (see: Python docs, Numeric Types).

Check a type with `type(x)`. Convert with `int("10")`, `str(10)`, `float("0.75")`. A conversion that cannot work raises an error (`int("abc")` fails) - that is a feature, not a bug, because it stops bad data early.

---

## 2. Strings

Text is the raw material of support tickets, so string handling matters.

```python
subject = "Cannot Log In"
subject.lower()            # 'cannot log in' - normalize before matching
subject.strip()            # remove leading/trailing whitespace
"login" in subject.lower() # True - substring test
f"{subject} has {len(subject)} chars"  # f-string: inserts values into text
```

- `.lower()` / `.upper()` - change case. Always lowercase before keyword matching so "Login" and "login" both match.
- `.strip()` - trims whitespace from both ends. Critical when data comes from humans or CSVs.
- `in` - tests whether one string appears inside another.
- **f-strings** (the `f"..."` form) - the modern way to build strings with values inside. You will see these in log messages and error details.

In `app.py`, `categorize()` does exactly this: `text = f"{subject} {body or ''}".lower()` then checks `if any(k in text for k in keywords)`.

---

## 3. Collections: lists, tuples, dicts, sets

| Type | Written as | Ordered | Changeable | Use for |
|------|-----------|---------|-----------|---------|
| list | `[1, 2, 3]` | yes | yes | a sequence you will add to or loop over |
| tuple | `(1, 2, 3)` | yes | no | a fixed group that should not change |
| dict | `{"key": "value"}` | yes (3.7+) | yes | look up a value by a key |
| set | `{1, 2, 3}` | no | yes | unique membership, fast "is X in here" |

```python
categories = ["auth", "billing", "bug"]     # list
categories.append("performance")            # add to it
row = {"subject": "Slow dashboard", "category": None}  # dict
row["category"]                             # look up by key -> None
unique_ids = {1, 2, 2, 3}                   # set -> {1, 2, 3}, dupes gone
```

A **dict** is the workhorse - it is exactly a JSON object, exactly a database row keyed by column name (`psycopg2`'s `RealDictCursor` hands you dicts), and exactly what a FastAPI endpoint returns. The keyword rules in `app.py` are a dict of category -> tuple of keywords. Sets are the right tool for deduplication, which you will hit in the SQL data-quality work.

---

## 4. Conditions

Code that chooses a path.

```python
if not subject:
    category = "uncategorized"
elif "login" in subject.lower():
    category = "auth"
else:
    category = "other"
```

- `if` / `elif` / `else` - test conditions top to bottom, run the first that is true.
- Comparisons: `==` equal, `!=` not equal, `<`, `>`, `<=`, `>=`.
- Combine with `and`, `or`, `not`.
- **Truthiness**: empty things are false. `""`, `[]`, `{}`, `()`, `set()`, `0`, `0.0`, `None`, and `False` are all "falsy" (see: Python docs, Truth Value Testing). That is why `if not subject:` cleanly skips blank subjects - you do not have to write `if subject == "" or subject is None`.

`None` is Python's "no value" (like SQL `NULL`). Test it with `is None` / `is not None`, never `== None`.

---

## 5. Loops

Do something for each item.

```python
for row in rows:                # loop over a list of dict rows
    counts[row["category"]] += 1

for i in range(3):              # 0, 1, 2
    print(i)
```

- `for ... in ...` - the standard loop; walks any collection.
- `range(n)` - produces `0` to `n-1`, for counting loops.
- `while condition:` - loop until a condition goes false. Used in retry loops (you will build one in USE 02).
- `break` exits a loop early; `continue` skips to the next item. `app.py` uses `continue` to skip blank-subject rows.

**Comprehensions** are compact loops that build a collection:

```python
matched = [k for k in keywords if k in text]   # list comprehension
```

Read it as "the value `k`, for each `k` in `keywords`, where `k` is in `text`".

---

## 6. Functions

A named, reusable block that takes inputs and returns an output. Functions are how you keep code testable - each does one thing, and a test can call it directly.

```python
def categorize(subject, body):
    text = f"{subject} {body or ''}".lower()
    for category, keywords in KEYWORD_RULES.items():
        if any(k in text for k in keywords):
            return category
    return "uncategorized"
```

- `def` starts a function; the name is how you call it.
- Parameters (`subject`, `body`) are inputs; `return` sends a value back.
- A function with no `return` gives back `None`.
- **Default arguments**: `def connect(host, port=5432)` - callers can omit `port`. Watch out: a default value is evaluated once, at definition time, so a mutable default like `def f(x=[])` is shared across calls - use `x=None` then set it inside instead (see: Python docs, Function definitions).
- **Keyword arguments**: call as `connect(host="x", port=5433)` for clarity.

`categorize()` is pure - same inputs always give the same output, no database, no network. Pure functions are trivial to test, which is why `test_app.py` tests it without a running database.

---

## 7. Modules and packages

- A **module** is a single `.py` file. `import os` gives you the standard-library `os` module.
- A **package** is a folder of modules (with an `__init__.py` historically).
- **The standard library** ships with Python: `os`, `json`, `logging`, `csv`, `datetime`, `unittest`. No install needed.
- **Third-party packages** come from PyPI via `pip`: `fastapi`, `psycopg2`, `pytest`, `requests`.

```python
import os                        # whole module
from collections import Counter  # one name from a module
import psycopg2.extras           # a submodule
```

Pin every third-party package with a version in `requirements.txt` (you saw `fastapi==0.115.0`). Pinning means "same versions everywhere" - your laptop, the CI runner, and Docker all install identical code, so "works on my machine" stops being a mystery. More on this in [02-software-engineering-basics.md](02-software-engineering-basics.md).

---

## 8. Error handling

Real systems fail: the database is down, a file is missing, an API times out. You handle failure explicitly instead of letting the program crash.

```python
try:
    conn = psycopg2.connect(host=DB_HOST, dbname=DB_NAME, ...)
except psycopg2.OperationalError as exc:
    raise HTTPException(status_code=503, detail=f"database unavailable: {exc}")
```

- `try:` - code that might fail.
- `except SomeError as exc:` - runs only if that specific error happened; `exc` holds the error object.
- `finally:` - always runs, error or not. `app.py` uses it to `conn.close()` so connections never leak.
- `raise` - throw an error on purpose, often after adding context.

**Rules that will save you (and are graded in SURVIVE):**

- Catch **specific** exceptions (`psycopg2.OperationalError`), not a bare `except:`. A bare catch hides bugs.
- Never silently swallow an error. At minimum, log it. Silence is how outages become mysteries.
- Add context when you re-raise: "database unavailable" is far more useful in a log than a raw stack trace 200 lines down.

---

## 9. File handling

Reading and writing files - CSVs of tickets, log files, a dead-letter file for bad rows.

```python
with open("tickets.csv") as f:
    for line in f:
        process(line)
# file is automatically closed here, even on error
```

- `open(path)` - defaults to read mode; use `open(path, "w")` to write, `"a"` to append.
- The `with` block (a **context manager**) closes the file automatically when the block ends. Always use `with` for files and database cursors so resources are released even if something throws.
- For structured data use the `csv` module, not manual `.split(",")` - real CSVs have quoted commas that break naive splitting. You will feel this pain firsthand in the SURVIVE `malformed-csv-crash` scenario.

---

## 10. Object-oriented programming (OOP)

A **class** bundles data and the functions that act on it into one type. You will use classes more than you write them at Tier 1, but you must be able to read them.

```python
class TicketClient:
    def __init__(self, base_url, api_key):   # constructor: sets up state
        self.base_url = base_url             # 'self' is this instance
        self.api_key = api_key

    def fetch(self, ticket_id):              # a method (function on the class)
        return f"{self.base_url}/tickets/{ticket_id}"

client = TicketClient("https://api.example.com", api_key="secret")
client.fetch(42)
```

- `class` defines a new type; `__init__` runs when you create an instance.
- `self` is the instance itself - the first parameter of every method.
- **Attributes** are data on the instance (`self.base_url`); **methods** are functions on it (`fetch`).

Why it matters: `FastAPI()`, `Counter()`, and your resilient API client in USE 02 are all objects. When you write `app = FastAPI()` you are creating an instance of the `FastAPI` class.

---

## 11. Type hints

Annotations that say what type a value should be. Python does not enforce them at runtime, but they document intent and let tools (and your editor) catch mistakes before you run the code.

```python
def categorize(subject: str, body: str | None) -> str:
    ...
```

- `subject: str` - subject should be a string.
- `body: str | None` - body is a string or `None` (the `X | Y` union syntax means "or", added in Python 3.10 by PEP 604; before that you wrote `Optional[str]` or `Union[str, None]`).
- `-> str` - the function returns a string.

Type hints are non-negotiable in professional code and in this program. They turn "what does this function take again?" into something you can read in one line, and they let `mypy` flag `categorize(123)` before it ever ships.

---

## 12. Logging

The professional replacement for `print()`. Logging has levels, timestamps, and can be turned up or down without editing code.

```python
import logging

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)

log.info("summary computed: %d tickets", total)
log.warning("skipped blank subject on row %s", row_id)
log.error("database unreachable: %s", exc)
```

- Levels, quietest to loudest: `DEBUG` (10) `< INFO` (20) `< WARNING` (30) `< ERROR` (40) `< CRITICAL` (50). Set `level=` to the lowest you want to see (see: Python Logging HOWTO).
- Use `%s`/`%d` placeholders with arguments, not f-strings, in log calls - the logging module defers formatting until the message is actually emitted, so the string work is skipped if the level is filtered out (see: Python Logging HOWTO).
- **Never log secrets** (passwords, API keys, tokens). A leaked key in a log file is the exact failure you fix in the `committed-secret` SURVIVE scenario.

`print()` is fine for a quick script. Logging is what you ship, because you can route it, level it, and search it.

---

## 13. Unit testing

Automated checks that a piece of code does what you expect. You will use `pytest`, the standard test runner.

```python
# test_app.py
from app import categorize

def test_login_is_auth():
    assert categorize("Cannot log in", "password reset") == "auth"

def test_unknown_is_uncategorized():
    assert categorize("How do I add a user", None) == "uncategorized"
```

- A test is a function whose name starts with `test_`.
- `assert <expression>` passes if the expression is true, fails otherwise.
- Run all tests with `python -m pytest -q`. Five dots means five passed (you saw this in BUILD Step 4).

**Why test pure functions like `categorize`?** They need no database, so tests run in milliseconds and give the same result every time - perfect for CI. You test the categorization rules here; you test the API and database wiring with integration tests later. Never advance on a red test.

---

## Vocabulary recap

- **variable / type** - a named value; Python infers the type.
- **str, int, float, bool** - the four scalar types.
- **list, tuple, dict, set** - the four collections; dict is a JSON object and a DB row.
- **None** - "no value", like SQL NULL; test with `is None`.
- **truthiness** - empty/zero/None count as false.
- **function** - named reusable block; `def`, `return`; pure functions are easy to test.
- **module / package** - a `.py` file / a folder of them; installed via `pip`, pinned in `requirements.txt`.
- **try/except/finally/raise** - explicit error handling; catch specific errors, never swallow.
- **context manager (`with`)** - auto-closes files and cursors.
- **class / self / method / attribute** - OOP building blocks.
- **type hint** - `x: str`, `-> str`; documents and enables tooling.
- **logging** - leveled, timestamped output that replaces print in production.
- **unit test / assert / pytest** - automated correctness checks.

Next: [02-software-engineering-basics.md](02-software-engineering-basics.md) - how professionals ship this code safely.

---

## References

- Python docs, Built-in Types (Numeric Types, Truth Value Testing): https://docs.python.org/3/library/stdtypes.html
- Python docs, Compound statements (function definitions, default and keyword arguments): https://docs.python.org/3/reference/compound_stmts.html
- Python Logging HOWTO (levels, deferred `%`-style formatting): https://docs.python.org/3/howto/logging.html
- PEP 604, Allow writing union types as `X | Y` (Python 3.10): https://peps.python.org/pep-0604/
- pytest documentation: https://docs.pytest.org/en/stable/

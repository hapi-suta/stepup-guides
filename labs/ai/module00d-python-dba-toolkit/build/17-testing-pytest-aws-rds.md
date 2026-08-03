# BUILD 17: Testing with pytest - Test Your Toolkit (AWS RDS)

## What You're Building

By the end of this guide you will have a `tests/` directory under `~/pgdba/` containing pytest test files for your DBA toolkit scripts - testing the config parser, user manager, and log parser without needing a live database by using mocks. You will run the full test suite with one command.

**Python concepts covered:** `assert`, `pytest` basics, test functions, fixtures, `parametrize`, mocking (`unittest.mock`), test organization, `conftest.py`

**DBA task:** Write automated tests for your DBA scripts. A bug in a backup script means data loss. A bug in a user manager script means a dropped role or wrong privilege. Tests catch these before production.

---

## Prerequisites

- Completed BUILD 16 (have `conf_parser.py`, `log_parser.py` in `~/pgdba/`)
- Python 3 installed
- `~/pgdba/` directory exists

---

## Step 1: Why Test DBA Scripts?

**DBA analogy:** You already know this mindset. You run `pg_verifybackup` to confirm backups are valid. You run `amcheck` to verify index integrity. You run `pg_dumpall` and restore to a staging server before trusting it for DR. `pytest` is the same pattern for Python scripts - a verification tool that catches problems before they matter.

A broken `conf_parser.py` might silently return wrong values, leading to a misconfigured replica. A broken `user_manager.py` might fail to enforce naming conventions and create roles with elevated privileges. Tests catch these bugs on your laptop, not in production at 3am.

On your Mac terminal, as your normal user:

```bash
ls ~/pgdba/
```

Confirm your existing toolkit scripts are there before writing tests for them.

```
Expected output (yours will differ):
conf_parser.py    log_parser.py    pg_monitor.py    user_manager.py
```

---

## Step 2: Install pytest

On your Mac terminal, as your normal user:

```bash
pip3 install pytest
```

- `pip3 install pytest` - downloads and installs the `pytest` package from PyPI
- `pytest` is not in Python's standard library, unlike `re` or `os`

```
Expected output (yours will differ):
Collecting pytest
  Downloading pytest-8.3.2-py3-none-any.whl (341 kB)
...
Successfully installed pytest-8.3.2
```

Verify the install:

```bash
python3 -m pytest --version
```

- `python3 -m pytest` - run pytest as a module inside your Python installation; more reliable than calling `pytest` directly because it always uses the right Python

```
Expected output (yours will differ):
pytest 8.3.2
```

---

## Step 3: assert Basics - Python's Verification Statement

**DBA analogy:** `assert` is like `DO $$ BEGIN ASSERT condition, 'message'; END $$` in PL/pgSQL - it checks that a condition is true and raises an error if it is not. It is the fundamental building block of every test.

On your Mac terminal, as your normal user:

```bash
python3 -c "
# assert passes silently when True
assert 1 + 1 == 2
assert 'postgres' in 'postgresql'
assert len([1, 2, 3]) == 3
print('All assertions passed')

# assert raises AssertionError when False
try:
    assert 1 == 2, 'Expected 1 to equal 2 but it did not'
except AssertionError as e:
    print(f'AssertionError caught: {e}')
"
```

- `assert condition` - raises `AssertionError` if `condition` is `False`
- `assert condition, 'message'` - the message is shown in the error output; always write a useful message
- `assert` with no message still raises an error, but gives no hint about what failed

```
Expected output (yours will differ):
All assertions passed
AssertionError caught: Expected 1 to equal 2 but it did not
```

---

## Step 4: Write Your First Test Function

pytest discovers test files and functions automatically. Any file named `test_*.py` and any function named `test_*` will be picked up and run.

On your Mac terminal, as your normal user:

```bash
mkdir -p ~/pgdba/tests
```

- `mkdir -p ~/pgdba/tests` - create the `tests/` directory; `-p` means "no error if it already exists"

Now write a minimal test file:

```bash
cat > ~/pgdba/tests/test_basics.py << 'PYEOF'
"""
Basic sanity tests - run these to verify pytest is working.
"""


def test_addition() -> None:
    """A trivial test to confirm pytest is discovering and running tests."""
    result = 1 + 1
    assert result == 2, f"Expected 2, got {result}"


def test_string_contains() -> None:
    """Verify string membership works as expected."""
    database_name = "prod_orders_v2"
    assert "orders" in database_name
    assert database_name.startswith("prod_")
    assert database_name.endswith("_v2")


def test_list_operations() -> None:
    """Verify list behavior we rely on in DBA scripts."""
    databases = ["postgres", "myapp", "reporting"]
    assert len(databases) == 3
    assert "myapp" in databases
    assert "unknown_db" not in databases
PYEOF
```

---

## Step 5: Run Tests with python3 -m pytest

On your Mac terminal, as your normal user:

```bash
python3 -m pytest ~/pgdba/tests/test_basics.py -v
```

- `~/pgdba/tests/test_basics.py` - path to the specific test file to run
- `-v` - verbose mode; shows each test function name and PASSED/FAILED status (without `-v` you only see a dot per test)

```
Expected output (yours will differ):
============================= test session starts ==============================
platform darwin -- Python 3.12.4, pytest-8.3.2, pluggy-1.5.0
collected 3 items

pgdba/tests/test_basics.py::test_addition PASSED                         [ 33%]
pgdba/tests/test_basics.py::test_string_contains PASSED                  [ 66%]
pgdba/tests/test_basics.py::test_list_operations PASSED                  [100%]

============================== 3 passed in 0.01s ==============================
```

---

## Step 6: Test conf_parser.py - Using a Temp Config File

Testing against real PostgreSQL config files would make the test suite fail if PostgreSQL is not installed. The correct approach: create a temp config file with known content, then assert on the results.

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/tests/test_conf_parser.py << 'PYEOF'
"""
Tests for conf_parser.py

Tests use temporary files with controlled content, not the real postgresql.conf.
This means tests pass even when PostgreSQL is not installed.
"""

import os
import sys
import tempfile

# Add the parent directory to sys.path so we can import conf_parser
sys.path.insert(0, os.path.expanduser('~/pgdba'))
import conf_parser


def test_read_conf_basic() -> None:
    """parse a simple two-line config file and verify values."""
    content = (
        "max_connections = 200\n"
        "shared_buffers = 512MB\n"
        "# this is a comment\n"
        "\n"
        "wal_level = logical\n"
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        tmp_path = f.name

    try:
        settings = conf_parser.read_conf(tmp_path)
        assert settings['max_connections'] == '200', \
            f"Expected '200', got {settings['max_connections']!r}"
        assert settings['shared_buffers'] == '512MB', \
            f"Expected '512MB', got {settings['shared_buffers']!r}"
        assert settings['wal_level'] == 'logical', \
            f"Expected 'logical', got {settings['wal_level']!r}"
    finally:
        os.unlink(tmp_path)   # always clean up temp files


def test_read_conf_skips_comments() -> None:
    """comment lines must not appear as settings."""
    content = (
        "# max_connections = 999\n"
        "max_connections = 100\n"
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        tmp_path = f.name

    try:
        settings = conf_parser.read_conf(tmp_path)
        assert settings.get('max_connections') == '100', \
            "Commented-out setting must be ignored"
        assert '# max_connections' not in settings, \
            "Comment line must not be stored as a key"
    finally:
        os.unlink(tmp_path)


def test_read_conf_strips_inline_comments() -> None:
    """inline comments after the value must be stripped."""
    content = "max_connections = 100\t\t# (change requires restart)\n"
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        tmp_path = f.name

    try:
        settings = conf_parser.read_conf(tmp_path)
        val = settings['max_connections']
        assert '#' not in val, f"Inline comment was not stripped: {val!r}"
        assert val.strip() == '100', f"Expected '100', got {val!r}"
    finally:
        os.unlink(tmp_path)


def test_get_setting_missing_key() -> None:
    """get_setting must return a default message for unset parameters."""
    settings: dict[str, str] = {'max_connections': '100'}
    result = conf_parser.get_setting(settings, 'work_mem')
    assert 'default' in result.lower(), \
        f"Expected 'default' in the message, got: {result!r}"


def test_parse_hba_basic() -> None:
    """parse a minimal pg_hba.conf and verify rule count and fields."""
    content = (
        "# TYPE  DATABASE  USER  ADDRESS  METHOD\n"
        "local   all       all            trust\n"
        "host    all       all  127.0.0.1/32  scram-sha-256\n"
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        tmp_path = f.name

    try:
        rules = conf_parser.parse_hba(tmp_path)
        assert len(rules) == 2, f"Expected 2 rules, got {len(rules)}"
        assert rules[0]['type'] == 'local'
        assert rules[1]['method'] == 'scram-sha-256'
    finally:
        os.unlink(tmp_path)


def test_find_trust_rules() -> None:
    """find_trust_rules must return only rules with method=trust."""
    rules = [
        {'type': 'local', 'database': 'all', 'user': 'all', 'address': '', 'method': 'trust'},
        {'type': 'host',  'database': 'all', 'user': 'all', 'address': '127.0.0.1/32', 'method': 'scram-sha-256'},
        {'type': 'host',  'database': 'all', 'user': 'all', 'address': '10.0.0.0/8', 'method': 'trust'},
    ]
    trust_rules = conf_parser.find_trust_rules(rules)
    assert len(trust_rules) == 2, f"Expected 2 trust rules, got {len(trust_rules)}"
    for r in trust_rules:
        assert r['method'] == 'trust'
PYEOF
```

- `sys.path.insert(0, ...)` - add `~/pgdba/` to Python's module search path so `import conf_parser` works (like adding a directory to `$PATH`)
- `tempfile.NamedTemporaryFile(delete=False)` - create a temp file that persists after closing so we can pass its path to the function being tested
- `os.unlink(tmp_path)` in a `finally` block - delete the temp file even if the test fails

---

## Step 7: Test user_manager.py - Test That Bad Input Raises an Error

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/tests/test_user_manager.py << 'PYEOF'
"""
Tests for user_manager.py

Tests validate input parsing and error handling logic
without connecting to a real database.
"""

import os
import sys
import pytest

sys.path.insert(0, os.path.expanduser('~/pgdba'))


def test_role_name_valid_characters() -> None:
    """Role names must only contain letters, digits, and underscores."""
    import re
    valid_pattern = re.compile(r'^[a-z][a-z0-9_]{0,62}$')

    valid_names = ['appuser', 'readonly_v2', 'db_admin_01']
    for name in valid_names:
        assert valid_pattern.match(name), f"Valid name rejected: {name!r}"

    invalid_names = ['App User', 'role-dash', '1startdigit', 'DROP TABLE--']
    for name in invalid_names:
        assert not valid_pattern.match(name), f"Invalid name accepted: {name!r}"


def test_privilege_list_parsing() -> None:
    """Verify that privilege strings are parsed correctly into lists."""
    # Simulates the kind of input parsing user_manager.py does
    def parse_privileges(priv_string: str) -> list[str]:
        allowed = {'SELECT', 'INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER'}
        raw = [p.strip().upper() for p in priv_string.split(',') if p.strip()]
        invalid = [p for p in raw if p not in allowed]
        if invalid:
            raise ValueError(f"Unknown privileges: {invalid}")
        return raw

    privs = parse_privileges('SELECT, INSERT, UPDATE')
    assert privs == ['SELECT', 'INSERT', 'UPDATE']

    with pytest.raises(ValueError, match='Unknown privileges'):
        parse_privileges('SELECT, DROP, SUPERUSER')


def test_connection_string_no_password_in_repr() -> None:
    """Database connection strings must not leak the password in repr() output."""
    class SafeConnString:
        def __init__(self, host: str, port: int, dbname: str, user: str, password: str) -> None:
            self.host = host
            self.port = port
            self.dbname = dbname
            self.user = user
            self._password = password   # private, prefixed with _

        def __repr__(self) -> str:
            return f'ConnString(host={self.host}, port={self.port}, dbname={self.dbname}, user={self.user})'

    conn = SafeConnString('localhost', 5432, 'myapp', 'appuser', 'SecretPass123')
    conn_repr = repr(conn)
    assert 'SecretPass123' not in conn_repr, "Password must not appear in repr()"
    assert 'appuser' in conn_repr, "Username should appear in repr()"
PYEOF
```

- `pytest.raises(ValueError, match='Unknown privileges')` - a context manager that asserts the block raises `ValueError` and that the error message matches the given string; if no exception is raised, the test fails
- `match=` accepts a regex pattern to check against the exception message

---

## Step 8: Fixtures - Setup and Teardown

**DBA analogy:** pytest fixtures are like the `setUp` and `tearDown` methods in test frameworks - they run before and after each test that needs them. In DBA terms: create a test schema before the test, drop it after. Or: start a transaction before, rollback after.

On your Mac terminal, as your normal user:

```bash
python3 -c "
import pytest
import tempfile
import os

# You can't run fixtures in a -c snippet, but we can show the concept:
# A fixture is just a function decorated with @pytest.fixture

# Without fixture (repetitive):
def test_a_without_fixture():
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.write(b'data')
    tmp.close()
    # ... test code ...
    os.unlink(tmp.name)   # must remember to clean up

def test_b_without_fixture():
    tmp = tempfile.NamedTemporaryFile(delete=False)
    tmp.write(b'data')
    tmp.close()
    # ... same setup again ...
    os.unlink(tmp.name)

# With fixture (DRY - Don't Repeat Yourself):
# @pytest.fixture
# def temp_log_file():
#     tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.log')
#     tmp.write(b'2024-01-15 14:23:45.123 UTC [12345] ERROR: test error\n')
#     tmp.close()
#     yield tmp.name        # <-- test runs here
#     os.unlink(tmp.name)   # <-- teardown: runs after the test, even if it fails

print('Fixture pattern explained - see conftest.py for the real implementation')
"
```

The `yield` in a fixture is the key: code before `yield` is setup (like `BEGIN`), code after `yield` is teardown (like `ROLLBACK` or cleanup).

---

## Step 9: parametrize - Test Multiple Inputs at Once

**DBA analogy:** `@pytest.mark.parametrize` is like testing your function against multiple PostgreSQL versions or multiple input values in one shot - instead of writing `test_pg14()`, `test_pg15()`, `test_pg16()` separately.

On your Mac terminal, as your normal user:

```bash
cat > /tmp/test_parametrize_demo.py << 'PYEOF'
import pytest
import re

ROLE_PATTERN = re.compile(r'^[a-z][a-z0-9_]{0,62}$')

def is_valid_role_name(name: str) -> bool:
    return bool(ROLE_PATTERN.match(name))

# Without parametrize: 6 separate test functions
# def test_valid_appuser(): assert is_valid_role_name('appuser')
# def test_valid_readonly(): assert is_valid_role_name('readonly')
# ... repeated forever ...

# With parametrize: one function, many inputs
@pytest.mark.parametrize("name,expected", [
    ("appuser",          True),
    ("readonly_v2",      True),
    ("db_admin_01",      True),
    ("App User",         False),   # uppercase + space
    ("role-dash",        False),   # hyphen not allowed
    ("1startdigit",      False),   # must start with letter
    ("DROP TABLE--",     False),   # SQL injection attempt
    ("",                 False),   # empty string
])
def test_role_name_validation(name: str, expected: bool) -> None:
    result = is_valid_role_name(name)
    assert result == expected, f"is_valid_role_name({name!r}) = {result}, expected {expected}"
PYEOF

python3 -m pytest /tmp/test_parametrize_demo.py -v
```

- `@pytest.mark.parametrize("name,expected", [...])` - the first argument is a comma-separated string of parameter names; the second is a list of tuples with one tuple per test case
- pytest generates one test case per tuple and names them automatically in the output

```
Expected output (yours will differ):
collected 8 items

test_parametrize_demo.py::test_role_name_validation[appuser-True] PASSED
test_parametrize_demo.py::test_role_name_validation[readonly_v2-True] PASSED
test_parametrize_demo.py::test_role_name_validation[db_admin_01-True] PASSED
test_parametrize_demo.py::test_role_name_validation[App User-False] PASSED
test_parametrize_demo.py::test_role_name_validation[role-dash-False] PASSED
test_parametrize_demo.py::test_role_name_validation[1startdigit-False] PASSED
test_parametrize_demo.py::test_role_name_validation[DROP TABLE---False] PASSED
test_parametrize_demo.py::test_role_name_validation[-False] PASSED

============================== 8 passed in 0.01s ==============================
```

---

## Step 10: Mocking with unittest.mock - Test Without a Real Database

**DBA analogy:** Mocking is like using a test schema with fake data instead of connecting to production. You replace `psycopg2.connect()` with a fake that returns whatever you tell it to - so your test never actually hits a database, but still exercises all your script's logic.

On your Mac terminal, as your normal user:

```bash
python3 -c "
from unittest.mock import MagicMock, patch

# Simulate what psycopg2.connect() returns
mock_conn   = MagicMock()
mock_cursor = MagicMock()

# Wire them together: conn.cursor() returns mock_cursor
mock_conn.cursor.return_value = mock_cursor

# Tell the mock cursor what to return when fetchall() is called
mock_cursor.fetchall.return_value = [
    ('appuser',  False, False, False),
    ('readonly', False, False, False),
    ('dbaadmin', True,  False, False),
]
mock_cursor.description = [
    ('rolname',), ('rolsuper',), ('rolcreatedb',), ('rolcreaterole',)
]

# Use it exactly like a real psycopg2 connection
cursor = mock_conn.cursor()
cursor.execute('SELECT rolname, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles')
rows = cursor.fetchall()

print('Rows returned by mock:')
for row in rows:
    print(' ', row)
print()
print('cursor.execute was called with:', cursor.execute.call_args)
"
```

- `MagicMock()` - creates a fake object that accepts any attribute access or method call without raising errors
- `.return_value = ...` - sets what a method call returns; `mock_cursor.fetchall.return_value = [...]` means calling `cursor.fetchall()` returns that list
- `cursor.execute.call_args` - records the arguments the mock was called with; useful for asserting that the right SQL was sent

```
Expected output (yours will differ):
Rows returned by mock:
  ('appuser', False, False, False)
  ('readonly', False, False, False)
  ('dbaadmin', True, False, False)

cursor.execute was called with: call('SELECT rolname, rolsuper, rolcreatedb, rolcreaterole FROM pg_roles')
```

---

## Step 11: Mock an AWS RDS Connection - Test RDS-Specific Logic Without AWS

On your Mac terminal, as your normal user:

```bash
cat > /tmp/test_rds_mock.py << 'PYEOF'
"""
Demonstrates mocking an AWS RDS connection.
The function under test would normally require a live RDS endpoint.
By mocking psycopg2.connect, the test runs without any AWS account.
"""

from unittest.mock import MagicMock, patch
import pytest


# This is the kind of function you'd have in a DBA script
def get_rds_connection_count(conn_params: dict[str, str]) -> int:
    """Connect to RDS and return the current connection count."""
    import psycopg2
    conn = psycopg2.connect(**conn_params)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")
    row = cursor.fetchone()
    cursor.close()
    conn.close()
    return int(row[0]) if row else 0


def test_rds_connection_count_normal() -> None:
    """get_rds_connection_count returns the value from the database query."""
    mock_conn   = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = mock_cursor
    mock_cursor.fetchone.return_value = (47,)   # simulate 47 active connections

    with patch('psycopg2.connect', return_value=mock_conn):
        count = get_rds_connection_count({
            'host': 'mydb.cluster-abc123.us-east-1.rds.amazonaws.com',
            'port': 5432,
            'dbname': 'prod',
            'user': 'dbaadmin',
            'password': 'secret',
        })

    assert count == 47, f"Expected 47, got {count}"
    # Verify the right SQL was executed
    mock_cursor.execute.assert_called_once_with(
        "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'"
    )
    # Verify the connection was properly closed
    mock_conn.close.assert_called_once()


def test_rds_connection_count_no_rows() -> None:
    """get_rds_connection_count returns 0 when the query returns no rows."""
    mock_conn   = MagicMock()
    mock_cursor = MagicMock()
    mock_conn.cursor.return_value = mock_cursor
    mock_cursor.fetchone.return_value = None   # simulate empty result

    with patch('psycopg2.connect', return_value=mock_conn):
        count = get_rds_connection_count({'host': 'rds.example.com', 'dbname': 'prod',
                                          'user': 'admin', 'password': 'x', 'port': 5432})

    assert count == 0
PYEOF

python3 -m pytest /tmp/test_rds_mock.py -v
```

- `with patch('psycopg2.connect', return_value=mock_conn):` - within this block, any call to `psycopg2.connect()` anywhere in the program returns `mock_conn` instead of opening a real connection
- `mock_cursor.execute.assert_called_once_with(...)` - asserts the mock was called exactly once with the specified arguments; if the SQL changed, this test would fail
- `mock_conn.close.assert_called_once()` - verifies the connection was closed (important for connection pool hygiene)

```
Expected output (yours will differ):
collected 2 items

test_rds_mock.py::test_rds_connection_count_normal PASSED
test_rds_mock.py::test_rds_connection_count_no_rows PASSED

============================== 2 passed in 0.04s ==============================
```

---

## Step 12: Test log_parser.py - Feed Sample Lines, Assert Parsed Output

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/tests/test_log_parser.py << 'PYEOF'
"""
Tests for log_parser.py

Creates temporary log files with known content and asserts
that the parser functions return the expected structured data.
"""

import os
import sys
import tempfile
import pytest

sys.path.insert(0, os.path.expanduser('~/pgdba'))
import log_parser


SAMPLE_LOG = """\
2024-01-15 14:20:05.100 UTC [11100] LOG:  connection received: host=10.0.1.5 port=52100
2024-01-15 14:20:10.200 UTC [11200] LOG:  duration: 5423.100 ms  statement: SELECT * FROM orders
2024-01-15 14:20:11.300 UTC [11300] ERROR:  relation "order_archive" does not exist at character 8
2024-01-15 14:20:12.400 UTC [11400] ERROR:  duplicate key value violates unique constraint "orders_pkey"
2024-01-15 14:20:13.500 UTC [11500] LOG:  duration: 234.500 ms  statement: UPDATE sessions SET ts = NOW()
2024-01-15 14:20:15.600 UTC [11600] FATAL:  password authentication failed for user "readonly"
2024-01-15 14:20:25.800 UTC [11800] ERROR:  conflict detected on relation "public.orders": conflict=update_delete; remote tuple: (id)=(9999); local conflicting tuple: (id)=(9999)
2024-01-15 14:20:30.900 UTC [11900] LOG:  duration: 12001.777 ms  statement: VACUUM ANALYZE orders
2024-01-15 14:20:37.200 UTC [12003] LOG:  deadlock detected
"""


@pytest.fixture
def sample_log_file() -> str:   # type: ignore[return]
    """Create a temp log file with known content. Yield the path, then clean up."""
    with tempfile.NamedTemporaryFile(mode='w', suffix='.log', delete=False) as f:
        f.write(SAMPLE_LOG)
        tmp_path = f.name
    yield tmp_path
    os.unlink(tmp_path)


def test_parse_errors_count(sample_log_file: str) -> None:
    """parse_errors must find all ERROR/FATAL lines."""
    errors = log_parser.parse_errors(sample_log_file)
    # 2 ERRORs + 1 FATAL + 1 ERROR (conflict line) = 4
    assert len(errors) == 4, f"Expected 4 errors, got {len(errors)}"


def test_parse_errors_severity_values(sample_log_file: str) -> None:
    """All returned records must have a valid severity level."""
    errors = log_parser.parse_errors(sample_log_file)
    valid_severities = {'ERROR', 'FATAL', 'PANIC', 'WARNING'}
    for e in errors:
        assert e['severity'] in valid_severities, \
            f"Unexpected severity: {e['severity']!r}"


def test_parse_slow_queries_count(sample_log_file: str) -> None:
    """parse_slow_queries with threshold=0 must return all duration lines."""
    slow = log_parser.parse_slow_queries(sample_log_file, threshold_ms=0.0)
    assert len(slow) == 3, f"Expected 3 slow query lines, got {len(slow)}"


def test_parse_slow_queries_sorted(sample_log_file: str) -> None:
    """parse_slow_queries must return results sorted slowest-first."""
    slow = log_parser.parse_slow_queries(sample_log_file, threshold_ms=0.0)
    durations = [q['duration_ms'] for q in slow]
    assert durations == sorted(durations, reverse=True), \
        f"Queries not sorted by duration: {durations}"


def test_parse_slow_queries_threshold(sample_log_file: str) -> None:
    """parse_slow_queries must filter out queries below the threshold."""
    slow = log_parser.parse_slow_queries(sample_log_file, threshold_ms=1000.0)
    for q in slow:
        assert q['duration_ms'] >= 1000.0, \
            f"Query below threshold included: {q['duration_ms']}ms"


@pytest.mark.parametrize("threshold_ms,expected_count", [
    (0.0,     3),
    (500.0,   2),
    (5000.0,  2),
    (20000.0, 0),
])
def test_parse_slow_queries_parametrized(sample_log_file: str, threshold_ms: float, expected_count: int) -> None:
    """Verify slow query count at multiple threshold values."""
    slow = log_parser.parse_slow_queries(sample_log_file, threshold_ms=threshold_ms)
    assert len(slow) == expected_count, \
        f"threshold={threshold_ms}: expected {expected_count} queries, got {len(slow)}"


def test_parse_replication_events_conflict(sample_log_file: str) -> None:
    """parse_replication_events must detect the conflict in the sample log."""
    events = log_parser.parse_replication_events(sample_log_file)
    assert len(events['conflicts']) == 1, \
        f"Expected 1 conflict, got {len(events['conflicts'])}"
    assert events['conflicts'][0]['relation'] == 'public.orders'


def test_parse_replication_events_deadlock(sample_log_file: str) -> None:
    """parse_replication_events must detect the deadlock in the sample log."""
    events = log_parser.parse_replication_events(sample_log_file)
    assert len(events['deadlocks']) == 1, \
        f"Expected 1 deadlock, got {len(events['deadlocks'])}"
PYEOF
```

- The `sample_log_file` fixture is defined once and injected into every test function that lists it as a parameter - pytest handles the wiring automatically
- `@pytest.fixture` with `yield` - code before `yield` is setup, code after `yield` is teardown

---

## Step 13: conftest.py - Shared Fixtures Across All Test Files

`conftest.py` is a special file that pytest reads automatically. Fixtures defined there are available to all test files in the same directory and subdirectories - without needing to import them.

On your Mac terminal, as your normal user:

```bash
cat > ~/pgdba/tests/conftest.py << 'PYEOF'
"""
conftest.py - shared fixtures for the pgdba test suite.

pytest discovers this file automatically. Any fixture defined here
is available to all test files in this directory without importing.
"""

import os
import sys
import tempfile
import pytest

# Make ~/pgdba importable in all test files
sys.path.insert(0, os.path.expanduser('~/pgdba'))


@pytest.fixture
def minimal_postgresql_conf() -> str:  # type: ignore[return]
    """
    Temp postgresql.conf with a small set of known settings.
    Yields the file path. File is deleted after the test.
    """
    content = (
        "# Minimal test config\n"
        "max_connections = 150\n"
        "shared_buffers = 256MB\n"
        "wal_level = replica\n"
        "log_min_duration_statement = 500\n"
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        path = f.name
    yield path
    os.unlink(path)


@pytest.fixture
def minimal_hba_conf() -> str:  # type: ignore[return]
    """
    Temp pg_hba.conf with two rules.
    Yields the file path. File is deleted after the test.
    """
    content = (
        "# TYPE  DATABASE  USER  ADDRESS       METHOD\n"
        "local   all       all                 trust\n"
        "host    all       all   127.0.0.1/32  scram-sha-256\n"
    )
    with tempfile.NamedTemporaryFile(mode='w', suffix='.conf', delete=False) as f:
        f.write(content)
        path = f.name
    yield path
    os.unlink(path)
PYEOF
```

- `conftest.py` - pytest's conventional filename for shared configuration; no import needed
- Any test file in `~/pgdba/tests/` can now use `minimal_postgresql_conf` and `minimal_hba_conf` as fixture parameters

---

## Step 14: Add conftest.py Fixtures to test_conf_parser.py

Now that the fixtures live in `conftest.py`, update `test_conf_parser.py` to use the shared ones.

On your Mac terminal, as your normal user:

```bash
cat >> ~/pgdba/tests/test_conf_parser.py << 'PYEOF'


# ---------- tests using conftest.py fixtures ----------

def test_conf_fixture_max_connections(minimal_postgresql_conf: str) -> None:
    """Verify the conftest fixture provides correct max_connections value."""
    settings = conf_parser.read_conf(minimal_postgresql_conf)
    assert settings.get('max_connections') == '150'


def test_hba_fixture_rule_count(minimal_hba_conf: str) -> None:
    """Verify the conftest HBA fixture has exactly 2 rules."""
    rules = conf_parser.parse_hba(minimal_hba_conf)
    assert len(rules) == 2, f"Expected 2 rules, got {len(rules)}"
PYEOF
```

---

## Step 15: Run the Full Test Suite

On your Mac terminal, as your normal user:

```bash
python3 -m pytest ~/pgdba/tests/ -v --tb=short
```

- `~/pgdba/tests/` - run all test files in the directory
- `-v` - verbose: show each test name and result
- `--tb=short` - on failure, show a short traceback (the failing line and assertion) instead of the full stack trace; easier to read

```
Expected output (yours will differ):
============================= test session starts ==============================
platform darwin -- Python 3.12.4, pytest-8.3.2
collected 24 items

tests/test_basics.py::test_addition PASSED                               [  4%]
tests/test_basics.py::test_string_contains PASSED                        [  8%]
tests/test_basics.py::test_list_operations PASSED                        [ 12%]
tests/test_conf_parser.py::test_read_conf_basic PASSED                   [ 16%]
tests/test_conf_parser.py::test_read_conf_skips_comments PASSED          [ 20%]
tests/test_conf_parser.py::test_read_conf_strips_inline_comments PASSED  [ 25%]
tests/test_conf_parser.py::test_get_setting_missing_key PASSED           [ 29%]
tests/test_conf_parser.py::test_parse_hba_basic PASSED                   [ 33%]
tests/test_conf_parser.py::test_find_trust_rules PASSED                  [ 37%]
tests/test_conf_parser.py::test_conf_fixture_max_connections PASSED      [ 41%]
tests/test_conf_parser.py::test_hba_fixture_rule_count PASSED            [ 45%]
tests/test_user_manager.py::test_role_name_valid_characters PASSED       [ 50%]
tests/test_user_manager.py::test_privilege_list_parsing PASSED           [ 54%]
tests/test_user_manager.py::test_connection_string_no_password_in_repr PASSED [ 58%]
tests/test_log_parser.py::test_parse_errors_count PASSED                 [ 62%]
tests/test_log_parser.py::test_parse_errors_severity_values PASSED       [ 66%]
tests/test_log_parser.py::test_parse_slow_queries_count PASSED           [ 70%]
tests/test_log_parser.py::test_parse_slow_queries_sorted PASSED          [ 75%]
tests/test_log_parser.py::test_parse_slow_queries_threshold PASSED       [ 79%]
tests/test_log_parser.py::test_parse_slow_queries_parametrized[0.0-3] PASSED [ 83%]
tests/test_log_parser.py::test_parse_slow_queries_parametrized[500.0-2] PASSED [ 87%]
tests/test_log_parser.py::test_parse_slow_queries_parametrized[5000.0-2] PASSED [ 91%]
tests/test_log_parser.py::test_parse_slow_queries_parametrized[20000.0-0] PASSED [ 95%]
tests/test_log_parser.py::test_parse_replication_events_conflict PASSED  [ 99%]
tests/test_log_parser.py::test_parse_replication_events_deadlock PASSED  [100%]

============================== 24 passed in 0.18s ==============================
```

All tests pass. Your DBA toolkit now has a test suite.

---

## What You Built

Your `~/pgdba/tests/` directory contains:
- `conftest.py` - shared fixtures for the whole test suite
- `test_basics.py` - sanity tests confirming pytest is working
- `test_conf_parser.py` - 11 tests for `conf_parser.py`
- `test_user_manager.py` - 3 tests for user management logic
- `test_log_parser.py` - 10 tests for `log_parser.py`

**Python concepts used:**
- `assert` - the fundamental verification statement
- `pytest` test discovery - any `test_*.py` file, any `test_*()` function
- `@pytest.fixture` with `yield` - setup and teardown (like BEGIN/ROLLBACK)
- `@pytest.mark.parametrize` - run one test function against multiple inputs
- `MagicMock` - fake objects that record how they were called
- `patch()` - replace a real function with a mock for the duration of a test
- `conftest.py` - shared fixtures available without importing

**Next:** BUILD 18 covers HTTP and APIs - sending real alerts via Slack webhooks and email when your DBA scripts detect problems.

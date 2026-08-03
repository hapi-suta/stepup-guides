# BUILD 14: Decorators - HA Failover Utilities (Repmgr HA)

**What you will build:** `~/pgdba/decorators.py` - a reusable decorator library with `@retry`, `@timed`, and `@log_call`. These wrap any DBA function to add automatic retry logic, execution timing, and audit logging - essential for HA failover scripts where transient connection failures are expected.

**Python concepts covered:** functions as objects, passing functions as arguments, closures, writing a decorator manually, @syntax, functools.wraps, decorators with arguments, stacking decorators

**Time to complete:** ~60 minutes

---

## Prerequisites

- Completed BUILD 13 (`~/pgdba/audit_logger.py` exists)
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)
- PostgreSQL running locally on port 5432

---

## Step 1: Functions are objects - you can store them and pass them around

In SQL, you can store a function name as a string and look it up in `pg_catalog.pg_proc`. In Python, functions are first-class objects - you can assign a function to a variable, put it in a list, or pass it as an argument to another function, without calling it.

The difference between `my_func` and `my_func()`:
- `my_func` - the function object itself (not called)
- `my_func()` - call the function and get its return value

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def run_health_check():
    print('Checking pg_stat_activity...')
    return 'healthy'

# Store the function in a variable - note: no () at the end
checker = run_health_check

# Now call it through the variable
result = checker()
print(result)

# You can also print the function object itself
print(run_health_check)
"
```

Expected output (yours will differ):

```
Checking pg_stat_activity...
healthy
<function run_health_check at 0x10a3b2c40>
```

The last line shows that `run_health_check` is an object with a memory address - not just a name.

---

## Step 2: A function that takes another function as input

Just as you can pass a table name to a PL/pgSQL function and use `EXECUTE format(...)` to run dynamic SQL on it, you can pass a Python function to another Python function and call it from inside.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def run_health_check():
    print('Running health check...')
    return 'healthy'

def run_with_banner(func):
    print('--- DBA task starting ---')
    result = func()          # call whatever function was passed in
    print('--- DBA task complete ---')
    return result

# Pass the function object (no parentheses) to run_with_banner
run_with_banner(run_health_check)
"
```

Expected output (yours will differ):

```
--- DBA task starting ---
Running health check...
--- DBA task complete ---
```

`run_with_banner` does not know or care what `func` does - it just adds a banner before and after. This is the core idea behind decorators.

---

## Step 3: Closures - inner functions that remember outer variables

A closure is an inner function that captures (remembers) a variable from its enclosing scope, even after the outer function finishes. Think of it like a PL/pgSQL block that captures a variable from the outer block's `DECLARE` section - the inner block can still use it.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def make_retry_wrapper(max_attempts):
    # max_attempts is defined here in the outer function

    def wrapper():
        # This inner function remembers max_attempts even after make_retry_wrapper returns
        for attempt in range(1, max_attempts + 1):
            print(f'Attempt {attempt} of {max_attempts}')

    return wrapper   # return the inner function, not its result

# retry_3_times is now a function that knows max_attempts=3
retry_3_times = make_retry_wrapper(3)
retry_3_times()
"
```

Expected output (yours will differ):

```
Attempt 1 of 3
Attempt 2 of 3
Attempt 3 of 3
```

`retry_3_times` is a closure - it carries `max_attempts=3` in its memory. This is how decorators with arguments work.

---

## Step 4: Build a simple decorator manually (before @ syntax)

A decorator is a function that takes another function, wraps it with extra behavior, and returns the wrapped version. Here is the full pattern written out by hand.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
def add_timing(func):
    import time

    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)   # call the original function
        elapsed = time.time() - start
        print(f'{func.__name__} took {elapsed:.4f}s')
        return result

    return wrapper   # return the wrapper, not the result

def run_vacuum():
    import time
    time.sleep(0.1)   # simulate work
    return 'vacuum complete'

# Manually wrap run_vacuum
timed_vacuum = add_timing(run_vacuum)

# Now call the wrapped version
result = timed_vacuum()
print(result)
"
```

Expected output (yours will differ):

```
run_vacuum took 0.1003s
vacuum complete
```

`add_timing(run_vacuum)` returns a new function (`wrapper`) that runs the original plus timing. `timed_vacuum` IS the wrapper - it just calls `run_vacuum` from inside.

---

## Step 5: @syntax - the clean way to apply decorators

Writing `timed_vacuum = add_timing(run_vacuum)` every time is verbose. The `@` syntax is shorthand - it automatically applies the decorator when Python loads the function definition.

`@add_timing` directly above `def run_vacuum():` is exactly equivalent to writing `run_vacuum = add_timing(run_vacuum)` after the definition.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time

def add_timing(func):
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        elapsed = time.time() - start
        print(f'{func.__name__} took {elapsed:.4f}s')
        return result
    return wrapper

@add_timing                 # same as: run_vacuum = add_timing(run_vacuum)
def run_vacuum():
    time.sleep(0.05)
    return 'vacuum complete'

result = run_vacuum()       # automatically timed now
print(result)
"
```

Expected output (yours will differ):

```
run_vacuum took 0.0503s
vacuum complete
```

From now on you always use `@` syntax. It is cleaner and is what you will see in every Python codebase.

---

## Step 6: functools.wraps - preserve the original function's metadata

When you wrap a function, the wrapper replaces it. That means `run_vacuum.__name__` now returns `'wrapper'` instead of `'run_vacuum'`, and its docstring is lost. In a DBA toolkit with 20 functions, losing those names makes debugging hard.

`functools.wraps` copies the original function's name, docstring, and other metadata onto the wrapper. Always use it in decorators.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time
from functools import wraps

def add_timing(func):
    @wraps(func)           # copy func's __name__, __doc__, etc. onto wrapper
    def wrapper(*args, **kwargs):
        start = time.time()
        result = func(*args, **kwargs)
        elapsed = time.time() - start
        print(f'{func.__name__} took {elapsed:.4f}s')
        return result
    return wrapper

@add_timing
def run_vacuum():
    'Runs VACUUM on all user tables.'
    time.sleep(0.05)

run_vacuum()
print(run_vacuum.__name__)    # 'run_vacuum', not 'wrapper'
print(run_vacuum.__doc__)     # original docstring preserved
"
```

Expected output (yours will differ):

```
run_vacuum took 0.0504s
run_vacuum
Runs VACUUM on all user tables.
```

---

## Step 7: Build @retry - auto-retry on psycopg2.OperationalError

`pgbouncer` and `pgpool` have connection retry settings. In HA failover scenarios, a script hitting the old primary gets `OperationalError` while the new primary is being promoted. The `@retry` decorator catches that and retries automatically - the function doesn't need to know about retry logic at all.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time
import psycopg2
from functools import wraps

attempt_count = 0   # global just for this demo

def retry(max_attempts=3, delay=2):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            global attempt_count
            for attempt in range(1, max_attempts + 1):
                attempt_count += 1
                try:
                    return func(*args, **kwargs)
                except psycopg2.OperationalError as e:
                    print(f'[RETRY] Attempt {attempt}/{max_attempts} failed: {e}')
                    if attempt < max_attempts:
                        print(f'[RETRY] Waiting {delay}s before retry...')
                        time.sleep(delay)
                    else:
                        print(f'[RETRY] All {max_attempts} attempts exhausted.')
                        raise
        return wrapper
    return decorator

@retry(max_attempts=3, delay=1)
def connect_to_primary():
    # Use a bad port to simulate a failed primary
    conn = psycopg2.connect(host='localhost', port=9999, dbname='postgres',
                            connect_timeout=2)
    return conn

try:
    connect_to_primary()
except psycopg2.OperationalError:
    print('Failover needed - primary unreachable after 3 attempts')
"
```

Expected output (yours will differ):

```
[RETRY] Attempt 1/3 failed: connection to server at "localhost" (::1), port 9999 failed...
[RETRY] Waiting 1s before retry...
[RETRY] Attempt 2/3 failed: connection to server at "localhost" (::1), port 9999 failed...
[RETRY] Waiting 1s before retry...
[RETRY] Attempt 3/3 failed: connection to server at "localhost" (::1), port 9999 failed...
[RETRY] All 3 attempts exhausted.
Failover needed - primary unreachable after 3 attempts
```

---

## Step 8: Build @timed - measure execution duration

In `psql`, `\timing` prints execution duration after every query. The `@timed` decorator does the same for any Python function - it prints how long the function took. This is useful for tracking how long a backup, VACUUM, or health check takes over time.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time
from functools import wraps

def timed(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        print(f'[TIMED] {func.__name__}: {elapsed:.4f}s')
        return result
    return wrapper

@timed
def run_table_bloat_check():
    time.sleep(0.15)   # simulate a slow query
    return {'tables_checked': 42, 'bloated': 3}

result = run_table_bloat_check()
print(f'Result: {result}')
"
```

Expected output (yours will differ):

```
[TIMED] run_table_bloat_check: 0.1503s
Result: {'tables_checked': 42, 'bloated': 3}
```

`time.perf_counter()` is more precise than `time.time()` for measuring short durations - use it when timing database operations.

---

## Step 9: Build @log_call - audit every function call

Compliance environments often require that every DBA action is logged - who ran what, when, with what arguments, and what was returned. The `@log_call` decorator does this automatically for every function it wraps, using `audit_logger` from BUILD 13.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger
from functools import wraps

logger = setup_logger('log_call_demo')

def log_call(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        logger.info(f'CALL: {func.__name__}(args={args}, kwargs={kwargs})')
        result = func(*args, **kwargs)
        logger.info(f'RETURN: {func.__name__} -> {result}')
        return result
    return wrapper

@log_call
def get_replication_lag(host: str, port: int = 5432) -> str:
    # In a real script, this would query pg_stat_replication
    return '0.5s lag'

get_replication_lag('pg-standby-01')
get_replication_lag('pg-standby-02', port=5433)
"
```

Expected output (yours will differ):

```
[INFO] log_call_demo: CALL: get_replication_lag(args=('pg-standby-01',), kwargs={})
[INFO] log_call_demo: RETURN: get_replication_lag -> 0.5s lag
[INFO] log_call_demo: CALL: get_replication_lag(args=('pg-standby-02',), kwargs={'port': 5433})
[INFO] log_call_demo: RETURN: get_replication_lag -> 0.5s lag
```

Every call is now audited: function name, arguments, and return value. This also writes to `~/pgdba/logs/dba_audit.log`.

---

## Step 10: Decorators with arguments - the extra wrapper layer

`@timed` is a simple decorator - you use it with no arguments. `@retry(max_attempts=3)` takes arguments. That requires one extra level of wrapping. The reason: `@retry(max_attempts=3)` first calls `retry(max_attempts=3)` to get back a decorator, and THEN applies that decorator to the function.

Think of it as two steps:
1. `retry(max_attempts=3)` returns a decorator function
2. That decorator function wraps `my_func`

Simple decorator: one layer (`decorator` -> `wrapper`)
Decorator with args: two layers (`outer(args)` -> `decorator` -> `wrapper`)

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
from functools import wraps

# This is the outer function - it takes the arguments
def retry(max_attempts=3, delay=1):
    # This is the decorator - it takes the function
    def decorator(func):
        # This is the wrapper - it takes the function's arguments
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                print(f'  attempt {attempt}/{max_attempts}')
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_attempts:
                        raise
            return None
        return wrapper
    return decorator   # <-- retry() returns the decorator, not the wrapper

@retry(max_attempts=2)
def flaky_function():
    raise RuntimeError('Simulated transient failure')

try:
    flaky_function()
except RuntimeError:
    print('All attempts failed')
"
```

Expected output (yours will differ):

```
  attempt 1/2
  attempt 2/2
All attempts failed
```

---

## Step 11: Stacking decorators - @log_call @timed @retry on one function

You can stack multiple decorators on a single function. They apply from bottom to top - the decorator closest to `def` wraps the function first.

`@log_call @timed @retry` means: retry wraps the function first, then timed wraps retry's wrapper, then log_call wraps that. When called: log_call fires first, then timed, then retry.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time
import sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger
from functools import wraps
import psycopg2

logger = setup_logger('stack_demo')

def retry(max_attempts=3, delay=0):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except psycopg2.OperationalError as e:
                    logger.warning(f'Retry {attempt}/{max_attempts}: {e}')
                    if attempt == max_attempts:
                        raise
                    time.sleep(delay)
        return wrapper
    return decorator

def timed(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        logger.info(f'[TIMED] {func.__name__}: {elapsed:.4f}s')
        return result
    return wrapper

def log_call(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        logger.info(f'[CALL] {func.__name__} starting')
        result = func(*args, **kwargs)
        logger.info(f'[CALL] {func.__name__} completed -> {result}')
        return result
    return wrapper

@log_call
@timed
@retry(max_attempts=3, delay=0)
def check_primary_health():
    conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute(\"SELECT pg_is_in_recovery(), version()\")
    row = cur.fetchone()
    conn.close()
    return {'is_standby': row[0], 'version': row[1][:30]}

check_primary_health()
"
```

Expected output (yours will differ):

```
[INFO] stack_demo: [CALL] check_primary_health starting
[INFO] stack_demo: [TIMED] check_primary_health: 0.0082s
[INFO] stack_demo: [CALL] check_primary_health completed -> {'is_standby': False, 'version': 'PostgreSQL 16.3 on x86_64-pc-li'}
```

---

## Step 12: Apply decorators to existing functions from previous scripts

Decorators shine when you retrofit them onto existing code with zero changes to the original function body. Here is how to apply `@retry` and `@timed` to a backup function without touching its internals.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import time, sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger
from functools import wraps
import psycopg2

logger = setup_logger('backup_runner')

def timed(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        logger.info(f'[TIMED] {func.__name__}: {time.perf_counter()-start:.4f}s')
        return result
    return wrapper

def log_call(func):
    @wraps(func)
    def wrapper(*args, **kwargs):
        logger.info(f'[AUDIT] {func.__name__} called with args={args}')
        result = func(*args, **kwargs)
        logger.info(f'[AUDIT] {func.__name__} returned: {result}')
        return result
    return wrapper

# Existing backup function - we add decorators without changing any internals
@log_call
@timed
def get_database_sizes():
    'Return size of each database in MB.'
    conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres',
                            user=os.environ.get('USER'), connect_timeout=3)
    cur = conn.cursor()
    cur.execute('''
        SELECT datname, pg_size_pretty(pg_database_size(datname))
        FROM pg_database
        WHERE datistemplate = false
        ORDER BY pg_database_size(datname) DESC
    ''')
    rows = cur.fetchall()
    conn.close()
    return {row[0]: row[1] for row in rows}

get_database_sizes()
"
```

Expected output (yours will differ):

```
[INFO] backup_runner: [AUDIT] get_database_sizes called with args=()
[INFO] backup_runner: [TIMED] get_database_sizes: 0.0095s
[INFO] backup_runner: [AUDIT] get_database_sizes returned: {'postgres': '8537 kB', 'template1': '7673 kB'}
```

---

## Step 13: Combine into decorators.py

Now write the final, clean `decorators.py` module.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
content = '''#!/usr/bin/env python3
\"\"\"
decorators.py - Reusable DBA decorator library.

Decorators:
    @retry(max_attempts, delay, exceptions)  - retry on transient failures
    @timed                                   - log execution duration
    @log_call                                - audit every call and return value

Usage:
    from decorators import retry, timed, log_call

    @log_call
    @timed
    @retry(max_attempts=3, delay=2)
    def promote_standby(host: str) -> bool:
        ...
\"\"\"

import time
import psycopg2
from functools import wraps
from typing import Tuple, Type
import sys
import os

sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger

_logger = setup_logger('decorators')


def retry(
    max_attempts: int = 3,
    delay: float = 2.0,
    exceptions: Tuple[Type[Exception], ...] = (psycopg2.OperationalError,)
):
    \"\"\"
    Retry a function on transient failures.

    Args:
        max_attempts: Number of total attempts before re-raising. Default 3.
        delay:        Seconds to wait between attempts. Default 2.
        exceptions:   Exception types to catch and retry on. Default: psycopg2.OperationalError.

    Analogy: connection_retry_count in pgbouncer / pgpool.
    \"\"\"
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    _logger.warning(
                        f'[RETRY] {func.__name__}: attempt {attempt}/{max_attempts} failed: {e}'
                    )
                    if attempt < max_attempts:
                        _logger.info(f'[RETRY] Waiting {delay}s...')
                        time.sleep(delay)
                    else:
                        _logger.error(f'[RETRY] {func.__name__}: all {max_attempts} attempts exhausted')
                        raise
        return wrapper
    return decorator


def timed(func):
    \"\"\"
    Log execution duration after the function returns.

    Analogy: \\\\timing in psql.
    \"\"\"
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        _logger.info(f'[TIMED] {func.__name__}: {elapsed:.4f}s')
        return result
    return wrapper


def log_call(func):
    \"\"\"
    Audit every call: log function name, arguments, and return value.

    Analogy: writing every DBA action to an audit table.
    \"\"\"
    @wraps(func)
    def wrapper(*args, **kwargs):
        _logger.info(f'[AUDIT] CALL  {func.__name__}(args={args}, kwargs={kwargs})')
        result = func(*args, **kwargs)
        _logger.info(f'[AUDIT] RETURN {func.__name__} -> {result}')
        return result
    return wrapper


if __name__ == \"__main__\":
    import psycopg2

    @log_call
    @timed
    @retry(max_attempts=2, delay=0)
    def demo_pg_connection():
        \"Demo: connect to local PostgreSQL and return server version.\"
        conn = psycopg2.connect(
            host=\"localhost\", port=5432, dbname=\"postgres\",
            user=os.environ.get(\"USER\"), connect_timeout=3
        )
        cur = conn.cursor()
        cur.execute(\"SELECT version()\")
        version = cur.fetchone()[0].split(\",\")[0]
        conn.close()
        return version

    demo_pg_connection()
    print(\"\\ndecorators.py self-test complete.\")
    print(f\"Check ~/pgdba/logs/dba_audit.log for the full audit trail.\")
'''
path = os.path.expanduser('~/pgdba/decorators.py')
with open(path, 'w') as f:
    f.write(content)
print(f'decorators.py written to {path}')
" 2>/dev/null || python3 -c "
import os
path = os.path.expanduser('~/pgdba/decorators.py')
print(f'Writing to {path}')
"
```

Because the heredoc approach can conflict with shell quoting, write the file directly:

```bash
cat > ~/pgdba/decorators.py << 'PYEOF'
#!/usr/bin/env python3
"""
decorators.py - Reusable DBA decorator library.

Decorators:
    @retry(max_attempts, delay, exceptions)  - retry on transient failures
    @timed                                   - log execution duration
    @log_call                                - audit every call and return value

Usage:
    from decorators import retry, timed, log_call

    @log_call
    @timed
    @retry(max_attempts=3, delay=2)
    def promote_standby(host: str) -> bool:
        ...
"""

import time
import os
import sys
import psycopg2
from functools import wraps
from typing import Tuple, Type

sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger

_logger = setup_logger('decorators')


def retry(
    max_attempts: int = 3,
    delay: float = 2.0,
    exceptions: Tuple[Type[Exception], ...] = (psycopg2.OperationalError,)
):
    """
    Retry a function on transient failures.

    Args:
        max_attempts: Total attempts before re-raising. Default 3.
        delay:        Seconds between attempts. Default 2.
        exceptions:   Exception types to retry on. Default: psycopg2.OperationalError.

    Analogy: connection_retry_count in pgbouncer / pgpool.
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(1, max_attempts + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    _logger.warning(
                        f'[RETRY] {func.__name__}: attempt {attempt}/{max_attempts} failed: {e}'
                    )
                    if attempt < max_attempts:
                        _logger.info(f'[RETRY] Waiting {delay}s...')
                        time.sleep(delay)
                    else:
                        _logger.error(
                            f'[RETRY] {func.__name__}: all {max_attempts} attempts exhausted'
                        )
                        raise
        return wrapper
    return decorator


def timed(func):
    """
    Log execution duration after the function returns.

    Analogy: \\timing in psql.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        start = time.perf_counter()
        result = func(*args, **kwargs)
        elapsed = time.perf_counter() - start
        _logger.info(f'[TIMED] {func.__name__}: {elapsed:.4f}s')
        return result
    return wrapper


def log_call(func):
    """
    Audit every call: log function name, arguments, and return value.

    Analogy: writing every DBA action to an audit table.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        _logger.info(f'[AUDIT] CALL  {func.__name__}(args={args}, kwargs={kwargs})')
        result = func(*args, **kwargs)
        _logger.info(f'[AUDIT] RETURN {func.__name__} -> {result}')
        return result
    return wrapper


if __name__ == '__main__':
    @log_call
    @timed
    @retry(max_attempts=2, delay=0)
    def demo_pg_connection():
        """Demo: connect to local PostgreSQL and return server version."""
        conn = psycopg2.connect(
            host='localhost', port=5432, dbname='postgres',
            user=os.environ.get('USER'), connect_timeout=3
        )
        cur = conn.cursor()
        cur.execute('SELECT version()')
        version = cur.fetchone()[0].split(',')[0]
        conn.close()
        return version

    demo_pg_connection()
    print('\ndecorators.py self-test complete.')
    print('Check ~/pgdba/logs/dba_audit.log for the full audit trail.')
PYEOF
echo "decorators.py written to ~/pgdba/"
```

Expected output (yours will differ):

```
decorators.py written to ~/pgdba/
```

---

## Step 14: Demo - a fully decorated function connecting to PostgreSQL

Run the self-test to see all three decorators firing together on a real PostgreSQL connection:

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/decorators.py
```

Expected output (yours will differ):

```
[INFO] decorators: [AUDIT] CALL  demo_pg_connection(args=(), kwargs={})
[INFO] decorators: [TIMED] demo_pg_connection: 0.0091s
[INFO] decorators: [AUDIT] RETURN demo_pg_connection -> PostgreSQL 16.3 on x86_64-pc-linux-gnu

decorators.py self-test complete.
Check ~/pgdba/logs/dba_audit.log for the full audit trail.
```

Now verify the full audit trail including DEBUG messages is in the log file:

```bash
tail -5 ~/pgdba/logs/dba_audit.log
```

Expected output (yours will differ):

```
2026-06-13 14:42:01 [INFO] decorators (decorators.py:68): [AUDIT] CALL  demo_pg_connection(args=(), kwargs={})
2026-06-13 14:42:01 [INFO] decorators (decorators.py:54): [TIMED] demo_pg_connection: 0.0091s
2026-06-13 14:42:01 [INFO] decorators (decorators.py:75): [AUDIT] RETURN demo_pg_connection -> PostgreSQL 16.3 on x86_64-pc-linux-gnu
```

---

## What you built

You now have `~/pgdba/decorators.py` with three production-grade decorators:

- `@retry(max_attempts, delay)` - catches `psycopg2.OperationalError` and retries, essential during HA failover when the old primary is still getting traffic
- `@timed` - logs execution duration for any function, equivalent to `\timing` in psql
- `@log_call` - audits every function call and return value to `dba_audit.log`

Apply any combination to any DBA function with three lines added above `def`.

---

## What you learned

| Python concept | DBA analogy |
|---|---|
| Functions as objects (`func`, not `func()`) | Function name stored in `pg_proc.proname` |
| Passing functions as arguments | `EXECUTE format('SELECT %I(...)', func_name)` |
| Closures | Inner PL/pgSQL block capturing outer `DECLARE` variables |
| `@decorator` syntax | Shorthand for `func = decorator(func)` |
| `functools.wraps` | Preserving `application_name` through a proxy layer |
| `@retry` | `connection_retry_count` in pgbouncer |
| `@timed` | `\timing` in psql |
| `@log_call` | Writing every DBA action to an audit table |
| Stacking decorators (bottom to top) | Nested function calls in SQL expressions |

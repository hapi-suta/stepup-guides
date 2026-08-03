# BUILD 13: Logging - DBA Audit Logger (Advanced Monitoring)

**What you will build:** `~/pgdba/audit_logger.py` - a reusable logging module that any DBA script can import. It writes structured, timestamped messages to both the console and a rotating log file at `~/pgdba/logs/dba_audit.log`.

**Python concepts covered:** logging module, log levels (DEBUG/INFO/WARNING/ERROR/CRITICAL), formatters, handlers (StreamHandler, FileHandler, RotatingFileHandler), getLogger(), configuring logging

**Time to complete:** ~50 minutes

---

## Prerequisites

- Completed BUILD 01 (your `~/pgdba/` directory exists)
- Python 3 installed
- PostgreSQL running locally on port 5432
- `psycopg2-binary` installed (`pip3 install psycopg2-binary`)

---

## Step 1: Why print() is not enough

You have been using `print()` to show output. That works during development, but in production it falls short - there is no timestamp, no severity level, no way to filter by importance, and no log file.

Think of it this way: `print()` is like using `RAISE NOTICE` in a function. It tells you something happened, but it does not go into your audit table, it does not record when it happened, and you cannot filter it later. The Python `logging` module is like writing to a proper audit table - every event has a timestamp, a severity level, the source module, and a message.

On your **Mac terminal**, as your **normal user**, run this comparison:

```bash
python3 -c "
import logging
print('Something happened')           # no timestamp, no level
logging.warning('Something happened') # timestamp + level included
"
```

Expected output (yours will differ):

```
Something happened
WARNING:root:Something happened
```

The logging output already includes the severity level (`WARNING`) and the logger name (`root`). That extra structure is what makes logs parseable by monitoring tools like Datadog, CloudWatch, or even grep.

---

## Step 2: Basic logging calls - INFO, WARNING, ERROR

The `logging` module has five functions that match five severity levels. You call them the same way you call `print()`.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
logging.info('Checkpoint reached')
logging.warning('Replication lag is 30 seconds')
logging.error('Could not connect to standby')
"
```

Expected output (yours will differ):

```
WARNING:root:Replication lag is 30 seconds
ERROR:root:Could not connect to standby
```

Notice that `logging.info()` produced no output. By default, Python's logging module ignores anything below WARNING severity. You will fix that in the next step.

---

## Step 3: Log levels - DEBUG through CRITICAL

PostgreSQL has `log_min_messages` in `postgresql.conf` - you set it to `DEBUG5` to see everything, or `WARNING` to see only serious events. Python logging works exactly the same way.

The five levels in order from least to most severe:

| Python Level | Numeric Value | PostgreSQL Equivalent |
|---|---|---|
| DEBUG | 10 | DEBUG5 / DEBUG1 |
| INFO | 20 | LOG / INFO |
| WARNING | 30 | WARNING |
| ERROR | 40 | ERROR |
| CRITICAL | 50 | PANIC |

Setting the level to `WARNING` means DEBUG and INFO messages are silently ignored - just like setting `log_min_messages = warning` in `postgresql.conf`.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
logging.basicConfig(level=logging.DEBUG)
logging.debug('Checking pg_stat_activity...')
logging.info('Connection pool healthy: 10/20 slots used')
logging.warning('Replication lag: 45s')
logging.error('Failed to reach pg-standby-01')
logging.critical('Primary is down - initiating failover')
"
```

Expected output (yours will differ):

```
DEBUG:root:Checking pg_stat_activity...
INFO:root:Connection pool healthy: 10/20 slots used
WARNING:root:Replication lag: 45s
ERROR:root:Failed to reach pg-standby-01
CRITICAL:root:Primary is down - initiating failover
```

---

## Step 4: basicConfig() - configure level and format

`logging.basicConfig()` is the simplest way to configure logging. You call it once, at the start of your script, before any logging calls.

The two most important parameters:
- `level` - the minimum severity to capture (like `log_min_messages`)
- `format` - what each log line looks like (like `log_line_prefix` in `postgresql.conf`)

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
logging.basicConfig(
    level=logging.INFO,
    format='%(levelname)s - %(message)s'
)
logging.info('Health check started')
logging.warning('Autovacuum running on large table')
"
```

Expected output (yours will differ):

```
INFO - Health check started
WARNING - Autovacuum running on large table
```

---

## Step 5: Formatters - add timestamps and module names

In `postgresql.conf`, `log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a '` adds timestamp, PID, user, and database to every log line. Python formatters do the same thing.

Key format tokens:

| Token | Meaning | PostgreSQL Analogy |
|---|---|---|
| `%(asctime)s` | Timestamp | `%t` in log_line_prefix |
| `%(levelname)s` | Severity level | Log level prefix |
| `%(name)s` | Logger name (module) | `app=%a` |
| `%(message)s` | The actual message | The log message body |
| `%(lineno)d` | Line number in source | - |

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logging.info('pg_monitor started')
logging.warning('WAL size exceeding threshold: 8.2 GB')
"
```

Expected output (yours will differ):

```
2026-06-13 14:32:01 [INFO] root: pg_monitor started
2026-06-13 14:32:01 [WARNING] root: WAL size exceeding threshold: 8.2 GB
```

---

## Step 6: FileHandler - write logs to a file

`basicConfig()` writes to the console (stdout). To write to a file instead, you use a `FileHandler`. Think of this as switching from `log_destination = 'stderr'` to `log_destination = 'csvlog'` in `postgresql.conf`.

First, create the logs directory:

On your **Mac terminal**, as your **normal user**:

```bash
mkdir -p ~/pgdba/logs
```

Now write a quick test that logs to a file:

```bash
python3 -c "
import logging

# Create a logger
logger = logging.getLogger('dba_test')
logger.setLevel(logging.DEBUG)

# Create a file handler - opens ~/pgdba/logs/test.log for writing
fh = logging.FileHandler('/Users/$(whoami)/pgdba/logs/test.log')
fh.setLevel(logging.DEBUG)

# Create a formatter and attach it to the handler
formatter = logging.Formatter('%(asctime)s [%(levelname)s] %(name)s: %(message)s',
                               datefmt='%Y-%m-%d %H:%M:%S')
fh.setFormatter(formatter)

# Attach the handler to the logger
logger.addHandler(fh)

logger.info('FileHandler test - this goes to the log file')
logger.warning('Disk usage at 78%')
print('Log written. Check ~/pgdba/logs/test.log')
"
```

Expected output (yours will differ):

```
Log written. Check ~/pgdba/logs/test.log
```

Verify the file was created:

```bash
cat ~/pgdba/logs/test.log
```

Expected output (yours will differ):

```
2026-06-13 14:32:05 [INFO] dba_test: FileHandler test - this goes to the log file
2026-06-13 14:32:05 [WARNING] dba_test: Disk usage at 78%
```

---

## Step 7: RotatingFileHandler - rotate when the file gets too big

In `postgresql.conf`, `log_rotation_size` and `log_rotation_age` prevent any single log file from growing unbounded. Python's `RotatingFileHandler` does the same: when the log file reaches a size limit, it renames the current file to `.log.1`, and starts a fresh `.log`. Old rotated files become `.log.2`, `.log.3`, etc.

Parameters:
- `maxBytes` - file size limit before rotation (like `log_rotation_size`)
- `backupCount` - how many rotated files to keep before deleting the oldest

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
from logging.handlers import RotatingFileHandler

logger = logging.getLogger('rotation_test')
logger.setLevel(logging.DEBUG)

# Rotate when file reaches 1 KB, keep 3 old copies
rh = RotatingFileHandler(
    '/Users/$(whoami)/pgdba/logs/rotation_test.log',
    maxBytes=1024,
    backupCount=3
)
formatter = logging.Formatter('%(asctime)s [%(levelname)s]: %(message)s',
                               datefmt='%Y-%m-%d %H:%M:%S')
rh.setFormatter(formatter)
logger.addHandler(rh)

# Write enough lines to trigger rotation
for i in range(50):
    logger.info(f'Log line {i}: simulating high-volume DBA audit events')

print('Done. Check ~/pgdba/logs/ for rotation_test.log and rotation_test.log.1')
"
```

Expected output (yours will differ):

```
Done. Check ~/pgdba/logs/ for rotation_test.log and rotation_test.log.1
```

Verify rotation happened:

```bash
ls -lh ~/pgdba/logs/rotation_test.log*
```

Expected output (yours will differ):

```
-rw-r--r--  1 postgres  staff   987B Jun 13 14:32 rotation_test.log
-rw-r--r--  1 postgres  staff  1.0K Jun 13 14:32 rotation_test.log.1
```

---

## Step 8: getLogger(__name__) - named loggers per module

Every script in a DBA toolkit should have its own named logger. That way, when you see a log line, you know which script produced it - just like `application_name` in `pg_stat_activity` tells you which app is connected.

The convention `logging.getLogger(__name__)` uses the module's file name as the logger name. In a script called `pg_monitor.py`, `__name__` equals `'pg_monitor'`, so the logger is named `'pg_monitor'`.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging

# Named logger - in a real script, use __name__ instead of the string
logger = logging.getLogger('pg_monitor')
logger.setLevel(logging.DEBUG)

handler = logging.StreamHandler()
formatter = logging.Formatter('[%(name)s] %(levelname)s: %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

logger.info('pg_monitor: health check started')
logger.warning('pg_monitor: long-running query detected (PID 4821)')
"
```

Expected output (yours will differ):

```
[pg_monitor] INFO: pg_monitor: health check started
[pg_monitor] WARNING: pg_monitor: long-running query detected (PID 4821)
```

The logger name `pg_monitor` now appears in every log line from this module. If you import a second module (`backup_runner`), its log lines will show `[backup_runner]` - making it easy to filter logs by module.

---

## Step 9: Multiple handlers - console AND file simultaneously

In PostgreSQL, you can set `log_destination = 'stderr,csvlog'` to write to multiple destinations at once. Python handlers work the same way: attach a `StreamHandler` (console) AND a `RotatingFileHandler` (file) to the same logger.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import logging
from logging.handlers import RotatingFileHandler

logger = logging.getLogger('multi_handler_test')
logger.setLevel(logging.DEBUG)

# Handler 1: console (StreamHandler defaults to stderr/stdout)
ch = logging.StreamHandler()
ch.setLevel(logging.INFO)  # console: INFO and above
ch.setFormatter(logging.Formatter('[%(levelname)s] %(message)s'))

# Handler 2: file with rotation
fh = RotatingFileHandler('/Users/$(whoami)/pgdba/logs/multi_test.log',
                         maxBytes=5*1024*1024, backupCount=5)
fh.setLevel(logging.DEBUG)  # file: DEBUG and above (more verbose)
fh.setFormatter(logging.Formatter('%(asctime)s [%(levelname)s] %(name)s: %(message)s',
                                   datefmt='%Y-%m-%d %H:%M:%S'))

logger.addHandler(ch)
logger.addHandler(fh)

logger.debug('DEBUG: only goes to file, not console')
logger.info('INFO: goes to both console and file')
logger.warning('WARNING: goes to both console and file')
"
```

Expected output (yours will differ):

```
[INFO] INFO: goes to both console and file
[WARNING] WARNING: goes to both console and file
```

Only two lines appear on console (INFO and above), but the log file will contain all three lines including the DEBUG one.

---

## Step 10: Build audit_logger.py - the reusable setup_logger() function

Now combine everything into a module other scripts can import. The `setup_logger()` function is the equivalent of a standard `logging.conf` that every DBA script shares.

On your **Mac terminal**, as your **normal user**, create the file:

```bash
python3 -c "
content = '''#!/usr/bin/env python3
\"\"\"
audit_logger.py - Reusable DBA logging setup.

Usage in any script:
    from audit_logger import setup_logger
    logger = setup_logger(__name__)
    logger.info(\"Script started\")
\"\"\"

import logging
import os
from logging.handlers import RotatingFileHandler

LOG_DIR = os.path.expanduser(\"~/pgdba/logs\")
LOG_FILE = os.path.join(LOG_DIR, \"dba_audit.log\")

# 10 MB max per file, keep 7 rotated copies (one week of daily logs)
MAX_BYTES = 10 * 1024 * 1024
BACKUP_COUNT = 7

CONSOLE_FORMAT = \"[%(levelname)s] %(name)s: %(message)s\"
FILE_FORMAT    = \"%(asctime)s [%(levelname)s] %(name)s (%(filename)s:%(lineno)d): %(message)s\"
DATE_FORMAT    = \"%Y-%m-%d %H:%M:%S\"


def setup_logger(name: str, console_level: int = logging.INFO,
                 file_level: int = logging.DEBUG) -> logging.Logger:
    \"\"\"
    Create and return a named logger that writes to console and rotating file.

    Args:
        name:          Logger name - pass __name__ from the calling module.
        console_level: Minimum level for console output. Default: INFO.
        file_level:    Minimum level for file output.   Default: DEBUG.

    Returns:
        logging.Logger: Configured logger instance.
    \"\"\"
    os.makedirs(LOG_DIR, exist_ok=True)

    logger = logging.getLogger(name)

    # Avoid adding duplicate handlers if setup_logger() is called more than once
    if logger.handlers:
        return logger

    logger.setLevel(logging.DEBUG)  # let handlers decide their own floor

    # --- Console handler ---
    ch = logging.StreamHandler()
    ch.setLevel(console_level)
    ch.setFormatter(logging.Formatter(CONSOLE_FORMAT))

    # --- Rotating file handler ---
    fh = RotatingFileHandler(LOG_FILE, maxBytes=MAX_BYTES, backupCount=BACKUP_COUNT)
    fh.setLevel(file_level)
    fh.setFormatter(logging.Formatter(FILE_FORMAT, datefmt=DATE_FORMAT))

    logger.addHandler(ch)
    logger.addHandler(fh)

    return logger


if __name__ == \"__main__\":
    # Quick self-test
    log = setup_logger(__name__)
    log.debug(\"DEBUG: verbose detail - only in file by default\")
    log.info(\"INFO: audit_logger self-test started\")
    log.warning(\"WARNING: this is a sample warning\")
    log.error(\"ERROR: this is a sample error\")
    log.critical(\"CRITICAL: this is a sample critical event\")
    print(f\"\\nLog file written to: {LOG_FILE}\")
'''
with open('/Users/' + __import__('os').environ['USER'] + '/pgdba/audit_logger.py', 'w') as f:
    f.write(content)
print('audit_logger.py written to ~/pgdba/')
"
```

Expected output (yours will differ):

```
audit_logger.py written to ~/pgdba/
```

---

## Step 11: Integrate with pg_monitor.py - add logging to health checks

The real power of `audit_logger.py` is that any script can import it with one line. Here is how to add structured logging to a health check function.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
from audit_logger import setup_logger
import psycopg2

logger = setup_logger('pg_health_check')

def check_connection():
    logger.info('Attempting connection to localhost:5432')
    try:
        conn = psycopg2.connect(
            host='localhost', port=5432, dbname='postgres',
            user=os.environ.get('USER'), connect_timeout=5
        )
        logger.info('Connection successful')
        cur = conn.cursor()
        cur.execute('SELECT count(*) FROM pg_stat_activity')
        count = cur.fetchone()[0]
        logger.info(f'Active connections: {count}')
        conn.close()
        return True
    except psycopg2.OperationalError as e:
        logger.error(f'Connection failed: {e}')
        return False

result = check_connection()
logger.info(f'Health check result: {\"PASS\" if result else \"FAIL\"}')
"
```

Expected output (yours will differ):

```
[INFO] pg_health_check: Attempting connection to localhost:5432
[INFO] pg_health_check: Connection successful
[INFO] pg_health_check: Active connections: 3
[INFO] pg_health_check: Health check result: PASS
```

---

## Step 12: Run audit_logger.py and verify both outputs

Run the self-test built into `audit_logger.py`:

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/audit_logger.py
```

Expected output (yours will differ):

```
[INFO] __main__: INFO: audit_logger self-test started
[WARNING] __main__: WARNING: this is a sample warning
[ERROR] __main__: ERROR: this is a sample error
[CRITICAL] __main__: CRITICAL: this is a sample critical event

Log file written to: /Users/yourname/pgdba/logs/dba_audit.log
```

Now check the log file - it should contain ALL five levels including DEBUG:

```bash
cat ~/pgdba/logs/dba_audit.log
```

Expected output (yours will differ):

```
2026-06-13 14:35:00 [DEBUG] __main__ (audit_logger.py:56): DEBUG: verbose detail - only in file by default
2026-06-13 14:35:00 [INFO] __main__ (audit_logger.py:57): INFO: audit_logger self-test started
2026-06-13 14:35:00 [WARNING] __main__ (audit_logger.py:58): WARNING: this is a sample warning
2026-06-13 14:35:00 [ERROR] __main__ (audit_logger.py:59): ERROR: this is a sample error
2026-06-13 14:35:00 [CRITICAL] __main__ (audit_logger.py:60): CRITICAL: this is a sample critical event
```

The file has all five lines (including DEBUG). The console only showed four (INFO and above). This is exactly the split behavior you configured in Step 9.

---

## Step 13: Demonstrate log level filtering

In production, you often want to suppress INFO-level noise and only see WARNING and above - like setting `log_min_messages = warning` on a busy production server.

Change the `console_level` argument to `WARNING`:

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import sys, os
sys.path.insert(0, os.path.expanduser('~/pgdba'))
import logging
from audit_logger import setup_logger

# Raise the console threshold to WARNING - INFO messages will be suppressed on console
logger = setup_logger('filter_demo', console_level=logging.WARNING)

logger.info('This INFO message will NOT appear on console (only in file)')
logger.info('Another INFO message - also suppressed on console')
logger.warning('This WARNING will appear on console AND in file')
logger.error('This ERROR will appear on console AND in file')
"
```

Expected output (yours will differ):

```
[WARNING] filter_demo: This WARNING will appear on console AND in file
[ERROR] filter_demo: This ERROR will appear on console AND in file
```

Only two lines on console. Check `~/pgdba/logs/dba_audit.log` and you will see all four lines - the DEBUG/INFO messages are captured to file even though they were filtered from the console.

---

## What you built

You now have `~/pgdba/audit_logger.py` - a production-grade logging module that:

- Writes to both console and a rotating log file simultaneously
- Keeps 7 rotated copies of up to 10 MB each (70 MB total log retention)
- Includes timestamps, severity levels, module names, and line numbers in file logs
- Prevents duplicate handlers if imported multiple times
- Can be imported by any future DBA script with `from audit_logger import setup_logger`

Every script you write from BUILD 14 onward will import this module. This is the foundation of your DBA automation audit trail.

---

## What you learned

| Python concept | DBA analogy |
|---|---|
| `logging` vs `print()` | Audit table vs `RAISE NOTICE` |
| Log levels (DEBUG - CRITICAL) | `log_min_messages` (DEBUG5 - PANIC) |
| `logging.basicConfig()` | `logging.conf` / `postgresql.conf` logging section |
| Formatter with `%(asctime)s` | `log_line_prefix = '%t'` |
| `FileHandler` | `log_destination = 'csvlog'` |
| `RotatingFileHandler` | `log_rotation_size` + `log_rotation_age` |
| `getLogger(__name__)` | `application_name` in `pg_stat_activity` |
| Multiple handlers | `log_destination = 'stderr,csvlog'` |

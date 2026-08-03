# BUILD 09: String Formatting - Backup Automator

**What you will build:** `~/pgdba/backup_auto.py` - a script that generates and optionally runs `pg_dump` and `pg_basebackup` commands with proper flags, timestamps, and compression, plus a PITR restore command builder.

**Python concepts covered:** f-strings (review), `str.format()`, multi-line strings (triple quotes), string methods (`join`, `replace`, `upper`, `lower`, `startswith`, `endswith`), `subprocess.run()`

**Time to complete:** ~50 minutes

---

## Prerequisites

- `~/pgdba/` directory exists
- PostgreSQL running locally on port 5432
- `pg_dump` and `pg_basebackup` on your PATH (they come with a Homebrew PostgreSQL install)

---

## Step 1: f-strings review - backup filenames with timestamps

You saw f-strings in BUILD 01. Here you use them for a DBA-specific task: building backup filenames that embed the server name, database name, and timestamp - so you can sort and identify backups at a glance.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import datetime

# The timestamp is the most important part of a backup filename
# Same idea as to_char(now(), 'YYYYMMDD_HH24MISS') in PostgreSQL
now = datetime.datetime.now()
timestamp = now.strftime('%Y%m%d_%H%M%S')

server  = 'pg-prod-1'
dbname  = 'appdb'
format  = 'custom'

# Build the filename with f-string
filename = f'{server}_{dbname}_{timestamp}.dump'
print(f'Backup file: {filename}')

# Build a full path
backup_dir = '/var/lib/postgresql/backups'
full_path  = f'{backup_dir}/{filename}'
print(f'Full path:   {full_path}')
"
```

What each piece does:
- `datetime.datetime.now()` - current timestamp (like `now()` in PostgreSQL)
- `.strftime('%Y%m%d_%H%M%S')` - formats the timestamp as `20260613_094502` (like `to_char(now(), 'YYYYMMDD_HH24MISS')`)
- The f-string glues everything together without explicit concatenation

Expected output (yours will differ):

```
Backup file: pg-prod-1_appdb_20260613_094502.dump
Full path:   /var/lib/postgresql/backups/pg-prod-1_appdb_20260613_094502.dump
```

---

## Step 2: datetime module - generate timestamps for backup names

The `datetime` module is your `to_char()` + `now()` + `age()` equivalent in Python. Learn these four patterns - you will use them in every monitoring, backup, and audit script.

On your **Mac terminal**:

```bash
python3 -c "
import datetime

now = datetime.datetime.now()

# Format patterns - same logic as PostgreSQL to_char()
print(now.strftime('%Y-%m-%d %H:%M:%S'))        # 2026-06-13 09:45:02
print(now.strftime('%Y%m%d'))                    # 20260613  (compact date)
print(now.strftime('%Y%m%d_%H%M%S'))             # 20260613_094502  (filename-safe)
print(now.strftime('%Y-%m-%dT%H:%M:%S'))         # ISO 8601 format

# Date arithmetic - like now() - interval '7 days'
seven_days_ago = now - datetime.timedelta(days=7)
print(f'7 days ago: {seven_days_ago.strftime(\"%Y-%m-%d\")}')

# Check if a backup is older than N hours (useful for monitoring backup age)
backup_time = datetime.datetime(2026, 6, 12, 3, 0, 0)
age_hours   = (now - backup_time).total_seconds() / 3600
print(f'Backup age: {age_hours:.1f} hours')
print(f'Overdue:    {age_hours > 25}')
"
```

What each piece does:
- `strftime(format)` - format a datetime as a string using format codes (same meanings as PostgreSQL format strings)
- `timedelta(days=7)` - a duration object, like `INTERVAL '7 days'`
- `.total_seconds()` - converts a duration to seconds so you can do math

Expected output (yours will differ):

```
2026-06-13 09:45:02
20260613
20260613_094502
2026-06-13T09:45:02
7 days ago: 2026-06-06
Backup age: 30.8 hours
Overdue:    True
```

---

## Step 3: str.format() - alternative string formatting

Before f-strings existed (Python < 3.6), `str.format()` was the standard way to insert values into strings. You will encounter it in older scripts and documentation. The `{}` placeholders work the same as in f-strings, but the values are passed as arguments to `.format()` instead of being embedded directly.

On your **Mac terminal**:

```bash
python3 -c "
server = 'pg-prod-1'
dbname = 'appdb'
port   = 5432

# str.format() - positional placeholders
cmd = 'pg_dump -h {} -p {} -d {}'.format('localhost', port, dbname)
print(cmd)

# Named placeholders - clearer for long strings
cmd2 = 'pg_dump -h {host} -p {port} -d {dbname} -U {user}'.format(
    host=server, port=port, dbname=dbname, user='postgres'
)
print(cmd2)

# You can also use % formatting (very old style - avoid in new code)
cmd3 = 'pg_dump -d %s -p %d' % (dbname, port)
print(cmd3)
"
```

Expected output (yours will differ):

```
pg_dump -h localhost -p 5432 -d appdb
pg_dump -h pg-prod-1 -p 5432 -d appdb -U postgres
pg_dump -d appdb -p 5432
```

Use f-strings for new code. Use `str.format()` when you need to build a template string that gets filled in later.

---

## Step 4: Triple-quoted strings - multi-line commands

Triple quotes (`"""` or `'''`) let you write a string that spans multiple lines without escape characters. This is ideal for multi-line shell commands, SQL queries, or configuration blocks where readability matters.

On your **Mac terminal**:

```bash
python3 -c "
dbname    = 'appdb'
backup_dir = '/var/lib/postgresql/backups'
timestamp  = '20260613_094502'

# Multi-line pg_dump command - easier to read than one long line
cmd = f'''pg_dump \\
    --host=localhost \\
    --port=5432 \\
    --dbname={dbname} \\
    --format=custom \\
    --compress=9 \\
    --file={backup_dir}/{dbname}_{timestamp}.dump'''

print('Command to run:')
print(cmd)
print()
print('As a single line:')
print(cmd.replace(' \\\\\n    ', ' '))
"
```

What each piece does:
- `'''...'''` - triple-quoted string, preserves newlines and indentation literally
- `\\` at the end of each line inside the string - a literal backslash (shell line continuation)
- This is not running the command yet - it is just building the string

Expected output (yours will differ):

```
Command to run:
pg_dump \
    --host=localhost \
    --port=5432 \
    --dbname=appdb \
    --format=custom \
    --compress=9 \
    --file=/var/lib/postgresql/backups/appdb_20260613_094502.dump

As a single line:
pg_dump --host=localhost --port=5432 --dbname=appdb --format=custom --compress=9 --file=/var/lib/postgresql/backups/appdb_20260613_094502.dump
```

---

## Step 5: String methods - join, replace, upper, lower, startswith, endswith

Python strings have built-in methods for common transformations. These map directly to SQL string functions you already know.

On your **Mac terminal**:

```bash
python3 -c "
# .join() - like array_to_string() in PostgreSQL
# Build a comma-separated column list for a selective dump
columns = ['id', 'order_date', 'customer_id', 'total_amount', 'status']
col_list = ', '.join(columns)
print(f'Columns: {col_list}')

# .replace() - like replace() in PostgreSQL
# Swap one path prefix for another in a restore command
old_path = '/var/lib/postgresql/backups/appdb_20260613.dump'
new_path = old_path.replace('/backups/', '/restore/')
print(f'Restore path: {new_path}')

# .upper() and .lower() - like UPPER() and LOWER() in SQL
env   = 'production'
label = env.upper()
print(f'Label: {label}')

# .startswith() and .endswith() - like LEFT() and RIGHT() comparisons
filename = 'pg-prod-1_appdb_20260613_094502.dump'
print(f'Is dump file: {filename.endswith(\".dump\")}')
print(f'Is prod:      {filename.startswith(\"pg-prod\")}')
print(f'Is dev:       {filename.startswith(\"pg-dev\")}')

# .split() - split a filename into parts
parts = filename.replace('.dump', '').split('_')
print(f'Parts: {parts}')
"
```

Expected output (yours will differ):

```
Columns: id, order_date, customer_id, total_amount, status
Restore path: /var/lib/postgresql/restore/appdb_20260613.dump
Label: PRODUCTION
Is dump file: True
Is prod:      True
Is dev:       False
Parts: ['pg-prod-1', 'appdb', '20260613', '094502']
```

---

## Step 6: Build pg_dump command generator

Now write a function that builds a complete `pg_dump` command as a list of arguments. Using a list (rather than a single string) is safer with `subprocess` - it avoids shell injection issues.

On your **Mac terminal**:

```bash
python3 -c "
import datetime
import os
import getpass

def generate_dump_cmd(
    host:       str = 'localhost',
    port:       int = 5432,
    dbname:     str = 'postgres',
    user:       str = None,
    backup_dir: str = None,
    fmt:        str = 'custom',
    compress:   int = 9,
    tables:     list = None
) -> list:
    '''
    Build a pg_dump command as a list of arguments.
    Returns a list suitable for subprocess.run().
    fmt options: custom, plain, directory
    '''
    if user is None:
        user = getpass.getuser()
    if backup_dir is None:
        backup_dir = os.path.expanduser('~/pgdba')

    timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    ext       = 'dump' if fmt == 'custom' else ('sql' if fmt == 'plain' else '')
    filename  = f'{dbname}_{timestamp}.{ext}' if ext else f'{dbname}_{timestamp}'
    filepath  = f'{backup_dir}/{filename}'

    cmd = [
        'pg_dump',
        f'--host={host}',
        f'--port={port}',
        f'--dbname={dbname}',
        f'--username={user}',
        f'--format={fmt}',
        f'--compress={compress}',
        f'--file={filepath}',
        '--verbose'
    ]

    # Add --table flags for selective dumps
    if tables:
        for table in tables:
            cmd.append(f'--table={table}')

    return cmd

cmd = generate_dump_cmd(dbname='postgres', fmt='custom')
print('pg_dump command:')
for arg in cmd:
    print(f'  {arg}')
"
```

Expected output (yours will differ):

```
pg_dump command:
  pg_dump
  --host=localhost
  --port=5432
  --dbname=postgres
  --username=hafopezi
  --format=custom
  --compress=9
  --file=/Users/hafopezi/pgdba/postgres_20260613_094502.dump
  --verbose
```

---

## Step 7: Build pg_basebackup command generator

`pg_basebackup` takes a full physical backup - equivalent to a cold copy of `$PGDATA`. Build a function that generates the command with the WAL method, checkpoint mode, and compression options.

On your **Mac terminal**:

```bash
python3 -c "
import datetime
import os
import getpass

def generate_basebackup_cmd(
    host:        str = 'localhost',
    port:        int = 5432,
    user:        str = None,
    backup_dir:  str = None,
    wal_method:  str = 'stream',
    checkpoint:  str = 'fast',
    compress:    int = 0
) -> list:
    '''
    Build a pg_basebackup command as a list of arguments.
    wal_method options: stream (include WAL inline), fetch (copy after), none
    checkpoint options: fast (forces immediate), spread (spreads I/O)
    compress: 0 = no compression, 1-9 = gzip level
    '''
    if user is None:
        user = getpass.getuser()
    if backup_dir is None:
        backup_dir = os.path.expanduser('~/pgdba')

    timestamp  = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
    backup_path = f'{backup_dir}/basebackup_{timestamp}'

    cmd = [
        'pg_basebackup',
        f'--host={host}',
        f'--port={port}',
        f'--username={user}',
        f'--pgdata={backup_path}',
        f'--wal-method={wal_method}',
        f'--checkpoint={checkpoint}',
        '--format=tar',
        '--progress',
        '--verbose'
    ]

    if compress > 0:
        cmd.append(f'--compress={compress}')

    return cmd

cmd = generate_basebackup_cmd(wal_method='stream', checkpoint='fast', compress=6)
print('pg_basebackup command:')
for arg in cmd:
    print(f'  {arg}')
"
```

What each piece does:
- `--wal-method=stream` - streams WAL during the backup so the backup is immediately recoverable
- `--checkpoint=fast` - forces a checkpoint at the start so the backup is consistent without waiting
- `--format=tar` - stores each tablespace as a `.tar` archive (suitable for offsite storage)
- `--compress=6` - gzip compression level 6 (good balance of speed and size)

Expected output (yours will differ):

```
pg_basebackup command:
  pg_basebackup
  --host=localhost
  --port=5432
  --username=hafopezi
  --pgdata=/Users/hafopezi/pgdba/basebackup_20260613_094502
  --wal-method=stream
  --checkpoint=fast
  --format=tar
  --progress
  --verbose
  --compress=6
```

---

## Step 8: Build PITR restore command generator

Point-In-Time Recovery (PITR) requires you to restore a base backup and then replay WAL up to a specific target time. The restore target is set in `postgresql.conf` (or `recovery.conf` on older versions). Build a function that generates the config block as a formatted string.

On your **Mac terminal**:

```bash
python3 -c "
import datetime

def generate_pitr_config(
    restore_command:     str,
    recovery_target_time: str,
    recovery_target_action: str = 'promote'
) -> str:
    '''
    Generate the postgresql.conf recovery parameters for PITR.
    recovery_target_action options: promote, pause, shutdown
    '''
    config = f'''# PITR Recovery Configuration
# Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# -----------------------------------------------------
# Add these lines to postgresql.conf before starting
# the restored instance. Remove them after promotion.

restore_command          = '{restore_command}'
recovery_target_time     = '{recovery_target_time}'
recovery_target_action   = '{recovery_target_action}'
recovery_target_inclusive = 'true'
'''
    return config

# Generate config for a recovery targeting 1 minute before an incident
target_time = '2026-06-13 09:44:00'
restore_cmd = 'cp /mnt/wal_archive/%f %p'

config = generate_pitr_config(
    restore_command=restore_cmd,
    recovery_target_time=target_time,
    recovery_target_action='promote'
)
print(config)
"
```

What each piece does:
- `restore_command` - the shell command PostgreSQL runs to retrieve archived WAL files; `%f` = filename, `%p` = destination path
- `recovery_target_time` - stop replay at this exact timestamp (like `pg_waldump --start-lsn` targeting a moment before the incident)
- `recovery_target_action = promote` - after reaching the target, promote to primary instead of staying in read-only standby mode

Expected output (yours will differ):

```
# PITR Recovery Configuration
# Generated: 2026-06-13 09:45:02
# -----------------------------------------------------
# Add these lines to postgresql.conf before starting
# the restored instance. Remove them after promotion.

restore_command          = 'cp /mnt/wal_archive/%f %p'
recovery_target_time     = '2026-06-13 09:44:00'
recovery_target_action   = 'promote'
recovery_target_inclusive = 'true'
```

---

## Step 9: subprocess.run() - actually execute a backup command

`subprocess.run()` runs a shell command from Python. You used it briefly in BUILD 01 with `which postgres`. Here you use it to run a real `pg_dump` against your local PostgreSQL.

On your **Mac terminal**:

```bash
python3 -c "
import subprocess

# A simple test: run pg_dump --version to confirm it is available
result = subprocess.run(
    ['pg_dump', '--version'],
    capture_output=True,
    text=True
)

print(f'Return code: {result.returncode}')
print(f'Output:      {result.stdout.strip()}')
print(f'Success:     {result.returncode == 0}')
"
```

What each piece does:
- `subprocess.run(list_of_args, ...)` - runs the command and waits for it to finish
- `capture_output=True` - captures both stdout and stderr so you can inspect them
- `text=True` - returns output as a string (not bytes)
- `result.returncode` - 0 = success, non-zero = failure (same as `$?` in bash)

Expected output (yours will differ):

```
Return code: 0
Output:      pg_dump (PostgreSQL) 16.3
Success:     True
```

Now try running it with `check=True`, which raises an exception on non-zero exit codes:

```bash
python3 -c "
import subprocess

try:
    result = subprocess.run(
        ['pg_dump', '--host=localhost', '--port=5432', '--dbname=nonexistent_db',
         '--username=bogus', '--format=custom', '--file=/dev/null'],
        capture_output=True,
        text=True,
        check=True      # raises CalledProcessError if return code != 0
    )
except subprocess.CalledProcessError as e:
    print(f'Backup FAILED (exit code {e.returncode})')
    print(f'Error: {e.stderr.strip()}')
"
```

Expected output (yours will differ):

```
Backup FAILED (exit code 1)
Error: pg_dump: error: connection to server on socket ...
```

---

## Step 10: Build backup schedule printer

Write a function that prints what would run at each cron interval - a dry-run scheduler. This uses `str.join()` and f-strings to format the output clearly.

On your **Mac terminal**:

```bash
python3 -c "
import datetime

def print_backup_schedule(
    databases:  list,
    backup_dir: str = '/var/lib/postgresql/backups'
) -> None:
    '''
    Print a backup schedule summary - what would run at each interval.
    Helps verify cron configuration before setting it up.
    '''
    now = datetime.datetime.now()
    print('=' * 65)
    print('  Backup Schedule Preview')
    print(f'  Generated: {now.strftime(\"%Y-%m-%d %H:%M:%S\")}')
    print('=' * 65)

    schedules = [
        ('Daily full dump',       '0 2 * * *',   'pg_dump --format=custom --compress=9'),
        ('Weekly base backup',    '0 1 * * 0',   'pg_basebackup --wal-method=stream'),
        ('Hourly WAL archive',    '0 * * * *',   'pg_receivewal (continuous)'),
    ]

    for label, cron, cmd_type in schedules:
        print(f'  {label}')
        print(f'    Cron:      {cron}')
        print(f'    Type:      {cmd_type}')
        print(f'    Databases: {\" | \".join(databases)}')
        print(f'    Output:    {backup_dir}/')
        print()

print_backup_schedule(
    databases=['appdb', 'auditdb', 'reportdb'],
    backup_dir='/var/lib/postgresql/backups'
)
"
```

What each piece does:
- `' | '.join(databases)` - joins the list with ` | ` separators (like `array_to_string(ARRAY[...], ' | ')`)
- The `schedules` list contains tuples - each tuple is one schedule entry
- `for label, cron, cmd_type in schedules` - unpacks each tuple into three named variables

Expected output (yours will differ):

```
=================================================================
  Backup Schedule Preview
  Generated: 2026-06-13 09:45:02
=================================================================
  Daily full dump
    Cron:      0 2 * * *
    Type:      pg_dump --format=custom --compress=9
    Databases: appdb | auditdb | reportdb
    Output:    /var/lib/postgresql/backups/

  Weekly base backup
    Cron:      0 1 * * 0
    Type:      pg_basebackup --wal-method=stream
    Databases: appdb | auditdb | reportdb
    Output:    /var/lib/postgresql/backups/

  Hourly WAL archive
    Cron:      0 * * * *
    Type:      pg_receivewal (continuous)
    Databases: appdb | auditdb | reportdb
    Output:    /var/lib/postgresql/backups/
```

---

## Step 11: Combine into backup_auto.py

Open vi and write the complete script:

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/backup_auto.py
```

Press `i` to enter insert mode, then type or paste the following:

```python
import subprocess
import datetime
import os
import getpass

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
DB_HOST    = 'localhost'
DB_PORT    = 5432
DB_USER    = getpass.getuser()  # auto-detects your Mac username
BACKUP_DIR = os.path.expanduser('~/pgdba')

# -------------------------------------------------------
# Helpers
# -------------------------------------------------------
def _timestamp() -> str:
    return datetime.datetime.now().strftime('%Y%m%d_%H%M%S')

# -------------------------------------------------------
# pg_dump command generator
# -------------------------------------------------------
def generate_dump_cmd(
    dbname:    str,
    fmt:       str  = 'custom',
    compress:  int  = 9,
    tables:    list = None
) -> list:
    '''
    Build a pg_dump command list.
    fmt options: custom, plain, directory
    Returns list suitable for subprocess.run().
    '''
    ext      = 'dump' if fmt == 'custom' else ('sql' if fmt == 'plain' else '')
    filename = f'{dbname}_{_timestamp()}.{ext}' if ext else f'{dbname}_{_timestamp()}'
    filepath = f'{BACKUP_DIR}/{filename}'

    cmd = [
        'pg_dump',
        f'--host={DB_HOST}',
        f'--port={DB_PORT}',
        f'--dbname={dbname}',
        f'--username={DB_USER}',
        f'--format={fmt}',
        f'--compress={compress}',
        f'--file={filepath}',
        '--verbose'
    ]

    if tables:
        for table in tables:
            cmd.append(f'--table={table}')

    return cmd

# -------------------------------------------------------
# pg_basebackup command generator
# -------------------------------------------------------
def generate_basebackup_cmd(
    wal_method: str = 'stream',
    checkpoint: str = 'fast',
    compress:   int = 0
) -> list:
    '''
    Build a pg_basebackup command list.
    wal_method: stream | fetch | none
    checkpoint: fast | spread
    compress: 0 = off, 1-9 = gzip level
    '''
    backup_path = f'{BACKUP_DIR}/basebackup_{_timestamp()}'

    cmd = [
        'pg_basebackup',
        f'--host={DB_HOST}',
        f'--port={DB_PORT}',
        f'--username={DB_USER}',
        f'--pgdata={backup_path}',
        f'--wal-method={wal_method}',
        f'--checkpoint={checkpoint}',
        '--format=tar',
        '--progress',
        '--verbose'
    ]

    if compress > 0:
        cmd.append(f'--compress={compress}')

    return cmd

# -------------------------------------------------------
# PITR recovery config generator
# -------------------------------------------------------
def generate_pitr_config(
    restore_command:        str,
    recovery_target_time:   str,
    recovery_target_action: str = 'promote'
) -> str:
    '''
    Generate postgresql.conf recovery parameters for PITR.
    recovery_target_action: promote | pause | shutdown
    '''
    return f"""# PITR Recovery Configuration
# Generated: {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
# Add to postgresql.conf before starting the restored instance.
# Remove after promotion.

restore_command           = '{restore_command}'
recovery_target_time      = '{recovery_target_time}'
recovery_target_action    = '{recovery_target_action}'
recovery_target_inclusive = 'true'
"""

# -------------------------------------------------------
# Run a backup command
# -------------------------------------------------------
def run_backup(cmd: list, dry_run: bool = False) -> bool:
    '''
    Execute a backup command. Returns True on success.
    Set dry_run=True to print the command without running it.
    '''
    print(f'  Command: {" ".join(cmd[:3])} ...')

    if dry_run:
        print('  [DRY RUN] Would run:')
        for arg in cmd:
            print(f'    {arg}')
        return True

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        print(f'  SUCCESS')
        if result.stdout:
            # Print last 3 lines of verbose output
            lines = result.stdout.strip().splitlines()
            for line in lines[-3:]:
                print(f'    {line}')
        return True
    except subprocess.CalledProcessError as e:
        print(f'  FAILED (exit code {e.returncode})')
        print(f'  Error: {e.stderr.strip()[:200]}')
        return False

# -------------------------------------------------------
# Backup schedule printer
# -------------------------------------------------------
def print_backup_schedule(databases: list) -> None:
    now = datetime.datetime.now()
    print('=' * 65)
    print('  Backup Schedule Preview')
    print(f'  Generated: {now.strftime("%Y-%m-%d %H:%M:%S")}')
    print(f'  Databases: {" | ".join(databases)}')
    print('=' * 65)

    schedules = [
        ('Daily full dump (custom format)', '0 2 * * *',
         'pg_dump --format=custom --compress=9'),
        ('Weekly base backup',              '0 1 * * 0',
         'pg_basebackup --wal-method=stream --checkpoint=fast'),
        ('Continuous WAL streaming',        '(at startup)',
         'pg_receivewal --directory=/archive'),
    ]

    for label, cron, cmd_type in schedules:
        print(f'  {label}')
        print(f'    Cron:   {cron}')
        print(f'    Type:   {cmd_type}')
        print()

# -------------------------------------------------------
# Main
# -------------------------------------------------------
if __name__ == '__main__':
    print('=' * 65)
    print('  Backup Automator')
    print('=' * 65)

    # 1. Show schedule preview
    print_backup_schedule(databases=['postgres'])
    print()

    # 2. Generate and show a pg_dump command (dry run)
    print('--- pg_dump (dry run) ---')
    dump_cmd = generate_dump_cmd(dbname='postgres', fmt='custom', compress=9)
    run_backup(dump_cmd, dry_run=True)
    print()

    # 3. Generate and show a pg_basebackup command (dry run)
    print('--- pg_basebackup (dry run) ---')
    base_cmd = generate_basebackup_cmd(wal_method='stream', checkpoint='fast', compress=6)
    run_backup(base_cmd, dry_run=True)
    print()

    # 4. Show a PITR config example
    print('--- PITR config example ---')
    pitr = generate_pitr_config(
        restore_command='cp /mnt/wal_archive/%f %p',
        recovery_target_time='2026-06-13 09:44:00',
        recovery_target_action='promote'
    )
    print(pitr)

    # 5. Run a real pg_dump (live - not dry run)
    print('--- Running real pg_dump ---')
    live_cmd = generate_dump_cmd(dbname='postgres', fmt='custom', compress=9)
    success  = run_backup(live_cmd, dry_run=False)
    print(f'Backup complete: {success}')
    print('=' * 65)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 12: Run a real pg_dump against local PostgreSQL

On your **Mac terminal**, as your **normal user**:

```bash
python3 ~/pgdba/backup_auto.py
```

Expected output (yours will differ):

```
=================================================================
  Backup Automator
=================================================================
  Backup Schedule Preview
  Generated: 2026-06-13 09:45:02
  Databases: postgres
=================================================================
  Daily full dump (custom format)
    Cron:   0 2 * * *
    Type:   pg_dump --format=custom --compress=9

  Weekly base backup
    Cron:   0 1 * * 0
    Type:   pg_basebackup --wal-method=stream --checkpoint=fast

  Continuous WAL streaming
    Cron:   (at startup)
    Type:   pg_receivewal --directory=/archive


--- pg_dump (dry run) ---
  Command: pg_dump --host=localhost ...
  [DRY RUN] Would run:
    pg_dump
    --host=localhost
    --port=5432
    --dbname=postgres
    --username=hafopezi
    --format=custom
    --compress=9
    --file=/Users/hafopezi/pgdba/postgres_20260613_094502.dump
    --verbose

--- pg_basebackup (dry run) ---
  Command: pg_basebackup --host=localhost ...
  [DRY RUN] Would run:
    pg_basebackup
    ...

--- PITR config example ---
# PITR Recovery Configuration
# Generated: 2026-06-13 09:45:02
...

--- Running real pg_dump ---
  Command: pg_dump --host=localhost ...
  SUCCESS
    pg_dump: dumping contents of table "public.orders"
    pg_dump: done
Backup complete: True
=================================================================
```

Confirm the backup file was created:

```bash
ls -lh ~/pgdba/*.dump
```

Expected output (yours will differ):

```
-rw-r--r--  1 hafopezi  staff   8.3K Jun 13 09:45  postgres_20260613_094502.dump
```

---

## What you built

You now have `~/pgdba/backup_auto.py` - a backup command generator that demonstrates:

| Python concept | DBA analogy |
|---|---|
| f-strings | `'prefix_' \|\| to_char(now(), 'YYYYMMDD_HH24MISS')` |
| `datetime.now().strftime()` | `to_char(now(), 'YYYYMMDD_HH24MISS')` |
| `str.format()` | Parameterized string templates |
| Triple-quoted strings | Multi-line SQL or configuration blocks |
| `.join()` | `array_to_string(ARRAY[...], ',')` |
| `.replace()` | `replace(string, from, to)` |
| `.startswith()` / `.endswith()` | `LEFT(str, n)` / `RIGHT(str, n)` comparisons |
| `subprocess.run()` | Calling OS commands from PL/pgSQL via `EXECUTE` |
| `check=True` | Raising an exception on non-zero exit (like `IF NOT FOUND THEN RAISE`) |

Next: BUILD 10 - Error Handling: Safe DBA Operations

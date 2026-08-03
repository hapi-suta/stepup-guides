# BUILD 12: argparse - Upgrade Planner CLI (Upgrades)

**What you will build:** `~/pgdba/upgrade_planner.py` - a command-line tool that accepts arguments to plan a PostgreSQL major version upgrade, validates the upgrade path, and generates the `pg_upgrade` command for you.

**Python concepts covered:** `argparse.ArgumentParser`, positional vs optional arguments, `choices`, `type`, `default`, `required`, mutually exclusive groups, subparsers

**Time to complete:** ~55 minutes

---

## Prerequisites

- Python 3.8+ (check with `python3 --version`)
- No additional packages needed - `argparse` is part of the Python standard library
- PostgreSQL running locally on port 5432

---

## Step 1: ArgumentParser - define a CLI like a function signature

`argparse` is Python's built-in library for building command-line tools. Think of `ArgumentParser` as defining a function's parameter list - you declare what arguments the tool accepts, their types, and what happens if they are missing. Python then parses `sys.argv` (the command-line arguments) automatically.

On your **Mac terminal**, as your **normal user**:

```bash
python3 -c "
import argparse

# Create the parser - this is like defining a function signature
parser = argparse.ArgumentParser(
    prog='upgrade_planner',
    description='PostgreSQL major version upgrade planner',
    epilog='Example: upgrade_planner plan --from-version 15 --to-version 16'
)

# Print the auto-generated help text
parser.print_help()
"
```

What each argument does:
- `prog` - the name shown in help output (normally the script filename)
- `description` - shown above the argument list in `--help`
- `epilog` - shown below the argument list in `--help`

Expected output (yours will differ):

```
usage: upgrade_planner [-h] ...

PostgreSQL major version upgrade planner

options:
  -h, --help  show this help message and exit

Example: upgrade_planner plan --from-version 15 --to-version 16
```

---

## Step 2: add_argument() - optional arguments with --prefix

Arguments that start with `--` are optional by default (the user does not have to provide them). They are like named parameters in a SQL function - `CREATE FUNCTION f(p_host TEXT DEFAULT 'localhost')`.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')

# Optional arguments - prefixed with --
parser.add_argument('--from-version', help='Current PostgreSQL major version (e.g. 15)')
parser.add_argument('--to-version',   help='Target PostgreSQL major version (e.g. 16)')
parser.add_argument('--data-dir',     help='Path to the current PGDATA directory')

# Parse the arguments passed on the command line
# When called with -c, sys.argv only has the -c string, so we use parse_args([])
# to simulate 'no arguments passed'
args = parser.parse_args([])

# Access each argument as an attribute - dashes become underscores
print(f'from_version: {args.from_version}')
print(f'to_version:   {args.to_version}')
print(f'data_dir:     {args.data_dir}')
"
```

What this does: `--from-version` becomes `args.from_version` (Python converts hyphens to underscores). When no argument is provided and there is no `default`, the value is `None` - same as a SQL function parameter with `DEFAULT NULL`.

Expected output (yours will differ):

```
from_version: None
to_version:   None
data_dir:     None
```

---

## Step 3: Positional arguments - required by position

A positional argument has no `--` prefix. It is required by default and matched by its position on the command line - like `pg_dump dbname` where `dbname` is positional and must be provided.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')

# Positional: must be provided, matched by position
parser.add_argument('action', help='What to do: check, plan, or generate')

# Optional: prefixed with --, not required
parser.add_argument('--from-version', help='Current PostgreSQL version number')

# Simulate calling: upgrade_planner plan --from-version 15
args = parser.parse_args(['plan', '--from-version', '15'])

print(f'action:       {args.action}')
print(f'from_version: {args.from_version}')
"
```

What this does: `'action'` with no dashes is a positional argument. When we call `parse_args(['plan', '--from-version', '15'])`, Python assigns `'plan'` to `action` and `'15'` to `from_version`.

Expected output (yours will differ):

```
action:       plan
from_version: 15
```

---

## Step 4: choices - restrict valid inputs

`choices` limits what values a user can pass - like a `CHECK` constraint on a column. If the user passes a value not in the list, argparse prints an error message automatically.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')

# choices acts like: CHECK (version IN (14, 15, 16, 17))
parser.add_argument(
    '--from-version',
    choices=['13', '14', '15', '16'],
    help='Current PostgreSQL major version. Valid: 13, 14, 15, 16'
)
parser.add_argument(
    '--to-version',
    choices=['14', '15', '16', '17'],
    help='Target PostgreSQL major version. Valid: 14, 15, 16, 17'
)

# Simulate a valid call
args = parser.parse_args(['--from-version', '15', '--to-version', '16'])
print(f'Valid:  from={args.from_version}  to={args.to_version}')

# Simulate an invalid call - argparse will call sys.exit() with an error message
# Uncomment the line below to see the error:
# args = parser.parse_args(['--from-version', '99'])
"
```

What this does: argparse validates the input against `choices` before your code even runs. Invalid input produces a clear error message like `error: argument --from-version: invalid choice: '99' (choose from '13', '14', '15', '16')`.

Expected output (yours will differ):

```
Valid:  from=15  to=16
```

---

## Step 5: default and required - like DEFAULT and NOT NULL

`default` sets the value when the argument is not provided - like `DEFAULT` in a column definition. `required=True` makes an optional argument mandatory - like `NOT NULL` with no default.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')

# default: like DEFAULT '/var/lib/pgsql/16/data' in a column definition
parser.add_argument(
    '--data-dir',
    default='/var/lib/pgsql/data',
    help='Path to PGDATA directory (default: /var/lib/pgsql/data)'
)

# required=True: like NOT NULL - must be provided even though it has --prefix
parser.add_argument(
    '--from-version',
    required=True,
    choices=['13', '14', '15', '16'],
    help='Current PostgreSQL major version (REQUIRED)'
)

# Optional with a default
parser.add_argument(
    '--method',
    default='pg_upgrade',
    choices=['pg_upgrade', 'dump_restore', 'logical'],
    help='Upgrade method (default: pg_upgrade)'
)

args = parser.parse_args(['--from-version', '15'])

print(f'from_version: {args.from_version}')
print(f'data_dir:     {args.data_dir}')
print(f'method:       {args.method}')
"
```

What this does: even though `--data-dir` and `--method` were not passed, they have defaults. `--from-version` is `required=True`, so omitting it would produce an error: `error: the following arguments are required: --from-version`.

Expected output (yours will differ):

```
from_version: 15
data_dir:     /var/lib/pgsql/data
method:       pg_upgrade
```

---

## Step 6: type= - automatic type conversion

By default, argparse gives you every argument as a string. The `type` parameter automatically converts the input to the specified Python type - like PostgreSQL casting an input `TEXT` to `INTEGER` for you.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')

# Without type=int, version would be the string '15' not the integer 15
# With type=int, argparse calls int('15') and stores 15
parser.add_argument('--from-version', type=int, choices=[13, 14, 15, 16])
parser.add_argument('--to-version',   type=int, choices=[14, 15, 16, 17])
parser.add_argument('--port',         type=int, default=5432)
parser.add_argument('--parallel',     type=int, default=4,
                    help='Number of worker processes for pg_upgrade')

args = parser.parse_args(['--from-version', '15', '--to-version', '16', '--parallel', '8'])

print(f'from_version type: {type(args.from_version)}  value: {args.from_version}')
print(f'to_version type:   {type(args.to_version)}    value: {args.to_version}')
print(f'port type:         {type(args.port)}           value: {args.port}')
print(f'parallel type:     {type(args.parallel)}       value: {args.parallel}')

# Now you can do arithmetic directly - no int() conversion needed
version_diff = args.to_version - args.from_version
print(f'Version gap: {version_diff} major version(s)')
"
```

What this does: `type=int` tells argparse to call `int()` on the raw string input. If the user passes a non-integer like `--port abc`, argparse prints `error: argument --port: invalid int value: 'abc'` before your code runs.

Expected output (yours will differ):

```
from_version type: <class 'int'>  value: 15
to_version type:   <class 'int'>  value: 16
port type:         <class 'int'>   value: 5432
parallel type:     <class 'int'>   value: 8
Version gap: 1 major version(s)
```

---

## Step 7: Parse args and use them - detect the current PostgreSQL version

Now build a function that detects the running PostgreSQL version by querying the database, and compare it to the `--from-version` argument.

On your **Mac terminal**:

```bash
python3 -c "
import argparse
import psycopg2

def get_pg_version() -> int:
    '''Query the running PostgreSQL instance for its major version number.'''
    conn = psycopg2.connect(host='localhost', port=5432, dbname='postgres')
    try:
        with conn.cursor() as cur:
            cur.execute('SHOW server_version_num')
            version_num = int(cur.fetchone()[0])
            # server_version_num format: XXYYZZ (e.g. 160003 = 16.3)
            major_version = version_num // 10000
            return major_version
    finally:
        conn.close()

parser = argparse.ArgumentParser(prog='upgrade_planner')
parser.add_argument('--from-version', type=int, choices=[13, 14, 15, 16],
                    help='Expected current version (will be validated against running PG)')
parser.add_argument('--to-version', type=int, choices=[14, 15, 16, 17], required=True)

args = parser.parse_args(['--from-version', '16', '--to-version', '17'])

actual_version = get_pg_version()
print(f'Running PostgreSQL version: {actual_version}')
print(f'--from-version argument:    {args.from_version}')
print(f'--to-version argument:      {args.to_version}')

if args.from_version and args.from_version != actual_version:
    print(f'WARNING: --from-version {args.from_version} does not match running version {actual_version}')
else:
    print('Version check: OK')
"
```

What `server_version_num` returns: a 6-digit integer where the first two digits are the major version. `160003` means PostgreSQL 16.3. Integer division by `10000` extracts the major version.

Expected output (yours will differ):

```
Running PostgreSQL version: 16
--from-version argument:    16
--to-version argument:      17
Version check: OK
```

---

## Step 8: Build the upgrade path validator

PostgreSQL supports single-version jumps with `pg_upgrade` (14 to 15, 15 to 16, etc.) and multi-version jumps (14 to 16 directly). However, you cannot go backwards (16 to 15 is not supported). This function validates the requested upgrade path.

On your **Mac terminal**:

```bash
python3 -c "
def validate_upgrade_path(from_ver: int, to_ver: int) -> tuple[bool, str]:
    '''
    Validate whether the upgrade path from_ver -> to_ver is supported.
    Returns (is_valid, message).
    '''
    SUPPORTED_VERSIONS = [13, 14, 15, 16, 17]

    if from_ver not in SUPPORTED_VERSIONS:
        return False, f'Version {from_ver} is not a supported upgrade source.'

    if to_ver not in SUPPORTED_VERSIONS:
        return False, f'Version {to_ver} is not a supported upgrade target.'

    if from_ver == to_ver:
        return False, f'Source and target are both version {from_ver}. Nothing to do.'

    if to_ver < from_ver:
        return False, (
            f'Cannot downgrade from {from_ver} to {to_ver}. '
            f'PostgreSQL does not support major version downgrades.'
        )

    # Multi-version jumps are supported by pg_upgrade but require care
    if to_ver - from_ver > 1:
        return True, (
            f'Direct upgrade {from_ver} -> {to_ver} is supported by pg_upgrade. '
            f'Note: you are skipping {to_ver - from_ver - 1} intermediate version(s). '
            f'Test thoroughly in a staging environment first.'
        )

    return True, f'Upgrade path {from_ver} -> {to_ver} is supported.'

# Test several paths
test_cases = [
    (15, 16), (14, 16), (16, 16), (16, 15), (16, 99), (13, 17)
]
for f, t in test_cases:
    valid, msg = validate_upgrade_path(f, t)
    status = 'OK    ' if valid else 'ERROR '
    print(f'{status}  {f} -> {t}: {msg}')
"
```

What `tuple[bool, str]` means: a function can return more than one value in Python by returning a tuple. The caller unpacks it with `is_valid, message = validate_upgrade_path(...)` - like a function returning a composite type in PostgreSQL.

Expected output (yours will differ):

```
OK      15 -> 16: Upgrade path 15 -> 16 is supported.
OK      14 -> 16: Direct upgrade 14 -> 16 is supported by pg_upgrade. Note: you are skipping 1 intermediate version(s). Test thoroughly in a staging environment first.
ERROR   16 -> 16: Source and target are both version 16. Nothing to do.
ERROR   16 -> 15: Cannot downgrade from 16 to 15. PostgreSQL does not support major version downgrades.
ERROR   16 -> 99: Version 99 is not a supported upgrade target.
OK      13 -> 17: Direct upgrade 13 -> 17 is supported by pg_upgrade. Note: you are skipping 3 intermediate version(s). ...
```

---

## Step 9: Build the pg_upgrade command generator

`pg_upgrade` requires several path arguments. Rather than memorizing the syntax, this function generates the exact command based on the arguments provided.

On your **Mac terminal**:

```bash
python3 -c "
def generate_pg_upgrade_command(
    from_ver: int,
    to_ver: int,
    old_data_dir: str,
    new_data_dir: str,
    old_bin_dir: str,
    new_bin_dir: str,
    parallel: int = 4,
    check_only: bool = False,
) -> str:
    '''Generate the pg_upgrade command for the given upgrade parameters.'''
    flags = [
        f'--old-datadir={old_data_dir}',
        f'--new-datadir={new_data_dir}',
        f'--old-bindir={old_bin_dir}',
        f'--new-bindir={new_bin_dir}',
        f'--jobs={parallel}',
    ]
    if check_only:
        flags.append('--check')

    flag_str = ' \\\n    '.join(flags)
    return f'pg_upgrade \\\n    {flag_str}'

cmd = generate_pg_upgrade_command(
    from_ver=15,
    to_ver=16,
    old_data_dir='/var/lib/pgsql/15/data',
    new_data_dir='/var/lib/pgsql/16/data',
    old_bin_dir='/usr/pgsql-15/bin',
    new_bin_dir='/usr/pgsql-16/bin',
    parallel=4,
    check_only=True,
)

print('Generated command:')
print()
print(cmd)
"
```

What `check_only` does: `pg_upgrade --check` runs all pre-upgrade checks without actually performing the upgrade - like a dry run. Always run this first before the real upgrade.

Expected output (yours will differ):

```
Generated command:

pg_upgrade \
    --old-datadir=/var/lib/pgsql/15/data \
    --new-datadir=/var/lib/pgsql/16/data \
    --old-bindir=/usr/pgsql-15/bin \
    --new-bindir=/usr/pgsql-16/bin \
    --jobs=4 \
    --check
```

---

## Step 10: mutually exclusive groups - --in-place vs --dump-restore

A mutually exclusive group prevents two arguments from being used together - like a `CHECK` constraint that says two columns cannot both be non-null. `pg_upgrade` and dump/restore are different upgrade methods and cannot both be specified at once.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')
parser.add_argument('--from-version', type=int, required=True)
parser.add_argument('--to-version',   type=int, required=True)

# Mutually exclusive group: the user can specify --in-place OR --dump-restore
# but not both. Like CHECK(NOT (in_place AND dump_restore)).
method_group = parser.add_mutually_exclusive_group()
method_group.add_argument(
    '--in-place',
    action='store_true',
    help='Use pg_upgrade for in-place binary upgrade (faster, no extra disk needed)'
)
method_group.add_argument(
    '--dump-restore',
    action='store_true',
    help='Use pg_dump + restore (slower, requires extra disk, safer for cross-platform)'
)

# Valid: only --in-place
args = parser.parse_args(['--from-version', '15', '--to-version', '16', '--in-place'])
print(f'in_place={args.in_place}  dump_restore={args.dump_restore}')

# Valid: only --dump-restore
args = parser.parse_args(['--from-version', '15', '--to-version', '16', '--dump-restore'])
print(f'in_place={args.in_place}  dump_restore={args.dump_restore}')

# This would fail with: error: argument --dump-restore: not allowed with argument --in-place
# Uncomment to see:
# args = parser.parse_args(['--from-version', '15', '--to-version', '16', '--in-place', '--dump-restore'])
"
```

What `action='store_true'` does: when the flag is present, the attribute is set to `True`. When absent, it is `False`. Used for on/off switches - like boolean configuration flags.

Expected output (yours will differ):

```
in_place=True  dump_restore=False
in_place=False  dump_restore=True
```

---

## Step 11: subparsers - check, plan, generate sub-commands

Subparsers let you build a tool with multiple sub-commands - like `git commit`, `git push`, `git status`. Each sub-command can have its own set of arguments. This is the pattern used by `pg_basebackup`, `pgbench`, and most professional CLI tools.

On your **Mac terminal**:

```bash
python3 -c "
import argparse

parser = argparse.ArgumentParser(prog='upgrade_planner')
subparsers = parser.add_subparsers(dest='command', help='Sub-command to run')

# Sub-command: check - detects current version, no extra args needed
check_parser = subparsers.add_parser('check', help='Detect current PostgreSQL version')
check_parser.add_argument('--port', type=int, default=5432)

# Sub-command: plan - validates the upgrade path
plan_parser = subparsers.add_parser('plan', help='Validate an upgrade path')
plan_parser.add_argument('--from-version', type=int, required=True, choices=[13,14,15,16])
plan_parser.add_argument('--to-version',   type=int, required=True, choices=[14,15,16,17])

# Sub-command: generate - generates the pg_upgrade command
gen_parser = subparsers.add_parser('generate', help='Generate pg_upgrade command')
gen_parser.add_argument('--from-version', type=int, required=True, choices=[13,14,15,16])
gen_parser.add_argument('--to-version',   type=int, required=True, choices=[14,15,16,17])
gen_parser.add_argument('--old-data-dir', required=True)
gen_parser.add_argument('--new-data-dir', required=True)
gen_parser.add_argument('--parallel', type=int, default=4)

# Simulate: upgrade_planner plan --from-version 15 --to-version 16
args = parser.parse_args(['plan', '--from-version', '15', '--to-version', '16'])
print(f'command:       {args.command}')
print(f'from_version:  {args.from_version}')
print(f'to_version:    {args.to_version}')

# Simulate: upgrade_planner check --port 5433
args = parser.parse_args(['check', '--port', '5433'])
print(f'command:       {args.command}')
print(f'port:          {args.port}')
"
```

What `dest='command'` does: stores the name of the chosen sub-command as `args.command`. You then use `if args.command == 'plan':` to branch to the right handler.

Expected output (yours will differ):

```
command:       plan
from_version:  15
to_version:    16
command:       check
port:          5433
```

---

## Step 12: Write upgrade_planner.py

Combine everything into the complete upgrade planner script.

On your **Mac terminal**, as your **normal user**:

```bash
vi ~/pgdba/upgrade_planner.py
```

Press `i` to enter insert mode, then paste the following:

```python
import argparse
import sys
from typing import Optional
import psycopg2

# -------------------------------------------------------
# Configuration
# -------------------------------------------------------
SUPPORTED_FROM_VERSIONS = [13, 14, 15, 16]
SUPPORTED_TO_VERSIONS   = [14, 15, 16, 17]

DEFAULT_BIN_DIR_TEMPLATE = '/usr/pgsql-{version}/bin'
DEFAULT_DATA_DIR_TEMPLATE = '/var/lib/pgsql/{version}/data'


# -------------------------------------------------------
# Helper functions
# -------------------------------------------------------

def get_running_pg_version(host: str = 'localhost', port: int = 5432) -> Optional[int]:
    """Connect to PostgreSQL and return the running major version number."""
    try:
        conn = psycopg2.connect(host=host, port=port, dbname='postgres',
                                connect_timeout=5)
        try:
            with conn.cursor() as cur:
                cur.execute('SHOW server_version_num')
                version_num = int(cur.fetchone()[0])
                return version_num // 10000
        finally:
            conn.close()
    except psycopg2.OperationalError as e:
        print(f'ERROR: Cannot connect to PostgreSQL at {host}:{port}: {e}', file=sys.stderr)
        return None


def validate_upgrade_path(from_ver: int, to_ver: int) -> tuple[bool, str]:
    """
    Validate whether upgrading from_ver -> to_ver is supported.
    Returns (is_valid, message).
    """
    if from_ver == to_ver:
        return False, f'Source and target are both version {from_ver}. Nothing to do.'

    if to_ver < from_ver:
        return False, (
            f'Cannot downgrade from {from_ver} to {to_ver}. '
            f'PostgreSQL does not support major version downgrades.'
        )

    if to_ver - from_ver > 1:
        skipped = to_ver - from_ver - 1
        return True, (
            f'Direct upgrade {from_ver} -> {to_ver} is supported by pg_upgrade. '
            f'You are skipping {skipped} intermediate version(s). '
            f'Test in staging first.'
        )

    return True, f'Upgrade path {from_ver} -> {to_ver} is supported by pg_upgrade.'


def generate_pg_upgrade_cmd(
    old_data_dir: str,
    new_data_dir: str,
    old_bin_dir: str,
    new_bin_dir: str,
    parallel: int = 4,
    check_only: bool = False,
    link_mode: bool = False,
) -> str:
    """Build the pg_upgrade shell command string."""
    flags = [
        f'--old-datadir={old_data_dir}',
        f'--new-datadir={new_data_dir}',
        f'--old-bindir={old_bin_dir}',
        f'--new-bindir={new_bin_dir}',
        f'--jobs={parallel}',
    ]
    if link_mode:
        flags.append('--link')
    if check_only:
        flags.append('--check')

    flag_str = ' \\\n    '.join(flags)
    return f'pg_upgrade \\\n    {flag_str}'


def generate_dump_restore_cmds(from_ver: int, to_ver: int,
                                 dbname: str = 'all') -> list[str]:
    """Generate pg_dumpall + restore commands for the dump-restore method."""
    dump_cmd = (
        f'# Step 1: Dump all databases from the old cluster\n'
        f'sudo su - postgres\n'
        f'/usr/pgsql-{from_ver}/bin/pg_dumpall -p 5432 > /tmp/pg{from_ver}_full.sql'
    )
    restore_cmd = (
        f'# Step 2: Restore into the new cluster (already initialized and started on 5433)\n'
        f'/usr/pgsql-{to_ver}/bin/psql -p 5433 -f /tmp/pg{from_ver}_full.sql postgres'
    )
    return [dump_cmd, restore_cmd]


# -------------------------------------------------------
# Sub-command handlers
# -------------------------------------------------------

def cmd_check(args: argparse.Namespace) -> int:
    """Detect current PostgreSQL version."""
    print(f'Checking PostgreSQL version at localhost:{args.port}...')
    version = get_running_pg_version(port=args.port)
    if version is None:
        return 1
    print(f'Running PostgreSQL major version: {version}')
    if version in SUPPORTED_FROM_VERSIONS:
        print(f'Version {version} can be upgraded to any of: '
              f'{[v for v in SUPPORTED_TO_VERSIONS if v > version]}')
    else:
        print(f'Version {version} is not in the supported upgrade source list.')
    return 0


def cmd_plan(args: argparse.Namespace) -> int:
    """Validate the requested upgrade path."""
    print(f'Validating upgrade path: {args.from_version} -> {args.to_version}')

    # Validate the path
    is_valid, message = validate_upgrade_path(args.from_version, args.to_version)
    status = 'OK' if is_valid else 'INVALID'
    print(f'[{status}] {message}')

    if not is_valid:
        return 1

    # Cross-check against the running instance if possible
    running = get_running_pg_version()
    if running is not None and running != args.from_version:
        print(f'WARNING: --from-version {args.from_version} does not match '
              f'running version {running}. Double-check your target server.')

    # Print estimated steps
    print()
    print('Upgrade plan summary:')
    print(f'  1. Stop the {args.from_version} cluster (pg_ctl stop or systemctl)')
    print(f'  2. Install PostgreSQL {args.to_version} binaries')
    print(f'  3. Initialize a new {args.to_version} data directory (initdb)')
    print(f'  4. Run: upgrade_planner.py generate --from-version {args.from_version} '
          f'--to-version {args.to_version} --check')
    print(f'  5. Fix any pg_upgrade --check failures')
    print(f'  6. Run: upgrade_planner.py generate --from-version {args.from_version} '
          f'--to-version {args.to_version} (without --check to run the real upgrade)')
    print(f'  7. Start the {args.to_version} cluster')
    print(f'  8. Run: vacuumdb --all --analyze-in-stages')
    print(f'  9. Validate, then delete the old cluster')
    return 0


def cmd_generate(args: argparse.Namespace) -> int:
    """Generate upgrade commands."""
    is_valid, message = validate_upgrade_path(args.from_version, args.to_version)
    if not is_valid:
        print(f'ERROR: {message}', file=sys.stderr)
        return 1

    old_data = args.old_data_dir or DEFAULT_DATA_DIR_TEMPLATE.format(version=args.from_version)
    new_data = args.new_data_dir or DEFAULT_DATA_DIR_TEMPLATE.format(version=args.to_version)
    old_bin  = DEFAULT_BIN_DIR_TEMPLATE.format(version=args.from_version)
    new_bin  = DEFAULT_BIN_DIR_TEMPLATE.format(version=args.to_version)

    if args.dump_restore:
        print(f'# Dump-restore upgrade: PostgreSQL {args.from_version} -> {args.to_version}')
        print()
        for cmd in generate_dump_restore_cmds(args.from_version, args.to_version):
            print(cmd)
            print()
    else:
        check_flag = not args.no_check
        link_flag  = args.link_mode

        print(f'# pg_upgrade command: PostgreSQL {args.from_version} -> {args.to_version}')
        if check_flag:
            print('# Running in CHECK MODE (--check). No data will be modified.')
            print('# Remove --check when you are ready for the real upgrade.')
        if link_flag:
            print('# LINK MODE enabled (--link). Old data files will be hard-linked.')
            print('# This is faster but makes rollback harder.')
        print()
        print('# Run as the postgres OS user:')
        print('sudo su - postgres')
        print()
        cmd = generate_pg_upgrade_cmd(
            old_data_dir=old_data,
            new_data_dir=new_data,
            old_bin_dir=old_bin,
            new_bin_dir=new_bin,
            parallel=args.parallel,
            check_only=check_flag,
            link_mode=link_flag,
        )
        print(cmd)
        print()
        print('exit')

    return 0


# -------------------------------------------------------
# Argument parser setup
# -------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog='upgrade_planner',
        description='PostgreSQL major version upgrade planner',
        epilog=(
            'Examples:\n'
            '  upgrade_planner.py check\n'
            '  upgrade_planner.py plan --from-version 15 --to-version 16\n'
            '  upgrade_planner.py generate --from-version 15 --to-version 16\n'
            '  upgrade_planner.py generate --from-version 15 --to-version 16 --dump-restore'
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    subparsers = parser.add_subparsers(dest='command', metavar='COMMAND')
    subparsers.required = True

    # --- check sub-command ---
    check_p = subparsers.add_parser('check', help='Detect the running PostgreSQL version')
    check_p.add_argument('--port', type=int, default=5432,
                         help='PostgreSQL port to check (default: 5432)')

    # --- plan sub-command ---
    plan_p = subparsers.add_parser('plan', help='Validate an upgrade path and list steps')
    plan_p.add_argument('--from-version', type=int, required=True,
                         choices=SUPPORTED_FROM_VERSIONS,
                         help='Current PostgreSQL major version')
    plan_p.add_argument('--to-version', type=int, required=True,
                         choices=SUPPORTED_TO_VERSIONS,
                         help='Target PostgreSQL major version')

    # --- generate sub-command ---
    gen_p = subparsers.add_parser('generate', help='Generate the upgrade command')
    gen_p.add_argument('--from-version', type=int, required=True,
                        choices=SUPPORTED_FROM_VERSIONS,
                        help='Current PostgreSQL major version')
    gen_p.add_argument('--to-version', type=int, required=True,
                        choices=SUPPORTED_TO_VERSIONS,
                        help='Target PostgreSQL major version')
    gen_p.add_argument('--old-data-dir', default=None,
                        help='Path to old PGDATA (default: /var/lib/pgsql/{from}/data)')
    gen_p.add_argument('--new-data-dir', default=None,
                        help='Path to new PGDATA (default: /var/lib/pgsql/{to}/data)')
    gen_p.add_argument('--parallel', type=int, default=4,
                        help='Number of pg_upgrade worker processes (default: 4)')
    gen_p.add_argument('--no-check', action='store_true',
                        help='Skip --check mode and generate the real upgrade command')
    gen_p.add_argument('--link-mode', action='store_true',
                        help='Use hard links instead of copying data files (faster, harder to roll back)')

    # Mutually exclusive: pg_upgrade (default) or dump-restore
    method_group = gen_p.add_mutually_exclusive_group()
    method_group.add_argument('--dump-restore', action='store_true',
                               help='Generate pg_dumpall + restore commands instead of pg_upgrade')

    return parser


# -------------------------------------------------------
# Entry point
# -------------------------------------------------------

if __name__ == '__main__':
    parser = build_parser()
    args = parser.parse_args()

    if args.command == 'check':
        sys.exit(cmd_check(args))
    elif args.command == 'plan':
        sys.exit(cmd_plan(args))
    elif args.command == 'generate':
        sys.exit(cmd_generate(args))
    else:
        parser.print_help()
        sys.exit(1)
```

Press `Esc`, then type `:wq` and press Enter to save and exit.

---

## Step 13: Test all three sub-commands

On your **Mac terminal**, as your **normal user**:

Test the `check` sub-command:

```bash
python3 ~/pgdba/upgrade_planner.py check
```

Expected output (yours will differ):

```
Checking PostgreSQL version at localhost:5432...
Running PostgreSQL major version: 16
Version 16 can be upgraded to any of: [17]
```

Test the `plan` sub-command:

```bash
python3 ~/pgdba/upgrade_planner.py plan --from-version 15 --to-version 16
```

Expected output (yours will differ):

```
Validating upgrade path: 15 -> 16
[OK] Upgrade path 15 -> 16 is supported by pg_upgrade.
WARNING: --from-version 15 does not match running version 16. Double-check your target server.

Upgrade plan summary:
  1. Stop the 15 cluster (pg_ctl stop or systemctl)
  2. Install PostgreSQL 16 binaries
  3. Initialize a new 16 data directory (initdb)
  4. Run: upgrade_planner.py generate --from-version 15 --to-version 16 --check
  ...
```

Test the `generate` sub-command:

```bash
python3 ~/pgdba/upgrade_planner.py generate --from-version 15 --to-version 16
```

Expected output (yours will differ):

```
# pg_upgrade command: PostgreSQL 15 -> 16
# Running in CHECK MODE (--check). No data will be modified.
# Remove --check when you are ready for the real upgrade.

# Run as the postgres OS user:
sudo su - postgres

pg_upgrade \
    --old-datadir=/var/lib/pgsql/15/data \
    --new-datadir=/var/lib/pgsql/16/data \
    --old-bindir=/usr/pgsql-15/bin \
    --new-bindir=/usr/pgsql-16/bin \
    --jobs=4 \
    --check

exit
```

---

## Step 14: Test the built-in help and error handling

On your **Mac terminal**:

View the top-level help:

```bash
python3 ~/pgdba/upgrade_planner.py --help
```

View the generate sub-command help:

```bash
python3 ~/pgdba/upgrade_planner.py generate --help
```

Test that an invalid version triggers the choices constraint:

```bash
python3 ~/pgdba/upgrade_planner.py plan --from-version 99 --to-version 16
```

Expected output (yours will differ):

```
usage: upgrade_planner plan [-h] --from-version {13,14,15,16} --to-version {14,15,16,17}
upgrade_planner plan: error: argument --from-version: invalid choice: 99 (choose from 13, 14, 15, 16)
```

Test the mutually exclusive group:

```bash
python3 ~/pgdba/upgrade_planner.py generate --from-version 15 --to-version 16 --dump-restore
```

Expected output (yours will differ):

```
# Dump-restore upgrade: PostgreSQL 15 -> 16

# Step 1: Dump all databases from the old cluster
sudo su - postgres
/usr/pgsql-15/bin/pg_dumpall -p 5432 > /tmp/pg15_full.sql

# Step 2: Restore into the new cluster (already initialized and started on 5433)
/usr/pgsql-16/bin/psql -p 5433 -f /tmp/pg15_full.sql postgres
```

---

## What you built

You now have `~/pgdba/upgrade_planner.py` - a professional CLI tool with three sub-commands, type-validated arguments, and automatic help generation. Here is how the Python concepts map to DBA knowledge:

| Python concept | DBA analogy |
|---|---|
| `ArgumentParser` | Defining a function signature with typed parameters |
| `--optional-arg` | Named function parameter: `p_host TEXT DEFAULT 'localhost'` |
| `positional_arg` | Positional function parameter: `CREATE FUNCTION f(dbname TEXT)` |
| `choices=[13,14,15,16]` | `CHECK (version IN (13, 14, 15, 16))` constraint |
| `required=True` | `NOT NULL` with no `DEFAULT` |
| `type=int` | `CAST(input AS INTEGER)` - automatic type enforcement |
| `default='value'` | `DEFAULT 'value'` in column or function definition |
| `add_mutually_exclusive_group()` | `CHECK (NOT (in_place AND dump_restore))` |
| `subparsers` | `pg_dump`, `pg_restore`, `pg_basebackup` - same binary, different modes |

Next: BUILD 13 - Exception Handling: Automated Backup Manager

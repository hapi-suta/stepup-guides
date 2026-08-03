---
layout: default
title: "Shell Scripting Fundamentals"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 1
---

# Shell Scripting Fundamentals

## Why Should a DBA Learn Shell Scripting?

You already know SQL. You can create roles, grant privileges, build schemas, and manage
tablespaces without breaking a sweat. But you are probably running the same SQL commands
over and over, just changing a database name or a role prefix.

Every time you provision a new application database, you:

1. Create a read group, a write group, and an app user
2. Create the database
3. Grant connect privileges
4. Create schemas and set up default privileges
5. Grant role memberships to individual users

That is five steps minimum, each with the application name baked in. Multiply that by
20 applications and you are doing the same work 100 times with minor variations.

Shell scripting lets you turn that repetitive SQL into a reusable tool. You write the
logic once, pass in the application name as a parameter, and the script handles
everything. Instead of copy-pasting SQL and doing find-and-replace, you run:

```bash
./provision-db.sh promos
```

And the script creates `promos_read_group`, `promos_write_group`, `promos_app_one`,
the `promos` database, and all the grants. Same script, different argument, different
database - every time.

That is the goal of this module. But first, you need the fundamentals.

---

## What Is a Shell Script?

A shell script is a plain text file containing commands that the shell executes one by
one. You already use the shell every time you type `ls`, `psql`, or `systemctl`. A
shell script just puts those commands into a file so you can run them repeatedly.

If you can type it at the terminal prompt, you can put it in a script file.

```bash
#!/bin/bash
echo "Hello from a shell script"
```

Two lines. The first line is special (covered next), and the second is the same `echo`
command you would type at your terminal.

---

## The Shebang Line

The very first line of every shell script should be:

```bash
#!/bin/bash
```

This is called the **shebang** (or hashbang). It tells the OS which program should
interpret the file.

- `#!` - The shebang marker. The OS recognizes these two characters at the start of a
  file as "use the following program to run this file."
- `/bin/bash` - The absolute path to the Bash interpreter.

You might see `#!/usr/bin/env bash`, which searches your `PATH` for Bash instead of
hardcoding the location. Either works.

One important detail: the shebang **must** be the very first line. No blank lines
before it, no spaces before the `#`. If it is not on line 1, position 1, it gets
ignored.

---

## Making Scripts Executable

By default, Linux treats new files as data, not programs. You need to grant execute
permission:

```bash
chmod +x provision-db.sh
```

The `+x` flag adds **execute** permission. After this, you can run the script:

```bash
./provision-db.sh
```

The `./` means "run the file in the current directory." Without it, the shell looks
for `provision-db.sh` in your `PATH` directories and will not find it.

You can also run a script explicitly through Bash without `chmod`:

```bash
bash provision-db.sh
```

But making scripts executable with `chmod +x` is the standard practice. Get in the
habit.

---

## Variables

Variables in Bash have no data types and no `DECLARE` statements. The syntax has a few
quirks that trip up beginners.

### Declaring and Using Variables

```bash
APP_NAME="promos"
echo "Provisioning database: $APP_NAME"
```

**Critical rule: no spaces around the `=` sign.** This works:

```bash
APP_NAME="promos"
```

This does NOT work:

```bash
APP_NAME = "promos"    # BROKEN - Bash thinks APP_NAME is a command
```

Bash is very literal about spaces. `APP_NAME = "promos"` tells Bash to run a command
called `APP_NAME` with two arguments: `=` and `"promos"`.

To use a variable's value, prefix it with `$`:

```bash
echo $APP_NAME
echo "$APP_NAME"
echo "${APP_NAME}"
```

All three work, but they are not all equal. Keep reading.

### Quoting Rules: Single vs Double Quotes

**Double quotes** - Variables get expanded:

```bash
APP_NAME="promos"
echo "Database: $APP_NAME"
# Output: Database: promos
```

**Single quotes** - Nothing gets expanded. Everything is literal:

```bash
APP_NAME="promos"
echo 'Database: $APP_NAME'
# Output: Database: $APP_NAME
```

**No quotes** - Variables expand, but word splitting and globbing happen:

```bash
GREETING="hello world"
echo $GREETING      # Works, but risky with spaces
echo "$GREETING"    # Safer - preserves the string as one unit
```

**Rule of thumb: always double-quote your variables.** Write `"$APP_NAME"`, not
`$APP_NAME`. This protects you from word splitting and unexpected behavior when a
variable contains spaces or special characters.

### Curly Braces for Clarity

Sometimes you need curly braces to separate the variable name from surrounding text:

```bash
APP_NAME="promos"
echo "${APP_NAME}_read_group"
# Output: promos_read_group
```

Without the braces:

```bash
echo "$APP_NAME_read_group"
# Output: (empty - Bash looks for a variable named APP_NAME_read_group)
```

Bash tries to expand the longest variable name it can find. The braces tell it exactly
where the variable name ends. When in doubt, use `${VAR}`.

---

## Positional Parameters

Positional parameters are how your script receives input from the command line. This is
what lets you write `./provision-db.sh promos` instead of hardcoding `promos`.

When you run:

```bash
./provision-db.sh promos data lw_promos_l20
```

Bash automatically assigns:

| Variable | Value              | Meaning                                |
|----------|--------------------|----------------------------------------|
| `$0`     | `./provision-db.sh`| The script's own name                  |
| `$1`     | `promos`           | First argument                         |
| `$2`     | `data`             | Second argument                        |
| `$3`     | `lw_promos_l20`    | Third argument                         |
| `$#`     | `3`                | Total number of arguments              |
| `$@`     | all three values   | All arguments as separate words        |

Inside your script, you would use them like this:

```bash
#!/bin/bash
APP_NAME="$1"
TABLESPACE="$2"
DEV_USER="$3"

echo "Creating database: $APP_NAME"
echo "Tablespace: $TABLESPACE"
echo "Developer: $DEV_USER"
```

Two tips:

- **Always assign positional parameters to named variables** at the top of your script.
  Reading `$APP_NAME` in line 50 is much clearer than reading `$1`.
- **Check that required arguments were provided:**

```bash
if [ -z "$1" ]; then
    echo "Usage: $0 <app_name>"
    exit 1
fi
```

`-z` tests whether the string is empty. If no argument was given, the script prints a
usage message and exits.

---

## Special Variables

### `$?` - Exit Code of the Last Command

Every command produces an exit code. `0` means success, anything else means failure:

```bash
psql -h localhost -U postgres -c "SELECT 1" > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "PostgreSQL is reachable"
else
    echo "Cannot connect to PostgreSQL"
fi
```

You will use this constantly. After running `psql` to create a database, you want to
know: did it actually work?

### `$$` - The Current Script's Process ID

Useful for creating temporary files that will not collide if two copies of the script
run at the same time:

```bash
TMPFILE="/tmp/provision-${$}.sql"
```

### `$!` - PID of the Last Background Process

Less common for DBA scripts, but if you kick off a `pg_dump` in the background, `$!`
holds its process ID so you can wait for it or check on it.

---

## Variable Expansion and Defaults

Bash has built-in syntax for providing default values and handling missing variables.

### `${VAR:-default}` - Use Default if Unset

```bash
TABLESPACE="${2:-pg_default}"
```

If `$2` was not provided, `TABLESPACE` gets `pg_default`. Otherwise it uses `$2`. This
lets you make arguments optional:

```bash
#!/bin/bash
APP_NAME="$1"
TABLESPACE="${2:-pg_default}"
OWNER="${3:-postgres}"

echo "App: $APP_NAME, Tablespace: $TABLESPACE, Owner: $OWNER"
```

Running `./provision-db.sh promos` gives you:

```
App: promos, Tablespace: pg_default, Owner: postgres
```

Running `./provision-db.sh promos data app_owner` gives you:

```
App: promos, Tablespace: data, Owner: app_owner
```

### `${VAR:?error message}` - Fail if Unset

```bash
APP_NAME="${1:?ERROR: app_name is required}"
```

If `$1` is empty, the script immediately exits and prints the error message. A compact
way to enforce required arguments without writing `if` blocks.

### `${VAR:=default}` - Set Default and Assign

Similar to `:-`, but this one actually assigns the default to the variable:

```bash
PG_HOST="${PG_HOST:=localhost}"
```

If `PG_HOST` is not already set in your environment, it gets set to `localhost`.

---

## Exit Codes

Exit codes are how scripts communicate success or failure. This matters because scripts
often call other scripts, and the caller needs to know whether the inner one succeeded.

| Exit Code | Meaning                        |
|-----------|--------------------------------|
| `0`       | Success                        |
| `1`       | General error                  |
| `2`       | Misuse of command (bad args)   |
| `3-125`   | Available for your own meanings|
| `126`     | Command found but not executable|
| `127`     | Command not found              |

You set the exit code with the `exit` command:

```bash
if [ -z "$APP_NAME" ]; then
    echo "ERROR: app_name is required" >&2
    exit 1
fi

# ... do the work ...

echo "Database $APP_NAME provisioned successfully"
exit 0
```

Note the `>&2` on the error message. That sends output to **stderr** instead of
stdout. Error messages should go to stderr so they do not get mixed into normal output.

If your script reaches the end without an explicit `exit`, the exit code is whatever
the last command returned. Relying on this is fragile. Be explicit.

---

## The Safety Net: `set -euo pipefail`

Put this near the top of every script, right after the shebang:

```bash
#!/bin/bash
set -euo pipefail
```

This enables three safety flags that catch bugs early.

### `set -e` - Exit on Error

Without `-e`, Bash keeps going when a command fails:

```bash
psql -c "CREATE DATABASE promos"    # Fails - database already exists
psql -d promos -c "DROP SCHEMA public CASCADE"   # Still runs! Oops.
```

With `set -e`, the script stops at the first failure.

### `set -u` - Error on Undefined Variables

Without `-u`, referencing an undefined variable silently gives you an empty string:

```bash
echo "Connecting to $PG_HSOT"    # Typo! PG_HSOT instead of PG_HOST
# Output: "Connecting to "       # No error, bug goes unnoticed.
```

With `set -u`, Bash immediately reports: `PG_HSOT: unbound variable`. This catches
typos in variable names instantly.

### `set -o pipefail` - Catch Failures in Pipes

Without `pipefail`, only the exit code of the **last** command in a pipe matters:

```bash
psql -c "SELECT * FROM nonexistent_table" | grep "something"
echo $?   # Returns grep's exit code, not psql's. The psql failure is hidden.
```

With `pipefail`, the pipe fails if **any** command in it fails.

### Putting It Together

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="${1:?Usage: $0 <app_name>}"
TABLESPACE="${2:-pg_default}"
OWNER="${3:-postgres}"

echo "Provisioning database: $APP_NAME"
```

This script requires the first argument, provides defaults for optional ones, stops on
any error, catches variable typos, and does not hide failures in pipes. A solid start.

---

## Quick Reference

| Concept                  | Syntax                          | Example                            |
|--------------------------|---------------------------------|------------------------------------|
| Variable assignment      | `VAR="value"`                   | `APP_NAME="promos"`                |
| Variable usage           | `"$VAR"` or `"${VAR}"`         | `echo "$APP_NAME"`                 |
| Positional parameter     | `$1`, `$2`, etc.                | `APP_NAME="$1"`                    |
| Argument count           | `$#`                            | `if [ $# -lt 1 ]; then ...`       |
| Default value            | `${VAR:-default}`               | `TBLSPC="${2:-pg_default}"`        |
| Required value           | `${VAR:?msg}`                   | `APP="${1:?need app_name}"`        |
| Last exit code           | `$?`                            | `if [ $? -ne 0 ]; then ...`       |
| Script name              | `$0`                            | `echo "Usage: $0 <app>"`          |
| Safety flags             | `set -euo pipefail`             | Always line 2 of your script       |
| Make executable          | `chmod +x script.sh`            | `chmod +x provision-db.sh`         |

---

## What is Next

You now have the vocabulary: variables, parameters, quoting, exit codes, and safety
flags. In the next chapter, we cover **functions**, **here documents**, and **psql
integration** - the three pieces that let you wrap SQL inside Bash and build a real
database provisioner.

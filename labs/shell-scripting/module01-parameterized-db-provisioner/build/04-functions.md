---
layout: default
title: "BUILD 04 - Functions"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 6
---

# BUILD 04 - Functions

## What You Will Learn

So far, your scripts have been linear - code runs from top to bottom. That works for small scripts, but your provisioning script will need to create roles, create a database, create a schema, and grant permissions. If all of that lives in one flat block, it becomes hard to read, hard to test, and hard to change.

Functions let you break a script into named, reusable pieces. In this guide, you will learn how to define functions, pass arguments to them, manage variable scope, and structure a script using the `main()` pattern.

---

## Step 1 - Define and Call a Simple Function

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-basic.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

say_hello() {
    echo "Hello from inside a function"
}

echo "Before the function call"
say_hello
echo "After the function call"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Function Syntax

- `say_hello()` - The function name followed by empty parentheses. The parentheses are required but always empty in bash (unlike SQL functions, you do not list parameters here).
- `{ ... }` - The function body. Everything between the curly braces runs when the function is called.
- `say_hello` - To call a function, just write its name. No parentheses, no `call` keyword.

Make it executable and run it.

On **pg-lab**, as **ec2-user**:

```bash
chmod +x ~/scripts/func-basic.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-basic.sh
```

Expected output (yours will differ):

```
Before the function call
Hello from inside a function
After the function call
```

The function ran exactly where you called it, then execution continued on the next line.

---

## Step 2 - Functions With Arguments

Functions receive arguments the same way scripts do - through positional parameters `$1`, `$2`, etc. But here is the critical thing to understand: **`$1` inside a function is different from `$1` at the script level.**

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-args.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

greet_user() {
    echo "Hello, $1. Your role is $2."
}

echo "Script's first argument: ${1:-none}"
greet_user "Beverly" "DBA"
greet_user "Alice" "Developer"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### The Scope of $1

When you run `./func-args.sh promos`, the script-level `$1` is `promos`. But inside `greet_user`, `$1` is whatever you passed to the function - `Beverly` in the first call, `Alice` in the second.

This means `$1` is context-dependent. Inside a function, it refers to the function's arguments, not the script's arguments. This is why you always assign script arguments to named variables at the top of your script - so they do not get shadowed inside functions.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-args.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-args.sh
```

Expected output (yours will differ):

```
Script's first argument: none
Hello, Beverly. Your role is DBA.
Hello, Alice. Your role is Developer.
```

Run it again with a script argument to see the difference.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-args.sh promos
```

Expected output (yours will differ):

```
Script's first argument: promos
Hello, Beverly. Your role is DBA.
Hello, Alice. Your role is Developer.
```

The script's `$1` was `promos`, but the function's `$1` was `Beverly` (first call) and `Alice` (second call). They do not interfere with each other.

---

## Step 3 - Local Variables

By default, variables in bash are **global**. If you set a variable inside a function, it changes everywhere - even outside the function. This can cause subtle bugs.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-global.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

MESSAGE="original"

change_message() {
    MESSAGE="changed by function"
}

echo "Before: $MESSAGE"
change_message
echo "After:  $MESSAGE"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-global.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-global.sh
```

Expected output (yours will differ):

```
Before: original
After:  changed by function
```

The function modified the global variable. This is the default behavior and it is dangerous. Now see how `local` fixes this.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-local.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

MESSAGE="original"

change_message() {
    local MESSAGE="changed by function"
    echo "Inside function: $MESSAGE"
}

echo "Before: $MESSAGE"
change_message
echo "After:  $MESSAGE"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### The local Keyword

`local MESSAGE="changed by function"` creates a variable that only exists inside the function. When the function finishes, the local variable disappears and the outer variable is untouched.

**Rule of thumb**: Always use `local` for variables inside functions unless you intentionally want to modify a global variable.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-local.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-local.sh
```

Expected output (yours will differ):

```
Before: original
Inside function: changed by function
After:  original
```

The outer `MESSAGE` was not affected. The function had its own copy.

---

## Step 4 - Return Values vs Echo for Output

Bash functions do not return values the way SQL functions or Python functions do. The `return` keyword sets an exit code (0-255), not a string. To get a string out of a function, you use `echo` and capture it with command substitution.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-return.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

build_role_name() {
    local app="$1"
    local suffix="$2"
    echo "${app}_${suffix}"
}

READ_ROLE=$(build_role_name "promos" "read_group")
WRITE_ROLE=$(build_role_name "promos" "write_group")

echo "Read role:  $READ_ROLE"
echo "Write role: $WRITE_ROLE"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### How This Works

- `build_role_name` uses `echo` to print its result.
- `$(build_role_name "promos" "read_group")` captures that output and assigns it to `READ_ROLE`. The `$(...)` syntax is called **command substitution** - it runs the command inside and replaces itself with the output.
- `return` is only useful for signaling success (0) or failure (non-zero), just like exit codes.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-return.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-return.sh
```

Expected output (yours will differ):

```
Read role:  promos_read_group
Write role: promos_write_group
```

You just built the same role names as your SQL provisioning script, but using a reusable function.

---

## Step 5 - Create a log() Function

Production scripts need to log what they are doing, with timestamps. You will create a `log()` function that prefixes every message with a timestamp.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-log.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

log "INFO" "Script started"
log "INFO" "Checking prerequisites"
log "WARN" "Tablespace 'data' not found, using default"
log "INFO" "Script finished"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### What Is New Here

- `date '+%Y-%m-%d %H:%M:%S'` prints the current date and time in a standard format.
- The `timestamp` variable is declared and assigned on separate lines. This is a best practice with `local` - if `$(date ...)` fails, `local` would mask the error because `local` itself always returns 0.
- The function takes two arguments: a severity level and the message.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-log.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-log.sh
```

Expected output (yours will differ):

```
[2026-06-23 10:30:15] [INFO] Script started
[2026-06-23 10:30:15] [INFO] Checking prerequisites
[2026-06-23 10:30:15] [WARN] Tablespace 'data' not found, using default
[2026-06-23 10:30:15] [INFO] Script finished
```

Every line has a timestamp and severity level. When your provisioning script runs against a real database, these logs will tell you exactly what happened and when.

---

## Step 6 - Create a validate_args() Function

Move your validation logic into its own function. This keeps the top of your script clean and makes the validation reusable.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/func-validate.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: $0 <app_name> [tablespace] [owner]"
    echo ""
    echo "Arguments:"
    echo "  app_name     Required. Name of the application"
    echo "  tablespace   Optional. Defaults to 'data'"
    echo "  owner        Optional. Defaults to 'postgres'"
    exit 1
}

validate_args() {
    if [ $# -lt 1 ]; then
        echo "ERROR: app_name is required" >&2
        echo "" >&2
        usage
    fi

    local app_name="$1"

    if [ -z "$app_name" ]; then
        echo "ERROR: app_name cannot be empty" >&2
        exit 1
    fi

    if [[ "$app_name" =~ [^a-z0-9_] ]]; then
        echo "ERROR: app_name can only contain lowercase letters, numbers, and underscores" >&2
        echo "       Got: '$app_name'" >&2
        exit 1
    fi
}

validate_args "$@"

APP_NAME="$1"
TABLESPACE="${2:-data}"
OWNER="${3:-postgres}"

echo "Validation passed"
echo "App: $APP_NAME | Tablespace: $TABLESPACE | Owner: $OWNER"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### New Concepts

- `"$@"` passes all script arguments to the function. Each argument stays separate (unlike `$*`, which merges them).
- `-z "$app_name"` tests if a string is empty (zero length).
- `[[ "$app_name" =~ [^a-z0-9_] ]]` is a regex test. `[^a-z0-9_]` matches any character that is NOT a lowercase letter, number, or underscore. If there is a match, the app name contains invalid characters.
- `[[ ... ]]` is the extended test command. It supports regex (`=~`), which the single-bracket `[ ... ]` does not.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/func-validate.sh
```

Test with no arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-validate.sh
```

Expected output (yours will differ):

```
ERROR: app_name is required

Usage: /home/ec2-user/scripts/func-validate.sh <app_name> [tablespace] [owner]

Arguments:
  app_name     Required. Name of the application
  tablespace   Optional. Defaults to 'data'
  owner        Optional. Defaults to 'postgres'
```

Test with an invalid app name.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-validate.sh "My App"
```

Expected output (yours will differ):

```
ERROR: app_name can only contain lowercase letters, numbers, and underscores
       Got: 'My App'
```

Test with a valid app name.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/func-validate.sh promos
```

Expected output (yours will differ):

```
Validation passed
App: promos | Tablespace: data | Owner: postgres
```

---

## Step 7 - The main() Function Pattern

Professional bash scripts use a pattern where all top-level logic goes inside a `main()` function. This is not a bash requirement - it is a convention that makes scripts cleaner and easier to reason about.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-structured.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

# --------------------------------------------------
# Logging
# --------------------------------------------------

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message"
}

# --------------------------------------------------
# Usage and validation
# --------------------------------------------------

usage() {
    echo "Usage: $0 <app_name> [tablespace] [owner]"
    echo ""
    echo "Provisions a PostgreSQL database with standard roles."
    echo ""
    echo "Arguments:"
    echo "  app_name     Required. Name of the application"
    echo "  tablespace   Optional. Defaults to 'data'"
    echo "  owner        Optional. Defaults to 'postgres'"
    echo ""
    echo "Example:"
    echo "  $0 promos data postgres"
    exit 1
}

validate_args() {
    if [ $# -lt 1 ]; then
        echo "ERROR: app_name is required" >&2
        echo "" >&2
        usage
    fi

    local app_name="$1"

    if [ -z "$app_name" ]; then
        echo "ERROR: app_name cannot be empty" >&2
        exit 1
    fi

    if [[ "$app_name" =~ [^a-z0-9_] ]]; then
        echo "ERROR: app_name must be lowercase letters, numbers, and underscores only" >&2
        echo "       Got: '$app_name'" >&2
        exit 1
    fi
}

# --------------------------------------------------
# Helper functions
# --------------------------------------------------

build_role_name() {
    local app="$1"
    local suffix="$2"
    echo "${app}_${suffix}"
}

# --------------------------------------------------
# Main
# --------------------------------------------------

main() {
    validate_args "$@"

    local app_name="$1"
    local tablespace="${2:-data}"
    local owner="${3:-postgres}"

    local read_role
    local write_role
    local app_role
    read_role=$(build_role_name "$app_name" "read_group")
    write_role=$(build_role_name "$app_name" "write_group")
    app_role=$(build_role_name "$app_name" "app_one")

    log "INFO" "Starting provisioning for '$app_name'"
    log "INFO" "Database: $app_name | Tablespace: $tablespace | Owner: $owner"
    log "INFO" "Creating role: $read_role"
    log "INFO" "Creating role: $write_role"
    log "INFO" "Creating role: $app_role"
    log "INFO" "TODO: Execute SQL statements here"
    log "INFO" "Provisioning complete"
}

main "$@"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Why the main() Pattern?

1. **Readability** - The script reads like a table of contents. Functions are defined at the top, and `main "$@"` at the very bottom tells you where execution begins.
2. **All variables are local** - Inside `main()`, you use `local` for every variable. Nothing leaks into global scope.
3. **`main "$@"`** at the bottom passes all script arguments into `main()`. This single line is the only top-level executable statement.
4. **Section comments** divide the script into logical groups. Anyone reading the script can jump to the section they need.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/provision-structured.sh
```

Run it with valid arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-structured.sh promos data postgres
```

Expected output (yours will differ):

```
[2026-06-23 10:45:00] [INFO] Starting provisioning for 'promos'
[2026-06-23 10:45:00] [INFO] Database: promos | Tablespace: data | Owner: postgres
[2026-06-23 10:45:00] [INFO] Creating role: promos_read_group
[2026-06-23 10:45:00] [INFO] Creating role: promos_write_group
[2026-06-23 10:45:00] [INFO] Creating role: promos_app_one
[2026-06-23 10:45:00] [INFO] TODO: Execute SQL statements here
[2026-06-23 10:45:00] [INFO] Provisioning complete
```

Run it with a different application name to see it work dynamically.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-structured.sh inventory
```

Expected output (yours will differ):

```
[2026-06-23 10:45:05] [INFO] Starting provisioning for 'inventory'
[2026-06-23 10:45:05] [INFO] Database: inventory | Tablespace: data | Owner: postgres
[2026-06-23 10:45:05] [INFO] Creating role: inventory_read_group
[2026-06-23 10:45:05] [INFO] Creating role: inventory_write_group
[2026-06-23 10:45:05] [INFO] Creating role: inventory_app_one
[2026-06-23 10:45:05] [INFO] TODO: Execute SQL statements here
[2026-06-23 10:45:05] [INFO] Provisioning complete
```

One script, any application name. The structure is ready for real SQL.

---

## Step 8 - Verify Your Work

List all the scripts you created in this guide.

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/func-*.sh ~/scripts/provision-structured.sh
```

Expected output (yours will differ):

```
-rwxr-xr-x. 1 ec2-user ec2-user  150 Jun 23 10:30 /home/ec2-user/scripts/func-args.sh
-rwxr-xr-x. 1 ec2-user ec2-user  120 Jun 23 10:28 /home/ec2-user/scripts/func-basic.sh
-rwxr-xr-x. 1 ec2-user ec2-user  180 Jun 23 10:32 /home/ec2-user/scripts/func-global.sh
-rwxr-xr-x. 1 ec2-user ec2-user  200 Jun 23 10:33 /home/ec2-user/scripts/func-local.sh
-rwxr-xr-x. 1 ec2-user ec2-user  280 Jun 23 10:35 /home/ec2-user/scripts/func-log.sh
-rwxr-xr-x. 1 ec2-user ec2-user  320 Jun 23 10:37 /home/ec2-user/scripts/func-return.sh
-rwxr-xr-x. 1 ec2-user ec2-user  550 Jun 23 10:40 /home/ec2-user/scripts/func-validate.sh
-rwxr-xr-x. 1 ec2-user ec2-user 1200 Jun 23 10:45 /home/ec2-user/scripts/provision-structured.sh
```

All files should have the `x` permission.

---

## What You Learned

- Functions are defined with `name() { ... }` and called by name (no parentheses)
- `$1` inside a function refers to the function's arguments, not the script's arguments
- `local` keeps variables scoped to the function and prevents global side effects
- `return` sets an exit code (0-255); use `echo` + `$(...)` to get string output from functions
- The `log()` function pattern adds timestamps and severity levels to output
- The `validate_args()` function centralizes input checking
- The `main() + main "$@"` pattern keeps scripts organized and all variables local

---

## Where You Stand

Over four guides, you have built up from `echo "Hello"` to a properly structured, validated, logged script skeleton. Here is what your provisioning script already does:

- Accepts the application name from the command line
- Falls back to sensible defaults for optional parameters
- Validates that the app name exists and contains only safe characters
- Builds role names dynamically from the app name
- Logs every step with timestamps
- Uses functions for clean organization
- Reports success or failure through exit codes

The only thing missing is the actual SQL execution. In the next guide, you will connect this skeleton to PostgreSQL and run real `CREATE ROLE` and `CREATE DATABASE` statements.

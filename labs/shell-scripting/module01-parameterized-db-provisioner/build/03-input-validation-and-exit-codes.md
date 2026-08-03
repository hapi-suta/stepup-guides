---
layout: default
title: "BUILD 03 - Input Validation and Exit Codes"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 5
---

# BUILD 03 - Input Validation and Exit Codes

## What You Will Learn

In the previous guide, you saw that bash silently accepts missing arguments. That is dangerous - a provisioning script with an empty database name could create broken roles or worse. In this guide, you will learn how to detect problems, report them clearly, and stop execution before any damage is done.

---

## Step 1 - What Are Exit Codes?

Every command you run in Linux produces an **exit code** - a number between 0 and 255. This number tells you whether the command succeeded or failed.

- **0** means success
- **Anything else** means failure

Run a command that succeeds.

On **pg-lab**, as **ec2-user**:

```bash
ls ~/scripts/hello.sh
```

Expected output (yours will differ):

```
/home/ec2-user/scripts/hello.sh
```

Now check the exit code.

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
0
```

`$?` is a special variable that holds the exit code of the most recent command. Zero means `ls` found the file successfully.

---

## Step 2 - See a Non-Zero Exit Code

Run a command that fails.

On **pg-lab**, as **ec2-user**:

```bash
ls ~/scripts/nonexistent-file.sh
```

Expected output (yours will differ):

```
ls: cannot access '/home/ec2-user/scripts/nonexistent-file.sh': No such file or directory
```

Check the exit code.

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
2
```

The exit code is 2 (not zero), which means the command failed. Different commands use different non-zero codes to indicate different kinds of failure, but the important thing is: **zero is success, non-zero is failure.**

---

## Step 3 - Your Scripts Have Exit Codes Too

Run one of your scripts and check its exit code.

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/hello.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
0
```

Your script exited with 0. But here is the problem - even when your script gets bad input (like a missing argument), it still exits with 0. That tells the caller "everything is fine" when it is not. You will fix this.

---

## Step 4 - The if/then/else/fi Structure

Bash uses `if/then/else/fi` for conditional logic. The syntax looks different from what you are used to in SQL, so read this carefully.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/check-arg.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

if [ $# -eq 0 ]; then
    echo "ERROR: No arguments provided"
    exit 1
else
    echo "You provided $# argument(s): $@"
    exit 0
fi
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Breaking Down the Syntax

- `if [ $# -eq 0 ]; then` - If the argument count equals zero, then do what follows.
- `[ ... ]` - This is a **test command**. The spaces after `[` and before `]` are required.
- `$#` - The number of arguments passed to the script.
- `-eq` - "equals" for numeric comparison. (For strings, you would use `=` instead.)
- `exit 1` - Stop the script immediately and report failure (exit code 1).
- `exit 0` - Stop the script and report success.
- `fi` - Closes the `if` block. It is `if` spelled backwards.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/check-arg.sh
```

Run it without arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/check-arg.sh
```

Expected output (yours will differ):

```
ERROR: No arguments provided
```

Check the exit code.

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
1
```

Now run it with an argument.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/check-arg.sh promos
```

Expected output (yours will differ):

```
You provided 1 argument(s): promos
```

Check the exit code.

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
0
```

The script now correctly reports success or failure through its exit code.

---

## Step 5 - Create a usage() Function

Production scripts print a helpful usage message when called incorrectly. You will create a function for this.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-check.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

usage() {
    echo "Usage: $0 <app_name> [tablespace] [owner]"
    echo ""
    echo "Arguments:"
    echo "  app_name     Required. Name of the application (e.g., promos)"
    echo "  tablespace   Optional. Defaults to 'data'"
    echo "  owner        Optional. Defaults to 'postgres'"
    echo ""
    echo "Example:"
    echo "  $0 promos data postgres"
    exit 1
}

if [ $# -lt 1 ]; then
    echo "ERROR: app_name is required"
    echo ""
    usage
fi

APP_NAME="$1"
TABLESPACE="${2:-data}"
OWNER="${3:-postgres}"

echo "Provisioning database: $APP_NAME"
echo "Tablespace: $TABLESPACE"
echo "Owner: $OWNER"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### What Is New Here?

- `usage()` is a **function**. You will learn more about functions in the next guide, but for now, think of it as a reusable block of code.
- `$0` inside the usage message prints the script name, so the example shows how to call this specific script.
- `-lt` means "less than" (numeric comparison). `$# -lt 1` checks if fewer than 1 argument was provided.
- The `usage` function calls `exit 1` at the end, so the script stops after printing the help text.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/provision-check.sh
```

Run it without arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-check.sh
```

Expected output (yours will differ):

```
ERROR: app_name is required

Usage: /home/ec2-user/scripts/provision-check.sh <app_name> [tablespace] [owner]

Arguments:
  app_name     Required. Name of the application (e.g., promos)
  tablespace   Optional. Defaults to 'data'
  owner        Optional. Defaults to 'postgres'

Example:
  /home/ec2-user/scripts/provision-check.sh promos data postgres
```

Now run it with the required argument.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-check.sh promos
```

Expected output (yours will differ):

```
Provisioning database: promos
Tablespace: data
Owner: postgres
```

The script either helps you fix the problem or does its job. No silent failures.

---

## Step 6 - The set Command - Your Safety Net

Bash has a built-in command called `set` that changes how the shell behaves. Three flags are essential for production scripts.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/set-demo.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

echo "Step 1: Starting"
echo "Step 2: About to use an unset variable"
echo "Name is: $UNDEFINED_VARIABLE"
echo "Step 3: This should not print"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### What Does Each Flag Do?

**`set -e`** - Exit immediately if any command fails (returns non-zero). Without this, bash keeps running even after errors.

**`set -u`** - Treat unset variables as errors. Without this, `$UNDEFINED_VARIABLE` would silently become an empty string. With it, bash stops and tells you the variable is not set.

**`set -o pipefail`** - If any command in a pipeline fails, the whole pipeline fails. Without this, only the exit code of the last command matters.

Together, `set -euo pipefail` is the standard safety net for production scripts. It catches the three most common categories of silent failures.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/set-demo.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/set-demo.sh
```

Expected output (yours will differ):

```
Step 1: Starting
Step 2: About to use an unset variable
/home/ec2-user/scripts/set-demo.sh: line 6: UNDEFINED_VARIABLE: unbound variable
```

The script stopped at line 6 because `$UNDEFINED_VARIABLE` was never defined. Step 3 never printed. Without `set -u`, it would have silently used an empty string and continued.

Check the exit code.

Still as **ec2-user** on **pg-lab**:

```bash
echo $?
```

Expected output (yours will differ):

```
1
```

Non-zero. The script correctly reported failure.

---

## Step 7 - See set -e in Action

Create another demo to show how `set -e` catches command failures.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/set-e-demo.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

echo "Step 1: Checking for a file that does not exist"
ls /tmp/this-file-does-not-exist-12345
echo "Step 2: This line should not execute"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable and run it.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/set-e-demo.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/set-e-demo.sh
```

Expected output (yours will differ):

```
Step 1: Checking for a file that does not exist
ls: cannot access '/tmp/this-file-does-not-exist-12345': No such file or directory
```

The `ls` command failed, so `set -e` stopped the script immediately. Step 2 never ran. Without `set -e`, bash would have printed the error from `ls` but continued to Step 2 as if nothing happened.

---

## Step 8 - How set -u Works With Default Values

You might be wondering - if `set -u` kills the script when a variable is unset, how do you use `${1:-default}`? Good news: the `:-` syntax is compatible with `set -u`. Bash sees the default and does not consider it an error.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/safe-defaults.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

APP_NAME="${1:-myapp}"
TABLESPACE="${2:-data}"

echo "App: $APP_NAME"
echo "Tablespace: $TABLESPACE"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable and run it without arguments.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/safe-defaults.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/safe-defaults.sh
```

Expected output (yours will differ):

```
App: myapp
Tablespace: data
```

No error. The `:-` syntax tells bash "I know this might be empty - use this default instead." That satisfies `set -u`.

---

## Step 9 - Build a Validated Script Skeleton

You now have all the pieces. Combine everything into a proper script skeleton that you will reuse throughout this module.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-skeleton.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash
set -euo pipefail

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

# --- Validate arguments ---
if [ $# -lt 1 ]; then
    echo "ERROR: app_name is required" >&2
    echo "" >&2
    usage
fi

APP_NAME="$1"
TABLESPACE="${2:-data}"
OWNER="${3:-postgres}"

# --- Derived values ---
READ_ROLE="${APP_NAME}_read_group"
WRITE_ROLE="${APP_NAME}_write_group"
APP_ROLE="${APP_NAME}_app_one"

# --- Report what will happen ---
echo "=== Database Provisioning ==="
echo ""
echo "Database:    $APP_NAME"
echo "Tablespace:  $TABLESPACE"
echo "Owner:       $OWNER"
echo ""
echo "Roles:"
echo "  $READ_ROLE"
echo "  $WRITE_ROLE"
echo "  $APP_ROLE"
echo ""
echo "TODO: SQL execution goes here"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Two New Details

- `>&2` after `echo` sends the output to **stderr** (standard error) instead of stdout. Error messages belong on stderr so they do not get mixed into normal output. This matters when other scripts consume your output.
- The comments (`# ---`) divide the script into logical sections: validation, derived values, and execution. This structure will grow as you add real SQL calls.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/provision-skeleton.sh
```

Test with no arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-skeleton.sh
```

Expected output (yours will differ):

```
ERROR: app_name is required

Usage: /home/ec2-user/scripts/provision-skeleton.sh <app_name> [tablespace] [owner]

Provisions a PostgreSQL database with standard roles.

Arguments:
  app_name     Required. Name of the application
  tablespace   Optional. Defaults to 'data'
  owner        Optional. Defaults to 'postgres'

Example:
  /home/ec2-user/scripts/provision-skeleton.sh promos data postgres
```

Test with valid arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-skeleton.sh promos
```

Expected output (yours will differ):

```
=== Database Provisioning ===

Database:    promos
Tablespace:  data
Owner:       postgres

Roles:
  promos_read_group
  promos_write_group
  promos_app_one

TODO: SQL execution goes here
```

---

## Step 10 - Verify Your Work

List all scripts and confirm they are executable.

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/
```

You should see all scripts with the `x` permission set. The key new files from this guide are `check-arg.sh`, `provision-check.sh`, `set-demo.sh`, `set-e-demo.sh`, `safe-defaults.sh`, and `provision-skeleton.sh`.

---

## What You Learned

- `$?` holds the exit code of the last command (0 = success, non-zero = failure)
- `exit 0` and `exit 1` let your script report success or failure to its caller
- `if [ condition ]; then ... else ... fi` is the basic conditional structure
- `-eq` (equals), `-lt` (less than) are numeric comparisons inside `[ ]`
- A `usage()` function gives callers clear instructions when they make mistakes
- `set -euo pipefail` is the standard safety net:
  - `-e` stops on any command failure
  - `-u` stops on any unset variable
  - `-o pipefail` catches failures inside pipelines
- `>&2` sends error messages to stderr where they belong
- The `:-` default syntax works safely with `set -u`

---

## Next Guide

Your scripts are getting structured, but the logic is still sitting loose at the top level. In the next guide, you will learn how to organize code into functions - reusable blocks that make your scripts readable, testable, and maintainable.

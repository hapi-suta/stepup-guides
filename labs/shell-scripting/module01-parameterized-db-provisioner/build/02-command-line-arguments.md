---
layout: default
title: "BUILD 02 - Command-Line Arguments"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 4
---

# BUILD 02 - Command-Line Arguments

## What You Will Learn

In this guide, you will learn how to pass values into a script from the command line. Instead of hardcoding variable values inside the script, the person running it can supply them at runtime. This is how you will eventually make your database provisioning script work for any application - not just "promos."

---

## Step 1 - Create a Script That Takes One Argument

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/greet.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

echo "Hello, $1"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/greet.sh
```

### What Is $1?

When you run a script with arguments, bash automatically assigns them to numbered variables called **positional parameters**:

- `$1` is the first argument
- `$2` is the second argument
- `$3` is the third argument, and so on

These are set by the caller, not inside the script.

---

## Step 2 - Run It With Different Arguments

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/greet.sh Beverly
```

Expected output (yours will differ):

```
Hello, Beverly
```

Run it again with a different name.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/greet.sh PostgreSQL
```

Expected output (yours will differ):

```
Hello, PostgreSQL
```

The script did not change. Only the argument changed. This is the power of parameterization - one script, many uses.

---

## Step 3 - Explore All the Special Variables

Bash provides several built-in variables related to arguments. You will create a script that displays all of them so you can see how they work.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/show-args.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

echo "Script name:      $0"
echo "First argument:   $1"
echo "Second argument:  $2"
echo "Third argument:   $3"
echo "Argument count:   $#"
echo "All arguments:    $@"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/show-args.sh
```

Run it with three arguments.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/show-args.sh alpha beta gamma
```

Expected output (yours will differ):

```
Script name:      /home/ec2-user/scripts/show-args.sh
First argument:   alpha
Second argument:  beta
Third argument:   gamma
Argument count:   3
All arguments:    alpha beta gamma
```

Here is what each special variable means:

| Variable | Meaning |
|----------|---------|
| `$0` | The name of the script itself (how it was called) |
| `$1` | First argument passed to the script |
| `$2` | Second argument passed to the script |
| `$#` | The total number of arguments (does not count `$0`) |
| `$@` | All arguments as a list |

---

## Step 4 - Create a Two-Argument Script

Think about your provisioning SQL. It creates roles like `promos_read_group` and `promos_write_group`. The pattern is `{app_name}_{role_suffix}`. You will create a script that takes a first name and last name and prints the full name.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/fullname.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

FIRST_NAME="$1"
LAST_NAME="$2"

echo "First name:  $FIRST_NAME"
echo "Last name:   $LAST_NAME"
echo "Full name:   $FIRST_NAME $LAST_NAME"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Why Assign $1 to a Named Variable?

You could use `$1` directly everywhere, but `$FIRST_NAME` is much easier to read. When your script grows to 50 or 100 lines, nobody will remember what `$1` was supposed to be. Named variables serve as documentation.

Make it executable and run it.

On **pg-lab**, as **ec2-user**:

```bash
chmod +x ~/scripts/fullname.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/fullname.sh Beverly Smith
```

Expected output (yours will differ):

```
First name:  Beverly
Last name:   Smith
Full name:   Beverly Smith
```

---

## Step 5 - What Happens When Arguments Are Missing

This is where things get interesting. Run your fullname script without any arguments.

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/fullname.sh
```

Expected output (yours will differ):

```
First name:
Last name:
Full name:
```

No error. No warning. Bash just silently used empty strings. This is one of the most common sources of bugs in shell scripts. Imagine running your database provisioning script and forgetting to pass the application name - it would try to create a role called `_read_group` with no prefix.

Run it again with only one argument.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/fullname.sh Beverly
```

Expected output (yours will differ):

```
First name:  Beverly
Last name:
Full name:   Beverly
```

The last name is just blank. Bash does not care that you expected two arguments. It happily runs with whatever it gets.

---

## Step 6 - Default Values with ${VAR:-default}

Bash has a built-in syntax for providing a fallback value when a variable is empty or unset. The pattern is `${VARIABLE:-default_value}`.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/greet-default.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

NAME="${1:-World}"

echo "Hello, $NAME"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### How Does ${1:-World} Work?

- If `$1` has a value, use that value.
- If `$1` is empty or was not provided, use `World` instead.

The `:-` is the key syntax. Think of it as "use this default if the variable is missing."

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/greet-default.sh
```

Run it without an argument.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/greet-default.sh
```

Expected output (yours will differ):

```
Hello, World
```

Now run it with an argument.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/greet-default.sh Beverly
```

Expected output (yours will differ):

```
Hello, Beverly
```

When you provide a value, the default is ignored. When you do not, the default kicks in.

---

## Step 7 - A Script With Multiple Defaults

You will now create a script that previews what a database provisioning call might look like, with sensible defaults for each parameter.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/provision-preview.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

APP_NAME="${1:-myapp}"
TABLESPACE="${2:-data}"
OWNER="${3:-postgres}"

READ_ROLE="${APP_NAME}_read_group"
WRITE_ROLE="${APP_NAME}_write_group"
APP_ROLE="${APP_NAME}_app_one"

echo "=== Provisioning Preview ==="
echo ""
echo "Database:    $APP_NAME"
echo "Tablespace:  $TABLESPACE"
echo "Owner:       $OWNER"
echo ""
echo "Roles to create:"
echo "  - $READ_ROLE   (read-only)"
echo "  - $WRITE_ROLE  (read-write)"
echo "  - $APP_ROLE    (application login)"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/provision-preview.sh
```

Run it with no arguments to see the defaults.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-preview.sh
```

Expected output (yours will differ):

```
=== Provisioning Preview ===

Database:    myapp
Tablespace:  data
Owner:       postgres

Roles to create:
  - myapp_read_group   (read-only)
  - myapp_write_group  (read-write)
  - myapp_app_one    (application login)
```

Now run it with the actual values from your SQL provisioning script.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/provision-preview.sh promos data postgres
```

Expected output (yours will differ):

```
=== Provisioning Preview ===

Database:    promos
Tablespace:  data
Owner:       postgres

Roles to create:
  - promos_read_group   (read-only)
  - promos_write_group  (read-write)
  - promos_app_one    (application login)
```

Those role names match your SQL script exactly. You just generated them dynamically from a single command-line argument.

---

## Step 8 - Override Only Some Defaults

What if you want to change the tablespace but keep the default owner? You still need to provide the arguments in order.

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/provision-preview.sh promos pg_default
```

Expected output (yours will differ):

```
=== Provisioning Preview ===

Database:    promos
Tablespace:  pg_default
Owner:       postgres

Roles to create:
  - promos_read_group   (read-only)
  - promos_write_group  (read-write)
  - promos_app_one    (application login)
```

The tablespace changed to `pg_default`, and the owner fell back to the default `postgres` because you did not provide a third argument.

This is a limitation of positional arguments - you must provide them in order. Later in this module, you will learn about named flags (like `--owner postgres`) that let you skip around. For now, positional arguments are enough.

---

## Step 9 - Verify Your Work

List all scripts you have created so far.

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/
```

Expected output (yours will differ):

```
total 24
-rwxr-xr-x. 1 ec2-user ec2-user 320 Jun 23 10:15 db-info.sh
-rwxr-xr-x. 1 ec2-user ec2-user 150 Jun 23 10:10 fullname.sh
-rwxr-xr-x. 1 ec2-user ec2-user  55 Jun 23 10:12 greet-default.sh
-rwxr-xr-x. 1 ec2-user ec2-user  40 Jun 23 10:08 greet.sh
-rwxr-xr-x. 1 ec2-user ec2-user  75 Jun 23 10:05 hello.sh
-rwxr-xr-x. 1 ec2-user ec2-user 420 Jun 23 10:16 provision-preview.sh
...
```

You should see six scripts, all executable.

---

## What You Learned

- `$1`, `$2`, `$3` are positional parameters - values passed from the command line
- `$0` is the script name, `$#` is the argument count, `$@` is all arguments
- Always assign positional parameters to named variables for readability
- Missing arguments silently become empty strings - bash will not warn you
- `${VAR:-default}` provides a fallback value when a variable is empty or unset
- You can build dynamic role names from a single app name argument - the same pattern your SQL provisioning script uses

---

## Next Guide

Your scripts currently accept missing arguments without complaint. In the next guide, you will learn how to validate inputs, provide clear error messages, and exit cleanly when something is wrong. This is what separates a quick hack from a production-ready script.

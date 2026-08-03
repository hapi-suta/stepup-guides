---
layout: default
title: "BUILD 01 - Your First Shell Script"
parent: "Module 01 - Parameterized DB Provisioner"
nav_order: 3
---

# BUILD 01 - Your First Shell Script

## What You Will Learn

In this guide, you will write your first shell script from scratch. You will learn what a shebang line is, how to create and run a script, and how variables work in bash. By the end, you will have a working script that uses variables and string interpolation.

---

## Step 1 - Create a Scripts Directory

Every project needs a clean place to store scripts. You will create a dedicated directory for all the scripts you build during this module.

On **pg-lab**, as **ec2-user**:

```bash
mkdir -p ~/scripts
```

The `-p` flag tells `mkdir` to create parent directories if needed, and to not complain if the directory already exists.

Now move into that directory.

On **pg-lab**, as **ec2-user**:

```bash
cd ~/scripts
```

Confirm you are in the right place.

Still as **ec2-user** on **pg-lab**:

```bash
pwd
```

Expected output (yours will differ):

```
/home/ec2-user/scripts
```

---

## Step 2 - Create Your First Script

You will create a file called `hello.sh`. The `.sh` extension is a convention that tells other people (and you, six months from now) that this file is a shell script.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/hello.sh
```

Press `i` to enter insert mode, then type the following exactly:

```bash
#!/bin/bash

echo "Hello, I am a shell script"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### What Is the Shebang Line?

The first line - `#!/bin/bash` - is called the **shebang** (or hashbang). It tells Linux which program should interpret this file. Without it, the system would not know whether this is a bash script, a Python script, or something else entirely.

- `#!` is the shebang marker. The kernel reads these two bytes to decide how to run the file.
- `/bin/bash` is the absolute path to the bash interpreter.

### What Does echo Do?

`echo` prints text to the terminal. The quotes around the message are not required for simple text, but using double quotes is a good habit - it prevents surprises when your text contains special characters later.

---

## Step 3 - Try to Run It

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/hello.sh
```

Expected output (yours will differ):

```
-bash: /home/ec2-user/scripts/hello.sh: Permission denied
```

This fails because Linux does not let you run a file unless it has **execute permission**. By default, new files only have read and write permissions.

---

## Step 4 - Check the Current Permissions

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/hello.sh
```

Expected output (yours will differ):

```
-rw-r--r--. 1 ec2-user ec2-user 50 Jun 23 10:00 /home/ec2-user/scripts/hello.sh
```

The first column shows permissions. `-rw-r--r--` means the owner can read and write, but nobody can execute. There is no `x` anywhere in that string.

---

## Step 5 - Make It Executable

On **pg-lab**, as **ec2-user**:

```bash
chmod +x ~/scripts/hello.sh
```

`chmod` changes file permissions. The `+x` flag adds execute permission for all users (owner, group, and others).

Verify the permission changed.

Still as **ec2-user** on **pg-lab**:

```bash
ls -l ~/scripts/hello.sh
```

Expected output (yours will differ):

```
-rwxr-xr-x. 1 ec2-user ec2-user 50 Jun 23 10:00 /home/ec2-user/scripts/hello.sh
```

Notice the `x` now appears three times - once for owner, once for group, once for others.

---

## Step 6 - Run It

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/hello.sh
```

Expected output (yours will differ):

```
Hello, I am a shell script
```

Your first shell script works.

---

## Step 7 - Add a Variable

Variables let you store values and reuse them. You will modify your script to use a variable instead of hardcoding your name.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/hello.sh
```

Press `i` to enter insert mode. Replace the entire contents with:

```bash
#!/bin/bash

NAME="Beverly"
echo "Hello, $NAME. I am a shell script."
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Variable Rules

There are three rules you must follow when assigning variables in bash:

1. **No spaces around the equals sign.** `NAME="Beverly"` is correct. `NAME = "Beverly"` will fail - bash will try to run `NAME` as a command.
2. **Use double quotes around values.** This protects you when values contain spaces or special characters.
3. **Use `$` to reference a variable.** `$NAME` tells bash to substitute the value stored in `NAME`.

Run the updated script.

On **pg-lab**, as **ec2-user**:

```bash
~/scripts/hello.sh
```

Expected output (yours will differ):

```
Hello, Beverly. I am a shell script.
```

---

## Step 8 - Single Quotes vs Double Quotes

This is one of the most important distinctions in shell scripting. Double quotes and single quotes behave differently.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/quotes.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

NAME="Beverly"

echo "Double quotes: Hello, $NAME"
echo 'Single quotes: Hello, $NAME'
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

Make it executable.

Still as **ec2-user** on **pg-lab**:

```bash
chmod +x ~/scripts/quotes.sh
```

Run it.

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/quotes.sh
```

Expected output (yours will differ):

```
Double quotes: Hello, Beverly
Single quotes: Hello, $NAME
```

The difference:

- **Double quotes** expand variables. `$NAME` is replaced with `Beverly`.
- **Single quotes** treat everything literally. `$NAME` stays as the text `$NAME`.

As a DBA, you will use this constantly. When you build SQL strings in a script, you will want some parts to expand (like a database name variable) and other parts to stay literal (like SQL keywords). Knowing which quotes to use is critical.

---

## Step 9 - Combine Multiple Variables

Real scripts use multiple variables together. You will create a script that builds a database name from parts, similar to how your provisioning SQL constructs role names.

On **pg-lab**, as **ec2-user**:

```bash
vi ~/scripts/db-info.sh
```

Press `i` to enter insert mode, then type:

```bash
#!/bin/bash

APP_NAME="promos"
ENV="production"
ROLE_SUFFIX="read_group"

DB_NAME="${APP_NAME}"
ROLE_NAME="${APP_NAME}_${ROLE_SUFFIX}"

echo "Application: $APP_NAME"
echo "Environment: $ENV"
echo "Database:    $DB_NAME"
echo "Read role:   $ROLE_NAME"
```

Press `Esc`, then type `:wq` and press `Enter` to save and quit.

### Why the Curly Braces?

Notice `${APP_NAME}_${ROLE_SUFFIX}` uses curly braces. Without them, bash would look for a variable called `$APP_NAME_` (including the underscore) or `$ROLE_SUFFIX` might merge with surrounding text. Curly braces tell bash exactly where the variable name starts and ends.

Compare:

- `$APP_NAME_$ROLE_SUFFIX` - bash looks for a variable named `APP_NAME_`, which does not exist.
- `${APP_NAME}_${ROLE_SUFFIX}` - bash correctly finds `APP_NAME` and `ROLE_SUFFIX`, joining them with an underscore.

Make it executable and run it.

On **pg-lab**, as **ec2-user**:

```bash
chmod +x ~/scripts/db-info.sh
```

Still as **ec2-user** on **pg-lab**:

```bash
~/scripts/db-info.sh
```

Expected output (yours will differ):

```
Application: promos
Environment: production
Database:    promos
Read role:   promos_read_group
```

Look at that last line. `promos_read_group` - that is the exact role name from your SQL provisioning script. You just built it dynamically from two variables instead of hardcoding it.

---

## Step 10 - Verify Your Work

List all the scripts you created in this guide.

On **pg-lab**, as **ec2-user**:

```bash
ls -l ~/scripts/
```

Expected output (yours will differ):

```
total 12
-rwxr-xr-x. 1 ec2-user ec2-user 120 Jun 23 10:05 db-info.sh
-rwxr-xr-x. 1 ec2-user ec2-user  75 Jun 23 10:02 hello.sh
-rwxr-xr-x. 1 ec2-user ec2-user  95 Jun 23 10:03 quotes.sh
```

You should see three files, all with the `x` (execute) permission.

---

## What You Learned

- The shebang (`#!/bin/bash`) tells Linux which interpreter to use
- `chmod +x` makes a script executable
- Variables are assigned with `=` (no spaces) and referenced with `$`
- Double quotes expand variables; single quotes do not
- Curly braces (`${VAR}`) clarify variable boundaries when combining with other text
- You can build dynamic strings (like role names) by combining variables - this is the foundation of parameterizing your SQL provisioning script

---

## Next Guide

In the next guide, you will learn how to pass values into your script from the command line instead of hardcoding them. This is the first step toward turning your SQL provisioning script into something reusable.

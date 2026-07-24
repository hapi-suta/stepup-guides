# Scenario 01 - Missing PATH (grep hidden)

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: grep: command not found when searching logs
Cannot search database logs or configuration files.
The grep command is missing from the system.
```

---

## Key Concepts for Revision

- **PATH** - An environment variable that lists directories where Linux looks for commands. When you type `grep`, Linux checks each directory in PATH (left to right) until it finds an executable named `grep`. If none is found, you get "command not found".

- **which** - A command that shows the full path to an executable. `which ls` returns `/usr/bin/ls`. If `which grep` returns nothing, the command is either not installed or not in a PATH directory.

- **find** - Can search the entire filesystem for a file by name. Unlike `which`, it does not rely on PATH. `find / -name "grep*"` searches everywhere.

- **/usr/bin** - The standard directory for user commands on CentOS. Most commands you use daily (`ls`, `cat`, `grep`, `head`, etc.) live here.

---

## Diagnostic Steps

### Step 1 - Confirm grep is missing

Try to use grep:

```bash
grep --version
```

Expected: `bash: grep: command not found`

### Step 2 - Check your PATH

```bash
echo $PATH
```

This shows the directories Linux searches for commands. Verify that `/usr/bin` is in the list.

### Step 3 - Check if grep exists in its normal location

```bash
ls -la /usr/bin/grep
```

Expected: The file is missing. This confirms grep was moved or deleted, not that PATH is wrong.

### Step 4 - Search for grep anywhere on the system

```bash
sudo find / -name "grep*" -type f 2>/dev/null
```

This searches the entire filesystem for any file starting with "grep". You should find it somewhere unexpected.

```
Expected output (yours will differ):
/usr/bin/grep.hidden
```

### Step 5 - Restore grep to its correct location

```bash
sudo mv /usr/bin/grep.hidden /usr/bin/grep
```

This moves the file back to its original name and location.

### Step 6 - Verify the fix

```bash
grep --version
```

Expected: Version information prints successfully.

```
Expected output (yours will differ):
grep (GNU grep) 3.7
...
```

```bash
which grep
```

Expected: `/usr/bin/grep`

---

## Root Cause

The `grep` binary was renamed from `/usr/bin/grep` to `/usr/bin/grep.hidden`. Since Linux looks for commands by exact filename in PATH directories, renaming the file made it invisible to the shell.

---

## Prevention

- Never rename system binaries. If you need to replace a command, use alternatives (`update-alternatives`) or symlinks.
- Monitor critical binaries with a configuration management tool.
- Use `rpm -V coreutils` or `rpm -V grep` to verify that system packages have not been tampered with.

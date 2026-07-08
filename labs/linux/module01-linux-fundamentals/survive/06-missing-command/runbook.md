# Scenario 06 - Missing Command (less removed)

**Severity:** P3 - Medium
**Expected Recovery Time:** 5 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: less: command not found when reading logs
Cannot use 'less' to page through log files.
The command appears to be missing from the system.
```

---

## Key Concepts for Revision

- **dnf** - The package manager on CentOS Stream 9 (and RHEL 9, Fedora). It installs, removes, and updates software packages.

- **rpm** - The low-level package tool. `rpm -q less` checks if a specific package is installed. `rpm -qf /usr/bin/less` shows which package owns a specific file.

- **which** - Shows the path to a command. If a command is not found, `which` returns an error. This tells you the command is either not installed or not in your PATH.

- **dnf provides** - `dnf provides "*/less"` tells you which package contains the `less` command. Useful when you do not know the package name.

---

## Diagnostic Steps

### Step 1 - Confirm less is missing

```bash
less --version
```

Expected: `bash: less: command not found`

### Step 2 - Check if the package is installed

```bash
rpm -q less
```

Expected: `package less is not installed`

This confirms the package was removed, not just the binary.

### Step 3 - Find out which package provides less

If you did not know the package name, you could search for it:

```bash
dnf provides "*/less"
```

```
Expected output (yours will differ):
less-590-3.el9.x86_64 : A text file browser similar to more, but better
Repo        : baseos
Matched from:
Filename    : /usr/bin/less
```

This tells you the package is called `less`.

### Step 4 - Reinstall the less package

```bash
sudo dnf install -y less
```

The `-y` flag automatically answers "yes" to confirmation prompts.

```
Expected output (yours will differ):
...
Installed:
  less-590-3.el9.x86_64
Complete!
```

### Step 5 - Verify the fix

```bash
less --version
```

```
Expected output (yours will differ):
less 590 (POSIX regular expressions)
...
```

```bash
which less
```

Expected: `/usr/bin/less`

Test it on a real file:

```bash
less /etc/passwd
```

Press `q` to exit. The pager should work normally.

---

## Root Cause

The `less` package was removed from the system (via `dnf remove`). This can happen when removing another package that lists `less` as a dependency, or from accidental package removal.

---

## Prevention

- Use `dnf history` to review recent package changes if commands suddenly disappear.
- Be cautious with `dnf remove` - always review the dependency list before confirming.
- On production servers, use `dnf versionlock` to prevent critical packages from being removed.
- Keep a list of required packages and verify them periodically.

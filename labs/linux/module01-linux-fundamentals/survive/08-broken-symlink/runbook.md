# Scenario 08 - Broken Symlink

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Configuration file missing
The application configuration at /opt/app/config/app.conf
cannot be read. The application will not start without it.
```

---

## Key Concepts for Revision

- **Symbolic link (symlink)** - A special file that points to another file or directory, like a shortcut. Created with `ln -s target linkname`. When you read the symlink, Linux transparently reads the target file.

- **Broken symlink** - A symlink whose target no longer exists. The symlink file still exists, but it points to nothing. Trying to read it gives "No such file or directory" even though `ls` shows the file.

- **ls -la** - Shows symlinks with an arrow (`->`). Example: `app.conf -> /opt/app/shared/app.conf`. If the target does not exist, many terminals show the symlink in red.

- **readlink** - Shows what a symlink points to. `readlink -f /path/to/symlink` shows the absolute path of the target.

- **file** - The `file` command identifies what type of file something is. For symlinks, it says "symbolic link" and shows the target.

---

## Diagnostic Steps

### Step 1 - Try to read the configuration file

```bash
cat /opt/app/config/app.conf
```

Expected: `cat: /opt/app/config/app.conf: No such file or directory`

This is confusing because the file seems to exist in `ls` output but cannot be read.

### Step 2 - Check what type of file it is

```bash
ls -la /opt/app/config/
```

```
Expected output (yours will differ):
total 0
drwxr-xr-x. 2 root root 22 Apr 19 16:00 .
drwxr-xr-x. 4 root root 34 Apr 19 16:00 ..
lrwxrwxrwx. 1 root root 27 Apr 19 16:00 app.conf -> /opt/app/shared/app.conf
```

Notice:
- The first character is `l` (lowercase L) - this means it is a symlink
- The arrow `->` shows it points to `/opt/app/shared/app.conf`

### Step 3 - Check if the target exists

```bash
ls -la /opt/app/shared/app.conf
```

Expected: `ls: cannot access '/opt/app/shared/app.conf': No such file or directory`

The target file is gone. The symlink points to a file that no longer exists.

### Step 4 - Verify with readlink

```bash
readlink -f /opt/app/config/app.conf
```

This shows the full target path. The file at that path does not exist.

### Step 5 - Check if the target directory exists

```bash
ls -la /opt/app/shared/
```

The directory exists but the config file is missing from it.

### Step 6 - Recreate the target config file

Since the original file was deleted, you need to recreate it. Use vi to create the config file:

```bash
sudo vi /opt/app/shared/app.conf
```

Press `i` to enter insert mode, then type the configuration:

```
# Application Configuration
listen_address = 0.0.0.0
listen_port = 5432
max_connections = 100
log_level = info
data_directory = /opt/app/data
```

Press `Esc`, then type `:wq` and press Enter to save and quit.

### Step 7 - Verify the fix

Check that the symlink now works:

```bash
cat /opt/app/config/app.conf
```

```
Expected output (yours will differ):
# Application Configuration
listen_address = 0.0.0.0
listen_port = 5432
max_connections = 100
log_level = info
data_directory = /opt/app/data
```

Verify the symlink still points to the correct target:

```bash
ls -la /opt/app/config/app.conf
```

```
Expected output (yours will differ):
lrwxrwxrwx. 1 root root 27 Apr 19 16:00 /opt/app/config/app.conf -> /opt/app/shared/app.conf
```

---

## Root Cause

The target file (`/opt/app/shared/app.conf`) that the symlink pointed to was deleted. The symlink itself was not touched, but since its target no longer existed, any attempt to read through the symlink failed with "No such file or directory".

---

## Prevention

- When removing files, check for symlinks pointing to them first: `find / -lname "/path/to/file" 2>/dev/null`
- Back up configuration files before making changes.
- Use configuration management tools to ensure all config files and their symlinks are correct.
- Keep config files in version control (git) so they can be recreated from history.
- Document the symlink relationships in your server documentation.

# Scenario 04 - Broken Home Directory

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: Cannot SSH into server - getting errors
SSH login succeeds but user profile is broken.
The .bash_profile, .bashrc and other config files are
missing from the home directory.
```

---

## Key Concepts for Revision

- **Home directory** - The personal directory for a user, defined in `/etc/passwd`. For `ec2-user`, it is `/home/ec2-user`. This is where shell configuration files (`.bashrc`, `.bash_profile`), SSH keys, and personal files live.

- **/etc/passwd** - Contains one line per user. The 6th field is the home directory path. The system uses this to set the `HOME` environment variable and to determine where to look for shell configuration files.

- **.bash_profile and .bashrc** - Shell configuration files that run when you log in. They set up your PATH, aliases, and environment. If these are missing, your shell still works but may behave differently.

- **authorized_keys** - The file `~/.ssh/authorized_keys` contains the public keys allowed to log in. If this file or the `.ssh` directory is missing, SSH key authentication fails.

---

## Diagnostic Steps

### Step 1 - Check what is in the home directory

```bash
ls -la ~/
```

Expected: Almost empty - only `.ssh` directory with `authorized_keys`. The normal files (`.bashrc`, `.bash_profile`, `.bash_history`, etc.) are missing.

### Step 2 - Check what /etc/passwd says the home directory should be

```bash
grep "ec2-user" /etc/passwd
```

```
Expected output (yours will differ):
ec2-user:x:1000:1000:Cloud User:/home/ec2-user:/bin/bash
```

The 6th field shows `/home/ec2-user` - that is the expected home directory.

### Step 3 - Look for a renamed or misplaced home directory

```bash
ls -la /home/
```

```
Expected output (yours will differ):
drwx------. 3 ec2-user ec2-user  111 Apr 19 10:00 ec2-user.broken
drwx------. 3 ec2-user ec2-user   29 Apr 19 16:00 ec2-user
```

The original home directory was renamed to `ec2-user.broken`. The current `ec2-user` directory is a minimal replacement with only SSH keys.

### Step 4 - Restore the original home directory

First, save the current SSH authorized_keys (to be safe):

```bash
cp ~/.ssh/authorized_keys /tmp/authorized_keys.bak
```

Remove the minimal home directory:

```bash
sudo rm -r /home/ec2-user
```

Move the original back:

```bash
sudo mv /home/ec2-user.broken /home/ec2-user
```

### Step 5 - Verify the fix

```bash
ls -la ~/
```

You should see all the original files:

```
Expected output (yours will differ):
drwx------. 3 ec2-user ec2-user  111 Apr 19 10:00 .
drwxr-xr-x. 3 root     root       22 Apr 19 10:00 ..
-rw-------. 1 ec2-user ec2-user  145 Apr 19 14:00 .bash_history
-rw-r--r--. 1 ec2-user ec2-user   18 Mar 15 10:00 .bash_logout
-rw-r--r--. 1 ec2-user ec2-user  141 Mar 15 10:00 .bash_profile
-rw-r--r--. 1 ec2-user ec2-user  492 Mar 15 10:00 .bashrc
drwx------. 2 ec2-user ec2-user   29 Apr 19 10:00 .ssh
```

Verify SSH keys are still present:

```bash
cat ~/.ssh/authorized_keys
```

Should show your public key.

### Step 6 - Verify ownership

```bash
ls -la /home/
```

Confirm the `ec2-user` directory is owned by `ec2-user:ec2-user`.

---

## Root Cause

The home directory `/home/ec2-user` was renamed to `/home/ec2-user.broken`. This caused the user's shell configuration files to be missing, making the login environment incomplete.

---

## Prevention

- Never rename or move a user's home directory while they are logged in.
- To properly move a home directory, use `usermod -d /new/path -m username` which updates both the directory and `/etc/passwd`.
- Back up home directories before making changes.
- Use configuration management to ensure home directories are correctly configured.

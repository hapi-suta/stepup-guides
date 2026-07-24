# Scenario 03 - Wrong File Permissions

**Severity:** P2 - High
**Expected Recovery Time:** 5-10 minutes
**Single Node:** NODE1 only

---

## Alert

```
ALERT: DNS resolution is failing for local hostnames
Applications cannot resolve hostnames to IP addresses.
The /etc/hosts file may be corrupted or inaccessible.
```

---

## Key Concepts for Revision

- **/etc/hosts** - A file that maps hostnames to IP addresses. The system checks this file before querying DNS. If it cannot be read, hostname resolution for local entries fails.

- **chmod** - Changes file permissions. Uses numeric notation (e.g., `chmod 644 file`) or symbolic notation (e.g., `chmod u+r file`).

- **Permission 000** - No one can read, write, or execute the file. Even the file owner is locked out. Only root (using sudo) can override this.

- **Standard /etc/hosts permission** - Should be `644` (owner read+write, group and others read). This file needs to be readable by all users and services on the system.

---

## Diagnostic Steps

### Step 1 - Try to read /etc/hosts

```bash
cat /etc/hosts
```

Expected: `cat: /etc/hosts: Permission denied`

This confirms the file exists but cannot be read.

### Step 2 - Check the current permissions

```bash
ls -la /etc/hosts
```

```
Expected output (yours will differ):
----------. 1 root root 158 Apr 19 10:00 /etc/hosts
```

The permission string `----------` means 000 - no one has any access.

### Step 3 - Check what the permissions should be

The correct permission for `/etc/hosts` is `644`:
- Owner (root): read + write
- Group (root): read
- Others: read

All users and services need to read this file for hostname resolution.

### Step 4 - Fix the permissions

```bash
sudo chmod 644 /etc/hosts
```

This restores the standard permissions.

### Step 5 - Verify the fix

```bash
ls -la /etc/hosts
```

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 158 Apr 19 10:00 /etc/hosts
```

Confirm the file is readable:

```bash
cat /etc/hosts
```

You should see the hostname-to-IP mappings.

```
Expected output (yours will differ):
127.0.0.1   localhost localhost.localdomain
::1         localhost localhost.localdomain
```

---

## Root Cause

The permissions on `/etc/hosts` were changed to 000 (no access for anyone). This prevented all users and system services from reading the file, which broke local hostname resolution.

---

## Prevention

- Never change permissions on system files in `/etc` without understanding the impact.
- Use `rpm -V setup` to verify that system configuration files have correct permissions.
- Implement a configuration management tool (like Ansible) that enforces correct permissions across all servers.
- Monitor critical file permissions with regular audits.

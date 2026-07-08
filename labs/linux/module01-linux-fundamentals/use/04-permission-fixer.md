# Exercise 04 - Permission Fixer

**Time estimate:** 15-20 minutes
**Prerequisites:** BUILD phase guide 06 complete

---

## Objective

You are given a list of files and directories with wrong permissions. Diagnose
what is wrong with each one and fix it. This is exactly what you do when a
database refuses to start because of permission problems.

---

## Setup

Run these commands to create the broken scenario:

```bash
mkdir -p ~/perm-lab/{data,config,scripts,logs}
```

```bash
touch ~/perm-lab/config/postgresql.conf
```

```bash
touch ~/perm-lab/config/pg_hba.conf
```

```bash
touch ~/perm-lab/scripts/backup.sh
```

```bash
touch ~/perm-lab/scripts/monitor.sh
```

```bash
touch ~/perm-lab/logs/server.log
```

Now set the WRONG permissions:

```bash
chmod 777 ~/perm-lab/data
```

```bash
chmod 644 ~/perm-lab/config/postgresql.conf
```

```bash
chmod 777 ~/perm-lab/config/pg_hba.conf
```

```bash
chmod 644 ~/perm-lab/scripts/backup.sh
```

```bash
chmod 644 ~/perm-lab/scripts/monitor.sh
```

```bash
chmod 600 ~/perm-lab/logs/server.log
```

---

## Tasks

Check the current permissions:

```bash
ls -la ~/perm-lab/
```

```bash
ls -la ~/perm-lab/config/
```

```bash
ls -la ~/perm-lab/scripts/
```

```bash
ls -la ~/perm-lab/logs/
```

For each item below, explain what is wrong and fix it.

---

**1. The data directory has permission 777. What is wrong and what should it be?**

<details>
<summary>Answer</summary>

**Problem:** 777 means everyone can read, write, and enter the data directory.
This is a critical security issue. Anyone on the server can read or modify
database files. PostgreSQL will refuse to start with these permissions.

**Fix:**
```bash
chmod 700 ~/perm-lab/data
```

**Correct permission:** 700 (only the owner has access).
</details>

---

**2. postgresql.conf has permission 644. Is this correct?**

<details>
<summary>Answer</summary>

**Problem:** 644 means everyone can read the config file. Database config
files can contain sensitive settings (like connection strings or auth
methods). They should be 600 so only the owner can read them.

**Fix:**
```bash
chmod 600 ~/perm-lab/config/postgresql.conf
```

**Correct permission:** 600 (only the owner can read and write).
</details>

---

**3. pg_hba.conf has permission 777. What is wrong?**

<details>
<summary>Answer</summary>

**Problem:** 777 means everyone can read AND write this file. pg_hba.conf
controls who is allowed to connect to the database. If anyone can modify it,
they could grant themselves access. PostgreSQL requires this file to be
readable only by the database owner.

**Fix:**
```bash
chmod 600 ~/perm-lab/config/pg_hba.conf
```

**Correct permission:** 600 (only the owner can read and write).
</details>

---

**4. backup.sh and monitor.sh have permission 644. What is wrong?**

<details>
<summary>Answer</summary>

**Problem:** 644 means the scripts are not executable. If you try to run
`./backup.sh`, you will get "Permission denied" because the execute bit is
not set.

**Fix:**
```bash
chmod 755 ~/perm-lab/scripts/backup.sh
```

```bash
chmod 755 ~/perm-lab/scripts/monitor.sh
```

**Correct permission:** 755 (owner can read/write/execute, others can
read/execute).
</details>

---

**5. server.log has permission 600. Is this a problem?**

<details>
<summary>Answer</summary>

**Problem:** 600 means only the owner can read the log file. Monitoring tools
and other team members might need to read logs for troubleshooting. Log files
should typically be 644 so they are readable by everyone.

**Fix:**
```bash
chmod 644 ~/perm-lab/logs/server.log
```

**Correct permission:** 644 (owner can read/write, others can read).
</details>

---

## Verify all fixes

```bash
ls -la ~/perm-lab/
```

Expected:
```
drwx------. 2 ec2-user ec2-user   6 ... data
drwxr-xr-x. 2 ec2-user ec2-user  ... config
drwxr-xr-x. 2 ec2-user ec2-user  ... logs
drwxr-xr-x. 2 ec2-user ec2-user  ... scripts
```

```bash
ls -la ~/perm-lab/config/
```

Expected:
```
-rw-------. 1 ec2-user ec2-user 0 ... pg_hba.conf
-rw-------. 1 ec2-user ec2-user 0 ... postgresql.conf
```

```bash
ls -la ~/perm-lab/scripts/
```

Expected:
```
-rwxr-xr-x. 1 ec2-user ec2-user 0 ... backup.sh
-rwxr-xr-x. 1 ec2-user ec2-user 0 ... monitor.sh
```

---

## Clean up

```bash
rm -r ~/perm-lab
```

---

## Key Takeaways

| Item | Correct Permission | Why |
|------|-------------------|-----|
| Data directory | 700 | Only the DB user should access data files |
| Config files | 600 | Contain sensitive settings, owner-only |
| Script files | 755 | Must be executable, readable by monitoring |
| Log files | 644 | Must be readable for troubleshooting |

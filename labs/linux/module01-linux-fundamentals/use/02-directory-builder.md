# Exercise 02 - Directory Builder

**Time estimate:** 20 minutes
**Prerequisites:** BUILD phase guides 03 and 06 complete

---

## Objective

Build a complete PostgreSQL-style directory layout from scratch and set
correct permissions for each directory. This mimics what you would do when
preparing a server for a new PostgreSQL installation.

---

## Task

Build the following directory structure under `/opt/pgsql/`:

```
/opt/pgsql/
├── data/         (permission: 700)
├── wal/          (permission: 700)
├── log/          (permission: 755)
├── backup/       (permission: 755)
└── scripts/      (permission: 755)
```

You will need `sudo` to create directories under `/opt` because it is owned
by root.

### Step 1 - Create the entire structure

Create all directories in one command.

<details>
<summary>Hint</summary>

Use `mkdir -p` with curly braces to create multiple directories at once.
You will need `sudo` because `/opt` is owned by root.
</details>

<details>
<summary>Answer</summary>

```bash
sudo mkdir -p /opt/pgsql/{data,wal,log,backup,scripts}
```
</details>

---

### Step 2 - Set permissions

Set the correct permission on each directory:

- `data` and `wal` need 700 (only the database user should access these)
- `log`, `backup`, and `scripts` need 755 (readable by others for monitoring)

<details>
<summary>Answer</summary>

```bash
sudo chmod 700 /opt/pgsql/data
```

```bash
sudo chmod 700 /opt/pgsql/wal
```

```bash
sudo chmod 755 /opt/pgsql/log
```

```bash
sudo chmod 755 /opt/pgsql/backup
```

```bash
sudo chmod 755 /opt/pgsql/scripts
```
</details>

---

### Step 3 - Create sample files

Create the following empty files to simulate a real installation:

- `/opt/pgsql/log/postgresql.log`
- `/opt/pgsql/backup/base-backup-2026-04-19.tar.gz`
- `/opt/pgsql/scripts/daily-backup.sh`
- `/opt/pgsql/scripts/check-replication.sh`

<details>
<summary>Answer</summary>

```bash
sudo touch /opt/pgsql/log/postgresql.log
```

```bash
sudo touch /opt/pgsql/backup/base-backup-2026-04-19.tar.gz
```

```bash
sudo touch /opt/pgsql/scripts/daily-backup.sh
```

```bash
sudo touch /opt/pgsql/scripts/check-replication.sh
```
</details>

---

### Step 4 - Make scripts executable

Set the script files to 755 so they can be executed.

<details>
<summary>Answer</summary>

```bash
sudo chmod 755 /opt/pgsql/scripts/daily-backup.sh
```

```bash
sudo chmod 755 /opt/pgsql/scripts/check-replication.sh
```
</details>

---

### Step 5 - Verify everything

Use `tree` and `ls -la` to verify the entire structure and permissions.

<details>
<summary>Answer</summary>

```bash
tree /opt/pgsql
```

Expected:
```
/opt/pgsql
├── backup
│   └── base-backup-2026-04-19.tar.gz
├── data
├── log
│   └── postgresql.log
├── scripts
│   ├── check-replication.sh
│   └── daily-backup.sh
└── wal

5 directories, 4 files
```

```bash
ls -la /opt/pgsql/
```

Expected:
```
total 0
drwxr-xr-x. 7 root root 73 Apr 19 15:30 .
drwxr-xr-x. 3 root root 19 Apr 19 15:30 ..
drwxr-xr-x. 2 root root 45 Apr 19 15:30 backup
drwx------. 2 root root  6 Apr 19 15:30 data
drwxr-xr-x. 2 root root 30 Apr 19 15:30 log
drwxr-xr-x. 2 root root 52 Apr 19 15:30 scripts
drwx------. 2 root root  6 Apr 19 15:30 wal
```

Verify that `data` and `wal` show `drwx------` (700) and the others show
`drwxr-xr-x` (755).
</details>

---

### Step 6 - Clean up

Remove the entire structure when you are done:

```bash
sudo rm -r /opt/pgsql
```

Verify it is gone:

```bash
ls /opt/pgsql
```

```
Expected output (yours will differ):
ls: cannot access '/opt/pgsql': No such file or directory
```

---

## Why This Matters

In a real PostgreSQL deployment:

- **data/** holds the actual database files. Permission 700 prevents other
  users from reading sensitive data.
- **wal/** holds write-ahead log files (transaction logs). Permission 700
  because these can be used to reconstruct data.
- **log/** holds server log files. Permission 755 so monitoring tools can read
  them.
- **backup/** holds backup files. Permission 755 so backup scripts running as
  different users can write here.
- **scripts/** holds maintenance scripts. Permission 755 so they can be
  executed.

# Build 01: Server Preparation

Prepare both servers (NODE1 and NODE2) for the backup and recovery lab.

Run every step on BOTH servers unless noted otherwise.

---

## 0. Connect to your servers

Before you can run any commands, you need to SSH into your servers. Your welcome email has your server IPs and SSH key.

### Mac / Linux

Open **Terminal** (on Mac: press Cmd + Space, type Terminal, press Enter) and run:

```bash
ssh -i ~/.ssh/[YOUR-KEY-FILE].pem ec2-user@[NODE1_IP]
```

If it asks "Are you sure you want to continue connecting?" type `yes` and press Enter.

### Windows (MobaXterm)

**MobaXterm** is a free terminal for Windows that works like a Linux terminal. Download it from **mobaxterm.mobatek.net** (Home Edition, free).

Open MobaXterm. You will see a local terminal at the bottom - this is where you run commands.

Save your SSH key first. Your welcome email has the key attached as a `.pem` file. Download the attachment, then run these commands in the MobaXterm terminal one at a time:

```bash
mkdir -p ~/.ssh && cp /drives/c/Users/*/Downloads/[YOUR-KEY-FILE].pem ~/.ssh/ && chmod 400 ~/.ssh/[YOUR-KEY-FILE].pem
```

If the file is not in Downloads, check your Desktop:

```bash
mkdir -p ~/.ssh && cp /drives/c/Users/*/Desktop/[YOUR-KEY-FILE].pem ~/.ssh/ && chmod 400 ~/.ssh/[YOUR-KEY-FILE].pem
```

Now connect:

```bash
ssh -i ~/.ssh/[YOUR-KEY-FILE].pem ec2-user@[NODE1_IP]
```

If it asks "Are you sure you want to continue connecting?" type `yes` and press Enter.

---

## 1. Update the OS

**Run on BOTH servers:**

SSH into your server as `ec2-user`:

```bash
ssh ec2-user@[NODE_IP]
```

Update all installed packages. The `-y` flag automatically answers "yes" to prompts so you don't have to confirm each one:

```bash
sudo dnf update -y
```

Expected: packages updated, no errors.

```
Expected output (yours will differ):
Last metadata expiration check: 0:02:15 ago on ...
Dependencies resolved.
...
Complete!
```

## 2. Set the hostname

Setting a hostname makes it easier to know which server you're on when you have multiple terminals open.

**Run on NODE1 (pg-primary):**

```bash
sudo hostnamectl set-hostname pg-primary
```

**Run on NODE2 (pg-backup):**

```bash
sudo hostnamectl set-hostname pg-backup
```

Verify the hostname was set. This prints the current hostname:

```bash
hostnamectl
```

```
Expected output (yours will differ):
 Static hostname: pg-primary
       Icon name: computer-vm
         Chassis: vm
      Machine ID: ...
    Operating System: CentOS Stream 9
```

## 3. Add /etc/hosts entries

The `/etc/hosts` file maps hostnames to IP addresses so you can type `pg-primary` instead of remembering an IP address.

**Run on BOTH servers:**

**Replace [NODE1_IP] and [NODE2_IP] with your actual IP addresses before running this command.**

Add entries for both nodes:

```bash
sudo tee -a /etc/hosts <<EOF
[NODE1_IP]  pg-primary
[NODE2_IP]  pg-backup
EOF
```

The `<<EOF` means "everything between this line and the next `EOF` is the text to write." The `tee -a` command appends that text to a file. We use `sudo tee` because the `/etc/hosts` file requires root privileges to edit.

Verify both names resolve. The `-c 2` flag sends just 2 pings and then stops:

```bash
ping -c 2 pg-primary
```

```bash
ping -c 2 pg-backup
```

Expected: both resolve and respond.

```
Expected output (yours will differ):
PING pg-primary (172.31.31.250) 56(84) bytes of data.
64 bytes from pg-primary (172.31.31.250): icmp_seq=1 ttl=64 time=0.015 ms
64 bytes from pg-primary (172.31.31.250): icmp_seq=2 ttl=64 time=0.024 ms
```

## 4. Firewall - SKIP THIS STEP

> **Your lab servers run on AWS.** Firewall rules are handled by AWS Security
> Groups, which were configured during provisioning. Ports 22 (SSH) and 5432
> (PostgreSQL) are already open between your two nodes. There is nothing to
> do here - move on to step 5.
>
> If you run `firewall-cmd`, you will see `command not found` because
> `firewalld` is not installed on this AMI. That is normal on AWS - security
> groups replace OS-level firewalls.

**Why security groups instead of firewalld?**

On cloud providers (AWS, GCP, Azure), network-level firewalls sit outside your
server. They filter traffic before it reaches the OS, so there is no need for
an OS firewall like firewalld or iptables. Your security group already allows:
- TCP 22 from anywhere (SSH)
- TCP 0-65535 between your two lab servers (intra-group)

## 5. Install essential tools

**Run on BOTH servers:**

Install common utilities we'll need throughout the lab. The `-y` flag skips the confirmation prompt:

```bash
sudo dnf install -y vim curl wget gnupg2 sudo net-tools rsync tar
```

```
Expected output (yours will differ):
Dependencies resolved.
...
Installed:
  vim-enhanced-...  curl-...  wget-...  gnupg2-...  net-tools-...  rsync-...  tar-...
Complete!
```

**Why rsync?** We install rsync explicitly because it is the backbone of WAL archiving in this lab. The `archive_command` on the primary will use rsync to copy WAL segments to the backup server. Without rsync, WAL archiving will not work and point-in-time recovery will be impossible.

> **Concept - rsync**: We install rsync explicitly because it is the backbone of
> WAL archiving in this lab. The archive_command on the primary will rsync WAL
> segments to the backup server. rsync uses delta transfers - it only sends the
> bytes that changed - making it efficient for large files.

## 6. Set timezone to UTC

**Run on BOTH servers:**

Set the system timezone to UTC:

```bash
sudo timedatectl set-timezone UTC
```

Verify the change:

```bash
timedatectl
```

Expected: `Time zone: UTC`.

```
Expected output (yours will differ):
               Local time: Sat 2026-04-19 01:00:00 UTC
           Universal time: Sat 2026-04-19 01:00:00 UTC
                 RTC time: Sat 2026-04-19 01:00:00 UTC
                Time zone: UTC (UTC, +0000)
```

> **Concept - UTC everywhere**: Production databases should always run in UTC.
> Timezone-aware applications convert for display. This prevents daylight saving
> surprises in cron jobs, WAL timestamps, and log correlation across regions.
> PITR recovery targets are especially sensitive to timezone confusion.

## 7. Verify SSH key-based authentication

SSH keys let you connect between servers without typing a password every time. This is required because backup tools (rsync, pgBackRest) need to transfer files automatically.

Inter-node SSH has been pre-configured for you during server setup. Let's verify it works.

### From NODE1

**Run on NODE1 (pg-primary):**

```bash
ssh ec2-user@pg-backup hostname
```

If it asks "Are you sure you want to continue connecting?" type `yes` and press Enter. You should NOT be asked for a password.

```
Expected output:
pg-backup
```

### From NODE2

**Run on NODE2 (pg-backup):**

```bash
ssh ec2-user@pg-primary hostname
```

```
Expected output:
pg-primary
```

If either test asks for a password instead of connecting, contact your instructor.

> **Concept - Bidirectional SSH**: WAL archiving needs NODE1 to push files to
> NODE2 (rsync over SSH). pgBackRest needs SSH in both directions when running
> in remote mode. Setting up keys now saves debugging later.

## 8. Verify the postgres user SSH keys

The PostgreSQL processes run as the `postgres` user. Archive commands and
pgBackRest also run as `postgres`, so this user needs SSH access too.

The postgres user and its SSH keys were wired up for you during server setup. Let's verify - you should not need to create anything.

### On NODE1

**Run on NODE1 (pg-primary):**

Confirm the postgres user exists and note its home directory - SSH looks for keys under that home, so this is the value that matters:

```bash
getent passwd postgres
```

You should see its home is `/var/lib/pgsql` (the seventh field, after the last colon). Do NOT run `useradd` - the PostgreSQL package already created this user during setup. Creating it again with a different home (like `/home/postgres`) is exactly what breaks the SSH key lookups.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Test SSH to NODE2:

```bash
ssh postgres@pg-backup hostname
```

If it asks "Are you sure you want to continue connecting?" type `yes` and press Enter. You should NOT be asked for a password.

```
Expected output:
pg-backup
```

Exit back to ec2-user:

```bash
exit
```

### On NODE2

**Run on NODE2 (pg-backup):**

Confirm the postgres user exists here too:

```bash
getent passwd postgres
```

Same as NODE1 - its home should be `/var/lib/pgsql`. Do NOT run `useradd`.

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Test SSH to NODE1:

```bash
ssh postgres@pg-primary hostname
```

```
Expected output:
pg-primary
```

Exit back to ec2-user:

```bash
exit
```

If either test asks for a password instead of connecting, contact your instructor.

## 9. Create custom mount point directories

**Run on BOTH servers:**

Create the `/opt/pgsql` directory tree on BOTH servers. This is where all
PostgreSQL data, logs, WAL, and backups will live.

Create the top-level data directory:

```bash
sudo mkdir -p /opt/pgsql/data
```

Create the log directory:

```bash
sudo mkdir -p /opt/pgsql/log
```

Create the WAL directory:

```bash
sudo mkdir -p /opt/pgsql/wal
```

Create the backup directory:

```bash
sudo mkdir -p /opt/pgsql/backup
```

Change ownership so the `postgres` user owns everything under `/opt/pgsql`. The `-R` flag applies recursively:

```bash
sudo chown -R postgres:postgres /opt/pgsql
```

Lock down the data directory. `700` means only the owner (postgres) can read, write, or enter it. PostgreSQL refuses to start if the data directory permissions are too open:

```bash
sudo chmod 700 /opt/pgsql/data
```

### On NODE1

**Run on NODE1 (pg-primary):**

Switch to the postgres user to create subdirectories:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Create the archive subdirectory:

```bash
mkdir -p /opt/pgsql/backup/archive
```

Create the dumps subdirectory:

```bash
mkdir -p /opt/pgsql/backup/dumps
```

Exit back to ec2-user:

```bash
exit
```

### On NODE2

**Run on NODE2 (pg-backup):**

Switch to the postgres user:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

Create the archive subdirectory:

```bash
mkdir -p /opt/pgsql/backup/archive
```

Create the dumps subdirectory:

```bash
mkdir -p /opt/pgsql/backup/dumps
```

Create the basebackup subdirectory:

```bash
mkdir -p /opt/pgsql/backup/basebackup
```

Create the logical backup subdirectory:

```bash
mkdir -p /opt/pgsql/backup/logical
```

Create the pgbackrest subdirectory:

```bash
mkdir -p /opt/pgsql/backup/pgbackrest
```

Exit back to ec2-user:

```bash
exit
```

### Verify (BOTH nodes)

**Run on BOTH servers:**

List the top-level directories:

```bash
ls -la /opt/pgsql/
```

List the backup subdirectories:

```bash
ls -la /opt/pgsql/backup/
```

Expected: all directories owned by `postgres:postgres`.

```
Expected output (yours will differ):
total 0
drwx------. 2 postgres postgres 6 Apr 19 01:00 data
drwxr-xr-x. 2 postgres postgres 6 Apr 19 01:00 log
drwxr-xr-x. 4 postgres postgres 38 Apr 19 01:00 backup
drwxr-xr-x. 2 postgres postgres 6 Apr 19 01:00 wal
```

> **Concept - Custom mount points**: Organizing PostgreSQL files under a single
> tree (`/opt/pgsql`) makes administration cleaner. In production, each
> subdirectory would be a dedicated volume or mount point - data on fast SSDs,
> WAL on a separate disk for write performance, backups on large spinning disks
> or network storage. Never put backups on the same disk as the database.

---

## Checkpoint

Both servers have:
- [x] Updated OS (CentOS Stream 9)
- [x] Correct hostname (pg-primary, pg-backup)
- [x] /etc/hosts with both nodes
- [x] Firewall handled by AWS security groups (step 4 skipped)
- [x] Essential tools installed (including rsync)
- [x] UTC timezone
- [x] SSH key-based auth between nodes (ec2-user and postgres users)
- [x] `/opt/pgsql/data`, `/opt/pgsql/log`, `/opt/pgsql/wal`, `/opt/pgsql/backup` directories created on both nodes

Proceed to `02-install-postgresql.md`.

# Build 01: Server Preparation

Prepare both servers (NODE1 and NODE2) for the backup and recovery lab.

Run every step on BOTH servers unless noted otherwise.

---

## 1. Update the OS

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

On NODE1:

```bash
sudo hostnamectl set-hostname pg-primary
```

On NODE2:

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

On BOTH servers, add entries for both nodes. Replace `[NODE1_IP]` and `[NODE2_IP]` with your actual IP addresses:

```bash
sudo tee -a /etc/hosts <<EOF
[NODE1_IP]  pg-primary
[NODE2_IP]  pg-backup
EOF
```

(`tee -a` appends text to a file. We use `sudo tee` because `/etc/hosts` requires root privileges to edit.)

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

> **Concept - rsync**: We install rsync explicitly because it is the backbone of
> WAL archiving in this lab. The archive_command on the primary will rsync WAL
> segments to the backup server. rsync uses delta transfers - it only sends the
> bytes that changed - making it efficient for large files.

## 6. Set timezone to UTC

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

## 7. Set up SSH key-based authentication

SSH keys let you connect between servers without typing a password every time. This is required because backup tools (rsync, pgBackRest) need to transfer files automatically.

### On NODE1

Generate an SSH key. The `-N ""` flag sets an empty passphrase (no password on the key). The `-t ed25519` flag uses a modern, secure key type:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

```
Expected output:
Generating public/private ed25519 key pair.
Your identification has been saved in /home/ec2-user/.ssh/id_ed25519
Your public key has been saved in /home/ec2-user/.ssh/id_ed25519.pub
```

Copy your public key to NODE2. This adds it to NODE2's authorized_keys so you can log in without a password:

```bash
ssh-copy-id ec2-user@pg-backup
```

### On NODE2

Generate an SSH key:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

Copy your public key to NODE1:

```bash
ssh-copy-id ec2-user@pg-primary
```

### Verify

From NODE1, test connecting to NODE2:

```bash
ssh ec2-user@pg-backup hostname
```

From NODE2, test connecting to NODE1:

```bash
ssh ec2-user@pg-primary hostname
```

Expected: returns the other node's hostname without a password prompt.

```
Expected output:
pg-backup
```

> **Concept - Bidirectional SSH**: WAL archiving needs NODE1 to push files to
> NODE2 (rsync over SSH). pgBackRest needs SSH in both directions when running
> in remote mode. Setting up keys now saves debugging later.

## 8. Set up the postgres user SSH keys

The PostgreSQL processes run as the `postgres` user. Archive commands and
pgBackRest also run as `postgres`, so this user needs SSH access too.

### On NODE1

Create the `postgres` OS user. The `|| true` at the end prevents an error if the user already exists:

```bash
sudo useradd -m -d /home/postgres -s /bin/bash postgres || true
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the `.ssh` directory:

```bash
mkdir -p ~/.ssh
```

Set permissions so only the postgres user can access this directory. SSH refuses to work if permissions are too open:

```bash
chmod 700 ~/.ssh
```

Generate an SSH key. The `-N ""` flag sets an empty passphrase:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

```
Expected output:
Generating public/private ed25519 key pair.
Your identification has been saved in /home/postgres/.ssh/id_ed25519
Your public key has been saved in /home/postgres/.ssh/id_ed25519.pub
```

Exit back to ec2-user:

```bash
exit
```

### On NODE2

Create the `postgres` OS user:

```bash
sudo useradd -m -d /home/postgres -s /bin/bash postgres || true
```

Switch to the postgres user:

```bash
sudo -iu postgres
```

Create the `.ssh` directory:

```bash
mkdir -p ~/.ssh
```

Set permissions so only the postgres user can access this directory:

```bash
chmod 700 ~/.ssh
```

Exit back to ec2-user:

```bash
exit
```

### Copy keys between nodes

On NODE1, switch to the postgres user and copy the key to NODE2:

```bash
sudo -iu postgres
```

```bash
ssh-copy-id postgres@pg-backup
```

Exit back to ec2-user:

```bash
exit
```

On NODE2, switch to the postgres user, generate a key, and copy it to NODE1:

```bash
sudo -iu postgres
```

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

```bash
ssh-copy-id postgres@pg-primary
```

Exit back to ec2-user:

```bash
exit
```

### Verify

From NODE1, switch to postgres and test:

```bash
sudo -iu postgres
```

```bash
ssh postgres@pg-backup hostname
```

Expected: `pg-backup` without a password prompt.

```
Expected output:
pg-backup
```

Exit back to ec2-user:

```bash
exit
```

## 9. Create custom mount point directories

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

Switch to the postgres user to create subdirectories:

```bash
sudo -iu postgres
```

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

Switch to the postgres user:

```bash
sudo -iu postgres
```

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

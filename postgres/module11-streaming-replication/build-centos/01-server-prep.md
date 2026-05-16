# Build 01: Server Preparation (CentOS Stream 9)

Prepare both servers (NODE1 and NODE2) for PostgreSQL installation.

Run every step on BOTH servers unless noted otherwise.

---

## Connecting to Your Servers

You received two IP addresses in your welcome email: one for NODE1 (pg-primary) and one for NODE2 (pg-standby). You will SSH in as the `ec2-user` account. This user has sudo access, which lets you run commands as root when needed.

**Mac / Linux users:**

Open your terminal. Set the correct permissions on your key file first. The `chmod 400` command makes the file readable only by you, which SSH requires:

```bash
chmod 400 ~/Downloads/your-key.pem
```

Connect to NODE1:

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE1_IP]
```

Connect to NODE2 (open a second terminal tab):

```bash
ssh -i ~/Downloads/your-key.pem ec2-user@[NODE2_IP]
```

**Windows users (MobaXterm):**

1. Open MobaXterm.
2. Click **Session** - then **SSH**.
3. In the **Remote host** field, enter your server IP.
4. Check **Specify username** and enter `ec2-user`.
5. Under **Advanced SSH settings**, check **Use private key** and browse to your `.pem` file.
6. Click **OK** to connect.

You should see a prompt that looks like: `[ec2-user@ip-xxx ~]$`

---

## Important: How Sudo Works on This Server

You are logged in as `ec2-user`. This is a regular user, but it can run any command as root by adding `sudo` in front. You will see `sudo` on almost every command in this guide. Do not skip it.

To run commands as the `postgres` operating system user, you will use:

```bash
sudo -iu postgres
```

The `-i` flag gives you a login shell as postgres (loads its environment). The `-u postgres` means "run as the postgres user". When you are done with postgres commands, type `exit` to return to `ec2-user`.

---

## 1. Update the OS

Run on BOTH servers.

Update the list of available packages and install any security or bug-fix updates. This can take a few minutes:

```bash
sudo dnf update -y
```

`dnf` is the package manager on CentOS Stream 9 (like `apt` on Ubuntu). The `-y` flag automatically answers "yes" to all prompts.

Expected output (yours will differ):

```
Updating Subscription Management repositories.
...
Complete!
```

---

## 2. Set the hostname

Run on NODE1:

```bash
sudo hostnamectl set-hostname pg-primary
```

Run on NODE2:

```bash
sudo hostnamectl set-hostname pg-standby
```

`hostnamectl` sets the system hostname persistently. It takes effect immediately - you do not need to reboot.

Verify the new hostname on each server:

```bash
hostname
```

Expected output on NODE1:

```
pg-primary
```

Expected output on NODE2:

```
pg-standby
```

---

## 3. Add /etc/hosts entries

Run on BOTH servers.

The `/etc/hosts` file maps hostnames to IP addresses locally. Adding both nodes here means PostgreSQL and SSH commands can use names like `pg-primary` instead of raw IP addresses.

Replace `[NODE1_IP]` and `[NODE2_IP]` with your actual server IPs from the welcome email.

```bash
sudo tee -a /etc/hosts <<EOF
[NODE1_IP]  pg-primary
[NODE2_IP]  pg-standby
EOF
```

`tee -a` reads from standard input and appends to the file. The `-a` means append (not overwrite).

Verify both names resolve:

```bash
ping -c 2 pg-primary
```

`-c 2` sends only 2 ping packets instead of pinging forever.

```bash
ping -c 2 pg-standby
```

Expected output (yours will differ):

```
PING pg-primary (10.0.1.100) 56(84) bytes of data.
64 bytes from pg-primary (10.0.1.100): icmp_seq=1 ttl=64 time=0.45 ms
64 bytes from pg-primary (10.0.1.100): icmp_seq=2 ttl=64 time=0.38 ms
```

Both names must respond before you continue.

---

## 4. Firewall

Run on BOTH servers.

**Skip this step.** These servers run on AWS, where security groups control network access. The security group for this lab already allows TCP 5432 (PostgreSQL) and TCP 22 (SSH) between your two nodes. You do not need to configure `firewalld`.

> **Concept - Security groups vs host firewall**: AWS security groups are stateful firewalls attached to your network interface. They filter traffic before it even reaches the OS. For lab environments this is sufficient. In production on bare metal or on-prem servers, you would also configure `firewalld` as a second layer of defense.

---

## 5. Install essential tools

Run on BOTH servers.

Install utilities you will need during the lab:

```bash
sudo dnf install -y vim curl wget gnupg2 sudo net-tools rsync tar
```

Each package:
- `vim` - text editor used for all config file edits in this lab
- `curl` / `wget` - download files from the internet
- `gnupg2` - GPG key handling (used when adding repos)
- `net-tools` - provides `netstat` for checking open ports
- `rsync` / `tar` - file copy and archive utilities

Expected output (yours will differ):

```
Last metadata expiration check: 0:03:12 ago on ...
Package vim-enhanced-2:8.2... is already installed.
...
Complete!
```

---

## 6. Set timezone to UTC

Run on BOTH servers.

Databases should always run in UTC. This prevents daylight saving surprises in cron jobs, WAL timestamps, and log correlation across regions:

```bash
sudo timedatectl set-timezone UTC
```

Verify the timezone was set correctly:

```bash
timedatectl
```

Expected output (yours will differ):

```
               Local time: Thu 2026-05-15 14:32:01 UTC
           Universal time: Thu 2026-05-15 14:32:01 UTC
                 RTC time: Thu 2026-05-15 14:32:01
                Time zone: UTC (UTC, +0000)
System clock synchronized: yes
```

The line `Time zone: UTC` confirms success.

> **Concept - UTC everywhere**: Production databases should always run in UTC. Timezone-aware applications convert for display. This prevents daylight saving surprises in cron jobs, WAL timestamps, and log correlation across regions.

---

## 7. Verify SSH between nodes

The provisioning script pre-configured SSH key trust between both nodes for the `postgres` operating system user. After you install PostgreSQL in the next guide, the `postgres` user will exist and you can verify this works.

For now, test that the `ec2-user` can reach each node by hostname.

From NODE1:

```bash
ssh ec2-user@pg-standby hostname
```

From NODE2:

```bash
ssh ec2-user@pg-primary hostname
```

Expected output (from each direction):

```
pg-standby
```

```
pg-primary
```

If the command asks for a password instead of connecting, contact your instructor. SSH keys have been pre-configured during server provisioning.

---

## Checkpoint

Both servers have:
- [x] Updated OS (dnf update complete)
- [x] Correct hostname (pg-primary / pg-standby)
- [x] /etc/hosts with both node IPs
- [x] Firewall skipped (AWS security groups in use)
- [x] Essential tools installed (vim, curl, net-tools, etc.)
- [x] UTC timezone
- [x] SSH key-based access between nodes confirmed

Proceed to `02-postgres-install.md`.

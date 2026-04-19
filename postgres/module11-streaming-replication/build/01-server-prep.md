# Build 01: Server Preparation

Prepare both servers (NODE1 and NODE2) for PostgreSQL installation.

Run every step on BOTH servers unless noted otherwise.

---

## 1. Update the OS

```bash
apt update && apt upgrade -y
```

Expected: packages updated, no errors.

## 2. Set the hostname

On NODE1:
```bash
hostnamectl set-hostname pg-primary
```

On NODE2:
```bash
hostnamectl set-hostname pg-standby
```

## 3. Add /etc/hosts entries

On BOTH servers, add these lines to `/etc/hosts` (substitute your actual IPs):

```bash
cat >> /etc/hosts <<EOF
[NODE1_IP]  pg-primary
[NODE2_IP]  pg-standby
EOF
```

Verify:
```bash
ping -c 2 pg-primary
ping -c 2 pg-standby
```

Expected: both resolve and respond.

## 4. Configure firewall

Allow PostgreSQL and SSH between the two nodes:

```bash
apt install -y ufw
ufw allow 22/tcp
ufw allow 5432/tcp
ufw --force enable
ufw status
```

Expected: `Status: active` with rules for 22 and 5432.

> **Note - Cloud providers**: If you are running on AWS, GCP, or similar, skip ufw
> and use security groups instead. Ensure your security group allows TCP 22 (SSH)
> and TCP 5432 (PostgreSQL) between the two instances.

> **Note - SSH user**: Cloud AMIs use non-root users (e.g., `admin` on Debian AMIs,
> `ubuntu` on Ubuntu). Set `SSH_USER=admin` in your student.env. All `sudo` commands
> in this guide work with any sudo-capable user.

> **Concept - Minimal firewall**: In production you would restrict 5432 to specific
> source IPs. For this lab, allowing from any source is fine because these are
> ephemeral servers. The habit of enabling a firewall at all is what matters.

## 5. Install essential tools

```bash
apt install -y vim curl wget gnupg2 lsb-release sudo net-tools
```

## 6. Set timezone to UTC

```bash
timedatectl set-timezone UTC
timedatectl
```

Expected: `Time zone: UTC`.

> **Concept - UTC everywhere**: Production databases should always run in UTC.
> Timezone-aware applications convert for display. This prevents daylight saving
> surprises in cron jobs, WAL timestamps, and log correlation across regions.

## 7. Verify SSH between nodes

From NODE1:
```bash
ssh root@pg-standby hostname
```

From NODE2:
```bash
ssh root@pg-primary hostname
```

Expected: returns the other node's hostname without password prompt.

If prompted for a password, set up key-based auth:
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
ssh-copy-id root@pg-standby   # from NODE1
ssh-copy-id root@pg-primary   # from NODE2
```

---

## Checkpoint

Both servers have:
- [x] Updated OS
- [x] Correct hostname
- [x] /etc/hosts with both nodes
- [x] Firewall active with 22 + 5432 open
- [x] Essential tools installed
- [x] UTC timezone
- [x] SSH key-based auth between nodes

Proceed to `02-postgres-install.md`.

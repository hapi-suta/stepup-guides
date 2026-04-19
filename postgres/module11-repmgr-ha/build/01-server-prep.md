# Build 01: Server Preparation

Prepare all four servers (NODE1, NODE2, NODE3, NODE4) for the repmgr HA lab.

Run every step on ALL FOUR servers unless noted otherwise.

---

## 1. Update the OS

```bash
apt update && apt upgrade -y
```

Expected: packages updated, no errors.

## 2. Set the hostnames

On NODE1:
```bash
hostnamectl set-hostname pg-repmgr-1
```

On NODE2:
```bash
hostnamectl set-hostname pg-repmgr-2
```

On NODE3:
```bash
hostnamectl set-hostname pg-repmgr-3
```

On NODE4:
```bash
hostnamectl set-hostname pg-repmgr-w
```

## 3. Add /etc/hosts entries

On ALL FOUR servers, add these lines to `/etc/hosts` (substitute your actual IPs):

```bash
cat >> /etc/hosts <<EOF
[NODE1_IP]  pg-repmgr-1
[NODE2_IP]  pg-repmgr-2
[NODE3_IP]  pg-repmgr-3
[NODE4_IP]  pg-repmgr-w
EOF
```

Verify:
```bash
ping -c 2 pg-repmgr-1
ping -c 2 pg-repmgr-2
ping -c 2 pg-repmgr-3
ping -c 2 pg-repmgr-w
```

Expected: all four resolve and respond.

## 4. Configure firewall

Allow PostgreSQL and SSH between all nodes:

```bash
apt install -y ufw
ufw allow 22/tcp
ufw allow 5432/tcp
ufw --force enable
ufw status
```

Expected: `Status: active` with rules for 22 and 5432.

> **Concept - Minimal firewall**: In production you would restrict 5432 to specific
> source IPs within your cluster network. For this lab, allowing from any source is
> fine because these are ephemeral servers. The habit of enabling a firewall at all
> is what matters.

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

## 7. Set up SSH key-based auth between all nodes

From each node, you need passwordless SSH to every other node. This is required
because repmgr executes remote commands (like `repmgr standby switchover`) over SSH.

On ALL FOUR servers:
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
```

Then copy keys between all nodes. From NODE1:
```bash
ssh-copy-id root@pg-repmgr-2
ssh-copy-id root@pg-repmgr-3
ssh-copy-id root@pg-repmgr-w
```

From NODE2:
```bash
ssh-copy-id root@pg-repmgr-1
ssh-copy-id root@pg-repmgr-3
ssh-copy-id root@pg-repmgr-w
```

From NODE3:
```bash
ssh-copy-id root@pg-repmgr-1
ssh-copy-id root@pg-repmgr-2
ssh-copy-id root@pg-repmgr-w
```

From NODE4:
```bash
ssh-copy-id root@pg-repmgr-1
ssh-copy-id root@pg-repmgr-2
ssh-copy-id root@pg-repmgr-3
```

Verify from each node:
```bash
ssh root@pg-repmgr-1 hostname
ssh root@pg-repmgr-2 hostname
ssh root@pg-repmgr-3 hostname
ssh root@pg-repmgr-w hostname
```

Expected: returns each node's hostname without password prompt.

> **Concept - SSH for repmgr operations**: Unlike basic streaming replication,
> repmgr needs SSH access between nodes. During a switchover, repmgr SSHes to
> the current primary to stop it, then promotes the target standby. Without
> passwordless SSH, automated failover via repmgrd will fail.

## 8. Set up SSH for the postgres user

repmgr runs commands as the `postgres` OS user. The postgres user also needs
passwordless SSH between nodes:

On ALL FOUR servers:
```bash
sudo -iu postgres bash -c 'ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519'
```

From NODE1 (as postgres):
```bash
sudo -iu postgres ssh-copy-id postgres@pg-repmgr-2
sudo -iu postgres ssh-copy-id postgres@pg-repmgr-3
sudo -iu postgres ssh-copy-id postgres@pg-repmgr-w
```

Repeat from NODE2, NODE3, and NODE4 to all other nodes.

Verify from each node:
```bash
sudo -iu postgres ssh postgres@pg-repmgr-1 hostname
sudo -iu postgres ssh postgres@pg-repmgr-2 hostname
sudo -iu postgres ssh postgres@pg-repmgr-3 hostname
sudo -iu postgres ssh postgres@pg-repmgr-w hostname
```

Expected: returns hostnames without password prompt.

---

## Checkpoint

All four servers have:
- [x] Updated OS
- [x] Correct hostname (pg-repmgr-1, pg-repmgr-2, pg-repmgr-3, pg-repmgr-w)
- [x] /etc/hosts with all four nodes
- [x] Firewall active with 22 + 5432 open
- [x] Essential tools installed
- [x] UTC timezone
- [x] SSH key-based auth between all nodes (root and postgres users)

Proceed to `02-install-postgresql.md`.

# Build 01: Server Preparation

Prepare all four servers (NODE1, NODE2, NODE3, NODE4) for the repmgr HA lab.

Run every step on ALL FOUR servers unless noted otherwise.

---

## 1. Update the OS

```bash
apt update
```

```bash
apt upgrade -y
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

Verify each hostname resolves. Run these one at a time:

```bash
ping -c 2 pg-repmgr-1
```

The `-c 2` flag sends only 2 ping packets, then stops.

```bash
ping -c 2 pg-repmgr-2
```

```bash
ping -c 2 pg-repmgr-3
```

```bash
ping -c 2 pg-repmgr-w
```

Expected: all four resolve and respond.

## 4. Configure firewall

Allow PostgreSQL and SSH between all nodes:

```bash
apt install -y ufw
```

The `-y` flag auto-confirms the install prompt.

```bash
ufw allow 22/tcp
```

This allows SSH connections through the firewall.

```bash
ufw allow 5432/tcp
```

This allows PostgreSQL connections through the firewall.

```bash
ufw --force enable
```

The `--force` flag skips the "are you sure?" prompt. This activates the firewall.

```bash
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
```

```bash
timedatectl
```

Expected: `Time zone: UTC`.

> **Concept - UTC everywhere**: Production databases should always run in UTC.
> Timezone-aware applications convert for display. This prevents daylight saving
> surprises in cron jobs, WAL timestamps, and log correlation across regions.

## 7. Verify SSH key-based auth between all nodes

From each node, you need passwordless SSH to every other node. This is required
because repmgr executes remote commands (like `repmgr standby switchover`) over SSH.

Inter-node SSH has been pre-configured for you during server setup. Let's verify it works.

From each node, test connecting to every other node. If it asks "Are you sure you want to continue connecting?" type `yes` and press Enter. You should NOT be asked for a password.

From NODE1:

```bash
ssh root@pg-repmgr-2 hostname
```

```bash
ssh root@pg-repmgr-3 hostname
```

```bash
ssh root@pg-repmgr-w hostname
```

From NODE2:

```bash
ssh root@pg-repmgr-1 hostname
```

```bash
ssh root@pg-repmgr-3 hostname
```

```bash
ssh root@pg-repmgr-w hostname
```

From NODE3:

```bash
ssh root@pg-repmgr-1 hostname
```

```bash
ssh root@pg-repmgr-2 hostname
```

```bash
ssh root@pg-repmgr-w hostname
```

From NODE4:

```bash
ssh root@pg-repmgr-1 hostname
```

```bash
ssh root@pg-repmgr-2 hostname
```

```bash
ssh root@pg-repmgr-3 hostname
```

Expected: returns each node's hostname without password prompt. If any test asks for a password, contact your instructor.

> **Concept - SSH for repmgr operations**: Unlike basic streaming replication,
> repmgr needs SSH access between nodes. During a switchover, repmgr SSHes to
> the current primary to stop it, then promotes the target standby. Without
> passwordless SSH, automated failover via repmgrd will fail.

## 8. Verify SSH for the postgres user

repmgr runs commands as the `postgres` OS user. The postgres user also needs
passwordless SSH between nodes. This has been pre-configured - let's verify.

From each node, switch to the postgres user and test:

```bash
sudo -iu postgres
```

**You are now the postgres user.**

```bash
ssh postgres@pg-repmgr-1 hostname
```

```bash
ssh postgres@pg-repmgr-2 hostname
```

```bash
ssh postgres@pg-repmgr-3 hostname
```

```bash
ssh postgres@pg-repmgr-w hostname
```

(Skip the hostname that matches the node you are on.)

Expected: returns hostnames without password prompt.

```bash
exit
```

Repeat on all four nodes. If any test asks for a password, contact your instructor.

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

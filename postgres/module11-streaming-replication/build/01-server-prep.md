# Build 01: Server Preparation (CentOS Stream 9)

Prepare both servers (NODE1 and NODE2) for PostgreSQL installation.

Run every step on BOTH servers unless noted otherwise.

---

## 1. Update the OS

```bash
sudo dnf update -y
```

`-y` automatically answers "yes" to all prompts.

Expected output (yours will differ):
```
Complete!
```

## 2. Set the hostname

On NODE1:
```bash
sudo hostnamectl set-hostname pg-primary
```

On NODE2:
```bash
sudo hostnamectl set-hostname pg-standby
```

Verify the hostname was set:

```bash
hostname
```

Expected: `pg-primary` or `pg-standby` depending on which node you are on.

## 3. Add /etc/hosts entries

On BOTH servers, add these lines to `/etc/hosts` (substitute your actual IPs):

```bash
sudo vi /etc/hosts
```

Add these two lines at the bottom:

```
[NODE1_IP]  pg-primary
[NODE2_IP]  pg-standby
```

Save and exit vi (`:wq`).

Verify:
```bash
ping -c 2 pg-primary
```

`-c 2` sends only 2 ping packets instead of pinging forever.

```bash
ping -c 2 pg-standby
```

Expected: both resolve and respond.

## 4. Firewall

> **Note - AWS students**: Skip this step. Your security group handles firewall rules.
> Ensure your security group allows TCP 22 (SSH) and TCP 5432 (PostgreSQL) between the two instances.

If you are NOT on AWS and want to configure firewalld:

```bash
sudo firewall-cmd --permanent --add-service=ssh
```

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
```

```bash
sudo firewall-cmd --reload
```

Verify:

```bash
sudo firewall-cmd --list-all
```

Expected: ports 22 and 5432 listed.

## 5. Install essential tools

```bash
sudo dnf install -y vim curl wget net-tools
```

## 6. Set timezone to UTC

```bash
sudo timedatectl set-timezone UTC
```

Verify the timezone is now UTC:

```bash
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

If either test asks for a password instead of connecting, contact your instructor. SSH keys have been pre-configured during server setup.

---

## Checkpoint

Both servers have:
- [x] Updated OS
- [x] Correct hostname
- [x] /etc/hosts with both nodes
- [x] Firewall configured (or security group on AWS)
- [x] Essential tools installed
- [x] UTC timezone
- [x] SSH key-based auth between nodes

Proceed to `02-postgres-install.md`.

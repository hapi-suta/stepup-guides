# Build 01: Server Preparation (CentOS Stream 9)

Prepare all four servers (NODE1, NODE2, NODE3, NODE4) for the repmgr HA lab.

Run every step on ALL FOUR servers unless noted otherwise.

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

## 2. Set the hostnames

On NODE1:
```bash
sudo hostnamectl set-hostname pg-repmgr-1
```

On NODE2:
```bash
sudo hostnamectl set-hostname pg-repmgr-2
```

On NODE3:
```bash
sudo hostnamectl set-hostname pg-repmgr-3
```

On NODE4:
```bash
sudo hostnamectl set-hostname pg-repmgr-w
```

Verify the hostname was set:

```bash
hostname
```

Expected: `pg-repmgr-1`, `pg-repmgr-2`, `pg-repmgr-3`, or `pg-repmgr-w` depending on which node you are on.

## 3. Add /etc/hosts entries

On ALL FOUR servers, add entries for every node to `/etc/hosts` (substitute your actual IPs):

```bash
sudo vi /etc/hosts
```

Add these four lines at the bottom:

```
[NODE1_IP]  pg-repmgr-1
[NODE2_IP]  pg-repmgr-2
[NODE3_IP]  pg-repmgr-3
[NODE4_IP]  pg-repmgr-w
```

Save and exit vi (`:wq`).

Verify each hostname resolves. Run these one at a time:

```bash
ping -c 2 pg-repmgr-1
```

`-c 2` sends only 2 ping packets instead of pinging forever.

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

## 4. Firewall

> **Note - AWS students**: Skip this step. Your security group handles firewall rules.
> Ensure your security group allows TCP 22 (SSH) and TCP 5432 (PostgreSQL) between all four instances.

If you are NOT on AWS and want to configure firewalld:

```bash
sudo firewall-cmd --permanent --add-service=ssh
```

This allows SSH connections through the firewall. The `--permanent` flag makes the rule survive reboots.

```bash
sudo firewall-cmd --permanent --add-port=5432/tcp
```

This allows PostgreSQL connections through the firewall.

```bash
sudo firewall-cmd --reload
```

This reloads the firewall so the new rules take effect.

Verify:

```bash
sudo firewall-cmd --list-all
```

Expected output (yours will differ):
```
public (active)
  ...
  services: cockpit dhcpv6-client ssh
  ports: 5432/tcp
  ...
```

> **Concept - Minimal firewall**: In production you would restrict 5432 to specific
> source IPs within your cluster network. For this lab, allowing from any source is
> fine because these are ephemeral servers. The habit of enabling a firewall at all
> is what matters.

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

**You are now back to ec2-user.**

Repeat on all four nodes. If any test asks for a password, contact your instructor.

---

## Checkpoint

All four servers have:
- [x] Updated OS
- [x] Correct hostname (pg-repmgr-1, pg-repmgr-2, pg-repmgr-3, pg-repmgr-w)
- [x] /etc/hosts with all four nodes
- [x] Firewall configured (or security group on AWS)
- [x] Essential tools installed
- [x] UTC timezone
- [x] SSH key-based auth between all nodes (root and postgres users)

Proceed to `02-install-postgresql.md`.

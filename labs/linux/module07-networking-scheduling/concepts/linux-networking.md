# Concepts: Linux Networking and Scheduling

This document is a reference. Read it once before the BUILD guides to get the big
picture. Then come back to it any time a term is unclear.

It explains four things. How a Linux server talks to the network. How the
firewall guards it. How names turn into addresses. How jobs get scheduled to
repeat. You will see all of it through the lens of what a DBA actually needs.

---

## 1. Addresses, Ports, and Sockets

### IP addresses

Every machine on a network has at least one IP address. It is the machine's
identity on the network. Two kinds matter to a DBA:

- **Private IP** (for example `10.0.1.50`) - used inside a private network like
  an AWS VPC. Other machines in the same network reach the server here
- **Public IP** - reachable from the internet. Databases usually should not have
  one. They sit on private networks, behind an app tier
- **Loopback** (`127.0.0.1`, name `localhost`) - always points back to the same
  machine. Traffic to the loopback never leaves the server

A subnet mask tells you how big the local network is. You write it as `/24`,
`/16`, and so on. It sorts addresses into two groups. Some are "local neighbors"
you can reach directly. The rest you reach through a gateway.

### The default gateway and routing

The **routing table** decides where outgoing data goes. Traffic headed for the
local subnet is delivered directly. Everything else goes to the **default
gateway**. Think of the gateway as the server's door to the wider network.

If there is no gateway, the server is trapped on its own subnet. This often
causes failed backups to remote storage and broken replication across networks.

### Ports

An IP address gets data to the right server. A **port** gets it to the right
program on that server. Ports are numbered 0 to 65535. Here are the well-known
ones:

| Port | Service |
|------|---------|
| 22 | SSH |
| 53 | DNS |
| 80 | HTTP |
| 443 | HTTPS |
| 5432 | PostgreSQL |
| 3306 | MySQL |
| 6379 | Redis |

### Sockets and binding

A program that accepts connections **binds** to a pair: an address plus a port.
That pair is a **socket**. The address it binds to matters a lot:

- `127.0.0.1:5432` - only programs on the same server can connect
- `0.0.0.0:5432` - programs on any machine can connect (if the firewall allows)

For PostgreSQL, the `listen_addresses` setting in `postgresql.conf` controls this
binding. The default is `localhost`, which binds to the loopback only. That is
why a fresh install refuses remote clients until you change it.

### LISTEN vs ESTABLISHED

A socket in the **LISTEN** state is a server waiting for new connections. A
socket in the **ESTABLISHED** state is a live session that is connected right
now. `ss -tulpn` shows the listeners. Drop the `-l` flag and you also see
established connections. That is how you count active database sessions.

---

## 2. The Firewall

A firewall decides which traffic is allowed in and out. On CentOS Stream 9 the
firewall is `firewalld`. You control it with `firewall-cmd`.

### Default deny

A safe firewall blocks everything except what you clearly allow. SSH works right
away because the base rules permit port 22. PostgreSQL's port 5432 stays blocked
until you add a rule for it.

### Zones

firewalld groups its rules into **zones**. A zone is a named set of rules applied
to network interfaces. Most single servers use the `public` zone. If you add a
rule without naming a zone, it lands in the active zone.

### Permanent vs runtime

firewalld keeps two rule sets:

- **Runtime** - the live rules right now, lost on reboot
- **Permanent** - saved to disk, survives reboots

`--permanent` writes to disk but does not apply the rule right away. `--reload`
makes the permanent rules live. Forgetting to reload is the classic "I opened the
port but it still does not work" mistake.

### The three gates to a database

For a remote client to reach PostgreSQL, three separate gates must all be open:

1. **PostgreSQL is listening** on a reachable address (`listen_addresses`)
2. **The firewall allows the port** (`firewall-cmd --add-port=5432/tcp`)
3. **`pg_hba.conf` authorizes the client** (host-based authentication)

In the cloud there is often a fourth gate. It is the **security group** or
network ACL. When you debug "cannot connect", check all of these in order.

---

## 3. Name Resolution and DNS

### Why names

Names like `pg-primary` or `db.example.com` are steady and easy to read. IPs
change, and they are easy to mistype. Every time you use a name, something turns
it into an IP address. That step is called **name resolution**.

### The resolution order

`/etc/nsswitch.conf` sets the order Linux checks its sources. On CentOS the
`hosts:` line normally reads `files dns`. That means:

1. **`/etc/hosts`** - the local name table on this machine, checked first
2. **DNS** - the servers listed in `/etc/resolv.conf`, checked only if
   `/etc/hosts` has no answer

The first source with an answer wins. So an `/etc/hosts` entry beats DNS.

### /etc/hosts

This is a plain file. Each line maps an `IP` to a `name`. It needs no DNS server,
and it is checked first. That makes it perfect for labs and for small clusters
where nodes call each other by name. In a replication setup, both nodes list each
other here. Then the config files can use names instead of IPs that might change.

### /etc/resolv.conf

This file lists the DNS `nameserver` to ask. It also lists a `search` domain that
gets added to short names. On CentOS, NetworkManager generates this file, so any
hand edits get wiped out. Read it to understand your DNS setup. To change DNS,
go through NetworkManager instead.

### Testing tools

- `getent hosts NAME` - resolves a name using the full system order (respects
  `/etc/hosts`)
- `nslookup NAME` - queries DNS directly (skips `/etc/hosts`)
- `dig NAME` / `dig +short NAME` - queries DNS directly with more detail

`dig` and `nslookup` skip `/etc/hosts`. But `getent` and normal programs do not.
So the same name can resolve to different answers depending on the tool you use.
This explains many "it works one way but not the other" puzzles.

---

## 4. Scheduling Recurring Jobs

### cron

`cron` runs commands on a schedule, even when no one is logged in. Each user has
a **crontab**. You edit it with `crontab -e` and list it with `crontab -l`. Each
line has five time fields plus a command:

```
minute  hour  day-of-month  month  day-of-week  command
```

`*` means "every value". `0 2 * * *` is "2 AM daily"; `*/15 * * * *` is "every 15
minutes".

Two rules keep cron jobs healthy:

- **Use full paths** to commands. Cron runs with a bare-bones environment and a
  short `PATH`
- **Log the output** with `>>` and `2>&1`. No one watches the output live, so a
  silent failure hides unless you capture it

A `%` has a special meaning in a crontab command. You must escape it as `\%`.
This comes up a lot in backup filenames that include the date.

### systemd timers

This is the modern alternative. A timer uses two files. A `.timer` unit says
when, and a `.service` unit says what. Timers have some upsides over cron:

- They log to the central **journal** (`journalctl`), so runs are easy to review
- With `Persistent=true`, a missed job runs after the server was powered off
- They can depend on other services

List them with `systemctl list-timers`. On CentOS, built-in timers already handle
log rotation and package cache refresh.

### Cron or timer?

Cron is simpler and works everywhere. Timers are easier to watch and more
reliable. Teams often use cron for quick jobs and timers for anything critical.
A DBA should be able to read and maintain both. Servers you inherit will use
whichever one the last admin picked.

### Trust but verify

The biggest scheduling risk is a job that is scheduled but quietly failing. This
is worst with a backup. Whether you use cron or a timer, always confirm the job
actually ran and succeeded. `journalctl -u crond` shows cron runs.
`systemctl status NAME.timer` shows a timer's last and next run times. A backup
you never check is not a backup.

---

## 5. Why This Matters to a DBA

Almost every "the application cannot connect to the database" ticket gets solved
with the skills in this module:

- **Confirm the database is listening** (`ss -tulpn | grep 5432`) and on a
  reachable address, not just the loopback
- **Confirm the port is open** in the firewall and any cloud security group
- **Test connectivity from the client side** with `nc -zv`, and read "refused"
  (server side) vs "timed out" (network side) to know where to look
- **Confirm names resolve** so replication and backups can find their targets
- **Schedule and verify** backups and maintenance so the database is protected
  and stays healthy over time

Networking is where you diagnose downtime. Scheduling is where you do the routine
work that prevents downtime. Master both, and you can handle the two most common
kinds of database operations work.

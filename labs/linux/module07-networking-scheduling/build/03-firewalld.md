# Build 03: The Firewall (firewalld)

You will learn how to see what the firewall allows. You will open the PostgreSQL
port so remote clients can connect. You will also make the change survive a
reboot. A closed firewall port is one of the two most common reasons a remote
client cannot reach a database. The other is `listen_addresses`, from the
previous guide.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. What a firewall does

A firewall decides which network traffic gets in and which is blocked. Even if
PostgreSQL is listening on `0.0.0.0:5432`, the firewall can still refuse the
connection before it reaches PostgreSQL. On CentOS Stream 9 a service called
`firewalld` manages the firewall. You control it with the `firewall-cmd` command.

> **Concept - Default Deny:** A well-set-up firewall blocks everything except the
> traffic you clearly allow. That is why SSH (port 22) works right away. The base
> rules permit it. PostgreSQL (port 5432) does not work until you add a rule for
> it. "Deny by default, allow on purpose" is the safe way to run a server.

---

## 2. Is the firewall even running?

On a minimal CentOS Stream 9 image, `firewalld` is not installed by default.
Install it first. This runs as `ec2-user` with `sudo`:

```bash
sudo dnf install -y firewalld
```

- `firewalld` is the package that provides both the firewall service and the
  `firewall-cmd` command.

Now enable the service so it starts on boot and start it right now:

```bash
sudo systemctl enable --now firewalld
```

- `enable` - start the service automatically on every boot
- `--now` - also start it immediately, without waiting for a reboot

Nothing prints on success. Check the firewalld service status:

```bash
sudo systemctl status firewalld
```

- `systemctl status` - report the state of a service
- `firewalld` - the firewall service

```
Expected output (yours will differ):
● firewalld.service - firewalld - dynamic firewall daemon
     Loaded: loaded (/usr/lib/systemd/system/firewalld.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-07-08 19:21:22 UTC; 9s ago
       Docs: man:firewalld(1)
   Main PID: 7566 (firewalld)
```

Look for `Active: active (running)`. If it says `inactive (dead)`, the firewall
is not enforcing anything. In that case your connection problem is somewhere
else. Press `q` to exit the status view.

---

## 3. firewall-cmd --list-all - See the current rules

This shows every rule in the active zone.

```bash
sudo firewall-cmd --list-all
```

```
Expected output (yours will differ):
public (active)
  target: default
  icmp-block-inversion: no
  interfaces: eth0
  sources:
  services: cockpit dhcpv6-client ssh
  ports:
  protocols:
  forward: yes
  masquerade: no
  ...
```

Read the important lines:

- `public (active)` - the active zone is named `public`. A zone is a named set of
  rules applied to one or more interfaces
- `services: ... ssh` - SSH is allowed. That is why your connection works
- `ports:` - empty. No extra ports are open, so port 5432 is blocked right now

> **Concept - Zones:** firewalld groups rules into zones. Most single servers use
> the `public` zone for their main interface. You do not need to create zones for
> this course. Just know this: when you add a rule, it goes into the active zone
> unless you say otherwise.

---

## 4. Open port 5432 for PostgreSQL

Add a rule that allows TCP traffic on port 5432. Use `--permanent` so the rule
survives a reboot:

```bash
sudo firewall-cmd --add-port=5432/tcp --permanent
```

- `--add-port=5432/tcp` - allow incoming TCP traffic on port 5432
- `--permanent` - write the rule to disk so it persists across reboots and
  service restarts

```
Expected output (yours will differ):
success
```

> **Concept - Permanent vs Runtime:** firewalld keeps two rule sets. The
> **runtime** set is live right now, but it is lost on reboot. The **permanent**
> set is saved to disk. `--permanent` writes to disk but does **not** apply the
> rule right away. This confuses a lot of people. You add a permanent rule, test
> it, and it does not work yet. You must reload to turn it on.

---

## 5. --reload - Activate the change

Apply the permanent rules to the running firewall:

```bash
sudo firewall-cmd --reload
```

`--reload` re-reads the permanent rules and makes them live. Your open port is
now active.

```
Expected output (yours will differ):
success
```

Confirm the port is now open:

```bash
sudo firewall-cmd --list-ports
```

`--list-ports` shows just the open ports in the active zone.

```
Expected output (yours will differ):
5432/tcp
```

Port 5432 is now open. A remote client can reach PostgreSQL, but only if two more
things are true. PostgreSQL must listen on a reachable address (see the previous
guide). And `pg_hba.conf` must permit the client.

> **DBA Context - The Three Gates:** For a remote client to connect to
> PostgreSQL, three gates must all be open. (1) PostgreSQL listens on a reachable
> address (`listen_addresses`). (2) The firewall allows the port (`firewall-cmd`).
> (3) `pg_hba.conf` authorizes the client. When you debug "connection refused" or
> "timed out", check all three. Forgetting the firewall is the classic mistake.

---

## 6. Closing a port

To reverse the change, remove the port the same way you added it, then reload:

```bash
sudo firewall-cmd --remove-port=5432/tcp --permanent
```

```bash
sudo firewall-cmd --reload
```

`--remove-port` deletes the rule from the permanent set. Then `--reload` applies
the removal. Closing a port cleanly matters just as much as opening one. You
never want more ports open than the job needs.

> **DBA Context - Least Exposure:** Open only the ports a server truly needs. A
> database server that only serves an internal app should not have 5432 open to
> the whole internet. In production you also limit rules to specific source IPs
> instead of allowing everyone. Keeping the exposed surface small is a core part
> of database security.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a firewall does and why SSH works but 5432 does not by default
- [ ] Check whether firewalld is running with `sudo systemctl status firewalld`
- [ ] List all current rules with `sudo firewall-cmd --list-all`
- [ ] Explain what a zone is
- [ ] Open port 5432 with `--add-port=5432/tcp --permanent`
- [ ] Explain the difference between permanent and runtime rules
- [ ] Activate a permanent rule with `--reload`
- [ ] Confirm the open port with `--list-ports`
- [ ] Close a port with `--remove-port` and `--reload`
- [ ] Name the three gates a remote client must pass to reach PostgreSQL

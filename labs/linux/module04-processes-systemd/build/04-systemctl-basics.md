# Build 04: systemctl Basics

On a modern Linux server, long-running programs are managed as services. This
includes databases, web servers, and SSH. The tool that runs them is called
systemd. You control every service with one command: `systemctl`.

Starting, stopping, restarting, and checking a database service is a DBA's most
common daily task. This guide teaches that skill with a real service.

**Time estimate:** 60 minutes

All steps run on your lab server. Connect with SSH first.

**Note on sudo:** Some commands change a service. This includes start, stop,
restart, enable, and disable. Those need root, so we run them with `sudo`. You
run them as **ec2-user** with `sudo` - do NOT switch to another user. Read-only
commands like `status`, `is-active`, and `is-enabled` usually work without
`sudo`.

---

## 1. What is a service?

A service (also called a unit) is a background program. systemd starts it,
stops it, and keeps it running for you.

You do not have to launch a program by hand and watch over it. Instead, you
hand it to systemd. systemd starts it at boot, restarts it if it crashes, and
collects its logs.

We will practice on a service that is already on your server: `chronyd`, the
time-sync service. It is safe to stop and start, so it is perfect for learning.
Everything you learn here works the same way for `postgresql` on a real
database server.

> **Concept - systemd and Units:** systemd is the init system on CentOS Stream
> 9. It is PID 1, the very first process the kernel starts, and the parent of
> everything else. It manages "units". The most common unit type is a
> `.service`. When you type `systemctl start postgresql`, you are asking PID 1
> to launch and watch over the PostgreSQL service.

---

## 2. systemctl status - Is it running?

The most useful `systemctl` command is `status`. It tells you a lot at once:
whether a service is running, whether it starts at boot, its main PID, and
recent log lines.

On **your lab server**, as **ec2-user**:

```bash
systemctl status chronyd
```

`systemctl status <service>` shows a full report on the named service.

```
Expected output (yours will differ):
● chronyd.service - NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chronyd.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-07-08 18:33:12 UTC; 2min 30s ago
       Docs: man:chronyd(8)
             man:chrony.conf(5)
    Process: 611 ExecStart=/usr/sbin/chronyd $OPTIONS (code=exited, status=0/SUCCESS)
   Main PID: 616 (chronyd)
      Tasks: 1 (limit: 10160)
     Memory: 3.5M (peak: 4.1M)
     CGroup: /system.slice/chronyd.service
             └─616 /usr/sbin/chronyd -F 2

Jul 08 18:33:12 localhost systemd[1]: Starting NTP client/server...
Jul 08 18:33:12 localhost chronyd[616]: chronyd version 4.8 starting ...
...
```

Read the key lines:

- The colored dot and first line - the service name and description
- `Loaded:` - whether systemd found the unit file, and whether it is `enabled` (starts at boot) or `disabled`
- `Active:` - the current state. `active (running)` is good; `inactive (dead)` means stopped; `failed` means it crashed
- `Main PID:` - the PID of the main process (you could inspect it with `ps` from Build 01)
- The bottom lines - the most recent log entries for this service

> **DBA Context - status Is Your First Look:** When someone says "the database
> is down", your first command is `systemctl status postgresql`. In one screen
> it tells you if it is running, when it last started, its PID, and the last
> few log lines. Those lines often show the exact error that stopped it.

---

## 3. is-active and is-enabled - Quick yes/no answers

Sometimes you just want a one-word answer. This is handy in scripts. Two
subcommands give you that.

```bash
systemctl is-active chronyd
```

`is-active` prints a single word: `active` if running, `inactive` if stopped,
`failed` if it crashed.

```
Expected output (yours will differ):
active
```

```bash
systemctl is-enabled chronyd
```

`is-enabled` tells you whether the service is set to start automatically at
boot: `enabled` or `disabled`.

```
Expected output (yours will differ):
enabled
```

> **Concept - Running vs Enabled (two separate ideas):** "Active" means it is
> running right now. "Enabled" means it will start on its own at the next boot.
> These two are separate. A service can be running now but disabled - it will
> not come back after a reboot. Or it can be enabled but stopped right now. A
> classic DBA mistake is starting the database by hand, forgetting to enable
> it, then finding after a reboot that the database never came back.

---

## 4. systemctl stop - Stop a service

Now let's stop `chronyd`. This changes the service, so it needs `sudo`.

On **your lab server**, as **ec2-user**:

```bash
sudo systemctl stop chronyd
```

`systemctl stop` asks the service to shut down cleanly. It sends a graceful
signal (SIGTERM, from Build 03) and waits for the service to exit. Nothing
prints on success.

Confirm it stopped:

```bash
systemctl is-active chronyd
```

```
Expected output (yours will differ):
inactive
```

Look at the full status to see the change:

```bash
systemctl status chronyd
```

```
Expected output (yours will differ):
○ chronyd.service - NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chronyd.service; enabled; preset: enabled)
     Active: inactive (dead) since Wed 2026-07-08 18:35:43 UTC; 18ms ago
   Duration: 2min 30.735s
...
Jul 08 18:35:43 ip-172-31-15-28 chronyd[616]: chronyd exiting
Jul 08 18:35:43 ip-172-31-15-28 systemd[1]: Stopping NTP client/server...
Jul 08 18:35:43 ip-172-31-15-28 systemd[1]: chronyd.service: Deactivated successfully.
```

Notice `Active:` now says `inactive (dead)` and the dot changed. Also notice
`Loaded:` still says `enabled`. Stopping a service does NOT disable it. It will
still start at the next boot.

> **DBA Context - Stopping the Database:** `sudo systemctl stop postgresql`
> does a clean shutdown. PostgreSQL finishes transactions, checkpoints, and
> flushes to disk before it exits. This is the right way to take a database
> down for maintenance. It uses the graceful SIGTERM path, not a forced kill.

---

## 5. systemctl start - Start a service

Bring `chronyd` back up.

```bash
sudo systemctl start chronyd
```

`systemctl start` launches the service, and systemd begins watching over it.
Nothing prints on success.

Confirm:

```bash
systemctl is-active chronyd
```

```
Expected output (yours will differ):
active
```

> **DBA Context - Starting the Database:** `sudo systemctl start postgresql`
> brings the database up under systemd's watch. If PostgreSQL fails to start,
> `systemctl status postgresql` and the logs (Build 06) will tell you why.
> Common causes are a bad config setting, wrong data directory permissions, or
> a port already in use.

---

## 6. systemctl restart - Stop then start

`restart` stops the service, then starts it again right away. Use it when a
service needs a full reload, or after certain config changes.

```bash
sudo systemctl restart chronyd
```

This stops `chronyd` (graceful SIGTERM), waits for it to exit, then starts a
fresh copy. Confirm it is back:

```bash
systemctl status chronyd
```

```
Expected output (yours will differ):
● chronyd.service - NTP client/server
     Loaded: loaded (/usr/lib/systemd/system/chronyd.service; enabled; preset: enabled)
     Active: active (running) since Wed 2026-07-08 18:35:43 UTC; 10ms ago
    Process: 4778 ExecStart=/usr/sbin/chronyd $OPTIONS (code=exited, status=0/SUCCESS)
   Main PID: 4783 (chronyd)
...
```

Notice the `Main PID` changed and `Active` shows a fresh start time. That is
proof it was fully restarted.

> **DBA Context - restart vs reload:** `restart` causes downtime. The database
> is unavailable during the stop-start gap, and every connection is dropped.
> Many PostgreSQL settings do NOT need a full restart. They can be applied with
> `reload` (SIGHUP, from Build 03), which keeps the database up. Use
> `systemctl reload postgresql` for reloadable settings. Only use `restart` for
> settings that truly need it (like `shared_buffers`). Never restart a
> production database without a maintenance window.

---

## 7. enable and disable - Control boot behavior

`enable` makes a service start on its own at boot. `disable` stops that.
Neither one starts or stops the service right now. They only affect the next
boot.

Disable `chronyd` from starting at boot:

```bash
sudo systemctl disable chronyd
```

```
Expected output (yours will differ):
Removed "/etc/systemd/system/multi-user.target.wants/chronyd.service".
```

Check that it is now disabled (but still running):

```bash
systemctl is-enabled chronyd
```

```
Expected output (yours will differ):
disabled
```

```bash
systemctl is-active chronyd
```

```
Expected output (yours will differ):
active
```

See - disabled but still active. Now re-enable it so your server is back to
normal:

```bash
sudo systemctl enable chronyd
```

```
Expected output (yours will differ):
Created symlink /etc/systemd/system/multi-user.target.wants/chronyd.service → /usr/lib/systemd/system/chronyd.service.
```

There is also a combined form that enables AND starts in one step:

```bash
sudo systemctl enable --now chronyd
```

The `--now` flag tells `enable` to also start the service right away. And
`disable --now` also stops it.

> **DBA Context - Always Enable the Database:** After you install PostgreSQL,
> run `sudo systemctl enable postgresql` so it survives a reboot. The `--now`
> form - `sudo systemctl enable --now postgresql` - both enables and starts it
> in one command. Forgetting to enable causes real outages. The database works
> until the server reboots, then never comes back on its own.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a systemd service (unit) is and that systemd is PID 1
- [ ] Run `systemctl status <service>` and read Loaded, Active, and Main PID
- [ ] Get a one-word answer with `is-active` and `is-enabled`
- [ ] Explain the difference between "active" (running now) and "enabled" (starts at boot)
- [ ] Stop a service with `sudo systemctl stop`
- [ ] Start a service with `sudo systemctl start`
- [ ] Restart a service with `sudo systemctl restart` and explain restart vs reload
- [ ] Enable and disable boot behavior, and use `enable --now`
- [ ] Explain why you must always enable the database service

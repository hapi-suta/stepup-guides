# Build 05: Reading a Unit File

Behind every service is a plain-text config file called a unit file. It tells
systemd what to run, when to start it, and what to do if it crashes. It holds a
lot more too.

As a DBA you will read these files to see how a database service is set up.
Sometimes you will edit them to change memory limits, restart behavior, or
startup order. This guide teaches you to read a unit file with confidence.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. Where unit files live

There are two important folders, and the difference matters.

- `/usr/lib/systemd/system/` - unit files installed by packages (dnf). These are the "factory defaults". You do NOT edit files here, because a package update will overwrite them.
- `/etc/systemd/system/` - unit files and overrides made by admins (you). Anything here beats the same-named file in `/usr/lib`.

> **Concept - Vendor vs Local (why two folders):** Think of
> `/usr/lib/systemd/system/` as the vendor's shipped copy. Think of
> `/etc/systemd/system/` as your own custom copy. When systemd loads a unit,
> files in `/etc` win. This lets you customize a service without touching the
> vendor file. Your changes then survive package upgrades. This is the same
> "vendor default vs your override" idea you saw with config files in `/etc`
> back in Module 01.

Look at the vendor folder:

```bash
ls /usr/lib/systemd/system/ | grep -E 'chronyd|sshd|postgres'
```

This lists the vendor unit files and keeps only a few names you know (from
Module 01's grep). The `-E` flag turns on extended patterns, so `|` means "or".

```
Expected output (yours will differ):
chronyd-restricted.service
chronyd.service
sshd-keygen@.service
sshd.service
sshd@.service
sshd.socket
...
```

---

## 2. systemctl cat - The right way to read a unit file

You could `cat` the file directly. But the best way is `systemctl cat`. It
shows the exact unit file systemd is really using, including the path and any
overrides, all in one place.

```bash
systemctl cat chronyd
```

`systemctl cat <service>` prints the unit file (or files) in effect for the
service. A comment line shows each file's full path.

```
Expected output (yours will differ):
# /usr/lib/systemd/system/chronyd.service
[Unit]
Description=NTP client/server
Documentation=man:chronyd(8) man:chrony.conf(5)
After=ntpdate.service sntp.service ntpd.service
Conflicts=ntpd.service systemd-timesyncd.service
ConditionCapability=CAP_SYS_TIME

[Service]
Type=forking
PIDFile=/run/chrony/chronyd.pid
EnvironmentFile=-/etc/sysconfig/chronyd
ExecStart=/usr/sbin/chronyd $OPTIONS
...
[Install]
WantedBy=multi-user.target
```

The first line is a comment showing which file this is. There is no override in
`/etc`, so you see just the one vendor file. On CentOS Stream 9 the real
`[Service]` section also has many hardening lines (`ProtectHome=yes`,
`PrivateTmp=yes`, several `CapabilityBoundingSet=` and `Protect...=` entries).
They are trimmed above with `...`. You do not need to memorize them - focus on
`Type`, `ExecStart`, and the section names.

> **DBA Context - cat vs opening the file:** Always use `systemctl cat` instead
> of opening the file by hand. On a real database server, the config in effect
> is often split across a vendor file plus one or more override snippets.
> `systemctl cat` shows you the whole picture and the exact paths. That way you
> never edit the wrong file.

---

## 3. The three sections of a unit file

Every `.service` unit file has up to three sections. Each is marked by a name
in square brackets. Read them from top to bottom.

### [Unit] - identity and ordering

This section describes the service and how it relates to others.

- `Description=` - a human-readable name (this is what `systemctl status` shows)
- `Documentation=` - where to read the manual
- `After=` - start this service AFTER the listed ones (ordering, not a hard requirement)
- `Requires=` - a hard dependency: if the required unit fails, this one will not start
- `Wants=` - a soft dependency: start the wanted unit too, but do not fail if it does not come up

### [Service] - what to run and how

This is the heart of the file. It tells systemd how to run the program.

- `Type=` - how systemd decides the service is "started" (`simple`, `forking`, `notify`, and more)
- `ExecStart=` - the exact command systemd runs to start the service
- `ExecStop=` - an optional command to stop it (if absent, systemd sends SIGTERM)
- `ExecReload=` - the command run on `systemctl reload` (often sends SIGHUP)
- `Restart=` - whether to auto-restart if it exits (`no`, `on-failure`, `always`)
- `User=` and `Group=` - which account the service runs as
- `EnvironmentFile=` - a file of environment variables and options to load

### [Install] - boot behavior

This section is used only by `enable` and `disable`.

- `WantedBy=multi-user.target` - when enabled, start this at the normal multi-user boot stage. This is why `enable` from Build 04 created a symlink under `multi-user.target.wants`.

> **DBA Context - Reading a PostgreSQL Unit:** A PostgreSQL unit file has a few
> tell-tale lines. You will see `User=postgres`, so it runs as the postgres
> account. You will see an `ExecStart=` that points at `pg_ctl` or `postmaster`
> with the data directory. You will see `Type=notify`, which means PostgreSQL
> tells systemd when it is truly ready. And you will often see
> `Restart=on-failure` so the database comes back after a crash. Knowing these
> lines lets you see exactly how your database starts.

---

## 4. Compare two real units

Look at the sshd unit to see the same structure in a different service:

```bash
systemctl cat sshd
```

```
Expected output (yours will differ):
# /usr/lib/systemd/system/sshd.service
[Unit]
Description=OpenSSH server daemon
Documentation=man:sshd(8) man:sshd_config(5)
After=network.target sshd-keygen.target
Wants=sshd-keygen.target

[Service]
Type=notify
EnvironmentFile=-/etc/sysconfig/sshd
ExecStart=/usr/sbin/sshd -D $OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
KillMode=process
Restart=on-failure
RestartSec=42s

[Install]
WantedBy=multi-user.target
```

Notice how much you can now read:

- `After=network.target` - SSH waits until networking is up (it needs the network)
- `ExecReload=/bin/kill -HUP $MAINPID` - reload sends SIGHUP (Build 03) to the main PID, exactly as we discussed
- `Restart=on-failure` - if sshd crashes, systemd restarts it
- `WantedBy=multi-user.target` - it starts at normal boot when enabled

---

## 5. daemon-reload - Tell systemd you changed a unit file

Here is a rule that trips up beginners. If you edit a unit file, systemd does
NOT notice on its own. You must tell it to re-read the files on disk.

```bash
sudo systemctl daemon-reload
```

`daemon-reload` makes systemd re-scan all unit files and rebuild its inner
picture of the system. Run it as **ec2-user** with `sudo`. Nothing prints on
success.

> **Concept - daemon-reload vs reload (two different things):** These sound
> alike but do opposite jobs. `systemctl daemon-reload` reloads systemd's own
> config. It re-reads the unit FILES after you edited them.
> `systemctl reload <service>` tells the RUNNING SERVICE to re-read its own
> config (for PostgreSQL, that is `postgresql.conf`). So: edit a unit file, run
> `daemon-reload`. Change a database setting, run `systemctl reload`.

Here is the correct order when you change a service's unit file:

1. Edit the override (never the vendor file) - see the tip below
2. Run `sudo systemctl daemon-reload` so systemd picks up the change
3. Run `sudo systemctl restart <service>` so the running service uses it

> **DBA Context - The Forgotten daemon-reload:** Here is a very common
> real-world mistake. An engineer edits the PostgreSQL unit file to raise a
> memory limit. They run `systemctl restart postgresql`. Then they are confused
> that nothing changed. The reason is they skipped `daemon-reload`, so systemd
> restarted the service with the OLD unit definition. Always run
> `daemon-reload` after editing a unit file.

---

## 6. The safe way to customize - override files

You should never edit files in `/usr/lib/systemd/system/`. The safe way to
change a service is a drop-in override. `systemctl edit` creates one for you.

```bash
sudo systemctl edit chronyd
```

This opens an editor with an empty override file (it uses your default editor).
Whatever you put here is saved to
`/etc/systemd/system/chronyd.service.d/override.conf`. It takes priority over
the vendor file, which stays untouched.

For now, just close the editor without saving. In vi, press `Esc`, then type
`:q!` and press Enter to quit without saving.

You can then see the override layered on top of the vendor file:

```bash
systemctl cat chronyd
```

If you had saved an override, `systemctl cat` would show both the vendor file
AND your override snippet, in order. That way you see exactly what applies.

> **DBA Context - Overrides for Databases:** In production you raise a
> database's memory limit or change its restart policy with a drop-in override.
> You do not edit the vendor unit. This keeps your change small, visible, and
> safe from package upgrades. After editing: `daemon-reload`, then `restart`.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between `/usr/lib/systemd/system/` (vendor) and `/etc/systemd/system/` (local)
- [ ] Read a unit file with `systemctl cat` and explain why it beats plain `cat`
- [ ] Identify the `[Unit]`, `[Service]`, and `[Install]` sections
- [ ] Explain `ExecStart`, `Restart`, `User`, `After`, and `WantedBy`
- [ ] Explain what `ExecReload=/bin/kill -HUP $MAINPID` does
- [ ] Run `sudo systemctl daemon-reload` and explain when it is needed
- [ ] Explain the difference between `daemon-reload` and `systemctl reload`
- [ ] Explain why you use `systemctl edit` overrides instead of editing vendor files

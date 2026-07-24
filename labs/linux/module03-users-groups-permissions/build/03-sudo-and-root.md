# Build 03: sudo and root

In this guide you will learn a few things. First, the difference between the
all-powerful root account and a regular user. Then how to run one command as
root with `sudo`, and how to run a command as another user with `sudo -u`. You
will also learn how to switch into another user's shell with `su -`, plus the
basics of the `/etc/sudoers` file.

This is core DBA knowledge. You rarely act as root directly. But you use `sudo`
all the time to manage services and to become the `postgres` user.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first as `ec2-user`.

---

## 1. root vs a regular user

The `root` user (UID 0) is the administrator of the whole server. It can read,
write, and delete any file. It can stop any program and change any setting.
There is no safety net. One mistyped command as root can destroy the system.

`ec2-user` is a regular user. It can only touch its own files, plus anything it
has been given access to. If you try to do something that needs root, you get
"permission denied".

See this for yourself. Try to read a root-only file as `ec2-user`:

```bash
cat /etc/shadow
```

`/etc/shadow` holds the scrambled passwords for every account. Only root can
read it.

```
Expected output (yours will differ):
cat: /etc/shadow: Permission denied
```

You are blocked. This is Linux protecting the system from a regular user.

> **Concept - Least Privilege:** The rule is simple. Use the least power needed
> to do the job. You log in as a regular user. You only step up to root for the
> one command that needs it. This limits the damage from a mistake or a hacked
> account. Databases follow the same rule. PostgreSQL runs as the low-power
> `postgres` user, never as root.

---

## 2. Running one command as root with sudo

`sudo` (short for "superuser do") runs one command as root. Then it drops you
right back to your normal user. This is the safe, everyday way to do admin
work.

Read the same protected file, but this time with `sudo`:

```bash
sudo cat /etc/shadow
```

You put `sudo` in front of the command you want to run as root. The first time
you use `sudo` in a session, it may ask for YOUR password. Not root's password.

```
Expected output (yours will differ):
root:!!:20640:0:99999:7:::
bin:*:19760:0:99999:7:::
daemon:*:19760:0:99999:7:::
...
ec2-user:!!:20642:0:99999:7:::
```

It worked. You read a root-only file, and you never became root for good.

Confirm you are still `ec2-user`:

```bash
whoami
```

```
Expected output (yours will differ):
ec2-user
```

You never turned into root. `sudo` gave root power to just that one command.

> **DBA Context - sudo systemctl:** As a DBA you will run commands like
> `sudo systemctl restart postgresql-16` all day long. These control system
> services, and they need root. One thing to note: `sudo systemctl ...` runs as
> `ec2-user` with extra rights. You do NOT switch to the `postgres` user to run
> systemctl. Managing the service is a root job. Running SQL is a postgres job.

---

## 3. Running a command AS another user with sudo -u

Sometimes you do not want root. You want to run a command as one specific
other user, most often `postgres`. The `-u` flag tells `sudo` which user to
become.

First create a demo user to target:

```bash
sudo useradd -m -s /bin/bash demo
```

Now run a command as `demo` without knowing `demo`'s password:

```bash
sudo -u demo whoami
```

`sudo -u demo` runs the command that follows it as the `demo` user. Here
`whoami` confirms which user actually ran it.

```
Expected output (yours will differ):
demo
```

The `whoami` ran as `demo`, even though you started it as `ec2-user`. This is
very handy for a DBA. It lets you run one quick command as `postgres` without
opening a whole new shell.

> **DBA Context - One-Off postgres Commands:** You will sometimes see people
> write `sudo -u postgres psql` to jump straight into the database as the
> postgres user. In these guides we do NOT chain it that way for beginners.
> Instead we switch users first (next section), then run the command in a
> separate step. Learn `sudo -u` so you can read other people's scripts. But
> use the clear two-step approach when you write your own.

---

## 4. Switching into another user's shell with su -

`su` (short for "substitute user") opens a whole new shell as another user.
Everything you type stays as that user until you `exit`. Use this when you have
several commands to run as one user.

Switch into a full root shell:

```bash
sudo su -
```

Breaking this down:

- `sudo` - approve the switch using your own rights
- `su` - substitute user (defaults to root when you name no user)
- `-` - the important dash. It loads the target user's full login environment,
  meaning their `PATH`, home directory, and shell settings

Your prompt changes from `$` to `#`. The `#` is the standard sign that you are
now root.

```
Expected output (yours will differ):
[root@ip-10-0-1-50 ~]#
```

Confirm who you are:

```bash
whoami
```

```
Expected output (yours will differ):
root
```

Now leave the root shell and return to `ec2-user`:

```bash
exit
```

Your prompt returns to `$`. Always `exit` as soon as you are done as root. Do
not leave a root shell sitting open.

### Switching to the postgres user

This same pattern is how a DBA becomes the `postgres` user. You will do this a
lot in later modules. It only works once PostgreSQL is installed, because the
installer is what creates the `postgres` account. If PostgreSQL is not installed
yet on your lab server, this command prints `su: user postgres does not exist`.
That is expected on a bare server. Read this section for the pattern and you
will practice it for real in Build 06 and later modules.

Switch to `postgres`:

```bash
sudo su - postgres
```

Naming `postgres` after `su -` starts a login shell as the `postgres` user,
not root. Your prompt changes to show you are now `postgres`.

```
Expected output (yours will differ):
[postgres@ip-10-0-1-50 ~]$
```

Confirm:

```bash
whoami
```

```
Expected output (yours will differ):
postgres
```

Then exit back to `ec2-user`:

```bash
exit
```

> **Concept - Why the Dash Matters:** `su - postgres` (with the dash) gives you
> postgres's real login environment. That includes the correct `PATH`, which
> finds `psql` and `pg_ctl`. `su postgres` (no dash) keeps YOUR environment.
> Your environment often does not include the PostgreSQL programs, so you get
> "command not found" errors. Always use the dash. This is why every guide
> shows `sudo su - postgres`.

---

## 5. The /etc/sudoers file (basics)

How does the system decide who is allowed to run `sudo`? The answer lives in
`/etc/sudoers` and the extra files under `/etc/sudoers.d/`.

Never edit these files with a normal text editor. Use `visudo` instead. It
checks your changes for mistakes before saving. A broken sudoers file can lock
everyone out of `sudo`.

View the rules safely with `visudo` in check mode:

```bash
sudo visudo -c
```

`-c` means "check". It tests the current file without opening an editor.

```
Expected output (yours will differ):
/etc/sudoers: parsed OK
/etc/sudoers.d/90-cloud-init-users: parsed OK
```

Look at the key line that grants access to the `wheel` group:

```bash
sudo grep wheel /etc/sudoers
```

```
Expected output (yours will differ):
## Allows people in group wheel to run all commands
%wheel	ALL=(ALL)	ALL
# %wheel	ALL=(ALL)	NOPASSWD: ALL
```

The second line is commented out (it starts with `#`), so it is not active. It
shows the alternative "no password" form that some servers enable.

Reading `%wheel ALL=(ALL) ALL`:

- `%wheel` - the `%` means this rule applies to a GROUP named `wheel`
- `ALL=(ALL)` - on ALL hosts, may run as ALL users
- `ALL` - may run ALL commands

This one line is why adding a user to the `wheel` group (Build 02) gives them
`sudo`.

### Granting narrow sudo access (read-only walkthrough)

In the real world you often let a user run only certain commands. For example,
you might let an on-call engineer restart PostgreSQL but do nothing else. A
sudoers file would contain a line like this:

```
oncall  ALL=(ALL)  /usr/bin/systemctl restart postgresql-16, /usr/bin/systemctl status postgresql-16
```

That lets `oncall` restart PostgreSQL and check its status through `sudo`, and
nothing more. We are only reading and explaining this. Do not add it on the lab
server.

> **DBA Context - Scoped sudo:** Production servers rarely give DBAs full root.
> Instead, security teams write narrow sudoers rules. For example: restart the
> DB service, read the logs, run `pg_ctl reload`, and nothing else. Knowing how
> to read a sudoers line tells you exactly what you can and cannot do on a
> locked-down server.

---

## 6. Why you should not log in as root

You can log in directly as root, but you should not. Here is why.

| Risk of using root directly | How sudo fixes it |
|-----------------------------|-------------------|
| No audit trail - you cannot tell who did what | `sudo` logs every command with the real user's name |
| One typo can destroy the whole system | You elevate only for the specific command that needs it |
| A leaked root password compromises everything | Each admin uses their own account; you disable root login |
| Everyone shares one root password | Access is granted per-user via `wheel` group membership |

Check the sudo audit log to see this in action:

```bash
sudo grep sudo /var/log/secure | tail -n 5
```

`grep sudo` finds the sudo entries. `tail -n 5` shows only the last five lines,
so the output stays short.

```
Expected output (yours will differ):
Jul  8 18:35:42 ip-172-31-8-187 sudo[4895]: ec2-user : PWD=/home/ec2-user ; USER=root ; COMMAND=/bin/cat /etc/shadow
Jul  8 18:35:42 ip-172-31-8-187 sudo[4895]: pam_unix(sudo:session): session opened for user root(uid=0) by ec2-user(uid=1000)
Jul  8 18:35:42 ip-172-31-8-187 sudo[4895]: pam_unix(sudo:session): session closed for user root
...
```

Every `sudo` command is logged with WHO ran it and WHAT they ran. The
`COMMAND=` line names the exact command; the `pam_unix` lines record when the
elevated session opened and closed. If everyone
logged in as root, that record would vanish. Now clean up the demo user:

```bash
sudo userdel -r demo
```

> **DBA Context - Accountability:** After something breaks, the first question
> is often "who changed what, and when?" The `sudo` audit log answers that.
> Direct root logins erase the answer. On any server you manage, turn off
> direct root SSH login. Make everyone use their own account with `sudo`.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain the difference between root and a regular user
- [ ] Explain the principle of least privilege
- [ ] Use `sudo` to run a single command as root and confirm you are still `ec2-user` afterward
- [ ] Use `sudo -u USER` to run a command as another user
- [ ] Use `sudo su -` to open a root shell and `exit` back
- [ ] Use `sudo su - postgres` to become the postgres user and explain why the dash matters
- [ ] Explain what `%wheel ALL=(ALL) ALL` in `/etc/sudoers` means
- [ ] Explain why you validate sudoers changes with `visudo -c`
- [ ] Give at least two reasons not to log in directly as root
- [ ] Find who ran a `sudo` command in `/var/log/secure`

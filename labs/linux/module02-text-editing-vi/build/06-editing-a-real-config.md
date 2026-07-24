# Build 06: Editing a Real Config File

You will put every skill from this module together to do a real DBA task. You
will open a live config file, make a safe change, save it, and check that the
change took. This is the same workflow you will use on the job. So we do it the
careful, professional way: back up first, edit, then verify.

**Time estimate:** 50 minutes

All steps run on your lab server. Connect with SSH first.

---

## 1. The professional workflow

Before touching any config, a good DBA follows the same three steps every time:

1. **Back up** the file so you can restore it if the change breaks something.
2. **Edit** the file with vi.
3. **Verify** the change is exactly what you intended before relying on it.

We will do all three on `sshd_config`. That is the SSH server's config file. It
is a safe, real file to practice on. We will only add a comment line. So even
if something goes wrong, SSH keeps working.

> **DBA Context - Why the Backup Step Is Not Optional:** Most locked-out servers
> and databases that will not start come from one thing: a config edit gone
> wrong. A one-second backup gives you a one-second recovery. Every experienced
> DBA copies the file before editing it. Skipping the backup is how a small
> mistake turns into a 3 a.m. incident.

---

## 2. Look at the file first (as ec2-user)

On your lab server, as **ec2-user**, look at the top of the SSH config so you
know what you are working with:

```bash
sudo head -20 /etc/ssh/sshd_config
```

`sudo` runs the command as the root user. You need root here because
`/etc/ssh/sshd_config` is owned by root. `head -20` prints the first 20 lines.

```
Expected output (yours will differ):
#	$OpenBSD: sshd_config,v 1.104 2021/07/02 05:11:21 dtucker Exp $

# This is the sshd server system-wide configuration file.  See
# sshd_config(5) for more information.
...
Include /etc/ssh/sshd_config.d/*.conf
```

Files under `/etc` almost always need root to edit. That is why every command
in this guide uses `sudo`.

---

## 3. Back up the file (as ec2-user)

Still as **ec2-user**, make a timestamped backup copy:

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak-2026-07-08
```

`sudo cp` copies the file as root. The new name ends in `.bak-2026-07-08`, so
you know it is a backup and when you made it. Use today's date. If the edit
goes wrong, you restore it with a single `sudo cp` in reverse.

Confirm the backup exists:

```bash
sudo ls -l /etc/ssh/sshd_config.bak-2026-07-08
```

`ls -l` lists the file in long format so you can see it is really there.

```
Expected output (yours will differ):
-rw-------. 1 root root 3674 Jul  8 14:10 /etc/ssh/sshd_config.bak-2026-07-08
```

---

## 4. Open the file in vi (as ec2-user with sudo)

Open the real config as root:

```bash
sudo vi /etc/ssh/sshd_config
```

`sudo vi` opens the file as root, so you are allowed to save changes to it. You
land in command mode at line 1.

This is a live system file, so take your time. Think before you type. And
remember your escape hatch: press `Esc`, then `:q!`, any time you want to quit
without saving.

---

## 5. Find the setting you care about

You are going to document a setting by adding a comment above it. First, find
the setting. Search for the `PermitRootLogin` line:

```
/PermitRootLogin
```

- `/` starts a forward search
- `PermitRootLogin` is the pattern
- press Enter to jump to it

The cursor lands on the line:

```
Expected output (yours will differ):
#PermitRootLogin prohibit-password
```

If there is more than one match, press `n` to check each one. Make sure you land
on the setting line, not a match buried in a comment paragraph.

---

## 6. Make the safe change: add a comment above the setting

You will add a dated comment line above the setting to explain a decision. This
is a real DBA habit. A good config explains itself.

Put the cursor on the `PermitRootLogin` line. Then press capital `O`. This opens
a new line **above** it and puts you in insert mode:

```
O
```

Now type the comment line:

```
# Reviewed 2026-07-08 by SUTA Labs student - root login stays disabled
```

Press `Esc` to return to command mode. The `-- INSERT --` marker at the bottom
disappears, confirming you are back in command mode.

Your two lines now read:

```
Expected output (yours will differ):
# Reviewed 2026-07-08 by SUTA Labs student - root login stays disabled
#PermitRootLogin prohibit-password
```

You only added a comment. You did not change any real setting, so SSH behaves
exactly as before. This is the safest possible edit to practice on a live file.

---

## 7. Save the change

Save and quit with `:wq`:

```
:wq
```

`:w` writes the file to disk as root; `q` quits. vim confirms the write at the
bottom:

```
Expected output (yours will differ):
"/etc/ssh/sshd_config" 131L, 3745B written
```

If instead you see `E45: 'readonly' option is set`, you opened the file without
`sudo`. Quit with `:q!`, then reopen with `sudo vi` as in Step 4.

---

## 8. Verify the change (as ec2-user)

Never trust that an edit worked. Always verify it. Still as **ec2-user**, use
`grep` to pull out your comment and the setting:

```bash
sudo grep -n -A1 "Reviewed 2026-07-08" /etc/ssh/sshd_config
```

Breaking down the flags:

- `grep` searches a file for a pattern
- `-n` shows the line number of each match
- `-A1` also prints 1 line **A**fter each match (so you see the setting under
  your comment)
- `"Reviewed 2026-07-08"` is the text to find

```
Expected output (yours will differ):
40:# Reviewed 2026-07-08 by SUTA Labs student - root login stays disabled
41:#PermitRootLogin prohibit-password
```

Your comment sits on the line right above the setting, just as you planned. The
change is confirmed.

---

## 9. Validate the config is still syntactically correct

SSH comes with a built-in checker that confirms the file is still valid. If a
config has a checker, always run it after you edit:

```bash
sudo sshd -t
```

`sshd -t` tells the SSH daemon to **t**est its config file and report any
errors. It does not start or restart anything. No output means the file is
valid.

```
Expected output (yours will differ):
```

(An empty result is success - `sshd -t` only prints something when there is a
problem.)

> **DBA Context - Validate Before You Reload:** PostgreSQL has similar checks.
> After editing `postgresql.conf`, you can run `SELECT pg_reload_conf();` or
> read the logs after a reload. After editing `pg_hba.conf`, a reload logs any
> syntax errors. The rule is the same everywhere: edit, validate, then apply.
> Never reload a service on a config you have not validated. A single syntax
> error can take the whole service down.

---

## 10. Clean up the backup (optional)

Once you are sure the change is good, you can remove the backup. On a real
production server you would often keep backups for a while. But for this lab you
can tidy up. Still as **ec2-user**:

```bash
sudo rm /etc/ssh/sshd_config.bak-2026-07-08
```

`sudo rm` removes the file as root. Only do this once you are sure the edit is
correct. If you have any doubt, leave the backup in place. Disk space is cheap,
and recovery is priceless.

---

## 11. The full workflow, recapped

You just performed the complete DBA config-editing loop:

| Step | Command | Purpose |
|------|---------|---------|
| Inspect | `sudo head -20 /etc/ssh/sshd_config` | Know what you are editing |
| Back up | `sudo cp ... ...bak-DATE` | Safety net for recovery |
| Edit | `sudo vi /etc/ssh/sshd_config` | Make the change |
| Find | `/PermitRootLogin` | Locate the setting |
| Change | `O` then type, then `Esc` | Add a documented comment |
| Save | `:wq` | Write to disk |
| Verify | `sudo grep -n -A1 ...` | Confirm the change landed |
| Validate | `sudo sshd -t` | Confirm the file is still valid |

This same loop works for `postgresql.conf`, `pg_hba.conf`, systemd unit files,
and every other config you will edit as a DBA. The tool is vi. The discipline
is: inspect, back up, edit, verify, validate.

---

## Checkpoint

Before finishing this module, confirm you can do all of the following:

- [ ] Explain the inspect / back up / edit / verify / validate workflow
- [ ] Make a timestamped backup of a config file with `sudo cp`
- [ ] Open a root-owned config file for editing with `sudo vi`
- [ ] Search for a setting inside the file with `/pattern`
- [ ] Add a comment line above a setting using `O`, then `Esc`
- [ ] Save the change with `:wq` and recognize the write confirmation
- [ ] Verify the change with `sudo grep -n -A1`
- [ ] Validate the SSH config with `sudo sshd -t`
- [ ] Explain why you never reload a service on an unvalidated config

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing. Congratulations - you can now edit config files on
any Linux server with vi.

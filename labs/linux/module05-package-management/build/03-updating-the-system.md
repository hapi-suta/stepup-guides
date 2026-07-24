# Build 03: Updating the System

In this guide you will learn to check for updates with `dnf check-update` and
apply them with `sudo dnf update`. You will see how `upgrade` relates to
`update`, how to apply security-only updates, and why patching matters. As a
DBA, keeping the system patched is a core part of protecting the database.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - Why patching matters

All software has bugs, and some bugs are security holes. Vendors release fixes
as package updates. Applying those updates is called "patching." Patching
closes the holes and fixes bugs before someone can exploit them.

A database server is a high-value target, because it holds the data. Say there
is an unpatched security flaw in OpenSSL, the kernel, or PostgreSQL itself. It
can let an attacker in or crash the service. Part of a DBA's job is keeping the
box patched. You also schedule those updates carefully, so the database is not
disrupted at a bad time.

---

## 1. dnf check-update - See what updates are available

`dnf check-update` lists packages that have a newer version available. It does
NOT install anything. It only reports. Because it only reads, it does not need
`sudo`.

On **your lab server**, as **ec2-user**:

```bash
dnf check-update
```

- `dnf` - the package manager
- `check-update` - list available updates without installing them

```
Expected output (yours will differ):
Last metadata expiration check: 0:03:11 ago on Wed 08 Jul 2026 02:40:55 PM UTC.

curl.x86_64                    7.76.1-31.el9        baseos
kernel.x86_64                  5.14.0-503.el9       baseos
openssl.x86_64                 1:3.2.2-6.el9        appstream
sudo.x86_64                    1.9.5p2-10.el9       appstream
...
```

Each line shows a package with a newer version available, and the repository it
would come from. If nothing needs updating, the command prints no list. It
simply returns you to the prompt.

> **DBA Context - Check Before You Change:** Before any maintenance window,
> `dnf check-update` tells you exactly what would change. You review the list.
> Watch for anything touching the kernel, glibc, openssl, or postgresql. Then
> plan the update around your database's availability needs.

---

## 2. sudo dnf update - Apply the updates

`sudo dnf update` downloads and installs the newer versions of all packages
that have them. It needs `sudo` because it changes system files.

Run it without `-y` so you can review the transaction first:

```bash
sudo dnf update
```

`dnf` works out the dependencies. Then it shows a full summary of everything it
will upgrade, and asks you to confirm:

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package        Architecture   Version           Repository     Size
========================================================================
Upgrading:
 curl           x86_64         7.76.1-31.el9     baseos        302 k
 openssl        x86_64         1:3.2.2-6.el9     appstream     1.1 M
 sudo           x86_64         1.9.5p2-10.el9    appstream     1.0 M
...
Transaction Summary
========================================================================
Upgrade  14 Packages

Total download size: 92 M
Is this ok [y/N]:
```

Read the summary. Check whether the `kernel` is in the list. A kernel update
needs a reboot to take effect. Type `y` to go ahead:

```
Expected output (yours will differ):
Downloading Packages:
...
Upgraded:
  curl-7.76.1-31.el9.x86_64    openssl-1:3.2.2-6.el9.x86_64
  sudo-1.9.5p2-10.el9.x86_64   ...
Complete!
```

> **DBA Context - Never Blind-Update Production:** On a production database
> host, you do NOT just run `sudo dnf update -y`. You review the list. You
> schedule a maintenance window. You take a backup first. And you check whether
> a reboot is required, for example after a kernel update. An unplanned reboot
> in the middle of the day takes the database offline.

---

## 3. update vs upgrade - What is the difference?

You will see both `dnf update` and `dnf upgrade` in guides online. On modern
`dnf`, they do the same thing. `upgrade` is just another name for `update`.
Both bring your installed packages up to their newest version.

```bash
sudo dnf upgrade
```

If your system is already up to date after Step 2, you will see:

```
Expected output (yours will differ):
Last metadata expiration check: 0:05:02 ago on Wed 08 Jul 2026 02:46:10 PM UTC.
Dependencies resolved.
Nothing to do.
Complete!
```

`Nothing to do.` means everything is already current. On older `yum`-based
systems, `update` and `upgrade` behaved a little differently. But on CentOS
Stream 9 with `dnf`, you can treat them as the same command.

---

## 4. Security updates only

Sometimes you want to apply only the updates that fix security problems, and
leave everything else alone. This limits change on a sensitive server. Use the
`--security` flag.

First, list which security updates are pending:

```bash
dnf check-update --security
```

```
Expected output (yours will differ):
Last metadata expiration check: 0:06:33 ago on Wed 08 Jul 2026 02:47:44 PM UTC.

openssl.x86_64                 1:3.2.2-6.el9        appstream
kernel.x86_64                  5.14.0-503.el9       baseos
```

Now apply only the security updates:

```bash
sudo dnf update --security
```

- `--security` - restrict the update to packages that fix security advisories

This installs the smallest set of changes needed to close known security
holes. It does not upgrade everything else on the box.

> **DBA Context - Security Patching Cadence:** Many teams apply full updates on
> a monthly maintenance window. But they apply critical security updates as
> soon as they are released. `dnf update --security` lets you patch the urgent
> holes without the churn of a full system upgrade. That keeps the database
> more stable between windows.

---

## 5. Updating a single package

You do not have to update everything at once. To update just one package, name
it after `update`:

```bash
sudo dnf update openssl
```

This upgrades `openssl` and only what it depends on. It leaves the rest of the
system unchanged. This helps when you need one specific fix and want to keep
change on a database server to a minimum.

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package        Architecture   Version           Repository     Size
========================================================================
Upgrading:
 openssl        x86_64         1:3.2.2-6.el9     appstream     1.1 M
 openssl-libs   x86_64         1:3.2.2-6.el9     appstream     2.4 M
...
Is this ok [y/N]:
```

---

## 6. Do I need to reboot?

Most package updates take effect right away. Two things need a reboot to fully
apply: a **kernel** update and, in some cases, core system libraries like
`glibc`. CentOS gives you a helper to tell you whether a reboot is needed.

Install the helper:

```bash
sudo dnf install -y dnf-utils
```

Now check whether a reboot is required:

```bash
sudo needs-restarting -r
```

- `-r` - report only whether a full reboot is required

```
Expected output (yours will differ):
Core libraries or services have been updated since boot-up:
  * kernel

Reboot is required to fully utilize these updates.
```

Does it say a reboot is required? On a database server, you schedule that
reboot during a maintenance window. Never in the middle of business hours.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain why patching matters for a database server
- [ ] Use `dnf check-update` to list available updates without installing them
- [ ] Explain why `check-update` does not need `sudo` but `update` does
- [ ] Apply updates with `sudo dnf update` and review the summary before confirming
- [ ] Explain that `dnf upgrade` and `dnf update` are the same on CentOS Stream 9
- [ ] Use `dnf update --security` to apply only security updates
- [ ] Update a single named package instead of the whole system
- [ ] Use `needs-restarting -r` to check whether a reboot is required
- [ ] Explain why you never blind-update a production database host with `-y`

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.

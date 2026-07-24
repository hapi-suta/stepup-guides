# Build 02: Installing and Removing Packages

In this guide you will learn to install software with `sudo dnf install` and
remove it with `sudo dnf remove`. You will learn what the `-y` flag does and
when NOT to use it. You will also see how `dnf` handles dependencies for you.
As a DBA, this is the core skill for getting PostgreSQL and its tools onto a
server.

**Time estimate:** 45 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - Why installing needs sudo

Searching for packages (Build 01) did not change the system. So it did not need
special permissions. Installing and removing software is different. It changes
files across the whole server. That needs administrator (root) power. You get
that power by putting `sudo` in front of the command.

`sudo` means "do this one command as the superuser (root)." You stay logged in
as `ec2-user`. But `dnf` runs with root power just for that one command. The
first time you use `sudo` in a session, it may ask for your password.

---

## 1. sudo dnf install - Install a package

Let's install `htop`, a friendly process viewer. On **your lab server**, as
**ec2-user**:

```bash
sudo dnf install htop
```

- `sudo` - run this command as root
- `dnf install` - the sub-command that installs a package
- `htop` - the package to install

`dnf` prints a summary of what it will do. Then it asks you to confirm:

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package        Architecture   Version         Repository       Size
========================================================================
Installing:
 htop           x86_64         3.2.1-1.el9     epel            179 k

Transaction Summary
========================================================================
Install  1 Package

Total download size: 179 k
Installed size: 384 k
Is this ok [y/N]:
```

Read the summary. It lists exactly what will be installed and how much it will
download. This is your chance to check before anything changes. Type `y` and
press Enter to go ahead:

```
Expected output (yours will differ):
Downloading Packages:
htop-3.2.1-1.el9.x86_64.rpm                     1.2 MB/s | 179 kB     00:00
...
Installed:
  htop-3.2.1-1.el9.x86_64

Complete!
```

The word `Complete!` means it worked. Now confirm the command is available:

```bash
which htop
```

```
Expected output (yours will differ):
/usr/bin/htop
```

---

## 2. Dependencies - dnf handles them for you

Most software needs other software to run. Those requirements are called
**dependencies**. When you install a package, `dnf` works out everything it
depends on and installs those too. You do not have to track them by hand.

Let's install a package that pulls in dependencies. `git` needs several
supporting libraries:

```bash
sudo dnf install git
```

Look at the summary. It lists more than just `git`:

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package             Architecture  Version          Repository     Size
========================================================================
Installing:
 git                 x86_64        2.43.5-1.el9     appstream     53 k
Installing dependencies:
 git-core            x86_64        2.43.5-1.el9     appstream    4.4 M
 git-core-doc        noarch        2.43.5-1.el9     appstream    2.9 M
 perl-Git            noarch        2.43.5-1.el9     appstream     37 k
...
Transaction Summary
========================================================================
Install  10 Packages
```

The `Installing dependencies:` section shows the extra packages `dnf` pulled in
for you. Type `y` to continue.

> **Concept - Dependency Resolution:** Before doing anything, `dnf` builds a
> plan. It reads what your package needs. Then it reads what those needs need,
> all the way down. This is called dependency resolution. If it cannot meet a
> requirement, it stops and tells you, without changing the system. This is why
> installing PostgreSQL with one command also brings in the exact libraries it
> needs.

---

## 3. The -y flag - and when NOT to use it

The `-y` flag answers "yes" for you at the confirmation prompt. So the install
runs without stopping to ask. This is handy in scripts, where no human is
watching.

```bash
sudo dnf install -y tree
```

- `-y` - assume "yes" to all prompts

```
Expected output (yours will differ):
Dependencies resolved.
...
Installed:
  tree-1.8.0-10.el9.x86_64

Complete!
```

Notice it did not stop to ask. It just installed.

**When NOT to use -y:** Do NOT use `-y` when you are working by hand on a
production database server. You want to read the summary first. The `-y` flag
will happily proceed even if `dnf` plans to remove a package you care about, or
pull in something unexpected. On a live database server, an automatic "yes" to
the wrong transaction can take the database offline.

> **DBA Context - The Danger of -y on Production:** Use `-y` in automation
> scripts you have already tested. On a live server you are touching by hand,
> always run the command WITHOUT `-y`. Read the transaction summary. Confirm no
> critical package is being removed or replaced. Only then type `y`. Many
> outages start with a rushed `dnf install -y` that quietly removed something
> important.

---

## 4. sudo dnf remove - Remove a package

`sudo dnf remove` uninstalls a package. Like install, it shows a summary and
asks you to confirm.

Let's remove the `tree` package we just installed:

```bash
sudo dnf remove tree
```

```
Expected output (yours will differ):
Dependencies resolved.
========================================================================
 Package     Architecture    Version           Repository        Size
========================================================================
Removing:
 tree        x86_64          1.8.0-10.el9      @appstream        44 k

Transaction Summary
========================================================================
Remove  1 Package

Freed space: 44 k
Is this ok [y/N]:
```

Type `y` to confirm.

```
Expected output (yours will differ):
Removing:
  tree-1.8.0-10.el9.x86_64

Complete!
```

**Read the removal summary very carefully.** When you remove a package, `dnf`
also removes anything that depended only on it. If you try to remove something
important, the list of things it wants to remove can be surprisingly long.
Always read the `Removing:` section before you type `y`.

> **DBA Context - Removing the Wrong Package:** Removing a package can cascade.
> Asking to remove a shared library can drag PostgreSQL, or even core system
> tools, out with it. Before you confirm any `dnf remove`, read every line of
> the `Removing:` list. If it includes anything you did not expect, type `N`
> and investigate first.

---

## 5. Reinstall and clean up

### Reinstall a package

Did a package's files get corrupted or deleted? Reinstall it to restore them:

```bash
sudo dnf reinstall htop
```

This downloads and lays down the package files again. It does not change the
version.

### Remove unused dependencies

Over time, some packages get left behind. These were installed only as
dependencies, and their parent has since been removed. Clean them up with:

```bash
sudo dnf autoremove
```

```
Expected output (yours will differ):
Dependencies resolved.
Nothing to do.
Complete!
```

If there is nothing to clean up, it simply says `Nothing to do.` That is fine.

---

## 6. Practice exercises

### Install the wget download tool

```bash
sudo dnf install wget
```

Read the summary, then type `y`.

### Confirm wget installed

```bash
which wget
```

```
Expected output (yours will differ):
/usr/bin/wget
```

### Install nano without a prompt (then we will still use vi)

```bash
sudo dnf install -y nano
```

We install `nano` here only to practice the `-y` flag. For editing files in
these labs you will use `vi`.

### Remove nano again

```bash
sudo dnf remove nano
```

Read the `Removing:` summary. Confirm only `nano` is listed. Then type `y`.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain why `dnf install` and `dnf remove` need `sudo` but `dnf search` does not
- [ ] Install a package with `sudo dnf install PACKAGE` and read the summary before confirming
- [ ] Explain what a dependency is and why `dnf` installs dependencies automatically
- [ ] Describe what the `-y` flag does
- [ ] Explain why you should NOT use `-y` on a live production database server
- [ ] Remove a package with `sudo dnf remove PACKAGE`
- [ ] Explain why you must read the `Removing:` list carefully before confirming
- [ ] Use `sudo dnf reinstall` to restore a package's files

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.

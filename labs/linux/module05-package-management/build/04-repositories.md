# Build 04: Working with Repositories

In this guide you will learn what a software repository is. You will see where
repo files live under `/etc/yum.repos.d/`. You will list your repos with
`dnf repolist`. You will turn repos on and off. And you will look inside a
`.repo` file to see what it holds.

As a DBA, you work with repos often. You add one every time you set up the
official PostgreSQL source or the EPEL extras.

**Time estimate:** 40 minutes

All steps run on your lab server. Connect with SSH first as **ec2-user**.

---

## Step 0 - What is a repository?

A repository (repo) is a server on the internet. It holds software packages and
a list of what is available. When you run `dnf install`, `dnf` searches every
repo your system knows about. It finds the package and downloads it from there.

Your CentOS box already has a few repos set up (`baseos` and `appstream`). To
install PostgreSQL 16, you will add one more: the official PostgreSQL repo
(PGDG). Once you understand repos, adding one is easy.

---

## 1. dnf repolist - See your configured repos

`dnf repolist` shows which repos are turned on. It only reads settings, so you
do not need `sudo`.

On **your lab server**, as **ec2-user**:

```bash
dnf repolist
```

```
Expected output (yours will differ):
repo id                        repo name
appstream                      CentOS Stream 9 - AppStream
baseos                         CentOS Stream 9 - BaseOS
extras-common                  CentOS Stream 9 - Extras packages
```

- `repo id` - the short name `dnf` uses to refer to the repo
- `repo name` - a human-readable description

To see disabled repos too, add `--all`:

```bash
dnf repolist --all
```

```
Expected output (yours will differ):
repo id                        repo name                              status
appstream                      CentOS Stream 9 - AppStream            enabled
appstream-debug                CentOS Stream 9 - AppStream - Debug    disabled
baseos                         CentOS Stream 9 - BaseOS               enabled
baseos-source                  CentOS Stream 9 - BaseOS - Source      disabled
...
```

The `status` column tells you the state of each repo. `enabled` means the repo
is used when you install. `disabled` means it is there but ignored.

---

## 2. /etc/yum.repos.d/ - Where repo files live

Each repo is set up by a `.repo` file. These files live in the
`/etc/yum.repos.d/` folder. List them:

```bash
ls /etc/yum.repos.d/
```

```
Expected output (yours will differ):
centos-addons.repo  centos.repo
```

Each file can set up one or more repos. When you add the PostgreSQL repo later,
a new file will show up in this folder.

> **DBA Context - Repo Files Are Just Text:** Everything `dnf` knows about where
> to get packages lives in these plain-text files. Adding the PostgreSQL repo
> just means dropping a new `.repo` file here. So when a server says it "cannot
> find the postgresql16 package", check this folder first. Look for the right
> `.repo` file, and make sure it is turned on.

---

## 3. What a .repo file contains

Let's look inside a repo file to see how it is built. Open it with `vi`. We are
only reading, so we will not change anything:

```bash
sudo vi /etc/yum.repos.d/centos.repo
```

To quit `vi` without changing anything, type `:q!` and press Enter.

A typical repo section looks like this:

```
[baseos]
name=CentOS Stream 9 - BaseOS
baseurl=http://mirror.stream.centos.org/9-stream/BaseOS/$basearch/os/
gpgcheck=1
enabled=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial
```

Here is what each line means:

- `[baseos]` - the repo id, in square brackets
- `name=` - the human-readable description
- `baseurl=` - the web address where the packages live
- `gpgcheck=1` - verify each package's cryptographic signature before installing (1 = yes)
- `enabled=1` - use this repo (1 = enabled, 0 = disabled)
- `gpgkey=` - the location of the key used to verify signatures

> **Concept - GPG Signature Checking:** `gpgcheck=1` tells `dnf` to check every
> package before installing it. It checks that the package is signed by a key
> you trust. This proves two things: the package really came from the vendor,
> and nobody changed it on the way to you. Never turn off `gpgcheck` on a
> database server. It is a key defense against installing a harmful package.

---

## 4. Enabling and disabling repos

You can turn a repo on or off for a single command, or permanently.

### For one command only

Add `--enablerepo` or `--disablerepo` to an install or search. This changes
nothing else. It only affects that one command:

```bash
dnf --disablerepo=extras-common list available "htop"
```

- `--disablerepo=extras-common` - ignore this repo for just this command

This is handy for testing. You can ask "would this package still be available if
I turned that repo off?" And you do it without changing any files.

### Permanently

To turn a repo on or off for good, use the `config-manager` tool. Install it
first:

```bash
sudo dnf install -y dnf-plugins-core
```

Disable a repo permanently (example uses `extras-common`):

```bash
sudo dnf config-manager --set-disabled extras-common
```

Re-enable it:

```bash
sudo dnf config-manager --set-enabled extras-common
```

- `--set-disabled` - sets `enabled=0` in the repo file
- `--set-enabled` - sets `enabled=1` in the repo file

Confirm the change:

```bash
dnf repolist
```

Behind the scenes, `config-manager` just edits the `enabled=` line in the
`.repo` file for you. You could change that line by hand with `vi`. But the
tool is safer.

---

## 5. Refreshing repo metadata

`dnf` saves a local copy of the package list so it does not download it every
time. This saved copy is called the cache. Sometimes the cache is out of date.
This often happens right after you add a new repo. Force a refresh with:

```bash
sudo dnf clean all
```

```
Expected output (yours will differ):
34 files removed
```

Then rebuild the cache:

```bash
sudo dnf makecache
```

```
Expected output (yours will differ):
CentOS Stream 9 - BaseOS                        3.1 MB/s | 8.4 MB     00:02
CentOS Stream 9 - AppStream                     4.5 MB/s |  22 MB     00:04
...
Metadata cache created.
```

> **DBA Context - Stale Metadata After Adding a Repo:** Here is a very common
> mix-up. You add the PostgreSQL repo, then get "No match for argument:
> postgresql16-server". The fix is almost always two commands: `sudo dnf clean
> all`, then `sudo dnf makecache`. This makes `dnf` pick up the new repo's
> package list.

---

## 6. Practice exercises

### List only enabled repos

```bash
dnf repolist
```

### List all repos including disabled ones

```bash
dnf repolist --all
```

### Look at the repo files present on the system

```bash
ls -l /etc/yum.repos.d/
```

```
Expected output (yours will differ):
-rw-r--r--. 1 root root 2.4K Jul  8 14:10 centos-addons.repo
-rw-r--r--. 1 root root 1.1K Jul  8 14:10 centos.repo
```

### Confirm gpgcheck is enabled in the base repo

```bash
sudo grep gpgcheck /etc/yum.repos.d/centos.repo
```

```
Expected output (yours will differ):
gpgcheck=1
gpgcheck=1
```

This one-off file read with `sudo grep` is fine for inspecting a config.

---

## Checkpoint

Before moving to the next guide, confirm you can do all of the following:

- [ ] Explain what a software repository is
- [ ] Use `dnf repolist` to see enabled repos and `--all` to see disabled ones
- [ ] Locate repo definition files under `/etc/yum.repos.d/`
- [ ] Read a `.repo` file and explain `name`, `baseurl`, `enabled`, and `gpgcheck`
- [ ] Explain what GPG signature checking protects against
- [ ] Disable and re-enable a repo with `dnf config-manager`
- [ ] Refresh the metadata cache with `dnf clean all` and `dnf makecache`
- [ ] Explain the common "package not found after adding a repo" fix

If any of these do not work, re-read the steps above or ask your instructor
for help before continuing.

# Module 01 - Git & GitHub for DBAs
## Guide 01: Your First Repository

**Objective:** Install git, create your first repository, and learn the everyday commands: status, add, commit, log, diff, show, and blame.
**Time:** 30-35 minutes
**Prerequisites:**
- You can SSH into your server **pg-git-1** as `ec2-user`
- You read Concepts 01 and 02 (the three areas: working directory, staging, repository)

---

## 1. Log in to your server

On your laptop, SSH into **pg-git-1** as **ec2-user**:

```bash
ssh -i your-key.pem ec2-user@YOUR_SERVER_IP
```

All of this guide happens as `ec2-user`. We will not touch PostgreSQL yet - first we learn git in a safe practice directory.

## 2. Install git

On **pg-git-1**, as **ec2-user**, check whether git is installed:

```bash
git --version
```

Expected output (yours will differ):

```
bash: git: command not found
```

Not installed. Install it with dnf, the package manager on CentOS. `sudo` runs the install as root, and `-y` answers "yes" to the confirmation prompt:

```bash
sudo dnf install -y git
```

Expected output (yours will differ):

```
Installed:
  git-2.52.0-1.el9.x86_64                git-core-2.52.0-1.el9.x86_64
  git-core-doc-2.52.0-1.el9.noarch       perl-DynaLoader-1.47-483.el9.x86_64
  ...
Complete!
```

Confirm it works:

```bash
git --version
```

Expected output (yours will differ):

```
git version 2.52.0
```

## 3. Tell git who you are

Every commit records an author. Git refuses to commit until it knows your name and email, so we set them once, globally (for your `ec2-user` account on this server). Use YOUR name and email:

```bash
git config --global user.name "Your Name"
```

```bash
git config --global user.email "you@example.com"
```

Two more one-time settings. First, make new repositories name their starting branch `main` (git's historical default is `master`, but `main` is the modern standard and what GitHub uses - setting this now avoids a confusing mismatch later):

```bash
git config --global init.defaultBranch main
```

Second, tell git to open `vi` whenever it needs you to type a message:

```bash
git config --global core.editor vi
```

Check all four settings landed:

```bash
git config --global --list
```

Expected output (yours will differ):

```
user.name=Felicite Nji
user.email=felicite.suta@gmail.com
init.defaultbranch=main
core.editor=vi
```

## 4. Create your first repository

Still as **ec2-user** on **pg-git-1**, make a practice directory and enter it:

```bash
mkdir ~/git-practice
```

```bash
cd ~/git-practice
```

Turn this directory into a git repository:

```bash
git init
```

Expected output (yours will differ):

```
Initialized empty Git repository in /home/ec2-user/git-practice/.git/
```

Look at what `git init` actually did. `ls -a` lists ALL files, including hidden ones (names starting with a dot):

```bash
ls -a
```

Expected output (yours will differ):

```
.  ..  .git
```

One hidden folder, `.git`. That folder IS the repository - all history and settings will live inside it. The directory is otherwise untouched.

## 5. git status - your orientation command

`git status` tells you the state of the repository. It is always safe to run, and it usually suggests your next command. Run it now:

```bash
git status
```

Expected output (yours will differ):

```
On branch main

No commits yet

nothing to commit (create/copy files and use "git add" to track)
```

Read it: you are on branch `main` (thanks to the setting from step 3), there is no history yet, and there is nothing to record. When in doubt at ANY point in this module, run `git status`.

## 6. Create a file to track

We will track a notes file - the kind of thing a DBA actually keeps per server. Create it with vi:

```bash
vi server-notes.md
```

In vi: press `i` to enter insert mode, type the four lines below, then press `Esc` and type `:wq` to save and quit.

```
# Server Notes - pg-git-1

PostgreSQL 16 data directory: /opt/pgsql/data
Port: 5432
```

Now ask git what it sees:

```bash
git status
```

Expected output (yours will differ):

```
On branch main

No commits yet

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	server-notes.md

nothing to commit but untracked files present (use "git add" to track)
```

**Untracked** means: git sees the file exists but is not recording its history yet. Git never tracks anything without being asked.

## 7. Stage it, then commit it

Remember the two-step model from Concepts 02: `add` puts the file's current content in the staging area, `commit` seals the snapshot. Stage the file:

```bash
git add server-notes.md
```

```bash
git status
```

Expected output (yours will differ):

```
On branch main

No commits yet

Changes to be committed:
  (use "git rm --cached <file>..." to unstage)
	new file:   server-notes.md
```

"Changes to be committed" = staged. Now take the snapshot. `-m` supplies the commit message on the command line (without `-m`, git opens vi and waits for you to type one - we will do that in a later guide):

```bash
git commit -m "add server notes for pg-git-1"
```

Expected output (yours will differ):

```
[main (root-commit) e22dad2] add server notes for pg-git-1
 1 file changed, 4 insertions(+)
 create mode 100644 server-notes.md
```

Read it: on branch `main`, this is the first commit ever (`root-commit`), its short ID is `e22dad2` (yours WILL differ - IDs are unique), one file with 4 new lines.

```bash
git status
```

Expected output (yours will differ):

```
On branch main
nothing to commit, working tree clean
```

**Working tree clean** is the phrase you want to see after every config change you make for the rest of your career: everything on disk is safely recorded.

## 8. Read the history

```bash
git log
```

Expected output (yours will differ):

```
commit e22dad22043a5f6ad7c5044bd52a6124ab83d63e
Author: Felicite Nji <felicite.suta@gmail.com>
Date:   Thu Aug 13 00:59:20 2026 +0000

    add server notes for pg-git-1
```

There is your audit trail: who, when, what, and the full 40-character commit ID. For day-to-day use the compact form is easier to read - one line per commit:

```bash
git log --oneline
```

Expected output (yours will differ):

```
e22dad2 add server notes for pg-git-1
```

Tip: if the log is long, git shows it in a pager. Press `q` to quit the pager.

## 9. Change the file and see the difference

Edit the notes file with vi. Add these two lines at the bottom (in vi: `i` to insert, `Esc` then `:wq` to save):

```bash
vi server-notes.md
```

```
Backups: not configured yet
```

(Leave one empty line above it, like a new paragraph.)

Now the key question git answers all day long: what changed?

```bash
git diff
```

Expected output (yours will differ):

```
diff --git a/server-notes.md b/server-notes.md
index 205ae8e..4f266be 100644
--- a/server-notes.md
+++ b/server-notes.md
@@ -2,3 +2,5 @@

 PostgreSQL 16 data directory: /opt/pgsql/data
 Port: 5432
+
+Backups: not configured yet
```

Lines starting with `+` were added (removals show as `-`). This is comparing your working directory against the staging area - your unstaged edits.

Stage the change, then run `git diff` again:

```bash
git add server-notes.md
```

```bash
git diff
```

Expected output: nothing at all. Surprised? `git diff` shows UNSTAGED changes, and you just staged everything. To see what is staged and about to be committed:

```bash
git diff --staged
```

Expected output (yours will differ):

```
diff --git a/server-notes.md b/server-notes.md
--- a/server-notes.md
+++ b/server-notes.md
@@ -2,3 +2,5 @@

 PostgreSQL 16 data directory: /opt/pgsql/data
 Port: 5432
+
+Backups: not configured yet
```

Remember the pair: `git diff` = not staged yet. `git diff --staged` = staged, ready to commit. Commit it:

```bash
git commit -m "note that backups are not configured yet"
```

Expected output (yours will differ):

```
[main 3d889bf] note that backups are not configured yet
 1 file changed, 2 insertions(+)
```

## 10. Inspect one commit: git show

`git show` displays a single commit in full - its metadata plus the exact change. With no argument it shows the newest commit (`HEAD`):

```bash
git show HEAD
```

Expected output (yours will differ):

```
commit 3d889bfb126264b61af4f74c6511c4bb37c1849d
Author: Felicite Nji <felicite.suta@gmail.com>
Date:   Thu Aug 13 00:59:20 2026 +0000

    note that backups are not configured yet

diff --git a/server-notes.md b/server-notes.md
...
+Backups: not configured yet
```

You can `git show` any commit ID from `git log` the same way. This is how you will answer "what exactly did that change do?" during incidents.

## 11. Who wrote each line: git blame

`git blame` labels every line of a file with the commit and author that last touched it:

```bash
git blame server-notes.md
```

Expected output (yours will differ):

```
^e22dad2 (Felicite Nji 2026-08-13 00:59:20 +0000 1) # Server Notes - pg-git-1
^e22dad2 (Felicite Nji 2026-08-13 00:59:20 +0000 2)
^e22dad2 (Felicite Nji 2026-08-13 00:59:20 +0000 3) PostgreSQL 16 data directory: /opt/pgsql/data
^e22dad2 (Felicite Nji 2026-08-13 00:59:20 +0000 4) Port: 5432
3d889bfb (Felicite Nji 2026-08-13 00:59:20 +0000 5)
3d889bfb (Felicite Nji 2026-08-13 00:59:20 +0000 6) Backups: not configured yet
```

Two different commits are visible (the `^` marks lines from the very first commit). On a shared config file, this command answers "who changed this line and when" instantly. This is the 2am command.

## 12. Checkpoint

You should now have exactly two commits:

```bash
git log --oneline
```

Expected output (yours will differ):

```
3d889bf note that backups are not configured yet
e22dad2 add server notes for pg-git-1
```

**You now know:** install git, set your identity, `git init`, the status/add/commit cycle, `log`, `diff` vs `diff --staged`, `show`, and `blame`.

Next guide: branches and merging - how to test a change without touching the version you trust.

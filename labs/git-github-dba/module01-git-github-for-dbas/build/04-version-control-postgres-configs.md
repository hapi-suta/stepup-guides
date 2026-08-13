# Module 01 - Git & GitHub for DBAs
## Guide 04: The Capstone - Version Control Your PostgreSQL Configs

**Objective:** Put your REAL PostgreSQL configuration files under git, connect the repo to GitHub, make a tuning change the professional way, then break the server with a bad config and recover it with git.
**Time:** 50-60 minutes
**Prerequisites:**
- Guides 01-03 completed (git installed, your GitHub account working)
- PostgreSQL 16 running on **pg-single** with data directory `/opt/pgsql/data`

---

## 1. The plan

Everything so far was practice. Now we do it for real: the repository will live directly in the PostgreSQL data directory, tracking exactly three config files (plus two small helpers):

- `postgresql.conf` - the main server configuration
- `pg_hba.conf` - who may connect, from where, how
- `postgresql.auto.conf` - what `ALTER SYSTEM` writes

Everything else in the data directory (your actual data!) will be explicitly ignored. This repo-in-the-data-directory pattern is the standard way to version configs that live where the engine puts them (the etckeeper tool has done the same for `/etc` for years).

## 2. Switch to the postgres user

The config files are owned by the `postgres` OS user, so ALL git work on this repo happens as `postgres`. On **pg-single**, as **ec2-user**:

```bash
sudo su - postgres
```

Your prompt changes. Confirm who and where you are:

```bash
whoami
```

```bash
echo $PGDATA
```

Expected output (yours will differ):

```
postgres
/opt/pgsql/data
```

## 3. Git identity for the postgres user

Git settings are per OS user. You configured `ec2-user` in guide 01; the `postgres` user has never met you. Same four commands, as **postgres** (use YOUR name and email):

```bash
git config --global user.name "Your Name"
```

```bash
git config --global user.email "you@example.com"
```

```bash
git config --global init.defaultBranch main
```

```bash
git config --global core.editor vi
```

## 4. Create the repository in the data directory

Still as **postgres** on **pg-single**:

```bash
cd $PGDATA
```

```bash
git init
```

Expected output (yours will differ):

```
Initialized empty Git repository in /opt/pgsql/data/.git/
```

Note what we did NOT do: we did not touch PostgreSQL. The server keeps running - to it, `.git` is just a folder it never looks at.

## 5. The whitelist .gitignore - the most important file in this repo

The data directory contains your database. We must never commit `base/`, `pg_wal/`, or any binary data files. Instead of ignoring things one by one, we invert it: **ignore everything, then re-allow only the files we want.** Create the file with vi (`i` to insert, `Esc` `:wq` to save):

```bash
vi .gitignore
```

```
*
!postgresql.conf
!pg_hba.conf
!pg_ident.conf
!postgresql.auto.conf
!.gitignore
```

Line 1 ignores everything. Each `!` line re-includes one file. (`pg_ident.conf` is the user-name mapping file - tiny, and it belongs with `pg_hba.conf`. The `.gitignore` itself is also tracked, so the safety rules travel with the repo.)

Now see what git considers trackable:

```bash
git status
```

Expected output (yours will differ):

```
On branch main

No commits yet

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	.gitignore
	pg_hba.conf
	pg_ident.conf
	postgresql.auto.conf
	postgresql.conf
```

Exactly five files - and NOT the hundreds of data files sitting in the same directory. The whitelist works. This check matters: if you ever see `base/` or `pg_wal/` in git status here, STOP and fix the .gitignore.

## 6. The baseline commit and tag

Record the known-good state, then name it:

```bash
git add .
```

```bash
git commit -m "baseline: configs as provisioned"
```

Expected output (yours will differ):

```
[main (root-commit) 4675838] baseline: configs as provisioned
 5 files changed, 917 insertions(+)
```

```bash
git tag -a baseline-v1 -m "known good: as provisioned"
```

From this moment, every config change on this server is a diff away from a known-good state.

## 7. Why you must work as postgres (a deliberate error)

Exit to `ec2-user` for a moment:

```bash
exit
```

On **pg-single**, as **ec2-user**, try to read the repo's status through sudo (which runs git as root):

```bash
sudo git -C /opt/pgsql/data status
```

Expected output (yours will differ):

```
fatal: detected dubious ownership in repository at '/opt/pgsql/data'
To add an exception for this directory, call:

	git config --global --add safe.directory /opt/pgsql/data
```

Git refuses: the repo belongs to `postgres`, and a DIFFERENT user (root) is poking at it. This is a security feature (and the error you will most often see teammates hit). The right response is not the suggested exception - it is to do git work as the owning user. Switch back:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

## 8. Watch postgres write to its own config - ALTER SYSTEM

`ALTER SYSTEM` is how you change settings from inside SQL. It writes to `postgresql.auto.conf` - which you now track. Still as **postgres**:

```bash
psql -c "ALTER SYSTEM SET work_mem = '8MB';"
```

```bash
git status
```

Expected output (yours will differ):

```
On branch main
Changes not staged for commit:
	modified:   postgresql.auto.conf
```

Git caught PostgreSQL editing its own file. Look at exactly what it wrote:

```bash
git diff
```

Expected output (yours will differ):

```
diff --git a/postgresql.auto.conf b/postgresql.auto.conf
--- a/postgresql.auto.conf
+++ b/postgresql.auto.conf
@@ -1,2 +1,3 @@
 # Do not edit this file manually!
 # It will be overwritten by the ALTER SYSTEM command.
+work_mem = '8MB'
```

Commit it like any other config change:

```bash
git add postgresql.auto.conf
```

```bash
git commit -m "raise work_mem to 8MB via ALTER SYSTEM"
```

One security note from Concepts 03: on a replica built with `pg_basebackup -R`, this file can contain a plaintext replication password if one was typed on the command line. Keep passwords in `~/.pgpass` and that never happens - and configs stay committable.

## 9. A real tuning change, the professional way

Change `shared_buffers` on a branch, exactly like the practice runs. As **postgres**, in `$PGDATA`:

```bash
git switch -c tune-shared-buffers
```

Open `postgresql.conf` with vi, find the line `shared_buffers = 128MB` (in vi, type `/shared_buffers` and press Enter to search), and change it to `256MB`:

```bash
vi postgresql.conf
```

```bash
git diff
```

Expected output (yours will differ):

```
-shared_buffers = 128MB			# min 128kB
+shared_buffers = 256MB			# min 128kB
```

```bash
git add postgresql.conf
```

```bash
git commit -m "raise shared_buffers to 256MB"
```

Merge it into main (fast-forward, since main has not moved):

```bash
git switch main
```

```bash
git merge tune-shared-buffers
```

```bash
git branch -d tune-shared-buffers
```

## 10. Reload vs restart - and how to know which you need

The file is changed and committed, but PostgreSQL has not read it yet. Ask for a reload from SQL:

```bash
psql -c "SELECT pg_reload_conf();"
```

Now the question every DBA must be able to answer: did my change take effect?

```bash
psql -c "SELECT name, setting, unit, pending_restart FROM pg_settings WHERE name IN ('shared_buffers','work_mem') ORDER BY name;"
```

Expected output (yours will differ):

```
      name      | setting | unit | pending_restart
----------------+---------+------+-----------------
 shared_buffers | 16384   | 8kB  | t
 work_mem       | 8192    | kB   | f
```

Read it carefully - this is the lesson of the whole section:

- `work_mem` = 8192 kB = 8MB. Applied. The reload was enough.
- `shared_buffers` = 16384 x 8kB = still 128MB, and `pending_restart = t`: PostgreSQL saw your new value but CANNOT apply it without a restart.

Run the `pending_restart` query after every config deployment. Now do the restart. Restarts are done with systemd, as **ec2-user** (not postgres):

```bash
exit
```

On **pg-single**, as **ec2-user**:

```bash
sudo systemctl restart postgresql-16
```

```bash
sudo -u postgres psql -c "SELECT name, setting, unit, pending_restart FROM pg_settings WHERE name IN ('shared_buffers','work_mem') ORDER BY name;"
```

Expected output (yours will differ):

```
      name      | setting | unit | pending_restart
----------------+---------+------+-----------------
 shared_buffers | 32768   | 8kB  | f
 work_mem       | 8192    | kB   | f
```

32768 x 8kB = 256MB, nothing pending. Tuning change: deployed, verified, and in the history books.

## 11. Put the config repo on GitHub

In your **browser**: create a second repository on GitHub named `pg-single-config`, **Private**, completely empty (no README) - same procedure as guide 03 step 2.

The postgres user needs its own SSH key on your GitHub account - remember, keys belong to the OS user, and the key you made in guide 03 belongs to ec2-user. On **pg-git-1**, as **ec2-user**:

```bash
sudo su - postgres
```

Generate a key for the postgres user, exactly like guide 03 (press Enter at every prompt; if it says the key already exists, answer `n` and just continue):

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

Print the public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Expected output (yours will differ):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMRdjyI88w6thZyFp5eswWdEjnC2x4CJlf4oVe3HX8uW you@example.com
```

In your **browser**: GitHub Settings -> SSH and GPG keys -> New SSH key, title `pg-single postgres`, paste, add. Then, back as **postgres** on **pg-single**, test (type `yes` at the first-time host prompt):

```bash
ssh -T git@github.com
```

Expected output (yours will differ):

```
Hi YOUR_USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

Connect and push - history, then tags:

```bash
cd $PGDATA
```

```bash
git remote add origin git@github.com:YOUR_USERNAME/pg-single-config.git
```

```bash
git push -u origin main
```

Expected output (yours will differ):

```
To github.com:YOUR_USERNAME/pg-single-config.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

```bash
git push origin --tags
```

Expected output (yours will differ):

```
To github.com:YOUR_USERNAME/pg-single-config.git
 * [new tag]         baseline-v1 -> baseline-v1
```

Your server's real configuration now survives the server.

## 12. The finale: break it, then recover with git

Time to have the incident on purpose, so the first time is not in production. You will commit a bad config change that LOOKS innocent, watch PostgreSQL refuse to start, then use git to find and undo it.

As **postgres**, in `$PGDATA`, open `postgresql.conf` with vi and change the `max_connections` line to an invalid value:

```
max_connections = banana			# (change requires restart)
```

Commit and push it with an innocent message - this is exactly how real incidents look:

```bash
git add postgresql.conf
```

```bash
git commit -m "increase max_connections for the new app"
```

```bash
git push
```

Now apply it. Exit to **ec2-user** and restart:

```bash
exit
```

```bash
sudo systemctl restart postgresql-16
```

Expected output (yours will differ):

```
Job for postgresql-16.service failed because the control process exited with error code.
See "systemctl status postgresql-16.service" and "journalctl -xeu postgresql-16.service" for details.
```

**The database is down.** Diagnose it like an SRE. With a broken config the logging collector never starts, so the error is in the systemd journal, not the postgres log:

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20 | grep -iE "fatal|invalid"
```

Expected output (yours will differ):

```
... LOG:  invalid value for parameter "max_connections": "banana"
... FATAL:  configuration file "/opt/pgsql/data/postgresql.conf" contains errors
```

The config file has errors. WHICH change did it? Ask git. As **ec2-user**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git log --oneline | head -3
```

Expected output (yours will differ):

```
10e95e7 increase max_connections for the new app
c6c84d4 raise shared_buffers to 256MB
f6759b8 raise work_mem to 8MB via ALTER SYSTEM
```

The newest commit touched connections. Confirm what it actually changed:

```bash
git show HEAD
```

Expected output (yours will differ):

```
-max_connections = 100			# (change requires restart)
+max_connections = banana			# (change requires restart)
```

There is the culprit, with author and timestamp attached. Undo it the safe way - revert creates a new commit restoring the old value, keeping the full story in history:

```bash
git revert --no-edit HEAD
```

Expected output (yours will differ):

```
[main db8eaa3] Revert "increase max_connections for the new app"
 1 file changed, 1 insertion(+), 1 deletion(-)
```

```bash
grep "^max_connections" postgresql.conf
```

Expected output (yours will differ):

```
max_connections = 100			# (change requires restart)
```

The file is fixed. Start the server - as **ec2-user**:

```bash
exit
```

```bash
sudo systemctl start postgresql-16
```

```bash
sudo -u postgres psql -c "SHOW max_connections;"
```

Expected output (yours will differ):

```
 max_connections
-----------------
 100
```

Back up. Finally, push the revert so GitHub has the whole story - as **ec2-user**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git push
```

```bash
git log --oneline | head -5
```

Expected output (yours will differ):

```
db8eaa3 Revert "increase max_connections for the new app"
10e95e7 increase max_connections for the new app
c6c84d4 raise shared_buffers to 256MB
f6759b8 raise work_mem to 8MB via ALTER SYSTEM
4675838 baseline: configs as provisioned
```

Read that history bottom to top: baseline, two tuning changes, one mistake, one recovery. Every line answers who/when/what. THIS is why DBAs version their configs.

```bash
exit
```

## 13. Checkpoint

- `/opt/pgsql/data` is a git repository tracking exactly 5 files (never data)
- Baseline tagged `baseline-v1`, everything pushed to your private `pg-single-config` repo
- You changed a setting via branch + merge, verified with `pending_restart`
- You broke the server, diagnosed it from the journal, found the culprit with `git log`/`git show`, recovered with `git revert`, and pushed the audit trail

**Module complete.** The USE exercises will drill these skills; SURVIVE will throw incidents at you without the guide rails.

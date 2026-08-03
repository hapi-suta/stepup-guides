# Build 2: Version the REAL Config (40 min)

In this lab the server's actual postgresql.conf and pg_hba.conf come off pgforge-1 and into the repo, and you make your first commit - the "as installed" baseline. From this moment, every config change on that server has a history.

Tested against a live PostgreSQL 16.11 server on 2026-07-22. Outputs are real captured outputs.

---

## Step 1: Pull the real postgresql.conf from the server

On **your Mac**, in **~/Projects/pg-ops**:

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@YOUR_SERVER_IP 'sudo cat /var/lib/pgsql/16/data/postgresql.conf' > config/pgforge-1/postgresql.conf
```

What this does: runs one command on the server (`sudo cat` prints the file - ec2-user cannot read it directly, the postgres user owns it) and the `>` saves what comes back into your repo folder on the Mac.

Expected result: no output on success. Check the file arrived:

```bash
wc -l config/pgforge-1/postgresql.conf
```

Expected output (yours will differ):
```
     831 config/pgforge-1/postgresql.conf
```

That is the real file - all 831 lines of it, mostly comments and defaults. That is normal.

## Step 2: Pull pg_hba.conf too

```bash
ssh -i ~/.ssh/yourkey.pem ec2-user@YOUR_SERVER_IP 'sudo cat /var/lib/pgsql/16/data/pg_hba.conf' > config/pgforge-1/pg_hba.conf
```

```bash
wc -l config/pgforge-1/pg_hba.conf
```

Expected output (yours will differ):
```
     125 config/pgforge-1/pg_hba.conf
```

## Step 3: Read before you commit - the cleaning check

Open each file and look for anything private before it enters history:

```bash
vi config/pgforge-1/postgresql.conf
```

A fresh initdb config has nothing private. But this check is a habit, not a formality - on a production server this file can contain passwords in connection strings, internal hostnames, or listen addresses you do not want public. Look, then quit with `:q`.

Do the same for pg_hba.conf - it shows your network layout, so on a real production repo you decide in USE Exercise 1 whether it belongs in a public repo at all.

## Step 4: Stage and commit the baseline

```bash
git add .gitignore config/pgforge-1/postgresql.conf config/pgforge-1/pg_hba.conf
```

Name files one by one - it forces you to know exactly what is entering history.

```bash
git status
```

Expected output:
```
On branch main

No commits yet

Changes to be committed:
  (use "git rm --cached <file>..." to unstage)
	new file:   .gitignore
	new file:   config/pgforge-1/pg_hba.conf
	new file:   config/pgforge-1/postgresql.conf
```

Commit:

```bash
git commit -m "feat: baseline pgforge-1 configs as installed (PG 16.11, fresh initdb)"
```

The message says WHY this state matters: it is the untouched starting point.

Expected output (yours will differ). The gitleaks banner runs on every commit - "no leaks found" is it approving:
```
    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

11:13PM INF 0 commits scanned.
11:13PM INF no leaks found
[main (root-commit) aa13149] feat: baseline pgforge-1 configs as installed (PG 16.11, fresh initdb)
 3 files changed, 967 insertions(+)
```

## Step 5: Read your history

```bash
git log --oneline
```

Expected output (your ID will differ):
```
aa13149 (HEAD -> main) feat: baseline pgforge-1 configs as installed (PG 16.11, fresh initdb)
```

`HEAD` is where you are standing in history - like the current LSN.

```bash
git show --stat HEAD
```

`show` displays one commit; `--stat` summarizes changed files instead of full diffs; `HEAD` means the latest.

Expected output (yours will differ):
```
commit aa1314977060a8e700137bf08a2640aada8c92aa
Author: Happy Afopezi <thedevopsdba@gmail.com>
Date:   Wed Jul 22 23:13:58 2026 -0700

    feat: baseline pgforge-1 configs as installed (PG 16.11, fresh initdb)

 .gitignore                        | 11 ++++
 config/pgforge-1/pg_hba.conf      | 125 ++++++++
 config/pgforge-1/postgresql.conf  | 831 ++++++++++++++++++++++
```

The baseline exists. Any future change to that server's config can now be compared against this exact moment - forever. Continue to Build 3, where you change the config in the repo and the server follows.

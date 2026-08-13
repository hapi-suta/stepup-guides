# Exercise 02: pg_hba Lockout Forensics

**Duration:** 20 minutes
**Objective:** Diagnose and recover from a bad pg_hba.conf change using git - while locked out of SQL.
**Prerequisites:** BUILD guide 04 completed. Single node. Work as **postgres** on **pg-single**.

## Background

A well-meaning "auth cleanup" changes local connections from `trust` to `md5`. Sounds more secure - except the postgres user has no password set, so the next person to run psql is locked out. You will make the change yourself (playing the colleague), then recover (playing you).

## Setup: be the colleague

As **postgres** on **pg-single**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

Open `pg_hba.conf` with vi. Find this line near the bottom:

```
local   all       all                 trust
```

Change `trust` to `md5`. Save, then commit and apply it, exactly as the colleague did:

```bash
git add pg_hba.conf
```

```bash
git commit -m "auth cleanup"
```

```bash
pg_ctl reload -D $PGDATA
```

## Question 1: How does the lockout actually look?

### Try it

```bash
psql -c "SELECT 1;"
```

Expected output (yours will differ):

```
Password for user postgres:
psql: error: connection to server on socket "/run/postgresql/.s.PGSQL.5432" failed: FATAL:  password authentication failed for user "postgres"
```

(Press Enter at the prompt.) You cannot get into SQL. Note what that means: `SELECT pg_reload_conf()` is NOT available to you. Keep that in mind for question 3.

## Question 2: Prove which change did it - without psql

### Try it

```bash
git log --oneline | head -3
```

```bash
git diff HEAD~1 HEAD
```

Expected output (yours will differ):

```
-local   all       all                 trust
+local   all       all                 md5
```

`HEAD~1 HEAD` means "compare the previous commit to the current one". There is your evidence: the exact line, the commit, the author, the time.

## Question 3: Recover - revert and reload without SQL

### Try it

```bash
git revert --no-edit HEAD
```

```bash
pg_ctl reload -D $PGDATA
```

Expected output (yours will differ):

```
[main 488a7cd] Revert "auth cleanup"
server signaled
```

`pg_ctl reload` sends the server a signal directly - no SQL session needed. This is the tool you reach for when pg_hba locks you out.

Verify you are back in:

```bash
psql -tc "SELECT 'access restored';"
```

Expected output (yours will differ):

```
 access restored
```

## Question 4 (thought exercise)

The colleague's INTENT (require passwords locally) was reasonable. What should the correct change have included to avoid the lockout? (Hint: two answers - set a password for the postgres role FIRST, and/or test with a second session still open before closing yours.)

# Scenario 02 - pg_hba Lockout: Locked Out of Your Own Database

**Severity:** HIGH
**Expected Recovery Time:** 10-25 minutes
**Single Node:** pg-git-1 only

## Alert

```
psql on pg-git-1 suddenly demands a password that nobody has - local
connections are locked out after a 'tighten local authentication' change.
PostgreSQL itself is still running.
```

## Key Concepts for Revision

- pg_hba.conf rules decide WHO gets in HOW; a bad rule can lock out even the superuser
- Locked out of SQL means `SELECT pg_reload_conf()` is NOT available - `pg_ctl reload` signals the server from the OS instead
- `git diff HEAD~1 HEAD` = exactly what the last commit changed
- pg_hba changes apply on RELOAD (no restart needed)

## Layer 1: Quick Reference

Reproduce the error -> `git diff HEAD~1 HEAD` -> revert as postgres -> `pg_ctl reload` -> psql works.

## Layer 2: Step by Step

### 1. See the lockout for yourself

On **pg-git-1**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
psql -c "SELECT 1;"
```

Password prompt, and no password works. You cannot fix this from inside SQL - you are never getting inside SQL. Everything that follows happens at the OS level.

### 2. Find what changed

Still as **postgres**:

```bash
cd $PGDATA
```

```bash
git log --oneline | head -3
```

```bash
git diff HEAD~1 HEAD
```

The diff shows the auth method flip (trust -> md5) on the local line. That is the lockout.

### 3. Revert and reload - no SQL required

```bash
git revert --no-edit HEAD
```

```bash
pg_ctl reload -D $PGDATA
```

`pg_ctl reload` sends SIGHUP straight to the postmaster - the OS-level equivalent of `pg_reload_conf()`, and it works precisely when SQL does not.

### 4. Verify

```bash
psql -tc "SELECT 'access restored';"
```

Push the revert if you have a remote (`git push`), then say **check my fix** to the bot.

## Layer 3: Understanding

The colleague's intent (require passwords locally) was defensible - the execution wasn't: they flipped the rule before setting a password for the postgres role, and tested nothing. The professional sequence for auth changes is: set the credential FIRST, keep one session open as a lifeline, apply the change, verify from a NEW session, only then close the lifeline. Also worth knowing for the day it is worse than md5: if you are ever fully locked out with no git history to revert, single-user mode (`postgres --single`) bypasses pg_hba entirely - the break-glass of last resort.

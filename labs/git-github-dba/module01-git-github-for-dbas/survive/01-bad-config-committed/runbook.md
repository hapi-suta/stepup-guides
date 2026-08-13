# Scenario 01 - Bad Config Committed: PostgreSQL Won't Start

**Severity:** CRITICAL
**Expected Recovery Time:** 15-30 minutes
**Single Node:** pg-git-1 only

## Alert

```
PostgreSQL is DOWN on pg-git-1 after last night's 'performance tuning for
app launch' deploy - the service refuses to start.
```

## Key Concepts for Revision

- When the config is broken, the logging collector never starts - startup errors land in the **systemd journal**, not the postgres log
- `git log --oneline` + `git show HEAD` = which change, by whom, exactly what
- `git revert` undoes a committed change WITH an audit trail - never hand-edit the mistake away
- Config changes take effect on restart; a revert fixes the FILE, systemd brings back the SERVICE

## Layer 1: Quick Reference (if you know what you are doing)

Journal -> culprit commit -> revert as postgres -> start service -> verify.

## Layer 2: Step by Step

### 1. Confirm the failure

On **pg-git-1**, as **ec2-user**:

```bash
sudo systemctl status postgresql-16 --no-pager | head -8
```

The service is failed/activating. Find WHY - the journal holds the startup error:

```bash
sudo journalctl -u postgresql-16 --no-pager -n 20 | grep -iE "fatal|invalid"
```

You are looking for lines like `invalid value for parameter ...` and `FATAL: configuration file ... contains errors`. Now you know WHICH file and WHICH parameter.

### 2. Find the culprit change with git

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git log --oneline | head -3
```

The newest commit has an innocent message. Verify what it ACTUALLY did:

```bash
git show HEAD
```

The diff shows the invalid value - and `git log` shows who committed it and when.

### 3. Undo it the safe way

```bash
git revert --no-edit HEAD
```

Confirm the file is fixed:

```bash
grep "^shared_buffers" postgresql.conf
```

### 4. Bring the database back

```bash
exit
```

As **ec2-user**:

```bash
sudo systemctl start postgresql-16
```

```bash
sudo -u postgres psql -c "SELECT 1;"
```

### 5. Complete the audit trail

If your repo has a GitHub remote, push the revert - as **postgres**: `git push`.

Say **check my fix** to the bot when you believe you are done.

## Layer 3: Understanding

Why revert instead of editing the value back by hand? Both fix the file - but the hand-edit creates a history where the mistake silently disappears, while revert creates a history that says "this change was made, it was wrong, it was undone, by this person, at this time". During a real postmortem that difference is everything. And why did the deploy "work" last night but fail now? Config file errors surface at the next restart/reload, not at commit time - which is exactly why you run the `pending_restart` check and restart deliberately after every config change, not whenever fate decides.

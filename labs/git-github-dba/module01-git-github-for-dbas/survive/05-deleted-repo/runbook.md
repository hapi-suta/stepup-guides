# Scenario 05 - Deleted Repo: The History Is Gone From the Server

**Severity:** HIGH
**Expected Recovery Time:** 20-35 minutes
**Single Node:** pg-git-1 only

## Alert

```
During a disk-space hunt, someone deleted the 'hidden junk folder'
/opt/pgsql/data/.git on pg-git-1. PostgreSQL is fine, your config FILES are
fine - but every commit, tag, and piece of history is gone from this server.
```

## Key Concepts for Revision

- `.git/` IS the repository; the working files are just a checkout
- Git is distributed: your GitHub remote holds the COMPLETE history - this is the recovery you set up in guide 04 without knowing it
- `git clone --no-checkout` fetches the repository without touching working files
- After transplanting `.git` back, `git reset` (no flags) rebuilds the index so status is truthful

## Layer 1: Quick Reference

Clone `--no-checkout` to /tmp -> move its `.git` into $PGDATA -> `git reset` -> `git status` clean -> cleanup /tmp.

## Layer 2: Step by Step

### 1. Confirm the damage

On **pg-git-1**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git status
```

`fatal: not a git repository`. The configs themselves are still here (`ls postgresql.conf` works) - PostgreSQL never needed git. Only the history is gone.

### 2. Fetch the full repository from GitHub - without touching your files

Clone into a scratch location. `--no-checkout` means "bring the history, do NOT write any working files" - important because your LIVE configs are sitting in $PGDATA and must not be overwritten by the clone:

```bash
cd /tmp
```

```bash
git clone --no-checkout git@github.com:YOUR_USERNAME/pg-git-1-config.git repo-rescue
```

### 3. Transplant the .git folder back

```bash
mv /tmp/repo-rescue/.git $PGDATA/.git
```

```bash
cd $PGDATA
```

The history is back, but git's index is empty (we skipped the checkout). Rebuild it against HEAD - `git reset` with no flags touches ONLY the index, never your files:

```bash
git reset
```

### 4. Verify everything lines up

```bash
git status
```

Expect `On branch main ... working tree clean` - your live files match the pushed history exactly. Confirm the history and tags made the trip:

```bash
git log --oneline | head -5
```

```bash
git tag
```

Clean up the scratch clone:

```bash
rm -rf /tmp/repo-rescue
```

Say **check my fix** to the bot.

## Layer 3: Understanding

If `git status` had NOT been clean after the transplant, that would mean your live files differ from what was last pushed - which files, `git diff` would tell you, and the decision (commit the difference vs restore from history) is a judgment call about which side is the truth. This scenario is also the strongest argument for guide 04's final push: had the history lived only on the server, it would now be gone permanently - git without a remote is RAID 0. Last thing worth noticing: your working configs were never at risk during recovery, because `--no-checkout` and index-only `git reset` are both deliberately chosen to leave the working directory alone. Recovery procedures that cannot damage the patient are the ones you can run at 2am.

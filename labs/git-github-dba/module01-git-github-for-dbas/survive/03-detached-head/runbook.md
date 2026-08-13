# Scenario 03 - Detached HEAD: Nobody Knows What's on Disk

**Severity:** MEDIUM
**Expected Recovery Time:** 10-20 minutes
**Single Node:** pg-git-1 only

## Alert

```
A teammate was 'just looking at an old version' of the config repo on
pg-git-1 and left. Now every git command in /opt/pgsql/data warns about a
'detached HEAD', and the config files on disk may NOT match what the team
believes is deployed.
```

## Key Concepts for Revision

- Detached HEAD = HEAD points directly at a COMMIT instead of a branch - you are "standing on" an old snapshot
- While detached, the files on disk reflect that old snapshot - the running server does not care (it keeps its in-memory config), but the NEXT reload/restart would read stale files
- `git status` names the state in its first line - always read it
- `git switch main` reattaches HEAD and restores the files to match main

## Layer 1: Quick Reference

`git status` -> confirm detached -> `git switch main` -> tree clean -> done.

## Layer 2: Step by Step

### 1. Diagnose

On **pg-git-1**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git status | head -3
```

First line: `HEAD detached at <commit>`. Compare what is on disk vs what main believes:

```bash
git diff main
```

Any output = the disk currently differs from your deployed truth. That is the operational risk: a restart right now would load OLD config.

### 2. Fix

```bash
git switch main
```

Git prints `Switched to branch 'main'` and the files snap back to the current state.

### 3. Verify

```bash
git status
```

`On branch main, nothing to commit, working tree clean.` Disk and history agree again. Say **check my fix** to the bot.

## Layer 3: Understanding

How did the teammate get here? Almost certainly `git checkout <old-commit>` to "look at" a previous config - which is a legitimate read-only operation IF you switch back. The state itself is not corruption; it is a parked car left in the middle of the road. The real danger is a commit made WHILE detached: it belongs to no branch, and switching away strands it. If you ever find `git status` reporting a detached HEAD with changes or commits you do not recognize, check `git reflog` before switching - any stranded commit will be there, and `git switch -c rescue <sha>` saves it. Safer habit for reading old versions without moving HEAD at all: `git show <commit>:postgresql.conf | less`.

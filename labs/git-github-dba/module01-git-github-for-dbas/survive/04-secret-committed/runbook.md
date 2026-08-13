# Scenario 04 - Secret Committed: A Password in the Repo

**Severity:** HIGH
**Expected Recovery Time:** 15-25 minutes
**Single Node:** pg-git-1 only

## Alert

```
A plaintext password file (app-password.txt) was just committed to the
pg-git-1 config repo - FORCE-added past your .gitignore - and pushed to
GitHub. Treat it as a real leak.
```

## Key Concepts for Revision

- Step ONE in any credential leak is ROTATION, not git surgery - the secret is compromised the moment it leaves the server
- Deleting a file in a NEW commit does not remove it from the OLD commit - git never forgets
- `git rm` removes a file from the repo tip AND disk; `git rm --cached` removes from the repo but keeps the disk file
- `.gitignore` is a guardrail, not a lock - `git add -f` walks right past it
- Full history cleanup = git-filter-repo + force push + GitHub cache purge + rotation anyway (clones/forks still have it)

## Layer 1: Quick Reference

Rotate (declare it) -> `git rm app-password.txt` -> commit -> push -> know what history still holds.

## Layer 2: Step by Step

### 1. Rotate first

In this lab the password is fictional - but say it out loud: **"in production I change this credential NOW, before touching git."** Rotation is the fix; everything after is hygiene.

### 2. Confirm what happened

On **pg-git-1**, as **ec2-user**:

```bash
sudo su - postgres
```

```bash
cd $PGDATA
```

```bash
git log --oneline | head -3
```

```bash
git show HEAD --stat
```

A new file `app-password.txt` in the newest commit. Note it is TRACKED despite your `*` gitignore - check why:

```bash
git log -1 --pretty=full
```

The committer force-added it (`git add -f` overrides .gitignore). Your guardrail was bypassed, not broken.

### 3. Remove it from the tip

```bash
git rm app-password.txt
```

```bash
git commit -m "remove committed password file"
```

```bash
git push
```

### 4. Verify

```bash
git ls-files | grep password
```

No output - the file is gone from the tip. Also confirm it is off the disk:

```bash
ls app-password.txt
```

`No such file or directory`. Say **check my fix** to the bot.

## Layer 3: Understanding

Is the secret gone? **No.** `git show HEAD~1:app-password.txt` still prints it - the old snapshot exists on the server AND on GitHub, and anyone who cloned in between has it forever. That is why rotation is step one and non-negotiable. When policy demands the history itself be scrubbed (compliance, public repos), the tool is `git-filter-repo --sensitive-data-removal`, followed by a force-push and a GitHub support request to purge cached views - and the rotation still had to happen. GitHub's push protection can block known secret patterns before they land, but it is only automatic on PUBLIC repos; your private config repo is protected by discipline and review, which is why the PR workflow from BUILD guide 03 exists.

# Build 4: Branches, Pull Requests, and Tags (45 min)

From now on, `main` is production. Every change goes through a branch and a pull request (PR), reviewed by you acting as the second DBA. This lab walks the full loop once, then tags your first baseline.

All commands tested on a Mac on 2026-07-22. Outputs are real captured outputs.

---

## Step 1: Create a feature branch

On **your Mac**, in **~/Projects/pg-ops**:

```bash
git switch -c feature/annotate-pg-hba
```

`switch -c` creates a new branch and moves you onto it - your zero-cost dev copy. Branch naming: `feature/`, `fix/`, or `docs/` prefix plus a short description.

Expected output:
```
Switched to a new branch 'feature/annotate-pg-hba'
```

## Step 2: Make a real change on the branch

Edit pg_hba.conf in the repo - add a comment header documenting what each rule is for (a change you would genuinely want reviewed):

```bash
vi config/pgforge-1/pg_hba.conf
```

Add a comment line above the rules, for example `# local trust is for initdb defaults - tighten before app traffic`. Save and quit with `:wq`.

```bash
git add config/pgforge-1/pg_hba.conf
```

```bash
git commit -m "docs: annotate pg_hba rules for pgforge-1"
```

Expected output (yours will differ):
```
    ░    gitleaks
11:14PM INF no leaks found
[feature/annotate-pg-hba 2992f83] docs: annotate pg_hba rules for pgforge-1
 1 file changed, 1 insertion(+)
```

## Step 3: Push the branch to GitHub

```bash
git push -u origin feature/annotate-pg-hba
```

`-u origin <branch>` pushes the branch and links it to GitHub, so future pushes from this branch are just `git push`.

Expected output:
```
remote:
remote: Create a pull request for 'feature/annotate-pg-hba' on GitHub by visiting:
remote:      https://github.com/hafopezi10/pg-ops/pull/new/feature/annotate-pg-hba
remote:
To https://github.com/hafopezi10/pg-ops.git
 * [new branch]      feature/annotate-pg-hba -> feature/annotate-pg-hba
branch 'feature/annotate-pg-hba' set up to track 'origin/feature/annotate-pg-hba'.
```

GitHub itself is suggesting the pull request. We will create it from the command line instead.

## Step 4: Open the pull request

```bash
gh pr create --fill
```

`--fill` uses your commit message as the PR title and body.

Expected output (a URL - yours will differ):
```
https://github.com/hafopezi10/pg-ops/pull/1
```

## Step 5: Review it like a second DBA

Open that URL in your browser. Click the "Files changed" tab. Read the diff line by line and ask: would I approve this if a junior DBA sent it? This 60 seconds of review is the entire point of the PR habit.

## Step 6: Merge and clean up

Back in **Terminal**:

```bash
gh pr merge --squash --delete-branch
```

`--squash` lands the whole branch as ONE clean commit on main. `--delete-branch` removes the branch afterward, local and remote.

Expected output (yours will differ):
```
Updating 8145740..1bf5818
Fast-forward
 config/pgforge-1/pg_hba.conf | 1 +
 1 file changed, 1 insertion(+)
```

Confirm you are back on main and synced:

```bash
git switch main
```

```bash
git pull
```

Expected output:
```
Already on 'main'
Your branch is up to date with 'origin/main'.
Already up to date.
```

## Step 7: Tag the first baseline

A tag is a NAMED restore point - like a labeled recovery target. Releases get tags.

```bash
git tag -a v1.0.0 -m "first reviewed baseline: pgforge-1 configs versioned, tuned, and annotated"
```

`-a` makes an annotated tag: it stores who, when, and why - not just a label.

```bash
git push origin v1.0.0
```

Expected output:
```
To https://github.com/hafopezi10/pg-ops.git
 * [new tag]         v1.0.0 -> v1.0.0
```

You can always return to exactly this state with `git checkout v1.0.0`.

BUILD is complete. Repeat the branch-PR-merge loop for every future change: one runbook and one decision doc through the loop are part of the done-when checklist. Then move to the USE exercises.

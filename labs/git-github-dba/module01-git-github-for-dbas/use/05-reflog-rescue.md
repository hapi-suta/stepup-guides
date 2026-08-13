# Exercise 05: The Reflog Rescue

**Duration:** 15 minutes
**Objective:** "Destroy" committed work with reset --hard, then recover it from the reflog - unassisted this time.
**Prerequisites:** BUILD guide 02 completed (`~/git-practice` exists). Single node. Work as **ec2-user** on **pg-git-1**.

## Background

Someday you (or a teammate) will run `git reset --hard` at the wrong moment. This exercise builds the muscle memory - and the calm - to fix it. We use the PRACTICE repo, not the config repo.

On **pg-git-1**, as **ec2-user**:

```bash
cd ~/git-practice
```

## Question 1: Create something worth losing

Open `server-notes.md` with vi and add a line you would hate to retype, e.g. `Connection pool sizing: pool_size = (cores * 2) + spindles`. Commit it:

### Try it

```bash
git add server-notes.md
```

```bash
git commit -m "add connection pool sizing formula"
```

```bash
git log --oneline | head -2
```

Write down the short commit ID you see.

## Question 2: The accident

### Try it

```bash
git reset --hard HEAD~1
```

```bash
git log --oneline | head -2
```

Your commit is gone from the log, and the line is gone from the file. On an unversioned server this would simply be lost work.

## Question 3: The rescue

Find the "lost" commit and bring it back. You know the tools - do it before reading the expected output.

### Try it

```bash
git reflog | head -5
```

Expected output (yours will differ):

```
d33915b HEAD@{0}: reset: moving to HEAD~1
f32e770 HEAD@{1}: commit: add connection pool sizing formula
...
```

```bash
git reset --hard 'HEAD@{1}'
```

```bash
git log --oneline | head -2
```

The commit is back at the top, and the formula is back in the file. Compare the ID with what you wrote down in question 1 - identical. It was never gone.

## Question 4 (thought exercise)

Why did this work? Where was the commit living while it was "deleted"? And what is the ONE case where committed work truly can be lost? (Hint: reflog entries expire after ~90 days, and `.git` itself can be deleted - which is why guide 03 put a copy on GitHub.)

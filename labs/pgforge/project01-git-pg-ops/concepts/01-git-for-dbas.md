# Concepts: Git for a DBA (20 min)

Read this before touching the terminal. No commands to run.

Git is PITR for your files. Every commit is a restore point you can inspect or return to, forever. That is the whole idea - the rest is vocabulary.

---

## 1. A repository

A repository (repo) is a folder Git watches. The entire history lives in a hidden `.git` folder inside it. Think of it as the data directory plus its complete WAL archive, in one place. Delete `.git` and the history is gone - just plain files left.

## 2. A commit is a snapshot, not a diff

When you commit, Git saves the full state of your files at that moment, with an ID, an author, a date, and a message. A labeled restore point. You will have hundreds of them.

## 3. The three zones

Files move through three zones:

1. **Working directory** - what is on disk right now
2. **Staging area** - what you marked for the next commit with `git add`
3. **History** - committed

DBA version: uncommitted changes in a session, then changes you reviewed and queued, then a committed transaction.

`git status` shows what is in which zone. It is your pg_stat_activity - run it constantly.

## 4. A branch is a dev copy of prod that costs nothing

Make a branch, experiment freely, then merge it back or throw it away. The default branch is `main`. Treat main like production: nothing lands on it without review, even when the reviewer is you.

## 5. A remote is your offsite replica

GitHub holds a copy of your repo. `push` sends your commits up. `pull` brings down what is there. A pushed commit survives your laptop dying - same reason WAL goes to S3.

## 6. Two ways to undo - know the difference cold

- `git revert` adds a NEW commit that undoes an old one. History stays complete.
- `git reset` rewinds history as if the commit never happened - like PITR to before the mistake. Fine on your own machine. Dangerous on anything already pushed.

When in doubt: revert.

---

## Checkpoint

Answer these from memory. If any answer is fuzzy, re-read the section, then move to BUILD.

1. What is the difference between the working directory and the staging area?
2. Why is revert safer than reset on a shared branch?
3. In DBA terms, what is a remote?
4. A commit is a ______, not a ______.

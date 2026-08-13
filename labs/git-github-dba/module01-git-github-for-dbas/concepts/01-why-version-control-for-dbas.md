# Concepts 01: Why Version Control for DBAs

**Time:** 15 minutes
**Phase:** Concepts (read before BUILD)

---

## The 2am story

It is 2:07am. Replication is broken, the app cannot connect, and PagerDuty will not stop ringing. You open `pg_hba.conf` and something looks... different. But different from what? You have no copy of yesterday's file. You do not know what changed, when it changed, or who changed it.

Now imagine the same night with version control:

```
git log --oneline pg_hba.conf
```

```
9f3c2a1 tighten app subnet to 10.0.2.0/24
b7e10dd allow replication from standby 10.0.1.15
4a90c3f baseline: pg_hba.conf as installed
```

One command shows every change ever made to that file, who made it, and when. One more command (`git diff`) shows exactly which lines changed. One more (`git revert`) puts the old version back. The incident is over in minutes, and you can prove what happened.

That is what this module gives you.

## What version control actually is

A version control system (VCS) records changes to files over time so you can recall any specific version later. Think of it as a time machine plus an audit trail for a directory.

Git is the VCS that won. It runs everywhere, it is free, and it is what GitHub, GitLab, and every DevOps pipeline in the industry is built on. The official documentation lives at git-scm.com, and the free Pro Git book (git-scm.com/book) is the canonical reference.

Two facts about git that surprise people:

1. **Git stores snapshots, not differences.** Every commit is a full picture of all your tracked files at that moment. Git is smart about storage, but mentally: each commit = a complete photo of the project.
2. **Git is distributed.** Every copy of a repository contains the complete history. Your server has it all, GitHub has it all. Either one alone is enough to recover everything.

## Why a DBA specifically should care

You already think in version-control terms every day. The concepts map almost one-to-one:

| You already know... | In git that is... |
|---|---|
| A checkpoint / savepoint | A commit - a named point you can return to |
| The WAL / audit log | `git log` - the ordered history of every change |
| A compensating transaction | `git revert` - a new change that undoes an old one |
| Point-in-time recovery | `git checkout <commit>` - view the world as of any moment |
| A full backup | A clone - every copy holds the complete history |

And the problems git solves are problems you already have:

- **"Who changed this setting and when?"** - `git blame postgresql.conf` answers it per line.
- **"What did this file look like before the incident?"** - `git show yesterday's-commit:pg_hba.conf`.
- **"Put it back the way it was."** - `git revert`, and the bad change is undone with a paper trail.
- **"The server died. Where are my configs?"** - `git clone` from GitHub and they are all back, with history.
- **Change control** - propose a config change on a branch, have a colleague review it as a pull request, merge it only after approval. That is real change management, for free.

## What we will version control in this module

PostgreSQL keeps its most important configuration as plain text files inside the data directory (on our CentOS servers: `/opt/pgsql/data`):

- **postgresql.conf** - the main server configuration (memory, connections, logging, ...)
- **pg_hba.conf** - host-based authentication: who may connect, from where, and how
- **postgresql.auto.conf** - settings written by `ALTER SYSTEM` (postgres edits this file itself - and git will show you every time it does)

Plain text files are exactly what git is best at. By the end of the module, every change to these files on your server will be recorded, reviewable, revertible, and backed up to your own GitHub account.

## What git is NOT

- Git is **not a backup tool for your database**. We version the configuration files, never the data files. (Your data is binary, huge, and changes constantly - that is what pg_basebackup and WAL archiving are for.)
- Git is **not automatic**. It records a snapshot only when you commit. The discipline of committing before and after every change is the habit this module builds.
- Git does **not need a network**. Everything except push/pull happens locally on your server, instantly.

## Vocabulary you will meet in BUILD

- **repository (repo)** - a directory whose history git is tracking. The history lives in a hidden `.git` folder inside it.
- **commit** - one recorded snapshot, with an author, a timestamp, and a message.
- **branch** - a movable label pointing at a commit. You will use branches to test config changes safely.
- **remote** - another copy of the repo somewhere else (for us: GitHub).
- **push / pull** - send your commits to the remote / bring its commits to you.

Do not memorize these now. You will type each one with your own hands in the BUILD guides.

## References (canonical docs)

- What is version control: https://git-scm.com/book/en/v2/Getting-Started-About-Version-Control
- What is Git (snapshots, not deltas): https://git-scm.com/book/en/v2/Getting-Started-What-is-Git%3F
- Pro Git book (free, the reference): https://git-scm.com/book

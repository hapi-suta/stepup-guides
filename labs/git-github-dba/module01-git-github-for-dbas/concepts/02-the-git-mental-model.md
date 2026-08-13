# Concepts 02: The Git Mental Model

**Time:** 20 minutes
**Phase:** Concepts (read before BUILD guides 01-02)

---

Most git confusion comes from typing commands without a picture of what they do. This doc gives you the picture. There are only four ideas: snapshots, the three areas, branches as pointers, and merging.

## Idea 1: Commits are snapshots

Every commit is a complete photo of all tracked files at that moment, plus:

- who took it (author name + email - this is why git demands you configure them first)
- when
- a message saying why
- a unique ID (a hash like `9f3c2a1...`)
- a pointer to the commit that came before it

So a repository's history is a chain of photos, newest pointing back to oldest:

```
4a90c3f  <--  b7e10dd  <--  9f3c2a1
(baseline)    (allow standby)  (tighten subnet)
```

`git log` walks this chain. `git show 9f3c2a1` opens one photo. Nothing you have committed is ever lost by accident - the photo album only grows.

## Idea 2: The three areas

This is the single most important diagram in git. A file's change passes through three places:

```
 Working directory  --git add-->  Staging area  --git commit-->  Repository
 (the real files                  (the box you                   (the photo
  you edit with vi)                are packing)                   album, .git/)
```

- **Working directory** - the actual files on disk. You edit `postgresql.conf` with vi here.
- **Staging area** (also called the index) - a loading dock. `git add postgresql.conf` says "include this file's current content in the next photo".
- **Repository** - `git commit` seals the box: everything staged becomes one permanent snapshot.

Why the two-step add/commit? So you can change five files but commit them as two separate, cleanly-described snapshots. For config work it keeps each commit small enough that `git log` reads like a change journal.

Three consequences beginners trip on:

1. **"Changes not staged for commit"** in `git status` just means: you edited a file but have not run `git add` yet.
2. If you edit a file AFTER `git add`, the new edit is not staged. Run `git add` again.
3. `git diff` shows working directory vs staging. `git diff --staged` shows staging vs the last commit. Different questions, different commands.

When in doubt, run `git status`. It is always safe, and it tells you the state of all three areas and usually the next command to run.

## Idea 3: The .git directory

`git init` in a directory creates one hidden folder, `.git/`, and nothing else. That folder IS the repository: all history, all configuration, all branches live inside it. The rest of your directory is just the working copy.

Two facts that matter for us as DBAs:

- Delete `.git/` and the directory is no longer a repository - your files are untouched, but all history is gone (unless it was pushed to a remote - a SURVIVE scenario in this module).
- Backup tools that copy your data directory (like pg_basebackup) will copy `.git/` along with it, because to them it is just another folder. Good to know, not a problem - we keep the repo tiny by only tracking config files.

## Idea 4: Branches are movable pointers

A branch is NOT a copy of your files. It is a sticky note with a name on it, stuck to one commit. The default branch is called `main` (older setups say `master`).

`HEAD` is git's name for "the sticky note you are currently standing on".

```
                      main (HEAD)
                        |
4a90c3f <-- b7e10dd <-- 9f3c2a1
```

When you commit, the sticky note moves forward to the new snapshot. When you create a branch (`git switch -c tuning-test`), git just writes a second sticky note on the same commit - instant, free:

```
                      main
                        |
4a90c3f <-- b7e10dd <-- 9f3c2a1
                        |
                      tuning-test (HEAD)
```

Now commits made on `tuning-test` move only that note. `main` stays where it was - your known-good configuration is untouched while you experiment. Switching branches (`git switch main`) changes which snapshot your working files reflect.

This is why branches are the DBA's safety net: test a risky `postgresql.conf` change on a branch; `main` still holds the config you trust.

## Idea 5: Merging (and the two kinds)

`git merge tuning-test` (run while standing on `main`) brings the branch's commits into main.

- **Fast-forward:** if `main` has not moved since you branched, git just slides the `main` sticky note forward. No new commit, nothing to resolve.
- **Three-way merge:** if BOTH branches gained commits, git combines them using their common ancestor and creates a merge commit with two parents.

**Conflicts** happen only when both branches changed the SAME lines of the SAME file. Git refuses to guess. It marks the disputed lines in the file:

```
<<<<<<< HEAD
shared_buffers = 256MB
=======
shared_buffers = 512MB
>>>>>>> tuning-test
```

You edit the file, keep the right content, delete the marker lines, `git add`, `git commit`. That is the whole procedure. And if you panic: `git merge --abort` returns everything to the moment before the merge. You will do this with your own hands in BUILD guide 02.

## The undo ladder (know which rung you are on)

Git has three "undo" commands. They are not interchangeable, and one of them destroys work:

| Command | Undoes | Safe? |
|---|---|---|
| `git restore <file>` | uncommitted edits in your working directory | **DESTROYS those edits.** No undo. Be sure. |
| `git restore --staged <file>` | un-stages a file (keeps your edits) | Safe |
| `git revert <commit>` | a committed change, by adding a new opposite commit | Safe, even after pushing. **The DBA default.** |
| `git reset --hard <commit>` | rewinds the branch AND your files to an old commit | Destroys everything after that point. Local emergencies only, never on pushed history. |

Rule of thumb: once something is committed, prefer `revert` - it is the compensating transaction of git, and it leaves the audit trail intact. Reach for `reset --hard` the way you would reach for PITR: deliberately, and understanding exactly what will be lost.

One safety net to remember: `git reflog` records where HEAD has been, even through resets. Committed work is almost never truly gone. You will use it in a SURVIVE scenario.

## References (canonical docs)

- Recording changes (three areas, status, add, commit): https://git-scm.com/book/en/v2/Git-Basics-Recording-Changes-to-the-Repository
- Branches in a nutshell (pointers, HEAD): https://git-scm.com/book/en/v2/Git-Branching-Branches-in-a-Nutshell
- Basic branching and merging (fast-forward, conflicts): https://git-scm.com/book/en/v2/Git-Branching-Basic-Branching-and-Merging
- Undoing things: https://git-scm.com/book/en/v2/Git-Basics-Undoing-Things
- git-restore / git-revert / git-reset manual pages: https://git-scm.com/docs/git-restore https://git-scm.com/docs/git-revert https://git-scm.com/docs/git-reset

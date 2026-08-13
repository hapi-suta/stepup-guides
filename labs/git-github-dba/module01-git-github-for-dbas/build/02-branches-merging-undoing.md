# Module 01 - Git & GitHub for DBAs
## Guide 02: Branches, Merging, and Undoing

**Objective:** Test changes safely on branches, merge them (including resolving a real conflict), shelve work with stash, and learn the three undo commands and when each is safe.
**Time:** 40-45 minutes
**Prerequisites:**
- Guide 01 completed: `~/git-practice` exists with two commits
- You read Concepts 02 (branches are movable pointers)

---

## 1. Where you are

On **pg-git-1**, as **ec2-user**, go to your practice repository:

```bash
cd ~/git-practice
```

List the branches. The `*` marks the one you are on:

```bash
git branch
```

Expected output (yours will differ):

```
* main
```

## 2. Create a branch and work on it

`git switch -c` creates a new branch and moves you onto it in one step (`-c` = create):

```bash
git switch -c tuning-notes
```

Expected output (yours will differ):

```
Switched to a new branch 'tuning-notes'
```

```bash
git branch
```

Expected output (yours will differ):

```
  main
* tuning-notes
```

Now make a change on this branch. Open the notes file with vi and add these lines at the bottom (in vi: `i` to insert, `Esc` then `:wq` to save):

```bash
vi server-notes.md
```

```
## Tuning ideas

- shared_buffers: default 128MB is low for this box
```

Stage and commit it:

```bash
git add server-notes.md
```

```bash
git commit -m "start a tuning ideas section"
```

Expected output (yours will differ):

```
[tuning-notes b67f374] start a tuning ideas section
 1 file changed, 4 insertions(+)
```

Notice the commit landed on `tuning-notes`, not `main`. See the whole picture (`--all` shows every branch, `--graph` draws the shape):

```bash
git log --oneline --all --graph
```

Expected output (yours will differ):

```
* b67f374 start a tuning ideas section
* 3d889bf note that backups are not configured yet
* e22dad2 add server notes for pg-git-1
```

## 3. Switch back: main is untouched

```bash
git switch main
```

Expected output (yours will differ):

```
Switched to branch 'main'
```

Look at the end of the file:

```bash
tail -4 server-notes.md
```

Expected output (yours will differ):

```
PostgreSQL 16 data directory: /opt/pgsql/data
Port: 5432

Backups: not configured yet
```

The tuning section is GONE - because on `main` it was never added. Your files on disk follow whichever branch you are standing on. This is the safety net: experiments on a branch cannot touch the version you trust.

## 4. Merge: the fast-forward case

Bring the branch's work into `main`. You merge INTO the branch you are standing on, so make sure `git branch` shows you on `main` first:

```bash
git merge tuning-notes
```

Expected output (yours will differ):

```
Updating 3d889bf..b67f374
Fast-forward
 server-notes.md | 4 ++++
 1 file changed, 4 insertions(+)
```

**Fast-forward**: `main` had not moved since you branched, so git simply slid the `main` pointer up to your branch's commit. No new commit was needed. The branch has served its purpose - delete the label (`-d` only deletes branches that are fully merged, so it is safe):

```bash
git branch -d tuning-notes
```

Expected output (yours will differ):

```
Deleted branch tuning-notes (was b67f374).
```

## 5. Set up a real conflict

Now the case every DBA needs to have survived once BEFORE it happens in production: two branches change the SAME line. First create a small settings file with vi (`i`, type the line, `Esc`, `:wq`):

```bash
vi settings-notes.md
```

```
work_mem = 4MB
```

```bash
git add settings-notes.md
```

```bash
git commit -m "record current work_mem"
```

Create a branch proposing one value:

```bash
git switch -c raise-work-mem
```

Edit `settings-notes.md` with vi and change the line to `work_mem = 8MB`:

```bash
vi settings-notes.md
```

```bash
git add settings-notes.md
```

```bash
git commit -m "propose work_mem 8MB"
```

Switch back to `main` and change the SAME line to a DIFFERENT value, `work_mem = 16MB`:

```bash
git switch main
```

```bash
vi settings-notes.md
```

```bash
git add settings-notes.md
```

```bash
git commit -m "propose work_mem 16MB"
```

Both branches have now moved since they parted, and they disagree about one line.

## 6. The conflict, and how to resolve it calmly

```bash
git merge raise-work-mem
```

Expected output (yours will differ):

```
Auto-merging settings-notes.md
CONFLICT (content): Merge conflict in settings-notes.md
Automatic merge failed; fix conflicts and then commit the result.
```

Do not panic. Run the orientation command:

```bash
git status
```

Expected output (yours will differ):

```
On branch main
You have unmerged paths.
  (fix conflicts and run "git commit")
  (use "git merge --abort" to abort the merge)

Unmerged paths:
	both modified:   settings-notes.md
```

Git tells you everything: which file is disputed (`both modified`), and your two exits - fix it, or abort. Look at what git did to the file:

```bash
cat settings-notes.md
```

Expected output (yours will differ):

```
<<<<<<< HEAD
work_mem = 16MB
=======
work_mem = 8MB
>>>>>>> raise-work-mem
```

Between `<<<<<<<` and `=======` is YOUR side (`HEAD` = main). Between `=======` and `>>>>>>>` is the branch's side. Git refuses to guess - you decide. Open the file with vi, delete ALL five lines, and leave only the value you decide is right:

```bash
vi settings-notes.md
```

```
work_mem = 8MB
```

Mark it resolved by staging it, then commit. Run `git commit` WITHOUT `-m` this time - git opens vi with a pre-written merge message. Just save and quit with `:wq`:

```bash
git add settings-notes.md
```

```bash
git commit
```

Expected output (yours will differ):

```
[main a14fa13] Merge branch 'raise-work-mem'
```

That is the entire procedure: status, edit out the markers, add, commit. See the shape of what you did:

```bash
git log --oneline --graph
```

Expected output (yours will differ):

```
*   a14fa13 Merge branch 'raise-work-mem'
|\
| * 47a0e77 propose work_mem 8MB
* | 1ed3775 propose work_mem 16MB
|/
* 0235137 record current work_mem
...
```

A commit with two parents - a **three-way merge**. Compare with the fast-forward earlier: this time both sides had moved, so git created a merge commit. Clean up the branch:

```bash
git branch -d raise-work-mem
```

## 7. The escape hatch: merge --abort

Once more, fast - but this time you will back out instead of resolving. Create the conflict:

```bash
git switch -c lower-work-mem
```

Edit `settings-notes.md` with vi: change the line to `work_mem = 2MB`. Then:

```bash
git add settings-notes.md
```

```bash
git commit -m "propose work_mem 2MB"
```

```bash
git switch main
```

Edit the same line with vi to `work_mem = 32MB`. Then:

```bash
git add settings-notes.md
```

```bash
git commit -m "propose work_mem 32MB"
```

```bash
git merge lower-work-mem
```

Expected output (yours will differ):

```
CONFLICT (content): Merge conflict in settings-notes.md
Automatic merge failed; fix conflicts and then commit the result.
```

This time, decide you want out. It is 2am, you are not sure, you want everything back the way it was:

```bash
git merge --abort
```

```bash
git status
```

Expected output (yours will differ):

```
On branch main
nothing to commit, working tree clean
```

Everything is exactly as it was before the merge. Remember this command - it turns a scary moment into a non-event. Delete the unwanted branch. Because it was never merged, lowercase `-d` refuses; capital `-D` means "yes, discard its work":

```bash
git branch -D lower-work-mem
```

Expected output (yours will differ):

```
Deleted branch lower-work-mem (was e856bad).
```

## 8. git stash: shelve work you are not ready to commit

You are mid-edit when something urgent comes up. Simulate it - add a line to `server-notes.md` with vi (any line, e.g. `# scratch idea, not ready`), then shelve everything:

```bash
git stash
```

Expected output (yours will differ):

```
Saved working directory and index state WIP on main: 504093b propose work_mem 32MB
```

```bash
git status
```

Expected output (yours will differ):

```
On branch main
nothing to commit, working tree clean
```

Clean tree - your half-done edit is in the stash drawer, and you are free to handle the emergency. See the drawer, then take the work back out:

```bash
git stash list
```

Expected output (yours will differ):

```
stash@{0}: WIP on main: 504093b propose work_mem 32MB
```

```bash
git stash pop
```

Expected output (yours will differ):

```
On branch main
Changes not staged for commit:
	modified:   server-notes.md
Dropped refs/stash@{0} (00d34d8f28191d53b6196c1394ae8881fb5a4f21)
```

Your edit is back, and the stash entry was dropped.

## 9. The undo ladder, rung by rung

**Rung 1 - `git restore`: discard uncommitted edits.** That scratch line you just popped - you decide you do not want it. WARNING: restore permanently throws away uncommitted changes to that file. There is no undo for this one:

```bash
git restore server-notes.md
```

```bash
git status
```

Expected output (yours will differ):

```
On branch main
nothing to commit, working tree clean
```

**Rung 2 - `git revert`: undo a COMMITTED change, safely.** Your `work_mem = 32MB` commit was a bad idea. Revert creates a NEW commit containing the opposite change - history is preserved, the audit trail shows both the mistake and the correction. This is the DBA default, and the only safe undo on anything already pushed or shared:

```bash
git revert --no-edit HEAD
```

Expected output (yours will differ):

```
[main d33915b] Revert "propose work_mem 32MB"
 1 file changed, 1 insertion(+), 1 deletion(-)
```

(`--no-edit` accepts the auto-generated message; without it, vi opens.)

```bash
git log --oneline | head -4
```

Expected output (yours will differ):

```
d33915b Revert "propose work_mem 32MB"
504093b propose work_mem 32MB
a14fa13 Merge branch 'raise-work-mem'
1ed3775 propose work_mem 16MB
```

Both the mistake and its undo are on the record. That is a feature, not clutter.

**Rung 3 - `git reset --hard`: the dangerous one.** It moves the branch pointer backward and makes your files match - commits after that point vanish from the branch. Watch it happen on a throwaway commit. Create one:

```bash
vi temp.txt
```

(Type `temporary note`, save with `:wq`.)

```bash
git add temp.txt
```

```bash
git commit -m "add a temporary note"
```

Now rewind the branch by one commit. `HEAD~1` means "one commit before where I am now":

```bash
git reset --hard HEAD~1
```

Expected output (yours will differ):

```
HEAD is now at d33915b Revert "propose work_mem 32MB"
```

```bash
ls
```

Expected output (yours will differ):

```
server-notes.md  settings-notes.md
```

`temp.txt` is gone - file AND commit. This is why the rule is: `reset --hard` on local, unshared work only, and only when you are certain. Never on anything pushed.

## 10. The safety net under the ladder: git reflog

Was that commit really destroyed? Almost never. The reflog records every place HEAD has been:

```bash
git reflog | head -5
```

Expected output (yours will differ):

```
d33915b HEAD@{0}: reset: moving to HEAD~1
f32e770 HEAD@{1}: commit: add a temporary note
d33915b HEAD@{2}: revert: Revert "propose work_mem 32MB"
504093b HEAD@{3}: reset: moving to HEAD
```

There it is at `HEAD@{1}` - the commit the reset "destroyed". Bring it back:

```bash
git reset --hard 'HEAD@{1}'
```

Expected output (yours will differ):

```
HEAD is now at f32e770 add a temporary note
```

```bash
ls
```

Expected output (yours will differ):

```
server-notes.md  settings-notes.md  temp.txt
```

Recovered. The lesson that should lower your blood pressure permanently: **once something is committed, it is almost impossible to truly lose it.** We do not actually want the temporary note, so put the branch back where it belongs (this reset points at the reflog entry we came from):

```bash
git reset --hard 'HEAD@{1}'
```

## 11. Tags: name the states you trust

Before a maintenance window, you want a named marker for "this exact state is known good". That is an annotated tag (`-a` = annotated, `-m` = its message):

```bash
git tag -a v1.0 -m "known good practice repo"
```

```bash
git tag
```

Expected output (yours will differ):

```
v1.0
```

```bash
git show v1.0 | head -8
```

Expected output (yours will differ):

```
tag v1.0
Tagger: Felicite Nji <felicite.suta@gmail.com>
Date:   Thu Aug 13 01:00:45 2026 +0000

known good practice repo

commit d33915b1f484c25cef57014189163150c7536701
Author: Felicite Nji <felicite.suta@gmail.com>
```

Unlike a branch, a tag never moves. `v1.0` will point at this exact snapshot forever - your named restore point.

## 12. Checkpoint

```bash
git log --oneline
```

Expected output (yours will differ):

```
d33915b Revert "propose work_mem 32MB"
504093b propose work_mem 32MB
a14fa13 Merge branch 'raise-work-mem'
1ed3775 propose work_mem 16MB
47a0e77 propose work_mem 8MB
0235137 record current work_mem
b67f374 start a tuning ideas section
3d889bf note that backups are not configured yet
e22dad2 add server notes for pg-git-1
```

Nine commits telling the full story, including one merge and one revert - plus a `v1.0` tag.

**You now know:** branches as safe experiments, fast-forward vs three-way merges, resolving AND aborting conflicts, stash, the undo ladder (restore / revert / reset), reflog recovery, and tags.

Next guide: GitHub - getting this history off the server.

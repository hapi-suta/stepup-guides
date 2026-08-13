# USE Phase Checklist - Git & GitHub for DBAs

Work through the five exercises in order. Check each skill off only when you performed it yourself, without copying from the BUILD guides.

## Exercise 01 - The Blame Hunt
- [ ] Found who/when changed shared_buffers with `git blame`
- [ ] Inspected the full commit with `git show <id>`
- [ ] Listed one file's history with `git log --oneline -- <file>`

## Exercise 02 - pg_hba Lockout Forensics
- [ ] Reproduced a real lockout (local trust -> md5) and read both error messages
- [ ] Identified the culprit change with `git diff HEAD~1 HEAD` while locked out of SQL
- [ ] Recovered with `git revert` + `pg_ctl reload` (no SQL needed)

## Exercise 03 - Tag Before the Maintenance Window
- [ ] Created an annotated pre-maintenance tag
- [ ] Generated the "what changed since the tag" report with `git diff <tag>`
- [ ] Pushed commit and tag separately to GitHub

## Exercise 04 - The Pickaxe Hunt
- [ ] Found every commit touching a setting with `git log -S`
- [ ] Read a single file's full patch history with `git log -p -- <file>`
- [ ] Narrowed a pickaxe search to an exact line

## Exercise 05 - The Reflog Rescue
- [ ] Destroyed a commit with `git reset --hard`
- [ ] Located it in `git reflog`
- [ ] Restored it and verified the commit ID matched

## Exit criteria

You are ready for SURVIVE when you can answer, from memory, in one sentence each:

1. Which command answers "who changed this line"?
2. Which undo command is safe on pushed history?
3. How do you reload pg_hba.conf when psql is locked out?
4. Why does `git push` not send your tags?
5. Where does a "destroyed" commit live, and for how long?

## Confirm completion

When every box above is checked and you can answer all five questions, confirm on **pg-git-1**, as **ec2-user**:

```bash
echo "USE phase complete: I am ready for SURVIVE"
```

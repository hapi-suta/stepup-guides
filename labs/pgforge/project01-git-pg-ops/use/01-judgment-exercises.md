# USE: Judgment Exercises (60 min)

No new commands. USE is where you decide like a professional. Each exercise produces a short document that you land through the branch-PR-merge loop from Build 3 - so the loop becomes muscle memory while you think.

---

## Exercise 1: What belongs in the repo?

You have five things:

1. Your postgresql.conf tuning templates
2. A backup script with an S3 bucket name inside it
3. A .pgpass file
4. A runbook that mentions customer names
5. Your crontab

For each one, decide: goes in as-is, goes in after cleaning, or never goes in. Write your five answers with one sentence of reasoning each into `docs/what-belongs-here.md`. Land it via PR.

## Exercise 2: The 2am rule

Production is down at 2am and the fix is a config change. Do you branch-PR-merge first, or fix production first and record it in Git right after?

Decide your rule and write it into `runbooks/emergency-changes.md`. Land it via PR.

Guidance: fix production first, record the change in Git immediately after, and say exactly that in the runbook - so it is a written policy, not a habit that depends on who is on call.

## Exercise 3: Commit messages a stranger can use

Look at every commit message in your repo so far:

```bash
git log --oneline
```

For each one, ask: six months from now, would this message tell me WHY the change happened? "update conf" tells you nothing. "perf: raise work_mem for month-end reporting spike" tells you everything.

You cannot cleanly change messages that are already pushed - so the lesson is forward-looking: write the message for the stranger who reads it later. That stranger is usually you.

Write your three rules for good commit messages into `docs/commit-message-rules.md`. Land it via PR.

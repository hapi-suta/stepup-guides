# SURVIVE 1: The Bad Parameter Change (30 min)

**Scenario:** a tuning change was reviewed on a bad day and merged. Now the template on main is dangerous, and anything provisioned from it will have a broken config. Find it, undo it, keep the history.

Have a timer ready. You will record your recovery time - that number goes in your notes.

Tested end to end on 2026-07-22. Outputs are real.

---

## Inject the failure

On **your Mac**, in **~/Projects/pg-ops**:

```bash
git switch -c fix/bad-tune
```

Open the OLTP template and set shared_buffers to something absurd for a 16GB host:

```bash
vi config/pgforge-1/postgresql.conf
```

Change `shared_buffers = 256MB` to `shared_buffers = 128GB` - absurd for a 2GB test server. Save and quit with `:wq`.

```bash
git add -u
```

`-u` stages every file Git already tracks that you changed - fine here because you changed exactly one.

```bash
git commit -m "perf: raise shared_buffers"
```

Note the message is vague on purpose - that is part of the scenario.

```bash
git switch main
```

```bash
git merge fix/bad-tune
```

Expected output (yours will differ):
```
Updating 1bf5818..9ec2853
Fast-forward
 config/pgforge-1/postgresql.conf | 2 +-
 1 file changed, 1 insertion(+), 1 deletion(-)
```

The bad change is now on main. The incident has begun. **Start your timer.**

---

## Recover

### Step 1: Find the offending commit

```bash
git log --oneline -3
```

`-3` shows the last three commits.

Expected output (your IDs will differ):
```
9ec2853 perf: raise shared_buffers
1bf5818 feat: add data-warehouse tuning template (#1)
8145740 perf: raise work_mem 16MB->32MB for OLTP sort-heavy workloads
```

The top one is the suspect. Inspect it:

```bash
git show HEAD
```

You will see `-shared_buffers = 256MB` and `+shared_buffers = 128GB`. Found it.

### Step 2: Revert it - not reset

```bash
git revert --no-edit HEAD
```

`revert` creates a NEW commit that undoes the bad one. History stays complete - the mistake and the fix are both on record, which is exactly what you want for an audit trail. `--no-edit` accepts the default message.

Expected output (yours will differ):
```
[main 1acdd71] Revert "perf: raise shared_buffers"
 1 file changed, 1 insertion(+), 1 deletion(-)
```

### Step 3: Prove the fix

```bash
grep '^shared_buffers' config/pgforge-1/postgresql.conf
```

Expected output:
```
shared_buffers = 256MB
```

Bonus reality check: had the bad value reached the server, PostgreSQL would refuse to start on restart - a 128GB shared_buffers cannot be allocated on a 2GB host. The repo caught it before the server ever saw it. That is the point of the review.

Back to the safe value. **Stop your timer.**

### Step 4: Push and record

```bash
git push
```

Write your recovery time into `docs/drill-times.md` (create it, land via PR):

```
2026-07-XX drill: bad parameter merged to main. Found + reverted + pushed in M minutes S seconds.
```

---

## What you practiced

Finding a bad change in history, undoing it without destroying the record, and proving the fix - the exact loop you will run when it is a production parameter and not a drill. Interview version: "I reverted rather than reset, because the audit trail matters more than a clean-looking history."

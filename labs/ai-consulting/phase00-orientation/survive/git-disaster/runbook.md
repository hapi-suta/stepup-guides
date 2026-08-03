# SURVIVE Runbook: A Secret Got Committed to Git

**Phase 0 - SURVIVE scenario 2 of 3**

## The situation

You (or a teammate) hard-coded an API key into a file and committed it to git. Now that secret lives in your history, and if you push it to GitHub, it is exposed to anyone who can see the repo. Attackers scan public GitHub for leaked keys within minutes.

This runbook teaches you to remove the secret from the tracked files, stop tracking the file, and move the secret to an **environment variable** where it belongs. It also shows how to scrub it from history.

Every command block tells you **which server** and **which user** you are. You do all of this on your **lab server** as **ec2-user**.

> **Rule for real life:** if a real secret was ever committed and pushed, treat it as compromised and **rotate (regenerate) the key immediately**. Removing it from git is not enough - it may already be copied. In this lab the key is fake, so we only practice the git side.

---

## Step 1: Reproduce the problem

On your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/git-disaster/inject.sh
```

(Adjust the path if your scenario copy lives elsewhere.)

This creates `~/survive-git-lab` with a fake secret committed into its history.

---

## Step 2: Move into the repo and find the secret

On your **lab server**, as **ec2-user**:

```bash
cd ~/survive-git-lab
```

Now search the tracked files for the leaked key. `git grep` searches only files git tracks.

```bash
git grep "API_KEY"
```

Expected output (yours will differ):

```
config.py:API_KEY = "sk-fake-1234567890ABCDEFsecretDONOTCOMMIT"
```

Confirm the secret is also in history, not just the current file:

```bash
git log --oneline -- config.py
```

`git log --oneline` lists commits, one per line. `-- config.py` limits it to that file.

Expected output (yours will differ):

```
c3d4e5f Add DB port to config
a1b2c3d Add config with API key
```

Two commits touched `config.py`. The secret is baked into history.

---

## Step 3: Move the secret out of the file

Open the file and remove the hard-coded key, replacing it with a lookup from the environment.

Still on your **lab server**, as **ec2-user**:

```bash
vi config.py
```

Press `i` to enter insert mode. Change the `API_KEY` line so the file reads:

```python
# Application configuration
import os
API_KEY = os.environ.get("API_KEY")
DB_HOST = "127.0.0.1"
DB_PORT = 5432
```

`os.environ.get("API_KEY")` reads the key from an environment variable at run time, so it never lives in your code.

Save and quit: press `Esc`, type `:wq`, press `Enter`.

Confirm the secret string is gone from the file:

```bash
grep "sk-fake" config.py
```

`grep` searches a file. If the secret is gone, `grep` prints nothing and returns quietly.

Expected output (empty - nothing printed):

```

```

---

## Step 4: Set the secret as an environment variable

Now provide the key the safe way, through the environment.

Still on your **lab server**, as **ec2-user**:

```bash
export API_KEY="sk-fake-1234567890ABCDEFsecretDONOTCOMMIT"
```

`export` sets an environment variable for this shell and anything it launches. Your app reads it via `os.environ.get`.

Confirm your app can see it (without printing the whole key):

```bash
python3 -c "import config; print('key loaded:', bool(config.API_KEY))"
```

Expected output (yours will differ):

```
key loaded: True
```

> For a permanent setup you would add secrets to a `.env` file that is git-ignored, or to your shell profile - never to tracked code.

---

## Step 5: Stop tracking config.py and ignore it

Even with the value removed, config files often gain secrets again. Stop tracking it and tell git to ignore it.

Remove it from tracking but keep the file on disk:

Still on your **lab server**, as **ec2-user**:

```bash
git rm --cached config.py
```

`git rm --cached` unstages/untracks the file but leaves it in your folder. Now git will no longer save changes to it.

Create a `.gitignore` so it stays ignored:

```bash
vi .gitignore
```

Press `i`, then type:

```
config.py
.env
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

---

## Step 6: Scrub the secret from history

The secret is still sitting in old commits. Rewrite history so it is gone from every commit. The simplest built-in tool is `git filter-branch`.

Still on your **lab server**, as **ec2-user**:

```bash
git filter-branch --force --index-filter "git rm --cached --ignore-unmatch config.py" --prune-empty -- --all
```

Breaking this down:
- `filter-branch` rewrites commits.
- `--force` runs even if a previous run left leftovers.
- `--index-filter "git rm --cached --ignore-unmatch config.py"` removes `config.py` from every commit's tracked files. `--ignore-unmatch` avoids errors in commits that never had it.
- `--prune-empty` drops any commit that becomes empty.
- `-- --all` applies to all branches.

Expected output (yours will differ, truncated):

```
Rewrite a1b2c3d... (2/3)
...
Ref 'refs/heads/main' was rewritten
```

Confirm the secret is no longer anywhere in history:

```bash
git log --all --oneline -S "sk-fake"
```

`git log -S "sk-fake"` finds any commit that added or removed that string. If history is clean, it prints nothing.

Expected output (empty - nothing printed):

```

```

---

## Step 7: Commit the cleanup

Save the `.gitignore` and the removal.

Still on your **lab server**, as **ec2-user**:

```bash
git add .gitignore
```

```bash
git commit -m "Remove committed secret, ignore config, load API key from env"
```

Expected output (yours will differ):

```
[main f6g7h8i] Remove committed secret, ignore config, load API key from env
 1 file changed, 2 insertions(+)
```

---

## Step 8: Validate

Run the validator.

Still on your **lab server**, as **ec2-user**:

```bash
bash ~/aiconsult-staging/phase00-orientation/survive/git-disaster/validate.sh
```

Expected output when fixed:

```
[validate] PASS: no secret in tracked files and none found in git history
```

If it fails, read the message and repeat the step it names.

---

## What you learned

- Secrets never belong in code. Load them from environment variables (or a git-ignored `.env`).
- `git grep` and `git log -S` find secrets in tracked files and history.
- `git rm --cached` + `.gitignore` stop tracking a file without deleting it.
- Removing a secret from the latest commit is not enough - it lives in history until you rewrite it (`git filter-branch`).
- In real life, a leaked key is compromised: rotate it immediately, then clean git.

# SURVIVE Runbook: A Secret Was Committed

**Scenario:** an API key and a database password were hardcoded into `config.py` and committed to git. This is the single most common security incident in real codebases. Once a secret is in git, it is exposed - anyone with the repo (or its history) has it, and "deleting the line" does not remove it from history.

**Your job:** respond in the correct order - **rotate first**, then move the secret to an environment variable, then scrub it from tracked files and prevent it happening again. You are on the **lab server**, as **ec2-user**, with Project 1 in `~/project1`.

The rule you are enforcing: **secrets never live in source.** They come from environment variables or a secrets manager. And on a leak, rotation comes before cleanup, because the secret is already compromised.

---

## Step 1: Confirm the leak

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

Search the tracked files for anything that looks like a key:

```bash
git grep -nE "sk-live|API_KEY *=|DB_PASSWORD *=" -- '*.py'
```

`git grep` searches only tracked files. `-n` shows line numbers, `-E` enables extended regex.

Expected output (the leak):

```
config.py:5:API_KEY = "sk-live-4f9a1c7e2b8d0a6f3e5c9b1d7a4f2e8c"
config.py:8:DB_PASSWORD = "labpass"
```

A live-looking API key and the database password are hardcoded in `config.py`. Confirm it is also in history (this is why deletion alone is not enough):

```bash
git log --oneline -- config.py
```

Expected output (yours will differ):

```
a1b2c3d add app config
```

The secret is baked into that commit permanently.

---

## Step 2: ROTATE the secret first (most important step)

The secret is already exposed, so assume it is compromised. **Rotation comes before cleanup.** In a real system you would:

- Log in to the provider (for example the API vendor's dashboard) and **issue a new key**.
- **Revoke the old key** so the leaked one stops working.
- For the database password, change it (`ALTER ROLE ... PASSWORD ...`) and update wherever it is stored.

For this lab there is no external provider, so simulate rotation by recording the new value you will use. Generate a fresh fake key:

```bash
echo "sk-live-$(openssl rand -hex 16)"
```

Expected output (yours will differ):

```
sk-live-9d3f7a1e5c8b2046fa9e1d7c3b5a8e02
```

Copy that value - it is your rotated key for the next step. The moment you rotate and revoke, the leaked key is worthless, which is the whole point: scrubbing git alone would leave a live key in the wild.

---

## Step 3: Move the secret to an environment variable

Rewrite `config.py` so it reads secrets from the environment instead of hardcoding them. Open it with `vi`:

```bash
vi config.py
```

Press `i`, replace the whole file with this safe version (paste your rotated key nowhere - it goes in the environment, not the file):

```python
"""App config. Secrets come from the environment - never hardcoded."""
import os

# Secrets from the environment. No defaults for secrets, so a missing
# value fails loudly instead of silently using something wrong.
API_KEY = os.environ["API_KEY"]
DB_PASSWORD = os.environ["DB_PASSWORD"]

# Non-secret config can keep safe defaults.
DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_NAME = os.environ.get("DB_NAME", "labdb")
DB_USER = os.environ.get("DB_USER", "labuser")
```

Press `Esc` and type `:wq` to save and quit.

Now provide the values through the environment (this is where your rotated key goes). Create a local `.env` that will NOT be committed:

```bash
vi .env
```

Press `i`, add the following (use your rotated key from Step 2 in place of the example):

```
API_KEY=sk-live-9d3f7a1e5c8b2046fa9e1d7c3b5a8e02
DB_PASSWORD=labpass
```

Press `Esc` and type `:wq`.

---

## Step 4: Prevent the .env from ever being committed

Add `.env` (and other secret files) to `.gitignore` so git refuses to track them.

Still on the **lab server**, as **ec2-user**:

```bash
vi .gitignore
```

Press `i`, add these lines:

```
.env
*.pem
.db_password.good
```

Press `Esc` and type `:wq`.

Confirm git now ignores `.env`:

```bash
git status --porcelain .env
```

Expected output (empty - nothing printed):

```
```

No output means git is ignoring `.env`. Good.

---

## Step 5: Commit a safe example instead

Document which variables are required by committing a `.env.example` with blank values - never the real ones.

Still on the **lab server**, as **ec2-user**:

```bash
vi .env.example
```

Press `i`, add:

```
API_KEY=
DB_PASSWORD=
DB_HOST=127.0.0.1
DB_NAME=labdb
DB_USER=labuser
```

Press `Esc` and type `:wq`.

---

## Step 6: Scrub the secret and commit the fix

Commit the cleaned `config.py`, the `.gitignore`, and the example.

Still on the **lab server**, as **ec2-user**:

```bash
git add config.py .gitignore .env.example
```

```bash
git commit -q -m "fix: move secrets to env vars, ignore .env, add example"
```

Verify the secret is gone from tracked files:

```bash
git grep -nE "sk-live|labpass" -- '*.py'
```

Expected output (empty - nothing printed):

```
```

No output means no secret remains in any tracked `.py` file.

---

## Step 7: Note on history (the hard part)

The old commit still contains the secret in git **history**. Scrubbing tracked files is necessary but not sufficient. In a real repo you would additionally:

- Rewrite history with `git filter-repo` (or BFG Repo-Cleaner) to purge the secret from every past commit, and force-push.
- Because rewriting history is disruptive and never fully reliable on a shared or public repo, **rotation (Step 2) is the real fix** - it makes the leaked value useless no matter who already copied it.

You already rotated in Step 2, so even the value sitting in history is now dead. That is why rotation comes first.

---

## What you learned

- **Rotate before you scrub.** The instant a secret is committed it is compromised; issuing a new key and revoking the old one is what actually protects you. Cleaning git without rotating leaves a live key exposed.
- **Secrets come from the environment**, read with `os.environ["API_KEY"]` (no default, so a missing secret fails loudly).
- **`.gitignore` the secret files** and commit a blank `.env.example` so the team knows what is required without exposing anything.
- **History is forever**, which is exactly why hardcoding a secret even once is a real incident.

## Prevention

- Add a pre-commit secret scanner (git-secrets, detect-secrets, gitleaks) that blocks commits containing key-like strings.
- Use a secrets manager (AWS Secrets Manager, Vault) so secrets are never in files at all.
- Code review specifically looks for hardcoded credentials - it is the highest-value thing a reviewer catches.

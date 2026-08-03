# Build 1: The Repo and the Secret Scanner (40 min)

In this lab you create the pg-ops repository on your Mac and install a secret scanner BEFORE any file enters it. The server from Build 0 stays running - Build 2 pulls its real configs into this repo.

All commands in this guide were tested on a Mac on 2026-07-22 (git 2.50.1, gitleaks 8.30.1). Outputs shown are real captured outputs.

---

## Step 1: Create the directory

On **your Mac**, in **Terminal**:

```bash
mkdir -p ~/Projects/pg-ops
```

Creates the folder. `-p` creates parent folders if needed and does not error if it already exists.

```bash
cd ~/Projects/pg-ops
```

Moves you into it. Stay in this folder for the whole guide.

## Step 2: Turn it into a Git repository

Still in **~/Projects/pg-ops**:

```bash
git init -b main
```

`init` creates the hidden `.git` folder (the data directory plus WAL archive). `-b main` names the first branch `main`.

Expected output (yours will differ):
```
Initialized empty Git repository in /Users/hafopezi/Projects/pg-ops/.git/
```

## Step 3: Confirm your identity

Every commit is stamped with an author. Check what Git will stamp:

```bash
git config user.name
```

```bash
git config user.email
```

Expected output (yours will differ):
```
Happy Afopezi
thedevopsdba@gmail.com
```

If either is empty or wrong, set them once for the whole machine:

```bash
git config --global user.name "Happy Afopezi"
```

```bash
git config --global user.email "your-email@example.com"
```

`--global` writes to `~/.gitconfig` so it applies to every repo on this Mac.

## Step 4: Check the secret scanner is installed

Why now, before anything else: Git history is forever by design. A password committed once stays in history even after you delete the file. The scanner refuses the commit before that can happen.

```bash
gitleaks version
```

Expected output (yours will differ):
```
8.30.1
```

If you get "command not found":

```bash
brew install gitleaks
```

## Step 5: Wire the scanner into every commit

A pre-commit hook is a small script Git runs before accepting a commit. If the script fails, the commit is refused - like a trigger that rejects bad rows.

Still in **~/Projects/pg-ops**, create the hook:

```bash
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/sh
gitleaks protect --staged --verbose
EOF
```

`protect --staged` scans only the files you are about to commit. `--verbose` shows details when it finds something.

Make it executable - Git silently ignores hooks that are not:

```bash
chmod +x .git/hooks/pre-commit
```

Verify:

```bash
ls -l .git/hooks/pre-commit
```

Expected output (yours will differ):
```
-rwxr-xr-x  1 hafopezi  wheel  46 Jul 22 23:13 .git/hooks/pre-commit
```

The `x` letters mean executable. Good.

One more scan, from the research: the hook only checks NEW commits. Any time you import existing files (like your old scripts later), also scan the whole history once:

```bash
gitleaks detect
```

On this brand-new repo it finds nothing - but run it after every big import. Already-committed secrets stay in history even if the file was deleted later.

## Step 6: Tell Git what to never track

```bash
cat > .gitignore << 'EOF'
# secrets - never in history
*.pem
*.key
.pgpass
*.env
credentials*

# noise
.DS_Store
*.log
*.swp
EOF
```

`.gitignore` lists file patterns Git will not track. Two layers of protection: this keeps secret files out, and gitleaks catches anything that slips through.

## Step 7: Create the folder layout

```bash
mkdir -p config/pgforge-1 scripts runbooks docs
```

One folder per server under `config/` - the server from Build 0 is pgforge-1. `scripts/` for tools, `runbooks/` for procedures, `docs/` for decisions.

## Step 8: Your first git status - learn to read it

```bash
git status
```

Expected output:
```
On branch main

No commits yet

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	.gitignore

nothing added to commit but untracked files present (use "git add" to track)
```

Read it top to bottom: you are on `main`, no restore points exist yet, and `.gitignore` is **untracked** - on disk but Git is not watching it yet. The empty folders do not appear at all: Git tracks files, not folders.

The repo is ready. Continue to Build 2, where the server's REAL configs come in.

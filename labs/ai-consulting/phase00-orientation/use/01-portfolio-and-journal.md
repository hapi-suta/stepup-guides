# USE: Build Your Portfolio and Learning Journal

**Phase 0, Module 0.3 (Part 1 of 2)**

In the BUILD module you set up your Linux tools. Now you will put them to work by creating the study and portfolio system you will use for the rest of this curriculum. By the end of this guide you will have a real GitHub portfolio, a technical-learning journal, and an experiment log - all tracked in git and ready to grow.

Everything you produce in this curriculum is evidence of your skill. Employers and clients look at a portfolio. So we start building it on day one.

**Validated on:** CentOS Stream 9, as ec2-user.

Throughout this guide, each command block tells you **which server** and **which user** you are. Follow that exactly.

---

## What you will create

1. A GitHub portfolio repository
2. A technical-learning journal (dated entries)
3. An experiment log (what you tried, what happened)
4. An architecture-diagram folder (for later modules)

---

## Step 1: Configure git with your name and email

git stamps every change you save with your name and email. Set them once so your portfolio shows you as the author.

On your **lab server**, as **ec2-user**:

```bash
git config --global user.name "Your Name"
```

`git config` changes git settings. `--global` applies it to all your repositories on this server. `user.name` is the name that appears on your commits.

Now set your email:

```bash
git config --global user.email "you@example.com"
```

Use the same email you use for GitHub so your commits link to your account.

Confirm both were saved:

```bash
git config --global --list
```

Expected output (yours will differ):

```
user.name=Your Name
user.email=you@example.com
init.defaultbranch=main
...
```

---

## Step 2: Create the portfolio folder

A portfolio is just a folder of your work, tracked by git. Make it in your home directory.

Still on your **lab server**, as **ec2-user**, move to your home directory:

```bash
cd ~
```

`cd` changes directory. `~` is a shortcut for your home directory.

Now create the folder:

```bash
mkdir ai-consulting-portfolio
```

`mkdir` makes a new directory. Move into it:

```bash
cd ai-consulting-portfolio
```

Confirm where you are:

```bash
pwd
```

`pwd` prints the working directory (the folder you are in).

Expected output (yours will differ):

```
/home/ec2-user/ai-consulting-portfolio
```

---

## Step 3: Turn the folder into a git repository

git tracks changes only inside a repository. Turn this folder into one.

Still on your **lab server**, as **ec2-user**, inside `ai-consulting-portfolio`:

```bash
git init
```

`git init` creates a hidden `.git` folder that stores your history. Nothing else in the folder changes.

Expected output (yours will differ):

```
Initialized empty Git repository in /home/ec2-user/ai-consulting-portfolio/.git/
```

---

## Step 4: Write the portfolio landing page (README)

A `README.md` is the front page of a repository. GitHub shows it automatically. Create it with vi.

Still on your **lab server**, as **ec2-user**:

```bash
vi README.md
```

`vi` is the text editor. This opens (and creates) `README.md`.

Once vi is open, press `i` to enter **insert mode** (you can now type). Type the following:

```markdown
# AI Consulting Portfolio

This repository is my working portfolio for the SUTA Labs AI Consulting curriculum.
It holds my learning journal, experiment logs, and project write-ups as I progress.

## Contents

- `journal/` - dated notes on what I learned each day
- `experiments/` - what I tried, what happened, what I concluded
- `diagrams/` - architecture diagrams for the projects I build

## About me

I am training to design and deliver AI systems for real clients.
```

To save and quit vi: press `Esc` to leave insert mode, then type `:wq` and press `Enter`. `:w` writes (saves), `:q` quits.

Confirm the file exists and has content:

```bash
cat README.md
```

`cat` prints a file to the screen.

Expected output (yours will differ):

```
# AI Consulting Portfolio

This repository is my working portfolio for the SUTA Labs AI Consulting curriculum.
...
```

---

## Step 5: Create the journal, experiments, and diagrams folders

Make the three subfolders your README promised.

Still on your **lab server**, as **ec2-user**, inside `ai-consulting-portfolio`:

```bash
mkdir journal experiments diagrams
```

`mkdir` can make several folders at once when you list them with spaces.

git ignores empty folders, so drop a placeholder file in `diagrams` so it gets tracked:

```bash
touch diagrams/.gitkeep
```

`touch` creates an empty file. `.gitkeep` is a common name for "keep this empty folder in git."

Confirm the layout:

```bash
ls -R
```

`ls` lists files. `-R` lists them recursively (including inside subfolders).

Expected output (yours will differ):

```
.:
README.md  diagrams  experiments  journal

./diagrams:

./experiments:

./journal:
```

---

## Step 6: Write your first learning-journal entry

The journal is dated notes on what you learned. Write today's entry.

Still on your **lab server**, as **ec2-user**, open a dated file with vi:

```bash
vi journal/2026-07-25.md
```

Name the file with the date so entries sort in order. Press `i` to enter insert mode, then type:

```markdown
# 2026-07-25 - Environment and portfolio setup

## What I did today
- Installed git, Python 3.12, Docker, and PostgreSQL on my lab server.
- Created my AI consulting portfolio repository.
- Started this learning journal.

## What I learned
- A virtual environment isolates one project's Python packages from another's.
- A README is the front page GitHub shows for a repository.

## Questions I still have
- When should I create a new virtual environment vs reuse one?

## Next
- Finish the glossary and templates guide.
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

Confirm it saved:

```bash
cat journal/2026-07-25.md
```

Expected output (yours will differ):

```
# 2026-07-25 - Environment and portfolio setup

## What I did today
...
```

---

## Step 7: Write your first experiment-log entry

The experiment log records a specific thing you tried and the result. This is the habit that makes you reproducible. Open a file:

Still on your **lab server**, as **ec2-user**:

```bash
vi experiments/001-hello-docker.md
```

Number experiments so they are easy to reference later. Press `i`, then type:

```markdown
# Experiment 001 - Run my first Docker container

## Goal
Confirm Docker works by running the hello-world image.

## What I ran
docker run --rm hello-world

## What happened
Docker pulled the image and printed "Hello from Docker!".

## Conclusion
Docker is installed and working. Containers run on this box.
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

---

## Step 8: Save your work with git

Right now git sees your files but has not saved a snapshot. Save one (this is called a **commit**).

Still on your **lab server**, as **ec2-user**, first see what git notices:

```bash
git status
```

`git status` shows which files are new or changed.

Expected output (yours will differ):

```
On branch main

No commits yet

Untracked files:
  (use "git add <file>..." to include in what will be committed)
	README.md
	diagrams/
	experiments/
	journal/
```

Now stage everything (mark it to be saved):

```bash
git add .
```

`git add` stages files. `.` means "everything in this folder."

Now take the snapshot with a message describing it:

```bash
git commit -m "Set up portfolio, journal, and first experiment log"
```

`git commit` saves the snapshot. `-m` provides the message inline.

Expected output (yours will differ):

```
[main (root-commit) a1b2c3d] Set up portfolio, journal, and first experiment log
 4 files changed, 40 insertions(+)
 create mode 100644 README.md
 ...
```

---

## Step 9: Push your portfolio to GitHub

Your commits live only on this server until you push them to GitHub, where employers can see them.

First, create an empty repository on GitHub in your browser:
1. Go to https://github.com/new
2. Name it `ai-consulting-portfolio`
3. Set it to **Public** so it is visible.
4. Do NOT add a README, .gitignore, or license (you already have files).
5. Click **Create repository**.

GitHub then shows you a URL like `https://github.com/YOURNAME/ai-consulting-portfolio.git`. Use it below.

Still on your **lab server**, as **ec2-user**, connect your local repo to GitHub:

```bash
git remote add origin https://github.com/YOURNAME/ai-consulting-portfolio.git
```

`git remote add` records where to push. `origin` is the standard nickname for your main remote. Replace `YOURNAME` with your GitHub username.

Rename your branch to `main` if it is not already:

```bash
git branch -M main
```

`git branch -M main` renames the current branch to `main` (the GitHub default).

Now push:

```bash
git push -u origin main
```

`git push` uploads your commits. `-u origin main` sets `origin/main` as the default so future pushes are just `git push`.

git will ask for your GitHub username and a **personal access token** (not your password). If you do not have a token, create one at https://github.com/settings/tokens with `repo` scope, and paste it when asked for the password.

Expected output (yours will differ):

```
Enumerating objects: 8, done.
...
To https://github.com/YOURNAME/ai-consulting-portfolio.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

Open `https://github.com/YOURNAME/ai-consulting-portfolio` in your browser. Your portfolio is now live.

---

## What you accomplished

- A public GitHub portfolio, tracked in git.
- A dated learning journal with your first entry.
- An experiment log with your first entry.
- A diagrams folder ready for later modules.

Keep the habit: write a journal entry at the end of each study session, and an experiment entry every time you try something and learn from the result. Commit and push at the end of each day.

Next: **02-glossary-and-templates.md**, where you build the glossary, documentation template, and reading-notes repo.

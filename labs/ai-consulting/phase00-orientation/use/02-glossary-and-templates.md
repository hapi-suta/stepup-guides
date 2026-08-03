# USE: Build Your Glossary, Templates, and Reading Notes

**Phase 0, Module 0.3 (Part 2 of 2)**

In Part 1 you created your portfolio, journal, and experiment log. In this guide you finish the study system: an AI terminology glossary you add to as you learn, a reusable project-documentation template, and a reading-notes repository for the articles and papers you study.

These are the tools professionals use to stay organized and reproducible. Building them now means you use them from day one.

**Validated on:** CentOS Stream 9, as ec2-user.

Each command block tells you **which server** and **which user** you are. Follow that exactly.

> **Before you start:** you should already have `~/ai-consulting-portfolio` from Part 1. If not, complete `01-portfolio-and-journal.md` first.

---

## What you will create

1. An AI terminology glossary (in your portfolio)
2. A project-documentation template (reusable for every project)
3. A separate reading-notes repository

---

## Step 1: Move into your portfolio

On your **lab server**, as **ec2-user**:

```bash
cd ~/ai-consulting-portfolio
```

`cd` changes directory. This moves you into the portfolio you built in Part 1.

Confirm you are in the right place:

```bash
pwd
```

Expected output (yours will differ):

```
/home/ec2-user/ai-consulting-portfolio
```

---

## Step 2: Create the glossary file

A glossary is your own dictionary of AI terms. Writing definitions in your own words is one of the best ways to learn. Create the file.

Still on your **lab server**, as **ec2-user**:

```bash
vi GLOSSARY.md
```

`vi` opens (and creates) the file. Press `i` to enter insert mode, then type these starter entries:

```markdown
# AI Terminology Glossary

My own definitions, in plain language. I add a new term every time I meet one.

## AI (Artificial Intelligence)
The broad field of making computers do tasks that normally need human intelligence.

## ML (Machine Learning)
A part of AI where a program learns patterns from data instead of being told exact rules.

## Generative AI
ML models that create new content - text, images, code - rather than just classifying or predicting.

## LLM (Large Language Model)
A generative AI model trained on huge amounts of text to predict and produce language.

## MLOps
The practices for reliably building, deploying, and maintaining machine-learning models in production.

## LLMOps
The subset of MLOps focused on the special needs of large language models - prompts, tokens, cost, and evaluation.
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

Confirm it saved:

```bash
cat GLOSSARY.md
```

`cat` prints the file.

Expected output (yours will differ):

```
# AI Terminology Glossary

My own definitions, in plain language. I add a new term every time I meet one.
...
```

---

## Step 3: Create a templates folder

You will start many projects. A template saves you from writing the same structure each time. Make a folder to hold your templates.

Still on your **lab server**, as **ec2-user**:

```bash
mkdir templates
```

`mkdir` makes the folder.

---

## Step 4: Write the project-documentation template

This is a fill-in-the-blanks document you copy into every new project. Create it.

Still on your **lab server**, as **ec2-user**:

```bash
vi templates/PROJECT_TEMPLATE.md
```

Press `i`, then type:

```markdown
# [PROJECT NAME]

## Problem
What business problem does this solve? Who is the [CLIENT] and what do they need?

## Approach
The high-level plan. What AI/ML technique, what data, what tools.

## Architecture
A short description of the components and how they connect.
(Diagram lives in ../diagrams/)

## Setup and how to run
Exact steps for someone new to reproduce this from scratch.

## Results
What worked. Numbers if you have them.

## Risks and limitations
What could go wrong. What this does not handle.

## Next steps
What you would do with more time.
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

Confirm:

```bash
cat templates/PROJECT_TEMPLATE.md
```

Expected output (yours will differ):

```
# [PROJECT NAME]

## Problem
What business problem does this solve? ...
```

---

## Step 5: Save these additions to git

Snapshot the glossary and template.

Still on your **lab server**, as **ec2-user**, see what changed:

```bash
git status
```

Expected output (yours will differ):

```
On branch main
Untracked files:
  (use "git add <file>..." to include in what will be committed)
	GLOSSARY.md
	templates/
```

Stage everything:

```bash
git add .
```

Commit with a message:

```bash
git commit -m "Add glossary and project documentation template"
```

Expected output (yours will differ):

```
[main e4f5g6h] Add glossary and project documentation template
 2 files changed, 40 insertions(+)
```

Push it to GitHub:

```bash
git push
```

Because you set the default in Part 1, plain `git push` works now.

Expected output (yours will differ):

```
...
To https://github.com/YOURNAME/ai-consulting-portfolio.git
   a1b2c3d..e4f5g6h  main -> main
```

---

## Step 6: Create a separate reading-notes repository

Your reading notes deserve their own repository so your portfolio stays focused on projects. Move back to your home directory first.

Still on your **lab server**, as **ec2-user**:

```bash
cd ~
```

Make the folder:

```bash
mkdir reading-notes
```

Move into it:

```bash
cd reading-notes
```

Turn it into a git repository:

```bash
git init
```

`git init` creates the hidden `.git` history folder.

Expected output (yours will differ):

```
Initialized empty Git repository in /home/ec2-user/reading-notes/.git/
```

---

## Step 7: Write a README and your first reading note

Create the front page.

Still on your **lab server**, as **ec2-user**, inside `reading-notes`:

```bash
vi README.md
```

Press `i`, then type:

```markdown
# Reading Notes

Notes on the articles, papers, and docs I study for AI consulting.
One file per source, named by date and topic.
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

Now write your first note:

```bash
vi 2026-07-25-mlops-vs-llmops.md
```

Press `i`, then type:

```markdown
# MLOps vs LLMOps - 2026-07-25

## Source
[Title and link of what you read]

## Key points
- MLOps covers the full lifecycle of ML models in production.
- LLMOps focuses on the extra concerns of language models: prompts, tokens, cost, evaluation.

## How this applies to my work
When I advise a [CLIENT], I need to know which set of practices fits their use case.

## Terms to add to my glossary
- prompt, token, evaluation
```

Save and quit: press `Esc`, type `:wq`, press `Enter`.

---

## Step 8: Save and push the reading-notes repo

Still on your **lab server**, as **ec2-user**, inside `reading-notes`, stage and commit:

```bash
git add .
```

```bash
git commit -m "Start reading notes with first entry"
```

Expected output (yours will differ):

```
[main (root-commit) h7i8j9k] Start reading notes with first entry
 2 files changed, 20 insertions(+)
```

Create an empty `reading-notes` repository on GitHub (same steps as Part 1, Step 9): go to https://github.com/new, name it `reading-notes`, set Public, do not add any files, click Create.

Connect and push:

```bash
git remote add origin https://github.com/YOURNAME/reading-notes.git
```

Replace `YOURNAME` with your GitHub username.

```bash
git branch -M main
```

```bash
git push -u origin main
```

Enter your GitHub username and personal access token when asked.

Expected output (yours will differ):

```
...
To https://github.com/YOURNAME/reading-notes.git
 * [new branch]      main -> main
```

---

## What you accomplished

- A glossary you will grow every time you learn a new term.
- A reusable project-documentation template.
- A separate, public reading-notes repository with your first note.

Your full study system now exists:
- `ai-consulting-portfolio` - journal, experiments, diagrams, glossary, templates
- `reading-notes` - one note per source you study

From here on, every module: read, take a note, learn a term (glossary), do the work (experiment log), reflect (journal), and commit. That loop is what turns study into a portfolio.

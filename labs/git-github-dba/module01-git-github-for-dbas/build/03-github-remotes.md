# Module 01 - Git & GitHub for DBAs
## Guide 03: GitHub - Your Repository, Off the Server

**Objective:** Create your own GitHub account, connect your server to it with an SSH key, push your practice repository, and run one full pull-request cycle.
**Time:** 40-45 minutes
**Prerequisites:**
- Guides 01-02 completed: `~/git-practice` has ~9 commits and a `v1.0` tag
- You read Concepts 03 (remotes, SSH keys, private repos)
- A web browser on your laptop

---

## 1. Create your GitHub account (browser)

In your **browser**, go to https://github.com/signup and create a free account:

1. Enter your email, choose a password, choose a username (this becomes part of all your repo URLs - short and professional is best, e.g. `fnji-dba`)
2. Verify your email when GitHub sends the code

Everywhere this guide says `YOUR_USERNAME`, type the username you just chose.

When your account is ready, confirm on the server so we move on together. On **pg-git-1**, as **ec2-user** (type your real username into the message):

```bash
echo "GitHub account created: YOUR_USERNAME"
```

## 2. Create a private repository (browser)

Still in your **browser**, on github.com:

1. Click the **+** in the top-right corner, then **New repository**
2. Repository name: `git-practice`
3. Visibility: select **Private** - this is a rule, not a preference. Server configs and notes never go in public repos (Concepts 03).
4. **Leave every checkbox unchecked** - no README, no .gitignore, no license. The repo must be EMPTY, because we are about to push an existing repository into it. (If GitHub creates a README, your first push gets rejected - the remote would have a commit you do not have.)
5. Click **Create repository**

GitHub now shows a page of setup commands. Ignore them - our guide covers it - but keep this page open.

Confirm on the server:

```bash
echo "Private repo git-practice created, empty, no README"
```

## 3. Generate an SSH key on your server

GitHub does not accept passwords from git; the server proves its identity with an SSH key. The key must belong to the OS user who runs git - our practice repo belongs to `ec2-user`.

On **pg-git-1**, as **ec2-user**, generate a modern ed25519 key pair. `-C` attaches your email as a label so you can recognize the key later:

```bash
ssh-keygen -t ed25519 -C "you@example.com"
```

Press Enter at every prompt (default file location, no passphrase for this lab).

Expected output (yours will differ):

```
Generating public/private ed25519 key pair.
Your identification has been saved in /home/ec2-user/.ssh/id_ed25519
Your public key has been saved in /home/ec2-user/.ssh/id_ed25519.pub
The key fingerprint is:
SHA256:jkRYawF3r3Hw4XyQVSzg2j1IoQ7+34+rkbvkRBSBswg you@example.com
...
```

Two files were created. `id_ed25519` is the PRIVATE key - it never leaves the server, never gets pasted anywhere. `id_ed25519.pub` is the PUBLIC key - that one is safe to share, and GitHub needs it. Print it:

```bash
cat ~/.ssh/id_ed25519.pub
```

Expected output (yours will differ):

```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHdOXjMf2o/Y74YPgp0u9jxbTVmxpaOXQurgzURwuaYR you@example.com
```

Select and copy the ENTIRE line, from `ssh-ed25519` through your email, with no extra spaces or line breaks.

## 4. Add the key to your GitHub account (browser)

In your **browser**, on github.com:

1. Click your profile picture (top-right) -> **Settings**
2. In the left sidebar: **SSH and GPG keys**
3. Click **New SSH key**
4. Title: `pg-git-1 ec2-user` (name keys after the server and user they live on - future you will thank you)
5. Key type: leave as **Authentication Key**
6. Paste the public key into the Key field
7. Click **Add SSH key**

## 5. Test the connection

Back on **pg-git-1**, as **ec2-user**:

```bash
ssh -T git@github.com
```

The FIRST time, SSH asks whether to trust GitHub's server (this is normal - it happens once per server):

```
The authenticity of host 'github.com' can't be established.
ED25519 key fingerprint is SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```

Type `yes` and press Enter.

Expected output (yours will differ):

```
Hi YOUR_USERNAME! You've successfully authenticated, but GitHub does not provide shell access.
```

That greeting with YOUR username = the key works. ("No shell access" is normal - GitHub only talks git.)

If you get `Permission denied (publickey)` instead: the key was not added correctly in step 4, or you are logged in as the wrong OS user - check `whoami` says `ec2-user`.

## 6. Connect your repo to GitHub

Tell your local repository where its remote copy lives. `origin` is the conventional nickname for the URL. Use YOUR username:

```bash
cd ~/git-practice
```

```bash
git remote add origin git@github.com:YOUR_USERNAME/git-practice.git
```

Verify:

```bash
git remote -v
```

Expected output (yours will differ):

```
origin	git@github.com:YOUR_USERNAME/git-practice.git (fetch)
origin	git@github.com:YOUR_USERNAME/git-practice.git (push)
```

## 7. Push your history

Send every commit you made in guides 01-02 to GitHub. `-u origin main` links your local `main` to the remote's `main` - needed only on the first push; afterwards a plain `git push` suffices:

```bash
git push -u origin main
```

Expected output (yours will differ):

```
...
To github.com:YOUR_USERNAME/git-practice.git
 * [new branch]      main -> main
branch 'main' set up to track 'origin/main'.
```

Now the moment that makes it real: in your **browser**, refresh your repository page. Every file, every commit, the full history from your server - browsable from anywhere. Click a commit and you will see the same diff `git show` gave you.

Your server can now burn down and your repository survives.

## 8. Tags do not push automatically

One gotcha to learn now: `git push` sends commits, NOT tags. Push your `v1.0` tag explicitly:

```bash
git push origin v1.0
```

Expected output (yours will differ):

```
To github.com:YOUR_USERNAME/git-practice.git
 * [new tag]         v1.0 -> v1.0
```

(In your browser, the repo page now shows **1 tag**.)

## 9. The pull request cycle - change control for DBAs

This is how config changes work on real teams: propose on a branch, review, merge. Run the whole cycle once.

On **pg-git-1**, as **ec2-user**, create a branch and a new file:

```bash
git switch -c add-backup-runbook
```

```bash
vi backup-runbook.md
```

Type this content (in vi: `i` to insert, `Esc` then `:wq` to save):

```
# Backup Runbook - pg-git-1

1. Check latest base backup
2. Verify WAL archiving
3. Test restore quarterly
```

```bash
git add backup-runbook.md
```

```bash
git commit -m "add first draft of backup runbook"
```

Push the BRANCH to GitHub:

```bash
git push -u origin add-backup-runbook
```

Expected output (yours will differ):

```
remote:
remote: Create a pull request for 'add-backup-runbook' on GitHub by visiting:
remote:      https://github.com/YOUR_USERNAME/git-practice/pull/new/add-backup-runbook
remote:
To github.com:YOUR_USERNAME/git-practice.git
 * [new branch]      add-backup-runbook -> add-backup-runbook
```

GitHub noticed the new branch and offers you a pull request URL right in the push output.

## 10. Open and merge the pull request (browser)

In your **browser**:

1. Open the URL from the push output (or go to your repo - GitHub shows a yellow banner: **add-backup-runbook had recent pushes** -> click **Compare & pull request**)
2. Title is pre-filled from your commit message. In the description write one sentence: what this change is and why.
3. Click **Create pull request**
4. Click the **Files changed** tab - THIS is the value of a PR: the reviewer sees the exact lines that will change, before they change. On a team, a colleague reviews here and approves.
5. Back on the **Conversation** tab, click **Merge pull request**, then **Confirm merge**

The branch is now merged into `main` - but only on GitHub. Your server does not know yet. Confirm on the server:

```bash
echo "PR merged on GitHub"
```

## 11. Pull the merge back to the server

On **pg-git-1**, as **ec2-user**:

```bash
git switch main
```

```bash
git pull
```

Expected output (yours will differ):

```
From github.com:YOUR_USERNAME/git-practice.git
   d33915b..4e8da25  main       -> origin/main
Updating d33915b..4e8da25
Fast-forward
 backup-runbook.md | 5 +++++
 1 file changed, 5 insertions(+)
 create mode 100644 backup-runbook.md
```

```bash
git log --oneline | head -3
```

Expected output (yours will differ):

```
4e8da25 Merge pull request #1 from YOUR_USERNAME/add-backup-runbook
2672fd6 add first draft of backup runbook
d33915b Revert "propose work_mem 32MB"
```

The full circle: branch on the server -> push -> review + merge on GitHub -> pull back to the server. That is the change-control workflow you would use for real config changes on a team.

## 12. Checkpoint

- Your GitHub account exists, with your server's SSH key installed
- `git-practice` is on GitHub, **private**, with all commits and the `v1.0` tag
- You ran one complete pull-request cycle

**You now know:** SSH key auth, remotes, push/pull, why tags push separately, and the PR workflow.

Next guide: the capstone - putting your REAL PostgreSQL configuration under version control.

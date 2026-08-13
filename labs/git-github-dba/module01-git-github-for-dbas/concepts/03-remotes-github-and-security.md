# Concepts 03: Remotes, GitHub, and Security

**Time:** 15 minutes
**Phase:** Concepts (read before BUILD guides 03-04)

---

## Local vs remote

Everything you learned in the first two concepts docs happens entirely on your server. No network, no account, no GitHub. That is a complete, working git setup - but it has a single point of failure: the server itself.

A **remote** is another copy of your repository somewhere else. For us that is GitHub. Because git is distributed, the GitHub copy is not a "master copy" - it is a full peer holding the complete history. Server dies? Clone from GitHub. GitHub unreachable? Keep committing locally and push later.

Four commands move history between the two:

- `git clone <url>` - make a new local copy of a remote repository (one-time)
- `git push` - send your new commits to the remote
- `git fetch` - download the remote's new commits, but do not touch your files
- `git pull` - fetch + merge into your current branch in one step

`origin` is not magic - it is just the default nickname git gives the remote's URL so you do not have to type it every time.

## What GitHub adds on top of git

GitHub is a hosting service for git repositories plus a collaboration layer:

- **Private repositories** - your configs, visible only to accounts you invite.
- **Pull requests (PRs)** - "please review my branch before it merges." A PR is a GitHub feature, not a git command. For a DBA team this is change control: propose a `postgresql.conf` change on a branch, a colleague reads the exact diff, approves, merge happens with a full paper trail. You will run this flow in BUILD guide 03.
- **A web view of history** - every commit, diff, and file browsable from anywhere, even when the server is down.

## How authentication works (SSH keys, not passwords)

GitHub removed password authentication for git operations in August 2021. You cannot `git push` with a username and password. The two options are a personal access token or an **SSH key** - we use SSH keys, the standard for servers.

The model is the same one you already use to SSH into your lab box:

1. Generate a key pair on the server: `ssh-keygen -t ed25519` (private key stays on the server, never leaves it)
2. Paste the PUBLIC key into your GitHub account (Settings -> SSH and GPG keys)
3. Test with `ssh -T git@github.com` - GitHub answers with your username

One subtlety that matters in this module: SSH keys belong to the **OS user** that runs git. Your practice repo runs as `ec2-user`, so that key lives in `/home/ec2-user/.ssh/`. The capstone repo runs as `postgres`, so that user gets its own key in its own home directory. One GitHub account can hold many keys - you will add both.

## Security: the rules for config repos

Version-controlling server configuration is standard practice (the etckeeper tool has done it for `/etc` for two decades). But configs are sensitive, so four rules apply.

### Rule 1: Server configs go in PRIVATE repositories. Always.

`pg_hba.conf` reveals your network topology, subnets, and auth methods. `postgresql.conf` reveals extensions, file paths, and replication setup. None of that belongs on the public internet. Public repos are scanned by bots within seconds of a push - leaked credentials in public repos are exploited almost instantly. When you create the repo in BUILD guide 03, you will choose Private, and that choice is the whole ballgame.

### Rule 2: Know which of your files can contain secrets

- **pg_hba.conf** - no secrets (it names WHO may connect, never passwords).
- **postgresql.conf** - normally no secrets. Exception: `ssl_passphrase_command` can embed one. Do not put it there.
- **postgresql.auto.conf** - the one to watch. When a standby is built with `pg_basebackup -R`, postgres writes `primary_conninfo` into this file, and if a password was given on the command line, **the replication password lands here in plain text**.

The fix is standard postgres practice anyway: keep passwords in `~/.pgpass` (the postgres user's password file), so `primary_conninfo` only ever references `passfile=` and no secret touches a config file. Our single-node lab has no replication, so your auto.conf will only ever contain `ALTER SYSTEM` output - but the habit matters the day you version a standby's configs.

### Rule 3: Git never forgets - so a committed secret is a ROTATED secret

If a password ever gets committed, deleting it in a new commit does NOT remove it - the old snapshot still contains it, forever, in every clone. The correct incident response, in order:

1. **Rotate the credential immediately.** This is the actual fix. Everything else is cleanup.
2. Remove it from history if required (the `git-filter-repo` tool - an advanced operation, covered as a SURVIVE scenario).
3. Remember that clones and forks made before the cleanup still hold the secret. Rotation is why you can sleep anyway.

GitHub's push protection can block known secret patterns at push time - but it is only automatic for public repos. Your private config repo relies on YOUR discipline, which is why rule 2 exists.

### Rule 4: Commit before and after every change

Not strictly security, but the discipline everything else depends on: snapshot the known-good state before you touch a config, snapshot again after. Every incident-recovery trick in this module assumes the good state was committed. Cheap insurance, two commands.

## References (canonical docs)

- Working with remotes: https://git-scm.com/book/en/v2/Git-Basics-Working-with-Remotes
- Generating an SSH key: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
- Adding the key to your account: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account
- Testing your SSH connection: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/testing-your-ssh-connection
- About pull requests: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/about-pull-requests
- Removing sensitive data from a repository: https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository
- pg_basebackup notes on postgresql.auto.conf: https://www.postgresql.org/docs/current/app-pgbasebackup.html
- The password file (.pgpass): https://www.postgresql.org/docs/current/libpq-pgpass.html

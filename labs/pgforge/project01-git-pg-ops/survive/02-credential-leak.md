# SURVIVE 2: The Leaked Credential (45 min)

**Scenario:** a config file with a password inside it got committed with the scanner bypassed - the incident every team eventually has. You will prove that deleting the file does NOT remove it from history, purge it properly, and write the postmortem.

Tested end to end on 2026-07-22. Outputs are real - including two surprises testing found (marked below).

---

## Part A: First, prove the scanner actually works

Before drilling the bypass, watch the scanner do its job once.

**Surprise from testing #1:** AWS's documented example key (`AKIAIOSFODNN7EXAMPLE`) is deliberately ignored by gitleaks - it commits cleanly. To test the scanner you need a realistic pattern. A fake GitHub token works.

On **your Mac**, in **~/Projects/pg-ops**:

```bash
printf 'github_token=ghp_x7KpQ2mNvR8sT4wY6zA1bC3dE5fG9hJ0kLmN\n' > scripts/creds.txt
```

Creates a file with a fake (but realistic-looking) token.

```bash
git add scripts/creds.txt
```

```bash
git commit -m "test: should be blocked"
```

Expected output - the commit is REFUSED:
```
    ░    gitleaks

Finding:     github_token=ghp_x7KpQ2mNvR8sT4wY6zA1bC3dE5fG9hJ0kLmN
Secret:      ghp_x7KpQ2mNvR8sT4wY6zA1bC3dE5fG9hJ0kLmN
RuleID:      github-pat
Entropy:     5.121928
File:        scripts/creds.txt
Line:        1
Fingerprint: scripts/creds.txt:github-pat:1

11:15PM INF 0 commits scanned.
11:15PM WRN leaks found: 1
```

The commit did not happen. That is the guardrail working. Clean up:

```bash
git reset HEAD scripts/creds.txt
```

```bash
rm scripts/creds.txt
```

## Part B: Inject the leak - bypass the hook

Now simulate the rushed engineer who bypasses the check:

```bash
printf 'host=db1\npassword=Fake123!\n' > scripts/old-backup.cfg
```

```bash
git add scripts/old-backup.cfg
```

```bash
git commit --no-verify -m "chore: add old backup config"
```

`--no-verify` skips the pre-commit hook. This flag is how real leaks happen - your postmortem will ban it.

Expected output (no gitleaks banner - the hook never ran):
```
[main 8215a21] chore: add old backup config
 1 file changed, 2 insertions(+)
 create mode 100644 scripts/old-backup.cfg
```

The password is now in history. Incident begun.

## Part C: The lesson most people learn the hard way

Instinct says: delete the file and commit. Do it, and watch it NOT work:

```bash
git rm scripts/old-backup.cfg
```

```bash
git commit -m "chore: remove backup config"
```

Now look for the password in history:

```bash
git log -p --all -- scripts/old-backup.cfg
```

`-p` shows the full changes of each commit that touched the file.

Expected output (truncated) - the password is still there:
```
-password=Fake123!
...
+password=Fake123!
```

Deleting a file only adds a "removed" snapshot on top. Every clone still carries the secret. In a real incident, the FIRST action is: **change the password/key immediately - assume it is already stolen.** History cleanup comes second.

## Part D: Purge it properly

```bash
git filter-repo --invert-paths --path scripts/old-backup.cfg --force
```

`filter-repo` rewrites history. `--invert-paths --path <file>` means "keep everything EXCEPT this file". `--force` is needed because this repo is not a fresh clone.

Expected output:
```
NOTICE: Removing 'origin' remote; see 'Why is my origin removed?'
        in the manual if you want to push back there.
        (was https://github.com/hafopezi10/pg-ops.git)
Parsed 8 commits
New history written in 0.06 seconds; now repacking/cleaning...
Completely finished after 0.17 seconds.
```

**Surprise from testing #2:** filter-repo REMOVES your GitHub connection (`origin`) on purpose - it is protecting you from pushing rewritten history by accident. You must add it back yourself.

Prove the password is gone:

```bash
git log -p --all -- scripts/old-backup.cfg
```

Expected output: nothing at all. The file never existed, as far as history is concerned.

Also note: commit IDs changed. filter-repo rewrote every commit after the leak - old IDs in your notes will no longer match. That is expected.

## Part E: Reconnect and force push

```bash
git remote add origin https://github.com/hafopezi10/pg-ops.git
```

```bash
git push --force origin main
```

`--force` replaces GitHub's history with your rewritten one. On a team repo you would announce this loudly first - everyone must re-clone. Solo, it is safe.

Expected output:
```
 + 1bf5818...cb4c398 main -> main (forced update)
```

## Part F: The postmortem

Create `docs/postmortems/2026-XX-credential-leak-drill.md` with four short sections: what happened (timeline), why the hook did not stop it (`--no-verify`), what we did (rotate first, then purge, then force push), and the rule going forward ("--no-verify is banned; any leak means the credential is rotated, no exceptions"). Land it via PR.

---

## What you practiced

The full leak lifecycle: scanner proof, the bypass, the delete-does-not-help lesson, a proper history purge with its two surprises, and the write-up. Interview version: "First action is rotating the credential - assume it is stolen. Cleanup is second. And the fix that matters is the guardrail that stops the next one."

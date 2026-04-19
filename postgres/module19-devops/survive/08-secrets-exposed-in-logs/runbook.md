# SURVIVE 08: Secrets Exposed in Logs - Runbook

## Symptom

A security audit discovers that database credentials and AWS keys are visible in CI build logs. The credentials are for a production database.

---

## Step 1: Identify All Exposed Secrets

Scan the CI log for credentials.

```bash
grep -in "password\|secret\|key\|token\|credential" /tmp/secrets-chaos/ci-logs/build-2026-04-19.log
```

Look for connection strings that contain embedded passwords.

```bash
grep -in "postgresql://.*:.*@" /tmp/secrets-chaos/ci-logs/build-2026-04-19.log
```

Document every secret found:

1. **Database password**: `SuperSecret123!` (for user `dbadmin`)
2. **AWS Secret Access Key**: `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY`
3. **Database host**: `prod-db.internal` (internal hostname exposed)

---

## Step 2: Rotate the Database Password IMMEDIATELY

This is the highest priority. Assume the credential is compromised.

Switch to the postgres user.

```bash
sudo -iu postgres
```

Generate a new password and change it.

```bash
psql -c "ALTER ROLE dbadmin WITH PASSWORD 'NewRotatedPass_$(date +%s)';"
```

Note: In production, you would use a password manager or `openssl rand -base64 24` to generate a strong password and store it in AWS Secrets Manager.

Verify the old password no longer works.

```bash
psql -h 127.0.0.1 -U dbadmin -d postgres -c "SELECT 1;"
```

This should fail with "password authentication failed" (since we changed the password).

Exit the postgres user.

```bash
exit
```

---

## Step 3: Fix the CI Workflow

Examine the broken workflow.

```bash
cat -n /tmp/secrets-chaos/db-ci.yml
```

Problems:
1. Password is hardcoded in the `env:` block
2. `echo "Connecting to $DATABASE_URL"` prints the full URL including password
3. `echo "AWS Key: $AWS_SECRET_ACCESS_KEY"` directly prints the key

Fix the workflow.

```bash
vi /tmp/secrets-chaos/db-ci.yml
```

Replace the contents with:

```yaml
name: Database CI (SECURE)
on: [push]
jobs:
  deploy:
    runs-on: ubuntu-latest
    env:
      # Use GitHub Secrets - never hardcode credentials
      DATABASE_URL: postgresql://dbadmin:${{ secrets.DB_PASSWORD }}@prod-db.internal:5432/appdb
    steps:
      - name: Debug connection
        run: echo "Connecting to database (credentials masked)"

      - name: Run migrations
        run: psql "$DATABASE_URL" -f migrations.sql

      # NEVER echo secrets - removed the debug step entirely
```

Key changes:
- Use `${{ secrets.DB_PASSWORD }}` instead of hardcoded password
- Remove any `echo` that includes secret variables
- Remove the AWS key debug step entirely

---

## Step 4: Mask Secrets in CI

In GitHub Actions, add secrets via Settings > Secrets and variables > Actions.

For the workflow, GitHub automatically masks any value stored as a secret. If the value appears in logs, it is replaced with `***`.

Additional protection - add `::add-mask::` for dynamic secrets:

```yaml
      - name: Mask database URL
        run: echo "::add-mask::${{ secrets.DB_PASSWORD }}"
```

---

## Step 5: Clean Up the Compromised Logs

Delete or purge the CI logs that contain secrets.

In the lab, remove the log file.

```bash
rm /tmp/secrets-chaos/ci-logs/build-2026-04-19.log
```

Create a clean log as a placeholder.

```bash
vi /tmp/secrets-chaos/ci-logs/build-2026-04-19.log
```

```
[2026-04-19T10:00:00Z] Starting database CI pipeline
[2026-04-19T10:00:01Z] Checkout code: OK
[2026-04-19T10:00:05Z] Installing PostgreSQL client...
[2026-04-19T10:00:15Z] Running migrations...
[2026-04-19T10:00:15Z] Connecting to database (credentials masked)
[2026-04-19T10:00:16Z] Applying V1__create_users.sql... OK
[2026-04-19T10:00:17Z] Applying V2__create_sessions.sql... OK
[2026-04-19T10:00:18Z] Running tests...
[2026-04-19T10:00:20Z] Test 1: PASS
[2026-04-19T10:00:21Z] Test 2: PASS
[2026-04-19T10:00:22Z] Deploying to staging...
[2026-04-19T10:00:23Z] Pipeline complete
```

In GitHub, you would:
1. Go to Actions > select the workflow run > delete the run
2. Or use `gh api -X DELETE repos/OWNER/REPO/actions/runs/RUN_ID`

---

## Step 6: Audit Who Accessed the Logs

In a real incident:
1. Check GitHub audit log for who viewed the workflow run
2. Check AWS CloudTrail for any usage of the exposed AWS key
3. Rotate the AWS key via IAM console
4. Notify the security team

---

## Step 7: Verify No Credentials Remain

Check that the log is clean.

```bash
grep -c "SuperSecret123\|wJalrXUtnFEMI" /tmp/secrets-chaos/ci-logs/build-2026-04-19.log
```

Expected output:
```
0
```

Zero matches means no credentials remain.

Check that the workflow does not hardcode credentials.

```bash
grep -c "SuperSecret123\|hardcoded" /tmp/secrets-chaos/db-ci.yml
```

Expected output:
```
0
```

---

## Prevention

1. **Never hardcode secrets** - Always use GitHub Secrets, Vault, or AWS Secrets Manager
2. **Never echo secrets** - Do not print environment variables that may contain credentials
3. **Use .gitignore** - Keep `.env` files out of version control
4. **Secret scanning** - Enable GitHub secret scanning and push protection
5. **Pre-commit hooks** - Use tools like `git-secrets` or `gitleaks` to catch secrets before they are committed
6. **Rotate regularly** - Rotate all database passwords on a schedule (every 90 days minimum)
7. **Least privilege** - CI pipelines should use a dedicated database user with only the permissions they need

---

## Discussion Points

- How quickly should you rotate after a leak? Immediately. Assume the credential is already being used by an attacker.
- What about secrets in git history? Use `git filter-branch` or BFG Repo Cleaner to remove them. But assume they are compromised regardless.
- What tools catch secrets in code? gitleaks, trufflehog, git-secrets, GitHub secret scanning

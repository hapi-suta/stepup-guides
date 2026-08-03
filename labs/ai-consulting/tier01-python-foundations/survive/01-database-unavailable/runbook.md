# SURVIVE Runbook: Database Unavailable

**Scenario:** the API is running but the `/summary` endpoint suddenly fails. Your job is to find out why and restore service, the way you would during a real incident.

**Validated on:** CentOS Stream 9, on 2026-07-23. The outputs below are real.

**Contract:**
- `inject.sh` - breaks it (stops PostgreSQL).
- `runbook.md` - this file: diagnose and fix.
- `validate.sh` - proves it is fixed (PASS/FAIL).

---

## Step 0: Inject the fault

On your **lab server**, as **ec2-user**:

```bash
bash ~/project1/../survive/01-database-unavailable/inject.sh
```

(Or run the scenario from wherever you placed it.) It ensures the API is up, then stops PostgreSQL.

---

## Step 1: Observe the symptom

On your **lab server**, as **ec2-user**, call the endpoint:

```bash
curl -s -o /dev/null -w "HTTP %{http_code}\n" http://127.0.0.1:8000/summary
```

Expected output:

```
HTTP 503
```

See the actual error body:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output (yours will differ):

```
{"detail":"database unavailable: connection to server at \"127.0.0.1\", port 5432 failed: Connection refused\n\tIs the server running on that host and accepting TCP/IP connections?\n"}
```

**Read the error.** It is not a crash and not a generic 500 - the app returns a clear `503` saying the database refused the connection. Good software tells you what is wrong. This is the "never swallow errors" principle paying off.

---

## Step 2: Diagnose

The error points at PostgreSQL, not the API. Check the database service:

```bash
systemctl is-active postgresql
```

Expected output:

```
inactive
```

That confirms it: the API is healthy, but PostgreSQL is down, so every database-backed request fails. If you wanted more detail you could check the logs:

```bash
sudo journalctl -u postgresql --no-pager | tail -5
```

---

## Step 3: Recover

Start PostgreSQL again:

```bash
sudo systemctl start postgresql
```

Confirm it is running:

```bash
systemctl is-active postgresql
```

Expected output:

```
active
```

Now retry the endpoint:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output:

```
{"status":"ok"}
```

The API recovered on its own once the database came back - no restart of the API needed, because it opens a fresh connection per request and surfaces failures instead of caching a broken state.

---

## Step 4: Validate

Run the validation script:

```bash
bash ~/project1/../survive/01-database-unavailable/validate.sh
```

Expected output (yours will differ):

```
[validate] PASS: database is up, API is healthy, summary total=10
```

---

## What this teaches

- A dependency being down is not the same as your app being broken. Read the error before touching code.
- A `503` with a clear reason is correct behaviour when a backing service is unavailable - far better than a crash or a silent hang.
- Recovery can be as small as restarting the dependency. Not every incident needs a code change.

## Real-world extension (for a consultant)

In production you would not restart by hand. Note for later tiers: this is where health checks, automatic restarts, connection pooling with retries, and alerting come in (Tier 9 and Tier 10). The failure mode you just saw by hand is exactly what those systems automate.

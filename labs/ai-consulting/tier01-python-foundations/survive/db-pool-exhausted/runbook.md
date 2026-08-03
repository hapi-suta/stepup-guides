# SURVIVE Runbook: Database Connection Broken (bad credentials)

**Scenario:** the Support Summarizer API is running, but every data endpoint fails. The database is fine; the app's credentials are wrong. This is the most common real incident there is - a rotated password never updated, a typo in a config change, or the wrong host.

**Your job:** diagnose why the app cannot reach the database, then recover it, following good-practice steps. You are on the **lab server**, as **ec2-user**, with Project 1 in `~/project1`.

---

## Step 1: Confirm the symptom

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output (the failure):

```
{"detail":"database unavailable: connection to server ... FATAL:  password authentication failed for user \"labuser\""}
```

Good design pays off here: the app did not crash or lie with a fake `200`. It returned a `503` with the real reason. Read the reason - it says **password authentication failed**. That is your lead.

---

## Step 2: Rule out the database itself

Before blaming the app, prove the database is actually up and the real credentials still work. Connect directly with the known-good password.

Still on the **lab server**, as **ec2-user**:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -c "SELECT 1;"
```

Expected output:

```
 ?column?
----------
        1
(1 row)
```

The database is healthy and `labpass` works. So the problem is **the app is using the wrong password**, not the database. This is the key diagnostic split: is it the dependency, or how you are talking to it?

---

## Step 3: Inspect what credentials the app is actually using

The app reads its config from environment variables, typically loaded from a `.env` file. Look at it.

Still on the **lab server**, as **ec2-user**:

```bash
cat .env
```

Expected output (the smoking gun):

```
DB_HOST=127.0.0.1
DB_NAME=labdb
DB_USER=labuser
DB_PASSWORD=WRONG-PASSWORD-INJECTED
```

There it is - the app was started with `DB_PASSWORD=WRONG-PASSWORD-INJECTED`. The credentials are wrong in config, exactly matching the `password authentication failed` error.

---

## Step 4: Fix the credential in config

Correct the password in `.env`. The known-good value was saved by the scenario to `.db_password.good`.

Still on the **lab server**, as **ec2-user**, check the good value:

```bash
cat .db_password.good
```

Expected output:

```
labpass
```

Now rewrite `.env` with the correct password. You can edit it with `vi`:

```bash
vi .env
```

Press `i`, change the last line to read exactly:

```
DB_PASSWORD=labpass
```

Then press `Esc` and type `:wq` to save and quit.

Confirm the file is now correct:

```bash
cat .env
```

Expected output:

```
DB_HOST=127.0.0.1
DB_NAME=labdb
DB_USER=labuser
DB_PASSWORD=labpass
```

---

## Step 5: Restart the app with the corrected config

Config changes do not apply to a running process - you must restart it so it re-reads the environment. First stop the broken process.

Still on the **lab server**, as **ec2-user**:

```bash
pkill -f "uvicorn app:app"
```

Load the corrected environment and start the app again:

```bash
set -a; . ./.env; set +a
```

`set -a` makes every variable defined next get exported; `. ./.env` reads the file into the shell; `set +a` turns that off again. Now start the server:

```bash
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

Give it three seconds to come up.

---

## Step 6: Verify recovery

Still on the **lab server**, as **ec2-user**:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output:

```
{"status":"ok"}
```

And the data endpoint works again:

```bash
curl -s http://127.0.0.1:8000/summary
```

Expected output (yours will differ):

```
{"total":10,"by_category":{"billing":3,"auth":2,"bug":2,"feature":1,"performance":1,"uncategorized":1}}
```

The app is healthy. Incident resolved.

---

## What you learned

- **Read the error.** The app returned `503` with the real cause (`password authentication failed`) instead of crashing. Honest error handling turns a 30-minute mystery into a 30-second diagnosis.
- **Split the problem**: is the dependency (the database) down, or is your connection to it wrong? Testing the database directly with the known-good password proved it was a config problem, not an outage.
- **Config lives in the environment**, so the fix is a config change plus a restart - never a code edit. If the real password had actually changed, the correct move is to update the secret in config (or the secrets manager) and restart, never to hardcode it in `app.py`.

## Prevention

- Store DB credentials in a secrets manager and have the app read them at startup, so a rotation updates automatically.
- Add a startup health check that fails loudly if the database is unreachable, so a bad deploy is caught immediately, not by the first user.
- Keep a `.env.example` in the repo (with blank values) so everyone knows which variables are required.

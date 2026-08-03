# SURVIVE Runbook: Auth Misconfiguration Exposes an Admin Endpoint

**Scenario:** a security scan (or a curious user) found an admin endpoint that returns every user's role, clearance, and **API token** - with no login required. Someone added an "internal debug" route and forgot the authorization dependency. This is Broken Access Control, the number-one API security risk.

**Your job:** confirm the exposure, lock it down, and prove the real admin API still works for real admins.

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, with Project 9 in `~/project9`.

---

## Step 1: Confirm the exposure

On your **lab server**, as **ec2-user**:

```bash
cd ~/project9
```

Call the suspect endpoint with **no credentials at all**:

```bash
curl -s http://127.0.0.1:8000/admin/debug/users
```

Expected output (the leak):

```
{"users":[{"username":"alice","role":"user","clearance":2,"api_token":"token-alice"},{"username":"admin","role":"admin","clearance":4,"api_token":"token-admin"}]}
```

That is a live secret leak. Any anonymous caller can read every user's bearer token and then impersonate the admin. This is a **critical** finding - treat it as an incident.

---

## Step 2: Compare against a properly protected route

The real admin route is protected. Prove the contrast - call it with no credentials:

Still on the **lab server**, as **ec2-user**:

```bash
curl -s http://127.0.0.1:8000/admin/users
```

Expected output:

```
{"detail":"not authenticated"}
```

So the pattern already exists and works; the debug route simply skipped it. The fix is to make the bad route follow the same rule (or delete it).

---

## Step 3: Find the offending code

Search `app.py` for admin routes and check which one lacks the auth dependency.

Still on the **lab server**, as **ec2-user**:

```bash
grep -n "admin" app.py
```

Expected output (yours will differ):

```
...
138:def admin_users(admin: dict = Depends(auth.require_admin)) -> dict:
...
185:@app.get("/admin/debug/users")
186:def admin_debug_users() -> dict:
```

Look at the difference: `admin_users` has `Depends(auth.require_admin)`; `admin_debug_users` has an empty `()`. That missing dependency is the whole bug.

---

## Step 4: Remove the leaky route

The debug route has no business existing in production. The cleanest fix is to delete it. Open the file with `vi`:

Still on the **lab server**, as **ec2-user**:

```bash
vi app.py
```

Scroll to the bottom. Find the injected block, which is clearly marked:

```
# ----- INJECTED BY SURVIVE (auth misconfiguration) -----
...
# ----- END INJECTED -----
```

Delete every line from the `# ----- INJECTED` comment through the `# ----- END INJECTED -----` comment. In `vi`, put the cursor on the first `# ----- INJECTED` line, then delete to the end of the block. A quick way: with the cursor on that line, type

```
dG
```

`dG` deletes from the current line to the end of the file (the injected block is the last thing in the file). Then save and quit: press `Esc`, type `:wq`, press Enter.

If you would rather keep a debug route (some teams do), the alternative fix is to add the dependency instead of deleting: change `def admin_debug_users() -> dict:` to `def admin_debug_users(admin: dict = Depends(auth.require_admin)) -> dict:`. Deleting is safer here because the route also leaks raw tokens, which no endpoint should ever return.

---

## Step 5: Restart the API

Config and code are loaded at startup, so restart to pick up the fix.

Still on the **lab server**, as **ec2-user**, stop the running API:

```bash
pkill -f "uvicorn app:app"
```

Load your environment:

```bash
set -a; . ./.env; set +a
```

Start it again in the background:

```bash
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

Give it a couple of seconds:

```bash
sleep 3
```

---

## Step 6: Verify the hole is closed

Still on the **lab server**, as **ec2-user**, call the leaky route again:

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8000/admin/debug/users
```

Expected output:

```
404
```

`404` means the route no longer exists. (If you chose to protect instead of delete, you would see `401` here - also acceptable.)

Now prove you did not break the real admin API - call it as a real admin:

```bash
curl -s -H "Authorization: Bearer token-admin" http://127.0.0.1:8000/admin/users
```

Expected output (yours will differ):

```
{"users":[{"username":"alice","email":"alice@example.com","role":"user","clearance":2},{"username":"admin","email":"admin@example.com","role":"admin","clearance":4}]}
```

The admin who should have access still does.

---

## Step 7: Rotate the exposed tokens

The tokens were exposed to anyone while the hole was open. Exposed secrets are compromised - closing the hole does not un-leak them. Rotate them.

Still on the **lab server**, as **ec2-user**:

```bash
set -a; . ./.env; set +a
```

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "UPDATE app_users SET api_token = 'token-' || substr(md5(random()::text),1,16) WHERE api_token IS NOT NULL;"
```

Expected output:

```
UPDATE 2
```

New tokens are issued; the leaked ones no longer work. (For the validator below we keep `token-admin` working, so in the lab you may skip this step or re-seed; in production, rotation is mandatory.)

---

## Step 8: Validate

Run the checker:

```bash
bash ~/project9/survive/auth-misconfig-admin-exposed/validate.sh
```

Expected output:

```
OK: /admin/debug/users no longer leaks to anonymous (HTTP 404)
OK: authenticated admin can still reach /admin/users
OK: /admin/users rejects anonymous (HTTP 401)
OK: every /admin route in app.py requires admin
PASS: admin surface locked down; admin API still works.
```

Note: if you rotated tokens in Step 7, re-seed the demo token first so the validator's `token-admin` works: `PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -f sql/seed.sql`.

---

## What you learned

- **Authentication is not authorization.** Knowing who a caller is (authn) is separate from what they may do (authz). The leaky route had neither. Every admin route must depend on an explicit authorization check.
- **Make the secure path the default.** Relying on each developer to remember `Depends(require_admin)` fails eventually. Better: put all admin routes under a router with the dependency applied once (`APIRouter(dependencies=[Depends(require_admin)])`), so a new route is protected unless someone actively opts out.
- **Never return secrets in an API response.** No endpoint should ever return a raw token or password, even to an admin. That the debug route did made the exposure far worse.
- **Closing a hole does not un-leak a secret.** Anything exposed while the hole was open is compromised - rotate it. Fix, then rotate, then verify.
- **Test authz, not just authn.** Your test suite should assert that a normal user gets 403 on admin routes and an anonymous caller gets 401 - the negative cases are the ones attackers use.

Prof. Happy (SUTA Labs)

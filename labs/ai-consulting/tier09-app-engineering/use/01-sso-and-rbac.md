# USE: Add SSO (OIDC) and Role-Based Admin Controls, and Document the Identity Flow

**Goal:** the BUILD gave you a working login and an admin role. Now you will make the authorization model real: add a THIRD role (`auditor`) that can read the audit log but cannot ingest, wire a new admin route behind the role check, and write up the identity flow the way you would hand it to a security reviewer. This is the everyday work of turning "it has a login" into "it has an access-control model."

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, Project 9 in `~/project9`, virtual environment available, database seeded.

**What you will practice:** OIDC login, server-side sessions, roles, the `require_admin` pattern generalized to `require_role`, and documenting an identity flow.

---

## Step 1: Trace the identity flow you already have

Before changing anything, understand the flow. Log in and watch each hop.

On your **lab server**, as **ec2-user**, in `~/project9`:

```bash
cd ~/project9
```

Load config and make sure the API is running:

```bash
set -a; . ./.env; set +a
```

```bash
pgrep -f "uvicorn app:app" >/dev/null || nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

Log in as the admin and keep the cookie:

```bash
curl -s -i -c admin.cookies -X POST http://127.0.0.1:8000/login -H "Content-Type: application/json" -d '{"email":"admin@example.com"}' | grep -i "set-cookie\|username"
```

Expected output (yours will differ):

```
set-cookie: session=Xk9....; HttpOnly; Path=/; SameSite=lax; Max-Age=28800
{"username":"admin","role":"admin"}
```

Trace it: you sent an email (the mock stand-in for "the IdP verified this email"), the server matched it to an `app_users` row, created a row in the `sessions` table, and returned an opaque `session` cookie marked `HttpOnly` (JavaScript cannot read it) and `SameSite=lax` (basic CSRF protection). Every later request just sends that cookie; the trust lives in the database, not the browser.

Confirm the session row exists:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "SELECT s.id IS NOT NULL AS has_session, u.username, u.role FROM sessions s JOIN app_users u ON u.id=s.user_id ORDER BY s.created_at DESC LIMIT 1;"
```

Expected output (yours will differ):

```
 has_session | username | role
-------------+----------+-------
 t           | admin    | admin
(1 row)
```

---

## Step 2: Add an `auditor` role in the database

You want a role that can read the audit log but cannot ingest documents. First relax the role check constraint and add the user.

Still on the **lab server**, as **ec2-user**, allow the new role value:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "ALTER TABLE app_users DROP CONSTRAINT IF EXISTS role_valid; ALTER TABLE app_users ADD CONSTRAINT role_valid CHECK (role IN ('user','admin','auditor'));"
```

Expected output:

```
ALTER TABLE
ALTER TABLE
```

Add the auditor user with a bearer token so you can test it without a browser:

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "INSERT INTO app_users (username, email, api_token, role, clearance) VALUES ('auditor','auditor@example.com','token-auditor','auditor',4) ON CONFLICT (username) DO UPDATE SET role='auditor', api_token='token-auditor';"
```

Expected output:

```
INSERT 0 1
```

---

## Step 3: Generalize the role check

`auth.py` has `require_admin`. Add a general `require_role` so you can protect a route with any role. Open the file:

Still on the **lab server**, as **ec2-user**:

```bash
vi auth.py
```

Press `i` to enter insert mode. Below the existing `require_admin` function, add:

```python
def require_role(*allowed_roles: str):
    """Build a dependency that requires the caller to have one of the roles.

    Usage in app.py:
        @app.get("/admin/audit")
        def audit(user: dict = Depends(auth.require_role("admin", "auditor"))):
            ...
    """
    def _dep(authorization: str = Header(default=""),
             session: str = Cookie(default="")) -> dict:
        user = current_user(authorization=authorization, session=session)
        if user["role"] not in allowed_roles:
            raise HTTPException(status_code=403,
                                detail=f"role must be one of: {', '.join(allowed_roles)}")
        return user
    return _dep
```

Press `Esc`, then type `:wq` and press Enter to save.

This is a dependency factory: `require_role("admin","auditor")` returns a dependency that lets either role through. `require_admin` still exists for the routes that must be admin-only.

---

## Step 4: Add an audit-log route behind the new role

Now expose the audit log to admins and auditors, but not normal users. Open `app.py`:

Still on the **lab server**, as **ec2-user**:

```bash
vi app.py
```

Press `i`. In the admin-routes section (near the other `/admin/*` routes), add:

```python
@app.get("/admin/audit")
def admin_audit(user: dict = Depends(auth.require_role("admin", "auditor"))) -> dict:
    """Recent audit-log entries. Readable by admins and auditors."""
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT username, action, detail, created_at "
                        "FROM audit_log ORDER BY id DESC LIMIT 20")
            rows = cur.fetchall()
    return {"entries": [{"username": r[0], "action": r[1], "detail": r[2],
                         "when": r[3].isoformat()} for r in rows]}
```

Press `Esc`, type `:wq`, press Enter.

---

## Step 5: Restart and test all three roles

Restart to load the new code.

Still on the **lab server**, as **ec2-user**:

```bash
pkill -f "uvicorn app:app"
```

```bash
nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

```bash
sleep 3
```

Auditor CAN read the audit log:

```bash
curl -s -o /dev/null -w "auditor -> /admin/audit : %{http_code}\n" -H "Authorization: Bearer token-auditor" http://127.0.0.1:8000/admin/audit
```

Expected output:

```
auditor -> /admin/audit : 200
```

Auditor CANNOT ingest (that route is admin-only):

```bash
curl -s -o /dev/null -w "auditor -> /admin/ingest : %{http_code}\n" -H "Authorization: Bearer token-auditor" -X POST http://127.0.0.1:8000/admin/ingest -H "Content-Type: application/json" -d '{"title":"x","source":"x.txt","body":"hello world"}'
```

Expected output:

```
auditor -> /admin/ingest : 403
```

Normal user (alice) CANNOT read the audit log:

```bash
curl -s -o /dev/null -w "alice   -> /admin/audit : %{http_code}\n" -H "Authorization: Bearer token-alice" http://127.0.0.1:8000/admin/audit
```

Expected output:

```
alice   -> /admin/audit : 403
```

Three roles, three different privilege sets, all enforced server-side. That is a real authorization model, not just a login.

---

## Step 6: Document the identity flow

A reviewer will ask "how does someone become authenticated and authorized here?" Write it down. Create a short doc:

Still on the **lab server**, as **ec2-user**:

```bash
vi IDENTITY_FLOW.md
```

Press `i` and write the flow in your own words. It should cover, in order:

1. **Login (authentication).** In production: user hits `/login`, is redirected to the OIDC identity provider, authenticates there, and is redirected back with an authorization code. The app exchanges the code for an ID token (a signed JWT) and reads the verified `email` claim. In the lab (`OIDC_MODE=mock`) the email is supplied directly to stand in for that verified claim.
2. **Session issuance.** The app matches the email to an `app_users` row, inserts a row in `sessions` with an expiry, and sets an opaque `HttpOnly`, `SameSite=lax` cookie. The browser never holds identity data, only the cookie.
3. **Per-request identity.** `current_user` resolves the caller by session cookie OR `Authorization: Bearer <token>` (service accounts). If neither resolves, it returns `401`.
4. **Authorization.** `require_admin` / `require_role(...)` check the user's `role` and return `403` if it is not allowed. Authentication (who) and authorization (what) are separate steps.
5. **Roles today:** `user` (ask only), `admin` (all admin routes), `auditor` (read the audit log, no ingest).
6. **Secrets:** session ids come from `secrets.token_urlsafe`; no password is stored by the app (the IdP owns that); bearer tokens are plain in the lab but must be hashed and rotatable in production.

Press `Esc`, type `:wq`, press Enter.

Confirm it saved:

```bash
head -5 IDENTITY_FLOW.md
```

Expected output (yours will differ):

```
# Identity Flow - Project 9
1. Login (authentication): ...
```

---

## What you learned

- **Authentication and authorization are separate.** Adding a role did not touch login at all - it changed only the "what may they do" check.
- **A dependency factory scales access control.** `require_role(*roles)` lets every route declare exactly who may call it, in one line, next to the route. That is how you keep authorization visible and auditable.
- **Server-side sessions keep trust off the client.** The browser holds an opaque cookie; the role and clearance live in the database, so you can revoke a session or change a role instantly.
- **Document the identity flow.** A written flow is what a security reviewer, a new teammate, and future-you actually need. If you cannot write it clearly, the model is not clear.

Prof. Happy (SUTA Labs)

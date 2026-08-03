# BUILD: Project 9 - Enterprise-Ready Knowledge Assistant

**Tier 9 - the capstone build.** You will take the RAG prototype idea from Tier 7 and turn it into an enterprise-ready application: SSO login (OIDC), role-based admin controls, a connection pool, an API gateway, secrets from the environment, background document ingestion via a worker, a monitoring endpoint, a backup-and-restore drill, and a documented deployment architecture. When you finish, you have an app you could actually put in front of a company.

**Validated on:** CentOS Stream 9, PostgreSQL 13, Python 3.12, Docker, in 2026. All output shown is real (truncated where long). Your numbers and timestamps will differ.

**Prerequisite:** you finished the Phase 0 environment setup - Python 3.12, Docker, and PostgreSQL with the `labuser` / `labdb` / `labpass` database are all working.

The project files live in `project9-enterprise-app/` next to this guide:

```
app.py            FastAPI backend (routes, auth wiring, metrics)
auth.py           OIDC login, sessions, current_user + require_admin
db.py             PostgreSQL connection POOL
retrieval.py      retrieve + generate (mock LLM fallback, no key needed)
worker.py         background ingestion worker (drains the job queue)
test_app.py       tests that need no database and no API key
requirements.txt  pinned dependencies
.env.example      documents every config var (copy to .env)
Dockerfile        container image (API and worker share it)
docker-compose.yml   the whole deployment: gateway + api + worker + db
gateway.conf      nginx API gateway config
backup.sh         pg_dump backup
restore.sh        restore into an isolated DB and verify
sql/schema.sql    tables (users, sessions, documents, chunks, jobs, audit)
sql/seed.sql      demo users + a couple of documents
templates/index.html   the minimal web UI
static/style.css, static/app.js   the frontend
```

---

## Step 1: Put the files on your server

On your **lab server** (CentOS Stream 9), as **ec2-user**, create the project folder and copy in the files from this repo.

```bash
mkdir -p ~/project9
```

Copy every file listed above into `~/project9`, keeping the `sql/`, `templates/`, and `static/` subfolders. Then move into the folder:

```bash
cd ~/project9
```

Confirm the layout:

```bash
ls
```

Expected output (yours will differ):

```
app.py     backup.sh    docker-compose.yml  gateway.conf  requirements.txt  sql
auth.py    db.py        Dockerfile          index.html    restore.sh        static
```

---

## Step 2: Create your environment file

The app reads ALL config from environment variables. Copy the template and keep the lab defaults.

Still on the **lab server**, as **ec2-user**, in `~/project9`:

```bash
cp .env.example .env
```

Look at what is in it:

```bash
cat .env
```

Expected output (truncated):

```
DB_HOST=127.0.0.1
DB_NAME=labdb
DB_USER=labuser
DB_PASSWORD=labpass
...
OIDC_MODE=mock
# ANTHROPIC_API_KEY=sk-ant-...
```

Two things to notice. `OIDC_MODE=mock` lets you log in without a real identity provider (the class box has none). `ANTHROPIC_API_KEY` is commented out, so the app uses the offline MOCK answer generator - no paid key needed, everything still runs.

The `.env` file holds secrets, so it must never be committed. Confirm it is ignored:

```bash
echo ".env" >> .gitignore
```

`>>` appends the line. Committing `.env.example` (blank values) documents what is required; committing `.env` (real values) leaks secrets.

---

## Step 3: Create the database schema and seed data

Load the tables, then the demo users and starter documents.

Still on the **lab server**, as **ec2-user**, in `~/project9`, create the schema:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -f sql/schema.sql
```

Expected output (yours will differ):

```
CREATE TABLE
CREATE TABLE
CREATE TABLE
CREATE INDEX
...
```

Now seed the demo users and documents:

```bash
PGPASSWORD=labpass psql -h 127.0.0.1 -U labuser -d labdb -f sql/seed.sql
```

Expected output:

```
INSERT 0 2
INSERT 0 2
INSERT 0 1
INSERT 0 1
```

That created two users - `alice` (role `user`, email `alice@example.com`) and `admin` (role `admin`, email `admin@example.com`) - and two documents with their chunks.

---

## Step 4: Create a virtual environment and install requirements

Still on the **lab server**, as **ec2-user**, in `~/project9`:

```bash
python3.12 -m venv .venv
```

`venv` makes an isolated Python so project packages do not collide with the system. Activate it:

```bash
source .venv/bin/activate
```

Your prompt now starts with `(.venv)`. Install the pinned dependencies:

```bash
pip install -r requirements.txt
```

Confirm the key packages landed:

```bash
pip list | grep -Ei "fastapi|uvicorn|psycopg2|pytest"
```

Expected output (yours will differ):

```
fastapi           0.115.0
psycopg2-binary   2.9.9
pytest            8.3.2
uvicorn           0.30.6
```

---

## Step 5: Run the tests

The tests cover the pure logic (the chunker and the mock generator) with no database and no key, so they run fast.

Still in the activated environment:

```bash
python -m pytest -q
```

Expected output (yours will differ):

```
.....                                                                    [100%]
5 passed in 0.03s
```

Five passed. Never move on with a red test.

---

## Step 6: Start the API

Start the web server in the background. It reads config from your `.env`, so load that first.

Still on the **lab server**, as **ec2-user**, in `~/project9`:

```bash
set -a; . ./.env; set +a
```

`set -a` marks everything that follows for export; sourcing `.env` loads the variables; `set +a` turns that off. Now start the server:

```bash
nohup uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

`uvicorn` is the server; `app:app` means "the `app` object inside `app.py`"; `nohup ... &` runs it detached with output going to `uvicorn.log`. Give it a couple of seconds, then check health:

```bash
curl -s http://127.0.0.1:8000/health
```

Expected output:

```
{"status":"ok","database":true}
```

`"database":true` means the API opened a pooled connection and the database answered. If you see `"degraded"`, the database is unreachable - check your `.env`.

---

## Step 7: Log in with SSO and get a session

The app uses OIDC login. In mock mode you present an email; a real deployment would redirect you to your identity provider. On success the server sets a session cookie.

Still on the **lab server**, as **ec2-user**, log in as `alice` and save the cookie to a file:

```bash
curl -s -c alice.cookies -X POST http://127.0.0.1:8000/login -H "Content-Type: application/json" -d '{"email":"alice@example.com"}'
```

`-c alice.cookies` tells curl to save the session cookie the server sets. Expected output:

```
{"username":"alice","role":"user"}
```

You are now signed in as a normal user. Check who the server thinks you are, sending the cookie back with `-b`:

```bash
curl -s -b alice.cookies http://127.0.0.1:8000/me
```

Expected output:

```
{"username":"alice","role":"user","clearance":2}
```

The server looked up your session in the `sessions` table and resolved your identity. The browser never sees anything but an opaque cookie.

---

## Step 8: Ask a question (grounded answer with citations)

Ask something the seeded documents can answer, sending your session cookie:

Still on the **lab server**, as **ec2-user**:

```bash
curl -s -b alice.cookies -X POST http://127.0.0.1:8000/ask -H "Content-Type: application/json" -d '{"query":"what is the meal expense cap?"}'
```

Expected output (yours will differ):

```
{"answer":"[MOCK] Based on the retrieved context: Employees may expense meals up to 40 dollars per day while travelling. Receipts are required for any single item over 25 dollars. [1]","generator":"mock","citations":[{"n":1,"source":"expense-policy.txt"}],"retrieved":2,"user":"alice","latency_ms":0}
```

The `[MOCK]` prefix tells you the offline generator answered (no API key set). The answer is grounded in the retrieved chunk and cites it with `[1]`. If you later set a real `ANTHROPIC_API_KEY` in `.env`, `generator` becomes the model name and the answer is model-written - the retrieval and citation plumbing is identical either way.

---

## Step 9: Prove role-based access control

Alice is a normal user, not an admin. Try to reach an admin route with her cookie:

Still on the **lab server**, as **ec2-user**:

```bash
curl -s -b alice.cookies http://127.0.0.1:8000/admin/users
```

Expected output:

```
{"detail":"admin role required"}
```

That is a `403`. Authentication succeeded (the server knows she is alice), but authorization failed (she lacks the admin role). Authentication and authorization are two different checks - this proves the app enforces both.

Now log in as the admin and save that cookie:

```bash
curl -s -c admin.cookies -X POST http://127.0.0.1:8000/login -H "Content-Type: application/json" -d '{"email":"admin@example.com"}'
```

Expected output:

```
{"username":"admin","role":"admin"}
```

List users as the admin:

```bash
curl -s -b admin.cookies http://127.0.0.1:8000/admin/users
```

Expected output (yours will differ):

```
{"users":[{"username":"alice","email":"alice@example.com","role":"user","clearance":2},{"username":"admin","email":"admin@example.com","role":"admin","clearance":4}]}
```

The admin route works for an admin and is blocked for everyone else. That is RBAC.

---

## Step 10: Confirm a service-account (bearer token) also works

Non-human callers - scripts, other services - authenticate with a bearer token instead of a browser session. The admin seed row has the token `token-admin`.

Still on the **lab server**, as **ec2-user**:

```bash
curl -s -H "Authorization: Bearer token-admin" http://127.0.0.1:8000/admin/users
```

Expected output (same as the cookie version):

```
{"users":[{"username":"alice","email":"alice@example.com","role":"user","clearance":2},{"username":"admin","email":"admin@example.com","role":"admin","clearance":4}]}
```

Same authorization rules, different credential. And with no credential at all, the app refuses:

```bash
curl -s -X POST http://127.0.0.1:8000/ask -H "Content-Type: application/json" -d '{"query":"x"}'
```

Expected output:

```
{"detail":"not authenticated"}
```

A clean `401` - the app never answers an unauthenticated caller.

---

## Step 11: Enqueue a document for background ingestion

Adding a document is slow work (chunking, indexing). The API does NOT do it inside the request - it enqueues a job and returns immediately. A separate worker does the real work. This is the synchronous-versus-asynchronous split.

Still on the **lab server**, as **ec2-user**, enqueue a document as the admin:

```bash
curl -s -H "Authorization: Bearer token-admin" -X POST http://127.0.0.1:8000/admin/ingest -H "Content-Type: application/json" -d '{"title":"Remote Work Policy","source":"remote-work.txt","body":"Remote employees must be reachable during core hours 10am to 3pm.\n\nCompany laptops must have full disk encryption enabled.","access_level":1}'
```

Expected output:

```
{"job_id":1,"status":"queued"}
```

You got a job id back instantly - the request did not wait for the document to be processed. Check the queue:

```bash
curl -s -H "Authorization: Bearer token-admin" http://127.0.0.1:8000/admin/jobs
```

Expected output (yours will differ):

```
{"jobs":[{"id":1,"title":"Remote Work Policy","source":"remote-work.txt","status":"queued","attempts":0,"last_error":null,"updated_at":"..."}]}
```

Status `queued`. Nothing has processed it yet because the worker is not running.

---

## Step 12: Run the background worker

The worker is a separate process. Run it once to drain the queue.

Still on the **lab server**, as **ec2-user**, in the activated environment:

```bash
python worker.py --once
```

`--once` drains everything queued and exits (leave off `--once` to run it forever). Expected output (yours will differ):

```
[worker] job 1 done: 1 chunks from remote-work.txt
[worker] processed 1 job(s).
```

Check the queue again:

```bash
curl -s -H "Authorization: Bearer token-admin" http://127.0.0.1:8000/admin/jobs
```

Expected output (yours will differ):

```
{"jobs":[{"id":1,"title":"Remote Work Policy","source":"remote-work.txt","status":"done","attempts":0,"last_error":null,"updated_at":"..."}]}
```

Status `done`. Now the new document is searchable - ask about it:

```bash
curl -s -H "Authorization: Bearer token-admin" -X POST http://127.0.0.1:8000/ask -H "Content-Type: application/json" -d '{"query":"disk encryption laptops"}'
```

Expected output (yours will differ):

```
{"answer":"[MOCK] Based on the retrieved context: Remote employees must be reachable during core hours 10am to 3pm. Company laptops must have full disk encryption enabled. [1]","generator":"mock","citations":[{"n":1,"source":"remote-work.txt"}],"retrieved":1,"user":"admin","latency_ms":0}
```

You just proved the full async pipeline: enqueue -> queued -> worker processes -> done -> queryable.

---

## Step 13: Check the monitoring endpoint

Operability means you can see what the app is doing. `/metrics` reports request volume, latency, the ingestion queue, and the connection pool.

Still on the **lab server**, as **ec2-user**:

```bash
curl -s http://127.0.0.1:8000/metrics
```

Expected output (yours will differ):

```
{"ask_count":2,"avg_latency_ms":0.0,"max_latency_ms":0,"ingest_queue":{"queued":0,"processing":0,"done":1,"failed":0},"db_pool":{"min":1,"max":5,"initialized":true}}
```

`db_pool.initialized:true` confirms the connection pool is live. `ingest_queue` is your early warning for a backed-up queue. These are the numbers a Grafana dashboard would chart.

---

## Step 14: Take a backup and prove it restores

A backup you have never restored is not a backup - it is a hope. Take one, then prove it.

Still on the **lab server**, as **ec2-user**, in `~/project9`, take a backup:

```bash
bash backup.sh
```

Expected output (yours will differ):

```
[backup] dumping labdb to ./backups/labdb-20260101-120000.dump
[backup] done: ./backups/labdb-20260101-120000.dump (16K)
[backup] REMEMBER: an untested backup is not a backup. Run restore.sh.
```

The restore drill restores into a SEPARATE database (`labdb_restore`) so it can never harm the live one, then verifies the row counts. It needs the `labuser` role to be able to create a database. Grant that once - switch to the postgres superuser:

```bash
sudo su - postgres
```

Now, as **postgres**, allow `labuser` to create databases:

```bash
psql -c "ALTER ROLE labuser CREATEDB;"
```

Expected output:

```
ALTER ROLE
```

Return to your own user:

```bash
exit
```

You are **ec2-user** again. Run the restore drill:

```bash
bash restore.sh
```

Expected output (yours will differ):

```
[restore] using dump: backups/labdb-20260101-120000.dump
[restore] recreating labdb_restore
[restore] restoring into labdb_restore
[restore] restored app_users=2 chunks=3
PASS: backup restored and verified (2 users, 3 chunks).
```

`PASS` means the backup is real and restorable. You now have a proven recovery path.

---

## Step 15: See the web UI (optional)

Open a browser to `http://<your-server-public-ip>:8000/`. You get a small page: sign in with `alice@example.com` or `admin@example.com`, ask a question, and (as admin) enqueue a document. It is plain HTML plus vanilla JavaScript calling the same API you just used with `curl` - no build tool, no framework. If you cannot open the port, the `curl` steps already proved every route.

Stop the API when you are done experimenting:

```bash
pkill -f "uvicorn app:app"
```

---

## Step 16: Run the whole thing as a deployment (optional, needs Docker)

`docker-compose.yml` is the deployment architecture as code:

```
client -> gateway (nginx) -> api (FastAPI) -> db (PostgreSQL)
                             worker         -> db
```

The gateway is the single public entry point (rate limiting, request-size caps, one place for TLS). The api and worker are the same image with different commands. The database holds all state.

Still on the **lab server**, as **ec2-user**, in `~/project9` (make sure `.env` exists), bring it up:

```bash
docker compose up -d --build
```

Give the containers a moment, then hit the app THROUGH the gateway on port 8080:

```bash
curl -s http://127.0.0.1:8080/health
```

Expected output:

```
{"status":"ok","database":true}
```

You reached the API through the nginx gateway - the API container itself is not published to the outside. Tear it down when done:

```bash
docker compose down
```

---

## What you built

- A **FastAPI backend** with request validation (Pydantic), real error responses (401/403/503, never a fake 200), and auto-generated API docs at `/docs`.
- **SSO login (OIDC)** issuing server-side sessions, plus **bearer tokens** for service accounts.
- **Role-based admin controls** - every admin route gated by `require_admin`.
- A **connection pool** so bursts of traffic reuse connections instead of exhausting the database.
- **Background ingestion** - the API enqueues, a separate **worker** drains the queue - the sync-vs-async split.
- **Secrets from the environment** only (12-factor); nothing hardcoded, nothing in the image.
- A **monitoring** endpoint, a **backup + verified restore** drill, and a **documented deployment** (gateway + api + worker + db) as compose.

Next: the USE exercises deepen the SSO/RBAC and architecture-diagram work, and the SURVIVE scenarios break this app four ways (queue backup, exposed admin endpoint, connection storm, data loss) so you can prove you can operate it under fire.

Prof. Happy (SUTA Labs)

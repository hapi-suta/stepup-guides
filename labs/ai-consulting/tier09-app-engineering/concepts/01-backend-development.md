# Module 9.1 - Backend Development

**Read this before you touch the keyboard.** A backend is the part of your app users never see but always depend on. It takes requests, checks who is asking, decides what they are allowed to do, talks to the database, and sends back an honest answer. In this tier you build Project 9 - a small AI question-answering service in FastAPI. This document explains every backend idea you will meet in that project, and WHY each choice was made, not just what to type. Read it once now, then keep it open while you code.

The stack you are building on:

| Piece | What we use | Why |
|---|---|---|
| Language | Python 3.12 | Modern async support, type hints |
| Web framework | FastAPI | Automatic validation and docs from type hints |
| Server | uvicorn | Fast ASGI server that runs FastAPI |
| Database | PostgreSQL (labdb, user labuser, password labpass) | Reliable, transactional, everywhere in the industry |
| Packaging | Docker | Same environment on your box and in production |
| Box | CentOS Stream 9, login user ec2-user | Your lab server |

The app lives in `app.py`. Supporting logic lives in `auth.py` (who you are), `db.py` (talking to Postgres), and `worker.py` (slow background work).

## 1. FastAPI

FastAPI is a Python web framework. You write plain Python functions and decorate them so a URL maps to a function. When a request arrives for that URL, FastAPI runs your function and turns whatever you return into an HTTP response.

Here are the real routes Project 9 exposes in `app.py`:

| Method + Path | Purpose |
|---|---|
| GET /health | Liveness check, no auth |
| GET / | HTML user interface |
| POST /login | Start an OIDC login |
| POST /logout | End the session |
| GET /me | Return the current user |
| POST /ask | Ask the AI a question |
| GET /metrics | Operational metrics |
| GET /admin/users | List users (admin only) |
| POST /admin/ingest | Queue a document ingest job (admin only) |
| GET /admin/jobs | See ingest job status (admin only) |

A minimal route looks like this:

```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/health")
def health():
    return {"status": "ok"}
```

The `@app.get("/health")` decorator says "when someone does GET /health, call this function." FastAPI serializes the returned dict into JSON automatically. You never write the raw HTTP by hand. That is the whole appeal - you focus on logic, the framework handles the plumbing.

You run it with uvicorn:

```bash
uvicorn app:app --host 0.0.0.0 --port 8000
```

The first `app` is the file `app.py`, the second `app` is the `FastAPI()` object inside it.

## 2. Request Validation

Never trust input from the outside world. A caller can send a missing field, a string where you wanted a number, or garbage designed to break you. Validation means: check the shape of the request BEFORE your logic runs, and reject bad input with a clear error.

FastAPI does this with Pydantic. You declare the shape as a class and FastAPI enforces it:

```python
from pydantic import BaseModel

class AskRequest(BaseModel):
    query: str
    k: int = 3
```

This says `/ask` needs a `query` that is a string, and an optional `k` that is an integer defaulting to 3. Wire it into the route:

```python
@app.post("/ask")
def ask(req: AskRequest, user = Depends(current_user)):
    ...
```

Now if a caller sends `{"query": 123}` or forgets `query` entirely, FastAPI rejects it with a 422 response describing exactly what was wrong - and your function never even runs. This is why validation belongs at the edge. Your business logic can assume the data is already clean, which keeps that code simple and safe.

WHY a default of 3 for `k`? It means "return the top 3 matches" for the AI search. A default makes the field optional without forcing every caller to think about it.

## 3. Authentication

Authentication answers one question: WHO are you? It does not decide what you can do - that is the next section. Project 9 accepts two proofs of identity, both resolved in `auth.py`.

First, a session cookie. After a user logs in through OIDC (an identity provider), the server creates a session and hands the browser a cookie. On every later request the browser sends the cookie back, and the server looks it up.

Second, an API token. A machine or script that cannot do a browser login sends a header instead:

```
Authorization: Bearer <api_token>
```

Both paths end at one dependency, `current_user()`, which figures out which proof was supplied and returns the matching user, or fails if neither is valid:

```python
from fastapi import Depends, HTTPException

def current_user(...):
    user = resolve_session_cookie(...) or resolve_bearer_token(...)
    if not user:
        raise HTTPException(status_code=401, detail="not authenticated")
    return user
```

Any route that needs a logged-in user just declares `Depends(current_user)`. FastAPI runs it first, and if it raises, your route body never executes. One place to check identity, reused everywhere - that is the point of a dependency.

## 4. Authorization

Authorization is a SEPARATE question from authentication: given that we know who you are, are you ALLOWED to do this? Mixing the two is a classic security bug. A logged-in user is authenticated, but that does not make them an admin.

Project 9 keeps them separate. `current_user()` proves identity. A second dependency, `require_admin()`, checks the user's role:

```python
def require_admin(user = Depends(current_user)):
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="admin role required")
    return user
```

Notice it depends on `current_user` first. So the chain is: authenticate, then authorize. The admin routes use it:

```python
@app.get("/admin/users")
def admin_users(user = Depends(require_admin)):
    ...
```

A normal user hitting `/admin/users` is authenticated fine but gets a 403. The difference between 401 and 403 matters: 401 means "I do not know who you are," 403 means "I know who you are and you still cannot do this."

## 5. Sessions

HTTP is stateless - each request stands alone and the server forgets you between requests. Sessions are how we remember a logged-in browser across many requests.

Project 9 uses SERVER-SIDE sessions. The real session data lives in a `sessions` table in Postgres. Each row has an opaque id and an `expires_at` timestamp. The browser only holds a cookie named `session` containing that opaque id - nothing else.

```python
import secrets

session_id = secrets.token_urlsafe(32)
# INSERT into sessions (id, user_id, expires_at) VALUES (...)
```

`secrets.token_urlsafe(32)` draws 32 random bytes (256 bits of entropy) from the operating system's cryptographically secure source and encodes them URL-safely. OWASP asks for at least 64 bits of entropy in a session id to resist brute-force guessing, so 256 bits is comfortably above the bar (see: https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html).

The cookie should be set with three important flags:

- `HttpOnly` - JavaScript in the browser cannot read the cookie, which blocks a whole class of cross-site scripting theft (see: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie).
- `SameSite=Lax` - the browser will not send the cookie on most cross-site subrequests (images, frames, cross-site POSTs), which blunts cross-site request forgery. Note this is a partial CSRF defense: `Lax` still allows the cookie on top-level navigations, so an attacker can trigger a GET-driven navigation. `Strict` is stronger, and OWASP recommends pairing SameSite with other CSRF defenses (fetch metadata or CSRF tokens) (see: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie/SameSite).
- `Secure` - the browser only sends the cookie over HTTPS, so it is never exposed on a plain-HTTP connection. In production always set `Secure`; OWASP lists HttpOnly, Secure, and SameSite together as the baseline for session cookies (see: https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html). On a local HTTP dev box you may drop `Secure`, but never in production.

WHY server-side and not put the data in the cookie itself? Because a server-side row can be deleted instantly to log someone out or revoke a stolen session. The `expires_at` column lets old sessions age out. The opaque `token_urlsafe` id is unguessable, so an attacker cannot forge one. The browser holds a meaningless string; all the trust lives on the server.

## 6. Background Jobs

Some work is too slow to do inside a request. Ingesting documents into the AI index can take minutes. If you did that inside `POST /admin/ingest`, the caller would sit there waiting, the connection might time out, and one slow job would tie up a worker. The fix is to split the work in two.

The request side, in `app.py`, only records the intent and returns immediately:

```python
@app.post("/admin/ingest")
def ingest(user = Depends(require_admin)):
    # INSERT INTO ingest_jobs (status) VALUES ('queued') RETURNING id
    return {"job_id": job_id, "status": "queued"}
```

The caller gets a `job_id` in a fraction of a second and can poll `GET /admin/jobs` later to see progress.

The work side is a completely separate process, `worker.py`, running on its own. It repeatedly claims queued jobs and does the slow work:

```sql
SELECT id FROM ingest_jobs
WHERE status = 'queued'
ORDER BY id
FOR UPDATE SKIP LOCKED
LIMIT 1;
```

`FOR UPDATE` locks the selected row against concurrent updates so no one else touches it. `SKIP LOCKED` tells other workers "if a row is already locked, skip past it and grab the next free one" instead of waiting. This is how you can run several workers at once without two of them fighting over the same job. The PostgreSQL manual calls out this exact use: skipping locked rows "can be used to avoid lock contention with multiple consumers accessing a queue-like table" (see: https://www.postgresql.org/docs/current/sql-select.html). This queue-in-a-table pattern is simple, durable (jobs survive a restart because they are rows in Postgres), and needs no extra message broker.

## 7. Async Programming

FastAPI lets you write a route two ways:

```python
@app.get("/a")
def sync_handler():      # normal function
    ...

@app.get("/b")
async def async_handler():   # coroutine
    ...
```

A `def` (sync) handler is run by FastAPI in an external threadpool, so a slow one does not freeze the whole server - other requests keep flowing on other threads. An `async def` handler runs directly on the main event loop and must never call a blocking operation, or it stalls every other request the loop is serving. This is FastAPI's documented behavior: a normal `def` path operation "is run in an external threadpool that is then awaited, instead of being called directly (as it would block the server)" (see: https://fastapi.tiangolo.com/async/).

In Project 9 our handlers are plain `def` (sync). We use psycopg2, which is a blocking database driver, so sync + threadpool is the correct and honest choice. Trying to `await` a blocking call would be a lie that hurts you.

The real lesson is not sync vs async syntax. It is this: a web request should be SHORT. The threadpool has a limited number of threads. If a single request runs for minutes (like document ingestion), it holds a thread the whole time and starves other users. That is exactly WHY ingestion goes to `worker.py` and not into the `/admin/ingest` handler. Fast work in the request, slow work in the background - that rule matters far more than which keyword you use.

## 8. Database Connections

Opening a fresh Postgres connection for every request is expensive - it involves a network round trip and authentication each time. A connection pool solves this by keeping a set of open connections ready to lend out and take back.

Project 9 uses a psycopg2 `ThreadedConnectionPool` in `db.py`. Its size comes from environment variables, `DB_POOL_MIN` and `DB_POOL_MAX`, never hardcoded. You borrow a connection through a context manager:

```python
from contextlib import contextmanager

@contextmanager
def get_conn():
    conn = pool.getconn()   # see note below on exhaustion behavior
    try:
        yield conn
    finally:
        pool.putconn(conn)  # ALWAYS returned, even on error
```

Used like this:

```python
with get_conn() as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT ...")
```

The `finally` is the heart of it. No matter what happens inside the `with` block - success, exception, early return - the connection goes back to the pool with `putconn`. Forget this and connections leak; after enough leaks the pool is empty and later requests fail. The psycopg docs are blunt about this: "After using `getconn()` you must call a corresponding `putconn()`; failing to do so will deplete the pool" (see: https://www.psycopg.org/docs/pool.html).

Know exactly what happens when the pool IS depleted, because it is a common misconception. The psycopg2 `ThreadedConnectionPool` does NOT block and wait for a free connection - when every connection is in use and it is already at `maxconn`, `getconn()` immediately raises `PoolError("connection pool exhausted")` (it fails fast rather than hanging). If you want borrow-with-timeout (wait up to N seconds, then error), that is a feature of the newer psycopg 3 pool, `psycopg_pool.ConnectionPool`, not of psycopg2's pool. So under a connection storm, plan to catch the `PoolError` and return a 503, not to rely on the pool queueing you. (see: https://www.psycopg.org/docs/pool.html, https://www.psycopg.org/psycopg3/docs/advanced/pool.html)

WHY read the size from the environment? Because of the twelve-factor rule: "store config in the environment" - anything that varies between deploys (your laptop, staging, production), including resource handles and credentials to backing services, lives in environment variables, not in code (see: https://12factor.net/config). The same `db.py` runs everywhere; only the env vars differ. Secrets like `labpass` are never written into source.

## 9. API Documentation

Good documentation that drifts out of date is worse than none. FastAPI avoids drift by generating docs FROM your code. Because you already declared your routes and your Pydantic models with type hints, FastAPI has everything it needs.

Two things come for free:

- `GET /openapi.json` - a machine-readable description of every route, its inputs, and its outputs, following the OpenAPI standard. FastAPI generates this schema for you from your routes and Pydantic models (see: https://fastapi.tiangolo.com/features/).
- `GET /docs` - Swagger UI, a human web page built from that JSON where you can read each endpoint and even try requests live in the browser. FastAPI also serves an alternative ReDoc UI at `/redoc` from the same schema (see: https://fastapi.tiangolo.com/features/).

You wrote `class AskRequest(BaseModel)` for validation, and the same class now documents the `/ask` request body automatically. One source of truth. When you change the model, the docs change with it. Open `/docs` after you start the server and click through your own API - it is the fastest way to confirm the shape of everything.

## 10. Error Responses

When something goes wrong, tell the truth. The worst backends return HTTP 200 with a fake success, or crash with a stack trace and no explanation. A good backend returns the right status code and a real reason.

You signal an error in FastAPI by raising `HTTPException`:

```python
from fastapi import HTTPException

raise HTTPException(status_code=401, detail="not authenticated")
```

FastAPI turns that into a proper HTTP response with that status and a JSON body `{"detail": "..."}`. Learn these codes:

| Code | Meaning | Example in Project 9 |
|---|---|---|
| 400 | Bad request - the caller sent something malformed | Invalid parameters |
| 401 | Not authenticated - we do not know who you are | `{"detail":"not authenticated"}` |
| 403 | Forbidden - we know you, but you may not do this | `{"detail":"admin role required"}` |
| 404 | Not found - the thing you asked for does not exist | Unknown job id |
| 500 | Server error - our code broke | Unhandled bug |
| 503 | Service unavailable - a dependency is down | Database unreachable |

The distinction between 401 and 403 is the one people get wrong most. 401 is about identity, 403 is about permission. Returning a real reason (`admin role required`) helps a legitimate caller understand and fix their request, without leaking secret internals. Never return 200 for a failure - downstream code and monitoring trust the status code, and lying with a fake success hides real problems until they hurt.

## Putting it together

A single `POST /ask` request walks through nearly everything above: FastAPI receives it, Pydantic validates the `AskRequest` body, `current_user()` authenticates the caller and raises 401 if not, the handler borrows a pooled connection with `with get_conn()`, runs the AI query, and returns clean JSON - all documented at `/docs` without you writing a word of it. If the caller had asked for an admin route, `require_admin()` would have added a 403 gate. If the work were slow ingestion, it would have been queued for `worker.py` instead. Every piece has one clear job, and each one fails honestly when it must.

## References

- FastAPI - Concurrency and async / await (sync `def` runs in a threadpool): https://fastapi.tiangolo.com/async/
- FastAPI - Features (automatic OpenAPI schema, Swagger UI at `/docs`, ReDoc at `/redoc`): https://fastapi.tiangolo.com/features/
- FastAPI - First Steps (running with uvicorn, the `app:app` object): https://fastapi.tiangolo.com/tutorial/first-steps/
- Uvicorn - ASGI server documentation: https://www.uvicorn.org/
- PostgreSQL - SELECT (FOR UPDATE / SKIP LOCKED, queue-like table use): https://www.postgresql.org/docs/current/sql-select.html
- PostgreSQL - Explicit Locking (row-level locks): https://www.postgresql.org/docs/current/explicit-locking.html
- Psycopg 2 - Connections pooling (`ThreadedConnectionPool`, `getconn`/`putconn`, exhaustion raises `PoolError`): https://www.psycopg.org/docs/pool.html
- Psycopg 3 - Connection pools (borrow-with-timeout `ConnectionPool`): https://www.psycopg.org/psycopg3/docs/advanced/pool.html
- OWASP - Session Management Cheat Sheet (session id entropy, HttpOnly/Secure/SameSite): https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
- MDN - Set-Cookie header (HttpOnly, Secure, SameSite): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie
- MDN - SameSite cookies (Lax is a partial CSRF defense): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Set-Cookie/SameSite
- The Twelve-Factor App - Store config in the environment: https://12factor.net/config
- MDN - HTTP response status codes (401/403/404/500/503 meanings): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status

Prof. Happy (SUTA Labs)

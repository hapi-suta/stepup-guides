"""Project 9: the enterprise-ready knowledge assistant (FastAPI backend).

What makes this "enterprise-ready" over the Tier 7 prototype:

  - SSO login (OIDC) that issues a server-side session cookie      -> auth.py
  - Role-based admin controls (require_admin on every admin route) -> auth.py
  - A connection POOL, not per-request connects                    -> db.py
  - Background ingestion: uploads enqueue a job, a worker does it   -> worker.py
  - Secrets + config from the environment only (12-factor)
  - A /metrics endpoint for monitoring
  - Every request audited in the database

Routes
  GET  /health              liveness (no auth)
  GET  /                    minimal web UI
  POST /login               OIDC login (mock mode: email -> session cookie)
  POST /logout              clear the session
  POST /ask                 ask a question (any authenticated user)
  GET  /me                  who am I (debugging aid)
  GET  /metrics             operational metrics (no auth for the demo)
  --- admin only (require_admin) ---
  GET  /admin/users         list users
  POST /admin/ingest        enqueue a document for background ingestion
  GET  /admin/jobs          ingestion queue status
"""
from __future__ import annotations

import os
import time

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import auth
import db
import retrieval

app = FastAPI(title="Enterprise Knowledge Assistant", version="9.0")

_HERE = os.path.dirname(os.path.abspath(__file__))
app.mount("/static", StaticFiles(directory=os.path.join(_HERE, "static")), name="static")


@app.on_event("startup")
def _startup() -> None:
    db.init_pool()


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class LoginRequest(BaseModel):
    email: str


class AskRequest(BaseModel):
    query: str
    k: int = 3


class IngestRequest(BaseModel):
    title: str
    source: str
    body: str
    access_level: int = 1


# ---------------------------------------------------------------------------
# Audit helper
# ---------------------------------------------------------------------------

def _audit(username: str, action: str, detail: str = "", latency_ms: int | None = None) -> None:
    """Write one audit row. Never let auditing break the request."""
    try:
        with db.get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "INSERT INTO audit_log (username, action, detail, latency_ms) "
                    "VALUES (%s, %s, %s, %s)",
                    (username, action, detail[:500], latency_ms),
                )
            conn.commit()
    except Exception:
        pass  # auditing is best-effort; the request already succeeded


# ---------------------------------------------------------------------------
# Public routes
# ---------------------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    """Liveness + database reachability. Used by the load balancer / monitor."""
    ok = db.db_ping()
    return {"status": "ok" if ok else "degraded", "database": ok}


@app.get("/", response_class=HTMLResponse)
def index() -> str:
    with open(os.path.join(_HERE, "templates", "index.html"), encoding="utf-8") as fh:
        return fh.read()


@app.post("/login")
def login(req: LoginRequest) -> JSONResponse:
    """OIDC login. In mock mode the email is accepted directly; a real IdP
    would supply a verified email. On success we issue a session cookie."""
    email = auth.resolve_oidc_email(req.email)
    user = auth._user_by_email(email)
    if not user:
        raise HTTPException(status_code=401, detail="no account for that email")
    sid = auth.create_session(user["id"])
    _audit(user["username"], "login", f"role={user['role']}")
    resp = JSONResponse({"username": user["username"], "role": user["role"]})
    # httponly stops JavaScript reading the cookie; samesite mitigates CSRF.
    resp.set_cookie("session", sid, httponly=True, samesite="lax",
                    max_age=auth.SESSION_TTL_HOURS * 3600)
    return resp


@app.post("/logout")
def logout() -> JSONResponse:
    resp = JSONResponse({"status": "logged out"})
    resp.delete_cookie("session")
    return resp


@app.get("/me")
def me(user: dict = Depends(auth.current_user)) -> dict:
    return {"username": user["username"], "role": user["role"],
            "clearance": user["clearance"]}


@app.post("/ask")
def ask(req: AskRequest, user: dict = Depends(auth.current_user)) -> dict:
    if not req.query.strip():
        raise HTTPException(status_code=400, detail="query must not be empty")
    start = time.monotonic()
    with db.get_conn() as conn:
        result = retrieval.answer(conn, req.query, user_clearance=user["clearance"], k=req.k)
    latency_ms = int((time.monotonic() - start) * 1000)
    _audit(user["username"], "ask", req.query, latency_ms)
    result["user"] = user["username"]
    result["latency_ms"] = latency_ms
    return result


@app.get("/metrics")
def metrics() -> dict:
    """Operational metrics for monitoring: volume, latency, queue depth, pool."""
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*), coalesce(avg(latency_ms),0), "
                        "coalesce(max(latency_ms),0) FROM audit_log WHERE action='ask'")
            total, avg_ms, max_ms = cur.fetchone()
            cur.execute("SELECT status, count(*) FROM ingest_jobs GROUP BY status")
            queue = {row[0]: row[1] for row in cur.fetchall()}
    return {
        "ask_count": int(total),
        "avg_latency_ms": round(float(avg_ms), 1),
        "max_latency_ms": int(max_ms),
        "ingest_queue": {"queued": queue.get("queued", 0),
                         "processing": queue.get("processing", 0),
                         "done": queue.get("done", 0),
                         "failed": queue.get("failed", 0)},
        "db_pool": db.pool_status(),
    }


# ---------------------------------------------------------------------------
# Admin routes - every one depends on require_admin
# ---------------------------------------------------------------------------

@app.get("/admin/users")
def admin_users(admin: dict = Depends(auth.require_admin)) -> dict:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT username, email, role, clearance FROM app_users ORDER BY id")
            rows = cur.fetchall()
    return {"users": [{"username": r[0], "email": r[1], "role": r[2], "clearance": r[3]}
                      for r in rows]}


@app.post("/admin/ingest")
def admin_ingest(req: IngestRequest, admin: dict = Depends(auth.require_admin)) -> dict:
    """Enqueue a document for BACKGROUND ingestion and return immediately.

    The slow work (chunking, indexing) is NOT done in this request - the worker
    does it. This is the synchronous-vs-asynchronous split: the user gets a fast
    202-style response and the job id to poll.
    """
    if not req.body.strip():
        raise HTTPException(status_code=400, detail="body must not be empty")
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO ingest_jobs (title, source, body, access_level) "
                "VALUES (%s, %s, %s, %s) RETURNING id",
                (req.title, req.source, req.body, req.access_level),
            )
            job_id = cur.fetchone()[0]
        conn.commit()
    _audit(admin["username"], "enqueue", f"job={job_id} source={req.source}")
    return {"job_id": job_id, "status": "queued"}


@app.get("/admin/jobs")
def admin_jobs(admin: dict = Depends(auth.require_admin)) -> dict:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, title, source, status, attempts, last_error, updated_at "
                "FROM ingest_jobs ORDER BY id DESC LIMIT 50"
            )
            rows = cur.fetchall()
    return {"jobs": [{"id": r[0], "title": r[1], "source": r[2], "status": r[3],
                      "attempts": r[4], "last_error": r[5],
                      "updated_at": r[6].isoformat()} for r in rows]}

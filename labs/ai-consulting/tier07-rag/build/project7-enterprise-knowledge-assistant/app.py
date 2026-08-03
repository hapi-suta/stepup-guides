"""FastAPI service for Project 7: the enterprise knowledge assistant.

Endpoints:
  GET  /health          liveness probe (no auth)
  POST /ask             ask a question; requires Authorization: Bearer <token>
  GET  /metrics         operational metrics (no auth for the demo)

Authentication: a bearer token maps to an app_users row with a clearance.
Authorization: the user's clearance is passed to retrieval as user_level, so
the SQL WHERE clause enforces document-level access control at the database.
Every request is written to audit_log.
"""

from __future__ import annotations

import time

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel

import rag

app = FastAPI(title="Enterprise Knowledge Assistant", version="1.0")


class AskRequest(BaseModel):
    query: str
    lang: str | None = None  # 'en' | 'fr' | None (search all languages)
    k: int = 5


def get_user(authorization: str = Header(default="")) -> dict:
    """Resolve the bearer token to a user row. Raises 401 if invalid."""
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization[len("Bearer "):].strip()
    conn = rag.db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT username, clearance FROM app_users WHERE api_token = %s",
                (token,),
            )
            row = cur.fetchone()
    finally:
        conn.close()
    if not row:
        raise HTTPException(status_code=401, detail="invalid token")
    return {"username": row[0], "clearance": row[1]}


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/ask")
def ask(req: AskRequest, user: dict = Depends(get_user)) -> dict:
    if not req.query.strip():
        raise HTTPException(status_code=400, detail="query must not be empty")

    start = time.monotonic()
    conn = rag.db_conn()
    try:
        result = rag.answer(
            conn,
            req.query,
            user_level=user["clearance"],  # RBAC: clearance drives retrieval
            lang=req.lang,
            k=req.k,
        )
        latency_ms = int((time.monotonic() - start) * 1000)
        # audit every request
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO audit_log (username, query, retrieved, generator, latency_ms) "
                "VALUES (%s, %s, %s, %s, %s)",
                (user["username"], req.query, result["retrieved"],
                 result["generator"], latency_ms),
            )
        conn.commit()
    finally:
        conn.close()

    result["user"] = user["username"]
    result["latency_ms"] = latency_ms
    return result


@app.get("/metrics")
def metrics() -> dict:
    """Operational metrics from the audit log: volume, latency, refusal rate."""
    conn = rag.db_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT count(*), coalesce(avg(latency_ms),0), "
                        "coalesce(max(latency_ms),0) FROM audit_log")
            total, avg_ms, max_ms = cur.fetchone()
            cur.execute("SELECT count(*) FROM audit_log WHERE retrieved = 0")
            no_context = cur.fetchone()[0]
    finally:
        conn.close()
    return {
        "total_queries": int(total),
        "avg_latency_ms": round(float(avg_ms), 1),
        "max_latency_ms": int(max_ms),
        "no_context_queries": int(no_context),
        "embed_model": rag.embed_model_name(),
    }

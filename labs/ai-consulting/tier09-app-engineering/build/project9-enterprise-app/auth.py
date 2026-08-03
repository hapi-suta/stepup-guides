"""Authentication and authorization for Project 9.

Two ways to prove who you are:

  1. SSO via OIDC (browser users). The real flow is: redirect the user to the
     identity provider, they log in there, the provider redirects back with a
     signed token containing an 'email' claim, we match that email to a user
     row and issue our own server-side session cookie. Because a class box has
     no real IdP, OIDC_MODE=mock lets the /login flow accept an email directly
     and skip the provider round-trip - the SAME session + role code runs after.
     Set OIDC_MODE=real plus the issuer/client env vars to use a real provider.

  2. Bearer token (service accounts, scripts, the API tests). Send
     Authorization: Bearer <api_token>.

AUTHORIZATION is separate from authentication: knowing WHO you are (authn) is
not the same as what you may DO (authz). require_admin() enforces role='admin'.
The auth-misconfig SURVIVE scenario is about an admin route that forgot it.
"""
from __future__ import annotations

import os
import secrets
from datetime import datetime, timedelta, timezone

from fastapi import Cookie, Header, HTTPException

import db

SESSION_TTL_HOURS = int(os.environ.get("SESSION_TTL_HOURS", "8"))
OIDC_MODE = os.environ.get("OIDC_MODE", "mock")  # 'mock' or 'real'


# ---------------------------------------------------------------------------
# User lookup
# ---------------------------------------------------------------------------

def _user_by_email(email: str) -> dict | None:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, username, role, clearance FROM app_users WHERE email = %s",
                (email.lower().strip(),),
            )
            row = cur.fetchone()
    if not row:
        return None
    return {"id": row[0], "username": row[1], "role": row[2], "clearance": row[3]}


def _user_by_token(token: str) -> dict | None:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, username, role, clearance FROM app_users WHERE api_token = %s",
                (token,),
            )
            row = cur.fetchone()
    if not row:
        return None
    return {"id": row[0], "username": row[1], "role": row[2], "clearance": row[3]}


# ---------------------------------------------------------------------------
# OIDC login -> server-side session
# ---------------------------------------------------------------------------

def resolve_oidc_email(email: str) -> str:
    """Return the verified email for a login attempt.

    In mock mode we trust the email the caller supplied (class box, no IdP).
    In real mode you would exchange an authorization code for an ID token and
    read the verified 'email' claim from it - never trust an unverified email.
    """
    if OIDC_MODE == "real":  # pragma: no cover - needs a real provider
        raise HTTPException(
            status_code=501,
            detail="OIDC_MODE=real requires the code-exchange step (see runbook).",
        )
    return email


def create_session(user_id: int) -> str:
    """Issue an opaque server-side session id and store it. Returns the id."""
    sid = secrets.token_urlsafe(32)
    expires = datetime.now(timezone.utc) + timedelta(hours=SESSION_TTL_HOURS)
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO sessions (id, user_id, expires_at) VALUES (%s, %s, %s)",
                (sid, user_id, expires),
            )
        conn.commit()
    return sid


def _user_by_session(sid: str) -> dict | None:
    with db.get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT u.id, u.username, u.role, u.clearance "
                "FROM sessions s JOIN app_users u ON u.id = s.user_id "
                "WHERE s.id = %s AND s.expires_at > now()",
                (sid,),
            )
            row = cur.fetchone()
    if not row:
        return None
    return {"id": row[0], "username": row[1], "role": row[2], "clearance": row[3]}


# ---------------------------------------------------------------------------
# FastAPI dependencies
# ---------------------------------------------------------------------------

def current_user(
    authorization: str = Header(default=""),
    session: str = Cookie(default=""),
) -> dict:
    """Resolve the caller to a user, by session cookie OR bearer token.

    Raises 401 if neither identifies a real user. This is authentication only -
    it says WHO you are, not what you may do.
    """
    if session:
        user = _user_by_session(session)
        if user:
            return user
    if authorization.startswith("Bearer "):
        token = authorization[len("Bearer "):].strip()
        user = _user_by_token(token)
        if user:
            return user
    raise HTTPException(status_code=401, detail="not authenticated")


def require_admin(
    authorization: str = Header(default=""),
    session: str = Cookie(default=""),
) -> dict:
    """Authorization gate: caller must be authenticated AND have role='admin'.

    Every admin route MUST depend on this. Forgetting it is the classic auth
    misconfiguration where an internal endpoint is reachable by anyone.
    """
    user = current_user(authorization=authorization, session=session)
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="admin role required")
    return user

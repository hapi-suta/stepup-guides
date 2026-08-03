"""Project 1: customer-support ticket summarizer.

Reads support tickets from PostgreSQL, cleans them, categorizes the
uncategorized ones with simple keyword rules, and exposes a summary
through a FastAPI endpoint.

Config comes from environment variables - never hardcode secrets.
"""
from __future__ import annotations

import os
from collections import Counter

import psycopg2
import psycopg2.extras
from fastapi import FastAPI, HTTPException

# --- configuration (environment variables, with safe local defaults) ---
DB_HOST = os.environ.get("DB_HOST", "127.0.0.1")
DB_NAME = os.environ.get("DB_NAME", "labdb")
DB_USER = os.environ.get("DB_USER", "labuser")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "labpass")

# keyword rules for tickets that have no category yet
KEYWORD_RULES = {
    "auth": ("login", "log in", "password", "sign in"),
    "billing": ("invoice", "refund", "charge", "payment"),
    "bug": ("crash", "error", "does nothing", "broken"),
    "performance": ("slow", "timeout", "lag"),
}

app = FastAPI(title="Support Ticket Summarizer")


def get_connection():
    """Open a database connection. Raises on failure - never swallowed."""
    try:
        return psycopg2.connect(
            host=DB_HOST, dbname=DB_NAME, user=DB_USER, password=DB_PASSWORD
        )
    except psycopg2.OperationalError as exc:
        raise HTTPException(status_code=503, detail=f"database unavailable: {exc}")


def categorize(subject: str, body: str | None) -> str:
    """Assign a category from keyword rules, or 'uncategorized'."""
    text = f"{subject} {body or ''}".lower()
    for category, keywords in KEYWORD_RULES.items():
        if any(k in text for k in keywords):
            return category
    return "uncategorized"


@app.get("/health")
def health() -> dict:
    """Liveness check: confirms the API and database are reachable."""
    conn = get_connection()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT 1;")
            cur.fetchone()
        return {"status": "ok"}
    finally:
        conn.close()


@app.get("/summary")
def summary() -> dict:
    """Return counts of tickets per category.

    Cleans blank subjects, fills missing categories via keyword rules,
    and returns a sorted summary plus the total.
    """
    conn = get_connection()
    try:
        with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute("SELECT subject, body, category FROM support_tickets;")
            rows = cur.fetchall()
    finally:
        conn.close()

    counts: Counter[str] = Counter()
    for row in rows:
        subject = (row["subject"] or "").strip()
        if not subject:
            continue  # skip records with no subject
        category = row["category"] or categorize(subject, row["body"])
        counts[category] += 1

    return {
        "total": sum(counts.values()),
        "by_category": dict(sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))),
    }

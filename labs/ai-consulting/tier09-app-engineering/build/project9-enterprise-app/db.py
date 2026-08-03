"""Database access for Project 9 - with a real connection POOL.

Opening a fresh PostgreSQL connection per request is the classic way an app
falls over under load: every request pays the TCP + auth cost, and a burst of
traffic opens more connections than the database allows ("too many clients").

A pool keeps a small set of connections open and hands them out. This module
is the single place connections are created, so pooling, sizing, and recovery
all live in one file. The db-connection-storm SURVIVE scenario exercises it.

Config is read from environment variables - never hardcode secrets.
"""
from __future__ import annotations

import contextlib
import os
import threading
import time

import psycopg2
from psycopg2 import pool

# Pool sizing comes from the environment so it can be tuned per box.
# minconn: connections kept open even when idle.
# maxconn: hard ceiling. Requests beyond this WAIT rather than overwhelming
#          PostgreSQL. Keep this well under PostgreSQL's max_connections.
_MIN = int(os.environ.get("DB_POOL_MIN", "1"))
_MAX = int(os.environ.get("DB_POOL_MAX", "5"))

_POOL: pool.ThreadedConnectionPool | None = None
# Guards borrowing so that when the pool is full, extra requests WAIT for a free
# connection instead of erroring. Bounded degradation beats a hard failure.
_LOCK = threading.Lock()
_BORROW_TIMEOUT = float(os.environ.get("DB_BORROW_TIMEOUT", "10"))


def _dsn() -> dict:
    """Build connection settings from the environment (12-factor config)."""
    return {
        "host": os.environ.get("DB_HOST", "127.0.0.1"),
        "port": os.environ.get("DB_PORT", "5432"),
        "dbname": os.environ.get("DB_NAME", "labdb"),
        "user": os.environ.get("DB_USER", "labuser"),
        "password": os.environ.get("DB_PASSWORD", "labpass"),
        # A connect timeout means a dead database fails fast instead of hanging.
        "connect_timeout": int(os.environ.get("DB_CONNECT_TIMEOUT", "5")),
    }


def init_pool() -> None:
    """Create the pool once, at startup. Safe to call more than once."""
    global _POOL
    if _POOL is None:
        _POOL = pool.ThreadedConnectionPool(_MIN, _MAX, **_dsn())


@contextlib.contextmanager
def get_conn():
    """Borrow a connection from the pool and always return it.

    Usage:
        with get_conn() as conn:
            ...            # use conn
    The connection is returned to the pool even if the block raises, so a
    handler error can never leak a connection - that leak is exactly what
    causes pool exhaustion over time.
    """
    if _POOL is None:
        with _LOCK:
            init_pool()
    assert _POOL is not None
    # Borrow, WAITING for a free connection if the pool is momentarily full.
    # psycopg2's getconn raises when the pool is exhausted rather than blocking,
    # so we retry with a short backoff up to _BORROW_TIMEOUT. This turns a burst
    # of traffic into a brief wait instead of a wall of 500s.
    conn = None
    deadline = time.monotonic() + _BORROW_TIMEOUT
    while conn is None:
        try:
            conn = _POOL.getconn()
        except pool.PoolError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.02)
    try:
        yield conn
    finally:
        # Roll back any half-finished transaction before reuse so the next
        # borrower gets a clean connection.
        with contextlib.suppress(Exception):
            conn.rollback()
        _POOL.putconn(conn)


def pool_status() -> dict:
    """Report pool sizing for the monitoring endpoint."""
    return {"min": _MIN, "max": _MAX, "initialized": _POOL is not None}


def db_ping() -> bool:
    """Return True if the database answers a trivial query. Never raises."""
    try:
        with get_conn() as conn:
            with conn.cursor() as cur:
                cur.execute("SELECT 1;")
                cur.fetchone()
        return True
    except Exception:
        return False


def raw_conn():
    """A single non-pooled connection, for scripts (worker, ingest, tests).

    Scripts are short-lived and single-threaded, so they do not need the pool.
    """
    return psycopg2.connect(**_dsn())

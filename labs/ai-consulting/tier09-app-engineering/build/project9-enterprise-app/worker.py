"""Background ingestion worker for Project 9.

The API enqueues documents (rows in ingest_jobs). This worker is a SEPARATE
process that claims queued jobs and does the slow work: chunk the text and
insert rows into documents + chunks. Separating this from the request path is
the whole point of asynchronous processing - a 5MB upload does not tie up a web
worker for 30 seconds.

Reliability properties:
  - Claims one job atomically with FOR UPDATE SKIP LOCKED, so two workers never
    grab the same job.
  - On success: status='done'. On failure: attempts++, last_error set, and the
    job goes back to 'queued' up to MAX_ATTEMPTS, then 'failed' (dead-letter).
  - Errors are recorded, never silently swallowed.

Run it as a long-lived process:   python worker.py
Or drain the queue once and exit: python worker.py --once
"""
from __future__ import annotations

import re
import sys
import time
import traceback

import db

MAX_ATTEMPTS = 3
POLL_SECONDS = 2


def chunk_text(text: str, max_chars: int = 400) -> list[str]:
    """Split text into paragraph-aware chunks. Simple and correct."""
    text = text.strip()
    if not text:
        return []
    paras = [p.strip() for p in re.split(r"\n\s*\n", text) if p.strip()]
    chunks: list[str] = []
    current = ""
    for para in paras:
        if current and len(current) + len(para) + 1 > max_chars:
            chunks.append(current.strip())
            current = para
        else:
            current = (current + "\n" + para).strip() if current else para
    if current.strip():
        chunks.append(current.strip())
    return chunks


def _claim_one(conn):
    """Atomically claim the oldest queued job. Returns the row or None."""
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id, title, source, body, access_level, attempts "
            "FROM ingest_jobs WHERE status = 'queued' "
            "ORDER BY id ASC FOR UPDATE SKIP LOCKED LIMIT 1"
        )
        row = cur.fetchone()
        if not row:
            return None
        cur.execute(
            "UPDATE ingest_jobs SET status='processing', updated_at=now() WHERE id=%s",
            (row[0],),
        )
    conn.commit()
    return row


def _process(conn, job) -> None:
    """Do the real ingestion for one claimed job."""
    job_id, title, source, body, access_level, _attempts = job
    pieces = chunk_text(body)
    if not pieces:
        raise ValueError("document produced no chunks (empty body)")
    with conn.cursor() as cur:
        cur.execute(
            "INSERT INTO documents (title, source, access_level) "
            "VALUES (%s, %s, %s) RETURNING id",
            (title, source, access_level),
        )
        doc_id = cur.fetchone()[0]
        for piece in pieces:
            cur.execute(
                "INSERT INTO chunks (doc_id, chunk_text, source, access_level) "
                "VALUES (%s, %s, %s, %s)",
                (doc_id, piece, source, access_level),
            )
        cur.execute(
            "UPDATE ingest_jobs SET status='done', updated_at=now() WHERE id=%s",
            (job_id,),
        )
    conn.commit()
    print(f"[worker] job {job_id} done: {len(pieces)} chunks from {source}")


def _fail(conn, job_id: int, attempts: int, err: str) -> None:
    """Record a failure. Requeue if we have retries left, else dead-letter."""
    new_attempts = attempts + 1
    new_status = "queued" if new_attempts < MAX_ATTEMPTS else "failed"
    with conn.cursor() as cur:
        cur.execute(
            "UPDATE ingest_jobs SET status=%s, attempts=%s, last_error=%s, "
            "updated_at=now() WHERE id=%s",
            (new_status, new_attempts, err[:500], job_id),
        )
    conn.commit()
    print(f"[worker] job {job_id} failed (attempt {new_attempts}) -> {new_status}: {err}")


def run_once() -> int:
    """Drain all currently-queued jobs. Returns how many were processed."""
    processed = 0
    conn = db.raw_conn()
    try:
        while True:
            job = _claim_one(conn)
            if job is None:
                break
            job_id, attempts = job[0], job[5]
            try:
                _process(conn, job)
                processed += 1
            except Exception as exc:  # record, requeue/dead-letter, keep going
                conn.rollback()
                _fail(conn, job_id, attempts, f"{type(exc).__name__}: {exc}")
                traceback.print_exc()
    finally:
        conn.close()
    return processed


def run_forever() -> None:
    print(f"[worker] started, polling every {POLL_SECONDS}s. Ctrl-C to stop.")
    while True:
        try:
            n = run_once()
            if n == 0:
                time.sleep(POLL_SECONDS)
        except KeyboardInterrupt:
            print("\n[worker] stopping.")
            return
        except Exception as exc:  # a transient DB outage should not kill the worker
            print(f"[worker] loop error, retrying: {exc}")
            time.sleep(POLL_SECONDS)


if __name__ == "__main__":
    if "--once" in sys.argv:
        count = run_once()
        print(f"[worker] processed {count} job(s).")
    else:
        run_forever()

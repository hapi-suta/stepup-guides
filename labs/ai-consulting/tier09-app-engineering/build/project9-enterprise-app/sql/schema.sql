-- Project 9 schema: enterprise-ready knowledge assistant on PostgreSQL.
-- Builds on the Tier 7 RAG idea but adds the tables an enterprise app needs:
-- roles, sessions, an ingestion job queue, and an audit log.
-- Run once against labdb. Idempotent - safe to re-run.

-- pgvector is optional here. If the extension is present we use a real vector
-- column; if not, this file still runs and retrieval falls back to keyword
-- matching in the app. We create the extension only if it exists.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = 'vector') THEN
        CREATE EXTENSION IF NOT EXISTS vector;
    END IF;
END $$;

-- ---------------------------------------------------------------------------
-- Users, roles, and sessions
-- ---------------------------------------------------------------------------

-- Users can arrive two ways:
--   1. SSO (OIDC): identified by their email 'sub' from the identity provider.
--   2. Service accounts / demo: a bearer api_token.
-- role drives authorization: 'admin' can reach /admin/*, 'user' cannot.
CREATE TABLE IF NOT EXISTS app_users (
    id         SERIAL PRIMARY KEY,
    username   TEXT UNIQUE NOT NULL,
    email      TEXT UNIQUE,             -- matched against the OIDC email claim
    api_token  TEXT UNIQUE,            -- service-account bearer token (optional)
    role       TEXT NOT NULL DEFAULT 'user',   -- 'user' or 'admin'
    clearance  INT  NOT NULL DEFAULT 1,        -- 1..4 document access ceiling
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT role_valid CHECK (role IN ('user', 'admin'))
);

-- Server-side sessions issued after a successful SSO login. The browser only
-- holds an opaque session id cookie; all trust lives in this table.
CREATE TABLE IF NOT EXISTS sessions (
    id          TEXT PRIMARY KEY,        -- random opaque session id
    user_id     INT NOT NULL REFERENCES app_users(id) ON DELETE CASCADE,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at  TIMESTAMPTZ NOT NULL
);

-- ---------------------------------------------------------------------------
-- Documents and chunks (the knowledge base)
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS documents (
    id           SERIAL PRIMARY KEY,
    title        TEXT NOT NULL,
    source       TEXT NOT NULL,
    access_level INT  NOT NULL DEFAULT 1,   -- 1=public .. 4=restricted
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS chunks (
    id           SERIAL PRIMARY KEY,
    doc_id       INT  NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_text   TEXT NOT NULL,
    source       TEXT NOT NULL,
    access_level INT  NOT NULL DEFAULT 1,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chunks_access ON chunks(access_level);

-- ---------------------------------------------------------------------------
-- Ingestion job queue (asynchronous background work)
-- ---------------------------------------------------------------------------

-- An admin uploads a document; the API does NOT parse and embed it in the
-- request. Instead it enqueues a job here and returns immediately. A separate
-- worker process claims jobs and does the slow work. This is the sync-vs-async
-- split the tier is about.
--
-- status lifecycle: queued -> processing -> done | failed
-- attempts + last_error make failures visible and retryable (not swallowed).
CREATE TABLE IF NOT EXISTS ingest_jobs (
    id          SERIAL PRIMARY KEY,
    title       TEXT NOT NULL,
    source      TEXT NOT NULL,
    body        TEXT NOT NULL,           -- raw document text to ingest
    access_level INT NOT NULL DEFAULT 1,
    status      TEXT NOT NULL DEFAULT 'queued',
    attempts    INT  NOT NULL DEFAULT 0,
    last_error  TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT status_valid CHECK (status IN ('queued','processing','done','failed'))
);

CREATE INDEX IF NOT EXISTS idx_jobs_status ON ingest_jobs(status);

-- ---------------------------------------------------------------------------
-- Audit log: every question and every admin action
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS audit_log (
    id          SERIAL PRIMARY KEY,
    username    TEXT NOT NULL,
    action      TEXT NOT NULL,           -- 'ask', 'enqueue', 'login', etc.
    detail      TEXT,
    latency_ms  INT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

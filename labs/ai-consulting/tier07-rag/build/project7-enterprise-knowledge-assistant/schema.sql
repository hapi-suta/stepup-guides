-- Project 7 schema: enterprise knowledge assistant on PostgreSQL + pgvector.
-- Run once against labdb. Idempotent (safe to re-run).

CREATE EXTENSION IF NOT EXISTS vector;

-- Documents: one row per source file, carries confidentiality + language.
CREATE TABLE IF NOT EXISTS documents (
    id           SERIAL PRIMARY KEY,
    title        TEXT NOT NULL,
    source       TEXT NOT NULL,          -- filename / URL the content came from
    lang         TEXT NOT NULL,          -- 'en' or 'fr'
    access_level INT  NOT NULL,          -- 1=public .. 4=restricted
    version      INT  NOT NULL DEFAULT 1,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Chunks: retrievable pieces. Each carries its own copy of the security +
-- language metadata so retrieval can filter without extra joins if needed,
-- and an embed_model column so an embedding-model change is detectable.
CREATE TABLE IF NOT EXISTS chunks (
    id           SERIAL PRIMARY KEY,
    doc_id       INT  NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    chunk_text   TEXT NOT NULL,
    embedding    vector(384) NOT NULL,
    source       TEXT NOT NULL,
    page         INT,
    access_level INT  NOT NULL,
    lang         TEXT NOT NULL,
    embed_model  TEXT NOT NULL,
    content_hash TEXT NOT NULL,          -- for dedup + poisoned-doc detection
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Users: who may see what. clearance is the max access_level they can read.
CREATE TABLE IF NOT EXISTS app_users (
    id        SERIAL PRIMARY KEY,
    username  TEXT UNIQUE NOT NULL,
    api_token TEXT UNIQUE NOT NULL,      -- simple bearer token for the demo
    clearance INT NOT NULL              -- 1..4, compared to chunk.access_level
);

-- Audit log: every question, who asked, what was retrieved, latency.
CREATE TABLE IF NOT EXISTS audit_log (
    id           SERIAL PRIMARY KEY,
    username     TEXT NOT NULL,
    query        TEXT NOT NULL,
    retrieved    INT  NOT NULL,
    generator    TEXT NOT NULL,
    latency_ms   INT  NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A partial index on access_level speeds the security filter as data grows.
CREATE INDEX IF NOT EXISTS idx_chunks_access ON chunks(access_level);
CREATE INDEX IF NOT EXISTS idx_chunks_lang   ON chunks(lang);

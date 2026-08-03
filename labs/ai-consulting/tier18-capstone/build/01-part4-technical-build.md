# BUILD: Capstone Part 4 - Technical Implementation

**Tier 18 - BUILD phase (Part 4).** This is the worked structure for building the secure bilingual RAG assistant that Governance (Part 3) specified. You do not start from scratch: you build on your Tier 7 enterprise knowledge assistant (PostgreSQL + pgvector, access-level filtering, bilingual corpus, citations, provider fallback) and harden it to meet every governance requirement.

**Validated on:** CentOS Stream 9, Python 3.12, PostgreSQL 16 + pgvector, on 2026-07-25 (foundation from Tier 7; capstone hardening reviewed).

**Prerequisite:** Parts 1-3 complete. You have the governance requirements list from Part 3 in hand. You have your Tier 7 assistant working.

**The rule:** the build is not done until it satisfies every governance requirement. Cross-check against the Part 3 list, not against "it runs."

---

## The governance requirements this build must meet

From Part 3, the build must deliver:
1. Access control mapped to data classification (public/internal/restricted)
2. Citations on every answer (explainability)
3. Appeal-grade logging (reconstructable per-response record)
4. Data boundaries - what never reaches an external provider
5. A pause/rollback capability (incident process)
6. Accessibility conformance (public-sector gate)
7. Model-provider abstraction (swap providers without app changes)
8. Per-language evaluation

Your Tier 7 assistant already gives you 1, 2, 7, and most of 8. Parts 3, 4, 5, 6 are the capstone hardening.

---

## Component map

```
ingest.py        -> load + chunk + classify + embed documents into pgvector
schema.sql       -> documents + chunks (access_level, lang, version, hash)
                    + audit_log (appeal-grade) + system_status (pause flag)
rag.py           -> retrieval (SQL-enforced access control) + generation
                    + provider abstraction + boundary enforcement
app.py           -> FastAPI: auth, permissions, /ask, /health, /pause
eval_harness.py  -> per-language evaluation against a golden set
monitor.py       -> health, latency, error rate, cost counters
Dockerfile       -> containerized deployment
```

---

## Step 1: Start from your Tier 7 assistant

On your **lab server**, as **ec2-user**:

```
cp -r ~/project7-enterprise-knowledge-assistant ~/capstone-assistant
```

The `cp -r` command copies the whole Tier 7 project into a new capstone folder so you can harden it without touching the original.

Then move into it:

```
cd ~/capstone-assistant
```

---

## Step 2: Add the appeal-grade audit table

The Tier 7 assistant logs, but not to appeal-grade. Add an `audit_log` table that stores everything needed to reconstruct a decision on appeal. Edit `schema.sql` and add:

```sql
-- Appeal-grade audit: one row per answered request, fully reconstructable.
CREATE TABLE IF NOT EXISTS audit_log (
    id              SERIAL PRIMARY KEY,
    ts              TIMESTAMPTZ NOT NULL DEFAULT now(),
    user_id         TEXT NOT NULL,
    user_clearance  INT  NOT NULL,
    query           TEXT NOT NULL,
    retrieved       JSONB NOT NULL,   -- [{doc_id, version, chunk_id, distance}]
    citations       JSONB NOT NULL,   -- what was shown to the user
    answer          TEXT NOT NULL,
    model_provider  TEXT NOT NULL,
    model_version   TEXT NOT NULL,
    lang            TEXT NOT NULL,
    human_decision  TEXT              -- filled by the accountable officer, if any
);
```

Every answer writes one row. This is the artifact the Tier 16 appeals scenario needs. Apply the schema:

```
psql -d labdb -f schema.sql
```

`psql -f` runs the SQL file. The `IF NOT EXISTS` guards make it safe to re-run.

---

## Step 3: Add the pause/rollback capability

The incident process needs a way to stop the assistant instantly. Add a status flag table and a `/pause` endpoint.

Add to `schema.sql`:

```sql
CREATE TABLE IF NOT EXISTS system_status (
    id       INT PRIMARY KEY DEFAULT 1,
    paused   BOOLEAN NOT NULL DEFAULT false,
    reason   TEXT,
    changed  TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK (id = 1)
);
INSERT INTO system_status (id, paused) VALUES (1, false)
    ON CONFLICT (id) DO NOTHING;
```

In `app.py`, check `paused` at the top of the `/ask` handler and refuse with a clear message if paused. Add an admin-only `/pause` endpoint. This gives the incident process a real switch, not a wish.

---

## Step 4: Enforce data boundaries in the provider layer

Governance decided what data never leaves the boundary. Enforce it in `rag.py`, not by hoping. Before sending retrieved context to an external model provider, check the access level of every chunk: restricted content must never be sent to an external provider unless the vendor assessment approved it. If a restricted chunk would be sent to a disallowed provider, either route to an approved in-boundary model or refuse and log.

The principle: the boundary is code, not a policy PDF. If restricted data can physically reach a disallowed provider, the control does not exist.

---

## Step 5: Confirm access control is SQL-enforced

Your Tier 7 assistant already filters by `access_level` inside the SQL query (never post-filtered in Python). Confirm the user's clearance is compared to the chunk's `access_level` in the WHERE clause. This is the control the role-bypass SURVIVE test will attack, so verify it now. A user must never retrieve a chunk above their clearance.

---

## Step 6: Per-language evaluation

Extend `eval_harness.py` so it reports metrics separately per language, never blended. Build the golden set with equal coverage per language. The system's real quality is its weakest language, per the Tier 17 finding. Run it and record the per-language scores.

---

## Step 7: Monitoring and cost counters

Add `monitor.py` (or extend health) to track latency, error rate, retrieval hit-rate, and a running token/cost counter per provider. Cost control is a Part 6 requirement; wire the counter now so operations has data.

---

## Step 8: Containerize and deploy

Your Tier 7 project has a `Dockerfile`. Confirm it builds the capstone assistant, then deploy to the cloud target from your technical review. Keep secrets in environment variables, never in the image.

```
docker build -t capstone-assistant .
```

`docker build` builds the image from the Dockerfile; `-t` tags it. Deploy per your Part 6 CI/CD.

---

## Step 9: Cross-check every governance requirement

Go back to the Part 3 requirements list and verify each is met in code:

- [ ] Access control mapped to classification (SQL-enforced, verified)
- [ ] Citations on every answer
- [ ] Appeal-grade audit_log written per response
- [ ] Data boundary enforced in the provider layer
- [ ] Pause/rollback endpoint works
- [ ] Accessibility conformance on the interface
- [ ] Provider abstraction (swap without app changes)
- [ ] Per-language evaluation

If any is unchecked, the build is not done, however well it runs.

---

## Exit standard for Part 4

The assistant runs, answers bilingually with citations, enforces classification-based access control in SQL, writes an appeal-grade record for every answer, enforces data boundaries, can be paused instantly, evaluates per language, and is containerized and deployed - and every governance requirement is met. It is now ready for Part 5 (security testing). Do not present or operate it until Part 5 passes.

---

Prof. Happy (SUTA Labs)

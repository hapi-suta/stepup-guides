# USE: Draw and Document the Target Architecture (Multitenancy, HA, DR, Data Residency)

**Goal:** an enterprise buyer, a security team, and your future on-call self all need one thing before they trust an app: a clear architecture document. You will produce `ARCHITECTURE.md` for Project 9 - a diagram plus the four cross-cutting concerns that always come up: multitenancy, high availability, disaster recovery, and data residency. You will ground every claim in the real system, and verify the claims that can be verified.

**Where you are:** the **lab server** (CentOS Stream 9), as **ec2-user**, Project 9 in `~/project9`.

**What you will practice:** reading a system to describe it accurately, ASCII diagramming, and reasoning about multitenancy / HA / DR / data residency.

---

## Step 1: Confirm the moving parts before you draw them

A diagram is only useful if it is true. List the real components.

On your **lab server**, as **ec2-user**, in `~/project9`:

```bash
cd ~/project9
```

Look at what the deployment actually declares:

```bash
grep -E "^  [a-z]+:" docker-compose.yml
```

Expected output:

```
  db:
  api:
  worker:
  gateway:
```

Four services: `db` (PostgreSQL, the only stateful one), `api` (FastAPI), `worker` (the ingestion drainer), and `gateway` (nginx). Confirm only the gateway is public:

```bash
grep -A2 "ports:" docker-compose.yml
```

Expected output (yours will differ):

```
    ports:
      - "8080:80"     # the ONLY public port
```

Only the gateway maps a host port. The API is reachable only through it.

---

## Step 2: Verify the multitenancy control before you claim it

Project 9 isolates users by a `clearance` level enforced in SQL. Prove it: a low-clearance user must not retrieve a high-clearance chunk.

Still on the **lab server**, as **ec2-user**, load config and ensure the API is up:

```bash
set -a; . ./.env; set +a
```

```bash
pgrep -f "uvicorn app:app" >/dev/null || nohup .venv/bin/uvicorn app:app --host 0.0.0.0 --port 8000 > uvicorn.log 2>&1 &
```

The seeded incident-response document is `access_level 2`. Alice has clearance 2, so she can see it; make a clearance-1 test user who must not.

```bash
PGPASSWORD=$DB_PASSWORD psql -h $DB_HOST -U $DB_USER -d $DB_NAME -c "INSERT INTO app_users (username,email,api_token,role,clearance) VALUES ('intern','intern@example.com','token-intern','user',1) ON CONFLICT (username) DO UPDATE SET clearance=1, api_token='token-intern';"
```

Expected output:

```
INSERT 0 1
```

Ask the intern (clearance 1) about the confidential incident-response content:

```bash
curl -s -H "Authorization: Bearer token-intern" -X POST http://127.0.0.1:8000/ask -H "Content-Type: application/json" -d '{"query":"what do I do on a suspected breach?"}'
```

Expected output (yours will differ - the intern gets NO confidential context):

```
{"answer":"I don't have that information.","generator":"mock","citations":[],"retrieved":0,"user":"intern","latency_ms":0}
```

Now ask alice (clearance 2) the same thing:

```bash
curl -s -H "Authorization: Bearer token-alice" -X POST http://127.0.0.1:8000/ask -H "Content-Type: application/json" -d '{"query":"what do I do on a suspected breach?"}'
```

Expected output (yours will differ - alice DOES get it):

```
{"answer":"[MOCK] Based on the retrieved context: On a suspected breach, page the on-call security lead within 15 minutes...","generator":"mock","citations":[{"n":1,"source":"incident-response.txt"}],"retrieved":1,"user":"alice","latency_ms":0}
```

Same question, different data, decided by clearance in the SQL `WHERE` clause. Now you can honestly write "tenant isolation enforced in-query" because you saw it hold.

---

## Step 3: Verify the DR path before you claim it

Do not write "we have backups" unless you have restored one. Run the drill.

Still on the **lab server**, as **ec2-user** (the drill needs `labuser` to have CREATEDB - the BUILD guide granted this):

```bash
bash backup.sh
```

Expected output (yours will differ):

```
[backup] done: ./backups/labdb-....dump (16K)
```

```bash
bash restore.sh
```

Expected output (yours will differ):

```
PASS: backup restored and verified (2 users, ... chunks).
```

`PASS` is your evidence. Note the backup file name and the PASS line - you will cite them in the DR section.

---

## Step 4: Write ARCHITECTURE.md

Now capture it. Create the document:

Still on the **lab server**, as **ec2-user**:

```bash
vi ARCHITECTURE.md
```

Press `i` and write the sections below. Use this diagram exactly (it matches what you verified in Steps 1-3):

```
                        Internet
                           |
                           v
                 +-------------------+
                 |  Gateway (nginx)  |   single public entry point
                 |  TLS, rate limit, |   (only published port)
                 |  size caps        |
                 +---------+---------+
                           |
                 +---------v---------+        +-------------------+
                 |   API (FastAPI)   |        |  Worker (same     |
                 |   /ask /login     |        |  image, drains    |
                 |   /admin/* etc.   |        |  ingest_jobs)     |
                 +---------+---------+        +---------+---------+
                           |                            |
                           |   ingest_jobs (queue)      |
                           +------------+---------------+
                                        |
                              +---------v---------+
                              | PostgreSQL (db)   |  the only stateful
                              | users, sessions,  |  component
                              | documents/chunks, |
                              | ingest_jobs, audit|
                              +-------------------+
```

Then write these five sections in your own words:

1. **Components and request path.** Client -> gateway -> API -> database. The worker is a second process on the same image that drains the `ingest_jobs` queue. Only the gateway is public; the API and worker are private. State lives only in PostgreSQL.

2. **Multitenancy.** Isolation is per-user `clearance` compared to each chunk's `access_level` in the SQL `WHERE` clause - access control in the query, never post-filtered in Python. Cite the Step 2 result (intern got nothing, alice got the confidential chunk). Note the production hardening path: a `tenant_id` on every row plus PostgreSQL Row-Level Security, or database-per-tenant for stronger isolation.

3. **High availability.** The API and worker are stateless, so you run multiple copies behind the gateway and lose none if one dies. The database is the single point of state - make it HA with a streaming replica and automatic failover. `docker-compose.yml` already has a `pg_isready` healthcheck and `depends_on: service_healthy`. State the HA pattern: stateless app tier + replicated DB.

4. **Disaster recovery.** `backup.sh` (pg_dump custom format) plus `restore.sh` (restore into an isolated DB and verify). Cite your Step 3 PASS as evidence the backup restores. State your RPO (how much data you can lose = backup frequency) and RTO (how long recovery takes = the drill duration). Note that in production backups ship off-box (e.g. S3) and the drill is scheduled.

5. **Data residency.** Data physically lives wherever the database runs, so region choice is a compliance lever (e.g. EU data stays in the EU -> deploy the DB in an EU region, possibly database-per-region). The LLM call reads `ANTHROPIC_API_KEY` from the environment with a mock fallback, so with no key set the app runs fully offline and no data leaves the box - a real residency control. When a key is set, note that query text goes to the vendor, which is a residency decision to document.

Press `Esc`, type `:wq`, press Enter.

---

## Step 5: Sanity-check your document

A good architecture doc has a diagram and covers the four concerns. Verify yours does.

Still on the **lab server**, as **ec2-user**:

```bash
grep -Eic "multitenan|high availab|disaster|residency" ARCHITECTURE.md
```

Expected output (4 or more - each concern is mentioned):

```
4
```

Confirm the diagram made it in:

```bash
grep -c "PostgreSQL (db)" ARCHITECTURE.md
```

Expected output:

```
1
```

---

## What you learned

- **A diagram must be true, so verify before you draw.** You confirmed the public surface, the multitenancy control, and the DR path with real commands before writing a word. That is the difference between a diagram and a wish.
- **Multitenancy is enforced in the query.** The intern-versus-alice test is the proof: isolation that lives in the SQL cannot be bypassed by application bugs above it.
- **DR is a drill, not a checkbox.** "We have backups" means nothing; "we restored backup X and it PASSED" means everything.
- **Data residency starts with where the database runs** - and every external call (like the LLM) is a residency decision you must document.

Prof. Happy (SUTA Labs)

# Module 9.4 - Architecture Patterns

**Read this before you touch the keyboard.** Architecture is not about drawing boxes to look clever. It is about the small set of decisions that are expensive to reverse later - how you split your code, how work flows through it, and what happens when a piece falls over at 3am. This document walks through the patterns you need for real AI application engineering, grounded in the app you are building in Project 9: a FastAPI service, a background worker, and one PostgreSQL database. For every pattern we explain what it is, why it matters, the tradeoffs, and exactly where Project 9 uses it (or deliberately does not yet). Read the whole thing once before you start wiring things together, because the patterns interact.

Project 9 target architecture:

```
                         Internet
                            |
                            v
                  +-------------------+
                  |   gateway (nginx) |   TLS termination, rate limit,
                  |   gateway.conf    |   2MB body cap, single entry point
                  +-------------------+
                            |
                            v
                  +-------------------+
                  |   api (FastAPI)   |   stateless, N replicas possible
                  |   POST /admin/    |
                  |   ingest enqueues |
                  +-------------------+
                       |          |
        enqueue job    |          | read/write
                       v          v
              +-----------------------------+
              |     db (PostgreSQL)         |
              |   chunks, users, ...        |
              |   ingest_jobs  <-- QUEUE    |
              +-----------------------------+
                       ^          ^
        drain job      |          | read/write
                       |          |
                  +-------------------+
                  |   worker (worker.py)|  same image as api,
                  |   FOR UPDATE        |  different command
                  |   SKIP LOCKED       |
                  +-------------------+
```

Note the `ingest_jobs` table sitting in the database between `api` and `worker`. That table IS the queue. The api writes jobs into it and returns; the worker reads jobs out of it and does the slow work. Keep that picture in your head for the rest of this doc.

---

## 1. Monolith versus microservices

A monolith is one deployable unit that contains all your features. Microservices split those features into many small services that talk over the network, each with its own deployment and often its own database.

Project 9 is a small modular monolith. There is one FastAPI application, one worker, and one database. The code is organized into modules (retrieval, ingestion, auth) but it all ships together. This is the right default. Most teams reach for microservices far too early and pay for it in latency, debugging pain, and operational overhead before they have the scale that would justify it.

Here is the pragmatic middle ground we actually use: our `api` and `worker` are the SAME container image, run with different commands. One codebase, one build, one set of dependencies - but two separately scalable processes. The api handles requests; the worker drains jobs. If ingestion gets heavy you scale up workers without touching the api, and vice versa. You get process-level independence without the cost of two codebases.

| Concern | Monolith | Microservices |
| --- | --- | --- |
| Deploy | One unit, simple | Many units, orchestration needed |
| Debug a request | One process, one log | Trace across the network |
| Scale one hot part | Scale the whole thing | Scale that service only |
| Data consistency | One database, easy | Distributed, hard |
| Team autonomy | Lower | Higher (teams own services) |
| Right for | Almost everyone starting out | Large orgs, proven scale bottlenecks |

When SHOULD you split into microservices? When a specific component has a genuinely different scaling profile, a different language requirement, or a team that needs to deploy independently many times a day. When should you NOT? When you are guessing at future scale, when your team is small, or when the services would need to make lots of chatty network calls to each other to serve one request. Start monolith. Extract a service only when the pain is real and measured.

---

## 2. Event-driven architecture

In a request-driven system, component A calls component B and waits for an answer. In an event-driven system, component A announces that something happened ("ingest requested") and does not care who reacts. Consumers pick up the event on their own schedule.

Event-driven designs decouple the producer from the consumer. The producer does not need to know how many consumers exist, whether they are up right now, or how long they take. This buys you resilience (a slow or down consumer does not block the producer) and flexibility (add new consumers without touching the producer).

Project 9 uses a simple form of event-driven architecture: the `ingest_jobs` table. When someone calls `POST /admin/ingest`, the api does not do the ingestion. It records an event - a row in `ingest_jobs` - and returns. The worker later reacts to that event. We are not running Kafka or RabbitMQ; a database table is a perfectly good event log for this scale, and it comes with transactions for free. The lesson: "event-driven" is a pattern, not a specific product. You can start with a table.

---

## 3. Synchronous versus asynchronous processing

Synchronous means the caller waits for the work to finish before getting a response. Asynchronous means the caller gets an immediate acknowledgement and the real work happens later.

Ingestion in Project 9 is asynchronous. Look at the shape:

```
POST /admin/ingest   ->   INSERT INTO ingest_jobs (...)   ->   return 202 immediately
                                       |
                                       v
                          worker picks it up later, does the slow embedding + chunking
```

HTTP 202 (Accepted) is the correct status for exactly this shape: it means "the request has been accepted for processing, but the processing has not been completed" and is intended for work handled by a separate process later (see: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/202). Return the `job_id` in the body so the caller can poll status. (Contrast with 201 Created, which implies the resource already exists at completion - not true yet for a queued job.)

Contrast this with the naive synchronous version: do the chunking, the embedding calls, and the database writes INSIDE the request handler, then return. It works fine with one file on your laptop. Under load it falls apart:

- Each request holds a worker thread/connection for the whole slow job. A handful of large uploads exhausts your capacity and healthy requests start timing out.
- HTTP clients and load balancers have timeouts (often 30-60s). A big ingestion blows past them and the client sees a failure even though the work might have succeeded.
- A crash mid-request loses the work with no record that it was ever requested.

Async fixes all three: the request is fast and cheap, the slow work is queued durably, and a crash just leaves the job un-drained for the next worker.

| | Synchronous | Asynchronous |
| --- | --- | --- |
| Caller experience | Waits for full result | Gets an ack, polls or is notified |
| Good for | Fast reads, simple writes | Slow, spiky, or unreliable work |
| Failure blast radius | Ties up the request | Isolated in the queue |
| Complexity | Low | Higher (need a queue + status) |

Rule of thumb: if the work can take longer than a couple of seconds or calls a flaky external service, make it async.

---

## 4. API gateway

An API gateway is the single front door to your system. Clients never talk to your application processes directly - they talk to the gateway, and the gateway forwards to the backend.

In Project 9 the gateway is nginx, configured in `gateway.conf`. It is covered in depth in module 9.3; here is why it belongs in an architecture discussion. The gateway is where you put the cross-cutting concerns that every request needs, so your application code does not have to:

- Rate limiting - `5 r/s per IP`, so one abusive client cannot starve everyone else.
- Request-size cap - `2MB`, so a giant body cannot exhaust memory before your code even sees it.
- TLS termination - HTTPS ends at the gateway; internal traffic to the api can be plain HTTP inside the trusted network.
- Hiding backends - clients cannot see how many api instances exist or where they live. You can add, remove, or restart instances behind the gateway with zero client changes.

```nginx
limit_req_zone $binary_remote_addr zone=api:10m rate=5r/s;

server {
    client_max_body_size 2m;      # request-size cap
    location / {
        limit_req zone=api burst=10;
        proxy_pass http://api_upstream;   # hides the real instances
    }
}
```

`limit_req_zone` declares a shared-memory zone keyed on the client IP and a sustained rate; `limit_req` applies it, with `burst` allowing a short spike to queue before nginx starts rejecting with 503 (see: https://nginx.org/en/docs/http/ngx_http_limit_req_module.html). `client_max_body_size` makes nginx reject a too-large body with 413 before it reaches the app (see: https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size). Because the gateway is the one public entry point, it is also the natural place to add authentication checks, logging, and load balancing across api replicas (see High availability below). Cross-reference module 9.3 for the full configuration.

---

## 5. Caching

Caching stores the result of expensive work so you can serve it again cheaply. In an AI app the expensive work is obvious: embedding text, running a retrieval query, and calling the LLM all cost time and money.

What is worth caching in a system like Project 9:

- Embeddings - the vector for a given piece of text never changes. Compute once, store it. (We already persist chunk embeddings, which is a form of this.)
- Retrieval results - the top-k chunks for a given query and clearance level are stable until the corpus changes.
- LLM responses - if two users send the identical prompt with the identical context, the answer can be reused.

Be honest: Project 9 does NOT cache LLM responses or retrieval results yet. Where you would add it: a response cache keyed by `(query, clearance)` - the clearance MUST be part of the key, or you will serve a high-clearance answer to a low-clearance user, which is a security bug, not a performance bug. For anything beyond one process, put the cache in Redis so all api replicas share it.

The hard part of caching is invalidation. A cache is a copy of the truth, and copies go stale. If you cache retrieval results and then ingest a new document, the cache now hides the new data. Every cache needs a clear answer to "when does this entry become wrong, and how do we evict it?" Common strategies: a time-to-live (TTL) so entries expire on their own, or explicit invalidation on write (when ingestion adds chunks, clear the affected query cache). If you cannot answer the invalidation question, do not add the cache yet. A wrong-but-fast answer is worse than a slow-but-right one.

---

## 6. Queues

A queue is a durable buffer of work waiting to be done. Producers put items in; consumers take items out. It is the backbone of the async pattern from section 3.

Project 9's queue is the `ingest_jobs` table. The magic that makes it a real queue and not just a to-do list is how the worker pulls jobs:

```sql
SELECT id, payload
FROM ingest_jobs
WHERE status = 'pending'
ORDER BY created_at
FOR UPDATE SKIP LOCKED
LIMIT 1;
```

`FOR UPDATE` locks the selected row so no other worker can grab it. `SKIP LOCKED` tells other workers "if a row is already locked, skip past it to the next one" instead of blocking. Together they let you run many workers safely against one table - each pulls a different job, none step on each other, and no job is processed twice. This is the standard PostgreSQL pattern for a work queue: the manual specifically names avoiding "lock contention with multiple consumers accessing a queue-like table" as the use case for SKIP LOCKED (see: https://www.postgresql.org/docs/current/sql-select.html). It means you do not need a separate queue product at this scale.

Why a queue at all, instead of just spawning a background thread? Durability. The job is a committed database row. If the worker crashes, the row is still there, status still `pending`, and the next worker picks it up. A background thread would vanish with the process.

---

## 7. Idempotency

An operation is idempotent if doing it twice has the same effect as doing it once. This sounds academic until something retries - and in distributed systems, everything retries eventually.

The ingestion worker in Project 9 is designed so a retry is safe. If a worker grabs a job, starts processing, and then crashes before marking it done, the job goes back to `pending` and gets picked up again. That re-run must not create duplicate chunks or corrupt state. This is exactly why the ingestion-queue SURVIVE scenario can requeue jobs freely - requeue-being-safe is only true because the work is idempotent. If a retry produced duplicates, requeueing would be a data-corruption bug, not a recovery tool.

For HTTP endpoints, the tool is an idempotency key. The client generates a unique key per logical operation and sends it with the request:

```bash
curl -X POST https://api.example.com/admin/ingest \
  -H "Idempotency-Key: 9f2c-doc-upload-001" \
  -d @document.json
```

The server records the key. If the same key arrives again (because the client retried after a timeout, or a webhook fired twice), the server returns the original result instead of doing the work again. Why you need this:

- Retries - the client's request succeeded but the response was lost; it retries and you would otherwise process it twice.
- Webhooks - providers deliver "at least once", meaning duplicates are normal, not exceptional. Your webhook handler MUST be idempotent.

Reads (GET) are naturally idempotent. The care is with writes and side effects. Design POST endpoints so a repeat is a no-op that returns the same answer.

---

## 8. Multitenancy

Multitenancy means one running system serves many customers (tenants) while keeping their data strictly separated. Getting this wrong is how you leak one customer's data to another - the single worst bug class in a SaaS product.

Project 9 approximates the row-level model. Access is controlled by a `clearance` column, and the separation is enforced IN the SQL query, not in Python:

```sql
SELECT chunk_id, content
FROM chunks
WHERE access_level <= :user_clearance   -- filter is IN the query
ORDER BY embedding <-> :query_vector
LIMIT :k;
```

The critical discipline: never fetch everything and filter in application code. Post-filtering in Python means the wrong rows already left the database, and one missed `if` statement leaks them. Put the boundary in the WHERE clause of every query so the database never even returns data the caller may not see.

The three multitenancy models:

| Model | Separation | Tradeoff |
| --- | --- | --- |
| Shared-schema, `tenant_id` (row-level) | A column, filtered in every query | Cheapest, most efficient; one bad query leaks data |
| Schema-per-tenant | A schema per tenant, same database | More isolation; harder to query across tenants, schema sprawl |
| Database-per-tenant | A whole database per tenant | Strongest isolation; expensive, heavy to operate at scale |

We use the shared-schema style (a clearance/access-level acting as the tenant boundary). To make it safe:

- Filter by tenant in EVERY query. No exceptions. A forgotten filter is a breach.
- Consider PostgreSQL Row-Level Security (RLS) so the database itself enforces the boundary even if a query forgets. You enable it with `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` and then define a `CREATE POLICY ... USING (...)` whose expression is checked against every row a query would return - rows failing the expression are simply invisible (see: https://www.postgresql.org/docs/current/ddl-rowsecurity.html). That turns a discipline problem ("did every query remember the filter?") into a database-enforced guarantee. The catch: the policy usually needs to know the current tenant, so you set it per-connection (for example via a session `SET` that the policy reads), which requires care with a shared connection pool.

Move up the table (schema- or database-per-tenant) only when a customer's compliance or isolation requirements demand it.

---

## 9. High availability

High availability (HA) means the system keeps serving even when a component fails. The strategy depends on one distinction: which parts hold state and which do not.

The Project 9 api is stateless. It keeps nothing important in memory between requests - all state lives in the database. Stateless components are easy to make highly available: run several identical api instances behind the gateway, and if one dies, the gateway routes to the others. No user notices. You can also scale horizontally just by adding instances.

The database is the single stateful component, and that makes it the hard part. You cannot just run five copies and load-balance writes across them. The standard answer is a primary with one or more replicas plus a failover mechanism: writes go to the primary, the replica stays in sync, and if the primary dies the replica is promoted to take over.

Project 9's docker-compose already builds the habits HA depends on - health awareness and ordered startup:

```yaml
services:
  db:
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U app"]
      interval: 10s
      retries: 5
  api:
    depends_on:
      db:
        condition: service_healthy    # api waits until db is actually ready
```

`pg_isready` is a real readiness check: it is the PostgreSQL utility that checks the connection status of a server and returns an exit code reflecting whether the server is accepting connections, not merely "is the process running" (see: https://www.postgresql.org/docs/current/app-pg-isready.html). In Compose, `depends_on` with `condition: service_healthy` makes the api wait until the db's healthcheck actually passes before it starts, rather than starting the moment the db container exists (see: https://docs.docker.com/reference/compose-file/services/, https://docs.docker.com/compose/how-tos/startup-order/). Note that Compose only waits at startup - if the db becomes unhealthy later, `depends_on` will not restart or re-gate the api, so your app still needs to handle the db going away at runtime. The HA pattern to remember: stateless app (replicate freely) + replicated database (primary/replica with failover). Push state out of your app so the app layer becomes trivially replaceable.

---

## 10. Disaster recovery

High availability handles a component dying. Disaster recovery (DR) handles the worse case: data loss, a corrupted database, a deleted table, a bad migration, a whole region gone. HA keeps you running; DR gets you back after you were not.

Project 9 has a real DR pair:

```bash
# backup.sh - a consistent, compressed logical backup
pg_dump -Fc -f /backups/app_$(date +%F).dump appdb

# restore.sh - restore into an ISOLATED database and verify, never over prod
createdb appdb_restore_check
pg_restore -d appdb_restore_check /backups/app_2026-07-23.dump
psql -d appdb_restore_check -c "SELECT count(*) FROM chunks;"   # verify
```

`-Fc` writes pg_dump's custom-format archive, which is the most flexible format and is compressed by default; it can only be read back by `pg_restore` (not `psql`), and `pg_restore -d` loads it into a target database (see: https://www.postgresql.org/docs/current/app-pgdump.html, https://www.postgresql.org/docs/current/app-pgrestore.html). One honest caveat for this teaching example: a plain `pg_dump` is a logical, point-in-time snapshot. It gives you an RPO no better than your dump interval. For an RPO of minutes you add continuous WAL archiving / physical backups (for example with pgBackRest), covered in the PostgreSQL backup docs (see: https://www.postgresql.org/docs/current/continuous-archiving.html).

Two numbers define your DR posture:

- RPO (Recovery Point Objective) - the maximum data loss you can tolerate, which equals your backup frequency. Back up daily and you can lose up to a day of data. Want an RPO of minutes? You need continuous archiving (WAL), not just nightly dumps.
- RTO (Recovery Time Objective) - how long recovery takes. You do not get to guess this. You MEASURE it by running a restore drill and timing it end to end. That is what the restore-from-backup SURVIVE scenario is for.

The rule that outranks all the tooling: **a backup you have never restored is not a backup.** An untested backup is a hope. Restore drills are the only proof that your dump is valid, your restore script works, and your RTO is real. Run them on a schedule, not after the disaster.

---

## 11. Data residency

Data residency is the requirement that data physically live in a particular place, usually a country or region, for legal or contractual reasons. The classic example: EU personal data must stay in the EU (GDPR). This is not a preference; it is often the law, and violating it carries fines.

In Project 9, the `access_level`/tenant model controls WHO can see data. Data residency controls WHERE the bytes sit. These are different axes and you need both. Residency drives concrete architecture decisions:

- Deployment region - you deploy the database (and often the whole stack) in the region the data must stay in. EU customers get EU infrastructure.
- Sometimes database-per-region - if you serve multiple regulated regions, you may run a separate database in each, and route each tenant's queries to their region's database. This connects back to the database-per-tenant idea in section 8, but sliced by geography.

The trap is a "helpful" feature that quietly moves data - a backup shipped to a bucket in the wrong region, an analytics pipeline that copies rows to a central warehouse, or an LLM call that sends the data to a vendor in another country. Residency has to be considered for every path data can take out of the box, not just the primary database.

---

## 12. Hybrid deployment

A hybrid deployment runs some components on-premises (in your own data center or VPC) and some in the cloud. The usual reason is control: keep the sensitive data - and the database - somewhere you fully own, while using cloud services for the parts that are not sensitive.

There are two common shapes:

- Split by component - the database and sensitive services on-prem, stateless compute in the cloud.
- Split by trust boundary - the data stays in your VPC, but a specific call reaches out to a vendor. The most common example in AI apps is the LLM call: the model runs at a vendor while your data sits in your infrastructure. You have to decide exactly what leaves the boundary in that call.

Project 9 gives you a real, concrete data-residency lever here. The LLM call reads `ANTHROPIC_API_KEY` from the environment and has a mock fallback:

```bash
# With a key set: real LLM call goes out to the vendor
export ANTHROPIC_API_KEY=sk-ant-...

# With no key: mock fallback, the app runs FULLY OFFLINE
unset ANTHROPIC_API_KEY   # no data leaves the box
```

When no key is set, the app uses the mock and NOTHING leaves the machine. That is not just a testing convenience - it is a genuine residency control. For a customer whose data may never touch a third-party vendor, you can run the exact same application with the key unset (or pointed at a self-hosted model) and be confident their data stays in the boundary. Same code, different deployment posture, driven by one environment variable. That is the essence of good architecture: the important decisions become configuration, not rewrites.

---

You now have the vocabulary and the concrete examples. When you build in Project 9, do not just make it work - notice which pattern each piece is, and be able to say why it is there and what it trades off. That is what separates an engineer who assembles services from one who designs systems.

## References

- MDN - HTTP 202 Accepted: https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/202
- MDN - HTTP 201 Created (contrast with 202): https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Status/201
- nginx - ngx_http_limit_req_module (limit_req_zone, burst): https://nginx.org/en/docs/http/ngx_http_limit_req_module.html
- nginx - client_max_body_size: https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size
- PostgreSQL - SELECT (FOR UPDATE / SKIP LOCKED, queue-like table): https://www.postgresql.org/docs/current/sql-select.html
- PostgreSQL - Row Security Policies (RLS): https://www.postgresql.org/docs/current/ddl-rowsecurity.html
- PostgreSQL - CREATE POLICY: https://www.postgresql.org/docs/current/sql-createpolicy.html
- PostgreSQL - pg_isready: https://www.postgresql.org/docs/current/app-pg-isready.html
- PostgreSQL - pg_dump (custom format `-Fc`): https://www.postgresql.org/docs/current/app-pgdump.html
- PostgreSQL - pg_restore: https://www.postgresql.org/docs/current/app-pgrestore.html
- PostgreSQL - Continuous Archiving and PITR (WAL, low-RPO backups): https://www.postgresql.org/docs/current/continuous-archiving.html
- Docker - Compose file services reference (ports vs expose, depends_on, healthcheck, service_healthy): https://docs.docker.com/reference/compose-file/services/
- Docker - Control startup and shutdown order in Compose: https://docs.docker.com/compose/how-tos/startup-order/

Prof. Happy (SUTA Labs)

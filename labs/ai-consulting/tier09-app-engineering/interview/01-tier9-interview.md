# Interview Prep: Tier 9 - AI Application Engineering

These are the questions a Tier 9 candidate is actually asked - the "turn a prototype into an enterprise-ready application" conversation. Each has a **strong model answer** and a **why they ask** note so you understand what the interviewer is probing. Answer in your own words; the goal is to sound like someone who has built, secured, and operated this - not recited it. Everything here maps to what you built and broke in Project 9.

---

## Q1. Synchronous versus asynchronous processing - when do you use each?

**Strong answer:**
Synchronous means the caller waits for the work to finish before getting a response; asynchronous means you accept the request, hand the work off, and respond immediately with a way to track it. Use synchronous for fast, interactive operations where the caller needs the result now - a question-and-answer endpoint, a lookup, a validation. Use asynchronous for slow, expensive, or bursty work - document ingestion, batch embedding, sending email, anything that could take seconds to minutes - because tying up a web worker for that long starves other requests and falls over under load. In Project 9 the `/ask` endpoint is synchronous (the user waits a moment for their answer), but `/admin/ingest` is asynchronous: it inserts a row into an `ingest_jobs` queue and returns a job id instantly, and a separate worker process drains the queue. The rule of thumb: if the work can exceed a second or two, or its volume is spiky, make it async with a queue and give the caller a status to poll.

**Why they ask:** It is the single most common design mistake in a first real app - doing slow work inside the request. They want to hear that you recognize the boundary and reach for a queue plus a worker, and that you understand the failure mode (worker starvation, timeouts) of getting it wrong.

---

## Q2. How do you design for multitenancy without data leaks?

**Strong answer:**
The core rule is that every query is scoped to the tenant, and that scoping lives in the data layer, not in application code that can be bypassed. In Project 9, retrieval enforces access in the SQL `WHERE` clause - a user's clearance is compared to each chunk's access level, so forbidden rows never leave the database. I never fetch everything and filter in Python, because one forgotten filter then leaks data. For real multitenancy there are three models: shared schema with a `tenant_id` column on every row (cheapest, densest, but one bad query leaks across tenants); schema-per-tenant; and database-per-tenant (strongest isolation, most overhead). Whichever you pick, the defenses are the same: a `tenant_id` on every table, every query filtered by it, and ideally PostgreSQL Row-Level Security so the database itself refuses cross-tenant reads even if the app forgets. I also test it as a negative case - I proved an intern with clearance 1 gets nothing when a clearance-2 document would answer, while a clearance-2 user gets it.

**Why they ask:** Cross-tenant data leaks are catastrophic and common. They want to see that you push isolation down to the database, that you know the tenancy models and their tradeoffs, and that you test the leak, not just the happy path.

---

## Q3. What does an API gateway give you?

**Strong answer:**
An API gateway is a single front door in front of your services, and it centralizes the concerns you do not want scattered across every service. In Project 9 the nginx gateway is the only public entry point; the API containers are not published directly. It gives me, in one place: TLS termination, rate limiting (my config caps requests per client IP, which is essential for an LLM endpoint where each call costs money and a runaway client can rack up a huge bill), request-size limits (reject a giant upload before it reaches the app), a stable entry point that hides how many API instances run behind it (so I can scale them without clients noticing), and a natural place for routing, auth header injection, and centralized logging. The mental model: cross-cutting concerns belong at the edge, so each service stays focused on its own logic.

**Why they ask:** It reveals whether you have run a service in production or only written the app. Rate limiting and cost control are the answers that show you have thought about LLM economics and abuse, not just routing.

---

## Q4. Walk me through your disaster-recovery plan.

**Strong answer:**
My DR plan has three parts: take backups, prove they restore, and know my recovery targets. In Project 9, `backup.sh` takes a compressed `pg_dump`, and - critically - `restore.sh` restores it into a separate database and verifies the row counts, because a backup you have never restored is a hope, not a backup. I run that restore drill regularly, not just when I set it up. I state two numbers: RPO (recovery point objective) is how much data I can afford to lose, which my backup frequency sets - hourly backups mean at most an hour of loss; and RTO (recovery time objective) is how long recovery takes, which the drill measures. In production the backups ship off the machine (S3 with lifecycle and versioning), the drill is scheduled and alerts if it fails, and for tighter RPO I add point-in-time recovery with WAL archiving. When a real disaster hit - I simulated a wiped knowledge base - I restored the affected tables in dependency order (parent `documents` before child `chunks`, or the foreign key rejects the rows) and verified the app answered again.

**Why they ask:** Everybody says "we have backups." They are checking whether you have actually restored one, whether you can define RPO and RTO, and whether you understand that untested backups are the number-one DR failure.

---

## Q5. How do you handle authentication versus authorization, and how did you implement SSO?

**Strong answer:**
Authentication is proving who you are; authorization is deciding what you may do - two separate checks, and conflating them is where access-control bugs come from. For SSO I use OIDC: the user is redirected to the identity provider, authenticates there, and is redirected back with an authorization code; the app exchanges that code for a signed ID token and reads the verified `email` claim - I never trust an unverified email. On success I issue my own server-side session: a row in a `sessions` table with an expiry, and an opaque `HttpOnly`, `SameSite=lax` cookie to the browser, so all trust lives server-side and I can revoke instantly. Non-human callers use bearer tokens instead. Authorization is a separate dependency: in Project 9 every admin route depends on `require_admin`, and I generalized it to `require_role(...)` so each route declares exactly which roles may call it. Forgetting that dependency is the classic exposure - I made the secure path the default by grouping admin routes under one dependency rather than relying on memory.

**Why they ask:** SSO and RBAC are table stakes for enterprise apps. They want to hear OIDC specifics (code exchange, verified claims, server-side sessions) and, above all, that you treat authn and authz as distinct and enforce authz on every protected route.

---

## Q6. A background worker keeps dying and jobs pile up. How do you make the queue reliable?

**Strong answer:**
Several layers. First, the worker runs under a supervisor - systemd, a container restart policy, or a Kubernetes Deployment - so a crash restarts it automatically instead of leaving the queue stranded. Second, jobs are claimed atomically so two workers never grab the same one; in Project 9 I use `SELECT ... FOR UPDATE SKIP LOCKED`. Third, I handle the orphaned in-flight job: if a worker dies mid-job, that job sits in `processing` forever, so I add a stale-job reaper that resets jobs whose `updated_at` is older than a safe threshold back to `queued` - with a guard so I never steal a job a live worker is actively holding. Fourth, processing is idempotent, so requeueing and retrying is always safe. Fifth, failures are recorded, not swallowed: each attempt increments a counter, and after a few tries the job moves to a `failed` dead-letter state with the error, instead of retrying forever. And I monitor queue depth so a growing backlog alerts me before a user notices their upload never appeared.

**Why they ask:** It separates people who have wired a queue in a demo from people who have operated one. The orphaned-job and dead-letter details, plus supervision and idempotency, are the signals of real experience.

---

## Q7. Your app falls over under load with database connection errors. What is happening and how do you fix it?

**Strong answer:**
Almost always it is connection handling. The classic bug is opening a new database connection per request and not closing it, or leaking connections on an error path; under a burst you open more connections than PostgreSQL allows and it starts refusing new ones with "too many clients." The fix is a connection pool: keep a small set of connections open and reuse them, and always return the connection - in a `finally` - so an exception cannot leak it. The pool's max size is a hard ceiling that protects the database; I size it so that (number of app instances times pool size) stays under PostgreSQL's `max_connections` with headroom, and when the pool is momentarily full, extra requests wait briefly rather than crashing - bounded degradation beats an outage. In Project 9 that is exactly `db.py`: a `ThreadedConnectionPool` borrowed through a context manager. When N grows large I put PgBouncer in front for server-side pooling. And I watch `pg_stat_activity` - a steadily rising connection count under steady traffic is a leak in progress.

**Why they ask:** Connection exhaustion is one of the most common production incidents. They want to hear "pool, always return it in a finally, size below the server limit, and monitor connection count" - the full picture, not just "add a pool."

---

## Q8. An internal admin endpoint turned out to be reachable by anyone. How did that happen and how do you prevent it?

**Strong answer:**
It happens when a route is added without its authorization dependency - the developer remembered to write the endpoint but not to gate it, so it authenticates no one and authorizes no one. The immediate response is to treat it as an incident: confirm the exposure, lock the route down (or delete it if it should not exist), and - because anything exposed while the hole was open is compromised - rotate any secrets it could have leaked; closing the hole does not un-leak them. To prevent recurrence, I make the secure path the default: put all admin routes under a router that applies the authorization dependency once, so a new route is protected unless someone actively opts out, rather than protected only if someone remembers. I also never return secrets in a response (that endpoint had been dumping raw tokens, which made it far worse), and I add tests for the negative cases - an anonymous caller must get 401 and a non-admin must get 403 on every admin route - because those are exactly the cases attackers probe.

**Why they ask:** Broken access control is the top web-app risk. They want to see incident instinct (fix, then rotate, then verify), a systemic prevention (secure-by-default routing), and that you test authorization, not just authentication.

---

## Q9. Monolith or microservices - how would you architect this app, and why?

**Strong answer:**
I would start as a modular monolith and only split when I have a concrete reason. Project 9 is one FastAPI app plus one worker plus one database - small, easy to develop, deploy, and reason about, with no network hops or distributed-transaction headaches. A pragmatic middle ground I do use: the API and the worker are the same image run with different commands, so they scale independently as separate processes while sharing one codebase. I would move to microservices when a specific part needs independent scaling, an independent release cadence, a different language or datastore, or strong team ownership boundaries - and I would accept the cost that brings: network latency, partial failures, distributed tracing, and data consistency across services. Premature microservices are a common way to turn a simple problem into a hard one, so the default is monolith-first, extract-when-it-hurts.

**Why they ask:** It is a maturity signal. Junior answers reflexively pick microservices; strong answers default to a monolith, name the specific triggers for splitting, and are honest about the operational cost.

---

## Q10. What is idempotency and where does it matter in this system?

**Strong answer:**
An operation is idempotent if doing it multiple times has the same effect as doing it once. It matters the moment anything can happen more than once - retries and message redelivery - which in practice is everywhere. In Project 9 the ingestion worker is designed so re-running a job is safe, which is what lets the stale-job reaper requeue an orphaned job without fear of corruption. For write endpoints that are not naturally idempotent - a POST that creates something - I use an idempotency key: the client sends a unique id with the request, and the server ignores a repeat of the same key, so a client that retries after a timeout does not double-create. The trap it prevents: you POST, the response times out, you never learn if it succeeded, you retry, and now you have two of everything. Designing for idempotency is what makes retries and at-least-once delivery safe instead of dangerous.

**Why they ask:** It is the concept that underpins reliable retries, queues, and webhooks. They want to see that you know retries without idempotency cause duplicates, and that you have applied it - not just defined it.

---

Prof. Happy (SUTA Labs)

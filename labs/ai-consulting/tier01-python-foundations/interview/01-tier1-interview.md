# Interview Prep: Tier 1 - Python, SQL, and API Foundations

These are the questions a Tier 1 AI-consulting or AI-engineering candidate is actually asked. Each has a **strong model answer** and a **why they ask** note, so you understand what the interviewer is really probing. Answer in your own words - the goal is to sound like someone who has built and debugged this, not recited it. Everything here maps to what you built and broke in this tier.

---

## Q1. Why should secrets like API keys never be hardcoded, and how do you handle them instead?

**Strong answer:**
Hardcoding a secret in source means it ends up in version control, and git history is forever - deleting the line later does not remove it from past commits. Anyone with the repo (or CI logs, or a leaked backup) has the key. So the rule is: secrets come from **environment variables** or a **secrets manager** (AWS Secrets Manager, Vault), read at runtime with something like `os.environ["API_KEY"]`. I keep real values in a `.env` file that is `.gitignore`d, commit only a `.env.example` with blank values to document what is required, and use a pre-commit secret scanner (gitleaks, detect-secrets) to block accidental commits. And critically, if a secret ever does leak, the first action is **rotation** - issue a new key and revoke the old one - because the leaked value is already compromised; scrubbing git without rotating leaves a live key in the wild.

**Why they ask:** Leaked credentials are the most common and most damaging real-world security failure. They want to see that you treat secrets as radioactive by default and that you know rotation comes before cleanup.

---

## Q2. What is idempotency, and why does it matter for an API client?

**Strong answer:**
An operation is idempotent if doing it multiple times has the same effect as doing it once. `GET`, `PUT`, and `DELETE` are naturally idempotent; `POST` (create) usually is not - POST "create order" twice and you get two orders. This matters the moment you add **retries** or receive **webhooks**, because both cause the same request to happen more than once. The classic trap: you `POST` to create something, the response times out, and you never learn whether it succeeded. If you retry blindly, you might double-create. The fix is an **idempotency key** - the client sends a unique id with the request, and the server ignores a repeat of the same key. That makes retries safe. I built exactly this in the tier: a webhook receiver that de-dupes on event id, so a sender's inevitable retry does not process the same event twice.

**Why they ask:** It separates people who have only made happy-path API calls from people who have run resilient integrations. Retries without idempotency cause duplicate charges and duplicate records - real production incidents.

---

## Q3. Explain a window function and give a case where you would use one over `GROUP BY`.

**Strong answer:**
A window function computes a value across a set of rows related to the current row, **without collapsing them** - unlike `GROUP BY`, you keep every row and add a computed column. You write it with `OVER (PARTITION BY ... ORDER BY ...)`. `PARTITION BY` restarts the calculation per group; `ORDER BY` orders rows within the partition.

Concrete case: I want to deduplicate support tickets, keeping the newest per subject. With `GROUP BY` I would lose the individual rows. Instead:

```sql
SELECT * FROM (
    SELECT *,
           row_number() OVER (PARTITION BY lower(trim(subject)) ORDER BY created_at DESC) AS rn
    FROM support_tickets
) t
WHERE rn = 1;
```

`row_number()` numbers rows within each subject, newest first; keeping `rn = 1` gives one row per subject and drops the duplicates - while still seeing every original row in the inner query. Other cases: running totals (`sum() OVER (ORDER BY ...)`), ranking, and time-series deltas with `lag()`/`lead()`.

**Why they ask:** Window functions are the single most valuable analytical SQL skill and a reliable signal of real data work. Top-N-per-group and dedupe are everyday tasks that trip up people who only know `GROUP BY`.

---

## Q4. How would you structure unit tests for a data pipeline?

**Strong answer:**
I separate the **pure logic** from the **I/O**, then test each with the right approach:

- **Unit tests for pure functions** - the transformation and validation logic (parse a row, categorize, clean a field) as functions that take input and return output, with no database or network. These are fast, deterministic, and run on every commit in CI. In this tier, `categorize()` is tested this way - no database needed.
- **Test the edge cases, not just the happy path** - empty input, missing/null fields, a malformed row, duplicates, wrong types. A data pipeline's job is largely handling bad data, so those cases are the point. I would assert that a malformed row goes to the dead-letter file and the good rows still process.
- **Integration tests** for the I/O boundaries - reading from and writing to a real (test) database - kept fewer and separate because they are slower.
- **Fixtures and factories** to build test data, and a fresh/rolled-back test schema so tests do not depend on each other.
- Follow the **testing pyramid**: many fast unit tests, fewer integration tests. And I write a test for every bug I fix, so it never regresses.

**Why they ask:** Pipelines fail on data, not logic, and untested pipelines silently corrupt downstream models. They want to see that you design code to be testable (pure functions) and that you test the failure modes, not just the sunny day.

---

## Q5. Walk me through what happens when you type a request and the server returns a 503 versus a 429. How should your client react to each?

**Strong answer:**
Status codes are grouped: `2xx` success, `4xx` the caller's fault, `5xx` the server's fault. A **`503 Service Unavailable`** is a `5xx` - the server is temporarily broken or overloaded (in my app, it means the database is unreachable). A **`429 Too Many Requests`** means I have exceeded a rate limit. Both are **transient**, so the client should **retry with exponential backoff** rather than give up. For `429` specifically I honor the `Retry-After` header if the server sent one, since it tells me exactly how long to wait. What I would **not** retry is a `400` (bad request) or `401` (bad credential) - those are `4xx`, they are my fault, and retrying just fails again. So the rule is: retry `5xx`, `429`, and timeouts with backoff and a cap; fail fast on other `4xx`.

**Why they ask:** It tests whether you understand HTTP semantics well enough to build a client that is both resilient and not abusive - retrying the right failures, respecting rate limits, and not hammering a struggling server.

---

## Q6. Your CSV ingest job crashed halfway through a nightly batch. How do you make it resilient, and what do you do with the bad rows?

**Strong answer:**
The core rule is that one bad row must never take down the whole batch. I wrap the per-row processing in `try/except` so a failure is isolated to the row that caused it, and I validate structure first (correct field count, required fields present) before trusting the data. Bad rows do not get dropped and do not crash the job - they go to a **dead-letter file** tagged with the reason they failed, so a human can inspect, fix, and re-drive them later. I log a warning per rejected row and emit a rejected-row count, and I would alert if that count spikes, because a sudden jump usually means the upstream source format changed. I also use the `csv` module rather than splitting on commas, so quoted commas do not fool the parser. Net result: the good rows load, the bad rows are captured and recoverable, and the job exits cleanly.

**Why they ask:** This is the daily reality of data engineering. They want to hear "isolate, validate, dead-letter, alert" - not "add a try/except around the whole thing and hope."

---

## Q7. What is the difference between a list, a tuple, a dict, and a set in Python, and when would you reach for each?

**Strong answer:**
A **list** `[...]` is an ordered, changeable sequence - use it when you have a collection you will loop over or append to, like rows fetched from a query. A **tuple** `(...)` is ordered but immutable - use it for a fixed group that should not change, like a coordinate or a set of keyword constants, and it can be a dict key where a list cannot. A **dict** `{"k": "v"}` maps keys to values with fast lookup - it is the workhorse: a JSON object, a database row keyed by column name, an API response body. A **set** `{...}` is an unordered collection of unique items with fast membership testing - I reach for it to deduplicate or to answer "have I seen this before" quickly, like the seen-event-ids set in my idempotent webhook receiver.

**Why they ask:** It is a fast check that you actually think in the right data structures, especially the dict-equals-JSON-equals-DB-row insight, which is central to gluing APIs and databases together.

---

## Q8. How do you find and handle missing data in a table before feeding it to a model or report?

**Strong answer:**
First I **profile** it - row count, distinct values, date range - to know what I am working with. Then I count the gaps in one pass with conditional aggregation: `count(*) FILTER (WHERE category IS NULL)` for missing values, and `count(*) FILTER (WHERE trim(subject) = '')` for the "empty but not null" case, which real data always has. I test for missing with `IS NULL`, never `= NULL`. Then I decide per column: **fill** it with a sensible default via `coalesce(category, 'uncategorized')`, **drop** the row if the missing field is essential (like a blank subject I cannot use), or **flag** it with a derived boolean feature like `(category IS NULL)::int` so the model can learn from the missingness itself. I package these checks into a data-quality report I can run on a schedule and alert on, so bad data is caught before it reaches the model, not after.

**Why they ask:** Data quality is most of the work in real AI projects, and models are only as good as their inputs. They want to see a systematic profile-quantify-decide approach and the SQL fluency (`IS NULL`, `FILTER`, `coalesce`) to execute it.

---

## Q9. Why use environment variables and virtual environments instead of just installing packages globally and hardcoding config?

**Strong answer:**
A **virtual environment** gives each project its own isolated Python with its own installed packages, so Project A's `fastapi==0.115` does not clash with Project B's older version - and I pin every dependency in `requirements.txt` so my laptop, the CI runner, and the Docker image all install identical code. That kills "works on my machine." **Environment variables** keep configuration - database host, log level, secrets - out of the code, so the same built artifact runs unchanged in dev, staging, and production; I just change the environment. This is the twelve-factor principle: config lives outside the code. Hardcoding config means editing and redeploying code just to point at a different database, and hardcoding secrets is a security incident. Reading `os.environ.get("DB_HOST", "127.0.0.1")` gives me an environment value with a safe local default.

**Why they ask:** It tests whether you can ship code a team can run reliably across environments - reproducible dependencies and config-out-of-code are baseline professional hygiene.

---

## Q10. What is a webhook, and what are the three things you must get right when receiving one?

**Strong answer:**
A webhook is the inverse of a normal API call: instead of me polling "is it done yet?", the other service calls **me** when an event happens - it POSTs a JSON event to an endpoint I expose and registered with them. Three things I must get right: **(1) Verify the sender** - the URL is public, so I check a signature header to be sure the event is genuinely from the provider and not a forgery. **(2) Acknowledge fast with a `200`** - I return quickly and do any slow work afterward (or hand it to a queue), because if I am slow the sender considers it failed and retries. **(3) Be idempotent** - senders retry, so I will receive the same event more than once; I de-dupe on the event id so processing it twice is safe. I built this in the tier - a receiver that de-dupes repeated event ids and returns immediately.

**Why they ask:** Webhooks power most real event-driven integrations, and getting verification, fast-ack, and idempotency wrong causes security holes, dropped events, and double-processing - all common production bugs.

---

## Quick-fire round (know these cold)

- **`is` vs `==`**: `is` checks identity (same object), `==` checks equality (same value). Use `is None`, never `== None`.
- **Mutable vs immutable**: lists/dicts/sets are mutable; strings/tuples/ints are immutable. Never use a mutable default argument (`def f(x=[])`) - it is shared across calls.
- **`WHERE` vs `HAVING`**: `WHERE` filters rows before grouping; `HAVING` filters groups after aggregation.
- **`->` vs `->>` in Postgres JSON**: `->` returns JSON, `->>` returns text. Use `->>` to compare or display a value.
- **Why catch specific exceptions, not bare `except:`**: a bare catch hides real bugs and swallows errors you needed to see. Catch the exception you expect (`psycopg2.OperationalError`) and let the rest surface.
- **What a timeout protects you from**: a hung upstream freezing your whole process indefinitely - always set one on every network call.

## How to prepare

Do not memorize these. For each question, actually run the thing: break the DB connection and read the 503, feed a malformed CSV and watch it dead-letter, run the resilient client against the flaky endpoint. When you have felt the failure and the fix, the answers come out naturally - and that is exactly what a good interviewer is listening for.

# Module 9.3 - Enterprise Integration

**Read this before you touch the keyboard.** An AI feature is easy. An AI feature that a real company will let inside its walls is hard, and the hard part is almost never the model. The hard part is everything around it: proving who the caller is, keeping secrets out of your code, standing a controlled front door in front of your API, moving slow work off the request path, and pulling documents out of the systems the business already runs on. That is enterprise integration. This module explains each piece using the actual code you build in Project 9, so you can see the small demo version and the production version side by side and understand why they differ.

Project 9 is the "enterprise app": a FastAPI application (`app.py`), a background worker (`worker.py`), a pooled database layer (`db.py`), an auth module (`auth.py`), and a deployment described as code (`docker-compose.yml` + `gateway.conf`). Everything below points back to those files.

---

## 1. Identity providers

An identity provider (IdP) is the system that owns "who your users are" and proves it on your behalf. Think Okta, Microsoft Entra ID (formerly Azure AD), Google Workspace, Auth0, Ping. In an enterprise, you do NOT build your own username-and-password store. Users already have a corporate account, IT already enforces password rules and multi-factor, and when someone is fired IT disables one account and they lose access to everything. Rebuilding any of that inside your app is a liability, not a feature.

So the pattern is: your app does not check passwords. It trusts the IdP to do that, and it consumes the IdP's answer.

In Project 9, `app_users` is a small local table (id, username, role, clearance, email, api_token). That table is NOT your password store. It is your local record of "people we recognise and what they may do here." Authentication (who you are) comes from the IdP. Authorization (what you may do) stays local, keyed off the email the IdP gives you.

Keep those two words straight, because they run together for the rest of your career:

| Term | Question it answers | Where it lives in Project 9 |
|------|--------------------|-----------------------------|
| Authentication (authn) | Who are you? | The IdP, plus `current_user()` |
| Authorization (authz) | What may you do? | `role` / `clearance` columns, `require_admin()` |

---

## 2. Single sign-on (SSO)

Single sign-on means a user logs in once, at the IdP, and every connected app trusts that one login. They do not get a separate password for your app. This is what "log in with your company account" does.

Why enterprises insist on it:

- One place to enforce policy (password rules, MFA, conditional access).
- One place to offboard - disable the account and access to every app vanishes at once.
- One audit trail of who logged in where.
- Users are not tempted to reuse or write down a dozen app passwords.

Project 9 supports SSO through OIDC (next section). The important mindset shift: your `/login` endpoint is not "check this password." In SSO, your login endpoint's real job is "trust the IdP's answer and turn it into a local session."

Because a classroom box has no real IdP, `auth.py` has an `OIDC_MODE` environment variable set to `mock` or `real`:

- `mock` (the lab default): `POST /login` accepts an email directly. If that email matches a row in `app_users`, the app issues a server-side session cookie. This lets you exercise the SAME session and role code without standing up an IdP.
- `real`: you would redirect to a real provider and run the full flow below.

The critical detail is that after the login step, the SAME code runs in both modes: `create_session()` issues an opaque session id, and `current_user()` resolves it. Only the "how did we learn the email" part changes.

---

## 3. OAuth (OAuth2)

OAuth2 is a delegated-authorization protocol. Its job is to let one party grant another party limited access to something, without handing over a password. The output of OAuth2 is an access token: a string that says "the bearer may do X for a while."

Note carefully: OAuth2 by itself is about authorization (access to resources), NOT about identity. It was designed to answer "may this app read your calendar," not "who is this person." That distinction is exactly why OpenID Connect exists (section 4).

The flow Project 9 uses in `real` mode is the authorization-code flow, the correct one for a web app with a server backend. Walk through it slowly:

1. User clicks "Log in." Your app redirects the browser to the IdP's authorize URL, sending your `client_id`, a `redirect_uri`, and the `scopes` you want.
2. The user authenticates AT THE IDP (password, MFA, whatever - your app never sees any of it).
3. The IdP redirects the browser back to your `redirect_uri` with a short-lived authorization code in the URL.
4. Your server (back channel, not the browser) exchanges that code plus your `client_secret` for tokens by calling the IdP's token endpoint.
5. The IdP returns an access token (and, with OIDC, an ID token).

The vocabulary you will use constantly:

| Term | Meaning |
|------|---------|
| issuer | The IdP's base URL. Identifies who minted the token. In Project 9: `OIDC_ISSUER`. |
| client_id | Public identifier for YOUR app, registered at the IdP. `OIDC_CLIENT_ID`. |
| client_secret | Private password for your app, used in the server-side code exchange. `OIDC_CLIENT_SECRET`. NEVER in browser code. |
| redirect_uri | The exact URL the IdP is allowed to send the user back to. Locked down to prevent token theft. |
| scopes | What you are asking for. For login: `openid email profile`. |
| authorization code | Short-lived one-time code, exchanged server-side for tokens. |
| access token | Grants access to resources for a limited time. |

Why the code goes through the browser but the secret exchange happens server-to-server: the browser is untrusted. A code alone is useless without the `client_secret`, which lives only on your server. That is what makes the authorization-code flow safe for confidential clients (an app that can keep a secret, like our server-backed web app), as opposed to public clients (a single-page app or mobile app that cannot).

One modern addition you must know about: PKCE (Proof Key for Code Exchange, RFC 7636). PKCE binds the authorization code to the specific client that started the flow, so a stolen code cannot be redeemed by anyone else. In OAuth 2.1 and the current OAuth security best-practice (RFC 9700), PKCE is REQUIRED for public clients using the authorization-code flow and RECOMMENDED even for confidential clients like ours (see: https://oauth.net/2.1/, https://datatracker.ietf.org/doc/rfc9700/). Concretely, before step 1 your app generates a random `code_verifier`, sends its hash as `code_challenge` on the authorize request, and sends the original `code_verifier` on the token exchange in step 4. Most IdP client libraries do this for you when you enable it. Turn it on: it is cheap and it closes a real attack.

---

## 4. OpenID Connect (OIDC)

OpenID Connect is a thin identity layer built ON TOP of OAuth2. It adds one thing OAuth2 was missing: a standard way to learn who the user is. It does this with a new artifact, the ID token.

An ID token is a signed JWT (JSON Web Token). "Signed" means the IdP cryptographically stamped it, so you can verify it was not tampered with and really came from the issuer you expect. Inside are claims - facts about the user - including `email`, `sub` (a locally unique, never-reassigned user id within the issuer), `name`, the `iss` (issuer), the `aud` (audience, which must contain your `client_id`), and expiry timestamps (see: https://openid.net/specs/openid-connect-core-1_0.html). Note `aud` MAY be an array of multiple audiences; the spec says you must reject the token if your `client_id` is not listed, or if it contains other audiences you do not trust.

The rule that will save you from a real breach: read the VERIFIED `email` claim from the ID token. Never trust an email that a client just handed you.

`auth.py` makes this concrete. In `real` mode, `resolve_oidc_email()` is where you exchange the code and pull the verified `email` claim out of the ID token. In `mock` mode it returns the email the caller supplied - fine for a class box with no IdP, dangerous anywhere else, which is why the function name and comments call it out. A decoded ID token looks like this:

```json
{
  "iss": "https://your-idp.example.com",
  "aud": "your-client-id",
  "sub": "a1b2c3-stable-user-id",
  "email": "dana@acme.com",
  "email_verified": true,
  "name": "Dana Lee",
  "exp": 1735689600
}
```

The validation steps the OIDC Core spec requires (section 3.1.3.7) are, in order: verify the signature against the IdP's published public keys (JWKS), confirm the `iss` exactly matches the issuer you expect, confirm the `aud` contains your `client_id`, and confirm the current time is before `exp` (see: https://openid.net/specs/openid-connect-core-1_0.html). On top of that, for our email-keyed lookup you confirm `email_verified` is true, and only then trust `email`. Then you look that email up in `app_users` and, if found, call `create_session()`. From that point on the user has a Project 9 session cookie and the rest of the app never thinks about OIDC again.

So the layering, one more time:

- OAuth2 gives you access tokens (authorization).
- OIDC adds the ID token (identity) on top.
- Project 9 uses the identity to issue its OWN session, then does authorization locally with `role` and `clearance`.

---

## 5. Service accounts

Not every caller is a human with a browser. Nightly batch jobs, other microservices, CI pipelines, and your own `test_app.py` all need to call the API. They cannot do an interactive SSO flow - there is nobody to click "Log in." For them you use a service account.

In Project 9 a service account authenticates with a bearer token:

```bash
curl -H "Authorization: Bearer $API_TOKEN" http://localhost:8080/some/endpoint
```

`current_user()` in `auth.py` accepts either path: a session cookie (humans, via SSO) or an `Authorization: Bearer <api_token>` header (machines, via `_user_by_token()`). Both resolve to the same user dict, so the rest of the code does not care how you proved yourself.

How a service-account token differs from a human SSO session:

| | Human SSO session | Service-account token |
|---|-------------------|-----------------------|
| Who | A person with a browser | A script or another service |
| Login flow | Interactive OIDC | None - the token IS the credential |
| Lifetime | Short (`SESSION_TTL_HOURS`, 8h) | Long-lived but should be rotatable |
| Stored where | `sessions` table, opaque id | `app_users.api_token` |
| MFA | Enforced at IdP | Not applicable |

Two production rules the lab deliberately does NOT follow, so you must know them:

1. Hash tokens at rest. Project 9 stores `api_token` in plain text for demo clarity. In production, store only a hash and compare hashes, so a database dump does not hand an attacker live credentials. This is the same principle OWASP applies to any long-lived secret or credential you have to persist (see: https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html).
2. Scope and rotate. A service account should have the narrowest role it needs (not admin "just in case"), and its token should be rotatable without downtime. Long-lived, over-privileged tokens are one of the most common ways enterprises get breached.

---

## 6. Secret managers

A secret is any value that would hurt you if leaked: database passwords, `client_secret`, API keys, tokens. The first law of secrets is that they must never be in your source code or your container image.

Project 9 follows the 12-factor config rule: "store config in the environment" - the app and worker read ALL configuration from environment variables, which the methodology recommends specifically because env vars are hard to check into git by accident and are language- and OS-agnostic (see: https://12factor.net/config). `db.py`'s `_dsn()` builds its connection from `DB_HOST`, `DB_PASSWORD`, and friends; `auth.py` reads `OIDC_*`; the LLM key is `ANTHROPIC_API_KEY`. Locally these come from a `.env` file that is `.gitignored`, and the repo ships a committed `.env.example` that documents every required variable with safe placeholder values. New developers copy `.env.example` to `.env` and fill it in. The real `.env` never enters git.

Look at the Dockerfile mindset: the image bakes NO secrets. Secrets are passed at RUNTIME (`env_file: .env` in `docker-compose.yml`). This matters because images get pushed to registries and shared; a secret baked into a layer is a secret leaked to everyone who can pull the image, forever, even after you "remove" it in a later layer.

In production, `.env` files do not scale and are hard to audit, so environment variables are populated by a dedicated secret manager - AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager, Azure Key Vault - which injects them at deploy time. Why bother:

- Rotation - change a database password in one place and every service picks it up, without a code change or rebuild.
- Audit - the manager logs who read which secret and when.
- Access control - fine-grained: this service may read the DB password, not the LLM key.
- No secrets in git, in images, or on developer laptops.

The mental model does not change from lab to prod: the app still just reads environment variables. Only the thing that FILLS those variables changes - a local `.env` in the lab, a secret manager in production.

---

## 7. API gateways

An API gateway is a single public front door that sits in front of your application. Clients talk to the gateway; the gateway talks to your API instances. Your API is never exposed to the internet directly.

Project 9 uses nginx as the gateway, configured in `gateway.conf` and wired up in `docker-compose.yml`. Look at what the compose file publishes: only the `gateway` service maps a host port (`8080:80`), which is what `ports` does - it publishes a container port to the host. The `api` service uses `expose: "8000"`, which makes the port reachable to other containers on the same Docker network but NOT published to the host or the outside world (see: https://docs.docker.com/reference/compose-file/services/). That is the whole point - the only way in is through the gateway.

What one gateway config buys you, all in one place:

- TLS termination - HTTPS ends at the gateway; internal traffic can be plain HTTP on the private network.
- Rate limiting - `gateway.conf` defines `limit_req_zone $binary_remote_addr ... rate=5r/s` per client IP, with a small `burst`. nginx keys the zone on `$binary_remote_addr` (a compact binary form of the client IP that uses less shared-memory than the string form) and enforces the rate with a leaky-bucket algorithm: requests above the rate are queued up to `burst`, then rejected (see: https://nginx.org/en/docs/http/ngx_http_limit_req_module.html). This is critical for LLM endpoints, because every call to a model costs money and a single abusive client could run up a large bill or exhaust your quota. Rate limiting is cost control, not just abuse control.
- Request-size limits - `client_max_body_size 2m` rejects oversized uploads before they ever reach the app; nginx returns 413 (Request Entity Too Large) when the declared body exceeds this, so a giant payload cannot tie up a worker or exhaust memory (see: https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size).
- Hiding your topology - clients cannot tell whether one API instance or twenty run behind `upstream app_backend`. You can scale the API horizontally and clients never notice.
- A single choke point for security headers, routing, logging, and health checks (note the `/health` location deliberately bypasses the rate limit so monitors are never throttled).

The one-sentence version: an API gateway is where you put every cross-cutting concern that should NOT live in your application code.

---

## 8. Message queues

Some work is too slow to do while the caller waits. Ingesting a 5MB document - chunking it, indexing it - can take many seconds. If you do that inside the HTTP request, one upload ties up a web worker the whole time, and under load your API falls over. The fix is a message queue: the request quickly writes a "please do this" record and returns; a separate worker does the slow work later.

Project 9's queue is a PostgreSQL table, `ingest_jobs`. The API inserts a row (`status='queued'`) and returns immediately. `worker.py` is a separate process that drains the queue. The clever, load-bearing line is how it claims work:

```python
SELECT id, title, source, body, access_level, attempts
FROM ingest_jobs WHERE status = 'queued'
ORDER BY id ASC FOR UPDATE SKIP LOCKED LIMIT 1
```

`FOR UPDATE` locks the row it selects against concurrent updates. `SKIP LOCKED` tells other workers to skip rows already locked by someone else rather than block on them. Together they mean you can run many workers safely - no two workers ever grab the same job, with no extra coordination service. This is a first-class PostgreSQL use case: the manual states SKIP LOCKED "can be used to avoid lock contention with multiple consumers accessing a queue-like table" (see: https://www.postgresql.org/docs/current/sql-select.html). The worker then marks it `processing`, does the chunking, and sets `done`; on failure it increments `attempts` and requeues up to `MAX_ATTEMPTS`, after which the job is `failed` (a dead-letter). Errors are recorded, never silently swallowed.

This is a real queue, but a lightweight one. When is a database-backed queue the right call, and when do you reach for a dedicated broker (RabbitMQ, Amazon SQS, Kafka)?

| | DB-backed queue (`ingest_jobs`) | Dedicated broker |
|---|--------------------------------|------------------|
| Setup | None - you already have the DB | A new system to run and monitor |
| Transactions | Enqueue in the SAME transaction as your data - atomic | Separate system, harder to keep in sync |
| Throughput | Fine for modest volume | Scales to very high volume |
| Decoupling | Producer and consumer share a DB | Fully decoupled services |
| Features | You build retries/DLQ yourself (we did) | Built-in retries, fan-out, ordering, DLQ |

The tradeoff in one line: a DB-backed queue is simple and transactional and perfect until you outgrow it; a broker scales further and decouples services at the cost of another moving part. Start with the table, move to a broker when volume or decoupling demands it - not before.

---

## 9. Enterprise document stores and SaaS integrations

The Project 9 knowledge base is only as useful as the documents in it. In the lab you feed it text directly. In a real enterprise, the documents already live somewhere - SharePoint, Confluence, Google Drive, Notion, an S3 bucket, a ticketing system - and you integrate with those systems through their APIs. These are SaaS integrations: your app pulling data from someone else's service.

The pattern reuses everything above:

1. Pull via the source's API (authenticating as a service account, section 5).
2. Enqueue an ingest job per document - one `ingest_jobs` row each (section 8).
3. The worker chunks and indexes it (section 8), exactly as it does for a direct upload.

The same worker, the same queue, a different source. That is the payoff of building the queue: adding SharePoint means writing a puller, not rebuilding ingestion.

Two hard rules for pulling from someone else's system:

- Respect their access controls. If a document is restricted in SharePoint, that restriction must follow the document into your store. Notice `ingest_jobs` and `chunks` carry `access_level` - it exists so retrieval can filter by clearance. Ingesting a confidential document as if it were public is a data leak with your name on it.
- Respect their rate limits. SaaS APIs throttle you. Page politely, back off on `429`, and never hammer a source during a full re-sync.

The other rule is idempotency and dedup. You WILL re-sync - on a schedule, after a crash, when someone edits a file. If a re-sync naively re-ingests everything, your knowledge base fills with duplicates and retrieval quality drops. Make ingestion idempotent: give each source document a stable external id (its SharePoint item id, its Drive file id), and on re-sync either skip unchanged documents or replace the existing one rather than appending a copy. "Running the sync twice produces the same result as running it once" is the property you are protecting.

---

## 10. Database connections

Every piece above eventually reads or writes the database, so how you connect matters. Opening a fresh PostgreSQL connection per request is the classic way an app falls over under load - every request pays the TCP and authentication cost, and a traffic burst opens more connections than the database allows.

Project 9 connects through a pooled connection layer in `db.py`: `init_pool()` opens a small, bounded set of connections once, and `get_conn()` hands them out and always returns them, even on error. All settings come from the environment (`DB_HOST`, `DB_POOL_MIN`, `DB_POOL_MAX`, and so on) - never hardcoded. Pool sizing, borrow timeouts, and recovery all live in this one file, which is why it is also the file the db-connection-storm SURVIVE scenario exercises.

This is intentionally brief here because connection pooling, pool sizing versus PostgreSQL's `max_connections`, and graceful degradation under a connection storm are covered in depth in module 9.1. Cross-reference that module before you tune anything - the short version is that `db.py` is the single place connections are created, and keeping it that way is what makes the app survivable under load.

---

## References

- OpenID Connect Core 1.0 (ID token claims iss/aud/sub/exp, validation in 3.1.3.7): https://openid.net/specs/openid-connect-core-1_0.html
- OAuth 2.1 (authorization-code flow, PKCE required for public clients): https://oauth.net/2.1/
- RFC 9700 - Best Current Practice for OAuth 2.0 Security (PKCE guidance): https://datatracker.ietf.org/doc/rfc9700/
- RFC 7636 - Proof Key for Code Exchange (PKCE): https://datatracker.ietf.org/doc/html/rfc7636
- RFC 6749 - The OAuth 2.0 Authorization Framework (authorization-code grant): https://datatracker.ietf.org/doc/html/rfc6749
- The Twelve-Factor App - Store config in the environment: https://12factor.net/config
- nginx - ngx_http_limit_req_module (limit_req_zone, burst, $binary_remote_addr, leaky bucket): https://nginx.org/en/docs/http/ngx_http_limit_req_module.html
- nginx - client_max_body_size (ngx_http_core_module): https://nginx.org/en/docs/http/ngx_http_core_module.html#client_max_body_size
- Docker - Compose file services reference (ports vs expose): https://docs.docker.com/reference/compose-file/services/
- PostgreSQL - SELECT (FOR UPDATE / SKIP LOCKED, queue-like table): https://www.postgresql.org/docs/current/sql-select.html
- OWASP - Cryptographic Storage Cheat Sheet (hash secrets at rest): https://cheatsheetseries.owasp.org/cheatsheets/Cryptographic_Storage_Cheat_Sheet.html
- OWASP - Access Control Cheat Sheet (authz separate from authn): https://cheatsheetseries.owasp.org/cheatsheets/Authorization_Cheat_Sheet.html

Prof. Happy (SUTA Labs)

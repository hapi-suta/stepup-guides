# Concepts: APIs

**Read this before you touch the keyboard.** An **API** (Application Programming Interface) is how one program talks to another. In AI work you are constantly on both sides: you **call** APIs (an LLM provider, a data source) and you **build** APIs (the FastAPI service in Project 1 that others call). This document is the vocabulary and the rules for both.

The examples use Project 1's own API (`GET /health`, `GET /summary`) and a generic external API of the kind you will call from an AI service.

---

## 1. What an API is

An API is a **contract**: "send me a request shaped like this, and I will send you a response shaped like that." You do not need to know how the other program works inside - only the contract. Your `/summary` endpoint is an API: the contract is "GET this URL, receive JSON with `total` and `by_category`."

Most APIs today are **HTTP APIs** - they speak the same protocol as web browsers. That is why you can test yours with `curl` and a browser. When people say "call the OpenAI API" or "the Anthropic API", they mean sending HTTP requests to a URL.

---

## 2. HTTP methods

The **method** (or verb) says what kind of action you want. The four you must know:

| Method | Means | Example | Changes data? |
|--------|-------|---------|---------------|
| `GET` | read something | `GET /summary` | no |
| `POST` | create something | `POST /tickets` | yes |
| `PUT` | replace something whole | `PUT /tickets/42` | yes |
| `DELETE` | remove something | `DELETE /tickets/42` | yes |

The critical property: **`GET` is safe and should never change data.** A monitor hitting `GET /health` a thousand times must be harmless. `POST`/`PUT`/`DELETE` change state. By the HTTP spec, `GET` is both safe and idempotent; `PUT` and `DELETE` are idempotent but not safe; `POST` is neither (see: MDN, HTTP request methods). Idempotent means doing it twice has the same effect as once (deleting ticket 42 twice still leaves it deleted). `POST` usually is not, which is why creating things needs care (see idempotency below).

---

## 3. Requests and responses

Every HTTP exchange is one **request** and one **response**.

A **request** has:

- a **method** (`GET`),
- a **URL** (`http://127.0.0.1:8000/summary`), optionally with **query parameters** (`?page=2&limit=50`),
- **headers** (metadata - who you are, what format you want),
- optionally a **body** (data you send, for `POST`/`PUT`, usually JSON).

A **response** has:

- a **status code** (`200`, `404`, `503`),
- **headers** (metadata about the response),
- a **body** (the data, usually JSON).

```bash
curl -s http://127.0.0.1:8000/summary
# request: GET /summary, no body
# response: 200, body {"total":10,"by_category":{...}}
```

---

## 4. JSON

**JSON** (JavaScript Object Notation) is the standard format for API data. It is just text with a simple structure: objects `{}`, arrays `[]`, strings, numbers, booleans, and `null`.

```json
{
  "total": 10,
  "by_category": {"billing": 3, "auth": 2},
  "ok": true,
  "note": null
}
```

A JSON object maps directly to a Python dict; a JSON array to a Python list. That is why dicts are so central (see [01-python-fundamentals.md](01-python-fundamentals.md)). In Python: `import json; json.loads(text)` turns JSON text into a dict; `json.dumps(obj)` turns a dict into JSON text. FastAPI does this conversion for you automatically - you return a dict, it sends JSON.

---

## 5. Headers

**Headers** are key-value metadata sent with a request or response. They carry everything that is not the main data. The ones you will actually use:

- `Content-Type: application/json` - "the body is JSON." Send this when you POST JSON.
- `Accept: application/json` - "send me JSON back."
- `Authorization: Bearer <token>` - your credential (see auth below).
- `User-Agent` - identifies the client.
- `Retry-After` - a server sends this to say "wait N seconds before retrying" (you handle it in the rate-limit exercise).

```bash
curl -s -H "Authorization: Bearer $API_KEY" \
        -H "Content-Type: application/json" \
        https://api.example.com/v1/data
```

`-H` adds a header. The token comes from an environment variable (`$API_KEY`), never hardcoded.

---

## 6. Status codes

The **status code** is a three-digit number saying how the request went. Learn the ranges, then the common ones.

- **2xx - success.** `200 OK` (got it), `201 Created` (POST made something), `204 No Content` (success, nothing to return).
- **3xx - redirect.** `301`/`302` (the resource moved).
- **4xx - the caller's fault.** `400 Bad Request` (malformed), `401 Unauthorized` (no/invalid credential), `403 Forbidden` (valid credential, not allowed), `404 Not Found`, `429 Too Many Requests` (you are rate-limited).
- **5xx - the server's fault.** `500 Internal Server Error` (it crashed), `503 Service Unavailable` (temporarily down, and the standard code when a server is overloaded or under maintenance - `app.py` returns this when the database is unreachable; a `503` should carry a `Retry-After` header when a recovery time is known - see: MDN, 503).

The dividing rule: **4xx means fix your request; 5xx means the server is broken - retrying may help.** Your client should retry 5xx and 429, but not 400 or 401 (retrying a bad request just fails again). This distinction drives all resilient-client logic.

---

## 7. Authentication

**Authentication** proves who is making the request. The common schemes, simplest first:

- **API key** - a long secret string you send in a header (`Authorization: Bearer sk-...`) or query parameter. Simple, and the most common way to call AI provider APIs. The key identifies and authorizes you. Treat it as a password: environment variable, never committed, rotate on leak.
- **Basic auth** - username and password base64-encoded in the header. Older, still seen internally.
- **OAuth** - see below, for delegated access.

`401` means authentication failed (bad or missing key). `403` means you authenticated fine but are not permitted to do this thing.

---

## 8. API keys (in practice)

An API key is the credential you will use most. Handling rules, which are graded in the `committed-secret` SURVIVE scenario:

- Store it in an environment variable: `export API_KEY=sk-...`, read with `os.environ["API_KEY"]`.
- Never hardcode it in source, never commit it, never log it.
- Give each service its own key so you can rotate one without breaking others.
- On leak: rotate immediately (issue a new key, revoke the old), then scrub. Scrubbing without rotating is worthless - the key was already exposed.

---

## 9. OAuth concepts

**OAuth** is a protocol for **delegated** access: letting your app act on a user's behalf without ever seeing their password. "Sign in with Google" is OAuth. You will mostly consume OAuth rather than implement it at Tier 1, so know the shape:

- The user authorizes your app at the provider.
- The provider gives your app an **access token** (short-lived) and often a **refresh token** (used to get new access tokens).
- You send the access token as `Authorization: Bearer <token>` on each request.
- When it expires you use the refresh token to get a new one, instead of asking the user again.

The key idea versus an API key: OAuth tokens are per-user, scoped (limited to certain permissions), and expire. API keys are per-application and long-lived.

---

## 10. Rate limits

A **rate limit** caps how many requests you may send in a window (for example, 60 per minute). Exceed it and the server returns `429 Too Many Requests`, often with a `Retry-After` header telling you how long to wait (`Retry-After` may be a number of seconds or an HTTP date - see: MDN, Retry-After). Every serious API - especially LLM providers - rate-limits you.

Your job as a client: respect the limit. When you get a `429`, do not hammer - wait (honor `Retry-After` if present, otherwise back off) and retry. A well-behaved client stays under the limit and degrades gracefully when it hits one.

---

## 11. Pagination

When a response would contain thousands of items, the server returns them in **pages** - a chunk at a time - and tells you how to get the next chunk. You must loop until there are no more pages, or you silently process only the first page (a very common bug).

Two common styles:

- **Offset/limit**: `GET /tickets?limit=50&offset=100` - "50 items starting at 100." Increase `offset` each loop until you get fewer than `limit` items back.
- **Cursor/token**: the response includes `next_cursor`; you pass it on the next request until it is empty. More robust for changing data.

You implement offset pagination in USE 02, so your client fetches **all** results, not just page one.

---

## 12. Retries

A **retry** is sending a failed request again. Networks and servers fail transiently, so a resilient client retries - but carefully:

- Retry only **transient** failures: `429`, `5xx`, timeouts, connection resets. Never retry `400`/`401`/`404` - those fail every time.
- Use **exponential backoff**: wait 1s, then 2s, then 4s, doubling each time, so you do not stampede a struggling server.
- Add **jitter** (a little randomness to the wait) so many clients do not all retry at the same instant.
- Cap the number of retries (say 5) and give up cleanly with a clear error, rather than looping forever.
- Combine with idempotency (below) so retrying a `POST` does not create duplicates.

This backoff loop is the core of the `api-429-timeout` SURVIVE scenario and USE 02.

---

## 13. Timeouts

A **timeout** is the maximum time you will wait for a response before giving up. **Always set one.** Without a timeout, one hung server can freeze your whole program indefinitely - a request that never returns and never fails.

```python
import requests
requests.get(url, timeout=5)          # one value applies to BOTH connect and read
requests.get(url, timeout=(3.05, 27)) # (connect timeout, read timeout) separately
```

By default `requests` has NO timeout - it can hang indefinitely - so you must always pass one (see: requests docs, Timeouts). A single value applies to both the connection timeout (time to establish the connection) and the read timeout (time to get the response); pass a `(connect, read)` tuple to set them separately. A timeout is a transient failure, so it pairs with retries: time out, back off, try again, and cap the attempts.

---

## 14. Webhooks

A **webhook** is the reverse of a normal API call: instead of you polling "is it done yet?", the other service **calls you** when an event happens. You expose an endpoint (say `POST /webhook`), register its URL with the provider, and they POST a JSON event to it (payment succeeded, job finished, new ticket).

Rules for receiving webhooks:

- **Verify the sender** - webhooks are public URLs; check a signature header so you only trust real events.
- **Respond fast with `200`** - acknowledge receipt immediately, do slow work afterward, or the sender will consider it failed and retry.
- **Be idempotent** - senders retry, so you will receive the same event more than once; processing it twice must be safe (see below).

You build a small webhook receiver in USE 02.

---

## 15. REST design

**REST** is the dominant style for HTTP APIs. It is a set of conventions that make an API predictable:

- **Resources are nouns, addressed by URL**: `/tickets`, `/tickets/42`. Not verbs like `/getTicket`.
- **The HTTP method is the verb**: `GET /tickets` lists, `POST /tickets` creates, `GET /tickets/42` reads one, `PUT /tickets/42` replaces, `DELETE /tickets/42` removes.
- **Status codes carry the outcome** (section 6).
- **JSON in, JSON out**, with a stable shape.
- **Stateless**: each request carries everything needed (including auth); the server keeps no per-client session between calls. This is what lets you run many copies behind a load balancer.

Project 1 is a small REST API. Following these conventions means any developer can guess how to use it without reading much documentation - which is the whole point.

---

## Idempotency (the concept behind safe retries and webhooks)

An operation is **idempotent** if doing it multiple times has the same effect as doing it once. `GET`, `PUT`, and `DELETE` are naturally idempotent; `POST` (create) usually is not - POST "create ticket" twice and you get two tickets.

This matters the moment you add retries or receive webhooks, because both cause the same request to happen more than once. The fix: an **idempotency key** - the client sends a unique id with the request, and the server ignores a repeat of the same key. That way a retried `POST` after a timeout (where you never learned if the first one worked) does not create a duplicate. Idempotency is a top interview topic for exactly this reason - it is the difference between a client that is safe to retry and one that quietly double-charges customers.

---

## Vocabulary recap

- **API / contract** - how programs talk; request-shape in, response-shape out.
- **HTTP method** - `GET` (read, safe), `POST` (create), `PUT` (replace), `DELETE`.
- **request / response** - method + URL + headers + body / status + headers + body.
- **JSON / `->` dict** - the standard data format; maps to Python dicts and lists.
- **headers** - metadata: `Content-Type`, `Authorization`, `Retry-After`.
- **status code** - `2xx` success, `4xx` your fault, `5xx` server fault; retry `5xx`/`429`, not `4xx`.
- **authentication / API key / OAuth** - proving who you are; keys per-app, OAuth tokens per-user and expiring.
- **rate limit / `429`** - cap on request volume; back off and retry.
- **pagination** - fetch all pages, not just the first; offset or cursor.
- **retry / exponential backoff / jitter** - resend transient failures, carefully.
- **timeout** - always set one; a hung server must not freeze you.
- **webhook** - the server calls you on an event; verify, ack fast, be idempotent.
- **REST / stateless** - noun resources, method verbs, JSON, no server-side session.
- **idempotency / idempotency key** - doing it twice equals doing it once; makes retries and webhooks safe.

You now have the full C layer. Next you apply it: the USE exercises and the SURVIVE scenarios.

---

## References

- MDN, HTTP request methods (safe vs idempotent): https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
- MDN, HTTP response status codes: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
- MDN, 503 Service Unavailable: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/503
- MDN, 429 Too Many Requests: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/429
- MDN, Retry-After header: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After
- RFC 9110, HTTP Semantics (methods, status codes, idempotency): https://www.rfc-editor.org/rfc/rfc9110
- MDN, Authorization header / Bearer scheme: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Authorization
- requests documentation, Timeouts: https://requests.readthedocs.io/en/latest/user/advanced/#timeouts
- JSON specification: https://www.json.org/

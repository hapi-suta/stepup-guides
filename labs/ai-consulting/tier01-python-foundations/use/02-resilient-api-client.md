# USE: Build a Resilient API Client and a Webhook Receiver

**Goal:** most AI work is calling flaky external APIs (LLM providers, data sources) and receiving events back. A naive client that fires one request with no timeout, no retry, and no pagination will fail in production. You will build a client that handles **pagination, retries, timeouts**, and a small **webhook receiver** - the resilience patterns from [04-apis.md](04-apis.md), made real.

**Where you are:** the lab server, as **ec2-user**, Project 1 in `~/project1`, virtual environment available.

**What you will practice:** functions, loops, error handling, HTTP status codes, exponential backoff, and a tiny FastAPI endpoint.

---

## Step 1: Install the requests library

`requests` is the standard Python HTTP client. Add it to the project.

On your **lab server**, as **ec2-user**, in `~/project1`:

```bash
cd ~/project1
```

```bash
source .venv/bin/activate
```

```bash
pip install requests==2.32.3
```

Expected output (yours will differ, truncated):

```
Successfully installed requests-2.32.3
```

Record the new dependency (config and dependency management discipline from the concepts):

```bash
echo "requests==2.32.3" >> requirements.txt
```

`>>` appends the line to the file. Pinning the version keeps installs reproducible.

---

## Step 2: Stand up a local flaky API to test against

You need something unreliable to prove your client is resilient. This tiny server returns paginated data but randomly fails with `429` and timeouts, exactly like a rate-limited real API.

Still on the **lab server**, as **ec2-user**, create it with `vi`:

```bash
vi flaky_server.py
```

Press `i`, type the following, then `Esc` and `:wq`:

```python
"""A deliberately flaky, paginated API for testing the client.

- /items?offset=&limit=  returns a page of items.
- ~40% of the time it returns 429 (rate limited) with Retry-After.
- ~15% of the time it sleeps long enough to trigger a client timeout.
"""
import random
import time

from fastapi import FastAPI, Response

app = FastAPI()

TOTAL = 25  # 25 fake items across pages


@app.get("/items")
def items(offset: int = 0, limit: int = 10, response: Response = None):
    roll = random.random()
    if roll < 0.40:
        response.status_code = 429
        response.headers["Retry-After"] = "1"
        return {"error": "rate limited"}
    if roll < 0.55:
        time.sleep(6)  # longer than the client's timeout -> forces a timeout
    page = [{"id": i} for i in range(offset, min(offset + limit, TOTAL))]
    return {"items": page, "total": TOTAL}
```

Start it in the background on port 8100 so it does not clash with Project 1 on 8000:

```bash
nohup uvicorn flaky_server:app --host 127.0.0.1 --port 8100 > flaky.log 2>&1 &
```

`nohup ... &` runs it in the background; output goes to `flaky.log`. Give it two seconds, then confirm it responds:

```bash
curl -s "http://127.0.0.1:8100/items?offset=0&limit=10"
```

Expected output (yours will differ - you may hit a 429 on the first try, run it again):

```
{"items":[{"id":0},{"id":1},{"id":2},...],"total":25}
```

---

## Step 3: Write the resilient client

This client sets a **timeout**, **retries** transient failures with **exponential backoff and jitter**, and follows **pagination** until all items are fetched.

Still on the **lab server**, as **ec2-user**, create it with `vi`:

```bash
vi resilient_client.py
```

Press `i`, type the following, then `Esc` and `:wq`:

```python
"""A resilient HTTP client: timeouts, retries with backoff, pagination.

Demonstrates the client-side resilience patterns from concepts/04-apis.md.
"""
import logging
import random
import time

import requests

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("client")

BASE_URL = "http://127.0.0.1:8100"
TIMEOUT = 3        # seconds - never wait forever
MAX_RETRIES = 5    # give up cleanly after this many
PAGE_LIMIT = 10


def get_with_retry(url: str, params: dict) -> dict:
    """GET a URL, retrying transient failures with exponential backoff."""
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(url, params=params, timeout=TIMEOUT)
        except requests.exceptions.Timeout:
            wait = backoff(attempt)
            log.warning("timeout on attempt %d, backing off %.1fs", attempt, wait)
            time.sleep(wait)
            continue

        if resp.status_code == 429:
            # honor Retry-After if present, else back off
            wait = float(resp.headers.get("Retry-After", backoff(attempt)))
            log.warning("429 rate limited on attempt %d, waiting %.1fs", attempt, wait)
            time.sleep(wait)
            continue

        if 500 <= resp.status_code < 600:
            wait = backoff(attempt)
            log.warning("server error %d on attempt %d, backing off %.1fs",
                        resp.status_code, attempt, wait)
            time.sleep(wait)
            continue

        if resp.status_code >= 400:
            # client error (400/401/404) - retrying will not help, fail fast
            raise RuntimeError(f"client error {resp.status_code}: {resp.text}")

        return resp.json()  # success

    raise RuntimeError(f"gave up after {MAX_RETRIES} attempts: {url}")


def backoff(attempt: int) -> float:
    """Exponential backoff with jitter: ~1s, 2s, 4s, ... plus randomness."""
    base = 2 ** (attempt - 1)
    return base + random.uniform(0, 0.5)


def fetch_all_items() -> list:
    """Follow pagination until every item is fetched."""
    all_items = []
    offset = 0
    while True:
        data = get_with_retry(f"{BASE_URL}/items",
                              {"offset": offset, "limit": PAGE_LIMIT})
        page = data["items"]
        all_items.extend(page)
        log.info("fetched %d items at offset %d (running total %d)",
                 len(page), offset, len(all_items))
        if len(page) < PAGE_LIMIT:
            break  # last page reached
        offset += PAGE_LIMIT
    return all_items


if __name__ == "__main__":
    items = fetch_all_items()
    print(f"DONE: fetched {len(items)} items total")
```

---

## Step 4: Run the client against the flaky server

Still on the **lab server**, as **ec2-user**, in the activated environment:

```bash
python resilient_client.py
```

Because the server fails randomly, you will see warnings for 429s and timeouts, then success. Run it a few times to see different failure patterns - it should always finish with all 25 items.

Expected output (yours will differ - the warnings depend on the random rolls):

```
WARNING 429 rate limited on attempt 1, waiting 1.0s
INFO fetched 10 items at offset 0 (running total 10)
WARNING timeout on attempt 1, backing off 1.2s
INFO fetched 10 items at offset 10 (running total 20)
INFO fetched 5 items at offset 20 (running total 25)
DONE: fetched 25 items total
```

Key things to notice:

- **Timeouts and 429s did not crash the client** - it backed off and retried.
- **It fetched all 25 items** across three pages, not just the first 10.
- The final count is always 25 no matter how the failures fell. That is resilience.

---

## Step 5: Add a webhook receiver to Project 1

Now the reverse direction: receive events pushed to you. You add a `POST /webhook` endpoint that acknowledges fast and is safe to receive the same event twice (idempotent).

Still on the **lab server**, as **ec2-user**, create a separate small app so you do not disturb `app.py`:

```bash
vi webhook.py
```

Press `i`, type the following, then `Esc` and `:wq`:

```python
"""A minimal, idempotent webhook receiver.

Acknowledges fast with 200 and de-duplicates repeated event ids, because
senders retry and you WILL receive the same event more than once.
"""
import logging

from fastapi import FastAPI, Request

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("webhook")

app = FastAPI()
seen_event_ids: set[str] = set()  # in-memory dedupe (a real system uses a DB)


@app.post("/webhook")
async def webhook(request: Request) -> dict:
    event = await request.json()
    event_id = event.get("id")

    if event_id in seen_event_ids:
        log.info("duplicate event %s ignored (idempotent)", event_id)
        return {"status": "duplicate_ignored"}

    seen_event_ids.add(event_id)
    log.info("processed event %s type=%s", event_id, event.get("type"))
    return {"status": "accepted"}
```

Start it on port 8200:

```bash
nohup uvicorn webhook:app --host 127.0.0.1 --port 8200 > webhook.log 2>&1 &
```

Give it two seconds.

---

## Step 6: Send the same webhook twice and prove idempotency

Send an event, then send the **exact same event id again**. The first is accepted; the second is ignored.

Still on the **lab server**, as **ec2-user**:

```bash
curl -s -X POST http://127.0.0.1:8200/webhook \
  -H "Content-Type: application/json" \
  -d '{"id": "evt_123", "type": "ticket.created"}'
```

Expected output:

```
{"status":"accepted"}
```

Now send it again (a sender retry):

```bash
curl -s -X POST http://127.0.0.1:8200/webhook \
  -H "Content-Type: application/json" \
  -d '{"id": "evt_123", "type": "ticket.created"}'
```

Expected output:

```
{"status":"duplicate_ignored"}
```

`-X POST` sets the method, `-H` sets the JSON content type, `-d` sends the JSON body. The second identical event was ignored - your receiver is idempotent, so a sender's retry cannot double-process an event.

---

## Step 7: Clean up

Stop the two background servers you started.

Still on the **lab server**, as **ec2-user**:

```bash
pkill -f "flaky_server:app"
```

```bash
pkill -f "webhook:app"
```

```bash
deactivate
```

---

## What you just built

- A **resilient client** with a **timeout** (never hangs forever), **retries with exponential backoff and jitter** for transient failures (429, 5xx, timeouts), and correct handling that **fails fast on 4xx** because retrying a bad request is pointless.
- **Pagination** handling that fetches **every** page, not just the first.
- A **webhook receiver** that acknowledges fast and is **idempotent**, so a sender's inevitable retry does not process the same event twice.

These four patterns - timeout, retry/backoff, pagination, idempotency - are the difference between an API integration that works in a demo and one that survives production. You harden this exact client further in the `api-429-timeout` SURVIVE scenario.

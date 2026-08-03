# SURVIVE Runbook: API Client Dies on 429s and Timeouts

**Scenario:** your client calls an external API that is rate-limited and occasionally hangs - exactly like a real LLM provider or data source under load. The naive client has no timeout (so it can freeze forever) and no retry (so it dies on the first `429`). You must make it survive a flaky endpoint.

**Your job:** add a **timeout** and **retry with exponential backoff** that honors `Retry-After`, so transient `429`s and timeouts are handled instead of fatal. You are on the **lab server**, as **ec2-user**, with Project 1 in `~/project1`. The scenario started a flaky API on port 8300.

The rule you are enforcing: **every network call needs a timeout and a retry strategy.** Transient failures (429, 5xx, timeouts) are normal - a resilient client backs off and tries again; it never hangs and never gives up on the first blip.

---

## Step 1: Reproduce the failure

On your **lab server**, as **ec2-user**:

```bash
cd ~/project1
```

Run the naive client a few times. It will either hang for about 8 seconds (a timeout that never times out) or raise on a `429`:

```bash
.venv/bin/python fragile_client.py
```

Expected output (one of two failures - run it again to see the other):

```
requests.exceptions.HTTPError: 429 Client Error: Too Many Requests for url: http://127.0.0.1:8300/data
```

or it simply hangs for ~8 seconds before returning. Both are unacceptable in production: one crashes on a normal rate-limit response, the other can freeze the whole program on a single slow call.

---

## Step 2: Understand the two defects

- **No timeout.** `requests.get(url)` with no `timeout=` will wait indefinitely for a response. When the server hangs, so does your program - forever. One stuck upstream call takes down your service.
- **No retry.** `429 Too Many Requests` is a transient, expected response that means "wait and try again." Calling `raise_for_status()` turns it into a fatal error on the very first occurrence, instead of backing off and retrying.

Both are fixed with a small retry loop that sets a timeout and treats `429`/timeout as retryable.

---

## Step 3: Rewrite the client with a timeout and backoff

Open the client with `vi`:

```bash
vi fragile_client.py
```

Press `i`, replace the whole file (in command mode you can `:%d` first) with this resilient version:

```python
"""Resilient client: timeout + retry with exponential backoff.

Survives a flaky endpoint that returns 429s and hangs. Transient failures
(429, 5xx, timeouts) are retried with backoff; a hang can never freeze us.
"""
import logging
import random
import time

import requests

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("client")

BASE_URL = "http://127.0.0.1:8300"
TIMEOUT = 3        # seconds - never wait forever
MAX_RETRIES = 6    # give up cleanly after this many


def backoff(attempt: int) -> float:
    """Exponential backoff with jitter: ~1s, 2s, 4s ... plus randomness."""
    return 2 ** (attempt - 1) + random.uniform(0, 0.5)


def fetch() -> dict:
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            resp = requests.get(f"{BASE_URL}/data", timeout=TIMEOUT)
        except requests.exceptions.Timeout:
            wait = backoff(attempt)
            log.warning("timeout on attempt %d, backing off %.1fs", attempt, wait)
            time.sleep(wait)
            continue

        if resp.status_code == 429:
            # honor the server's Retry-After if it sent one, else back off
            wait = float(resp.headers.get("Retry-After", backoff(attempt)))
            log.warning("429 on attempt %d, waiting %.1fs", attempt, wait)
            time.sleep(wait)
            continue

        if 500 <= resp.status_code < 600:
            wait = backoff(attempt)
            log.warning("server error %d on attempt %d, backing off %.1fs",
                        resp.status_code, attempt, wait)
            time.sleep(wait)
            continue

        resp.raise_for_status()  # any other 4xx: fail fast, retry won't help
        return resp.json()       # success

    raise RuntimeError(f"gave up after {MAX_RETRIES} attempts")


if __name__ == "__main__":
    print(fetch())
```

Press `Esc` and type `:wq` to save and quit.

What changed:

- `timeout=TIMEOUT` on the request - a hang now raises `Timeout` after 3s instead of freezing.
- A retry loop that treats `429`, `5xx`, and timeouts as retryable, waiting with **exponential backoff and jitter** between attempts.
- `429` honors the server's `Retry-After` header when present - the polite, correct behavior.
- Non-retryable `4xx` still fails fast (retrying a bad request is pointless).
- A hard cap (`MAX_RETRIES`) so it gives up cleanly instead of looping forever.

---

## Step 4: Run the resilient client

Still on the **lab server**, as **ec2-user**:

```bash
.venv/bin/python fragile_client.py
```

Because the endpoint is flaky, you will see warnings for 429s and timeouts, then success. Run it several times - it should always succeed within the retry budget.

Expected output (yours will differ - the warnings depend on the random failures):

```
WARNING 429 on attempt 1, waiting 1.0s
WARNING timeout on attempt 2, backing off 2.3s
INFO ...
{'ok': True, 'value': 42}
```

The client absorbed a `429` and a timeout, backed off between attempts, and still returned `{'ok': True, 'value': 42}`. It survived the flaky endpoint.

---

## Step 5: Confirm it never hangs

The old client could freeze for 8+ seconds. The new one times out at 3s per attempt and retries, so no single call blocks it. You can see per-attempt timing in the warnings - each timeout is capped at `TIMEOUT` seconds, never the server's full 8-second hang.

---

## What you learned

- **Always set a timeout.** A network call with no timeout can freeze your entire program on one slow upstream. `timeout=3` turns an infinite hang into a retryable event.
- **Retry transient failures with backoff.** `429`, `5xx`, and timeouts are normal - back off (exponential, with jitter) and try again instead of crashing on the first one.
- **Honor `Retry-After`.** When the server tells you how long to wait, wait that long - it is the correct, rate-limit-friendly behavior.
- **Fail fast on non-transient errors and cap retries.** Do not retry a `400`/`401`, and never loop forever.

## Prevention

- Wrap all outbound calls in a shared resilient client (or a library like `tenacity`) so every call gets timeout + backoff by default.
- Add jitter so many clients do not retry in lockstep and stampede a recovering server.
- Track retry and failure rates - a rising retry rate is an early warning that an upstream is degrading.
- Clean up: `pkill -f "flaky_api:app"` stops the test server when you are done.

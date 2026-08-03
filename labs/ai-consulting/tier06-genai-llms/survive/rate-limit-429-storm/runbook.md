# SURVIVE: Rate Limit 429 Storm

Your client sends a burst of requests as fast as it can. The provider is rate
limited - it allows only so many requests per second and returns HTTP 429 (Too
Many Requests) for the rest. Because the client has no backoff and no batching,
it trips the limit almost immediately and crashes on the first 429. The feature
falls over under any real load.

In this runbook you will detect the 429 storm, diagnose the missing resilience,
and fix it by adding exponential backoff (honoring Retry-After) and batching so
every request eventually succeeds.

**No real API and no API key are involved.** A LOCAL mock LLM server enforces a
fake rate limit and returns real 429s with a Retry-After header, so you test the
resilience LOGIC (backoff + batching) for free. The mechanics map one-to-one to a
real provider (Concepts 6.4).

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

Run the injector to see the storm.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It builds the working directory, starts the rate-limiting
mock server, and runs the broken client, which fires requests too fast.

Expected output (yours will differ):

```
==> Creating working directory: /home/ec2-user/survive-rate-limit-429-storm
...
==> Running the broken client.py so you can see it fail under the 429 storm:
-------------------------------------------------------------
Traceback (most recent call last):
  ...
urllib.error.HTTPError: HTTP Error 429: Too Many Requests
-------------------------------------------------------------

The client fired requests too fast, tripped the rate limit, and crashed on
a 429 (HTTP Error 429: Too Many Requests). No backoff and no batching means
a rate limit is fatal. Open runbook.md and add backoff + batching.
```

`HTTP Error 429: Too Many Requests` after only a few calls is the storm. The run
died with most requests never sent.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-rate-limit-429-storm
```

Look at how the client makes calls.

Still on your lab server, as ec2-user:

```
grep -n "def call_model\|def run\|backoff\|Retry-After\|sleep" client.py
```

`grep -n` prints matching lines with line numbers.

Expected output (yours will differ):

```
17:def call_model(prompt: str) -> dict:
28:def run():
```

Notice what is NOT there: no `backoff`, no handling of `Retry-After`, no `sleep`,
no batching. The client calls `urllib.request.urlopen` once per request with no
retry, so the first 429 raises an `HTTPError` and kills the whole run.

The real cause is not "the provider rate-limits us" - every provider does
(Concepts 6.4, rate limits). The real cause is that the client has **no backoff
and no pacing**: it neither retries a 429 after waiting, nor spaces requests out
to stay under the limit.

Confirm the server does send a Retry-After hint we can honor:

Still on your lab server, as ec2-user, hammer it a few times to trip the limit:

```
for i in $(seq 1 8); do curl -s -o /dev/null -w "%{http_code} " -X POST http://127.0.0.1:8974/ -d '{}'; done; echo
```

`for ... seq 1 8` loops 8 times; `curl -w "%{http_code}"` prints just the HTTP
status of each call.

Expected output (yours will differ):

```
200 200 200 200 200 429 429 429
```

The first few succeed, then the limit trips and the rest are 429. That is exactly
what your client must survive.

---

## Layer 3: Fix and verify

Fix the client to (a) retry a 429 with exponential backoff and jitter, honoring
Retry-After, and (b) batch/pace the requests so it does not fire the whole burst
at once.

Open the file.

Still on your lab server, as ec2-user:

```
vi client.py
```

First, replace `call_model` with a version that retries on 429 using exponential
backoff. Press `i` and change the function to:

```python
import random
import time
import urllib.error


def call_model(prompt: str, max_retries: int = 8) -> dict:
    """Call the mock LLM, retrying 429s with exponential backoff + jitter.

    On a 429, wait the server's Retry-After if given, else an exponentially
    growing delay (1s, 2s, 4s, ...) plus a little random jitter so many clients
    do not retry in lockstep (Concepts 6.4). Give up after max_retries.
    """
    for attempt in range(max_retries):
        req = urllib.request.Request(
            f"http://127.0.0.1:{PORT}/",
            data=json.dumps({"prompt": prompt}).encode(),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=3) as resp:
                return json.loads(resp.read())
        except urllib.error.HTTPError as exc:
            if exc.code != 429:
                raise  # only 429 is retryable here
            retry_after = exc.headers.get("Retry-After")
            if retry_after is not None:
                delay = float(retry_after)
            else:
                delay = 2 ** attempt
            delay += random.uniform(0, 0.25)  # jitter
            print(f"[warn] 429 on '{prompt}', backing off {delay:.2f}s "
                  f"(attempt {attempt + 1}/{max_retries})")
            time.sleep(delay)
    raise RuntimeError(f"gave up after {max_retries} retries on '{prompt}'")
```

Next, replace `run` with a version that batches/paces the requests so it does not
fire all 30 at once. Still in insert mode, change `run` to:

```python
def run():
    succeeded = 0
    batch_size = 4          # send a small batch, then pause (batching)
    pause_between = 1.1     # seconds - stay under the server's per-second limit
    for i in range(TOTAL_REQUESTS):
        call_model(f"request {i}")   # backoff inside handles any 429
        succeeded += 1
        # After each batch, pause so we respect the rate window (batching/pacing).
        if (i + 1) % batch_size == 0:
            time.sleep(pause_between)
    print(f"DONE succeeded={succeeded} total={TOTAL_REQUESTS}")
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit.

Now run it again.

Still on your lab server, as ec2-user:

```
python client.py
```

Expected output (yours will differ - you may see a few backoff warnings):

```
[warn] 429 on 'request 5', backing off 0.63s (attempt 1/8)
[warn] 429 on 'request 9', backing off 0.41s (attempt 1/8)
DONE succeeded=30 total=30
```

Signs of a healthy, rate-limit-resilient client:

- It no longer crashes on a 429 - it backs off and retries.
- It honors the server's Retry-After and adds jitter (Concepts 6.4).
- It batches/paces the burst so it mostly stays under the limit in the first place.
- ALL 30 requests eventually succeed (`succeeded=30 total=30`).

You have turned a fatal 429 storm into a run that survives and completes. That is
the survive.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It reruns your `client.py` against the rate-limiting
server, checks it exits cleanly, and confirms the DONE line shows all requests
succeeded.

Expected output (yours will differ):

```
Running your client.py against the rate-limiting server ...
DONE line: DONE succeeded=30 total=30
PASS: survived the 429 storm - all 30 requests eventually succeeded via backoff + batching.
```

If you see `PASS`, you are done.

---

## Takeaways

- Every provider rate-limits. A 429 is normal traffic control, not a bug - your
  client must expect and survive it.
- Exponential backoff + jitter is the correct response to a 429: wait, retry, and
  do not all retry in lockstep. Honor Retry-After when the server sends it.
- Batching/pacing keeps you under the limit in the first place, so you hit fewer
  429s at all.
- Cap the retries so you fail cleanly instead of retrying forever.
- You proved all of this against a LOCAL mock server that enforces a real rate
  limit - no real API and no key - so the resilience logic is fully testable for
  free.

Prof. Happy (SUTA Labs)

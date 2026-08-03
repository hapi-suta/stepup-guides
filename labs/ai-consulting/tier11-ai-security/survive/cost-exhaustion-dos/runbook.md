# SURVIVE Runbook: Cost-Exhaustion Denial of Service - Rate-Limit and Cap

**Scenario:** every call to your assistant costs money (tokens) and compute. An attacker discovers your `/ask` endpoint has no rate limit and no budget cap, so they fire a flood of large requests. Your bill climbs without bound and real users get starved. This is **unbounded consumption** (OWASP GenAI LLM10) - a denial of service that hits your wallet as much as your uptime.

**Your job:** add a **rate limit** and a **budget cap**, then prove they hold under a flood while normal use still works. You are on the **lab server** (CentOS Stream 9), as **ec2-user**. The scenario built a self-contained assistant in `~/t11-cost-dos` with a simulated spend meter.

The rule you are enforcing: **every expensive endpoint needs a rate limit and a spend cap.** Cost is a resource; unbounded cost is an outage.

---

## Step 1: See the runaway spend

On your **lab server**, as **ec2-user**:

```bash
cd ~/t11-cost-dos
```

Run the flood tool. It sends 200 large requests and prints the final spend:

```bash
.venv/bin/python flood.py
```

Expected output (yours will differ):

```
accepted=200 blocked=0
final spend: {'usd': 0.378}
```

All 200 requests were accepted, none blocked, and the meter climbed unchecked from one attacker in seconds. This is simulated pricing on a tiny run - at real token prices and real volume it is a large, fast bill and a genuine outage for paying users.

---

## Step 2: Understand the defect

Open the app:

```bash
cat app.py
```

The `/ask` handler adds cost and answers, with nothing in between:

```python
SPEND["usd"] += est_cost(body.question)
return {...}
```

There is no throttle on how many requests a caller can make, and no ceiling on total spend. Both are needed: a rate limit stops the flood's speed; a budget cap stops the total damage even from a slow, sustained abuser.

---

## Step 3: Add a per-minute rate limit and spend cap

You will enforce, per rolling one-minute window: at most `MAX_CALLS` requests, and at most `MAX_SPEND` dollars. Both reset each minute, so legitimate use continues while abuse is contained. Edit the app:

```bash
vi app.py
```

Press `i`. Add these limits near the top, just under `COST_PER_1K_TOKENS`:

```python
import time
from fastapi import HTTPException

MAX_CALLS = 30       # requests per minute
MAX_SPEND = 0.05     # dollars per minute
WINDOW = {"start": time.time(), "calls": 0, "usd": 0.0}


def _check_and_reset():
    now = time.time()
    if now - WINDOW["start"] >= 60:            # new minute -> reset the window
        WINDOW.update(start=now, calls=0, usd=0.0)
```

Now replace the `ask` handler with a version that enforces both limits before spending:

```python
@app.post("/ask")
def ask(body: Ask):
    _check_and_reset()

    # Rate limit: too many calls this minute -> 429.
    if WINDOW["calls"] >= MAX_CALLS:
        raise HTTPException(status_code=429, detail="rate limit exceeded")

    cost = est_cost(body.question)
    # Budget cap: this call would blow the minute's budget -> 402.
    if WINDOW["usd"] + cost > MAX_SPEND:
        raise HTTPException(status_code=402, detail="budget cap reached")

    WINDOW["calls"] += 1
    WINDOW["usd"] += cost
    SPEND["usd"] += cost
    return {"answer": llm.complete(SYSTEM, body.question),
            "spend_usd": round(SPEND["usd"], 4)}
```

Press `Esc`, type `:wq`, press Enter.

Why two limits: the **rate limit** (`429`) caps request velocity so a flood cannot sail through; the **budget cap** (`402`) caps dollars so even large or slow requests cannot exceed your spend ceiling. Both reset each minute so real users are never permanently locked out.

---

## Step 4: Restart the assistant

On your **lab server**, as **ec2-user**, in `~/t11-cost-dos`:

```bash
pkill -f "app:app" || true
```

```bash
nohup .venv/bin/uvicorn app:app --host 127.0.0.1 --port 8000 > server.log 2>&1 &
```

```bash
sleep 4
```

---

## Step 5: Prove the limits hold

Run the flood again:

```bash
.venv/bin/python flood.py
```

Expected output (yours will differ):

```
accepted=26 blocked=174
final spend: {'usd': 0.0491}
```

Most requests are now **blocked** (the `429`/`402` responses), and total spend stops just under the `$0.05` minute cap instead of running unchecked. The flood is contained.

Confirm a normal single request still works (wait for the minute window to reset first):

```bash
sleep 61
```

```bash
curl -s -X POST http://127.0.0.1:8000/ask -H 'Content-Type: application/json' -d '{"question":"hi"}'
```

Expected output (yours will differ):

```
{"answer":"Answer (mock).","spend_usd":0.0489}
```

A real user is served normally. Now run the validator (it takes about a minute because it waits for the window to reset):

```bash
bash validate.sh
```

Expected output (yours will differ):

```
OK: rate limit and budget cap are present in the code
OK: the flood was throttled/capped (187 requests blocked)
OK: spend is bounded ($0.0489, cap held)
OK: a normal request still succeeds
PASS: cost-exhaustion DoS is rate-limited and budget-capped.
```

---

## What you learned

- **Cost is a resource that must be bounded.** An LLM endpoint with no limits is a denial-of-service and a runaway bill waiting to happen.
- **Rate limit and budget cap are different controls.** One bounds request velocity (`429`), the other bounds dollars (`402`); you need both.
- **Windowed limits contain abuse without locking out real users** - they reset each minute.
- **Test the control, not just the intent.** You proved it by flooding and watching requests get blocked and spend stop at the cap.

## Prevention

- Enforce per-user and per-key rate limits and daily/monthly budget caps at the gateway, not just per process.
- Cap input and output token counts per request so one giant prompt cannot be arbitrarily expensive.
- Alert when spend crosses a threshold (say 50 percent of budget) so you react before the cap.
- Require authentication so limits attach to an identity, and you can block a specific abuser.

Prof. Happy (SUTA Labs)

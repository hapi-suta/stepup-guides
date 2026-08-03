# SURVIVE: Cost runaway - cap the 2am blowout

A retry loop went wrong at 2am and hammered your LLM API thousands of times.
Every call is billed per token, so a bug that would be harmless in a normal web
app is a five-figure surprise in an LLM app. Your serving path had no budget cap,
so nothing stopped it. This is the cost blowout every LLMOps engineer must be
able to contain (Concepts 10.3, cost control).

Your job is to confirm the blowout with the cost monitor, add a budget guard to
the serving path that refuses calls once the daily budget is spent, prove the
guard holds under the same runaway load, and document the finding. Everything
runs offline with a mock LLM and simulated per-token cost.

Before you start, run the injector if you have not already:

```
bash inject.sh
```

That builds `~/survive-cost-runaway`, unleashes a 5000-call runaway loop against
the unguarded serving path, and runs the cost monitor so you can see the
blowout.

---

## Layer 1: Detect

On your lab server, as ec2-user, move into the working directory. `cd` changes
your current directory so the commands find the files.

```
cd ~/survive-cost-runaway
```

Activate the virtual environment. `source` loads the venv.

```
source .venv/bin/activate
```

Run the cost monitor. It sums the cost of every logged call and compares it to
the daily budget. `--budget 1.00` sets the daily budget to one dollar.

```
python cost_alert.py --budget 1.00
```

Expected output (yours will differ):

```
requests:   5000
total_cost: $3.3
budget:     $1.0
ALERT: cost $3.3 exceeds daily budget $1.0
RESULT: BUDGET BREACHED
```

Spend is more than 3x the daily budget from 5000 calls. That is the blowout.
Note the monitor tells you it happened, but nothing stopped it - you need a
control in the serving path, not just an alert after the fact.

---

## Layer 2: Diagnose

Look at why nothing stopped the spend. Read the serving path. `cat` prints the
file so you can see there is no budget check.

```
cat serve_call.py
```

Expected output (truncated - yours will differ):

```
"""Unguarded LLM serving path. Every call is billed and logged. No budget cap.
...
def serve(question):
    answer = complete(question)
    ...
```

`serve()` calls the model and logs the cost, but never asks "have we already
spent the budget?" That is the gap. Any loop, bug, or abusive client can spend
without limit. The fix is a guard that checks accumulated spend before every
call and refuses once the budget is reached.

---

## Layer 3: Correct and validate

Write a guarded serving path. It sums today's spend from the metrics log and
refuses the call once spend reaches the daily budget - so a runaway is capped
instead of unlimited. Open a new file with vi.

```
vi guarded_serve.py
```

In vi, press `i` to enter insert mode, type the file below, then press `Esc` and
type `:wq` and press Enter to save and quit.

```python
"""Guarded LLM serving path: refuses calls once the daily budget is spent.

Before serving, it sums today's cost from llm_metrics.jsonl. If spend is at or
over DAILY_BUDGET, it refuses the call (returns a BUDGET message and does NOT
bill). This caps a runaway loop instead of letting it blow out the bill.
"""
import json
from datetime import datetime, timezone
from pathlib import Path

from llm_client import complete

LOG = "llm_metrics.jsonl"
DAILY_BUDGET = 1.00
PRICE_PER_1K_INPUT = 0.003
PRICE_PER_1K_OUTPUT = 0.015


def count_tokens(text):
    return max(1, len(text) // 4)


def spent_today():
    path = Path(LOG)
    if not path.exists():
        return 0.0
    total = 0.0
    for line in path.read_text().splitlines():
        if not line.strip():
            continue
        total += json.loads(line).get("cost_usd", 0.0)
    return total


def serve(question):
    # The guard: stop before spending past the budget.
    if spent_today() >= DAILY_BUDGET:
        return "BUDGET: daily budget reached, call refused"
    answer = complete(question)
    in_tok = count_tokens(question)
    out_tok = count_tokens(answer)
    cost = round(in_tok / 1000 * PRICE_PER_1K_INPUT
                 + out_tok / 1000 * PRICE_PER_1K_OUTPUT, 6)
    with open(LOG, "a") as fh:
        fh.write(json.dumps({
            "ts": datetime.now(timezone.utc).isoformat(),
            "input_tokens": in_tok, "output_tokens": out_tok,
            "cost_usd": cost, "error": False,
        }) + "\n")
    return answer
```

Press `Esc`, type `:wq`, press Enter.

Now prove the guard holds. First clear the old runaway log so you start from a
clean day. `rm -f` deletes the file without complaining if it is missing.

```
rm -f llm_metrics.jsonl
```

Run the same runaway loop, but this time against your guarded path. `runaway.py`
takes the module name and a call count.

```
python runaway.py guarded_serve 5000
```

Expected output (yours will differ):

```
attempted: 5000  served: 1516  refused: 3484
```

The guard served calls until the budget was spent, then refused the rest. The
loop attempted 5000 calls but only about 1500 were billed - the guard stopped
the blowout. Confirm the spend is capped by running the monitor. We give it a
tiny bit of slack over the budget (`--budget 1.05`) because one in-flight call
can tip just over before the guard trips.

```
python cost_alert.py --budget 1.05
```

Expected output (yours will differ):

```
requests:   1516
total_cost: $1.0006
budget:     $1.05
RESULT: within budget
```

Spend held at about one dollar instead of blowing past three. The guard works.
Now document the finding. Open the file with vi.

```
vi cost_findings.md
```

Press `i`, type your findings, then `Esc` and `:wq`. Make sure you mention the
budget/cap, describe the runaway, and name a control (rate limit, token
counting, caching, or the guard). Something like:

```markdown
# Cost runaway findings

## Detection
A runaway retry loop hammered the serving path 5000 times overnight. The cost
monitor showed $3.30 spent against a $1.00 daily budget - a 3x blowout with no
alarm, because the serving path had no budget cap.

## Cause
The serving path had no budget guard and no rate limit. Any loop or bug could
spend without limit. Cost is a first-class operational risk for an LLM app.

## Fix
Added guarded_serve.py: before each call it sums today's spend and refuses the
call once the daily budget is reached, so a runaway is capped instead of
unlimited. Under the same 5000-call load it served ~1516 and refused the rest,
holding spend at ~$1.00.

## Prevention
Budget cap plus a per-client rate limit, token counting on every request, and
caching for repeated prompts. Wire a threshold alert so spend crossing the
budget pages someone.
```

Now validate your work. This runs the checker, which re-runs the runaway against
your guard from a clean log, confirms the guard refuses calls and caps spend,
and checks your findings.

```
bash validate.sh
```

Expected output (yours will differ):

```
=== Validating SURVIVE: cost-runaway ===
OK:   guarded_serve.py exists
OK:   guarded_serve.py exposes a serve() function
OK:   guard refused 3484 calls once the budget was spent
OK:   post-runaway spend stayed within the $1.05 cap (guard held)
OK:   cost_findings.md exists
OK:   findings mention the budget/cap
OK:   findings describe the runaway
OK:   findings name a control (rate limit / token count / cache / guard)
RESULT: PASS - budget guard holds under the runaway, spend capped, documented
```

If you see RESULT: PASS you have survived the scenario.

---

## The lesson

An alert tells you the money is gone; a guard stops it from leaving. For an LLM
app, cost is not a report you read the next morning - it is a control you build
into the serving path. The layered defence is: token counting on every call so
you can measure spend, a budget cap that refuses calls past the limit, a rate
limit per client so one caller cannot dominate, and caching so repeated prompts
are free. The consulting takeaway: never ship an LLM feature without a spending
control, and prove it holds under load before launch, not after the bill
arrives.

Prof. Happy (SUTA Labs)

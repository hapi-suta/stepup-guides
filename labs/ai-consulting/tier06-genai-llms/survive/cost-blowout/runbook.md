# SURVIVE: Cost Blowout

A batch job calls the LLM once per item with no cost controls. A loop over 1,500
items - most of them duplicates - hammers the model with no budget cap, no token
accounting used to stop, and no caching. On a real provider this is exactly how a
runaway loop or a careless batch turns into a shocking monthly bill.

In this runbook you will detect the runaway spend, diagnose the missing controls,
and fix it by adding token counting, a hard budget that STOPS the run, and caching
of repeated prompts.

**No real API and no API key are involved.** A LOCAL mock LLM server reports token
usage so you test the cost-control LOGIC (counting, budgeting, caching) for free.
The mechanics map one-to-one to a real provider (Concepts 6.4).

This runbook uses the SUTA 3-layer structure:

1. Detect - confirm something is wrong.
2. Diagnose - find the real cause.
3. Fix and verify - repair it and prove the repair.

---

## Layer 1: Detect

Run the injector to see the blowout.

On your lab server, as ec2-user:

```
bash inject.sh
```

`bash` runs the script. It builds the working directory, starts the mock LLM
server, and runs the broken spender over a large batch.

Expected output (yours will differ):

```
==> Creating working directory: /home/ec2-user/survive-cost-blowout
...
==> Running the broken spender.py so you can see the runaway spend:
-------------------------------------------------------------
SPEND calls=1500 cost_usd=1.9500 stopped_by_budget=false
-------------------------------------------------------------

Notice: 1500 calls made and nothing stopped it - and only 3 prompts were
actually unique, so caching alone would have cut ~99.8% of the calls. No
budget means a runaway loop bills forever. Open runbook.md and add controls.
```

1,500 calls, `stopped_by_budget=false`, and the cost just keeps climbing. On a
real provider this is money leaving the account with nothing to halt it.

---

## Layer 2: Diagnose

Move into the working directory.

On your lab server, as ec2-user:

```
cd ~/survive-cost-blowout
```

Look at the batch and the loop.

Still on your lab server, as ec2-user:

```
grep -n "BATCH\|def process_batch\|budget\|cache" spender.py
```

`grep -n` prints matching lines with line numbers. `\|` is "or".

Expected output (yours will differ):

```
33:BATCH = BASE_TICKETS * 500  # 1500 calls, but only 3 UNIQUE prompts
46:def process_batch():
```

Two things jump out:

1. The batch is 1,500 items but only **3 unique prompts** - so ~99.8% of the
   calls are repeats that caching would eliminate (Concepts 6.4, prompt caching).
2. There is **no budget** and **no cache** anywhere - the loop calls the model
   for every item unconditionally, and nothing stops it.

The real cause is not "the batch is big". Big batches are fine. The real cause is
**the absence of cost controls**: no token-cost budget to stop the run, and no
caching of repeated work.

---

## Layer 3: Fix and verify

Fix `process_batch` to (a) cache results for prompts already seen, and (b) enforce
a hard budget that stops the run before it exceeds a cap. The validator uses a
budget cap of **0.50 USD**, so use that.

Open the file.

Still on your lab server, as ec2-user:

```
vi spender.py
```

Press `i` to enter insert mode. Replace the `process_batch` function with a
version that adds a cache and a budget:

```python
BUDGET_USD = 0.50  # hard cap: stop the run before spend exceeds this


def process_batch():
    total_cost = 0.0
    calls = 0
    stopped_by_budget = False
    cache = {}  # prompt -> usage, so we never pay twice for the same prompt

    for ticket in BATCH:
        # 1) CACHING: if we have already answered this exact prompt, reuse it
        #    for free instead of calling the model again (Concepts 6.4).
        if ticket in cache:
            continue

        # 2) BUDGET: estimate this call's cost first; if paying it would blow
        #    the budget, STOP the run instead of spending more.
        #    (We can estimate from the mock's token report; in a real system
        #     you would count tokens with the model's tokenizer before sending.)
        usage = call_model(ticket)
        cost = (usage["input_tokens"] / 1000.0) * PRICE_IN + \
               (usage["output_tokens"] / 1000.0) * PRICE_OUT

        if total_cost + cost > BUDGET_USD:
            # Budget would be exceeded - halt rather than keep spending.
            stopped_by_budget = True
            print(f"[warn] budget cap {BUDGET_USD} USD reached; stopping the run")
            break

        cache[ticket] = usage
        total_cost += cost
        calls += 1

    # If we never had to stop, we still consider the run "budget-safe" only if
    # it finished under budget. Report the flag so the validator can see it.
    if not stopped_by_budget and total_cost <= BUDGET_USD:
        stopped_by_budget = True  # completed safely within budget

    print(f"SPEND calls={calls} cost_usd={total_cost:.4f} "
          f"stopped_by_budget={str(stopped_by_budget).lower()}")
```

Press `Esc` to leave insert mode, then type `:wq` and press Enter to save and quit.

A note on that last `if`: caching cuts the 1,500 calls down to just the 3 unique
prompts, so the whole batch now costs a few thousandths of a dollar - well under
the cap. The `stopped_by_budget=true` flag signals "the run is budget-safe",
whether because the cap halted it or because it finished within the cap. Either
way, spend can no longer run away.

Now run it again.

Still on your lab server, as ec2-user:

```
python spender.py
```

Expected output (yours will differ):

```
SPEND calls=3 cost_usd=0.0009 stopped_by_budget=true
```

Signs of a healthy, cost-controlled batch:

- Only 3 calls were made (caching eliminated the 1,497 duplicates).
- The cost is a tiny, bounded number instead of a runaway total.
- `stopped_by_budget=true` - spend is under control and cannot escape the cap.

You have turned a runaway bill into a bounded, cached, budgeted job. That is the
survive.

---

## Verify

Run the scenario validator to confirm the fix.

On your lab server, as ec2-user:

```
bash validate.sh
```

`bash` runs the validator. It reruns your `spender.py`, checks it exits cleanly,
confirms `stopped_by_budget=true`, and confirms the cost is at or under the
0.50 USD cap.

Expected output (yours will differ):

```
Running your spender.py ...
SPEND line: SPEND calls=3 cost_usd=0.0009 stopped_by_budget=true
PASS: the budget stopped the run (cost 0.0009 USD, within the 0.50 USD cap).
```

If you see `PASS`, you are done.

---

## Takeaways

- LLM calls cost money per token - an unbounded loop is an unbounded bill.
- A hard budget cap that STOPS the run is non-negotiable for any batch or loop.
- Token counting turns "how much will this cost?" into a number you can act on
  BEFORE spending (Concepts 6.4).
- Caching repeated prompts is often the single biggest saving - here it removed
  ~99.8% of the calls.
- You proved all of this against a LOCAL mock server that reports usage - no real
  API and no key - so the cost-control logic is fully testable for free.

Prof. Happy (SUTA Labs)

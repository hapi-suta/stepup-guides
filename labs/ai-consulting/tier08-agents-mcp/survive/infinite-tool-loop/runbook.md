# SURVIVE Runbook: Infinite Tool-Call Loop Burns Budget

**Scenario:** the agent got stuck. A confused model keeps calling the same tool over and over and never produces a final answer. Because the agent's limits were set effectively to infinity, the loop had no termination condition and ran until a demo backstop we added just so it would not literally hang your terminal. In production this is a runaway agent quietly draining your token budget - not malicious, just unbounded.

**The rule you are enforcing:** every agent must have **termination conditions**. At minimum a **tool-call limit** and a **token budget**, both checked *inside the loop before each step*. An agent whose only stop condition is "the model decides to stop" is a bill waiting to happen.

You are on the **lab server** (CentOS Stream 9), as **ec2-user**, in the `survive/infinite-tool-loop` directory of the Tier 8 content.

---

## Step 1: See the runaway

`inject.sh` already ran the looping agent with limits turned off. Look at the result.

On the **lab server**, as **ec2-user**:

```bash
cat last_run.json
```

Expected output (the symptom - it only stopped at the demo's hard backstop, after a huge number of calls and tokens):

```
{"stopped": "hard_safety_stop", "tool_calls": 100000, "tokens_used": 2000000, "limits": {"MAX_TOOL_CALLS": 100000000, "MAX_TOKENS": 100000000}}
```

`"stopped": "hard_safety_stop"` means your real limits never fired - only the demo's emergency backstop did. `tool_calls: 100000` is the runaway. In real money, that is a large token bill for a task that never finished.

---

## Step 2: Confirm the validator fails

The validator re-runs the agent and checks that it stops for a *real* reason (your limit), not the demo backstop.

Still as **ec2-user**:

```bash
bash validate.sh
```

Expected output (it fails, because limits are still off):

```
FAIL: the loop only stopped at the demo backstop - your real limits never fired
```

---

## Step 3: Look at the current limits

The limits live in `limits.json`.

```bash
cat limits.json
```

Expected output (the problem - limits set so high they never bite):

```
{"MAX_TOOL_CALLS": 100000000, "MAX_TOKENS": 100000000}
```

A 100-million tool-call cap is no cap at all. Real termination conditions have to be small enough to actually fire.

---

## Step 4: Set sane limits

Open the limits file with vi:

```bash
vi limits.json
```

Press `i` to enter insert mode. Replace the contents with sane values:

```json
{"MAX_TOOL_CALLS": 8, "MAX_TOKENS": 20000}
```

Press `Esc`, then type `:wq` and press Enter to save and quit vi.

Eight tool calls is plenty for a health check; the budget of 20,000 tokens is a hard ceiling on cost. In a real agent these are constants (or config) that the loop checks before every step - exactly what the BUILD agent does with `MAX_TOOL_CALLS` and `MAX_TOKENS_BUDGET`.

---

## Step 5: Verify the fix

Re-run the validator:

```bash
bash validate.sh
```

Expected output (fixed - the loop now stops on your real limit, bounded and cheap):

```
OK: loop stopped on a real termination condition (max_tool_calls)
OK: run bounded to 8 tool calls (limit 8)
PASS: the runaway loop is now bounded by termination conditions.
```

The model is still confused - it still loops. You did not fix the model. You put a hard boundary around it, so a confused model costs 8 tool calls instead of infinity. That boundary is the point.

---

## What you learned

- **Termination conditions are mandatory, not optional.** Every agent loop needs a tool-call cap and a token budget, checked before each step.
- **"The model will stop when done" is not a limit.** A confused or hijacked model may never decide it is done. The harness must stop it.
- **Set limits that actually fire.** A cap set to infinity is theater. Pick a number a healthy run stays well under, so a runaway is caught early.
- **Limits bound cost, not correctness.** They do not make the model smarter; they make a broken run cheap and observable instead of catastrophic. Pair them with an audit trail so you can see *why* a run hit its limit and fix the underlying cause.

Prof. Happy (SUTA Labs)

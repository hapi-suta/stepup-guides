# SURVIVE Runbook: Tool Timeout / Error Mid-Plan - Recover Without Corrupting State

**Scenario:** partway through its plan, the agent called a tool that hung (a flaky dependency that never returned). The harness had no timeout and no error handling, so the failure propagated and **crashed the agent mid-run** - the report was never written and the run ended in a corrupt, half-finished state. The right behavior is to give every tool call a deadline, catch any failure, and hand it back to the model as an *observation* so the agent can recover with a fallback.

**The rule you are enforcing:** tools call real systems, and real systems hang and fail. Every tool call needs a **timeout**, and every tool failure must become an **observation** (`is_error: true`), never an unhandled exception. A crashed agent that corrupts its own state is worse than an agent that says "that call failed, here is what I did instead".

You are on the **lab server** (CentOS Stream 9), as **ec2-user**, in the `survive/tool-timeout-recovery` directory of the Tier 8 content.

---

## Step 1: See the crash

`inject.sh` already ran the agent while a tool hung, with tool calls unprotected. Look at the result.

On the **lab server**, as **ec2-user**:

```bash
cat last_run.json
```

Expected output (the symptom - the run crashed and no report was produced):

```
{"report_written": false, "crashed": true, "error": "tool hung and there was no error handling", "audit": []}
```

`"crashed": true` and `"report_written": false` mean the hung tool took down the whole run. The empty audit shows it died before recording anything useful.

---

## Step 2: Confirm the validator fails

The validator re-runs the agent and checks it recovers instead of crashing.

Still as **ec2-user**:

```bash
bash validate.sh
```

Expected output (it fails, because the harness is still unprotected):

```
FAIL: the run crashed on the tool timeout - state was corrupted mid-plan
```

---

## Step 3: Look at the current config

The harness behavior is driven by `config.json`.

```bash
cat config.json
```

Expected output (the problem - tool calls are unprotected):

```
{"PROTECT_TOOLS": false}
```

With `PROTECT_TOOLS` off, there is no per-call timeout and no catch around the tool - so a hang or an exception propagates and crashes the agent.

---

## Step 4: Apply the fix

Open the config with vi:

```bash
vi config.json
```

Press `i` to enter insert mode. Turn protection on:

```json
{"PROTECT_TOOLS": true}
```

Press `Esc`, then type `:wq` and press Enter to save and quit vi.

This flips the harness to the protected path: each tool call runs under a deadline (a 2-second timeout in the demo), and any timeout or exception is caught and returned to the model as an errored observation. In a real agent this is a wrapper around every tool call - the exact pattern the BUILD agent uses in its `run()` loop.

---

## Step 5: Verify the fix

Re-run the validator (it takes a couple of seconds because the flaky tool really does hang until the deadline):

```bash
bash validate.sh
```

Expected output (fixed - the agent catches the timeout, falls back, and finishes):

```
OK: the run did not crash
OK: the tool failure was caught and recorded as an observation
OK: the agent fell back to cached metrics and wrote the report
PASS: the agent recovered from the tool timeout without corrupting state.
```

The flaky tool still hangs - you did not fix the dependency. You made the agent survive it: the hung call becomes a logged error, the model sees it, switches to the cached fallback, and completes the report. That is graceful degradation.

---

## What you learned

- **Every tool call needs a timeout.** A wedged dependency must not freeze the whole agent. Give each call a deadline and move on when it is exceeded.
- **A tool failure is an observation, not a crash.** Catch it, mark it as an error, and feed it back to the model. The model can then try a fallback, adjust arguments, or report that it could not complete a step.
- **Protect state.** An unhandled exception mid-plan leaves the agent in a half-finished state no one designed. Catching failures keeps the transcript coherent so recovery is possible.
- **Graceful degradation beats hard failure.** "I used cached metrics because the live source timed out" is a good outcome. A crash with a half-written report is not.

Prof. Happy (SUTA Labs)

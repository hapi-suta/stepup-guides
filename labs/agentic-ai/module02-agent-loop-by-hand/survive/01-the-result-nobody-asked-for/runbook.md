# The Result Nobody Asked For

**Severity:** P2 - High (the agent cannot investigate anything)
**Expected Recovery Time:** 15-25 minutes
**Server:** ai-lab, user ec2-user

## Objective

Your DBA agent crashes on every question that needs a tool. A teammate changed `agent.py` last night. Find the broken line from the error message and your understanding of the tool-use round trip, fix it, and prove the agent works again with its own logs.

---

## Alert

```text
ALERT: the DBA agent crashes on every incident question
It prints its first tool call, then stops with an error
before any answer. A teammate 'tidied up' agent.py last
night.
```

Prof. Happy starts the scenario by running `inject.sh` on your server. Do not read `inject.sh` first.

---

## Key Concepts for Revision

- **The round trip has an id.** Every `tool_use` block the model sends carries an `id`. Every `tool_result` you send back must quote that exact `id` in `tool_use_id`. Otherwise the API cannot match result to request, and it rejects the whole call with `400 invalid_request_error`.
- **"Fails after the first tool call" narrows the search.** The model's request arrived (you saw `[turn 1] tool call: ...`), so the call that fails is the one that sends your tool results back. That code is Parts 3 and 4 of `agent.py` (Build 03).
- **The error names the message and the block.** `messages.2.content.0` means: in the list of messages, number 2 (counting from 0), content block 0. Count through your conversation: message 0 is your question, message 1 is the model's tool request, message 2 is your tool results.

---

## Investigate

Work on **ai-lab** as **ec2-user**, inside `~/agentic-ai`. Reproduce the symptom with a question that needs a tool:

```bash
python agent.py "How full is the root filesystem?"
```

Two things to notice: the `[turn 1] tool call:` line printed before the crash, and the last line of the error. Which status code, which message number, which block, and which field does it complain about?

---

## Find the root cause

Using the "messages.2" clue, decide which part of `agent.py` builds message 2. Then look at the line that builds each tool result:

```bash
grep -n tool_use_id agent.py
```

Compare that line with the table for Part 4 in Build 03. What should the value be, and what is it now?

Hint, if you are stuck after 15 minutes: the model sent an `id` like `toolu_018skJLggREAeDgk6S9phNr3`. Ask yourself what your code is sending back instead.

---

## Fix it

Edit `agent.py` with vi and change only the broken value back:

```bash
vi agent.py
```

In vi: type `/tool_use_id` and press Enter to jump to the line, fix the value, then `Esc` and `:wq`. Change nothing else.

Check that the file is still valid Python before you run it:

```bash
python -m py_compile agent.py
```

No output means it compiled.

---

## Prove it is fixed

Run the tool question again:

```bash
python agent.py "How full is the root filesystem?"
```

It should print a `[turn 1] tool call: disk_usage ...` line, an answer, and `stop reason: end_turn`. Then tell SutaAI it is fixed. Prof. Happy's `validate.sh` checks your logs, not the wording of the answer.

Expected validator result (yours will differ):

```text
== Validating: The Result Nobody Asked For ==
  PASS  tool results quote the model's id again
  PASS  agent.py is valid Python
  PASS  a tool-using run finishes (exit 0)
  PASS  the run made and logged at least one tool call
  PASS  the run was logged and ended with end_turn
== RESOLVED: 5 passed ==
```

---

## Post-incident questions

1. Which part of the error message pointed you to the cause?
2. The `[turn 1] tool call:` line printed before the crash. What does that prove worked, and what does it prove failed?
3. The broken value still started with `toolu_`, so it looked right at a glance. What check would have caught this before it reached production? (Think: a test that runs one tool-using question.)
4. Look at `logs/tool_calls.jsonl`. Did the broken runs log their tool calls before crashing? What does that tell you about the order of logging and sending in the loop?

# Build 03: The Agent Loop

**Objective:** Write a working agent in about 50 lines of plain Python, with no framework: it calls the model, runs every tool it asks for, sends the results back, and repeats until the model is done or a turn limit stops it. Every tool call and every run is logged.

**Estimated Time:** 35-45 minutes

**Prerequisites:**
- Builds 01 and 02 of this module finished

---

## The loop in plain English

1. Send the conversation and the tools to the model.
2. If it did not ask for a tool, it is finished: print the answer and stop.
3. Otherwise, run each tool it asked for, write each call to a log, and add the results to the conversation.
4. Go back to step 1, but never more than 6 times.

That is the whole idea. Frameworks add features on top, but this is the engine inside all of them.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Write the agent

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > agent.py <<'EOF'
import json
import os
import sys

import anthropic

from tools import RUN, TOOLS

MAX_TURNS = 6
PRICE_IN = 0.10 / 1_000_000
PRICE_OUT = 0.50 / 1_000_000

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]
system = ("You are a careful PostgreSQL DBA assistant. Look with the tools before you answer. "
          "The tools are read-only. Keep the final answer under 120 words.")
messages = [{"role": "user", "content": sys.argv[1]}]
tokens_in = tokens_out = 0
os.makedirs("logs", exist_ok=True)

for turn in range(1, MAX_TURNS + 1):
    response = client.messages.create(model=model, max_tokens=1500, output_config={"effort": "low"},
                                      system=system, tools=TOOLS, messages=messages)
    tokens_in += response.usage.input_tokens
    tokens_out += response.usage.output_tokens
    messages.append({"role": "assistant", "content": response.content})
    if response.stop_reason != "tool_use":
        break

    results = []
    for block in response.content:
        if block.type != "tool_use":
            continue
        print(f"[turn {turn}] tool call: {block.name} {json.dumps(block.input)}")
        try:
            output, is_error = str(RUN[block.name](**block.input)), False
        except (KeyError, TypeError, ValueError, OSError) as error:
            output, is_error = f"tool failed: {error!r}", True
        with open("logs/tool_calls.jsonl", "a") as log:
            log.write(json.dumps({"turn": turn, "tool": block.name, "input": block.input,
                                  "is_error": is_error}) + "\n")
        results.append({"type": "tool_result", "tool_use_id": block.id,
                        "content": output, "is_error": is_error})
    messages.append({"role": "user", "content": results})

answer = "".join(block.text for block in response.content if block.type == "text")
cost = tokens_in * PRICE_IN + tokens_out * PRICE_OUT
print()
print(answer)
print()
print(f"turns: {turn}   stop reason: {response.stop_reason}   cost: ${cost:.6f}")
with open("logs/runs.jsonl", "a") as log:
    log.write(json.dumps({"question": sys.argv[1], "turns": turn, "stop_reason": response.stop_reason,
                          "tokens_in": tokens_in, "tokens_out": tokens_out,
                          "cost_usd": round(cost, 8)}) + "\n")
EOF
```

Read it in five parts.

**Part 1: setup** (top of the file down to `os.makedirs`)

| Line(s) | What it does |
|---|---|
| `from tools import RUN, TOOLS` | The tool descriptions (for the model) and the name-to-function table (for your code) |
| `MAX_TURNS = 6` | **Guardrail.** The loop may call the model at most 6 times. Like `statement_timeout`: a runaway agent is stopped, not trusted |
| `system = (...)` | Standing instructions: look before answering, the tools are read-only, keep it short |
| `messages = [...]` | The conversation starts with your question |
| `tokens_in = tokens_out = 0` | Two running totals for the cost report at the end |

**Part 2: call the model** (the start of the `for` loop)

| Line(s) | What it does |
|---|---|
| `for turn in range(1, MAX_TURNS + 1):` | Repeat with `turn` = 1, 2, ... 6. `range(1, 7)` stops before 7 |
| `response = client.messages.create(...)` | One call, exactly like Module 1, plus `tools=TOOLS` |
| `tokens_in += ...`, `tokens_out += ...` | Add this call's tokens to the totals. `+=` means "add to" |
| `messages.append({"role": "assistant", "content": response.content})` | Add the model's whole reply (text and tool requests) to the conversation, unchanged |
| `if response.stop_reason != "tool_use": break` | If it did not ask for a tool, the job is done. `break` leaves the loop |

**Part 3: run the tools it asked for**

| Line(s) | What it does |
|---|---|
| `results = []` | Collect every tool result from this turn |
| `if block.type != "tool_use": continue` | Skip text blocks. `continue` jumps to the next block |
| `print(f"[turn {turn}] tool call: ...")` | Show on screen what the agent is doing, live |
| `RUN[block.name](**block.input)` | Find the function by name and call it with the model's inputs. `**` unpacks `{"path": "/"}` into `path="/"` |
| `except (KeyError, TypeError, ValueError, OSError) as error:` | **Guardrail.** If the tool name is unknown (`KeyError`), the inputs are wrong (`TypeError`, `ValueError`) or the file system refuses (`OSError`), do not crash: turn the error into a result the model can read |
| `is_error` | `True` when the tool failed. The model is told, so it can try something else |
| `log.write(...)` to `logs/tool_calls.jsonl` | **Audit trail.** One line per tool call: turn, tool, inputs, success or failure |

**Part 4: send the results back**

| Line(s) | What it does |
|---|---|
| `{"type": "tool_result", "tool_use_id": block.id, ...}` | The answer to one request. `tool_use_id` must be the **same id** the model sent, or the API rejects the call |
| `messages.append({"role": "user", "content": results})` | All results from this turn go back in one message, as if you were replying to the model |

**Part 5: report** (after the loop)

| Line(s) | What it does |
|---|---|
| `answer = ...` | The final text from the last reply |
| `cost = ...` | Total tokens times prices, for the whole run |
| `print(f"turns: ...")` | How many turns it took, why it stopped, what it cost |
| `log.write(...)` to `logs/runs.jsonl` | One line per run: question, turns, stop reason, tokens, cost |

---

## Step 3 - Count the lines

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
wc -l agent.py
```

Expected output (yours will differ):

```text
55 agent.py
```

A complete agent in 55 lines, blank lines included.

---

## Step 4 - Give the agent a real incident

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python agent.py "Users say the app cannot connect. Check the log and the disk, then tell me the most likely cause."
```

Expected output (yours will differ):

```text
[turn 1] tool call: tail_log {"lines": 50}
[turn 1] tool call: disk_usage {"path": "/"}

**Most likely cause: connection slots are exhausted.** At 03:05:12 and 03:05:13 the server logged `FATAL: sorry, too many clients already`, which is the error the app would get when it tries to connect and no slots are free.

Other findings:
- **Disk is not the problem:** `/` is 15% used with 8 GB free.
- **Possible contributor:** `report_user` failed password authentication three times at 02:31. ...
...

turns: 2   stop reason: end_turn   cost: $0.000441
```

Read it from the top. In turn 1 the model asked for **two** tools at once (parallel tool calls), your code ran both, and in turn 2 it answered with `end_turn`. It found the connection-limit errors, ruled out disk space, and mentioned the other problems hidden in the log. The whole investigation cost less than a tenth of a cent.

---

## Step 5 - Read the tool-call audit log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat logs/tool_calls.jsonl
```

Expected output (yours will differ):

```text
{"turn": 1, "tool": "tail_log", "input": {"lines": 50}, "is_error": false}
{"turn": 1, "tool": "disk_usage", "input": {"path": "/"}, "is_error": false}
```

This is the evidence of what the agent actually did, separate from what it said. If an agent ever claims "I checked the disk" and this log has no `disk_usage` line, it did not check.

---

## Step 6 - Read the run log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat logs/runs.jsonl
```

Expected output (yours will differ):

```text
{"question": "Users say the app cannot connect. Check the log and the disk, then tell me the most likely cause.", "turns": 2, "stop_reason": "end_turn", "tokens_in": 1991, "tokens_out": 484, "cost_usd": 0.0004411}
```

One line per question asked: how many turns, why it stopped and what it cost. In Module 8 you grade agents automatically from logs like these.

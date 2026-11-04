# Build 02: Your First LLM Call

**Objective:** Write a 33-line Python program that sends one question to Claude through the SUTA proxy, prints the answer and the token counts, and records the call in a log file.

**Estimated Time:** 20-30 minutes

**Prerequisites:**
- Build 01 finished (your prompt starts with `(.venv)` after you log in)

---

## What a call looks like

An LLM call is a request and a response, like running one query against a remote database:

| Database | LLM call |
|---|---|
| You connect to a host | The library connects to `ANTHROPIC_BASE_URL` (the proxy) |
| You authenticate with a password | The library sends `ANTHROPIC_API_KEY` |
| You pick a database | You pick a **model** (`claude-haiku-5-5`) |
| You send SQL | You send **messages** (who said what) |
| You get rows back | You get **content blocks** back (the answer) |
| `EXPLAIN ANALYZE` shows what it cost | `usage` shows how many **tokens** went in and came out |

Tokens are the unit the model reads and writes. A token is roughly three quarters of an English word. You pay per token, separately for tokens in and tokens out.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Write the program

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > first_call.py <<'EOF'
import json
import os

import anthropic

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]

response = client.messages.create(
    model=model,
    max_tokens=400,
    output_config={"effort": "low"},
    messages=[
        {"role": "user", "content": "In two sentences, what does VACUUM do in PostgreSQL?"},
    ],
)

answer = "".join(block.text for block in response.content if block.type == "text")
print(answer)
print()
print("model:", response.model)
print("stop reason:", response.stop_reason)
print("tokens in:", response.usage.input_tokens, "tokens out:", response.usage.output_tokens)

os.makedirs("logs", exist_ok=True)
with open("logs/calls.jsonl", "a") as log:
    log.write(json.dumps({
        "script": "first_call.py",
        "model": response.model,
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
        "stop_reason": response.stop_reason,
    }) + "\n")
EOF
```

This writes the whole program into `first_call.py` in one paste (the same `cat > file <<'EOF'` trick from Build 01). Here is every line, top to bottom:

| Line(s) | What it does |
|---|---|
| `import json`, `import os` | Load two tools that come with Python: `json` writes structured log lines, `os` reads environment variables and makes folders |
| `import anthropic` | Load the Claude library you installed in Build 01 |
| `client = anthropic.Anthropic()` | Create a **client**: the connection object. With no arguments it reads `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` from your environment, so no key appears in the code |
| `model = os.environ["SUTA_LLM_MODEL"]` | Read the model name (`claude-haiku-5-5`) from the environment. `os.environ` is like `SHOW` for shell variables |
| `response = client.messages.create(` | Send one request and wait for the answer. Everything inside the brackets is a setting for this call |
| `model=model,` | Which model answers |
| `max_tokens=400,` | The most tokens the model may write back. A hard cap, like `statement_timeout` for output |
| `output_config={"effort": "low"},` | How hard the model thinks before answering. `low` is fast and cheap, right for simple questions |
| `messages=[ ... ],` | The conversation so far. Here it is one message with `"role": "user"` (you) and `"content"` (your question) |
| `answer = "".join(...)` | The reply comes back as a list of **blocks**. This keeps only the `text` blocks and joins them into one string |
| `print(answer)` and the next four `print` lines | Show the answer, the model that answered, why it stopped, and the token counts |
| `os.makedirs("logs", exist_ok=True)` | Make a `logs` folder if it does not exist yet |
| `with open("logs/calls.jsonl", "a") as log:` | Open the log file in **append** mode (`"a"`), so every run adds a line and nothing is overwritten |
| `log.write(json.dumps({...}) + "\n")` | Write one JSON line describing this call. One JSON object per line is called **JSON Lines** (`.jsonl`), and it is how most AI tools log |

Python cares about indentation: the lines inside `create(` and inside `with` are indented with spaces. Paste the block exactly as shown.

---

## Step 3 - Run it

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python first_call.py
```

`python` runs the program with the course's Python 3.12 (because `(.venv)` is active).

Expected output (yours will differ):

```text
VACUUM in PostgreSQL reclaims storage occupied by dead tuples left behind by UPDATE and DELETE operations, making that space reusable within the table (it generally doesn't return it to the operating system unless using VACUUM FULL). It also updates the visibility map and free space map, and it protects against transaction ID wraparound by freezing old row versions.

model: claude-haiku-5-5
stop reason: end_turn
tokens in: 31 tokens out: 120
```

Your answer will be worded differently every time. That is normal: the model writes a new answer on each call. The parts that stay the same are the shape: an answer, the model name, `stop reason: end_turn` (the model finished on its own) and two token counts.

---

## Step 4 - Read the log line it wrote

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat logs/calls.jsonl
```

`cat` prints a file.

Expected output (yours will differ):

```text
{"script": "first_call.py", "model": "claude-haiku-5-5", "input_tokens": 31, "output_tokens": 120, "stop_reason": "end_turn"}
```

This line is your **audit trail**. As a DBA you would never run a production job without a log, and AI programs are no different: in later modules, these logs are how you prove what an agent did, what it cost, and why it stopped.

---

## Step 5 - Run it again and count the calls

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python first_call.py
```

Run the same program a second time. The answer changes, and the log grows by one line.

---

## Step 6 - Count the lines in the log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
wc -l logs/calls.jsonl
```

`wc -l` counts lines. Two runs means two lines.

Expected output (yours will differ):

```text
2 logs/calls.jsonl
```

You have now made a real LLM call, read its usage numbers, and kept a log of it. Every agent in this course is built from exactly this call, repeated in a loop.

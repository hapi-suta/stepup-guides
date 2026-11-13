# Build 03: Tokens and Cost

**Objective:** Count tokens before you send a question, work out the exact dollar cost of each call, see what happens when the answer is cut off by `max_tokens`, and check your running spend on the proxy.

**Estimated Time:** 25-35 minutes

**Prerequisites:**
- Build 02 finished (`first_call.py` runs)

---

## How the bill is calculated

Every call is billed in two parts:

| Part | Price for `claude-haiku-5-5` | Per token |
|---|---|---|
| Input tokens (everything you send) | $0.10 per million | $0.0000001 |
| Output tokens (everything it writes, including its thinking) | $0.50 per million | $0.0000005 |

Output costs five times more than input. A short question with a long answer is mostly output cost.

DBA analogy: this is capacity planning. You would never size a server without knowing the cost of one query times the number of queries per day. AI is the same: cost per call times calls per day. An agent that makes 10 calls per question at $0.0005 each costs $0.005 per question, and $5 per thousand questions.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Write the cost calculator

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > cost.py <<'EOF'
import json
import os
import sys

import anthropic

PRICE_IN = 0.10 / 1_000_000
PRICE_OUT = 0.50 / 1_000_000

question = sys.argv[1]
max_tokens = int(sys.argv[2]) if len(sys.argv) > 2 else 400

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]
messages = [{"role": "user", "content": question}]

counted = client.messages.count_tokens(model=model, messages=messages)
print("tokens counted before sending:", counted.input_tokens)

response = client.messages.create(
    model=model,
    max_tokens=max_tokens,
    output_config={"effort": "low"},
    messages=messages,
)

answer = "".join(block.text for block in response.content if block.type == "text")
cost = response.usage.input_tokens * PRICE_IN + response.usage.output_tokens * PRICE_OUT

print(answer)
print()
print("stop reason:", response.stop_reason)
print("tokens in:", response.usage.input_tokens, "tokens out:", response.usage.output_tokens)
print(f"cost of this call: ${cost:.6f}")

os.makedirs("logs", exist_ok=True)
with open("logs/calls.jsonl", "a") as log:
    log.write(json.dumps({
        "script": "cost.py",
        "max_tokens": max_tokens,
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
        "stop_reason": response.stop_reason,
        "cost_usd": round(cost, 8),
    }) + "\n")
EOF
```

Only the new lines are explained here. Everything else is the same as `first_call.py`.

| Line(s) | What it does |
|---|---|
| `import sys` | Lets the program read what you type after `python cost.py` |
| `PRICE_IN = 0.10 / 1_000_000` | Dollars per input token. `1_000_000` is one million; the underscores are only there to make it readable |
| `PRICE_OUT = 0.50 / 1_000_000` | Dollars per output token |
| `question = sys.argv[1]` | The first thing you type after the script name becomes the question. `sys.argv` is the list of words on the command line |
| `max_tokens = int(...) if len(sys.argv) > 2 else 400` | If you typed a second value, use it as the cap; otherwise use 400. `int(...)` turns the text `"20"` into the number 20 |
| `messages = [...]` | The conversation, stored in a variable so both calls below use the same one |
| `counted = client.messages.count_tokens(...)` | Ask the model how many input tokens this would be **without** running it. It costs nothing. It is the `EXPLAIN` before the `EXPLAIN ANALYZE` |
| `cost = ... * PRICE_IN + ... * PRICE_OUT` | Tokens times price, for input and output, added together |
| `print(f"cost of this call: ${cost:.6f}")` | An **f-string** puts a value inside text. `:.6f` means "show 6 decimal places" |
| `"cost_usd": round(cost, 8)` | The log line now carries the cost too |

---

## Step 3 - Ask a question and see its price

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python cost.py "Explain what a PostgreSQL checkpoint is in three sentences."
```

The text in double quotes is the question. It becomes `sys.argv[1]`.

Expected output (yours will differ):

```text
tokens counted before sending: 32
A PostgreSQL checkpoint is a point in the write-ahead log (WAL) at which all dirty data pages in shared memory are flushed to disk, guaranteeing that changes up to that point are physically stored in the data files. Checkpoints are triggered automatically based on time (checkpoint_timeout) or WAL volume (max_wal_size), or manually with the CHECKPOINT command. ...

stop reason: end_turn
tokens in: 32 tokens out: 196
cost of this call: $0.000101
```

The count before sending (32) matches the tokens in (32). That is how you can price a prompt before you spend anything. The whole call cost about one hundredth of a cent.

---

## Step 4 - Cut the answer off with max_tokens

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python cost.py "Explain what a PostgreSQL checkpoint is in three sentences." 20
```

The `20` at the end becomes `max_tokens`, so the model may write only 20 tokens.

Expected output (yours will differ):

```text
tokens counted before sending: 32
A PostgreSQL checkpoint is a point in the write-

stop reason: max_tokens
tokens in: 32 tokens out: 20
cost of this call: $0.000013
```

The answer stops mid-word and `stop reason` is now `max_tokens`, not `end_turn`. The model did not choose to stop: the cap stopped it. A program must check `stop_reason` before trusting an answer, the same way you check a backup's exit code before trusting the backup.

---

## Step 5 - Add up what your log says you spent

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "import json; print(round(sum(json.loads(line).get('cost_usd', 0) for line in open('logs/calls.jsonl')), 6))"
```

`python -c "..."` runs a one-line program without a file. It reads every line of the log, turns each into data with `json.loads`, takes `cost_usd` (0 for the Build 02 lines, which did not record a cost), adds them up with `sum`, and rounds to 6 places.

Expected output (yours will differ):

```text
0.000114
```

This is a tiny version of a cost report from your own logs, like summing `pg_stat_statements.total_exec_time` to see where the time went.

---

## Step 6 - Compare with what the proxy says you spent

Still on **ai-lab**, as **ec2-user**:

```bash
curl -s -H "Authorization: Bearer $ANTHROPIC_API_KEY" $ANTHROPIC_BASE_URL/key/info | python -m json.tool | grep -E '"(spend|max_budget)"'
```

The same key check as Build 01, keeping the spend and cap lines.

Expected output (yours will differ):

```text
        "spend": 0.0017034,
        "max_budget": 5.0,
```

The proxy's number counts **every** call ever made with your key, including the Build 02 calls that did not log a cost, so it is usually higher than your log total. It can also be a little behind your last call, because the proxy writes spend in batches about once a minute. Run the command again a minute later and it catches up. The proxy is the source of truth for your $5 cap: once `spend` reaches `max_budget`, every call is refused until Prof. Happy raises it.

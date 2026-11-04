# Build 04: Messages and Memory

**Objective:** Prove that the model remembers nothing between calls, then give it memory the only way that works: by sending the whole conversation every time. Add a system prompt, and watch the input tokens (and the cost) grow with every turn.

**Estimated Time:** 25-35 minutes

**Prerequisites:**
- Build 03 finished

---

## The model is stateless

Each call is a brand new session. Nothing from your last call carries over.

DBA analogy: every call is like `psql -c "..."`. A temporary table you created in the last `psql -c` is gone in the next one, because it was a different session. If you want the next statement to know something, you have to send it again.

So "chat memory" is not memory inside the model. It is your program keeping a list of every message and resending the full list on every call. That list is the `messages` you have been sending since Build 02.

| Role | Who wrote it |
|---|---|
| `user` | You (or your program) |
| `assistant` | The model, in an earlier turn |
| `system` (a separate setting, not in the list) | Standing instructions for the whole conversation, like session settings in `postgresql.conf` |

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Write a program with no memory

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > forgetful.py <<'EOF'
import os

import anthropic

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]


def ask(text):
    response = client.messages.create(
        model=model,
        max_tokens=300,
        output_config={"effort": "low"},
        messages=[{"role": "user", "content": text}],
    )
    return "".join(block.text for block in response.content if block.type == "text")


print("ME: My production database is called payroll. Reply in one sentence.")
print("AI:", ask("My production database is called payroll. Reply in one sentence."))
print()
print("ME: What is my production database called? Reply in one sentence.")
print("AI:", ask("What is my production database called? Reply in one sentence."))
EOF
```

| Line(s) | What it does |
|---|---|
| `def ask(text):` | Defines a **function**: a named, reusable block of code, like a stored procedure. `text` is its one parameter |
| The indented lines under `def` | The body of the function: one call with a single message, then return the text of the answer |
| `return ...` | Hands the answer back to whoever called `ask` |
| The four `print` lines at the bottom | Ask two questions, each in its own separate call |

Notice that each call sends a list with exactly one message. The second call never hears the first.

---

## Step 3 - Run it

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python forgetful.py
```

Expected output (yours will differ):

```text
ME: My production database is called payroll. Reply in one sentence.
AI: Got it, your production database is called "payroll."

ME: What is my production database called? Reply in one sentence.
AI: I don't have access to your systems or any information about your production database, so I can't tell you its name. You could check your application's configuration files, environment variables, or your hosting provider's dashboard.
```

The second answer does not know the name. Nothing is wrong with the model: you never told it in that call.

---

## Step 4 - Write a program that keeps the conversation

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > chat.py <<'EOF'
import json
import os

import anthropic

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]
system = "You are a senior PostgreSQL DBA. Answer in at most two short sentences."
history = []


def ask(text):
    history.append({"role": "user", "content": text})
    response = client.messages.create(
        model=model,
        max_tokens=300,
        output_config={"effort": "low"},
        system=system,
        messages=history,
    )
    reply = "".join(block.text for block in response.content if block.type == "text")
    history.append({"role": "assistant", "content": reply})
    with open("logs/calls.jsonl", "a") as log:
        log.write(json.dumps({
            "script": "chat.py",
            "turn": len(history) // 2,
            "input_tokens": response.usage.input_tokens,
            "output_tokens": response.usage.output_tokens,
        }) + "\n")
    print("ME:", text)
    print("AI:", reply)
    print("   (tokens in this turn:", response.usage.input_tokens, ")")
    print()


ask("My production database is called payroll and runs PostgreSQL 16.")
ask("What is my production database called?")
ask("Which PostgreSQL major version does it run?")
EOF
```

| Line(s) | What it does |
|---|---|
| `system = "..."` | Standing instructions. Sent with every call, never part of `history` |
| `history = []` | An empty **list** that will hold every message, in order |
| `history.append({"role": "user", ...})` | Add your new message to the end of the list |
| `system=system,` | Send the standing instructions with this call |
| `messages=history,` | Send the **whole** list, not just the newest message. This is the memory |
| `history.append({"role": "assistant", "content": reply})` | Add the model's answer to the list too, so the next call sees it |
| `"turn": len(history) // 2` | Each turn adds two messages (yours and the model's), so the turn number is the list length divided by 2. `//` divides and drops the remainder |
| The three `ask(...)` lines | Three turns of one conversation |

---

## Step 5 - Run it

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python chat.py
```

Expected output (yours will differ):

```text
ME: My production database is called payroll and runs PostgreSQL 16.
AI: Understood: you're running a PostgreSQL 16 production database named "payroll." What do you need help with, and what's the issue or task?
   (tokens in this turn: 58 )

ME: What is my production database called?
AI: Your production database is called "payroll."
   (tokens in this turn: 111 )

ME: Which PostgreSQL major version does it run?
AI: PostgreSQL 16.
   (tokens in this turn: 141 )
```

Now it remembers. Look at the token counts: 58, then 111, then 141. Every turn resends everything before it, so input tokens (and cost) keep growing as the conversation gets longer. A 50-turn chat pays for turn 1 fifty times. This is why long-running agents need a plan for trimming or summarizing their history, which you will see later in the course.

---

## Step 6 - Find the growth in your log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
grep chat.py logs/calls.jsonl
```

`grep` prints only the lines that contain `chat.py`.

Expected output (yours will differ):

```text
{"script": "chat.py", "turn": 1, "input_tokens": 58, "output_tokens": 44}
{"script": "chat.py", "turn": 2, "input_tokens": 111, "output_tokens": 13}
{"script": "chat.py", "turn": 3, "input_tokens": 141, "output_tokens": 12}
```

The same growth, recorded as evidence. You now know the three facts every agent is built on: a call is stateless, memory is the message list you resend, and every resend costs tokens.

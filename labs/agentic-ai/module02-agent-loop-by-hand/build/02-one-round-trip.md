# Build 02: One Round Trip

**Objective:** Send a question together with your tool list, and catch the model asking to use a tool. You will not run the tool yet: this tutorial is only about reading the request the model sends back.

**Estimated Time:** 15-25 minutes

**Prerequisites:**
- Build 01 of this module finished (`tools.py` works)

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Write the round-trip program

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > one_round_trip.py <<'EOF'
import os
import sys

import anthropic

from tools import TOOLS

client = anthropic.Anthropic()
model = os.environ["SUTA_LLM_MODEL"]

response = client.messages.create(
    model=model,
    max_tokens=1000,
    output_config={"effort": "low"},
    tools=TOOLS,
    messages=[{"role": "user", "content": sys.argv[1]}],
)

print("stop reason:", response.stop_reason)
for block in response.content:
    if block.type == "text":
        print("text:", block.text)
    elif block.type == "tool_use":
        print("tool request:", block.name, block.input, "id:", block.id)
EOF
```

| Line(s) | What it does |
|---|---|
| `from tools import TOOLS` | Load the tool definitions you wrote in Build 01 |
| `tools=TOOLS,` | The one new setting: send the tool list with the question, so the model knows what it may ask for |
| `messages=[{... sys.argv[1]}]` | Your question comes from the command line, like `cost.py` |
| `for block in response.content:` | Go through each block of the reply, one at a time |
| `if block.type == "text":` | A text block is normal writing. Print it |
| `elif block.type == "tool_use":` | A `tool_use` block is a request. `elif` means "otherwise, if" |
| `block.name, block.input, block.id` | Which tool, with which inputs, and the request ID your result must quote back |

---

## Step 3 - Ask something that needs a tool

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python one_round_trip.py "How full is the root filesystem?"
```

Expected output (yours will differ):

```text
stop reason: tool_use
tool request: disk_usage {'path': '/'} id: toolu_018skJLggREAeDgk6S9phNr3
```

The model did not answer. It stopped with `tool_use` and asked you to run `disk_usage` with `path` set to `/`. It chose the tool and the input by reading your descriptions. Your `id` will be different on every run.

Nothing ran on your server. The model only asked. Deciding whether to run it is your code's job, and that decision point is where every agent safety control lives.

---

## Step 4 - Ask something that needs no tool

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python one_round_trip.py "What is the capital of France?"
```

Expected output (yours will differ):

```text
stop reason: end_turn
text: The capital of France is Paris.
```

Same tools offered, but the model did not need them, so it answered directly with `end_turn`. Having tools available does not force the model to use them.

---

## Step 5 - Ask something that needs the log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python one_round_trip.py "Are there any FATAL errors in the PostgreSQL log?"
```

Expected output (yours will differ):

```text
stop reason: tool_use
tool request: tail_log {'lines': 50} id: toolu_01F5gUK4wmifkbKSueQqKYxs
```

This time it picked `tail_log` and chose how many lines to read. You now know what the model sends back. In Build 03 your code will run the tool, return the result, and keep going until the model is done.

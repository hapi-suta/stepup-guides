# Build 01: Tools the Model Can Ask For

**Objective:** Create a sample PostgreSQL log, write two read-only tools in plain Python (one checks disk space, one reads the end of the log), describe them so a model can understand them, and test them yourself before any AI touches them.

**Estimated Time:** 25-35 minutes

**Prerequisites:**
- Module 01 finished (your prompt starts with `(.venv)` after you log in)

---

## Why test the tools first

The model will choose when to call these tools and with what inputs. If a tool is broken, the agent will fail in confusing ways. So you prove each tool works by hand first, the same way you would test a monitoring query in `psql` before putting it in a cron job.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Make a folder for sample data

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
mkdir data
```

Your lab server does not run PostgreSQL in this module, so you will give the agent a realistic sample log to investigate. In Module 4 the tools read a real database.

---

## Step 3 - Write the sample PostgreSQL log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > data/postgresql.log <<'EOF'
2026-11-04 02:00:01 UTC [1201] LOG:  checkpoint starting: time
2026-11-04 02:00:31 UTC [1201] LOG:  checkpoint complete: wrote 1840 buffers (11.2%); write=29.8 s
2026-11-04 02:14:09 UTC [5530] ERROR:  duplicate key value violates unique constraint "employees_email_key"
2026-11-04 02:20:44 UTC [5612] WARNING:  there is no transaction in progress
2026-11-04 02:31:17 UTC [5701] FATAL:  password authentication failed for user "report_user"
2026-11-04 02:31:19 UTC [5702] FATAL:  password authentication failed for user "report_user"
2026-11-04 02:31:22 UTC [5703] FATAL:  password authentication failed for user "report_user"
2026-11-04 02:45:00 UTC [1201] LOG:  checkpoint starting: wal
2026-11-04 02:45:02 UTC [1201] LOG:  checkpoints are occurring too frequently (14 seconds apart)
2026-11-04 02:45:02 UTC [1201] HINT:  Consider increasing the configuration parameter "max_wal_size".
2026-11-04 02:52:38 UTC [5844] ERROR:  deadlock detected
2026-11-04 02:52:38 UTC [5844] DETAIL:  Process 5844 waits for ShareLock on transaction 99812; blocked by process 5850.
2026-11-04 03:05:12 UTC [5901] FATAL:  sorry, too many clients already
2026-11-04 03:05:13 UTC [5902] FATAL:  sorry, too many clients already
2026-11-04 03:10:00 UTC [1201] LOG:  checkpoint complete: wrote 9120 buffers (55.7%); write=0.9 s
EOF
```

Fifteen log lines in the standard PostgreSQL format: timestamp, process ID in brackets, severity (`LOG`, `WARNING`, `ERROR`, `FATAL`, `HINT`, `DETAIL`) and the message. It hides four different problems for your agent to find.

---

## Step 4 - Write the tools

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > tools.py <<'EOF'
import os
import shutil

LOG_FILE = os.path.expanduser("~/agentic-ai/data/postgresql.log")


def disk_usage(path):
    total, used, free = shutil.disk_usage(path)
    return f"{path}: {used * 100 // total}% used, {free // 1024**3} GB free of {total // 1024**3} GB"


def tail_log(lines):
    lines = max(1, min(int(lines), 50))
    with open(LOG_FILE) as log:
        return "".join(log.readlines()[-lines:])


TOOLS = [
    {
        "name": "disk_usage",
        "description": "Show how full the filesystem that holds a directory is. Read-only.",
        "input_schema": {
            "type": "object",
            "properties": {"path": {"type": "string", "description": "A directory, for example /"}},
            "required": ["path"],
        },
    },
    {
        "name": "tail_log",
        "description": "Return the last N lines of the PostgreSQL server log (1 to 50). Read-only.",
        "input_schema": {
            "type": "object",
            "properties": {"lines": {"type": "integer", "description": "How many lines, 1 to 50"}},
            "required": ["lines"],
        },
    },
]

RUN = {"disk_usage": disk_usage, "tail_log": tail_log}
EOF
```

The file has three parts: two functions, the descriptions the model reads, and a lookup table.

| Line(s) | What it does |
|---|---|
| `import shutil` | Python's file utilities. `shutil.disk_usage` is the same information as `df` |
| `LOG_FILE = os.path.expanduser(...)` | The full path of the log. `expanduser` turns `~` into `/home/ec2-user` |
| `def disk_usage(path):` | Tool 1. Takes a directory and returns one line of text |
| `total, used, free = shutil.disk_usage(path)` | Three numbers in bytes for the filesystem holding `path` |
| `return f"{path}: {used * 100 // total}% used, ..."` | Turn the bytes into a readable sentence. `1024**3` is one gigabyte |
| `def tail_log(lines):` | Tool 2. Like `tail -n` on the log |
| `lines = max(1, min(int(lines), 50))` | **Guardrail.** Whatever the model asks for, read at least 1 and at most 50 lines. The model chooses the input, your code enforces the limit |
| `with open(LOG_FILE) as log:` | Open the log for reading only |
| `return "".join(log.readlines()[-lines:])` | Read all lines, keep the last `lines` of them, join them back into one block of text |
| `TOOLS = [ ... ]` | The **tool definitions**: what the model sees. It never sees your Python code, only these names and descriptions |
| `"name"` | The exact name the model uses to ask for the tool |
| `"description"` | Plain English the model reads to decide when to use it. "Read-only" tells it this tool cannot change anything |
| `"input_schema"` | The inputs, written as JSON Schema: their names, types (`string`, `integer`) and which are `required` |
| `RUN = {...}` | A **dictionary** (a lookup table, like a two-column table with a primary key) from tool name to the Python function. The agent loop uses it to find the right function by name |

---

## Step 5 - Test the disk tool yourself

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from tools import disk_usage; print(disk_usage('/'))"
```

`from tools import disk_usage` loads your function from `tools.py`. Then it runs it on `/` and prints the result. No AI is involved yet.

Expected output (yours will differ):

```text
/: 15% used, 8 GB free of 9 GB
```

---

## Step 6 - Test the log tool and its guardrail

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from tools import tail_log; print(tail_log(500))"
```

You asked for 500 lines on purpose. The guardrail caps it at 50, and the log only has 15, so you get the whole file and nothing breaks.

Expected output (yours will differ):

```text
2026-11-04 02:00:01 UTC [1201] LOG:  checkpoint starting: time
2026-11-04 02:00:31 UTC [1201] LOG:  checkpoint complete: wrote 1840 buffers (11.2%); write=29.8 s
...
2026-11-04 03:05:13 UTC [5902] FATAL:  sorry, too many clients already
2026-11-04 03:10:00 UTC [1201] LOG:  checkpoint complete: wrote 9120 buffers (55.7%); write=0.9 s
```

---

## Step 7 - Look at what the model will see

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "import json; from tools import TOOLS; print(json.dumps(TOOLS[1], indent=2))"
```

This prints the second tool definition (`TOOLS[1]`, because counting starts at 0) as formatted JSON. This is all the model knows about `tail_log`.

Expected output (yours will differ):

```text
{
  "name": "tail_log",
  "description": "Return the last N lines of the PostgreSQL server log (1 to 50). Read-only.",
  "input_schema": {
    "type": "object",
    "properties": {
      "lines": {
        "type": "integer",
        "description": "How many lines, 1 to 50"
      }
    },
    "required": [
      "lines"
    ]
  }
}
```

A good description is the difference between an agent that picks the right tool and one that guesses. Treat it like a column comment: write it for someone who has never seen your code.

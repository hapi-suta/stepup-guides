# Build 02: Lists and Dictionaries: Group the Incidents

**Objective:** Read the whole log into a list of dictionaries, walk through it with a loop, count records per severity with a dictionary, and finish with a one-line summary your agent could use as a tool.

**Estimated Time:** 40-50 minutes

**Prerequisites:**
- Build 01 finished (`logparse.py` defines `parse_line`)

---

## What you are building

Three functions, each using the one before it:

| Function | Takes | Returns | SQL comparison |
|---|---|---|---|
| `load_log()` | a file path | a list of dictionaries, one per log line | `SELECT * FROM log` |
| `count_by_severity()` | that list | a dictionary of severity to count | `GROUP BY severity` |
| `severity_summary()` | nothing | one line of text, highest count first | `ORDER BY count DESC`, formatted |

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Add load_log to your file

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Add two lines and a blank line at the very **top** of the file, above `def parse_line`:

```python
import os

LOG_FILE = os.path.expanduser("~/agentic-ai/data/postgresql.log")
```

Then add this function at the **bottom** of the file, with two blank lines above it. Save and quit with `Esc`, `:wq`, `Enter`.

```python
def load_log(path=LOG_FILE):
    records = []
    with open(path) as log:
        for line in log:
            line = line.rstrip("\n")
            if line == "":
                continue
            records.append(parse_line(line))
    return records
```

| Line(s) | What it does |
|---|---|
| `import os` | Loads Python's operating-system helpers |
| `LOG_FILE = os.path.expanduser(...)` | The full path of the log. `expanduser` turns `~` into `/home/ec2-user` |
| `def load_log(path=LOG_FILE):` | A function with a **default value**: call `load_log()` and it reads the sample log, call `load_log("/other/file")` and it reads that one |
| `records = []` | An empty **list** to collect results in |
| `with open(path) as log:` | Opens the file for reading and closes it when the indented block ends, even if something fails |
| `for line in log:` | A **loop**: runs the indented lines once for every line of the file |
| `line = line.rstrip("\n")` | Removes the line-ending character from the right side |
| `if line == "": continue` | Skips an empty line. `continue` jumps to the next turn of the loop |
| `records.append(parse_line(line))` | Calls your function from Build 01 and adds the dictionary to the end of the list |
| `return records` | Hands back the whole list. It is indented once, so it runs after the loop has finished, not inside it |

---

## Step 3 - Load the log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import load_log; records = load_log(); print(len(records)); print(records[0]); print(records[-1]['message'])"
```

`len(records)` counts the list. `records[0]` is the first item. `records[-1]` is the last one: negative positions count from the end.

Expected output (yours will differ):

```text
15
{'time': '2026-11-04 02:00:01 UTC', 'pid': 1201, 'severity': 'LOG', 'message': 'checkpoint starting: time'}
checkpoint complete: wrote 9120 buffers (55.7%); write=0.9 s
```

Fifteen lines in the file, fifteen dictionaries in the list. A list of dictionaries is a table: each dictionary is a row, each key is a column.

---

## Step 4 - Start the Python prompt

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python
```

You stay at the `>>>` prompt for the next two steps.

---

## Step 5 - Walk the list with a loop

Still on **ai-lab**, as **ec2-user**, at the Python `>>>` prompt. After the `for` line the prompt changes to `...`, which means Python is waiting for the rest of the block. Indent the `if` line with four spaces and the `print` line with eight. Press `Enter` on the empty `...` line to run the loop.

```
>>> from logparse import load_log
>>> records = load_log()
>>> for record in records:
...     if record["severity"] == "FATAL":
...         print(record["time"], record["message"])
...
```

The loop visits every dictionary in the list. `record["severity"] == "FATAL"` compares two values (two equals signs compare, one equals sign assigns). Only the matching records are printed. This is `WHERE severity = 'FATAL'`.

Expected output (yours will differ):

```text
2026-11-04 02:31:17 UTC password authentication failed for user "report_user"
2026-11-04 02:31:19 UTC password authentication failed for user "report_user"
2026-11-04 02:31:22 UTC password authentication failed for user "report_user"
2026-11-04 03:05:12 UTC sorry, too many clients already
2026-11-04 03:05:13 UTC sorry, too many clients already
```

Leave the Python prompt open for the next step.

---

## Step 6 - Count with a dictionary, by hand

Still at the Python `>>>` prompt:

```
>>> counts = {}
>>> counts.get("FATAL", 0)
>>> counts["FATAL"] = counts.get("FATAL", 0) + 1
>>> counts["FATAL"] = counts.get("FATAL", 0) + 1
>>> counts
>>> counts["PANIC"]
>>> exit()
```

`counts = {}` is an empty dictionary. `.get("FATAL", 0)` means "the value for FATAL, or 0 if there is none yet". The third line reads the current count, adds 1, and stores it back. Running it twice counts to 2. The line before `exit()` asks for a key that does not exist, on purpose. `exit()` then leaves the Python prompt.

Expected output (yours will differ):

```text
>>> counts.get("FATAL", 0)
0
>>> counts
{'FATAL': 2}
>>> counts["PANIC"]
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
KeyError: 'PANIC'
```

Square brackets on a missing key raise `KeyError`. `.get()` with a default never does. Counting needs `.get()`, because the first time you see a severity it is not in the dictionary yet.

---

## Step 7 - Add count_by_severity to your file

Back on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Add this function at the bottom of the file, with two blank lines above it. Save and quit.

```python
def count_by_severity(records):
    counts = {}
    for record in records:
        severity = record["severity"]
        counts[severity] = counts.get(severity, 0) + 1
    return counts
```

It is the counting line from Step 6 inside the loop from Step 5. For every record it reads the severity and adds 1 to that severity's count.

---

## Step 8 - Count the log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import load_log, count_by_severity; print(count_by_severity(load_log()))"
```

`count_by_severity(load_log())` runs the inner call first and passes its result to the outer one.

Expected output (yours will differ):

```text
{'LOG': 5, 'ERROR': 2, 'WARNING': 1, 'FATAL': 5, 'HINT': 1, 'DETAIL': 1}
```

The keys appear in the order they were first seen in the log, not in order of size. The next step fixes that.

---

## Step 9 - Start the Python prompt again

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python
```

---

## Step 10 - Sort by count

Still on **ai-lab**, as **ec2-user**, at the Python `>>>` prompt:

```
>>> from logparse import load_log, count_by_severity
>>> counts = count_by_severity(load_log())
>>> list(counts.items())
>>> sorted(counts.items(), key=lambda item: item[1], reverse=True)
>>> exit()
```

`.items()` gives the dictionary as pairs: `('LOG', 5)` is a **tuple**, a fixed pair of values. `sorted()` returns a new, sorted list. `key=lambda item: item[1]` tells it what to sort by: for each pair, use position 1, the count. `lambda` is a one-line function without a name. `reverse=True` puts the biggest first.

Expected output (yours will differ):

```text
>>> list(counts.items())
[('LOG', 5), ('ERROR', 2), ('WARNING', 1), ('FATAL', 5), ('HINT', 1), ('DETAIL', 1)]
>>> sorted(counts.items(), key=lambda item: item[1], reverse=True)
[('LOG', 5), ('FATAL', 5), ('ERROR', 2), ('WARNING', 1), ('HINT', 1), ('DETAIL', 1)]
```

`LOG` and `FATAL` both have 5. They stay in the order they had before the sort. Remember that: in Build 04 you will have to decide what happens on a tie.

---

## Step 11 - Add severity_summary to your file

Back on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Add this function at the bottom of the file, with two blank lines above it. Save and quit.

```python
def severity_summary():
    counts = count_by_severity(load_log())
    parts = []
    for severity, count in sorted(counts.items(), key=lambda item: item[1], reverse=True):
        parts.append(f"{severity}={count}")
    return " ".join(parts)
```

| Line(s) | What it does |
|---|---|
| `for severity, count in sorted(...)` | Loops over the sorted pairs and unpacks each pair into two names |
| `f"{severity}={count}"` | An **f-string**: text with values dropped in where the braces are, giving `FATAL=5` |
| `" ".join(parts)` | Glues the list of strings into one string with a space between them |

---

## Step 12 - Run the summary

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import severity_summary; print(severity_summary())"
```

Expected output (yours will differ):

```text
LOG=5 FATAL=5 ERROR=2 WARNING=1 HINT=1 DETAIL=1
```

Fifteen log lines became one line of 47 characters. For an agent, that is the difference between paying to read the whole log and paying to read six numbers.

---

## Step 13 - Predict, then run

Write down what `count_by_severity` returns when the list is empty. An error, `None`, or something else?

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import count_by_severity; print(count_by_severity([]))"
```

Expected output (yours will differ):

```text
{}
```

The loop ran zero times, so the empty dictionary was returned untouched. A function that behaves sensibly on empty input is a function you can trust at 3 a.m.

---

## What you can now explain

- Why a list of dictionaries is a table, and how a `for` loop with an `if` is a `WHERE` clause
- Why counting uses `counts.get(key, 0) + 1` and not `counts[key] + 1`
- What `sorted(..., key=..., reverse=True)` does, and what happens to ties
- Why `return records` is indented once and not twice in `load_log`

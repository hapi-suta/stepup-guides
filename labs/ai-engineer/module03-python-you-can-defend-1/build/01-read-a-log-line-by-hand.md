# Build 01: Read a Log Line by Hand

**Objective:** Take one PostgreSQL log line apart at the Python prompt, one operation at a time, then write your first function, `parse_line`, that turns a log line into a dictionary.

**Estimated Time:** 35-45 minutes

**Prerequisites:**
- Module 02 Build 01 finished (`~/agentic-ai/data/postgresql.log` exists)
- You have read the concept note "How Python Runs Your Tools"

---

## The rule for this track

Type the code yourself. Do not paste it. Typing is slower and you will make mistakes, and reading those mistakes is the lesson. Only data files and supplied test files are pasted.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Start the Python prompt

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python
```

`python` with no file name starts the **interactive prompt**. You type one line, Python runs it and shows the result. It is `psql` for Python: the fastest way to try something.

Expected output (yours will differ):

```text
Python 3.12.15 (main, ...) [GCC ...] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>>
```

`>>>` means Python is waiting for you. In the steps below, lines to type are shown with `>>>` in front. Type only what comes after it, one line at a time, pressing `Enter` after each.

---

## Step 3 - Put one log line in a name

Still on **ai-lab**, as **ec2-user**, at the Python `>>>` prompt:

```
>>> line = '2026-11-04 02:31:17 UTC [5701] FATAL:  password authentication failed for user "report_user"'
>>> type(line)
>>> len(line)
```

The first line attaches the name `line` to a piece of text. The text is inside single quotes because it contains double quotes. `type()` tells you what kind of value a name holds. `len()` counts its characters.

Expected output (yours will differ):

```text
>>> type(line)
<class 'str'>
>>> len(line)
92
```

`str` is a string: text. Everything read from a log file starts as a string.

---

## Step 4 - Cut the string by position

Still at the Python `>>>` prompt:

```
>>> line[0]
>>> line[0:4]
>>> line[:23]
>>> line[24:]
```

Square brackets cut a piece out of a string. Counting starts at 0. `[0:4]` means from position 0 up to, but not including, position 4. Leaving a side empty means "from the start" or "to the end".

Expected output (yours will differ):

```text
>>> line[0]
'2'
>>> line[0:4]
'2026'
>>> line[:23]
'2026-11-04 02:31:17 UTC'
>>> line[24:]
'[5701] FATAL:  password authentication failed for user "report_user"'
```

The timestamp is always the first 23 characters of a line in this log, so `line[:23]` is the timestamp and `line[24:]` is everything after the space that follows it.

---

## Step 5 - Cut the string at a separator

Still at the Python `>>>` prompt:

```
>>> stamp = line[:23]
>>> rest = line[24:]
>>> rest.split("] ", 1)
>>> pid_part, rest = rest.split("] ", 1)
>>> pid_part
>>> rest
```

`.split("] ", 1)` cuts the string where it finds `] ` and stops after the first cut (that is what the `1` means). The result is a **list** with two parts. The fourth line gives each part its own name in one move: the first part goes to `pid_part`, the second replaces `rest`. This is called **unpacking**.

Expected output (yours will differ):

```text
>>> rest.split("] ", 1)
['[5701', 'FATAL:  password authentication failed for user "report_user"']
>>> pid_part
'[5701'
>>> rest
'FATAL:  password authentication failed for user "report_user"'
```

---

## Step 6 - Turn text into a number

Still at the Python `>>>` prompt:

```
>>> pid_part[1:]
>>> type(pid_part[1:])
>>> pid = int(pid_part[1:])
>>> type(pid)
>>> pid + 1
>>> "5701" + 1
```

`pid_part[1:]` drops the `[`. What is left looks like a number but is still text. `int()` converts it. The last line is wrong on purpose.

Expected output (yours will differ):

```text
>>> pid_part[1:]
'5701'
>>> type(pid_part[1:])
<class 'str'>
>>> type(pid)
<class 'int'>
>>> pid + 1
5702
>>> "5701" + 1
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
TypeError: can only concatenate str (not "int") to str
```

That `TypeError` is Python refusing to guess. `'5701'` in quotes is text, `5701` without quotes is a number. Read the last line of the error: it names exactly what went wrong.

---

## Step 7 - Split the severity from the message

Still at the Python `>>>` prompt:

```
>>> severity, message = rest.split(":", 1)
>>> severity
>>> message
>>> message.strip()
```

The same split-and-unpack as Step 5, this time at the first `:`. The `1` matters: many PostgreSQL messages contain more colons, and you only want to cut at the first one. `.strip()` removes the spaces at both ends.

Expected output (yours will differ):

```text
>>> severity
'FATAL'
>>> message
'  password authentication failed for user "report_user"'
>>> message.strip()
'password authentication failed for user "report_user"'
```

You have now taken the line apart into four pieces: `stamp`, `pid`, `severity` and the stripped message.

---

## Step 8 - Leave the Python prompt

Still at the Python `>>>` prompt:

```
>>> exit()
```

You are back at the shell prompt, which starts with `(.venv)`. Everything you typed at `>>>` is gone. To keep code, it has to go into a file.

---

## Step 9 - Write the function in a file

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Press `i` to start typing. Type this, with exactly four spaces at the start of each indented line (eight for the lines inside the braces). When you are done press `Esc`, then type `:wq` and press `Enter` to save and quit.

```python
def parse_line(line):
    stamp = line[:23]
    rest = line[24:]
    pid_part, rest = rest.split("] ", 1)
    severity, message = rest.split(":", 1)
    return {
        "time": stamp,
        "pid": int(pid_part[1:]),
        "severity": severity,
        "message": message.strip(),
    }
```

| Line(s) | What it does |
|---|---|
| `def parse_line(line):` | Defines a **function** named `parse_line` that takes one input, called `line` inside the function |
| The four lines after it | The same cuts you made by hand in Steps 4 to 7 |
| `return { ... }` | Hands a **dictionary** back to whoever called the function: four keys, each with its value |
| `"pid": int(pid_part[1:])` | The process ID, converted to a number on the way out |
| Indentation | Python uses indentation to know what belongs to the function. Every line of the body is indented four spaces |

---

## Step 10 - Call your function

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import parse_line; print(parse_line('2026-11-04 02:52:38 UTC [5844] ERROR:  deadlock detected'))"
```

`python -c "..."` runs one line of Python and exits. `from logparse import parse_line` loads your function from `logparse.py`. Then it calls the function on a different log line and prints what comes back.

Expected output (yours will differ):

```text
{'time': '2026-11-04 02:52:38 UTC', 'pid': 5844, 'severity': 'ERROR', 'message': 'deadlock detected'}
```

If you get `IndentationError` or `SyntaxError`, read the line number in the message, open the file with `vi logparse.py` and compare that line with Step 9.

---

## Step 11 - Predict, then run

Before you run the next command, write down your answers to two questions. What will `severity` be for a `HINT` line? Will `pid` be text or a number?

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import parse_line; r = parse_line('2026-11-04 02:45:02 UTC [1201] HINT:  Consider increasing the configuration parameter \"max_wal_size\".'); print(r['severity']); print(type(r['pid']))"
```

`r['severity']` looks up one value in the dictionary by its key.

Expected output (yours will differ):

```text
HINT
<class 'int'>
```

Predicting before you run is the habit that turns typing into understanding. Do it for every command in this track.

---

## What you can now explain

- Why `'5701'` and `5701` are different, and where the conversion happens in your function
- What `[:23]`, `[24:]` and `.split(":", 1)` each return
- The difference between trying something at `>>>` and keeping it in a file
- What `return` gives back, and to whom

One weakness to keep in mind for Build 03: `parse_line` trusts that every line has the same shape. Ask yourself what it does with a line that does not.

# Build 03: Exceptions and Tests: A Tool That Fails Well

**Objective:** Break your own function on purpose, read the traceback, make it fail early with a message that names the problem, then install pytest and lock the behaviour in with tests, including one you write yourself.

**Estimated Time:** 40-50 minutes

**Prerequisites:**
- Build 02 finished (`logparse.py` defines `parse_line`, `load_log`, `count_by_severity` and `severity_summary`)

---

## Why a tool has to fail well

Your agent loop from Module 02 catches a failing tool and sends the error text to the model:

```python
except (KeyError, TypeError, ValueError, OSError) as error:
    output, is_error = f"tool failed: {error!r}", True
```

So the model's only information about a failure is the message inside your exception. A vague message produces a confused agent. A precise one lets it recover.

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Break parse_line on purpose

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import parse_line; parse_line('garbage')"
```

You are giving `parse_line` text that is not a log line, to see what it does.

Expected output (yours will differ):

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/ec2-user/agentic-ai/logparse.py", line 9, in parse_line
    pid_part, rest = rest.split("] ", 1)
    ^^^^^^^^^^^^^^
ValueError: not enough values to unpack (expected 2, got 1)
```

This is a **traceback**. Read it from the bottom up:

| Line | What it tells you |
|---|---|
| `ValueError: not enough values to unpack (expected 2, got 1)` | What went wrong: the split produced one piece, and two names were waiting |
| `pid_part, rest = rest.split("] ", 1)` | The line of your code that failed |
| `File ".../logparse.py", line 9, in parse_line` | Which file, which line number, which function |
| `File "<string>", line 1` | Who called it: your one-line `python -c` command |

The error is true but useless to anyone who did not write the function. It talks about unpacking. The real problem is that the input was not a log line.

---

## Step 3 - Fail early with a clear message

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Add two lines as the **first two lines inside** `parse_line`, directly under the `def parse_line(line):` line. Save and quit.

```python
    if line[24:25] != "[":
        raise ValueError(f"not a PostgreSQL log line: {line!r}")
```

| Part | What it does |
|---|---|
| `line[24:25]` | The one character at position 24, where every real log line has the `[` of the process ID. A slice never fails: on a short string it returns `""` |
| `!= "["` | "Is not equal to" |
| `raise ValueError(...)` | Stops the function right here and reports a failure of type `ValueError` |
| `{line!r}` | Puts the offending text into the message, in quotes, so invisible characters such as tabs show up |

`ValueError` is the standard exception for "right type, wrong value". The input is a string, as expected, but not a string this function can use.

---

## Step 4 - Break it again

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import parse_line; parse_line('garbage')"
```

Expected output (yours will differ):

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/ec2-user/agentic-ai/logparse.py", line 8, in parse_line
    raise ValueError(f"not a PostgreSQL log line: {line!r}")
ValueError: not a PostgreSQL log line: 'garbage'
```

Same exception type, same place, but now the last line says what is wrong and shows the input. That is the line your agent would send to the model.

---

## Step 5 - Ask for a file that does not exist

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import load_log; load_log('/no/such/file.log')"
```

Expected output (yours will differ):

```text
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/home/ec2-user/agentic-ai/logparse.py", line 23, in load_log
    with open(path) as log:
         ^^^^^^^^^^
FileNotFoundError: [Errno 2] No such file or directory: '/no/such/file.log'
```

You did not write this error. Python's `open()` raised it, and its message is already clear, so you leave it alone. `FileNotFoundError` is a kind of `OSError`, which your agent loop catches.

---

## Step 6 - Start the Python prompt

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python
```

---

## Step 7 - See what the model would be told

Still on **ai-lab**, as **ec2-user**, at the Python `>>>` prompt. Type this block. It is the same `try` and `except` your agent loop uses. Press `Enter` on the empty `...` line to run it, then leave the prompt with `exit()`.

```
>>> from logparse import parse_line
>>> try:
...     parse_line("garbage")
... except (KeyError, TypeError, ValueError, OSError) as error:
...     print(f"tool failed: {error!r}")
...
>>> exit()
```

`try:` runs the indented code. If it raises one of the listed exception types, Python jumps to the `except` block, with the exception available under the name `error`. The program does not stop.

Expected output (yours will differ):

```text
tool failed: ValueError("not a PostgreSQL log line: 'garbage'")
```

That one line is everything the model learns about the failure. Before Step 3 it would have read `ValueError('not enough values to unpack (expected 2, got 1)')`.

---

## Step 8 - Add pytest to the project's requirements

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
echo 'pytest==9.2.0' >> requirements.txt
```

`>>` appends one line to the end of `requirements.txt` (one `>` would overwrite the file). `pytest==9.2.0` pins the exact version, so everyone who installs this project gets the same test runner.

---

## Step 9 - Install it

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
pip install -r requirements.txt
```

`pip` installs every library listed in the file into your virtual environment. The ones you already have are skipped.

Expected output (yours will differ):

```text
...
Installing collected packages: pygments, pluggy, packaging, iniconfig, pytest
Successfully installed iniconfig-2.3.1 packaging-26.3 pluggy-1.7.0 pygments-2.21.0 pytest-9.2.0
```

---

## Step 10 - Make a folder for tests

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
mkdir tests
```

Tests live next to the code, in their own folder, so they are easy to find and easy to run together.

---

## Step 11 - Paste the first test file

This is a supplied test file, so it is pasted, not typed. Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > tests/test_logparse.py <<'EOF'
import pytest

from logparse import count_by_severity, load_log, parse_line

LINE = '2026-11-04 02:31:17 UTC [5701] FATAL:  password authentication failed for user "report_user"'


def test_parse_line_splits_the_four_fields():
    assert parse_line(LINE) == {
        "time": "2026-11-04 02:31:17 UTC",
        "pid": 5701,
        "severity": "FATAL",
        "message": 'password authentication failed for user "report_user"',
    }


def test_parse_line_rejects_garbage():
    with pytest.raises(ValueError):
        parse_line("garbage")


def test_count_by_severity_counts_each_level():
    records = [{"severity": "FATAL"}, {"severity": "LOG"}, {"severity": "FATAL"}]
    assert count_by_severity(records) == {"FATAL": 2, "LOG": 1}


def test_load_log_missing_file_raises():
    with pytest.raises(FileNotFoundError):
        load_log("/no/such/file.log")
EOF
```

| Line(s) | What it does |
|---|---|
| `def test_...():` | A test is a function whose name starts with `test_`. The name says what must be true |
| `assert a == b` | The claim. If `a` equals `b` the test passes. If not, it fails and pytest shows both values |
| `with pytest.raises(ValueError):` | The claim is that the indented code **must** raise `ValueError`. If it runs without failing, the test fails |
| `records = [{"severity": "FATAL"}, ...]` | Test data written in the test itself, so the test does not depend on the log file |

---

## Step 12 - Run the tests

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -m pytest -q
```

`python -m pytest` runs pytest from the current folder, so the tests can find `logparse.py`. `-q` means quiet: one character per test.

Expected output (yours will differ):

```text
....                                                                     [100%]
4 passed in 0.01s
```

Each dot is a passing test. An `F` would be a failing one, followed by a report showing which claim did not hold.

---

## Step 13 - Write a fifth test yourself

<!-- solo -->

No code is given for this step. Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`, open the test file:

```bash
vi tests/test_logparse.py
```

At the bottom, with two blank lines above it, write a test named `test_parse_line_turns_pid_into_an_integer`. Its claim: the `pid` in the dictionary returned by `parse_line(LINE)` is an integer, not text. You saw how to ask for a value's type in Build 01. Save and quit.

---

## Step 14 - Run all five tests

<!-- solo -->

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -m pytest -q
```

Expected output (yours will differ):

```text
.....                                                                    [100%]
5 passed in 0.01s
```

To be sure your test can fail, change `int(pid_part[1:])` to `pid_part[1:]` in `logparse.py`, run the tests, watch your new test fail, then put `int()` back and run them again. A test you have never seen fail has not proved anything yet.

---

## What you can now explain

- How to read a traceback from the bottom up
- Why you raise `ValueError` with the input in the message instead of letting the unpack error through
- What `try` and `except` do, and why your agent loop needs them around every tool call
- What `assert` and `pytest.raises` each claim
- Why a test must be seen failing once

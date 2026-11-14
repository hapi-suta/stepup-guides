# Build 04: Write It Yourself: top_errors

**Objective:** Write a function alone, from a specification and a set of tests. Nobody gives you the code. You are done when the tests pass and you can explain every line.

**Estimated Time:** 45-75 minutes

**Prerequisites:**
- Build 03 finished (`python -m pytest -q` shows 5 passed)

---

## How this tutorial is different

Builds 01 to 03 showed you the code and asked you to type it. This one shows you what the code must **do**. That is how real work arrives: a requirement and a way to check it.

Two rules:

- Do not ask an AI to write the function. Ask it to explain an error message, or a Python feature, if you need to.
- Run the tests often. A failing test is not a bad sign. It is the next instruction.

---

## The specification

Add a function `top_errors(records, n=3)` to `logparse.py`.

| Rule | Detail |
|---|---|
| Input | `records`: a list of dictionaries, each with at least the keys `severity` and `message`. `n`: how many results to return, 3 if not given |
| What to count | Only records whose severity is `ERROR` or `FATAL`. Count how many times each `message` appears |
| Output | A list of `(message, count)` tuples |
| Order | Highest count first. When two messages have the same count, the one that comes first alphabetically goes first |
| Limit | At most `n` results |
| Empty input | An empty list gives an empty list |
| Bad `n` | If `n` is less than 1, raise `ValueError` |
| Side effects | The function must not change the `records` list it was given |

For the sample log the result must be:

```text
[('password authentication failed for user "report_user"', 3), ('sorry, too many clients already', 2), ('deadlock detected', 1)]
```

---

## Step 1 - Go to the course folder

On your **ai-lab** server, as **ec2-user**:

```bash
cd ~/agentic-ai
```

---

## Step 2 - Paste the supplied tests

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
cat > tests/test_top_errors.py <<'EOF'
import pytest

from logparse import top_errors


def rec(severity, message):
    return {"severity": severity, "message": message}


RECORDS = [
    rec("FATAL", "too many clients"),
    rec("ERROR", "deadlock detected"),
    rec("LOG", "checkpoint starting"),
    rec("FATAL", "too many clients"),
    rec("ERROR", "duplicate key"),
    rec("WARNING", "no transaction in progress"),
    rec("FATAL", "too many clients"),
    rec("ERROR", "deadlock detected"),
]


def test_counts_only_error_and_fatal_most_frequent_first():
    assert top_errors(RECORDS, 10) == [
        ("too many clients", 3),
        ("deadlock detected", 2),
        ("duplicate key", 1),
    ]


def test_n_limits_the_result():
    assert top_errors(RECORDS, 2) == [("too many clients", 3), ("deadlock detected", 2)]


def test_default_n_is_three():
    many = [rec("ERROR", name) for name in ("a", "b", "c", "d", "e")]
    assert len(top_errors(many)) == 3


def test_ties_are_broken_alphabetically():
    assert top_errors([rec("ERROR", "b"), rec("ERROR", "a")], 5) == [("a", 1), ("b", 1)]


def test_empty_input_gives_empty_list():
    assert top_errors([], 3) == []


def test_n_below_one_raises_value_error():
    with pytest.raises(ValueError):
        top_errors(RECORDS, 0)


def test_input_is_not_changed():
    before = [dict(record) for record in RECORDS]
    top_errors(RECORDS, 2)
    assert RECORDS == before
EOF
```

Seven tests, one for each rule in the specification. Read them before you write anything: each test name is a sentence, and each `assert` is an example of the rule.

---

## Step 3 - Run the tests and watch them fail

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -m pytest -q tests/test_top_errors.py
```

Naming a file after `pytest` runs only the tests in that file.

Expected output (yours will differ):

```text
...
tests/test_top_errors.py:3: in <module>
    from logparse import top_errors
E   ImportError: cannot import name 'top_errors' from 'logparse' (/home/ec2-user/agentic-ai/logparse.py)
=========================== short test summary info ============================
ERROR tests/test_top_errors.py
!!!!!!!!!!!!!!!!!!!! Interrupted: 1 error during collection !!!!!!!!!!!!!!!!!!!!
1 error in 0.04s
```

This is the right failure. The function does not exist yet, so the test file cannot even import it. Writing the tests first and seeing them fail is how you know they are checking something.

---

## Step 4 - Write the function

<!-- solo -->

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi logparse.py
```

Write `top_errors` at the bottom of the file. Work in small moves and run the tests after each one:

1. Write only the `def` line and `return []`. Run the tests. Two tests should pass now. Which two, and why?
2. Add the rule for a bad `n`.
3. Count the messages. You wrote almost this loop in Build 02.
4. Sort, then limit.

Save and quit after each move, run the tests in the next step, then come back here.

---

## Step 5 - Run the tests after every move

<!-- solo -->

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -m pytest -q tests/test_top_errors.py
```

Go back and forth between Step 4 and this step until all seven tests pass.

When a test fails, pytest prints the `assert` line with the value your function returned and the value the test expected. Read both before you change anything.

**Hints. Read one only after 15 minutes stuck on the same test, and only the next one.**

1. For "only ERROR or FATAL": `if value in ("ERROR", "FATAL"):` is true when `value` is one of the two.
2. For "at most n": a list can be cut the same way as a string. `items[:2]` is the first two.
3. For the tie rule: the `key` function of `sorted()` may return a tuple, and tuples are compared position by position. A number can be made to sort backwards by putting a minus sign in front of it.

---

## Step 6 - All tests pass

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -m pytest -q
```

With no file name, pytest runs every test in the project: your five from Build 03 and the seven new ones.

Expected output (yours will differ):

```text
............                                                             [100%]
12 passed in 0.01s
```

Twelve dots. The five old tests still passing matters as much as the seven new ones: it proves that adding `top_errors` broke nothing you built before.

---

## Step 7 - Run it on the real log

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from logparse import load_log, top_errors; print(top_errors(load_log()))"
```

Expected output (yours will differ):

```text
[('password authentication failed for user "report_user"', 3), ('sorry, too many clients already', 2), ('deadlock detected', 1)]
```

Three failed logins, two refused connections, one deadlock. `duplicate key value violates unique constraint ...` also happened once, but it lost the tie to `deadlock detected` alphabetically and `n` is 3.

---

## Step 8 - From a blank file

<!-- solo -->

Close your editor. Set a timer for 15 minutes. In a new file, `scratch.py`, write `count_by_severity` from memory, without opening `logparse.py`.

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
vi scratch.py
```

---

## Step 9 - Check your blank-file version

Still on **ai-lab**, as **ec2-user**, inside `~/agentic-ai`:

```bash
python -c "from scratch import count_by_severity; print(count_by_severity([{'severity': 'FATAL'}, {'severity': 'LOG'}, {'severity': 'FATAL'}]))"
```

Expected output (yours will differ):

```text
{'FATAL': 2, 'LOG': 1}
```

If you could not finish in 15 minutes, that is the most useful thing you learned today: do it again tomorrow until you can. Writing a small function from nothing, under a clock, is exactly what a coding interview asks for.

---

## Defend it

Answer these aloud, as if to an interviewer, without looking at your code. Then check each answer against the code.

1. Walk through your function line by line for the input `[rec("ERROR", "b"), rec("ERROR", "a")]`. What does each name hold after each line?
2. Which line would you change to also count `PANIC`? Which test would you add first?
3. Your function is called with `n="3"` (text, from a model). What happens, and on which line?
4. Why does `test_input_is_not_changed` exist? Write one line that would make it fail.

Record your answers or give them live. Your tutor scores each one 0 to 4 against this scale; you do not score yourself: 0 could not start, 1 recognised the idea, 2 explained it, 3 explained it and could change the code, 4 could rebuild it from a blank file and argue for the design. Anything below 3, do again tomorrow.

---

## What you can now explain

- How to turn a specification into code by letting tests fail one at a time
- How you filtered, counted, sorted with a tie rule, and limited the result
- Why the old tests passing is part of the proof
- What your function does with input it was not designed for

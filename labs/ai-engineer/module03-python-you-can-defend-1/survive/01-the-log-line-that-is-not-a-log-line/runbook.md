# The Log Line That Is Not a Log Line

**Severity:** P2 - High (the log tools return nothing but errors)
**Expected Recovery Time:** 25-40 minutes
**Server:** ai-lab, user ec2-user

## Objective

Your `severity_summary` tool fails on every call. Nobody changed your code. Find out from the traceback what changed, decide what your code should do about it, fix it without weakening `parse_line`, and add a test so it cannot come back.

---

## Alert

```text
ALERT: the severity summary tool fails on every call
It worked yesterday. Nobody changed the code. The
database had a statement timeout a few minutes ago.
```

Prof. Happy starts the scenario by running `inject.sh` on your server. Do not read `inject.sh` first.

---

## Key Concepts for Revision

- **Code can break without changing.** A function that is correct for yesterday's input can fail on today's. When the code has not changed, look at the data.
- **Read the traceback from the bottom.** The last line names the failure and, because you wrote the message with `{line!r}` in Build 03, it shows the exact input that caused it. The lines above show which function called which.
- **Strict parser, tolerant reader.** `parse_line` answers "is this one line a record?" and should stay strict. `load_log` answers "what records are in this file?" and has to cope with a real file. Those are two different jobs.
- **Real PostgreSQL logs have lines that are not records.** A statement that spans several lines is logged with its later lines indented by a tab. They belong to the record above them.

---

## Investigate

Work on **ai-lab** as **ec2-user**, inside `~/agentic-ai`. Reproduce the symptom:

```bash
python -c "from logparse import severity_summary; print(severity_summary())"
```

Read the traceback from the bottom. Three things to write down: the exception type, the text inside the message, and the chain of three functions above it.

Now look at the end of the data, with invisible characters made visible:

```bash
tail -5 data/postgresql.log | cat -A
```

`cat -A` shows a tab as `^I` and the end of each line as `$`.

Expected output (yours will differ):

```text
2026-11-04 03:12:40 UTC [6010] ERROR:  canceling statement due to statement timeout$
2026-11-04 03:12:40 UTC [6010] STATEMENT:  SELECT e.id, d.name$
^I  FROM employees e JOIN departments d ON d.id = e.department_id$
^I WHERE e.hired_on > now() - interval '30 days';$
2026-11-04 03:13:02 UTC [6011] FATAL:  sorry, too many clients already$
```

---

## Find the root cause

Answer these before you touch any code:

1. Which of the five new lines are records, and which are not?
2. `parse_line` raised `ValueError` on one of them. Was `parse_line` wrong to do that?
3. Which function decided that one bad line should stop the whole file from being read? Did you ever decide that, or did it just happen?

Hint, if you are stuck after 15 minutes: look at the one line in `load_log` that calls `parse_line`, and remember what `try` and `except` did in Build 03, Step 7.

---

## Fix it

Two fixes are tempting and both are wrong:

- Deleting the awkward lines from the log. The next statement timeout puts them back, and in production the log is not yours to edit.
- Removing the check from `parse_line`. Then garbage is silently turned into nonsense records.

The fix belongs in `load_log`: when a line is not a record, skip it and carry on with the next one.

```bash
vi logparse.py
```

Change only `load_log`. Then check the file is still valid Python:

```bash
python -m py_compile logparse.py
```

No output means it compiled.

---

## Add the test that would have caught it

Open your test file:

```bash
vi tests/test_logparse.py
```

Write one new test: a log containing a record, then a tab-indented continuation line, then another record, must load as exactly two records. Your test needs its own small log file. pytest gives every test a private temporary folder if the test function takes an argument named `tmp_path`; look up "tmp_path" in the pytest documentation and use it.

Run everything:

```bash
python -m pytest -q
```

Every test must pass, including the old ones.

---

## Prove it is fixed

```bash
python -c "from logparse import severity_summary; print(severity_summary())"
```

Expected output (yours will differ):

```text
FATAL=6 LOG=5 ERROR=3 WARNING=1 HINT=1 DETAIL=1 STATEMENT=1
```

Then tell SutaAI it is fixed. Prof. Happy's `validate.sh` checks what your code does, not how it is written.

Expected validator result (yours will differ):

```text
== Validating: The Log Line That Is Not a Log Line ==
  PASS  the log still has all 20 lines (nothing was deleted)
  PASS  the two continuation lines are still in the log
  PASS  load_log reads past them and returns 18 records
  PASS  the new records are counted (FATAL 6, STATEMENT 1)
  PASS  severity_summary works again
  PASS  parse_line still rejects a line that is not a record
  PASS  all your tests pass
  PASS  you added a test for this incident (13 or more tests)
  (the original 15-line sample log has been put back)
== RESOLVED: 8 passed ==
```

When every check passes, the validator puts the original 15-line sample log back, so later modules start from the same data.

---

## Post-incident questions

1. The code did not change and the tool broke. What does that tell you about where to look first in the next incident?
2. Your fix skips lines that are not records. The skipped lines here were part of a SQL statement. What information did the agent lose, and when would that matter?
3. A silent skip can hide a real problem, for example a log in a completely different format where every line is skipped. How could `load_log` report how many lines it skipped without failing? Who should see that number?
4. Why was it right to keep `parse_line` strict and make `load_log` tolerant, and not the other way round?
5. `parse_line` finds the timestamp by position (`line[:23]`). Name one change to the PostgreSQL configuration that would break it, and say which test you would write to catch that.

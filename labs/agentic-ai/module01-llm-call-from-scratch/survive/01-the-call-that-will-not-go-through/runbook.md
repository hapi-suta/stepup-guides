# The Call That Will Not Go Through

**Severity:** P2 - High (every AI script on the server is down)
**Expected Recovery Time:** 10-20 minutes
**Server:** ai-lab, user ec2-user

## Objective

Every AI script on your server stops with an error. Nothing in your code changed. Find out why from the error message alone, fix the one-character cause, and prove the fix with a logged, successful call.

---

## Alert

```text
ALERT: every AI script on ai-lab is failing
first_call.py, cost.py and chat.py all stop with an error.
Nothing in ~/agentic-ai was changed. Log out, log back in,
then investigate.
```

Prof. Happy starts the scenario by running `inject.sh` on your server. Do not read `inject.sh` before you have solved it: in a real incident nobody hands you the script that broke production.

---

## Key Concepts for Revision

- **Read the last line of a traceback first.** A Python error prints many lines. The last one names the error type and the message from the server. The lines above it only show where in the library the error passed through.
- **HTTP status codes.** `401` = the key is wrong or missing. `403` = the key is fine but not allowed to do this. `404` = wrong address. `422` = budget exceeded on this proxy. `429` = too many requests too fast.
- **Environment variables come from your login.** `~/.bashrc` sources `~/.suta-llm.env` when you log in. A change to that file does nothing to an already-open shell until you `source` it again.
- **Model names are exact strings.** `claude-haiku-5-5` and `claude-haiku-5.5` look the same to a person and are different to a computer, like `payroll` and `Payroll` as quoted identifiers.

---

## Investigate

Work on **ai-lab** as **ec2-user**, inside `~/agentic-ai`. Run the simplest script and read only the last line of the error:

```bash
python first_call.py
```

Ask yourself: which status code is it, and what does that code mean according to the list above? Is the problem the key, the address, the budget, or something else the key is being asked to do?

---

## Find the root cause

The error names something your program asked for. Find where your program gets that value. Look at `first_call.py` for the line that sets `model`, then check the value that line reads:

```bash
echo $SUTA_LLM_MODEL
```

Compare it, character by character, with the model name in Build 01 and the concepts notes.

Hint, if you are stuck after 10 minutes: the file that sets this variable is `~/.suta-llm.env`. You can check just that line without printing your key:

```bash
grep SUTA_LLM_MODEL ~/.suta-llm.env
```

Never `cat` the whole file into chat: it holds your key.

---

## Fix it

Edit the one wrong character in `~/.suta-llm.env` with vi:

```bash
vi ~/.suta-llm.env
```

In vi: move to the `SUTA_LLM_MODEL` line, put the cursor on the wrong character, press `r` and type the right one, then `Esc` and `:wq` to save and quit. Change nothing else in the file.

Then load the fixed file into your current shell:

```bash
source ~/.suta-llm.env
```

---

## Prove it is fixed

Run the script again:

```bash
python first_call.py
```

It should print an answer and `stop reason: end_turn`, and add one line to `logs/calls.jsonl`. Then tell SutaAI it is fixed. Prof. Happy's `validate.sh` (it lives next to `inject.sh`) checks the side effects, never the wording of the answer.

Expected validator result (yours will differ):

```text
== Validating: The Call That Will Not Go Through ==
  PASS  model line is exactly claude-haiku-5-5
  PASS  key file is still mode 600
  PASS  first_call.py exits 0 with the fixed settings
  PASS  the successful call was logged
== RESOLVED: 4 passed ==
```

---

## Post-incident questions

Answer these for SutaAI. They are the part an interviewer cares about.

1. Which line of the error told you the cause, and what was the status code?
2. Why did the error say "not available for this API key" instead of "this model does not exist"? What does that tell you about where the request was refused (the proxy or Claude itself)?
3. Why did fixing the file not help until you ran `source`?
4. How would you stop this typo from happening again for a whole class of students?

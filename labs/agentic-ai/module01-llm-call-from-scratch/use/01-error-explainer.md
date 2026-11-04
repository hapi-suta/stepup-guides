# The PostgreSQL Error Explainer

## Objective

Build `explain_error.py`: a small tool a junior DBA could use at 3 a.m. You give it a PostgreSQL error message, and it returns a short, calm explanation and a first thing to check. Then measure what it costs to run, and decide whether it is cheap enough to give to a whole team.

Your team keeps pasting PostgreSQL errors into chat and asking "what does this mean?". You want a command that answers in a consistent format, costs almost nothing, and keeps a log so you can see how often it is used.

Use what you learned in Builds 02 to 04. You may copy from `first_call.py`, `cost.py` and `chat.py`. Work in `~/agentic-ai` on **ai-lab** as **ec2-user**.

---

## Task 1 - Build the explainer

Create `explain_error.py` so that this works:

`python explain_error.py 'FATAL:  sorry, too many clients already'`

Requirements:
- The error message comes from the command line (`sys.argv[1]`).
- A **system prompt** makes every answer follow the same shape: what the error means, the most likely cause, and one safe first check. Three short lines, no more.
- It prints the answer and the cost of the call.
- It appends one line to `logs/calls.jsonl` with `"script": "explain_error.py"`, the token counts, `stop_reason` and `cost_usd`.

---

## Task 2 - Try it on three real errors

Run it on these three errors (copy them exactly):

- `FATAL:  sorry, too many clients already`
- `ERROR:  deadlock detected`
- `FATAL:  password authentication failed for user "report_user"`

Is the shape of every answer the same? If not, what in your system prompt would you change, and why?

---

## Task 3 - Protect the answer from being cut off

Run one error with `max_tokens` set very low. What does your program print, and how would someone using it know the answer is incomplete? Change the program so that when `stop_reason` is `max_tokens` it prints a clear warning instead of a half sentence.

---

## Task 4 - Price it for your team

Using your log, work out the average cost per explanation. Your team runs it about 40 times a day. What does a month cost? Compare that to your $5 cap. Show the numbers you used and where they came from (your log lines, not a guess).

---

## Summary: proof to send SutaAI

- The last three `explain_error.py` lines of `logs/calls.jsonl` (use `grep explain_error.py logs/calls.jsonl | tail -3`)
- Your monthly cost calculation
- Your answer to the Task 2 question

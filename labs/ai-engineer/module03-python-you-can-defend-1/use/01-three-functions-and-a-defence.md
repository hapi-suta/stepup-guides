# Three Functions and a Defence

## Objective

Give your agent the tools you wrote in this module, then take the 50-line `agent.py` from Module 02 apart into three functions you can test without calling a model. Finish by defending the result the way you would in an interview.

No commands are given. You know how to edit a file, run a test and read a log. Work in `~/agentic-ai` on **ai-lab** as **ec2-user**. Tasks 1 and 3 make a few real LLM calls on your key; Tasks 2 and 4 make none.

---

## Task 1 - Make your functions into tools

Add two tools to `tools.py`, next to `disk_usage` and `tail_log`:

- `severity_summary`, which takes no inputs
- `top_errors`, which takes one input, `n`, and reports on the server log

Your `top_errors` in `logparse.py` takes a list of records, but a model cannot send a list of records. Decide what the tool function in `tools.py` should take and return, and write that small function. Remember that a tool result goes back to the model as text.

Write each description for a model that has never seen your code. Then answer: the model sends `n` as the text `"3"` instead of the number `3`. What does your tool do? What should it do? Make it so, and prove it with a test.

---

## Task 2 - Three functions out of agent.py

Reshape `agent.py` so that these three jobs are functions, and the loop calls them:

- `run_tool(name, tool_input)`: runs one tool and returns the output text and whether it failed
- `log_tool_call(turn, name, tool_input, is_error)`: writes one line to `logs/tool_calls.jsonl`
- `run_cost(tokens_in, tokens_out)`: returns the cost in dollars

Then write tests for `run_tool` and `run_cost` in `tests/test_agent.py`. They must pass without an LLM key and without the network.

You will hit a problem as soon as your test file says `from agent import run_cost`. Work out what happens, why, and how Python programs are normally written to avoid it. Fix it in `agent.py`.

For each of the three functions, write one sentence: why is this the right place to cut? Then name one piece of `agent.py` you chose **not** to turn into a function, and why.

---

## Task 3 - Prove the agent still works

Ask the reshaped agent: `What went wrong most often last night? Give me the numbers.`

Show from `logs/tool_calls.jsonl` which tools it called. Did it choose `top_errors`, `severity_summary`, `tail_log`, or more than one? Explain the choice from your tool descriptions.

Compare the `runs.jsonl` line for this run with an earlier run that only had `tail_log`. Did the cost change? Is the answer better?

---

## Task 4 - The defence

Do this aloud, without looking at your code first. Record yourself or do it with your tutor.

1. **Explain.** In two minutes, describe what happens from the moment the model asks for `top_errors` to the moment it reads the result. Name every function involved.
2. **Predict.** `run_tool("tail_log", {"lines": "abc"})`. What exactly is returned? Now run it and compare.
3. **Find the bug.** In Build 03 you saw that a missing log file reaches the model as `FileNotFoundError(2, 'No such file or directory')`. What useful fact is missing from that text? Where would you fix it: in the tool, or in `run_tool`? Defend your choice.
4. **Change it.** A teammate asks for `top_errors` to ignore failed-login messages. Describe the change, the test you would write first, and one risk.

Your tutor scores each part 0 to 4; you do not score yourself: 0 could not start, 1 recognised the idea, 2 explained it, 3 explained it and could change the code, 4 could rebuild it from a blank file and argue for the design. This module is complete when all four are at 3 or above.

---

## Summary: proof to send SutaAI

- The output of `python -m pytest -q` showing your new tests passing
- The `tool_calls.jsonl` lines for the Task 3 run, and the two `runs.jsonl` lines you compared
- Your three "why cut here" sentences and the one thing you left alone
- The recording of your defence, for scoring, and what you will repeat tomorrow

# Give Your Agent a Third Tool

## Objective

Add a third read-only tool to your agent, `count_by_severity`, that counts the log lines at each severity level. Then prove from your own logs that the agent chose it, and decide whether the extra tool made the agent better or just more expensive.

On-call DBAs keep asking the agent "how bad was last night?". Reading 50 raw log lines every time is slow and costs tokens. A tool that returns a short summary (how many `FATAL`, `ERROR`, `WARNING` and `LOG` lines) would let the agent answer from a few numbers.

Work in `~/agentic-ai` on **ai-lab** as **ec2-user**. Change only `tools.py`. `agent.py` should need no change at all; if you find yourself editing it, ask yourself why.

---

## Task 1 - Write the tool

Add a function `count_by_severity()` to `tools.py` that reads `data/postgresql.log` and returns the count of lines for each severity. It takes no inputs. It must be read-only.

---

## Task 2 - Describe it to the model

Add its definition to `TOOLS` and its function to `RUN`. Write the description for a model that has never seen your code. What would make it choose this tool instead of `tail_log` for a "how bad was it?" question?

Prove your function works by itself before any AI uses it (the same habit as Build 01, Step 5).

---

## Task 3 - Prove the agent chose it

Ask the agent: `How bad was last night for the database? Give me the numbers.`

Show from `logs/tool_calls.jsonl` which tools it called in that run. Did it call your new tool? Did it also call `tail_log`? Explain why you think it made those choices.

---

## Task 4 - Better or just more expensive?

Compare the `runs.jsonl` line for this question with an earlier run that only had two tools. Did the number of turns or the cost change? Is the answer more useful? Would you keep the tool in a production agent? Give one reason for and one against.

---

## Summary: proof to send SutaAI

- The output of your Task 2 self-test
- The `tool_calls.jsonl` lines for the Task 3 run
- The two `runs.jsonl` lines you compared in Task 4, and your conclusion

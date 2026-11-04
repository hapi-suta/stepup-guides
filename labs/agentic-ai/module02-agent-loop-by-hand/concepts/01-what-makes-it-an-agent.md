# What Makes It an Agent

Read this before Build 01 of this module. No code. It explains the one idea the whole course rests on: an agent is an LLM call inside a loop, plus tools your code runs for it.

---

## 1. The model cannot do anything by itself

In Module 1 the model only wrote text. It cannot read your disk, open a log file or query a database. If you ask "how full is my disk?", the best it can do is guess or tell you how to check.

**Tools** fix that. A tool is a normal function in your program (Python code you wrote) plus a short description the model can read. When the model decides it needs information, it does not run anything. It sends back a **request**: "please run `disk_usage` with `path` = `/`". Your code decides whether to run it, runs it, and sends the result back.

DBA comparison: the model is a consultant on the phone. It cannot touch your server. It can say "run `df -h` and read me the output", and you decide whether to do it. Your code is the person with their hands on the keyboard.

---

## 2. The tool-use round trip

| Step | Who | What happens |
|---|---|---|
| 1 | Your code | Sends the question **and** the list of tools (name, description, what inputs each takes) |
| 2 | Model | Replies with `stop_reason: tool_use` and a `tool_use` block: tool name, inputs, and an `id` |
| 3 | Your code | Runs that function with those inputs |
| 4 | Your code | Sends the result back as a `tool_result` block carrying the **same `id`** |
| 5 | Model | Either asks for another tool (back to step 2) or answers with `stop_reason: end_turn` |

The `id` matters. It is how the model matches a result to its request, like a transaction ID matching a commit to its begin. Send a result with the wrong `id` and the API rejects the whole request.

---

## 3. The loop

Steps 2 to 5 repeat until the model stops asking for tools. That repetition is the **agent loop**:

1. Call the model with the conversation and the tools.
2. If `stop_reason` is not `tool_use`: the model is done. Print the answer. Stop.
3. Otherwise run every tool it asked for and add the results to the conversation.
4. Go back to 1.

In Build 03 you write this loop in about 50 lines of plain Python, with no framework. Frameworks like LangGraph (Module 5) are this same loop with more features. Once you have written it by hand, no framework is magic.

---

## 4. Guardrails every loop needs

An agent decides its own next step, so your code must set the limits it cannot cross.

| Guardrail | Why | DBA comparison |
|---|---|---|
| **Maximum turns** | A confused model can ask for tools forever, and every turn costs money | `statement_timeout` |
| **Read-only tools** | The model chooses the inputs. Never give it a tool that can delete or change data until you have approval steps (Module 5) | A read-only role for reporting users |
| **Capped tool output** | A tool that returns a 2 GB log would blow up the cost of every later turn | `LIMIT` on a query |
| **Errors go back to the model** | If a tool fails, tell the model (`is_error`) so it can try something else, instead of crashing the program | Catching an exception in a job and logging it |
| **A log of every tool call** | You must be able to prove what the agent did | `log_statement = 'all'` or pgaudit |

---

## 5. Why the answer can still be wrong

Tools give the model real data, but the model still writes the conclusion. It can misread a log line or overstate a cause. Two habits protect you:

- Make the model **show what it checked** (which tools, what they returned). Your tool-call log does this.
- Judge the agent by its **evidence**, not its confidence. A calm, well-written answer built on the wrong log line is still wrong.

This is also why SutaAI checks your work from your log files, not from the words your agent wrote.

---

## 6. Words you will meet

| Term | Meaning |
|---|---|
| **Tool definition** | Name + description + `input_schema` (a JSON description of the inputs). The model only sees this, never your Python code |
| **`tool_use` block** | The model's request to run a tool |
| **`tool_result` block** | Your answer to that request, with the matching `tool_use_id` |
| **Parallel tool calls** | The model can ask for several tools in one turn. Run them all and send all results back in one message |
| **Turn** | One call to the model inside the loop |
| **Agent** | An LLM that decides which tools to call, in a loop, until the task is done |

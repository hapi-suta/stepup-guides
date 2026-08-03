# Concepts 8.2: Agent Components

**Tier 8 - AI agents, tools and MCP.** Teaching reference. In Concepts 8.1 we said an agent is a model in a loop calling tools. Now we open the hood. An agent is not one thing - it is a set of parts that fit together. Knowing the parts by name lets you reason about *where* an agent goes wrong and *what* to fix, instead of throwing more prompt at it and hoping.

**Who this is for:** DBAs moving into AI consulting. Think of an agent like a small service you operate: it has inputs, state, a control loop, side effects, and logging. Every one of those has a database equivalent you already understand.

---

## 1. The parts, one at a time

Here is every component, with a plain definition and why it matters. The BUILD project has all of these; when you read `agent.py` you will recognize them.

**Goal.** What the agent is trying to achieve, in one sentence. "Check database health and write an incident report." A fuzzy goal produces a fuzzy agent. Pin it down.

**Instructions (the system prompt).** The standing rules the model follows on every step: its role, what it may and may not do, how to behave. This is where you write "you are read-only" and "never invent metrics". Instructions are advice to the model - important, but *not* a security boundary (that lives in the harness).

**Planning.** How the agent decides its next step. Modern models plan implicitly: given the goal, the tools, and what they have seen so far, they choose the next tool call. You do not usually write a planner; you give a good goal and good tool descriptions and let the model plan.

**Tools.** The functions the agent can call to affect the world or gather information. Each tool has a name, a description, and a typed input schema. Tools are the agent's hands. Covered in depth in Concepts 8.3.

**Memory.** What the agent remembers. There are two kinds. *Short-term* memory is the running transcript of this task - every tool call and result, re-sent to the model each step (the model itself is stateless; your loop provides the memory). *Long-term* memory is anything persisted across separate runs (a file, a database). The BUILD agent uses short-term memory only.

**State.** The current situation the agent is reasoning over - the transcript so far, plus counters like "tool calls used" and "budget remaining". State is what changes as the loop runs. Keep it explicit; a mutable blob you cannot inspect is a debugging nightmare.

**Execution loop.** The heart. One iteration: send the state to the model, get back either a final answer or a tool call, execute the tool if asked, append the result to the state, repeat. The loop is where you enforce every limit and every gate.

**Observation.** The result of a tool call, fed back into the state so the model can react to it. "The CPU is at 95%." Without observation an agent is blind - it acts but never learns whether the action worked.

**Error handling.** What happens when a tool fails. A robust agent catches the error, returns it to the model *as a tool result marked as an error*, and lets the model try another approach - it does not crash. Covered in Concepts 8.3 and drilled in SURVIVE.

**Termination conditions.** The rules that stop the loop. There are always at least three: (1) the model says it is done, (2) a hard limit is hit (max tool calls, max budget), (3) an error the agent cannot recover from. An agent with no termination condition can loop forever, burning money. This is not optional.

**Human approval.** A gate that pauses the loop and waits for a person before taking a consequential action. The model *requests* the action; a human *authorizes* it. Covered in Concepts 8.5 and central to BUILD.

**Audit trail.** A durable log of every tool call the agent made, with inputs, results, and timestamps. When a client asks "what did the agent actually do?", the audit trail is your answer. No audit trail, no accountability, no trust.

---

## 2. How the loop actually runs, step by step

Here is one full pass of the execution loop, so the parts click together. This is exactly the shape of the BUILD agent's `run()`:

1. **Check limits.** Have we hit the max number of tool calls? Is the budget spent? If yes, stop now (termination).
2. **Send state to the model.** The system prompt (instructions) + the transcript so far (state/short-term memory) + the tool definitions.
3. **Read the model's response.** It is one of two things:
   - a **final answer** -> record it, stop the loop (termination: model done);
   - a **tool call** -> the model is asking to run a function with some arguments.
4. **Gate the tool call.** Is this tool read-only, or does it need human approval? If it needs approval, pause and ask a human (human approval). If denied, feed "denied" back as the observation.
5. **Execute the tool** (if allowed). Wrap it in error handling. Whatever comes back - success or a caught error - becomes the observation.
6. **Record it** in the audit trail (name, input, result, timestamp).
7. **Append the observation** to the state (memory) and go back to step 1.

Every safety property in this tier is a rule inside this loop. Least privilege is step 4. Limits are step 1. Audit is step 6. If you understand this loop, you understand agents.

---

## 3. Where agents go wrong, mapped to the parts

When an agent misbehaves, name the part:

- It never finishes / loops forever -> **termination conditions** are missing or too loose.
- It did something it should not have -> **tools** are too powerful, or the **human approval** gate is missing.
- It hallucinated a fact instead of checking -> weak **instructions**, or no **tool** for the real data.
- It crashed on a flaky API -> no **error handling**.
- You cannot tell what it did -> no **audit trail**.
- It "forgot" what it already found -> **memory/state** not fed back correctly.

This mapping is the whole value of learning the parts. A vague "the agent is broken" becomes a specific, fixable component.

---

## 4. The consultant framing

When you scope an agent for a client, you are really scoping these components. "What is the goal? What tools does it need, and which are dangerous? When does it stop? Where is the human gate? How do we audit it?" A client who hears you ask those questions knows they are talking to someone who has built one before. A vendor who only says "our AI figures it out" has not.

---

## Key terms recap

- **Goal, instructions, planning, tools, memory, state** - what the agent knows and can do.
- **Execution loop** - think, act, observe, repeat; every safety rule lives inside it.
- **Observation, error handling** - how the agent perceives results and survives failures.
- **Termination conditions** - the always-present rules that stop the loop; never optional.
- **Human approval, audit trail** - the gate before consequential actions and the durable record of everything done.

---

## References

- Anthropic, "Building effective agents" (agent loop, tools, planning) - https://www.anthropic.com/engineering/building-effective-agents
- Anthropic tool use overview (the request/execute/observe loop) - https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview

Prof. Happy (SUTA Labs)

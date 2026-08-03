# Concepts 8.1: Agent Foundations

**Tier 8 - AI agents, tools and MCP.** This is a teaching reference, not a lab. Read it, keep the ideas in your head, and come back when a BUILD or USE step uses a term you want to double-check. You do not need to memorize anything. You need a clear mental model of what an "agent" actually is, so that when a client says "build me an AI agent" you can tell them what they are really asking for, and what it will and will not do.

**Who this is for:** you are a DBA moving into AI consulting. You already reason about systems, control flow, and failure modes. An agent is a familiar shape dressed in new clothes: it is a loop that calls functions, where a language model decides which function to call next. Nothing here is magic.

---

## 1. The word "agent" is overloaded - here is the ladder

Clients use "agent" to mean everything from a chatbot to a self-driving robot. Before you can build one you have to know which rung of the ladder they mean. From simplest to most capable:

**Chatbot.** Text in, text out. One turn. It answers from what the model already knows. No tools, no memory beyond the conversation you re-send. This is a single model call.

**Workflow.** A fixed sequence of steps that you, the developer, wrote in code. The model might do one step (summarize this, classify that), but *you* decide the order. The control flow is in your code, not the model's head. Predictable, testable, cheap. Most "AI features" clients want are actually workflows.

**Tool-using assistant.** A model that can call functions you gave it - look up a value, query a database, do exact arithmetic - and then use the result to finish its answer. Still usually one round of "call tool, read result, answer". The model chooses *whether* to use a tool, but the overall shape is short.

**Agent.** A model in a **loop**, calling tools repeatedly, deciding each step for itself, until it judges the task done. This is the real dividing line, and it is exactly how Anthropic frames it: workflows are systems where LLMs and tools are orchestrated through predefined code paths, whereas agents are systems where the model dynamically directs its own process and tool use (see: https://www.anthropic.com/engineering/building-effective-agents). In a workflow *you* control the loop; in an agent the *model* controls the loop. That autonomy is the power and the danger.

**Multi-agent system.** Several agents that talk to each other - a coordinator that hands sub-tasks to specialist agents. More capable for big tasks, much harder to debug and control. Reach for it only when a single agent genuinely cannot hold the whole job.

**Autonomous system.** An agent left running with no human in the loop, acting on the world on its own schedule. Rare, and reserved for tasks where every action is cheap to reverse. For anything consequential, you keep a human gate (Concepts 8.5).

The consultant takeaway: **start at the lowest rung that solves the problem.** Agents cost more, are slower, and are harder to make safe. Do not sell an autonomous system when a workflow would do.

---

## 2. Chatbot versus agent - the real difference

This is the single most-asked interview question in this tier, so get it crisp.

A **chatbot** answers. You ask, it replies, done. There is one model call and the conversation ends there (or waits for your next message).

An **agent** acts. It is given a goal, and it runs a loop: think, choose an action, take the action, observe the result, think again - repeated until the goal is met. It can call tools, read their output, and change course based on what it finds.

The difference is not "smarter model". It is **control flow**. A chatbot does one thing. An agent decides its own sequence of things. That is why an agent can book a flight, investigate a bug, or run a database health check, and a chatbot can only talk about doing those things.

Because the agent controls the loop, two questions immediately follow, and they define the rest of this tier:
- **When does it stop?** (termination conditions - Concepts 8.2)
- **What is it allowed to do?** (least privilege, human approval, limits - Concepts 8.5)

An agent without good answers to those two questions is not a product. It is a liability.

---

## 3. When you should - and should not - build an agent

Before choosing the agent rung, check all four of these. If the answer to any is "no", drop to a workflow or a single call. (These four match the industry checklist for "should I build an agent?" - see Anthropic's guidance at https://platform.claude.com/docs/en/agents-and-tools/agent-sdk/overview and https://www.anthropic.com/engineering/building-effective-agents.)

- **Complexity.** Is the task multi-step and hard to fully specify in advance? "Turn this incident into a written report" is agent-shaped. "Extract the title from this PDF" is not - that is one call.
- **Value.** Does the outcome justify the higher cost and latency? Agents make many model calls; each one costs tokens and time.
- **Viability.** Is the model actually good at this task? If it fails the task once in a single call, a loop will just fail more expensively.
- **Cost of error.** Can mistakes be caught and undone? An agent that files a report you review is fine. An agent that wires money is not, unless every step is gated.

The honest consultant often talks a client *down* the ladder. That is a feature, not a failure.

---

## 4. Why agents are worth the trouble

When the four checks pass, agents earn their cost. A single model call has to solve the whole task in one shot. An agent gets to **look before it leaps**: it can query the database, see the actual state, and decide the next step based on reality instead of guessing. It can recover from a tool error and try another approach. It can break a fuzzy goal ("figure out why the database is slow") into concrete steps it discovers as it goes.

That is exactly the kind of work a junior operator does: not a fixed script, but a goal plus judgment plus the ability to check results and adjust. An agent is that pattern, automated - with all the supervision that a junior operator also needs.

---

## 5. What you will build in this tier

The BUILD project is a **read-only database operations agent**. It is given a goal like "check the health of the database and write an incident report". It has tools: get database health metrics, review approved monitoring metrics, search runbooks, and (gated) recommend an operational action. It runs a loop, calls tools, reads results, and produces a report - and it **never runs a destructive command**, **requires human approval before any operational action**, and **records every tool call**.

Everything runs on a **local mock** so you can build, run, and break it without a paid API key. The mock is a stand-in language model that plays the same tool-calling protocol a real model uses. A few clearly marked steps show how to swap in a real model (Claude, via the `anthropic` SDK) with your own key. The safety machinery - approvals, limits, audit - is identical whether the brain is the mock or a real model. That is the point: **safety lives in your harness, not in the model.**

---

## Key terms recap

- **Chatbot / workflow / tool-using assistant / agent / multi-agent / autonomous** - the capability ladder; build the lowest rung that works.
- **Control flow** - who decides the sequence of steps. Workflow: you. Agent: the model. This is the real chatbot-versus-agent line.
- **Loop** - the agent's defining structure: think, act, observe, repeat, until done.
- **Harness** - your code around the model: the loop, the tools, the approvals, the limits, the audit log. Safety lives here.

---

## References

- Anthropic, "Building effective agents" (workflow vs agent; when to build an agent) - https://www.anthropic.com/engineering/building-effective-agents
- Anthropic Agent SDK / tool use overview - https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Anthropic Python SDK (`anthropic`) - https://github.com/anthropics/anthropic-sdk-python

Prof. Happy (SUTA Labs)

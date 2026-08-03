# Concepts 8.3: Tool Calling

**Tier 8 - AI agents, tools and MCP.** Teaching reference. Tools are how an agent moves from "talks about doing work" to "does work". This chapter is the mechanics: how a tool is defined, how the model asks to call one, how you validate and gate it, and how you handle the failures that will absolutely happen. As a DBA you already have strong instincts here - a tool call is a lot like a stored procedure invocation, with the same need for validated parameters, permissions, transactions, and rollback.

**Who this is for:** DBAs moving into AI consulting. Everything below has a database analogy. Lean on them.

---

## 1. What a tool is

A tool is a function your code exposes to the model. It has three parts:

- a **name** (`get_db_health`),
- a **description** in plain language telling the model *when* to use it,
- an **input schema** - a typed contract for the arguments, exactly like a function signature or a stored-procedure parameter list.

Here is a tool schema, the shape both the mock and a real model expect:

```json
{
  "name": "get_db_health",
  "description": "Return current database health metrics (CPU, connections, replication lag). Read-only. Call this when you need the live state of the database.",
  "input_schema": {
    "type": "object",
    "properties": {
      "instance": {"type": "string", "description": "Which database instance to check"}
    },
    "required": ["instance"]
  }
}
```

Write the description like documentation for a colleague: say *when* to call it, not just what it does. A well-described tool is called correctly; a vaguely described one is called at the wrong time with the wrong arguments.

---

## 2. The tool-calling protocol

The flow is a hand-off, and the boundary is the whole point:

1. You send the model the goal, the transcript, and the list of tool schemas.
2. The model, instead of answering, replies "call `get_db_health` with `{"instance": "pg-prod-1"}`". This is a **request**, not an execution.
3. **Your code** decides whether to run it, then runs it, and captures the result.
4. You send the result back to the model as an **observation**.
5. The model uses the result to continue.

The critical fact for a client: **the model never runs your code.** It only asks. Your harness executes - or refuses. That gap is where every security control lives. A vendor who says "the AI runs the query" has either mis-spoken or mis-built; the AI *requests* the query and your code runs it under your rules. (This is confirmed by the model providers themselves - Anthropic's tool-use docs describe the model returning a `tool_use` request and your code returning a `tool_result`; see: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview.)

One nuance for accuracy: this "your code executes" rule is about **client-side tools** - the tools you define and run, which is all of the BUILD agent's tools. Some providers also offer **server-side tools** (for example web search or code execution) that run on the *provider's* infrastructure, not yours. Those are a different category with their own controls; for everything you build in this tier, the request/execute boundary above is the model.

---

## 3. Parameter validation

The model produces the arguments, and the model can be wrong - a mistyped field, an out-of-range number, an instance name that does not exist. Never trust tool arguments blindly. This is the same discipline as never trusting user input in SQL.

Two layers:
- **Schema validation.** The input schema (types, required fields) catches shape errors. Some model APIs can enforce it for you - Anthropic, for example, offers "strict" tool use (`strict: true` on the tool definition) that guarantees the model's arguments conform to your schema via constrained decoding (see: https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use). The mock enforces it in the harness.
- **Business validation.** *Inside the tool*, check that the value makes sense: the instance is one you manage, the number is in range, the string is on your allowlist. Reject with a clear error otherwise.

Parameterize, never string-concatenate. A tool that builds SQL by pasting the model's argument into a query string is an injection hole - the exact bug you already guard against with bind parameters.

---

## 4. Allowlisting and authorization

**Allowlisting.** The agent gets only the tools it needs, and each tool accepts only the values it should. The BUILD agent has no `run_sql` tool at all - it physically cannot run arbitrary SQL, because that tool does not exist in its toolset. The most reliable way to stop an agent doing X is to not give it a tool that does X.

**Authorization.** Who is the agent acting as, and what is that identity allowed to do? A read-only agent should run under a read-only database role, so that even a bug cannot write. Defense in depth: the harness refuses write tools *and* the underlying credential cannot write. Never rely on the prompt alone - "you are read-only" is instruction, not enforcement.

---

## 5. Read-only versus write actions

Split every tool into two buckets and treat them completely differently:

- **Read-only tools** gather information and change nothing: get metrics, search runbooks, read a config. Safe to run automatically. Safe to run in parallel. Cheap to get wrong - the worst case is a wasted call.
- **Write / action tools** change the world: restart a service, scale a cluster, delete a row, send an email. These are gated. In the BUILD agent, the one action tool (`recommend_action`) does **not** execute anything - it records a recommendation that a human must approve. That is the pattern: the agent proposes, a human disposes.

If you remember one rule from this chapter: **read-only runs; write waits for a human.**

---

## 6. Idempotency, transaction boundaries, and rollback

These three are your database instincts applied to tools:

**Idempotency.** An idempotent action produces the same result if run twice. "Set replicas to 3" is idempotent; "add one replica" is not. Design action tools to be idempotent where you can, because an agent (or a retry) may call the same tool twice - a flaky network can make you unsure whether the first call landed.

**Transaction boundaries.** If an action has several parts that must all succeed or all fail, wrap them in a transaction, exactly as you would in the database. An agent that half-completes a multi-step change leaves the system in a state no one designed. Keep each tool a single, complete unit of work.

**Rollback.** For any consequential action, know how to undo it *before* you run it. Prefer reversible actions. When something is irreversible (dropping data, sending money), it gets the strictest gate and, ideally, a dry-run first. SURVIVE drills the case where an agent reaches for an irreversible action without approval.

---

## 7. Timeouts and tool-error recovery

Tools call real systems, and real systems hang and fail. Two must-haves:

**Timeout handling.** Every tool call gets a deadline. If a tool does not return in time, you stop waiting and treat it as a failure - you do not let one wedged call freeze the whole agent. (In the BUILD harness this is a wrapper around each tool.)

**Tool-error recovery.** When a tool fails - timeout, exception, bad result - you do **not** crash the agent. You catch the error and return it to the model as a tool result *marked as an error*. This `is_error: true` field on a tool result is a real part of the protocol (Anthropic's `tool_result` blocks accept `is_error: true`; see: https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview). The model then sees "that call failed, here is why" and can try a different tool, adjust arguments, or report that it could not complete the step. This keeps the agent robust: one flaky call becomes a recoverable observation, not a crash. This is the exact scenario in SURVIVE's `tool-timeout-recovery`.

A crashed agent that corrupts its own state is worse than an agent that reports "I could not reach the database". Recover gracefully, always.

---

## Key terms recap

- **Tool = name + description + input schema.** Describe *when* to call it.
- **The model requests, your code executes.** That boundary is where security lives.
- **Validate parameters** - schema plus business rules; parameterize, never concatenate.
- **Allowlist tools and authorize the identity.** Don't give a read-only agent a write tool.
- **Read-only runs; write waits for a human.**
- **Idempotency, transactions, rollback, timeouts, error-as-observation** - your DBA instincts, applied to tools.

---

## References

- Anthropic tool use overview (tool_use request / tool_result response; is_error) - https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Anthropic strict tool use (schema-conformant arguments) - https://platform.claude.com/docs/en/agents-and-tools/tool-use/strict-tool-use
- Anthropic "Building effective agents" (agent vs workflow, tool design) - https://www.anthropic.com/engineering/building-effective-agents

Prof. Happy (SUTA Labs)

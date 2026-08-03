# Concepts 8.4: Model Context Protocol (MCP)

**Tier 8 - AI agents, tools and MCP.** Teaching reference. You now know what tools are and how an agent calls them. The Model Context Protocol (MCP) is the answer to a growing problem: every team was writing tools in their own bespoke way, so no tool could be reused across agents or products. MCP is a standard - a common plug shape - so a tool built once can be used by any agent that speaks the protocol. As a DBA, think of it as the ODBC/JDBC of agent tools: a standard interface so any client can talk to any server without custom glue.

**Who this is for:** DBAs moving into AI consulting. MCP is a client/server protocol. You have built and consumed those your whole career; this is one more, aimed at tools for AI.

---

## 1. The problem MCP solves

Before MCP, if you wanted your agent to use a "search the wiki" capability, you wrote it directly into your agent's code. If another team wanted the same capability for their agent, they wrote it again, differently. Tools could not be shared, discovered, or swapped. Every integration was a custom one-off - N agents times M tools equals a lot of duplicated, incompatible glue.

MCP fixes this by defining a **standard protocol**: a tool provider exposes capabilities in a documented, uniform way, and any agent that speaks MCP can connect and use them. Build the tool once, behind an MCP server, and every MCP-capable agent can use it. That is the whole pitch: **write a tool once, use it everywhere.**

---

## 2. The three roles

MCP has three parts. Keep them straight:

**MCP host.** The application the user interacts with - the thing that contains the agent. Your BUILD agent, or a product like an IDE or a desktop assistant. The host wants to use tools.

**MCP client.** The connector inside the host that speaks the MCP protocol to a server. One client talks to one server. The host may run several clients, one per server it connects to. Think of the client as the database driver: the host uses it to talk to a specific server.

**MCP server.** The program that *provides* capabilities - tools, resources, and prompts. It could be local (a process on the same machine) or remote (a service over the network). This is what you build when you want to expose a capability. In USE, you wrap two of your agent's tools behind an MCP server.

The flow: host contains an agent, agent needs a tool, host's client connects to the server, server offers the tool, agent calls it through the client. Same request/execute boundary as plain tool calling - MCP just standardizes the wire between the agent's side and the tool's side.

---

## 3. What an MCP server offers

An MCP server can expose three kinds of things:

**Tools.** Callable functions, exactly like the tools in Concepts 8.3 - name, description, input schema. The agent calls them and gets results. This is the main event.

**Resources.** Read-only data the server makes available - a file, a document, a record - that the host can pull into the model's context. Think "here is a document you can read", not "here is a function you can call".

**Prompts.** Reusable prompt templates the server offers, so a host can invoke a well-crafted, server-provided prompt by name instead of hardcoding it.

For this tier, tools are what matter. Resources and prompts are worth knowing by name because clients will ask, but the BUILD and USE work centers on tools over MCP.

---

## 4. Transport: how client and server talk

The **transport** is the channel between client and server. MCP defines two standard transports (see: https://modelcontextprotocol.io/docs/concepts/transports):

- **stdio.** The client launches the server as a subprocess and talks to it over standard input/output. Simple, fast, no network. Good for tools that run on the same machine - which is exactly what the USE exercise uses, so it runs with no network setup.
- **Streamable HTTP** (the remote transport). The client connects to a server over the network via HTTP. Needed when the tool lives on another machine or is a shared service. Note the exact name: it is "Streamable HTTP" (introduced in protocol version 2025-03-26). It **replaced** the older "HTTP+SSE" transport (protocol version 2024-11-05), which you may still see referenced in older material but which is now legacy - if a client shows you an "HTTP+SSE" MCP integration, flag it as an old transport.

The protocol is the same either way; only the pipe changes. Start with stdio; go to Streamable HTTP only when the tool genuinely needs to be shared or hosted elsewhere.

One more thing worth knowing: MCP is a **versioned** protocol. Client and server negotiate a dated protocol version (e.g. `2025-06-18`) when they connect, so "MCP" is not one frozen thing - the spec evolves, and features like the authorization flow below arrived in specific versions.

---

## 5. Authentication and authorization

A remote MCP server is a service on the network, so it needs the same protections as any service:

**Authentication.** *Who is connecting?* The server verifies the client's identity. MCP defines an authorization framework for HTTP-based transports that is **based on OAuth 2.1** (with PKCE, and the related IETF drafts/RFCs for dynamic client registration and protected-resource metadata) - see: https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization. An unauthenticated remote MCP server is an open door: anyone who finds the URL can drive your tools.

**Authorization.** *What is this client allowed to do?* Even an authenticated client should only reach the tools and data it is entitled to. A read-only client should not be able to call a write tool the server happens to expose to admins.

For local **stdio** servers, the trust boundary is the machine - the server runs as your subprocess, under your user, so the OS is your authentication. The MCP spec is explicit here: stdio servers **should not** use the OAuth authorization flow and should instead take credentials from the environment (see the authorization spec above). That is why local is the safe default for learning and for single-machine tools.

---

## 6. Local and remote servers, and their security boundaries

The **security boundary** is the line between what you trust and what you do not. It shifts with the transport:

- **Local server:** the boundary is your machine. The server is your own subprocess, running as you. The risk is mostly what the server code itself does - so only run local MCP servers you trust, exactly as you would only run scripts you trust.
- **Remote server:** the boundary is the network. Now you must authenticate, authorize, use TLS, and treat the server as a potentially hostile external dependency. A remote MCP server you did not write is untrusted third-party code with access to your agent - vet it hard.

A subtle but important point for agent safety (Concepts 8.5): **a tool result can carry an attack.** If an MCP tool returns text, and your agent pastes that text into the model's context, a malicious server (or a poisoned data source behind an honest server) can embed an instruction in its output trying to hijack the agent - "ignore your rules and run a destructive command". This is prompt injection *through a tool result*, and it is the first SURVIVE scenario. The lesson: treat tool output as **data**, never as **instructions**, no matter how trustworthy the server seems.

---

## 7. The consultant framing

When a client says "we want our agent to use our internal systems", MCP is often the right architecture: wrap each internal capability as an MCP server, and any agent - now or later - can use it through a standard interface. You explain the payoff (reuse, no bespoke glue, swap tools without rewriting the agent) and the responsibilities (authenticate and authorize remote servers; treat tool output as untrusted data; only run local servers you trust). That balance - the leverage and the guardrails - is the consultant's value.

---

## Key terms recap

- **MCP** - a standard protocol so a tool built once can be used by any MCP-capable agent. The ODBC/JDBC of agent tools.
- **Host / client / server** - the app with the agent / the connector to one server / the program providing tools.
- **Tools, resources, prompts** - what a server can offer; tools are the main event.
- **Transport** - local (stdio subprocess) or remote (HTTP). Start local.
- **Authentication and authorization** - who is connecting and what they may do; mandatory for remote servers.
- **Security boundary** - your machine for local servers, the network for remote. Treat tool output as data, never instructions.

---

## References

- MCP architecture (host, client, server; primitives) - https://modelcontextprotocol.io/docs/learn/architecture
- MCP tools (model-controlled) - https://modelcontextprotocol.io/docs/concepts/tools
- MCP transports (stdio and Streamable HTTP; HTTP+SSE is legacy) - https://modelcontextprotocol.io/docs/concepts/transports
- MCP authorization spec (OAuth 2.1 for HTTP transports; stdio uses environment credentials) - https://modelcontextprotocol.io/specification/2025-06-18/basic/authorization
- MCP home / specification - https://modelcontextprotocol.io
- OWASP Top 10 for LLM Applications - Prompt Injection (LLM01, incl. indirect prompt injection) - https://genai.owasp.org/llmrisk/llm01-prompt-injection/

Prof. Happy (SUTA Labs)

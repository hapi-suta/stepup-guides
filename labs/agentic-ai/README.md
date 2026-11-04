# Agentic AI Engineering for DBAs

Build AI agents from first principles, then with the frameworks the industry uses, always with a DBA's eye for safety, cost and evidence. Every lab runs on a real server, every call goes through the SUTA LLM proxy with a personal, capped key, and every exercise is checked from side effects (files, logs, exit codes), never from the exact words an AI wrote.

**Status:** pilot. Modules 01 and 02 are built and tested. Modules 03 to 12 follow only after the pilot passes cleanly with real students.

## Environment

- One CentOS Stream 9 server per student (**ai-lab**), user **ec2-user**
- Python 3.12 in a virtual environment at `~/agentic-ai/.venv`
- Libraries pinned in `requirements.txt` (anthropic 2.4.0, openai 3.45.0)
- Model: `claude-haiku-5-5` through the SUTA LLM proxy; personal key with a $5 cap in `~/.suta-llm.env`, issued by Prof. Happy

## Modules

| Module | Topic | Status |
|---|---|---|
| 01 | [An LLM Call From Scratch](module01-llm-call-from-scratch/) - messages, tokens, cost, statelessness | Pilot |
| 02 | [The Agent Loop by Hand](module02-agent-loop-by-hand/) - tools, the round trip, a 50-line agent | Pilot |
| 03 | Structured outputs and validating AI-written SQL | Planned |
| 04 | MCP: read-only PostgreSQL DBA tools (stdio and streamable HTTP) | Planned |
| 05 | LangGraph: state, Postgres checkpointer, human approval with interrupt() | Planned |
| 06 | Agentic retrieval on pgvector | Planned |
| 07 | Multi-agent systems and an A2A introduction | Planned |
| 08 | Agent evals | Planned |
| 09 | Observability and cost | Planned |
| 10 | Safety and AI data security | Planned |
| 11 | A production agent service | Planned |
| 12 | Capstone | Planned |

## Method

Concepts (why), BUILD (guided, one command per step, real captured output), USE (assignments where you think), SURVIVE (something breaks; you find and fix it from the evidence).

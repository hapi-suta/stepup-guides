# AI Engineer

Become an engineer who builds agents and LLM features into real software and can prove with evals that they work. One project grows through the whole track: **PG On-Call Agent**, a service that investigates PostgreSQL incidents with read-only tools.

**Status:** Modules 01 to 03 are available. Module 03 is the first module written for this track.

## How this track differs from Agentic AI Engineering for DBAs

The `agentic-ai` track gives you each program as one block to paste. This track makes you write the code: you type it, you test it, and from Module 03 onward the last tutorial of every module gives you a specification and tests instead of code. The rule for this track is:

- Type code yourself with `vi`. Paste only data files and supplied test files.
- Prove every step with a command, a test or a log line, never with what an AI wrote.
- If you cannot explain a line, you are not done with it.

## Environment

The same server as `agentic-ai`: one CentOS Stream 9 server (**ai-lab**), user **ec2-user**, Python 3.12 in `~/agentic-ai/.venv`.

## Modules

| Module | Topic | Status |
|---|---|---|
| 01 | An LLM Call From Scratch (from `agentic-ai`, done without pasting) | Reused |
| 02 | The Agent Loop by Hand (from `agentic-ai`, done without pasting) | Reused |
| 03 | [Python You Can Defend I](module03-python-you-can-defend-1/) - strings, lists, dictionaries, functions, exceptions, tests | Built |
| 04 | Python You Can Defend II - types, Pydantic, structured outputs | Planned |
| 05 | Evals I - prove it before you change it | Planned |
| 06-18 | See the curriculum design | Planned |

Modules 01 and 02 are linked from `agentic-ai` (symlinks), so both tracks teach from one copy. In this track you type every program yourself instead of pasting it, then rewrite it from a blank file.

## Method

Concepts (why), BUILD (guided, one command per step, real captured output), USE (assignments where you think and defend), SURVIVE (something breaks; you find and fix it from the evidence).

Mastery is scored 0 to 4: 0 unfamiliar, 1 recognise, 2 explain, 3 apply (change and debug it with few hints), 4 defend (rebuild a related task alone and discuss the trade-offs). A module is complete at level 3.
